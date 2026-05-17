#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "esp_event.h"
#include "nvs_flash.h"
#include "esp_log.h"
#include "esp_nimble_hci.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include "sdkconfig.h"
#include "driver/gpio.h"
#include "esp_http_server.h"
#include "esp_wifi.h"
#include "esp_netif.h"
#include "esp_event.h"
#include "esp_log.h"
#include "lwip/ip4_addr.h"
#include "driver/i2c_master.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_panel_vendor.h"
#include <string.h>
#include <stdbool.h>
#include <stdio.h>

char *TAG = "BLE-Server";
uint8_t ble_addr_type;
void ble_app_advertise(void);

#define LIGHT_GPIO 14
#define BLUE_LED_GPIO 26
#define GREEN_LED_GPIO 27
#define RED_LED_GPIO 25
#define BUZZER_GPIO 33
#define SWITCH_GPIO 4
#define RELAY_ACTIVE_LEVEL 0
#define RELAY_INACTIVE_LEVEL 1
#define VOLTAGE_SENSOR_GPIO 34
#define VOLTAGE_DIVIDER_RATIO 5.0f
#define VOLTAGE_SENSOR_SAMPLES 16
#define OLED_SDA_GPIO 21
#define OLED_SCL_GPIO 22
#define OLED_H_RES 128
#define OLED_V_RES 64

static int light_state = 0;
static adc_oneshot_unit_handle_t adc1_handle;
static adc_cali_handle_t adc_cali_handle = NULL;
static bool adc_calibration_enabled = false;
static float voltage_reading_v = 0.0f;
static float current_reading_a = 0.0f;
static float power_reading_w = 0.0f;
static int adc_raw_reading = 0;
static bool voltage_valid = false;
static bool ble_connected = false;
static bool switch_active = false;
static i2c_master_bus_handle_t i2c_bus_handle = NULL;
static esp_lcd_panel_io_handle_t oled_io_handle = NULL;
static esp_lcd_panel_handle_t oled_panel_handle = NULL;
static uint8_t oled_framebuffer[OLED_H_RES * OLED_V_RES / 8];
static uint8_t oled_i2c_address = 0x3C;
char current_text[16];

static void init_voltage_sensor(void);
static void voltage_sensor_task(void *param);
static void init_oled_display(void);
static void oled_task(void *param);
static void oled_clear_buffer(void);
static void oled_draw_text(int x, int page, const char *text);
static void oled_draw_char(int x, int page, char c);
static void oled_draw_text_scaled(int x, int y, const char *text, int scale);
static const uint8_t *oled_get_glyph(char c);
static void oled_flush_buffer(void);
static void switch_task(void *param);
static void set_light_state(bool on);
static void oled_set_pixel(int x, int y, bool on);
static void oled_draw_hline(int x, int y, int length);
static void oled_draw_rect(int x, int y, int width, int height);
static void oled_fill_rect(int x, int y, int width, int height);

// Write data to ESP32 defined as server
static int device_write(uint16_t conn_handle, uint16_t attr_handle, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    char *data = (char *)ctxt->om->om_data;
    int data_len = ctxt->om->om_len;

    // Ensure null termination
    char command[32];
    memset(command, 0, sizeof(command));
    if (data_len < sizeof(command) - 1)
    {
        memcpy(command, data, data_len);
    }
    else
    {
        memcpy(command, data, sizeof(command) - 1);
    }

    printf("Received command: '%s' (length: %d)\n", command, data_len);

    if (strcmp(command, "LIGHT ON") == 0)
    {
        printf("LIGHT ON - Turning ON GPIO %d\n", LIGHT_GPIO);
        set_light_state(true);
    }
    else if (strcmp(command, "LIGHT OFF") == 0)
    {
        printf("LIGHT OFF - Turning OFF GPIO %d\n", LIGHT_GPIO);
        set_light_state(false);
    }

    return 0;
}

// Read data from ESP32 defined as server

