# Telemetry Ingest — Compact Design Document (In-Order Batches)

## Goal

Lossless, low-latency ingest of time-series sensor data with live streaming when connected and automatic backfill after outages or restarts. We achieve at-least-once delivery on the wire and exactly-once in storage through idempotent keys and a prefix-over-observed-sequence high-water mark (HWM) using in-order batches per stream.

- Stream identity: `(device_id, stream_id, boot_id)`
- Monotonic position within a boot: `tick_ms` = floor(monotonic time since boot in ms)
- Idempotent primary key: `(device_id, stream_id, boot_id, tick_ms)`
- Two notions of time: `ts_device` (event time from device clock) and `ts_ingested` (server arrival)

### In-Order Batches (simple mode)

For each `(device_id, stream_id, boot_id)`:

- Device sends batches strictly in tick order, with rows sorted by `tick_ms`.
- Device keeps at most one batch in flight; it waits for the server response before sending the next batch.
- Server sets `ack_tick` to the maximum `tick_ms` in the accepted batch (i.e., the last sample now known durable) and never requires “dense +1” contiguity; this permits jitter in the timestamps and avoids annoying bookeeping around logical timestamps

This makes HWM a prefix over the **transmission order** guaranteed by the device, not over every integer time step.

## Data Structures

### On the Device (local WAL)

- Table: `wal` — durable append-only log of samples until acknowledged by the server.
  - `device_id TEXT`
  - `stream_id TEXT`
  - `boot_id   TEXT` — new UUID each process start (or real device boot)
  - `tick_ms   INTEGER` — floor(monotonic time since boot, ms); strictly increasing per `(stream_id, boot_id)`
  - `value     REAL`
  - `ts_device REAL` — seconds since epoch (device wall clock; may drift or be absent)
  - `sent      INTEGER` — transient (0/1); deleted after ack
  - PK: `(device_id, stream_id, boot_id, tick_ms)`

Behavior

- Every sample is inserted into `wal`.
- Flush loop selects unsent rows where `tick_ms > ack_tick` (ordered), sends **one ordered batch**, waits for the response, then deletes rows `<= ack_tick`.

### On the Server

- Table: `streams` — per-stream cursors & watermarks
  - `device_id TEXT`, `stream_id TEXT`, `boot_id TEXT`
  - `ack_tick INTEGER DEFAULT -1` — HWM over **observed ordered samples** (last durable sample)
  - `max_seen INTEGER DEFAULT -1` — largest `tick_ms` ever seen (for stats/visibility)
  - `hwm_event_time REAL` — best-known event-time watermark (seconds since epoch) over acked rows
  - PK: `(device_id, stream_id, boot_id)`

- Table: `records` — canonical telemetry store (idempotent upserts)
  - `device_id TEXT`, `stream_id TEXT`, `boot_id TEXT`, `tick_ms INTEGER`
  - `value REAL`, `ts_device REAL`, `ts_ingested REAL`
  - PK: `(device_id, stream_id, boot_id, tick_ms)`
  - Indexes: `(device_id, stream_id, boot_id)` and optionally `(device_id, stream_id, ts_device)`

- Table: `anchors` — optional mapping from ticks to wall clock
  - `id INTEGER PK AUTOINCREMENT`
  - `device_id TEXT`, `stream_id TEXT`, `boot_id TEXT`
  - `tick_ms INTEGER`, `server_time REAL` — used to estimate event time when `ts_device` is missing

Record shape (over the wire)

```json
{
  "device_id": "dev1",
  "stream_id": "stream1",
  "boot_id": "d1c2-…",
  "tick_ms": 125000,
  "value": 22.7,
  "ts_device": 1723568032.512
}
```

---

## Backend Implementation

### API

- `POST /v1/hello`
  - Body: `{ device_id, stream_id, boot_id, tick_anchor_ms }`
  - Action: ensure `streams` row exists; insert `anchors(device_id, stream_id, boot_id, tick_anchor_ms, now())`.
  - Response: `{ ack_tick, max_seen }`

- `POST /v1/batch`
  - Body: `{ device_id, stream_id, boot_id, start_tick_ms, end_tick_ms, records:[...] }`
  - Device contract for **in-order mode**:
    - `records` sorted by `tick_ms`
    - `start_tick_ms > ack_tick` (device fetched cursor just before)
    - at most one in-flight batch per `(device_id, stream_id, boot_id)`
  - Server action:
    1. Upsert `records` into `records` (INSERT OR IGNORE by PK), set `ts_ingested=now()`.
    2. Update `max_seen = max(max_seen, end_tick_ms)`.
    3. Set `ack_tick = max(ack_tick, max_tick_ms_in_batch)` because the device guarantees order and single in-flight batch.
    4. Update `hwm_event_time` as the maximum `ts_device` among acked rows; if missing/unreliable, estimate using the last anchor:
       `ts_event ≈ server_time_anchor + (tick_ms - tick_anchor_ms)/1000.0`.
  - Response: `{ acked_through_tick_ms: ack_tick, hwm_event_time }`
  - Optional server safety: if `start_tick_ms <= ack_tick`, either accept (duplicates no-op) or return `409 Conflict` to signal protocol violation.

