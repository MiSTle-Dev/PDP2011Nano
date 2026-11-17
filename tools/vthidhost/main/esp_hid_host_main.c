/*
 * SPDX-FileCopyrightText: 2021 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Unlicense OR CC0-1.0
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "esp_bt.h"
#include "esp_bt_defs.h"
#include "esp_gap_ble_api.h"
#include "esp_gatts_api.h"
#include "esp_gatt_defs.h"
#include "esp_bt_main.h"
#include "esp_bt_device.h"

#include "esp_hidh.h"
#include "esp_hid_gap.h"

#include "esp_timer.h"

#include "driver/uart.h"
#include "driver/gpio.h"

#define TYPEMATIC_DELAY 15
#define TYPEMATIC_INTVL 50000

static const char *TAG = "VTHIDHOST";

const uart_port_t uart_num = UART_NUM_2;
const uart_config_t uart_config = {
   .baud_rate = 9600,
   .data_bits = UART_DATA_8_BITS,
   .parity = UART_PARITY_DISABLE,
   .stop_bits = UART_STOP_BITS_1,
   .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
   .rx_flow_ctrl_thresh = 0,
   .source_clk = UART_SCLK_DEFAULT,
} ;
const int uart_buffer_size = (1024 * 2);
QueueHandle_t uart_queue;


static volatile uint8_t lastch = 0337;
static uint8_t kact = 0337;


static uint8_t kbtab1[128] = {
   0, 0, 0, 0,
   'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
   '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
   0347,                   // enter - sends clrf
   27,                     // escape
   0373,                   // backspace sends del
   9,                      // tab
   ' ',                    // space
   '-',
   '=',
   '[',
   ']',
   '\\',
   0,                      // ? dec 50, ellipsis?
   ';',
   '\'',
   '`',
   ',',
   '.',
   '/',
   0,                      // caps lock, decimal 57
   0375,                   // f1
   0376,                   // f2
   0377,                   // f3
   0340,                   // f4
   0,                      // f5
   0,                      // f6
   0,                      // f7
   0,                      // f8
   0,                      // f9
   0,                      // f10
   0,                      // f11
   0,                      // f12
   0,                      // prtscr
   0,                      // scrolllk
   0,                      // pause
   0371,                   // insert
   0372,                   // home
   0346,                   // pgup
   0373,                   // delete
   0374,                   // end
   0345,                   // pgdn
   0343,                   // right
   0341,                   // left
   0342,                   // down
   0344,                   // up
   0351,                   // numlk
   0350,                   // kp slash
   0353,                   // kp asterisk
   0354,                   // kp minus
   0355,                   // kp plus
   0352,                   // kp enter
   0360,                   // kp 1
   0361,                   // kp 2
   0362,                   // kp 3
   0363,                   // kp 4
   0364,                   // kp 5
   0365,                   // kp 6
   0366,                   // kp 7
   0367,                   // kp 8
   0370,                   // kp 9
   0357,                   // kp 0
   0356,                   // kp dot
   0,                      // ? dec 100, ellipsis?
   0,                      //
   0,                      //
   0,                      // kp equals
   0,                      // f13
   0,                      // f14
   0,                      // f15
   0,                      // f16
   0,                      // f17
   0,                      // f18
   0,                      // f19
   0,                      // f20
   0,                      // f21
   0,                      // f22
   0,                      // f23
   0,                      // f24
   0,
   0,
   0,
   0,
   0,
   0,
   0,
   0,
   0,
   0,
   0,
   0
} ;

static uint8_t kbtab2[64] = {
   0, 0, 0, 0,
   'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
   '!', '@', '#', '$', '%', '^', '&', '*', '(', ')',
   10,                    // enter
   27,                    // escape
   8,                     // backspace
   9,                     // tab
  ' ',                    // space
   '_',
   '+',
   '{',
   '}',
   '|',
   0,                      // ? dec 50, ellipsis?
   ':',
   '"',
   '~',
   '<',
   '>',
   '?',
   0,                      // caps lock, decimal 57
   0,                      // f1
   0,                      // f2
   0,                      // f3
   0,                      // f4
   0,                      // f5
   0                       // f6 decimal 63
} ;

static uint8_t keyboardxlate(uint8_t ctrl, uint8_t key)
{
   uint8_t t;

   t=kbtab1[key & 0x7f];                                            // normal case
   if ((ctrl & 0x22) && (key < 64)) t=kbtab2[key & 0x3f];           // shifted case
   if (ctrl & 0x11) {                                               // control
      if (t >= 'a' && t <= 'z') {
         t = t - 96;
         return t;
      }
      if (t >= 64 && t <= 95) {
         t = t - 64;
         return t;
      }
   }
   return t;
}

void hidh_callback(void *handler_args, esp_event_base_t base, int32_t id, void *event_data)
{
   esp_hidh_event_t event = (esp_hidh_event_t)id;
   esp_hidh_event_data_t *param = (esp_hidh_event_data_t *)event_data;

   uint8_t key;
   uint8_t ctrl;
   uint8_t ch;
   uint8_t byte8;
   uint16_t inputlength;
   int i, j;
   static int lastvectorlength = 2;
   int produced, keyerror;

   produced = 0;
   keyerror = 0;
   lastch = kact;

   switch (event) {
   case ESP_HIDH_OPEN_EVENT: {
      if (param->open.status == ESP_OK) {
         const uint8_t *bda = esp_hidh_dev_bda_get(param->open.dev);
         ESP_LOGI(TAG, ESP_BD_ADDR_STR " OPEN: %s", ESP_BD_ADDR_HEX(bda), esp_hidh_dev_name_get(param->open.dev));
         esp_hidh_dev_dump(param->open.dev, stdout);
      } else {
          ESP_LOGE(TAG, " OPEN failed!");
      }
      break;
   }
   case ESP_HIDH_BATTERY_EVENT: {
      const uint8_t *bda = esp_hidh_dev_bda_get(param->battery.dev);
      ESP_LOGI(TAG, ESP_BD_ADDR_STR " BATTERY: %d%%", ESP_BD_ADDR_HEX(bda), param->battery.level);
      break;
   }
   case ESP_HIDH_INPUT_EVENT: {
//        const uint8_t *bda = esp_hidh_dev_bda_get(param->input.dev);
//        ESP_LOGI(TAG, ESP_BD_ADDR_STR " INPUT: %8s, MAP: %2u, ID: %3u, Len: %d, Data:", ESP_BD_ADDR_HEX(bda), esp_hid_usage_str(param->input.usage), param->input.map_index, param->input.report_id, param->input.length);
//        ESP_LOG_BUFFER_HEX(TAG, param->input.data, param->input.length);
      inputlength = param->input.length;
      if (inputlength < 8) {
         break;
      }
      if (inputlength >= 9) {
         byte8 = *((uint8_t *) (param->input.data)+8);
      } else {
         byte8 = 0;
      }
      ctrl = *((uint8_t *) (param->input.data));
      for (i=0; i < inputlength; i++) {
         key = *((uint8_t *) (param->input.data)+i);
         if (i == 1) key = byte8;
         if (i > 1 && key == 0) break;
         printf("%02x ", key);
      }
      if (i > lastvectorlength) {
         printf("{ ");
         for (j = lastvectorlength; j < i; j++) {
            key = *((uint8_t *) (param->input.data)+j);
            if (key == 1) {
               printf("E ");
               keyerror++;
            } else {
               ch = keyboardxlate(ctrl, key);
               printf("%02x(%d) = %02x '%c' ", key, key, ch, isprint(ch) && !isspace(ch) ? ch : '.');
               uart_write_bytes(uart_num, (const char *) &ch, 1);
               produced++;
               lastch = ch;
            }
         }
         printf("}");
      }
      lastvectorlength = i;
      if (produced == 0 && keyerror == 0) {
         printf("{ nul }");
         uart_write_bytes(uart_num, (const char *) &kact, 1);
         lastch = kact;
      }
      printf("\n");
      break;
   }
   case ESP_HIDH_FEATURE_EVENT: {
      const uint8_t *bda = esp_hidh_dev_bda_get(param->feature.dev);
      ESP_LOGI(TAG, ESP_BD_ADDR_STR " FEATURE: %8s, MAP: %2u, ID: %3u, Len: %d", ESP_BD_ADDR_HEX(bda),
               esp_hid_usage_str(param->feature.usage), param->feature.map_index, param->feature.report_id,
               param->feature.length);
      ESP_LOG_BUFFER_HEX(TAG, param->feature.data, param->feature.length);
      break;
   }
   case ESP_HIDH_CLOSE_EVENT: {
      const uint8_t *bda = esp_hidh_dev_bda_get(param->close.dev);
      ESP_LOGI(TAG, ESP_BD_ADDR_STR " CLOSE: %s", ESP_BD_ADDR_HEX(bda), esp_hidh_dev_name_get(param->close.dev));
      break;
   }
   default:
      ESP_LOGI(TAG, "EVENT: %d", event);
      break;
   }
}

#define SCAN_DURATION_SECONDS 5

void hid_demo_task(void *pvParameters)
{
   size_t results_len = 0;
   esp_hid_scan_result_t *results = NULL;
   ESP_LOGI(TAG, "SCAN...");
   //start scan for HID devices
   esp_hid_scan(SCAN_DURATION_SECONDS, &results_len, &results);
   ESP_LOGI(TAG, "SCAN: %u results", results_len);
   if (results_len) {
      esp_hid_scan_result_t *r = results;
      esp_hid_scan_result_t *cr = NULL;
      while (r) {
         printf("  %s: " ESP_BD_ADDR_STR ", ", (r->transport == ESP_HID_TRANSPORT_BLE) ? "BLE" : "BT ", ESP_BD_ADDR_HEX(r->bda));
         printf("RSSI: %d, ", r->rssi);
         printf("USAGE: %s, ", esp_hid_usage_str(r->usage));
#if CONFIG_BT_BLE_ENABLED
         if (r->transport == ESP_HID_TRANSPORT_BLE) {
            cr = r;
            printf("APPEARANCE: 0x%04x, ", r->ble.appearance);
            printf("ADDR_TYPE: '%s', ", ble_addr_type_str(r->ble.addr_type));
         }
#endif /* CONFIG_BT_BLE_ENABLED */
#if CONFIG_BT_HID_HOST_ENABLED
         if (r->transport == ESP_HID_TRANSPORT_BT) {
            cr = r;
            printf("COD: %s[", esp_hid_cod_major_str(r->bt.cod.major));
            esp_hid_cod_minor_print(r->bt.cod.minor, stdout);
            printf("] srv 0x%03x, ", r->bt.cod.service);
            print_uuid(&r->bt.uuid);
            printf(", ");
         }