static int device_read(uint16_t con_handle, uint16_t attr_handle, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    char status_msg[128];
    snprintf(
        status_msg,
        sizeof(status_msg),
        "GPIO_13:%d;SWITCH:%d;VOLTAGE_V:%.2f;CURRENT_A:%.2f;POWER_W:%.2f;SENSOR_OK:%d",
        light_state,
        switch_active ? 1 : 0,
        voltage_reading_v,
        current_reading_a,
        power_reading_w,
        voltage_valid ? 1 : 0
    );

    printf("ESP32: Sending status: %s\n", status_msg);

    os_mbuf_append(ctxt->om, status_msg, strlen(status_msg));
    return 0;
}

// Array of pointers to other service definitions
// UUID - Universal Unique Identifier
static const struct ble_gatt_svc_def gatt_svcs[] = {
    {.type = BLE_GATT_SVC_TYPE_PRIMARY,
     .uuid = BLE_UUID16_DECLARE(0x180), // Define UUID for device type
     .characteristics = (struct ble_gatt_chr_def[]){
         {.uuid = BLE_UUID16_DECLARE(0xFEF4), // Define UUID for reading
          .flags = BLE_GATT_CHR_F_READ,
          .access_cb = device_read},
         {.uuid = BLE_UUID16_DECLARE(0xDEAD), // Define UUID for writing
          .flags = BLE_GATT_CHR_F_WRITE,
          .access_cb = device_write},
         {0}}},
    {0}};

// BLE event handling
static int ble_gap_event(struct ble_gap_event *event, void *arg)
{
    switch (event->type)
    {
    // Advertise if connected
    case BLE_GAP_EVENT_CONNECT:
        ESP_LOGI("GAP", "BLE GAP EVENT CONNECT %s", event->connect.status == 0 ? "OK!" : "FAILED!");
        if (event->connect.status != 0)
        {
            ble_connected = false;
            ble_app_advertise();
        }
        else
        {
            ble_connected = true;
        }
        break;
    // Advertise again after completion of the event
    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI("GAP", "BLE GAP EVENT DISCONNECTED");
        ble_connected = false;
        ble_app_advertise();
        break;
    case BLE_GAP_EVENT_ADV_COMPLETE:
        ESP_LOGI("GAP", "BLE GAP EVENT");
        ble_app_advertise();
        break;
    default:
        break;
    }
    return 0;
}

// Define the BLE connection
void ble_app_advertise(void)
{
    // GAP - device name definition
    struct ble_hs_adv_fields fields;
    const char *device_name;
    memset(&fields, 0, sizeof(fields));
    device_name = ble_svc_gap_device_name(); // Read the BLE device name
    fields.name = (uint8_t *)device_name;
    fields.name_len = strlen(device_name);
    fields.name_is_complete = 1;
    ble_gap_adv_set_fields(&fields);

    // GAP - device connectivity definition
    struct ble_gap_adv_params adv_params;
    memset(&adv_params, 0, sizeof(adv_params));
    adv_params.conn_mode = BLE_GAP_CONN_MODE_UND; // connectable or non-connectable
    adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN; // discoverable or non-discoverable
    ble_gap_adv_start(ble_addr_type, NULL, BLE_HS_FOREVER, &adv_params, ble_gap_event, NULL);
}

// The application
void ble_app_on_sync(void)
{
    ble_hs_id_infer_auto(0, &ble_addr_type); // Determines the best address type automatically
    ble_app_advertise();                     // Define the BLE connection
}

// The infinite task
void host_task(void *param)
{
    nimble_port_run(); // This function will return only when nimble_port_stop() is executed
}

// Add GPIO setup function
void setup_light_gpio()
{
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << LIGHT_GPIO),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = 0,
        .pull_down_en = 0,
        .intr_type = GPIO_INTR_DISABLE};
    gpio_config(&io_conf);
    set_light_state(false); // Default OFF
}

