### IAQ Sensor Data and Diagnostic Packets

1. IAQ Sensor will maintain a permanant hardware ID via mac address (ex: device_id: "e5:d6:b2:79:56:a5")
   - IAQ Sensor will have a local option to reset a logical deployment ID for deployment changes (ex: deployment_id: "dep_D7kP3zQ9mXaL2vRb" mapped to human readable names on backend?)
2. IAQ Sensor will feature monotonic data counters (u_int64) that counts up from initial firmware flash/factory reset for each data point. Firmware updates should not modify this value. If a data_counter:3 exists, all data points lower such as data_counter:2, data_counter:1, and data_counter:0 should also exist. No skipped data points ever. If missing datapoints something has failed and there should be some sort of notification indicating that the hardware should be replaced (ex: data_counter: 1521055, event_counter: 12322)
3. IAQ Sensor will have a local unix timestamp with each data point. (ex: device_ts: 1779123456789)
4. IAQ Sensor will have a data payload of the average data for the previous time interval. This will be configurable but current design has it at 1min.
   ex:

```
		{
		  "NOXindex_0-500": 87,
		  "RTC_TempC": 24.13,
		  "RTC_TempC_Cal": 23.91,
		  "SCD41_CO2ppm": 612,
		  "SCD41_RH": 41.8,
		  "SCD41_TempC": 24.44,
		  "SCD41_TempC_Cal": 24.12,
		  "SEN55_PM10p0_ugpm3": 5.3,
		  "SEN55_PM1p0_ugpm3": 2.1,
		  "SEN55_PM2p5_ugpm3": 3.2,
		  "SEN55_PM4p0_ugpm3": 4.0,
		  "SEN55_RH": 42.1,
		  "SEN55_TempC": 24.31,
		  "SEN55_TempC_Cal": 24.02,
		  "SHTC3_RH": 41.5,
		  "SHTC3_TempC": 24.28,
		  "SHTC3_TempC_Cal": 23.98,
		  "VOCindex_0-500": 96,
		}
```

Data Packet: Each data packet above will be written to disk and persisted every 1 min. This is the data that should guarantee at least 1 write to the database. It will look something like this:

```
		{
		  "device_id": "A4:C1:38:7B:92:11",
		  "deployment_id": "dep_D7kP3zQ9mXaL2vRb",
		  "data_counter": 918273,
		  "device_timestamp_ms": 1779123456789,
		  "boot_id": "8a6dbe0d5af0e1bc",
		  "boot_counter: 31,
		  "uptime_sec": 4444,
		  "WiFi_RSSI_dBm": -61,
		  "NOXindex_0-500": 87,
		  "RTC_TempC": 24.13,
		  "RTC_TempC_Cal": 23.91,
		  "SCD41_CO2ppm": 612,
		  "SCD41_RH": 41.8,
		  "SCD41_TempC": 24.44,
		  "SCD41_TempC_Cal": 24.12,
		  "SEN55_PM10p0_ugpm3": 5.3,
		  "SEN55_PM1p0_ugpm3": 2.1,
		  "SEN55_PM2p5_ugpm3": 3.2,
		  "SEN55_PM4p0_ugpm3": 4.0,
		  "SEN55_RH": 42.1,
		  "SEN55_TempC": 24.31,
		  "SEN55_TempC_Cal": 24.02,
		  "SHTC3_RH": 41.5,
		  "SHTC3_TempC": 24.28,
		  "SHTC3_TempC_Cal": 23.98,
		  "VOCindex_0-500": 96
		}
```

Additional diagnostic debug packet for sensor metadata collection. This is very useful for diagnosing issues and spotting patterns. Could also be stored to disk as we have tons of storage available (8gb sd card per sensor).

```
		{
		  "device_id": "A4:C1:38:7B:92:11",
		  "deployment_id": "dep_D7kP3zQ9mXaL2vRb",
		  "boot_counter": 31, <-- monotonic
		  "event_counter": 1224, <-- monotonic and what the backend will use for ACK syncing of debug packets
		  "data_counter": 918273, <-- The current data count on event/metadata generation
		  "event_reason": "HEARTBEAT", (can be a lot of things like wifi state transitions (connected -> disconnected), etc...)
		  "device_ts": 1771827437882,
		  "boot_id": "8a6dbe0d5af0e1bc",
		  "boot_ts": 1779119012345,
		  "uptime_sec": 4446,
		  "boot_reason", "POWERON" (Can have a lot of these, like watchdog, user reset, etc...)
		  "hardware_ver": "1.0.0",
		  "firmware_ver": "v1.1b",
		  "device_type": "IAQ-SEN66-NOX",
		  "device_name": "IAQ0014",
		  "sampling_interval_sec": 60,
		  "WiFi": 	{
					  "connected: "true",
					  "RSSI_dBm": -54,
					  "Channel": 14,
					  "BSSID": "aa:bb:cc:dd:ee:ff", <-- This represents the access point the sensor is connected to
					  "disconnect_count": 229, <-- Monotonic
					  "reconnect_count": 21, <-- Monotonic
					  "reconnect_attempt_count": 24, <-- Monotonic
					  "last_disconnect_reason": 4, (ESP32 library has a bunch of these. 4 is Assoc Expire which means it couldn't get a solid signal for a handshake)
					  "connection_uptime_sec": 311
					},
		  "System": {
					  "battery_mV": 3943,
					  "rom_free_storage_bytes": 2929311,
					  "last_backend_ts": 1771827437732,
					  "backend_HWM": 918273,
					  "sdcard_present": "true", <--- hardware failure diagnostic
					  "sdcard_buffered_data_count": 0, <-- this counts up when the sensor fails to receive an ACK from backend
					  "sdcard_buffered_event_count" 0, <-- this counts up when the sensor fails to receive an ACK from backend
					  "watchdog_reset_count": 0, <-- monotonic used to identify firmware issues or device failure
					  "cpu_usage_percent": 11.3,
					  "current_free_heap_bytes": 222312, <-- current memory pressure
					  "min_free_heap_bytes: 22023, <-- useful for detecting memory leaks, if this keeps going down it means there's a memory leak
					  "last_NTP_sync": 1775185525000,
					  "last_NTP_offset_ms": -3112,
					  "last_time_to_ACK_ms: 2198, <-- measures device wall clock time from sending packet to receiving backend ACK maybe not useful on device side
					}
		}

```
