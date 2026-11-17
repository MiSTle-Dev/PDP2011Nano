
/*

  esp32 telnet server proof of concept

*/

#include <string.h>
#include <sys/param.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "esp_netif.h"
#include "protocol_examples_common.h"

#include "lwip/err.h"
#include "lwip/sys.h"

#include "driver/uart.h"
#include "driver/gpio.h"

#include "lwip/err.h"
#include "lwip/sockets.h"
#include "lwip/sys.h"
#include "lwip/netdb.h"

#include "app_nvs.h"
#include "app_wifi.h"
#include "app_uart.h"
#include "app_telnetd.h"
#include "app_cons.h"

static const char *TAG = "app_main";


void app_main(void)
{
   ESP_LOGI(TAG, "start up");

   initnvs();
   wifi_init_sta();
   uart_init();

   xTaskCreate(app_telnetd, "telnetd", 4096, NULL, 10, NULL);

   ESP_LOGI(TAG, "init done");

   app_cons();
}
