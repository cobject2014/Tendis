# Native amd64 Write Benchmark on Aliyun ECS via Podman

**Date**: 2026-03-31  
**Purpose**: Run the same direct-harness write benchmark on a real `x86_64 Linux` host with a cleaner CPU topology than the earlier VMware and Hyper-V VMs.

## Host

- Host IP: `39.106.7.212`
- OS: `Ubuntu 24.04.4 LTS`
- Kernel: `6.8.0-106-generic`
- Architecture: `x86_64`
- Hypervisor: `KVM`
- CPU model: `Intel(R) Xeon(R) Platinum 8369B CPU @ 2.70GHz`
- CPU topology: `1 socket x 2 cores x 2 threads` (`4 vCPU`)
- Memory: about `30 GiB`
- Container engine: `podman 4.9.3`

Storage observed on the host:

- active benchmark disk path: root filesystem on `/dev/vda3` (`ext4`)
- unused extra disk: `/dev/nvme0n1` (`Ali ECS NVMe Instance Storage`, empty, not touched)

The user explicitly asked not to format or mount `/dev/nvme0n1`, so this benchmark ran on the current mounted system/data disk only.

## Image delivery

To avoid remote registry dependency:

- local `tendis-amd64-current:latest` was exported and uploaded
- local `redislabs/memtier_benchmark:latest` was exported and uploaded
- both images were loaded on the remote host with `podman load`

## Benchmark methodology

Same harness shape as the recent direct container-network benchmark:

- server image: `tendis-amd64-current:latest`
- server config: image-baked `build-arm/tendisplus.runtime.conf`
- server limits: `--cpus=4 --memory=8g`
- client image: `redislabs/memtier_benchmark:latest`
- network path: `--network container:<server>` to `127.0.0.1:51002`
- memtier: `-t 4 -c 50`
- warmup: `30s`
- measured trials: `3 x 30s`
- workloads:
  - `SET p1`
  - `SET p5`

Key server config values in `build-arm/tendisplus.runtime.conf`:

- `bind 0.0.0.0`
- `port 51002`
- `daemon no`
- `loglevel notice`
- `rocks.blockcachemb 4096`
- `executorThreadNum 48`

## Results

Median of 3 measured trials:

| Workload | Median ops/sec | p50 | p99 | Trial ops/sec |
|----------|----------------|-----|-----|---------------|
| `SET p1` | `42,006.17` | `4.639 ms` | `10.431 ms` | `42,288.34 / 40,066.60 / 42,006.17` |
| `SET p5` | `65,742.66` | `14.335 ms` | `28.671 ms` | `63,127.24 / 66,572.18 / 65,742.66` |

Repo-local result tables:

- `build-arm/perf-amd64-native-aliyun-podman-20260331.raw.tsv`
- `build-arm/perf-amd64-native-aliyun-podman-20260331.median.tsv`

## Disk-path suitability notes

Quick host-side write checks on the current mounted disk path:

- large sequential write with one final flush:
  - `dd if=/dev/zero of=/tmp/dd-fsync-test.bin bs=1M count=128 conv=fdatasync`
  - elapsed `0.21s`
- small sync-write path:
  - `dd if=/dev/zero of=/tmp/dd-dsync-4k.bin bs=4K count=10000 oflag=dsync`
  - elapsed `14.26s`

That small synchronous write path is still much slower than a good local NVMe path, so these write results are usable as native amd64 host data for this ECS VM, but they still include notable storage-path cost from the mounted system disk.

## Interpretation

This host is cleaner than the previous two x86 VMs in CPU topology, but its current active disk path still limits write-heavy benchmarking. So these numbers are better as native amd64 reference data for this Aliyun ECS host than as a final `amd64 vs arm64` architecture verdict.
