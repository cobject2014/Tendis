# Native amd64 Write Benchmark on Remote Linux Host

**Date**: 2026-03-31  
**Purpose**: Run the write-only benchmark on a real `x86_64 Linux` machine, using the same newer memtier harness shape as the recent local experiments.

## Host

- Host IP: `10.202.3.45`
- OS: `Ubuntu 24.04.1 LTS`
- Kernel: `6.17.0-19-generic`
- Architecture: `x86_64`
- CPU count: `4`
- Memory: `7.8 GiB`
- CPU model reported by `lscpu`: `AMD Ryzen 9 5900X 12-Core Processor`
- Root disk: `80G` virtual disk

This is a native `x86_64` Linux host, not emulation.

## Image delivery

To avoid registry dependency on the remote host, local images were exported and uploaded over SCP:

- `tendis-amd64-current:latest`
- `redislabs/memtier_benchmark:latest`

The benchmark was then run directly on the remote host after `docker load`.

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

Raw files pulled back from the remote host:

- `/tmp/write-amd64-native-20260331/median.tsv`
- `/tmp/write-amd64-native-20260331/raw.tsv`

Repo copies saved alongside this note:

- `build-arm/perf-amd64-native-20260331.median.tsv`
- `build-arm/perf-amd64-native-20260331.raw.tsv`

## Results

Median of 3 measured trials:

| Workload | Median ops/sec | p50 | p99 | Trial ops/sec |
|----------|----------------|-----|-----|---------------|
| `SET p1` | `49,279.59` | `3.631 ms` | `9.791 ms` | `50,855.46 / 49,279.59 / 43,287.91` |
| `SET p5` | `80,030.83` | `9.983 ms` | `38.143 ms` | `80,030.83 / 77,512.29 / 90,446.92` |

## Notes

The run showed visible throughput drops and long-tail pauses during multiple trials. Examples observed during the live run:

- `SET p1` had stalls around `22 ms` and `49 ms`
- `SET p5` had a severe pause around `385 ms`

So this machine is valid as a native amd64 benchmark target, but the measured write performance is strongly affected by host/storage/runtime conditions on this specific VM.

## Interpretation

This file answers one narrow question: what does the current amd64 image do on a real x86 Linux machine?

It does **not** by itself answer the architecture gap question, because this host is not matched to the earlier arm64 environment:

- different machine
- different CPU family
- different storage path
- likely different virtualization noise

So these results should be treated as **native amd64 reference data for this host**, not as a final `amd64 vs arm64` verdict.

## Likely VM performance issues

Follow-up diagnostics on the same host point to several infrastructure-side problems that can explain the poor write result:

1. The disk is attached through an old VMware virtual SCSI path, not a paravirtual controller.

   Kernel messages show:

   - `LSI53C1030 B0`
   - `VMware Virtual disk`

   That is a much weaker choice for write-heavy database benchmarking than VMware PVSCSI or virtual NVMe.

2. The kernel cannot discover disk cache capability and falls back to write-through assumptions.

   `dmesg` showed:

   - `Cache data unavailable`
   - `Assuming drive cache: write through`

   For a write path like Tendis + RocksDB + binlog, this is a major red flag. It strongly suggests sync-heavy writes will stall far more than on a normal write-back-backed SSD path.

3. The VM CPU topology is presented as `4 sockets x 1 core`, not `1 socket x 4 cores`.

   `lscpu` reported:

   - `CPU(s): 4`
   - `Thread(s) per core: 1`
   - `Core(s) per socket: 1`
   - `Socket(s): 4`

   That topology is unusual for a small VM and can create unnecessary scheduler and NUMA/topology weirdness for a container benchmark.

4. Small synchronous writes are much slower than large sequential writes.

   Lightweight write checks on the host:

   - large sequential write with one final flush:
     - `dd if=/dev/zero of=/tmp/dd-fsync-test.bin bs=1M count=128 conv=fdatasync`
     - elapsed `0.40s`
   - small sync write path:
     - `dd if=/dev/zero of=/tmp/dd-dsync-4k.bin bs=4K count=10000 oflag=dsync`
     - elapsed `6.15s`

   The second case is only about `40 MiB` total data but takes over six seconds, which is consistent with the benchmark's visible write stalls and long p99 tails.

## Practical recommendations

- Recreate the VM with `1 socket x 4 cores`
- Prefer VMware PVSCSI or virtual NVMe instead of the current LSI virtual SCSI path
- Check ESXi datastore / virtual disk policy and enable a sane write-back-backed cache path if your durability model allows it
- If possible, benchmark on a less contended datastore or directly on a host-backed local SSD / NVMe path
- Before drawing architecture conclusions, rerun the same amd64 benchmark after fixing the VM/storage path