#endif /* CONFIG_BT_HID_HOST_ENABLED */
         printf("NAME: %s ", r->name ? r->name : "");
         printf("\n");
         r = r->next;
      }
      if (cr) {
         //open the last result
         esp_hidh_dev_open(cr->bda, cr->transport, cr->ble.addr_type);
      }
      //free the results
      esp_hid_scan_results_free(results);
   }
   vTaskDelete(NULL);
}


static void typematic_timer_callback(void* arg)
{
   static int delay = 0;

   if (lastch != kact) {
      delay++;
      if (delay>=TYPEMATIC_DELAY) {
         if (delay==TYPEMATIC_DELAY) {
            printf("typematic 0x%02x '%c'\n", lastch, isprint(lastch) && !isspace(lastch) ? lastch : '.');
         }
         uart_write_bytes(uart_num, (const char *) &lastch, 1);
      }
   } else {
      delay = 0;
   }
}


void init_uart()
{
   ESP_ERROR_CHECK(uart_param_config(uart_num, &uart_config));
   ESP_ERROR_CHECK(uart_set_pin(uart_num, 7, 8, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));
   ESP_ERROR_CHECK(uart_driver_install(uart_num, uart_buffer_size, uart_buffer_size, 10, &uart_queue, 0));
   ESP_ERROR_CHECK(uart_set_mode(uart_num, UART_MODE_UART));
}