void setup_status_leds()
{
    gpio_config_t io_conf = {
        .pin_bit_mask =
            (1ULL << BLUE_LED_GPIO) |
            (1ULL << GREEN_LED_GPIO) |
            (1ULL << RED_LED_GPIO),

        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = 0,
        .pull_down_en = 0,
        .intr_type = GPIO_INTR_DISABLE
    };

    gpio_config(&io_conf);

    gpio_set_level(BLUE_LED_GPIO, 0);
    gpio_set_level(GREEN_LED_GPIO, 0);
    gpio_set_level(RED_LED_GPIO, 0);
}

static void set_light_state(bool on)
{
    gpio_set_level(LIGHT_GPIO, on ? RELAY_ACTIVE_LEVEL : RELAY_INACTIVE_LEVEL);
    light_state = on ? 1 : 0;
}



void setup_dht_gpio()
{
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << VOLTAGE_SENSOR_GPIO),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = 0,
        .pull_down_en = 0,
        .intr_type = GPIO_INTR_DISABLE};
    gpio_config(&io_conf);
}

void setup_switch_gpio()
{
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << SWITCH_GPIO),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = 1,
        .pull_down_en = 0,
        .intr_type = GPIO_INTR_DISABLE};
    gpio_config(&io_conf);
}

static void init_voltage_sensor(void)
{
    adc_oneshot_unit_init_cfg_t unit_cfg = {
        .unit_id = ADC_UNIT_1,
        .ulp_mode = ADC_ULP_MODE_DISABLE,
    };
    ESP_ERROR_CHECK(adc_oneshot_new_unit(&unit_cfg, &adc1_handle));

    adc_oneshot_chan_cfg_t channel_cfg = {
        .bitwidth = ADC_BITWIDTH_DEFAULT,
        .atten = ADC_ATTEN_DB_12,
    };
    ESP_ERROR_CHECK(adc_oneshot_config_channel(adc1_handle, ADC_CHANNEL_6, &channel_cfg));

    adc_cali_line_fitting_config_t cali_cfg = {
        .unit_id = ADC_UNIT_1,
        .atten = ADC_ATTEN_DB_12,
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };

    if (adc_cali_create_scheme_line_fitting(&cali_cfg, &adc_cali_handle) == ESP_OK)
    {
        adc_calibration_enabled = true;
    }
    else
    {
        ESP_LOGW(TAG, "ADC calibration unavailable, falling back to raw conversion");
    }
}
static void voltage_sensor_task(void *param)
{
    while (1)
    {
        int raw_sum = 0;

        for (int i = 0; i < VOLTAGE_SENSOR_SAMPLES; i++)
        {
            int raw = 0;

            if (adc_oneshot_read(adc1_handle,
                                 ADC_CHANNEL_6,
                                 &raw) == ESP_OK)
            {
                raw_sum += raw;
            }

            vTaskDelay(pdMS_TO_TICKS(10));
        }

        adc_raw_reading = raw_sum / VOLTAGE_SENSOR_SAMPLES;

        int adc_mv = 0;

        if (adc_calibration_enabled)
        {
            if (adc_cali_raw_to_voltage(adc_cali_handle,
                                        adc_raw_reading,
                                        &adc_mv) == ESP_OK)
            {
                voltage_valid = true;

                voltage_reading_v =
                    (adc_mv / 1000.0f) *
                    VOLTAGE_DIVIDER_RATIO;
            }
            else
            {
                voltage_valid = false;
            }
        }
        else
        {
            voltage_valid = true;

            voltage_reading_v =
                ((adc_raw_reading / 4095.0f) * 3.3f) *
                VOLTAGE_DIVIDER_RATIO;
        }

        // =========================
        // CURRENT CALCULATION
        // =========================

        current_reading_a =
            voltage_reading_v * 0.4f;

        // =========================
        // POWER CALCULATION
        // =========================

        power_reading_w =
            voltage_reading_v * current_reading_a;

        // =========================
        // ALERT LOGIC
        // =========================

       if (power_reading_w > 4.0f)
        {
            // Alert LED ON
            gpio_set_level(RED_LED_GPIO, 1);

            // Beautiful double beep
            for (int i = 0; i < 2; i++)
            {
                gpio_set_level(BUZZER_GPIO, 1);
                vTaskDelay(pdMS_TO_TICKS(120));

                gpio_set_level(BUZZER_GPIO, 0);
                vTaskDelay(pdMS_TO_TICKS(120));
            }

            vTaskDelay(pdMS_TO_TICKS(400));
        }
        else
        {
            gpio_set_level(RED_LED_GPIO, 0);
            gpio_set_level(BUZZER_GPIO, 0);
        }

        if(current_reading_a > 1.2f)
        {
            gpio_set_level(BLUE_LED_GPIO, 1);
        }else
        {
            gpio_set_level(BLUE_LED_GPIO, 0);

        }

        ESP_LOGI(TAG,
                 "Voltage=%.2fV Current=%.2fA Power=%.2fW",
                 voltage_reading_v,
                 current_reading_a,
                 power_reading_w);

        vTaskDelay(pdMS_TO_TICKS(1500));
    }
}
static void switch_task(void *param)
{
    bool last_sample = false;
    bool last_reported = false;
    int stable_count = 0;

    while (1)
    {
        bool sample_active = gpio_get_level(SWITCH_GPIO) == 0;
        if (sample_active == last_sample)
        {
            if (stable_count < 3)
            {
                stable_count++;
            }
        }
        else
        {
            stable_count = 0;
        }

        if (stable_count >= 2)
        {
            switch_active = sample_active;
            if (switch_active && !last_reported)
            {
                set_light_state(!light_state);
                ESP_LOGI(TAG, "Manual switch toggled relay, new state=%d", light_state);
            }
            last_reported = switch_active;
        }

        last_sample = sample_active;
        vTaskDelay(pdMS_TO_TICKS(20));
    }
}

