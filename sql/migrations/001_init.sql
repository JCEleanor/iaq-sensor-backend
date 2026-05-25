CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Cleanup existing tables if they exist (for retry)
DROP TABLE IF EXISTS sensor_data;
DROP TABLE IF EXISTS devices;

-- 1. Device Table: Tracks physical hardware and its current logical assignment.
CREATE TABLE devices (
    device_id TEXT PRIMARY KEY,       -- MAC Address (e.g., 'A4:C1:38:7B:92:11'). NOTE: MACADDR or TEXT?
    deployment_id TEXT NOT NULL,         -- Logical ID (e.g., 'dep_D7kP3zQ9mXaL2vRb')
    device_name TEXT,                    -- Human readable name (e.g., 'IAQ0014')
    device_type TEXT,                    -- Hardware model (e.g., 'IAQ-SEN66-NOX')
    last_data_hwm BIGINT DEFAULT 0,      -- Last data_counter received (for HWM tracking)
    last_seen_at TIMESTAMPTZ,            -- Last time a record was received from this device
    hardware_ver TEXT,
    firmware_ver TEXT,
    timezone TEXT DEFAULT 'UTC',         -- For frontend normalization
    point_of_contact TEXT,               -- Deployment metadata
    sampling_interval_sec INTEGER DEFAULT 60,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    is_broken BOOLEAN DEFAULT FALSE      -- True if there's a gap in data_counter
);

-- 2. Sensor Data Table (Hypertable): Stores the high-frequency IAQ metrics.
CREATE TABLE sensor_data (
    time TIMESTAMPTZ NOT NULL,           -- Derived from device_timestamp_ms (for partitioning)
    server_time TIMESTAMPTZ DEFAULT NOW(),-- NOTE: When the record was actually received, send back to devices
    device_id TEXT NOT NULL REFERENCES devices(device_id),
    deployment_id TEXT NOT NULL,         -- Denormalized for easier historical querying
    data_counter BIGINT NOT NULL,        -- Monotonic counter for HWM tracking
    device_timestamp_ms BIGINT NOT NULL, -- Original device wall-clock time
    boot_id TEXT,                        -- Tracks data across reboots
    boot_counter INTEGER,
    uptime_sec INTEGER,
    wifi_rssi_dbm INTEGER,
    
    -- Sensor Metrics (mapped from IAQ-sensor-layout.md)
    nox_index INTEGER,
    voc_index INTEGER,
    rtc_temp_c NUMERIC(5, 2),
    rtc_temp_c_cal NUMERIC(5, 2),
    scd41_co2_ppm INTEGER,
    scd41_rh NUMERIC(5, 2),
    scd41_temp_c NUMERIC(5, 2),
    scd41_temp_c_cal NUMERIC(5, 2),
    sen55_pm10_0_ugpm3 NUMERIC(6, 2),
    sen55_pm1_0_ugpm3 NUMERIC(6, 2),
    sen55_pm2_5_ugpm3 NUMERIC(6, 2),
    sen55_pm4_0_ugpm3 NUMERIC(6, 2),
    sen55_rh NUMERIC(5, 2),
    sen55_temp_c NUMERIC(5, 2),
    sen55_temp_c_cal NUMERIC(5, 2),
    shtc3_rh NUMERIC(5, 2),
    shtc3_temp_c NUMERIC(5, 2),
    shtc3_temp_c_cal NUMERIC(5, 2)
);

-- NOTE: eventually need a deployment table to store deployment metadata (ie, location, point of contact, etc.)
-- NOTE: an event table to store diagnostic debug packet (ie, event_reason, WiFi, System)

SELECT create_hypertable('sensor_data', 'time');

CREATE UNIQUE INDEX idx_sensor_data_device_counter ON sensor_data (device_id, data_counter DESC, time DESC);

-- optimization
-- ALTER TABLE sensor_data SET (
--     timescaledb.compress,
--     timescaledb.compress_segmentby = 'device_id',
--     timescaledb.compress_orderby = 'time DESC'
-- );

-- -- Automatically compress data older than 7 days
-- SELECT add_compression_policy('sensor_data', INTERVAL '7 days');