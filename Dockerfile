FROM debian:12 AS builder

LABEL maintainer="Navyum <yhj2433488839@gmail.com>"

WORKDIR /opt

ARG CURL_VERSION=curl-8_2_1
ARG QUICHE_VERSION=0.18.0

# 合并所有构建步骤到一个RUN命令中，减少镜像层数
# 使用--no-install-recommends减少不必要的包
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        git \
        autoconf \
        automake \
        autotools-dev \
        libtool \
        cmake \
        curl \
        ca-certificates \
        libnghttp2-dev \
        zlib1g-dev && \
    # 安装rust & cargo
    curl https://sh.rustup.rs -sSf | sh -s -- -y -q && \
    # 克隆并构建quiche
    git clone --recursive https://github.com/cloudflare/quiche && \
    export PATH="$HOME/.cargo/bin:$PATH" && \
    cd quiche && \
    git checkout $QUICHE_VERSION && \
    cargo build --package quiche --release --features ffi,pkg-config-meta,qlog && \
    mkdir -p quiche/deps/boringssl/src/lib && \
    ln -vnf $(find target/release -name libcrypto.a -o -name libssl.a) quiche/deps/boringssl/src/lib/ && \
    cd .. && \
    # 克隆并构建curl
    git clone https://github.com/curl/curl && \
    cd curl && \
    git checkout $CURL_VERSION && \
    autoreconf -fi && \
    ./configure \
        LDFLAGS="-Wl,-rpath,/opt/quiche/target/release" \
        --with-openssl=/opt/quiche/quiche/deps/boringssl/src \
        --with-quiche=/opt/quiche/target/release \
        --with-nghttp2 \
        --with-zlib && \
    make && \
    make DESTDIR="/debian/" install

# 多阶段构建中，builder阶段的内容不会进入最终镜像
# 这里只做最小清理以避免缓存问题
RUN rm -rf ~/.cargo/registry ~/.cargo/git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

FROM debian:12-slim

# 只安装运行时必需的包，使用--no-install-recommends
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        nghttp2 \
        zlib1g && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 复制构建产物
COPY --from=builder /debian/usr/local/ /usr/local/
COPY --from=builder /opt/quiche/target/release /opt/quiche/target/release

# 更新动态链接库缓存
RUN ldconfig

WORKDIR /opt

# 从本地复制httpstat脚本
COPY httpstat.sh /opt/httpstat.sh
RUN chmod +x /opt/httpstat.sh

CMD ["curl"]