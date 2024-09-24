FROM --platform=linux/amd64 public.ecr.aws/ubuntu/ubuntu:24.04 AS builder

ARG VERSION='23.05.5'

ENV DEBIAN_FRONTEND=noninteractive
ENV GIT_URL='https://git.openwrt.org/openwrt/openwrt.git'
ENV GIT_BRANCH="v${VERSION}"
ENV RESET_GIT='true'
ENV CORES="$(cat /proc/cpuinfo | grep processor | wc -l)"
ENV DEBUG='true'
ENV FORCE_UNSAFE_CONFIGURE=1
ENV LC_ALL=C.UTF-8

RUN apt update && apt install -y build-essential clang flex bison g++ gawk \
    gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev \
    python3-setuptools rsync swig unzip zlib1g-dev file wget 

RUN git clone $GIT_URL -b $GIT_BRANCH --depth 1 --single-branch /openwrt
COPY . /openwrt
WORKDIR /openwrt

RUN ./scripts/feeds update -a && \
    ./scripts/feeds install -a && \
    make defconfig download && \
    make -j$(nproc)

FROM scratch
COPY --from=builder /openwrt/bin/ . 
