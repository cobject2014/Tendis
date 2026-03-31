# amd64 Host Comparison for Write Benchmarking

**Date**: 2026-03-31  
**Purpose**: Compare the three native `amd64` Linux hosts used or evaluated for Tendis write benchmarking, focusing on host configuration, disk-path behavior, and `SET p1` usefulness.

## Summary Table

| Host | Virtualization / OS | CPU / Memory | Disk path used for check | Small sync write check | Tendis `SET p1` median | Notes |
|------|----------------------|--------------|---------------------------|------------------------|------------------------|-------|
| `10.202.3.45` | VMware full virtualization, Ubuntu 24.04.1 | `4 vCPU`, `7.8 GiB`, `AMD Ryzen 9 5900X` exposure, abnormal `4 sockets x 1 core` topology | `VMware Virtual disk`, old `LSI53C1030` virtual SCSI, kernel assumed `write through` | `dd bs=4K count=10000 oflag=dsync` -> `6.15s` | `49,279.59 ops/sec` | Native amd64 run completed, but storage path and topology were clearly poor for write benchmarking. |
| `10.202.3.43` | Hyper-V full virtualization, Rocky Linux 9.7 | `16 vCPU`, `~23 GiB`, `Intel i9-13900KF` exposure, normal topology | `Msft Virtual Disk` via `storvsc`, write cache enabled | `dd bs=4K count=10000 oflag=dsync` -> `42.47s` | `N/A` | Rejected before formal Tendis benchmark because the small sync-write path was catastrophically slow. |
| `39.106.7.212` | Aliyun ECS KVM, Ubuntu 24.04.4 | `4 vCPU`, `~30 GiB`, `Intel Xeon Platinum 8369B`, `1 socket x 2 cores x 2 threads` | current mounted root disk `/dev/vda3` (`ext4`), extra local NVMe existed but was intentionally not used | `dd bs=4K count=10000 oflag=dsync` -> `14.26s` | `42,006.17 ops/sec` | Cleaner CPU topology than the first two VMs, but the active disk path still imposed noticeable sync-write cost. |

## Sequential Write Check

| Host | Large sequential flush check |
|------|------------------------------|
| `10.202.3.45` | `dd bs=1M count=128 conv=fdatasync` -> `0.40s` |
| `10.202.3.43` | `dd bs=1M count=128 conv=fdatasync` -> `0.03s` |
| `39.106.7.212` | `dd bs=1M count=128 conv=fdatasync` -> `0.21s` |

## Tendis `SET p1`

| Host | Tendis `SET p1` median ops/sec | p50 | p99 | Source |
|------|-------------------------------|-----|-----|--------|
| `10.202.3.45` | `49,279.59` | `3.631 ms` | `9.791 ms` | [perf-amd64-native-20260331.md](/Users/williamyao/dev/tendis_fork/build-arm/perf-amd64-native-20260331.md) |
| `10.202.3.43` | `N/A` | `N/A` | `N/A` | rejected before benchmark |
| `39.106.7.212` | `42,006.17` | `4.639 ms` | `10.431 ms` | [perf-amd64-native-aliyun-podman-20260331.md](/Users/williamyao/dev/tendis_fork/build-arm/perf-amd64-native-aliyun-podman-20260331.md) |

## Takeaway

For write-heavy Tendis benchmarking, the small synchronous write path is the best quick filter among these hosts. The Hyper-V VM (`10.202.3.43`) was unusable. The VMware VM (`10.202.3.45`) was benchmarkable but still storage-path-limited. The Aliyun ECS host (`39.106.7.212`) had the cleanest CPU presentation, but because the benchmark used the mounted root disk instead of the empty local NVMe, its write numbers still reflect significant disk-path cost rather than pure amd64 CPU capability.
