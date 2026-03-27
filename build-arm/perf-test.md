# Tendis-ARM perf test

## Task 
Because this fork is ARM porting, many x86 optimization is missing. So we must optimize current ARM version.
- Setup performance base line. Use [Redis Benchmakr tool]("https://github.com/redis/memtier_benchmark") to evalute current ARM build. The tool [doc]("https://redis.io/blog/memtier_benchmark-a-high-throughput-benchmarking-tool-for-redis-memcached/").
- Analyze what optimization is missed for ARM build. And draft a plan and check list to `build-arm` folder.
- Do all needed experiments to boost Tendis performance. Log all sucessful or failed experiments to `build-arm` folder.

## Constrains
- Use current ARM tendis container as test target.
- Limit resource of Tendis container to 8G mem and 4 core CPU. This is our performance baseline.
- For every major change，please run full test to make function is not broken.
- Focus only on ARM-specific optimizations. General optimizations (LTO, PGO, config tuning, etc.) are assumed already handled by Tendis upstream.