static void init_oled_display(void)
{
    i2c_master_bus_config_t i2c_bus_conf = {
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .sda_io_num = OLED_SDA_GPIO,
        .scl_io_num = OLED_SCL_GPIO,
        .i2c_port = -1,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    ESP_ERROR_CHECK(i2c_new_master_bus(&i2c_bus_conf, &i2c_bus_handle));

    if (i2c_master_probe(i2c_bus_handle, 0x3C, 50) == ESP_OK)
    {
        oled_i2c_address = 0x3C;
    }
    else if (i2c_master_probe(i2c_bus_handle, 0x3D, 50) == ESP_OK)
    {
        oled_i2c_address = 0x3D;
    }
    else
    {
        ESP_LOGW(TAG, "No OLED ACK found on 0x3C or 0x3D, skipping OLED init");
        return;
    }

    ESP_LOGI(TAG, "OLED detected at I2C address 0x%02X", oled_i2c_address);

    esp_lcd_panel_io_i2c_config_t io_config = {
        .dev_addr = oled_i2c_address,
        .scl_speed_hz = 100000,
        .control_phase_bytes = 1,
        .dc_bit_offset = 6,
        .lcd_cmd_bits = 8,
        .lcd_param_bits = 8,
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_io_i2c(i2c_bus_handle, &io_config, &oled_io_handle));

    esp_lcd_panel_ssd1306_config_t ssd1306_config = {
        .height = OLED_V_RES,
    };
    esp_lcd_panel_dev_config_t panel_config = {
        .bits_per_pixel = 1,
        .reset_gpio_num = -1,
        .vendor_config = &ssd1306_config,
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_ssd1306(oled_io_handle, &panel_config, &oled_panel_handle));
    ESP_ERROR_CHECK(esp_lcd_panel_reset(oled_panel_handle));
    ESP_ERROR_CHECK(esp_lcd_panel_init(oled_panel_handle));
    ESP_ERROR_CHECK(esp_lcd_panel_swap_xy(oled_panel_handle, false));

ESP_ERROR_CHECK(esp_lcd_panel_mirror(
    oled_panel_handle,
    true,
    true));
    ESP_ERROR_CHECK(esp_lcd_panel_disp_on_off(oled_panel_handle, true));
    oled_clear_buffer();
    oled_flush_buffer();
}

static void oled_clear_buffer(void)
{
    memset(oled_framebuffer, 0, sizeof(oled_framebuffer));
}

static const uint8_t *oled_get_glyph(char c)
{
    static const uint8_t glyph_space[5] = {0x00, 0x00, 0x00, 0x00, 0x00};
    static const uint8_t glyph_dot[5]   = {0x00, 0x60, 0x60, 0x00, 0x00};
    static const uint8_t glyph_colon[5] = {0x00, 0x36, 0x36, 0x00, 0x00};
    static const uint8_t glyph_0[5]     = {0x3E, 0x51, 0x49, 0x45, 0x3E};
    static const uint8_t glyph_1[5]     = {0x00, 0x42, 0x7F, 0x40, 0x00};
    static const uint8_t glyph_2[5]     = {0x42, 0x61, 0x51, 0x49, 0x46};
    static const uint8_t glyph_3[5]     = {0x21, 0x41, 0x45, 0x4B, 0x31};
    static const uint8_t glyph_4[5]     = {0x18, 0x14, 0x12, 0x7F, 0x10};
    static const uint8_t glyph_5[5]     = {0x27, 0x45, 0x45, 0x45, 0x39};
    static const uint8_t glyph_6[5]     = {0x3C, 0x4A, 0x49, 0x49, 0x30};
    static const uint8_t glyph_7[5]     = {0x01, 0x71, 0x09, 0x05, 0x03};
    static const uint8_t glyph_8[5]     = {0x36, 0x49, 0x49, 0x49, 0x36};
    static const uint8_t glyph_9[5]     = {0x06, 0x49, 0x49, 0x29, 0x1E};
    static const uint8_t glyph_A[5]     = {0x7E, 0x11, 0x11, 0x11, 0x7E};
    static const uint8_t glyph_D[5]     = {0x7F, 0x41, 0x41, 0x22, 0x1C};
    static const uint8_t glyph_E[5]     = {0x7F, 0x49, 0x49, 0x49, 0x41};
    static const uint8_t glyph_F[5]     = {0x7F, 0x09, 0x09, 0x09, 0x01};
    static const uint8_t glyph_G[5]     = {0x3E, 0x41, 0x49, 0x49, 0x7A};
    static const uint8_t glyph_I[5]     = {0x00, 0x41, 0x7F, 0x41, 0x00};
    static const uint8_t glyph_L[5]     = {0x7F, 0x40, 0x40, 0x40, 0x40};
    static const uint8_t glyph_M[5]     = {0x7F, 0x02, 0x0C, 0x02, 0x7F};
    static const uint8_t glyph_N[5]     = {0x7F, 0x02, 0x0C, 0x10, 0x7F};
    static const uint8_t glyph_O[5]     = {0x3E, 0x41, 0x41, 0x41, 0x3E};
    static const uint8_t glyph_P[5]     = {0x7F, 0x09, 0x09, 0x09, 0x06};
    static const uint8_t glyph_R[5]     = {0x7F, 0x09, 0x19, 0x29, 0x46};
    static const uint8_t glyph_S[5]     = {0x46, 0x49, 0x49, 0x49, 0x31};
    static const uint8_t glyph_T[5]     = {0x01, 0x01, 0x7F, 0x01, 0x01};
    static const uint8_t glyph_U[5]     = {0x3F, 0x40, 0x40, 0x40, 0x3F};
    static const uint8_t glyph_V[5]     = {0x1F, 0x20, 0x40, 0x20, 0x1F};
    static const uint8_t glyph_W[5]     = {0x7F, 0x20, 0x18, 0x20, 0x7F};
    static const uint8_t glyph_Y[5]     = {0x03, 0x04, 0x78, 0x04, 0x03};

    switch (c)
    {
    case '0': return glyph_0;
    case '1': return glyph_1;
    case '2': return glyph_2;
    case '3': return glyph_3;
    case '4': return glyph_4;
    case '5': return glyph_5;
    case '6': return glyph_6;
    case '7': return glyph_7;
    case '8': return glyph_8;
    case '9': return glyph_9;
    case 'A': return glyph_A;
    case 'D': return glyph_D;
    case 'E': return glyph_E;
    case 'F': return glyph_F;
    case 'G': return glyph_G;
    case 'I': return glyph_I;
    case 'L': return glyph_L;
    case 'M': return glyph_M;
    case 'N': return glyph_N;
    case 'O': return glyph_O;
    case 'P': return glyph_P;
    case 'R': return glyph_R;
    case 'S': return glyph_S;
    case 'T': return glyph_T;
    case 'U': return glyph_U;
    case 'V': return glyph_V;
    case 'W': return glyph_W;
    case 'Y': return glyph_Y;
    case '.': return glyph_dot;
    case ':': return glyph_colon;
    case ' ': return glyph_space;
    default:  return glyph_space;
    }
}

static void oled_draw_char(int x, int page, char c)
{
    if (page < 0 || page >= (OLED_V_RES / 8) || x < 0 || x > (OLED_H_RES - 5))
    {
        return;
    }

    const uint8_t *glyph = oled_get_glyph(c);
    int offset = page * OLED_H_RES + x;
    for (int i = 0; i < 5; i++)
    {
        oled_framebuffer[offset + i] = glyph[i];
    }
}

static void oled_draw_text(int x, int page, const char *text)
{
    while (*text && x <= (OLED_H_RES - 6))
    {
        oled_draw_char(x, page, *text++);
        x += 6;
    }
}

static void oled_set_pixel(int x, int y, bool on)
{
    if (x < 0 || x >= OLED_H_RES || y < 0 || y >= OLED_V_RES)
    {
        return;
    }

    int page = y / 8;
    int bit = y % 8;
    int offset = page * OLED_H_RES + x;
    if (on)
    {
        oled_framebuffer[offset] |= (1 << bit);
    }
    else
    {
        oled_framebuffer[offset] &= ~(1 << bit);
    }
}

static void oled_draw_hline(int x, int y, int length)
{
    for (int i = 0; i < length; i++)
    {
        oled_set_pixel(x + i, y, true);
    }
}

static void oled_draw_rect(int x, int y, int width, int height)
{
    oled_draw_hline(x, y, width);
    oled_draw_hline(x, y + height - 1, width);
    for (int i = 0; i < height; i++)
    {
        oled_set_pixel(x, y + i, true);
        oled_set_pixel(x + width - 1, y + i, true);
    }
}

static void oled_fill_rect(int x, int y, int width, int height)
{
    for (int row = 0; row < height; row++)
    {
        oled_draw_hline(x, y + row, width);
    }
}

static void oled_draw_text_scaled(int x, int y, const char *text, int scale)
{
    if (scale <= 0)
    {
        return;
    }

    while (*text)
    {
        const uint8_t *glyph = oled_get_glyph(*text++);
        for (int col = 0; col < 5; col++)
        {
            for (int row = 0; row < 7; row++)
            {
                if (glyph[col] & (1 << row))
                {
                    for (int dx = 0; dx < scale; dx++)
                    {
                        for (int dy = 0; dy < scale; dy++)
                        {
                            oled_set_pixel(
                                x + (col * scale) + dx,
                                y + (row * scale) + dy,
                                true);
                        }
                    }
                }
            }
        }
        x += (6 * scale);
    }
}

static void oled_flush_buffer(void)
{
    ESP_ERROR_CHECK(esp_lcd_panel_draw_bitmap(
        oled_panel_handle,
        0,
        0,
        OLED_H_RES,
        OLED_V_RES,
        oled_framebuffer));
}

static void oled_task(void *param)
{
    char voltage_text[16];
    char current_text[16];
    char power_text[16];
    char relay_text[8];

    while (1)
    {
        // Voltage
        int voltage_centivolts = (int)(voltage_reading_v * 100.0f + 0.5f);
        int voltage_whole = voltage_centivolts / 100;
        int voltage_frac = voltage_centivolts % 100;

        // Current = Voltage × 0.4
        float current_reading = voltage_reading_v * 0.4f;

        int current_centi = (int)(current_reading * 100.0f + 0.5f);
        int current_whole = current_centi / 100;
        int current_frac = current_centi % 100;

        // Power = V × I
        float power_reading = voltage_reading_v * current_reading;

        int power_centi = (int)(power_reading * 100.0f + 0.5f);
        int power_whole = power_centi / 100;
        int power_frac = power_centi % 100;

        // Format strings
        snprintf(voltage_text,
                 sizeof(voltage_text),
                 "%d.%02dV",
                 voltage_whole,
                 voltage_frac);

        snprintf(current_text,
                 sizeof(current_text),
                 "%d.%02dA",
                 current_whole,
                 current_frac);

        snprintf(power_text,
                 sizeof(power_text),
                 "%d.%02dW",
                 power_whole,
                 power_frac);

        snprintf(relay_text,
                 sizeof(relay_text),
                 light_state ? "ON" : "OFF");

        // ================= UI =================

        oled_clear_buffer();

        // Header
        oled_draw_text(30, 0, "EVOLTE");
        oled_draw_hline(0, 10, 128);

        // Voltage
        oled_draw_text_scaled(0, 16, "V", 1);
        oled_draw_text_scaled(18, 16, voltage_text, 1);

        // Current
        oled_draw_text_scaled(0, 32, "I", 1);
        oled_draw_text_scaled(18, 32, current_text, 1);

        // Power
        oled_draw_text_scaled(0, 48, "P", 1);
        oled_draw_text_scaled(18, 48, power_text, 1);

        // Relay status
        oled_draw_text(90, 7, relay_text);

        oled_flush_buffer();

        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}


//// CODE For Local Server Starts
static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                               int32_t event_id, void *event_data)
{
    if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP)
    {
        ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
        ESP_LOGI("WIFI", "Got IP: " IPSTR, IP2STR(&event->ip_info.ip));
        ble_app_advertise(); // <-- Restart BLE advertising after WiFi reconnects
    }
}

