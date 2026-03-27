# Review of `perf-optimization-plan.md`

## Summary

The plan is directionally reasonable, but it is not execution-safe yet. The main issues are:

- it does not keep the optimized build path and the mandatory test path in sync
- it contaminates the baseline with non-ARM config tuning
- its benchmark method is too weak to support small ARM-specific conclusions
- some validation steps do not actually prove the intended optimization is active
- jemalloc page-size work is prioritized too early without first verifying the environment

## Findings

### 1. Release and test build paths are not kept in sync

The plan says to change `-march=armv8-a` to `-march=armv8-a+crc+crypto` in the Dockerfile, but it only names the release Dockerfile.

- Plan reference: `build-arm/perf-optimization-plan.md`, Phase 2.1
- Actual release build path: `build-arm/Dockerfile`
- Actual test build path: `build-arm/Dockerfile.test`

This matters because the task requires full regression testing for every major change. If the ARM flag is updated only in the release image but not in the test image, benchmarking and validation will be done against different binaries.

Recommendation:

- any compiler-flag change must be applied to both `build-arm/Dockerfile` and `build-arm/Dockerfile.test`
- better, factor the ARM flag into one shared build argument or one shared patch point so the two files cannot drift

### 2. The proposed baseline is not a true baseline

The task says to use the current ARM Tendis container as the test target and focus only on ARM-specific optimizations.

However, the plan adds:

- "Prepare a standard `tendisplus.conf` tuned for 4-core / 8G"

before baseline measurement.

That changes more than the architecture-specific behavior. It mixes baseline collection with config tuning, which is explicitly outside the intended scope of this task.

Recommendation:

- baseline should use the current ARM image and current config, with only the required container resource limits applied
- if config experiments are ever run, record them separately and do not mix them into the ARM baseline

### 3. Benchmark methodology is too light for this task

The proposed memtier commands are a reasonable start, but the plan does not specify:

- warm-up runs
- repeated trials
- reset or refill policy between workloads
- variance handling
- how CPU and memory are sampled in a repeatable way

This repo already contains benchmark automation that handles preheat and workload orchestration:

- `performance_test_tools/auto_test_tools/startAll.sh`
- `performance_test_tools/pipeline_automation_tools/benchmark_ver_release.sh`

Those scripts are not a drop-in fit for this ARM task, but they show the level of measurement discipline the plan should adopt.

Recommendation:

- add one short warm-up before each measured run
- run each workload at least 3 times and report median or best-with-variance
- define whether data is reused or the server is reset between SET, GET, and mixed tests
- capture resource metrics with a fixed method, not ad hoc `docker stats` observation

### 4. CRC verification is not strong enough

The plan proposes:

- `objdump -d tendisplus | grep crc32`

That only proves some CRC instruction exists somewhere in the final binary. It does not prove:

- RocksDB’s CRC32C hot path is the one actually selected
- the target codepath is exercised by Tendis
- the performance gain is measurable in relevant workloads

Recommendation:

- verify the RocksDB ARM CRC32C source path and compile definitions directly
- then validate with workload data that is plausibly checksum-sensitive
- treat disassembly as a supporting check, not the primary proof

### 5. jemalloc page-size work is ranked too early

The plan correctly notes that page size should be checked first, but still ranks the jemalloc page-size item as high impact before that check is done.

In this fork, jemalloc is built by the native Ubuntu ARM build flow through CMake. That makes the page-size concern worth checking, but not strong enough yet to rank as a top-priority optimization without evidence.

Recommendation:

- first record `getconf PAGE_SIZE` inside the actual benchmark container
- only pursue `--with-lg-page=16` if the environment really uses 64 KB pages or memory behavior clearly indicates a jemalloc mismatch
- otherwise keep this item as conditional, not a default priority-4 action

## Recommended changes to the plan

1. Baseline first with the current ARM image and current config, only enforcing `--cpus=4 --memory=8g`.
2. Add a benchmark protocol section covering warm-up, repeats, reset policy, and result reporting.
3. Require every compiler/build optimization to be mirrored in both ARM Dockerfiles.
4. Split validation into:
   - build-time/source verification
   - full regression tests
   - benchmark comparison
5. Gate jemalloc page-size work on actual measured environment data.

## Verdict

The plan is useful as a first draft, but it should be revised before execution. The highest-value fixes are:

- make release and test build paths consistent
- keep the baseline clean
- strengthen the measurement methodology
