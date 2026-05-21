-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- 1. Device Metadata Table
-- Tracks physical hardware and its current logical assignment.
CREATE TABLE devices (
    device_id TEXT PRIMARY KEY,          -- MAC Address (e.g., 'A4:C1:38:7B:92:11')
    deployment_id TEXT NOT NULL,         -- Logical ID (e.g., 'dep_D7kP3zQ9mXaL2vRb')
    device_name TEXT,                    -- Human readable name (e.g., 'IAQ0014')
    device_type TEXT,                    -- Hardware model (e.g., 'IAQ-SEN66-NOX')
    hardware_ver TEXT,
    firmware_ver TEXT,
    timezone TEXT DEFAULT 'UTC',         -- For frontend normalization
    point_of_contact TEXT,               -- Deployment metadata
    sampling_interval_sec INTEGER DEFAULT 60,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Sensor Data Table (Hypertable)
-- Stores the high-frequency IAQ metrics.
CREATE TABLE sensor_data (
    time TIMESTAMPTZ NOT NULL,           -- Derived from device_timestamp_ms (for partitioning)
    server_time TIMESTAMPTZ DEFAULT NOW(),-- When the record was actually received
    device_id TEXT NOT NULL REFERENCES devices(device_id),
    deployment_id TEXT NOT NULL,         -- Denormalized for easier historical querying
    data_counter BIGINT NOT NULL,        -- Monotonic counter for HWM tracking
    device_timestamp_ms BIGINT NOT NULL, -- Original device wall-clock time
    boot_id TEXT,                        -- Tracks data across reboots
    boot_counter INTEGER,
    uptime_sec INTEGER,
    wifi_rssi_dbm INTEGER,
    
    -- Sensor Metrics (mapped from IAQ-sensor-layout.md)
    nox_index INTEGER,                   -- NOXindex_0-500
    voc_index INTEGER,                   -- VOCindex_0-500
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

-- Convert to hypertable for time-series optimization
SELECT create_hypertable('sensor_data', 'time');

-- Unique constraint to ensure monotonicity and prevent duplicate data ingestion
-- The DESC index makes 'MAX(data_counter)' lookups for HWM extremely efficient.
CREATE UNIQUE INDEX idx_sensor_data_device_counter ON sensor_data (device_id, data_counter DESC);
