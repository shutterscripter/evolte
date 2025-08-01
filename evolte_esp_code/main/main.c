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

char *TAG = "BLE-Server";
uint8_t ble_addr_type;
void ble_app_advertise(void);

#define LIGHT_GPIO 13


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
        gpio_set_level(LIGHT_GPIO, 1);
    }
    else if (strcmp(command, "LIGHT OFF") == 0)
    {
        printf("LIGHT OFF - Turning OFF GPIO %d\n", LIGHT_GPIO);
        gpio_set_level(LIGHT_GPIO, 0);
    }
    else if (strcmp(command, "FAN ON") == 0)
    {
        printf("FAN ON\n");
        // Add your fan control logic here
    }
    else if (strcmp(command, "FAN OFF") == 0)
    {
        printf("FAN OFF\n");
        // Add your fan control logic here
    }
    else
    {
        printf("Unknown command: '%s'\n", command);
    }

    return 0;
}

// Read data from ESP32 defined as server
static int device_read(uint16_t con_handle, uint16_t attr_handle, struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    os_mbuf_append(ctxt->om, "Data from the server", strlen("Data from the server"));
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
            ble_app_advertise();
        }
        break;
    // Advertise again after completion of the event
    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI("GAP", "BLE GAP EVENT DISCONNECTED");
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
    gpio_set_level(LIGHT_GPIO, 0); // Default OFF
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
//// Code for Local Server Ends
void app_main()
{
    nvs_flash_init();
    setup_light_gpio();
    //wifi_init_sta();   // Initialize Wi-Fi station
    //start_webserver(); // Start HTTP server
    // esp_nimble_hci_and_controller_init();      // 2 - Initialize ESP controller
    nimble_port_init();                       // 3 - Initialize the host stack
    ble_svc_gap_device_name_set("eVolte_01"); // 4 - Initialize NimBLE configuration - server name
    ble_svc_gap_init();                       // 4 - Initialize NimBLE configuration - gap service
    ble_svc_gatt_init();                      // 4 - Initialize NimBLE configuration - gatt service
    ble_gatts_count_cfg(gatt_svcs);           // 4 - Initialize NimBLE configuration - config gatt services
    ble_gatts_add_svcs(gatt_svcs);            // 4 - Initialize NimBLE configuration - queues gatt services.
    ble_hs_cfg.sync_cb = ble_app_on_sync;     // 5 - Initialize application
    nimble_port_freertos_init(host_task);     // 6 - Run the thread
}
