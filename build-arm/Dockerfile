# --- 第一阶段：编译环境 ---
FROM  ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# 安装基础构建工具
RUN apt-get update && apt-get install -y \
    git cmake build-essential python3 curl m4 autoconf automake libtool \
    libssl-dev zlib1g-dev libbz2-dev libsnappy-dev liblz4-dev libzstd-dev \
    libgflags-dev libgoogle-perftools-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# 拉取 Tendis 源码 (建议使用稳定分支)
RUN git clone --recursive --branch 2.8.3-rocksdb-v8.5.3 https://github.com/Tencent/Tendis.git

WORKDIR /src/Tendis

# Configure git user for patching
RUN git config --global user.email "builder@example.com" && \
    git config --global user.name "Builder"

# Apply patches to RocksDB
RUN cd src/thirdparty/rocksdb/rocksdb && \
    git am --abort || true && \
    git am -s ../../patch/0001-add-statistic-for-sst-file-info.patch && \
    git am -s ../../patch/0002-add-latency-statistic-log.patch && \
    git am -s ../../patch/0003-better-control-of-blobldb-space-amp.patch

# Apply patches to jemalloc
RUN cd src/thirdparty/jemalloc && \
    git apply ../patch/jemalloc_patch.diff

# Debug: Check if header exists after patching
RUN find src/thirdparty/rocksdb -name tendis_extension.h



# 1. 修复 ARM 架构下 char 的符号问题 (防止重复添加 signed)
RUN sed -i 's/signed char DecodeTable/char DecodeTable/g' src/tendisplus/utils/base64.cpp && \
    sed -i 's/char DecodeTable/signed char DecodeTable/g' src/tendisplus/utils/base64.cpp && \
    sed -i 's/signed char ch = DecodeTable/char ch = DecodeTable/g' src/tendisplus/utils/base64.cpp && \
    sed -i 's/char ch = DecodeTable/signed char ch = DecodeTable/g' src/tendisplus/utils/base64.cpp

# 2. 移除硬编码的 x86 指令优化，改为 ARM 兼容模式
RUN find . -name "CMakeLists.txt" -exec sed -i 's/-mno-avx -mno-avx2//g' {} + && \
    find . -name "CMakeLists.txt" -exec sed -i 's/-march=nocona/-march=armv8-a/g' {} +

# 3. 预处理 jemalloc (保持不变)
ENV EXTRA_CXXFLAGS="-O3"
ENV EXTRA_CFLAGS="-O3"

# --- 核心修复：注入编译器宽松模式 ---
# 1. -Wno-error: 禁止将警告视为错误 (Tendis 老代码警告很多)
# 2. -fpermissive: 容忍旧式 C++ 语法
# 3. -include cstdint: GCC 11 必须显式包含此文件，否则会报 uint64_t 错误
ENV CXXFLAGS="-O3 -Wno-error -Wno-deprecated-declarations -fpermissive -include cstdint"
ENV CFLAGS="-O3 -Wno-error -Wno-deprecated-declarations"

# 4. 执行编译
# 为了安全起见，我们在 cmake 命令中显式关闭测试相关的构建，进一步减少报错概率
RUN apt-get remove -y libgflags-dev && apt-get autoremove -y

RUN mkdir build_arm && cd build_arm && \
    cmake .. -DCMAKE_BUILD_TYPE=Release \
             -DENABLE_ALL_WARNINGS=OFF \
             -DUSE_JEMALLOC=ON \
             -DFORCE_BUILD_GFLAGS=ON \
             -DSNAPPY_WITH_GFLAGS=OFF \
             -DSNAPPY_WITH_TESTS=OFF \
             -DBUILD_TESTING=OFF \
             -DTENDIS_BUILD_TEST=OFF && \
    make -j$(nproc) tendisplus

# --- 第三阶段：最终运行镜像 ---
FROM ubuntu:22.04

# 运行时仅安装基础库
RUN apt-get update && apt-get install -y \
    libssl3 libsnappy1v5 liblz4-1 libzstd1 libgoogle-perftools4 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /src/Tendis/build_arm/bin/tendisplus /app/
COPY --from=builder /src/Tendis/tendisplus.conf /app/

EXPOSE 6379 16379
ENTRYPOINT ["/app/tendisplus", "/app/tendisplus.conf"]