void app_main(void)
{
   esp_err_t ret;
#if HID_HOST_MODE == HIDH_IDLE_MODE
   ESP_LOGE(TAG, "Please turn on BT HID host or BLE!");
   return;
#endif
   ret = nvs_flash_init();
   if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
      ESP_ERROR_CHECK(nvs_flash_erase());
      ret = nvs_flash_init();
   }
   ESP_ERROR_CHECK( ret );
   init_uart();
   ESP_LOGI(TAG, "setting hid gap, mode:%d", HID_HOST_MODE);
   ESP_ERROR_CHECK( esp_hid_gap_init(HID_HOST_MODE) );
#if CONFIG_BT_BLE_ENABLED
   ESP_ERROR_CHECK( esp_ble_gattc_register_callback(esp_hidh_gattc_event_handler) );
#endif /* CONFIG_BT_BLE_ENABLED */
   esp_hidh_config_t config = {
      .callback = hidh_callback,
      .event_stack_size = 4096,
      .callback_arg = NULL,
   };
   ESP_ERROR_CHECK( esp_hidh_init(&config) );

   const esp_timer_create_args_t typematic_timer_args = {
      .callback = &typematic_timer_callback,
      .name = "typematic"
   };
   esp_timer_handle_t typematic_timer;
   ESP_ERROR_CHECK(esp_timer_create(&typematic_timer_args, &typematic_timer));
   ESP_ERROR_CHECK(esp_timer_start_periodic(typematic_timer, TYPEMATIC_INTVL));

   xTaskCreate(&hid_demo_task, "hid_task", 6 * 1024, NULL, 2, NULL);
}

