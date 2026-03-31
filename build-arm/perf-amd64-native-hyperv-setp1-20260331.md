# Native amd64 `SET p1` Benchmark on Hyper-V Host

**Date**: 2026-03-31  
**Purpose**: Save the user-requested `SET p1` benchmark result for the Hyper-V host `10.202.3.43`, even though earlier storage checks suggested it was a poor write-benchmark target.

## Host

- Host IP: `10.202.3.43`
- OS: `Rocky Linux 9.7`
- Architecture: `x86_64`
- Hypervisor: `Microsoft Hyper-V`
- CPU model exposure: `Intel i9-13900KF`
- CPU count: `16 vCPU`
- Memory: about `23 GiB`
- Container engine: `podman`

## Important caveat

This host had already shown an unusually bad small sync-write path in quick `dd` checks:

- large sequential flush check was fast
- `4K dsync` writes were catastrophically slow

So this result is worth keeping as a real `SET p1` measurement on the host, but it should still be interpreted as host-specific benchmark data rather than clean architecture evidence.

## Benchmark methodology

This run only covered `SET p1`.

- server image: `tendis-amd64-current:latest`
- server config: image-baked `build-arm/tendisplus.runtime.conf`
- server limits: `--cpus=4 --memory=8g`
- client image: `redislabs/memtier_benchmark:latest`
- network path: `--network container:<server>` to `127.0.0.1:51002`
- memtier: `-t 4 -c 50`
- warmup: `30s`
- measured trials: `3 x 30s`
- workload:
  - `SET p1`

The first attempt under rootless `podman` failed because the user session did not have the required `cpu` cgroup controller for `--cpus=4`. The successful run switched to `sudo podman`.

## Results

Median of 3 measured trials:

| Workload | Median ops/sec | p50 | p99 | Trial ops/sec |
|----------|----------------|-----|-----|---------------|
| `SET p1` | `118,624.07` | `N/A` | `N/A` | `120,707.75 / 118,110.87 / 118,624.07` |

Repo-local result tables:

- `build-arm/perf-amd64-native-hyperv-setp1-20260331.raw.tsv`
- `build-arm/perf-amd64-native-hyperv-setp1-20260331.median.tsv`

## Note on latency fields

The generated JSON on this host used a latency schema that did not match the parser in the ad-hoc collection script, so `p50` and `p99` were not extracted into the `.tsv` files. The throughput values are valid and came from the completed memtier runs.