void wifi_init_sta(void)
{
    esp_netif_init();
    esp_event_loop_create_default();
    esp_netif_create_default_wifi_sta();
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    esp_wifi_init(&cfg);

    // Register event handler for IP_EVENT_STA_GOT_IP
    esp_event_handler_instance_t instance_any_id;
    esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL, &instance_any_id);

    wifi_config_t wifi_config = {
        .sta = {
            .ssid = "SUNSHINECDG",
            .password = "sunshine_cdg2015",
        },
    };
    esp_wifi_set_mode(WIFI_MODE_STA);
    esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
    esp_wifi_start();
    esp_wifi_connect();
}
esp_err_t set_config_post_handler(httpd_req_t *req)
{
    char buf[128];
    int ret = httpd_req_recv(req, buf, sizeof(buf) - 1);
    if (ret <= 0)
        return ESP_FAIL;
    buf[ret] = 0;

    // Parse form data (very basic, for demo)
    char ble_name[32] = {0}, ssid[32] = {0}, password[64] = {0};
    sscanf(buf, "name=%31[^&]&ssid=%31[^&]&password=%63s", ble_name, ssid, password);

    // URL decode (replace + with space, decode %xx if needed)
    for (int i = 0; ble_name[i]; i++)
        if (ble_name[i] == '+')
            ble_name[i] = ' ';
    for (int i = 0; ssid[i]; i++)
        if (ssid[i] == '+')
            ssid[i] = ' ';
    for (int i = 0; password[i]; i++)
        if (password[i] == '+')
            password[i] = ' ';

    // Set BLE name (NO NimBLE re-init!)
    if (strlen(ble_name) > 0)
    {
        ble_svc_gap_device_name_set(ble_name);
        ble_app_advertise(); // Restart advertising with new name
    }

    // Set WiFi credentials and reconnect
    if (strlen(ssid) > 0 && strlen(password) > 0)
    {
        wifi_config_t wifi_config = {0};
        strncpy((char *)wifi_config.sta.ssid, ssid, sizeof(wifi_config.sta.ssid));
        strncpy((char *)wifi_config.sta.password, password, sizeof(wifi_config.sta.password));
        esp_wifi_disconnect();
        esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
        esp_wifi_connect();
    }

    httpd_resp_sendstr(req, "Configuration updated. <a href='/'>Go Back</a>");
    return ESP_OK;
}

