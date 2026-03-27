# Tendis ARM Performance Optimization Plan

## Overview

The current ARM build replaces x86-specific flags (`-mno-avx`, `-mno-avx2`, `-march=nocona`) with a generic `-march=armv8-a` and `-O3`. This gets the build working but leaves ARM-specific hardware acceleration partially unused in **Tendis's own code**.

However, **RocksDB v8.5.3 handles ARM optimization internally** — its CMakeLists.txt (lines 232-239) auto-detects aarch64 and adds `-march=armv8-a+crc+crypto` for its own compilation. This means:
- RocksDB CRC32C hardware acceleration is **likely already active** without any Dockerfile change
- The Dockerfile's sed (`-march=nocona` → `-march=armv8-a`) only affects CMakeLists.txt files that contain `-march=nocona` — which is Tendis's own code, **not** RocksDB's

General optimizations (LTO, PGO, config tuning, etc.) are assumed already handled by Tendis upstream — this plan focuses **only on ARM-specific gaps**.

### Build path rule

Every compiler or build flag change **must be applied to both**:
- `build-arm/Dockerfile` (release image)
- `build-arm/Dockerfile.test` (test image)

To prevent drift, factor shared ARM flags into a Docker build argument:
```dockerfile
ARG ARM_MARCH_FLAGS="-march=armv8-a+crc+crypto"
# used in the sed replacement and ENV CXXFLAGS lines
```

### Known stray x86 flags

- [src/tendisplus/tools/CMakeLists.txt](../src/tendisplus/tools/CMakeLists.txt) line 2 contains `-march=native` hardcoded in link flags — this is not caught by the current sed and may cause issues or suboptimal codegen on ARM

---

## Phase 1: Baseline Measurement

### 1.1 Setup benchmarking environment
- [ ] Build current ARM Tendis image from `build-arm/Dockerfile` — **no modifications**
- [ ] Run container with resource limits: `docker run --cpus=4 --memory=8g`
- [ ] Use the **existing `tendisplus.conf`** shipped in the image — do not tune it
- [ ] Install `memtier_benchmark` in a separate client container (or on host)

### 1.2 Benchmark protocol
- [ ] **Warm-up**: before each measured workload, run a 30-second warm-up with the same command (results discarded)
- [ ] **Trials**: run each workload **3 times**; report **median ops/sec** and note min/max
- [ ] **Reset policy**: restart the Tendis container between workload types (SET → GET → mixed); within a workload's 3 trials, keep the server running
- [ ] **Data seeding**: before GET-only and mixed workloads, pre-seed with a SET run (e.g., `memtier_benchmark --ratio=1:0 --key-maximum=1000000 -d 128 -c 50 -t 4 --test-time=60`) to populate data; this seeding run is not measured
- [ ] **Resource capture**: record CPU and memory via `docker stats --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}"` at 10-second intervals during the run, using a background script; do not rely on ad-hoc observation

### 1.3 Run baseline benchmarks
- [ ] **SET workload**: `memtier_benchmark -s <host> -p 6379 --test-time=120 --ratio=1:0 -d 128 --pipeline=1 -c 50 -t 4`
- [ ] **GET workload**: `memtier_benchmark -s <host> -p 6379 --test-time=120 --ratio=0:1 -d 128 --pipeline=1 -c 50 -t 4`
- [ ] **Mixed workload (1:10)**: `memtier_benchmark -s <host> -p 6379 --test-time=120 --ratio=1:10 -d 128 --pipeline=1 -c 50 -t 4`
- [ ] **Pipeline benchmark**: repeat above with `--pipeline=10` and `--pipeline=50`
- [ ] Record: ops/sec (median of 3), avg latency, p99 latency, CPU%, memory
- [ ] Save results to `build-arm/perf-baseline.md`

---

## Phase 2: Verify RocksDB ARM CRC32 (verify-only, likely already working)

RocksDB v8.5.3's own CMakeLists.txt adds `-march=armv8-a+crc+crypto` when it detects aarch64. This should make hardware CRC32C active without any change on our side. This phase **verifies** that assumption.

### 2.1 Source-level verification (done — results recorded here)
- [x] `src/thirdparty/rocksdb/rocksdb/CMakeLists.txt` lines 232-239: checks `CMAKE_SYSTEM_PROCESSOR` for `arm64|aarch64|AARCH64`, then adds `-march=armv8-a+crc+crypto`
- [x] `src/thirdparty/rocksdb/rocksdb/util/crc32c_arm64.h`: `#ifdef __ARM_FEATURE_CRC32` → defines `HAVE_ARM64_CRC` and maps `crc32c_u64` to `__crc32cd` intrinsic
- [x] `src/thirdparty/rocksdb/rocksdb/util/crc32c.cc` lines 1111-1116: `#elif defined(HAVE_ARM64_CRC)` → selects `ExtendARMImpl` at runtime via `crc32c_runtime_check()`
- [x] `src/thirdparty/rocksdb/rocksdb/util/crc32c_arm64.cc`: runtime check uses `getauxval(AT_HWCAP) & HWCAP_CRC32` on Linux

### 2.2 Build-time verification (to be done inside Docker)
- [ ] Add a build step to print the CMake status message: should show `HAS_ARMV8_CRC yes`
- [ ] `objdump -d tendisplus | grep -c crc32c` as supporting evidence
- [ ] Check RocksDB startup log for the exact string: `Fast CRC32 supported: Supported on Arm64` (failure would show `Fast CRC32 supported: Not supported on Arm64`)

