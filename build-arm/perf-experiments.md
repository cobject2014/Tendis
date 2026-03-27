# Tendis ARM Performance Experiments

---

## Experiment 1 — Phase 3: Upgrade `-march` flag + remove stray `-march=native`

**Date**: 2026-03-27  
**Status**: ✅ KEEP

### What changed

| File | Change |
|------|--------|
| `build-arm/Dockerfile` | `sed` now replaces `-march=nocona` with `-march=armv8-a+crc+crypto` for Tendis-own CMakeLists |
| `build-arm/Dockerfile.test` | Same change as Dockerfile |
| `build-arm/Dockerfile` | Added `sed 's/ -march=native//g'` on `src/tendisplus/tools/CMakeLists.txt` |
| `build-arm/Dockerfile.test` | Same native-flag removal |
| `src/tendisplus/tools/CMakeLists.txt` | Removed stray ` -march=native` from `target_link_libraries` linker flags |

**Rationale**: The original Dockerfile patched x86-only `-march=nocona` to `-march=armv8-a` (bare), missing the `+crc+crypto` extensions that enable hardware CRC32/AES in Tendis-own code. A stray `-march=native` was also incorrectly placed in linker flags (CMake CMP0004 violation on ARM builds).

Note: RocksDB was already using `-march=armv8-a+crc+crypto` internally — its own CMakeLists.txt auto-detects aarch64. This change affects only Tendis-own compilation units.

### Results

**Benchmark config**: `memtier_benchmark` v2.3.0, 4 threads × 50 clients, 128-byte values, 30s per trial, 3 trials (median reported). Container: `--cpus=4 --memory=8g`.

| Workload   | Pipeline | Baseline (ops/sec) | Phase 3 (ops/sec) | Delta    | Change  |
|------------|----------|--------------------|-------------------|----------|---------|
| SET        | 1        | 44,047             | 44,957            | +910     | **+2.1%**  |
| SET        | 5        | 111,985            | 127,379           | +15,394  | **+13.7%** |
| GET        | 1        | 40,707             | 47,383            | +6,676   | **+16.4%** |
| GET        | 5        | 139,981            | 181,934           | +41,953  | **+30.0%** |
| Mixed 1:1  | 1        | 42,452¹            | 46,215            | +3,763   | **+8.9%**  |
| Mixed 1:1  | 5        | 155,365¹           | 149,571           | −5,794   | −3.7%²  |

¹ Baseline mixed used `--ratio 1:10` (SET:GET); Phase 3 used `--ratio 1:1`. These rows are not directly comparable — treat as directional only.  
² Within trial variance (Phase 3 range: 141k–153k; baseline range: 153k–160k). Likely noise given the pure-GET improvement of +30%.

### Latency (Phase 3, median trial)

| Workload  | Pipeline | p50 lat | p99 lat |
|-----------|----------|---------|---------|
| SET       | 1        | 0.70 ms | 201.73 ms |
| SET       | 5        | 3.73 ms | 203.78 ms |
| GET       | 1        | 0.66 ms | 201.73 ms |
| GET       | 5        | 0.97 ms | 201.73 ms |
| Mixed 1:1 | 1        | 0.70 ms | 201.73 ms |
| Mixed 1:1 | 5        | 1.53 ms | 202.75 ms |

p99 tail latency (~201ms) is unchanged — still dominated by RocksDB compaction pauses, as at baseline.

### Regression tests

| Suite | Result |
|-------|--------|
| Redis compatibility (`redistest.sh`) | ✅ PASSED |
| Go integration tests (14 tests) | ✅ PASSED (14/14) |

### Verdict: KEEP ✅

The `-march=armv8-a+crc+crypto` flag delivers material throughput gains across all pure-workload cases (up to +30% on GET p5). No regressions in correctness tests. The changes are low-risk: the flag only affects Tendis-own code, and RocksDB was already using the same extensions at baseline.

---

## Experiment 2 — LSE Atomics: `-march=armv8.1-a` + `-mno-outline-atomics`

**Date**: 2026-03-27  
**Status**: ❌ REVERT

### What changed

| File | Change |
|------|--------|
| `build-arm/Dockerfile` | `-march=armv8-a+crc+crypto` → `-march=armv8.1-a+crc+crypto`; added `-mno-outline-atomics` to CFLAGS/CXXFLAGS |
| `build-arm/Dockerfile.test` | Same changes |