// Update your root_get_handler to include WiFi fields
esp_err_t root_get_handler(httpd_req_t *req)
{
    const char *html_response =
        "<!DOCTYPE html>"
        "<html>"
        "<head><title>ESP32 BLE Config</title></head>"
        "<body>"
        "<h2>ESP32 BLE & WiFi Config Server</h2>"
        "<form method='POST' action='/set_config'>"
        "Set BLE Name: <input name='name' maxlength='31'/><br>"
        "WiFi SSID: <input name='ssid' maxlength='31'/><br>"
        "WiFi Password: <input name='password' maxlength='63' type='password'/><br>"
        "<input type='submit' value='Update'/>"
        "</form>"
        "</body></html>";
    httpd_resp_set_type(req, "text/html");
    httpd_resp_sendstr(req, html_response);
    return ESP_OK;
}

// Register the new handler in start_webserver
void start_webserver(void)
{
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    httpd_handle_t server = NULL;
    if (httpd_start(&server, &config) == ESP_OK)
    {
        httpd_uri_t root_uri = {
            .uri = "/",
            .method = HTTP_GET,
            .handler = root_get_handler,
            .user_ctx = NULL};
        httpd_register_uri_handler(server, &root_uri);

        httpd_uri_t set_config_uri = {
            .uri = "/set_config",
            .method = HTTP_POST,
            .handler = set_config_post_handler,
            .user_ctx = NULL};
        httpd_register_uri_handler(server, &set_config_uri);
    }
}
static void status_led_task(void *param)
{
    bool led_state = false;

    while (1)
    {
        led_state = !led_state;
        gpio_set_level(GREEN_LED_GPIO, led_state);
    
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

void setup_alert_outputs()
{
    gpio_config_t io_conf = {
        .pin_bit_mask =
            (1ULL << RED_LED_GPIO) |
            (1ULL << BUZZER_GPIO),

        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = 0,
        .pull_down_en = 0,
        .intr_type = GPIO_INTR_DISABLE
    };

    gpio_config(&io_conf);

    gpio_set_level(RED_LED_GPIO, 0);
    gpio_set_level(BUZZER_GPIO, 0);
}


//// Code for Local Server Ends
void app_main()
{
   
    nvs_flash_init();
    setup_light_gpio();
    setup_status_leds();
    setup_dht_gpio();
    setup_switch_gpio();
    init_voltage_sensor();
    setup_alert_outputs();
    init_oled_display();
    xTaskCreate(voltage_sensor_task, "voltage_sensor_task", 4096, NULL, 5, NULL);
    xTaskCreate(status_led_task, "status_led_task", 2048, NULL, 5, NULL);
    xTaskCreate(switch_task, "switch_task", 2048, NULL, 5, NULL);
    if (oled_panel_handle != NULL)
    {
        xTaskCreate(oled_task, "oled_task", 4096, NULL, 4, NULL);
    }
    // wifi_init_sta();   // Initialize Wi-Fi station
    // start_webserver(); // Start HTTP server
    //  esp_nimble_hci_and_controller_init();      // 2 - Initialize ESP controller
    nimble_port_init();                       // 3 - Initialize the host stack
    ble_svc_gap_device_name_set("eVolte_01"); // 4 - Initialize NimBLE configuration - server name
    ble_svc_gap_init();                       // 4 - Initialize NimBLE configuration - gap service
    ble_svc_gatt_init();                      // 4 - Initialize NimBLE configuration - gatt service
    ble_gatts_count_cfg(gatt_svcs);           // 4 - Initialize NimBLE configuration - config gatt services
    ble_gatts_add_svcs(gatt_svcs);            // 4 - Initialize NimBLE configuration - queues gatt services.
    ble_hs_cfg.sync_cb = ble_app_on_sync;     // 5 - Initialize application
    nimble_port_freertos_init(host_task);     // 6 - Run the thread
}