- `GET /v1/cursor?device_id=&stream_id=&boot_id=`
  - Response: `{ ack_tick, max_seen }`

- `GET /v1/state`
  - Response: summary across streams (counts, cursors, watermarks)

### HWM (prefix over observed sequence)

- Server advances `ack_tick` to the **largest tick in the accepted batch**.
- Out-of-order arrivals are avoided by the device rule (in-order, single in-flight); duplicates do not advance HWM but are harmless.
- `hwm_event_time` tracks max event-time among acked ticks.

### Storage Guarantees

- Exactly-once in storage: PK-based idempotent upserts; retries are free.
- Provenance: keep both `ts_device` and `ts_ingested`.
- Late data is fine: ordering relies on `(boot_id, tick_ms)`, not timestamps.

---

## Sensor (Device) Implementation

### Lifecycle

1. Boot: create new `boot_id` (UUID).
2. Hello: for each stream, `POST /v1/hello` with `tick_anchor_ms=0` (records an anchor).
3. Sampling (per stream):
   - Compute `value`.
   - Set `tick_ms = floor(monotonic_time_since_boot_ms())`.
   - Set `ts_device = now()` (if available).
   - Insert into local `wal` with composite PK.
4. Flush Loop (per stream):
   - `GET /v1/cursor` → `ack_tick`.
   - Select next **ordered** batch where `tick_ms > ack_tick`.
   - `POST /v1/batch` with that batch (only one in flight).
   - On response, delete local rows `<= acked_through_tick_ms`.
   - Repeat until no progress; sleep briefly.

### Resilience

- If either process is killed, no data is lost:
  - Device persists all samples in `wal` until acknowledged and deleted.
  - Server ignores duplicate inserts due to PK.
  - On restart, device uses a new `boot_id` for new samples but still flushes any unsent rows from old boots (since `wal` rows carry original `boot_id`).

### Irregular / Jittery Sampling

- Irregular cadence is naturally supported because `tick_ms` comes from a monotonic clock at sample time; gaps in `tick_ms` are expected and harmless.
- HWM is tied to the last acknowledged sample **by order**, not to a dense grid.

---

## Minimal Schemas (DDL excerpts)

Device (SQLite)

```sql
CREATE TABLE IF NOT EXISTS wal (
  device_id  TEXT NOT NULL,
  stream_id  TEXT NOT NULL,
  boot_id    TEXT NOT NULL,
  tick_ms    INTEGER NOT NULL,
  value      REAL,
  ts_device  REAL NOT NULL,
  sent       INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (device_id, stream_id, boot_id, tick_ms)
);

CREATE TABLE IF NOT EXISTS meta (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL
);
```

Server (SQLite)

```sql
CREATE TABLE IF NOT EXISTS streams (
  device_id TEXT NOT NULL,
  stream_id TEXT NOT NULL,
  boot_id   TEXT NOT NULL,
  ack_tick  INTEGER NOT NULL DEFAULT -1,
  max_seen  INTEGER NOT NULL DEFAULT -1,
  hwm_event_time REAL,
  PRIMARY KEY (device_id, stream_id, boot_id)
);

CREATE TABLE IF NOT EXISTS records (
  device_id TEXT NOT NULL,
  stream_id TEXT NOT NULL,
  boot_id   TEXT NOT NULL,
  tick_ms   INTEGER NOT NULL,
  value     REAL,
  ts_device REAL,
  ts_ingested REAL NOT NULL,
  PRIMARY KEY (device_id, stream_id, boot_id, tick_ms)
);

CREATE TABLE IF NOT EXISTS anchors (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id TEXT NOT NULL,
  stream_id TEXT NOT NULL,
  boot_id   TEXT NOT NULL,
  tick_ms   INTEGER NOT NULL,
  server_time REAL NOT NULL
);
```

---

## Why This Works

- Deterministic resume via `(boot_id, tick_ms)`; no timestamp ambiguity.
- Idempotent storage with composite PK; retries are no-ops.
- Clear HWM equals “last sample durably stored given ordered transmission,” enabling clean late-data handling without assuming fixed sample period.
- Simple ops: both sides are SQLite-backed; easy to swap server DB for Postgres/Timescale later without logic changes.
- Irregular sampling is first-class: `tick_ms` reflects actual capture time from a monotonic clock; order is preserved by the in-order batch rule.
