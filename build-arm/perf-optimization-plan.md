# Tendis ARM Performance Optimization Plan

## Overview

The current ARM build replaces x86-specific flags (`-mno-avx`, `-mno-avx2`, `-march=nocona`) with a generic `-march=armv8-a` and `-O3`. This gets the build working but leaves ARM-specific hardware acceleration unused. General optimizations (LTO, PGO, config tuning, etc.) are assumed already handled by Tendis upstream — this plan focuses **only on ARM-specific gaps**.

---

## Phase 1: Baseline Measurement

### 1.1 Setup benchmarking environment
- [ ] Build current ARM Tendis image from `build-arm/Dockerfile`
- [ ] Run container with resource limits: `docker run --cpus=4 --memory=8g`
- [ ] Install `memtier_benchmark` in a separate client container (or on host)
- [ ] Prepare a standard `tendisplus.conf` tuned for 4-core / 8G

### 1.2 Run baseline benchmarks
- [ ] **SET workload**: `memtier_benchmark -s <host> -p 6379 --test-time=120 --ratio=1:0 -d 128 --pipeline=1 -c 50 -t 4`
- [ ] **GET workload**: `memtier_benchmark -s <host> -p 6379 --test-time=120 --ratio=0:1 -d 128 --pipeline=1 -c 50 -t 4`
- [ ] **Mixed workload (1:10)**: `memtier_benchmark -s <host> -p 6379 --test-time=120 --ratio=1:10 -d 128 --pipeline=1 -c 50 -t 4`
- [ ] **Pipeline benchmark**: repeat above with `--pipeline=10` and `--pipeline=50`
- [ ] Record: ops/sec, avg latency, p99 latency, CPU usage (`docker stats`)
- [ ] Save results to `build-arm/perf-baseline.md`

---

## Phase 2: ARM Compiler Target (High impact)

### 2.1 Upgrade `-march` to enable ARM hardware acceleration
- [ ] Change `-march=armv8-a` → `-march=armv8-a+crc+crypto` in Dockerfile
  - Enables **hardware CRC32** instructions (ARM equivalent of x86 SSE4.2 CRC)
  - Enables **hardware AES** instructions (ARM equivalent of x86 AES-NI)
- [ ] RocksDB uses CRC32 heavily for checksums — hardware CRC can yield **2-5x** CRC speedup
- [ ] If targeting specific hardware (e.g., AWS Graviton2/3), consider:
  - `-march=armv8.2-a+crc+crypto+fp16+dotprod`
  - or `-mcpu=neoverse-n1`
- [ ] **Verify**: `objdump -d tendisplus | grep crc32` should show hardware CRC instructions (not software fallback)

---

## Phase 3: RocksDB ARM Hardware Codepaths

### 3.1 Verify ARM CRC32C is active in RocksDB (High impact)
- [ ] On x86, RocksDB uses `HAVE_SSE42` to enable hardware CRC32C via `_mm_crc32_*` intrinsics
- [ ] For ARM, RocksDB needs `HAVE_ARM64_CRC` (or auto-detection via `__ARM_FEATURE_CRC32`)
- [ ] Check `util/crc32c.cc` in the RocksDB v8.5.3 source — verify it has an ARM CRC path
- [ ] The v8.5.3 RocksDB should auto-detect if compiled with `-march=armv8-a+crc`, but verify this works
- [ ] If not auto-detected, manually define `-DHAVE_ARM64_CRC` in CMake

### 3.2 Verify ARM-specific runtime code paths
- [ ] `AsmVolatilePause()` uses `wfe` on aarch64 — **correct** (x86 equivalent: `pause`)
- [ ] `CACHE_LINE_SIZE` = 128 for aarch64 — **correct** (x86 uses 64)
- [ ] `xxhash.cc` checks `__ARM_FEATURE_UNALIGNED` for unaligned access — verify this is set by the compiler with our `-march` flags
- [ ] Check if any x86-only SIMD paths (SSE/AVX) in Tendis source have no ARM NEON fallback

---

## Phase 4: jemalloc ARM Page Size (High impact)

### 4.1 Fix page size configuration
- [ ] ARM Linux commonly uses **64KB pages** (vs 4KB on x86)
- [ ] jemalloc compiled with wrong page size assumption causes **massive memory overhead** — this is a well-known ARM pitfall
- [ ] **Check**: run `getconf PAGE_SIZE` inside the container to determine actual page size
- [ ] If 64KB: configure jemalloc with `--with-lg-page=16` in the autogen step
- [ ] If 4KB (standard): no change needed, but verify jemalloc auto-detects correctly
- [ ] The current jemalloc build in CMakeLists.txt calls `./autogen.sh --enable-prof` without any page size flag — this relies on build-time detection, which may be **wrong in cross-compilation or Docker buildx**

---

## Phase 5: Regression Testing

Per project constraints, **every major change must pass the full test suite** before being accepted.

### Regression test procedure
- [ ] After each optimization change, rebuild the test image: `docker build -t tendis-test -f build-arm/Dockerfile.test .`
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

| Priority | Item | Expected Impact | Risk | Why ARM-specific |
|----------|------|----------------|------|------------------|
| 1 | Baseline measurement (Phase 1) | prerequisite | None | — |
| 2 | `-march=armv8-a+crc+crypto` (2.1) | High | Low | Enables ARM CRC32/AES hardware (x86 has SSE4.2/AES-NI) |
| 3 | RocksDB ARM CRC32C verify (3.1) | High | Low | x86 uses SSE4.2 CRC; ARM needs its own codepath |
| 4 | jemalloc page size fix (4.1) | High | Low | ARM uses 64KB pages; x86 uses 4KB |
| 5 | ARM runtime codepath audit (3.2) | Low-Medium | Low | Verify wfe/cache-line/unaligned access correctness |
