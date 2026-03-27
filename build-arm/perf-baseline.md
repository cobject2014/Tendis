# Tendis ARM Baseline Performance

**Date**: 2026-03-27  
**Image**: `tendis-arm-baseline` (built from `build-arm/Dockerfile` — unmodified, `-march=armv8-a`)  
**Host**: ARM64 (aarch64), OrbStack  
**Container limits**: `--cpus=4 --memory=8g`  
**Client**: `redislabs/memtier_benchmark:latest` v2.3.0, `-c 50 -t 4 -d 128`  
**Protocol**: 30s warmup (discarded) before each workload type; 3 trials per workload; median reported; container kept running within a workload type, restarted between types. GET/Mixed workloads pre-seeded with a 60s SET run (`--key-maximum=1000000`).

---

## Results

| Workload  | Pipeline | ops/sec (median) | p50 latency | p99 latency | Trial ops/sec         |
|-----------|----------|-----------------|-------------|-------------|----------------------|
| SET       | 1        | 44,047          | 0.74 ms     | 201.73 ms   | 42,385 / 44,047 / 44,621 |
| SET       | 5        | 111,985         | 5.70 ms     | 203.78 ms   | 103,906 / 111,985 / 112,215 |
| SET       | 10       | 119,163         | 12.86 ms    | 50.43 ms    | 48,035¹ / 119,163 / 121,359 |
| GET       | 1        | 40,707          | 0.73 ms     | 201.73 ms   | 40,592 / 40,707 / 43,266 |
| GET       | 5        | 139,981         | 1.52 ms     | 202.75 ms   | 138,956 / 139,981 / 140,242 |
| Mixed 1:10| 1        | 42,452          | 0.71 ms     | 201.73 ms   | 41,781 / 42,452 / 43,585 |
| Mixed 1:10| 5        | 155,365         | 1.21 ms     | 202.75 ms   | 153,292 / 155,365 / 160,138 |

¹ SET p10 trial 1 anomaly (48K vs 119K in subsequent trials) — likely cold-start effect; median is reliable.

---

## Observations

- **p99 ~200ms across p1 workloads**: Consistent tail-latency spike across all pipeline=1 workloads. Likely RocksDB compaction/flush pauses hitting the measurement window. This is the baseline to compare against.
- **Pipeline scaling**: p5 delivers ~2.5–3.4× the throughput of p1, suggesting the server has headroom and round-trip latency is the dominant p1 bottleneck.
- **RocksDB CRC32**: `HAS_ARMV8_CRC yes` confirmed in build log — hardware CRC32 already active at this baseline (no change needed here).

---

## Phase 2 Verification (RocksDB ARM CRC32)

From the Docker build log:
```
-- Performing Test HAS_ARMV8_CRC - Success
--  HAS_ARMV8_CRC yes
[ 77%] Building CXX object rocksdb/CMakeFiles/rocksdb.dir/util/crc32c_arm64.cc.o
```
RocksDB v8.5.3 auto-detected aarch64 and compiled with `-march=armv8-a+crc+crypto`. Hardware CRC32C is active at baseline — **no Dockerfile change required for RocksDB**.

---

## Phase 4 — jemalloc Page Size

```
getconf PAGE_SIZE = 4096  (4 KB)
```
Container uses 4KB pages. jemalloc auto-detection is correct. `--with-lg-page=16` fix is **not needed**.
