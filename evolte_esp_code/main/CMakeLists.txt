idf_component_register(SRCS "main.c"
                    INCLUDE_DIRS "."
                    REQUIRES nvs_flash bt esp_netif esp_event esp_http_server driver esp_wifi lwip)
