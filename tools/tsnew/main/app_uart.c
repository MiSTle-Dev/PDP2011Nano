
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

#include "app_telnetd.h"

static const char *TAG = "app_uart";


const int uart1 = UART_NUM_1;
uart_config_t uart1_config = {
   .baud_rate = 9600,
   .data_bits = UART_DATA_8_BITS,
   .parity = UART_PARITY_DISABLE,
   .stop_bits = UART_STOP_BITS_1,
   .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
   .rx_flow_ctrl_thresh = 0,
   .source_clk = UART_SCLK_DEFAULT
};

// Setup UART buffered IO with event queue
const int uart1_buffer_size = (1024 * 2);
QueueHandle_t uart1_queue;

const int uart2 = UART_NUM_2;
uart_config_t uart2_config = {
   .baud_rate = 9600,
   .data_bits = UART_DATA_8_BITS,
   .parity = UART_PARITY_DISABLE,
   .stop_bits = UART_STOP_BITS_1,
   .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
   .rx_flow_ctrl_thresh = 0,
   .source_clk = UART_SCLK_DEFAULT
};

// Setup UART buffered IO with event queue
const int uart2_buffer_size = (1024 * 2);
QueueHandle_t uart2_queue;



static void uart_task(void *pvParameters)
{
   int uart;
   int i;
   char buf[1024];
   int noofbytes;
   int lastrunwasproductive=0;
   int didhitmax=0;

   uart = (int) pvParameters;
   ESP_LOGI(TAG, "task started for uart %d", uart);

   while (1) {
      if (lastrunwasproductive) {
         noofbytes=uart_read_bytes(uart, (uint8_t *) &buf, sizeof(buf)-1, 0);
      } else {
         noofbytes=uart_read_bytes(uart, (uint8_t *) &buf, 1, 100);
      }
      didhitmax=0;
      if (noofbytes>0) {
         if (noofbytes==sizeof(buf)-1) {
            didhitmax++;
         }
         for (i=0; i<MAX_SESSION; i++) {
            if (session[i].sock!=0 && session[i].uart==uart) {
               telnetd_send(&session[i], buf, noofbytes);
            }
         }
         lastrunwasproductive=1;
      } else {
         lastrunwasproductive=0;
      }
      if (didhitmax) {
         ESP_LOGI(TAG, "hit max for uart %d", uart);
         didhitmax=0;
      }
   }
}



void uart_init(void)
{
// Configure UART parameters -- UART1 is LINE
   ESP_ERROR_CHECK(uart_param_config(uart1, &uart1_config));
   ESP_ERROR_CHECK(uart_set_pin(uart1, 19, 22, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));

// Configure UART parameters -- UART2 is CONS
   ESP_ERROR_CHECK(uart_param_config(uart2, &uart2_config));
   ESP_ERROR_CHECK(uart_set_pin(uart2, 7, 8, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));

// Install UART driver using an event queue here
   ESP_ERROR_CHECK(uart_driver_install(uart1, uart1_buffer_size, uart1_buffer_size, 20, &uart1_queue, 0));
//   uart_set_tx_idle_num(uart1, 10);
//   uart_wait_tx_done(uart1, 10);
//   uart_set_rx_timeout(uart1, 10);

// Install UART driver using an event queue here
   ESP_ERROR_CHECK(uart_driver_install(uart2, uart2_buffer_size, uart2_buffer_size, 20, &uart2_queue, 0));
//   uart_set_tx_idle_num(uart2, 10);
//   uart_wait_tx_done(uart2, 10);
//   uart_set_rx_timeout(uart2, 10);

   xTaskCreate(uart_task, "uart_reader1", 4096, (void *) uart1, 15, NULL);
   xTaskCreate(uart_task, "uart_reader2", 4096, (void *) uart2, 15, NULL);
}