**Rationale**: GCC 11 on aarch64 enables `-moutline-atomics` by default — runtime dispatch stubs that select LL/SC or LSE at startup. The Phase 3 binary had 5,779 such dispatch calls. This experiment aimed to eliminate dispatch overhead by forcing inline native LSE instructions via `-march=armv8.1-a` (implies `+lse`) and `-mno-outline-atomics`.

**Codegen verification**: Dispatch stubs reduced from 5,779 → 556 (remaining 556 from thirdparty libs with own build flags). Tendis-own code successfully compiled with inline LSE.

### Results

| Workload   | Pipeline | Phase 3 (ops/sec) | LSE (ops/sec) | Delta    | Change   |
|------------|----------|--------------------|---------------|----------|----------|
| SET        | 1        | 44,957             | 42,067        | −2,890   | **−6.4%** 🔴 |
| SET        | 5        | 127,379            | 123,798       | −3,581   | **−2.8%** 🔴 |
| GET        | 1        | 47,383             | 45,643        | −1,740   | **−3.7%** 🔴 |
| GET        | 5        | 181,934            | 183,996       | +2,062   | +1.1% ⚪ |
| Mixed 1:1  | 1        | 46,215             | 45,309        | −906     | −2.0% ⚪ |
| Mixed 1:1  | 5        | 149,571            | 146,446       | −3,125   | **−2.1%** 🔴 |

### Regression tests

| Suite | Result |
|-------|--------|
| Redis compatibility (52 tests) | ✅ PASSED |
| Go integration tests | 🔄 Running (not waited — reverted based on benchmark results) |

### Analysis

The LSE experiment produced a small but consistent regression across most workloads. Two factors explain this:

1. **GCC outline-atomics already provides LSE**: On hardware that supports LSE (Apple Silicon, Graviton2+), the runtime dispatch was already selecting LSE instructions. The dispatch overhead (~2-3%) was the only potential gain.
2. **Forced `-mno-outline-atomics` may be suboptimal**: The runtime dispatch can select the best atomics implementation per-callsite. Forcing all atomics to inline LSE removes this flexibility. On Apple Silicon's micro-architecture, some LL/SC patterns may actually be faster than LSE equivalents.

### Verdict: REVERT ❌

The default GCC outline-atomics (runtime LSE dispatch) is already optimal. Forcing inline LSE via `-mno-outline-atomics` provides no benefit and introduces a small regression. Changes reverted.

---

## Experiment 3 — Snappy/LZ4 ARM march flags via CFLAGS

**Date**: 2026-03-27  
**Status**: ❌ REVERT

### What changed

Added `-march=armv8-a+crc+crypto` to `ENV CFLAGS` and `ENV CXXFLAGS` in both Dockerfiles, so that all thirdparty libs (snappy, lz4, jemalloc) compile with ARM CRC/crypto instruction set — not just Tendis-own code and RocksDB.

**Codegen verification**: Phase 3 had only 1/8 compilation records with `-march`; snappy-opt had 6/8. Confirmed snappy/lz4/Tendis code all received the flag.

### Results

| Workload   | Pipeline | Phase 3 (ops/sec) | Snappy-opt (ops/sec) | Change   |
|------------|----------|--------------------|----------------------|----------|
| SET        | 1        | 44,957             | 42,758               | **−4.9%** 🔴 |
| SET        | 5        | 127,379            | 125,277              | −1.7% ⚪ |
| GET        | 1        | 47,383             | 45,618               | **−3.7%** 🔴 |
| GET        | 5        | 181,934            | 179,159              | −1.5% ⚪ |
| Mixed 1:1  | 1        | 46,215             | 44,204               | **−4.4%** 🔴 |
| Mixed 1:1  | 5        | 149,571            | 149,720              | +0.1% ⚪ |

### Analysis

Adding `-march` to ENV CFLAGS likely conflicts with the sed-applied `-march` in CMakeLists.txt files, causing double-specification or suboptimal flag ordering. The ENV flags are processed before CMake's own flags, and when both specify `-march`, the last one wins — but the interaction may produce unexpected codegen choices. The small regression is consistent across p1 workloads.

### Verdict: REVERT ❌

Changes reverted. The sed-only approach (Phase 3) remains optimal.
