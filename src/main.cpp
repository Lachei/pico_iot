/**
 * Copyright (c) 2022 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "pico/cyw43_arch.h"
#include "pico/stdlib.h"

#include "lwip/ip4_addr.h"
#include "lwip/apps/mdns.h"

#include "FreeRTOS.h"
#include "task.h"

#include "log_storage.h"
#include "access_point.h"
#include "wifi_storage.h"
#include "webserver.h"
#include "usb_interface.h"
#include "settings.h"
#include "measurements.h"
#include "crypto_storage.h"
#include "ntp_client.h"

#define TEST_TASK_PRIORITY ( tskIDLE_PRIORITY + 1UL )

constexpr UBaseType_t STANDARD_TASK_PRIORITY = tskIDLE_PRIORITY + 1ul;
constexpr UBaseType_t CONTROL_TASK_PRIORITY = tskIDLE_PRIORITY + 10ul;

constexpr uint32_t time_ms() { return time_us_64() / 1000; }
constexpr uint32_t time_s() { return time_us_64() / 1000000; }

void usb_comm_task(void *) {
    LogInfo("Usb communication task started");
    crypto_storage::Default();

    for (;;) {
	handle_usb_command();
    }
}

void measure_task(void *) {
}

void control_task(void *) {
    time_us_64();

}

void wifi_search_task(void *) {
    LogInfo("Wifi task started");
    if (wifi_storage::Default().ssid_wifi.empty()) // onyl start the access point by default if no normal wifi connection is set
        access_point::Default().init();

    constexpr uint32_t ap_timeout = 10;
    uint32_t cur_time = time_s();
    uint32_t last_conn = cur_time;

    for (;;) {
        cur_time = time_s();
        uint32_t dt = cur_time - last_conn;
        wifi_storage::Default().update_hostname();
        wifi_storage::Default().update_wifi_connection();
        if (wifi_storage::Default().wifi_connected)
            last_conn = cur_time;
        if (dt % 30 == 5) // every 30 seconds enable reconnect try
            wifi_storage::Default().wifi_changed = true;
        if (dt > ap_timeout) {
            access_point::Default().init();
            cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, cur_time & 1);
        } else {
            cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, wifi_storage::Default().wifi_connected);
        }
        wifi_storage::Default().update_scanned();
        if (wifi_storage::Default().wifi_connected)
            ntp_client::Default().update_time();
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}


// task to initailize everything and only after initialization startin all other threads
// cyw43 init has to be done in freertos task because it utilizes freertos synchronization variables
void startup_task(void *) {
    LogInfo("Starting initialization");
    std::cout << "Starting initialization\n";
    if (cyw43_arch_init()) {
        for (;;) {
            vTaskDelay(1000);
            LogError("failed to initialize\n");
            std::cout << "failed to initialize arch (probably ram problem, increase ram size)\n";
        }
    }
    cyw43_arch_enable_sta_mode();
    wifi_storage::Default().update_hostname();
    Webserver().start();
    LogInfo("Ready, running http at {}", ip4addr_ntoa(netif_ip4_addr(netif_list)));
    LogInfo("Initialization done");
    std::cout << "Initialization done, get all further info via the commands shown in 'help'\n";

    cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, 1);
    xTaskCreate(usb_comm_task, "usb_comm", 512, NULL, 1, NULL);
    xTaskCreate(wifi_search_task, "UpdateWifiThread", 512, NULL, 1, NULL);
    cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, 0);
    vTaskDelete(NULL); // remove this task for efficiency reasions
}

int main( void )
{
    stdio_init_all();

    LogInfo("Starting FreeRTOS on all cores.");
    std::cout << "Starting FreeRTOS on all cores\n";

    xTaskCreate(startup_task, "StartupThread", 512, NULL, 1, NULL);

    vTaskStartScheduler();
    return 0;
}
