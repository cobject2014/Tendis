# Round 2 Review of `perf-optimization-plan.md`

## Summary

The updated plan is substantially better than the previous version. It fixes the main earlier issues:

- it now keeps release and test build paths aligned
- it keeps the baseline clean by using the current image and config
- it defines a more credible benchmark protocol
- it correctly recognizes that RocksDB already contains ARM CRC32C support
- it gates jemalloc page-size work on actual environment checks

Only a few issues remain before execution.

## Findings

### 1. Phase 2.3 fallback is not implementable as written

The fallback section says to manually force ARM CRC flags "in both Dockerfiles", but the example shown is CMake syntax:

```cmake
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -march=armv8-a+crc+crypto")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=armv8-a+crc+crypto")
```

That cannot be pasted directly into a Dockerfile. The current build flow uses Dockerfile `ENV` settings and `cmake` invocation, so this fallback needs to be rewritten as one of:

- pass `CFLAGS` / `CXXFLAGS` from the Dockerfiles
- pass `-DCMAKE_C_FLAGS=...` and `-DCMAKE_CXX_FLAGS=...` in the `cmake` command
- patch RocksDB's `CMakeLists.txt` directly

Recommendation:

- rewrite Phase 2.3 to describe the exact implementation path that will be used

### 2. Phase 3 likely has lower impact than currently claimed

The revised plan correctly shows that RocksDB already handles the important ARM CRC32 path internally. That is the strongest architecture-specific optimization identified so far.

By comparison, the remaining Tendis-side item is:

- replacing Tendis-owned `-march=armv8-a`
- fixing one stray `-march=native` in `src/tendisplus/tools/CMakeLists.txt`

The identified stray flag is in a tools target, not clearly in the main `tendisplus` hot path. So the current expected impact for Phase 3 is not yet well supported by evidence from the codebase.

Recommendation:

- downgrade Phase 3 expected impact from `Medium` to `Low/Unknown until benchmarked`
- keep it in the plan, but present it as a hypothesis to test rather than a likely win

### 3. The expected runtime log string should be made exact

The plan says RocksDB startup should report `"Arm64" not "No"`.

That wording is close, but the actual log string is produced by `crc32c::IsFastCrc32Supported()` and is logged as:

- `Supported on Arm64`
- or `Not supported on Arm64`

Recommendation:

- update the plan to check for the full string, not a shortened interpretation
- this will make later scripting and verification less fragile

## What Improved Since Round 1

These earlier issues are now addressed well:

- release/test Dockerfile drift is explicitly handled
- baseline measurement now uses the current unmodified image and config
- benchmark protocol now includes warm-up, repeat runs, reset policy, and seeding
- RocksDB CRC verification is based on actual source paths instead of only disassembly
- jemalloc page-size work is now conditional on real environment data

## Verdict

The plan is close to ready. The remaining work is mostly cleanup of execution details and wording:

1. fix Phase 2.3 so the fallback matches the real build mechanism
2. soften the claimed impact of Phase 3
3. make the RocksDB runtime log check use the exact expected string