### 2.3 If verification fails
- [ ] If RocksDB's auto-detection doesn't trigger (e.g., Docker buildx cross-compilation confuses `CMAKE_SYSTEM_PROCESSOR`), force the flags via one of these paths (choose one):
  - **Option A — ENV variables** (preferred): append to the existing `CFLAGS` / `CXXFLAGS` lines already in the Dockerfile (which carry `-O3`, `-Wno-error`, `-fpermissive`, `-include cstdint`):
    ```dockerfile
    ENV CFLAGS="${CFLAGS} -march=armv8-a+crc+crypto"
    ENV CXXFLAGS="${CXXFLAGS} -march=armv8-a+crc+crypto"
    ```
    This is safest because the build already depends on those ENV lines; appending preserves all existing flags.
  - **Option B — patch RocksDB's CMakeLists.txt**: add a `sed` in the Dockerfile to force the flag inside RocksDB's own CMakeLists.txt (most surgical, only affects RocksDB)
  - **Option C — cmake command-line**: pass `-DCMAKE_C_FLAGS=...` / `-DCMAKE_CXX_FLAGS=...` to cmake. **Caution**: CMake `-D` cache variables override the `CFLAGS`/`CXXFLAGS` environment variables entirely rather than appending, so the value must include all existing flags (`-O3 -Wno-error ...`) plus the new one — this is fragile and not recommended
  
  All options must be applied to **both** `build-arm/Dockerfile` and `build-arm/Dockerfile.test`

---

## Phase 3: Tendis-own Code ARM Flags

The Dockerfile sed changes `-march=nocona` → `-march=armv8-a` in Tendis's own CMakeLists.txt files. This gives Tendis-authored code (not RocksDB) only the base ARMv8 instruction set, missing CRC32/AES for any Tendis code that might use them.

### 3.1 Upgrade Tendis code march flag
- [ ] Change the sed replacement target from `-march=armv8-a` to `-march=armv8-a+crc+crypto` in **both Dockerfiles**
- [ ] This ensures Tendis's own code can also use hardware CRC/AES if needed
- [ ] Fix the stray `-march=native` in `src/tendisplus/tools/CMakeLists.txt` — add a sed to remove or replace it

### 3.2 Verify ARM-specific runtime code paths
- [ ] `AsmVolatilePause()` uses `wfe` on aarch64 — **correct** (x86 equivalent: `pause`)
- [ ] `CACHE_LINE_SIZE` = 128 for aarch64 — **correct** (x86 uses 64)
- [ ] `xxhash.cc` checks `__ARM_FEATURE_UNALIGNED` — verify this is defined by the compiler with `-march=armv8-a+crc+crypto`
- [ ] Check if any x86-only SIMD paths (SSE/AVX) in Tendis source code (not RocksDB) have no ARM fallback

### 3.3 Validation
1. **Regression tests**: must pass in both Dockerfiles
2. **Benchmark comparison**: run the full benchmark protocol (Phase 1.2) and compare against baseline

---

## Phase 4: jemalloc ARM Page Size (Conditional)

### 4.1 Environment check (must run before any jemalloc change)
- [ ] Run `getconf PAGE_SIZE` inside the **actual benchmark container** and record the result
- [ ] Run `cat /proc/version` to confirm kernel config
- [ ] If page size is **4096 (4KB)**: jemalloc auto-detection is likely correct — skip 4.2, mark this item as resolved
- [ ] If page size is **65536 (64KB)**: proceed to 4.2

### 4.2 Fix page size configuration (only if 4.1 indicates 64KB pages)
- [ ] Configure jemalloc with `--with-lg-page=16` in the autogen step in **both Dockerfiles**
- [ ] jemalloc compiled with wrong page size assumption causes massive memory overhead
- [ ] The current jemalloc build in CMakeLists.txt calls `./autogen.sh --enable-prof` without any page size flag — this relies on build-time detection, which may be wrong in cross-compilation or Docker buildx

---

## Phase 5: Regression Testing

Per project constraints, **every major change must pass the full test suite** before being accepted.

### Regression test procedure
- [ ] After each optimization change, apply the change to **both** `build-arm/Dockerfile` and `build-arm/Dockerfile.test`
- [ ] Rebuild the test image: `docker build -t tendis-test -f build-arm/Dockerfile.test .`
- [ ] Run Redis compatibility tests: `docker run --rm tendis-test /src/Tendis/run_redis_compat_test.sh`
- [ ] Run Go integration tests: `docker run --rm tendis-test /src/Tendis/run_go_integration_test.sh`
- [ ] Only proceed to benchmark if all tests pass
- [ ] If tests fail, revert the change and log the failure

---

## Phase 6: Experiment Tracking

All experiments should be logged in `build-arm/perf-experiments.md` with:
- Date
- What was changed (specific flag/config)
- Benchmark command used
- Results (ops/sec, latency p50/p99)
- Comparison vs baseline
- Test suite result: PASS / FAIL
- Verdict: KEEP / REVERT / INVESTIGATE

---

## Priority Order (recommended execution sequence)

| Priority | Item | Expected Impact | Risk | Notes |
|----------|------|----------------|------|-------|
| 1 | Baseline measurement (Phase 1) | prerequisite | None | Uses current unmodified image |
| 2 | Verify RocksDB CRC32 already works (Phase 2) | Verify only | None | RocksDB v8.5.3 should auto-enable; confirm in Docker build log |
| 3 | Upgrade Tendis-own code `-march` + fix stray `-march=native` (Phase 3) | Low/Unknown until benchmarked | Low | Affects Tendis code only, not in known hot path; treat as hypothesis to test |
| 4 | jemalloc page size check (Phase 4.1) | Conditional | Low | Only matters if container uses 64KB pages |
| 5 | jemalloc page size fix (Phase 4.2) | High if needed | Low | Only if 4.1 confirms 64KB pages |
