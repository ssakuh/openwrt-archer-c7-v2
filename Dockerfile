# syntax=docker/dockerfile:1.6
FROM public.ecr.aws/ubuntu/ubuntu:24.04 AS builder

ARG VERSION='25.12.5'

ENV DEBIAN_FRONTEND=noninteractive
ENV GIT_URL='https://git.openwrt.org/openwrt/openwrt.git'
ENV GIT_BRANCH="v${VERSION}"
ENV FORCE_UNSAFE_CONFIGURE=1
ENV LC_ALL=C.UTF-8
ENV TZ=UTC

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        bzip2 \
        build-essential \
        ccache \
        clang \
        flex \
        bison \
        file \
        gawk \
        g++ \
        gcc \
        gettext \
        git \
        gperf \
        libelf-dev \
        libncurses-dev \
        libssl-dev \
        libtool \
        libunistring-dev \
        make \
        patch \
        python3 \
        python3-setuptools \
        python3-distutils-extra \
        rsync \
        swig \
        texinfo \
        time \
        unzip \
        wget \
        xsltproc \
        zlib1g-dev && \
    if dpkg --print-architecture | grep -q amd64; then \
        apt-get install -y --no-install-recommends g++-multilib gcc-multilib || true; \
    fi && \
    gcc --version && g++ --version

RUN git clone "${GIT_URL}" -b "${GIT_BRANCH}" --depth 1 --single-branch /openwrt

WORKDIR /openwrt

# Feeds first (cached) — local patches only touch main repo, not feeds,
# so patch edits below don't invalidate this layer.
RUN ./scripts/feeds update -a && \
    ./scripts/feeds install -a

COPY patches/ ./patches/
COPY files/ ./files/
COPY db.txt ./db.txt

RUN set -e; \
    while IFS= read -r patch || [ -n "$patch" ]; do \
        patch="$(echo "$patch" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')"; \
        [ -z "$patch" ] && continue; \
        patch -p1 --forward < "patches/$patch"; \
    done < patches/series

RUN cat > .config <<'EOF'
CONFIG_TARGET_ath79=y
CONFIG_TARGET_ath79_generic=y
CONFIG_TARGET_ath79_generic_DEVICE_tplink_archer-c7-v2=y
CONFIG_CCACHE=y
# Stock ath10k driver+firmware instead of -ct: measured 2026-09-14,
# LAN up 258->299M (P4 304->357M), down unchanged ~200M (single-core TX
# wall), no firmware crashes. -ct radiated ~12dB hotter at same txpower
# setting but did not convert to throughput (PA EVM limit).
CONFIG_PACKAGE_kmod-ath10k=y
# CONFIG_PACKAGE_kmod-ath10k-ct is not set
CONFIG_PACKAGE_ath10k-firmware-qca988x=y
# CONFIG_PACKAGE_ath10k-firmware-qca988x-ct is not set
CONFIG_PACKAGE_kmod-tcp-bbr=y
CONFIG_PACKAGE_kmod-sched-cake=y
CONFIG_PACKAGE_sqm-scripts=y
CONFIG_PACKAGE_luci-app-sqm=y
CONFIG_PACKAGE_etherwake=y
CONFIG_PACKAGE_kmod-wireguard=y
CONFIG_PACKAGE_wireguard-tools=y
CONFIG_PACKAGE_luci-proto-wireguard=y
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_dnsmasq-full-dhcpv6=y
CONFIG_PACKAGE_luci-ssl=y
CONFIG_MBEDTLS_SSL_PROTO_TLS1_3=y
CONFIG_OPENSSL_WITH_TLS13=y
EOF

RUN make defconfig && \
    grep -q '^CONFIG_TARGET_ath79_generic=y' .config

RUN --mount=type=cache,target=/openwrt/dl,sharing=locked \
    ulimit -s unlimited && \
    make tools/zstd/compile -j1 V=s && \
    make download

RUN --mount=type=cache,target=/openwrt/dl,sharing=locked \
    --mount=type=cache,target=/openwrt/.ccache,sharing=locked \
    ulimit -s unlimited && \
    make tools/sed/compile -j1 V=s && \
    make -j$(nproc)

FROM scratch AS export

COPY --from=builder /openwrt/bin/ /
