# Prebuilt build container for apex-android-toolchains
# Encapsulates LLVM/Clang build toolchains, CMake, Ninja, Zig cross-compilers,
# QEMU emulation for Linux ARM64 execution verification, and packaging utilities.
FROM ubuntu:24.04

ARG ZIG_VERSION=0.17.0-dev.1978+c961124d9
ARG LLVM_MINGW_VERSION=20260826

ENV DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.source="https://github.com/Apex-Studio-Dev/apex-android-toolchains"
LABEL org.opencontainers.image.description="Builder image for Apex Android LLVM and NDK toolchains"

# Core build system & dependencies
RUN apt-get update && apt-get install -y --no-install-recommends software-properties-common \
    && apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates aria2 curl wget xz-utils unzip git make cmake ninja-build \
        build-essential file p7zip-full python3 python3-pip python3-dev python3-setuptools \
        autoconf automake libtool autoconf-archive pkg-config rsync \
        clang lld patchelf binutils zstd ccache \
        zlib1g-dev libssl-dev libxml2-dev liblzma-dev libbz2-dev uuid-dev cpio bzip2 \
        qemu-user-static binfmt-support \
    && rm -rf /var/lib/apt/lists/*

# Configure git system defaults to avoid dubious ownership issues in container
RUN git config --system --add safe.directory '*' \
    && git config --system user.name "Apex Toolchain Builder" \
    && git config --system user.email "builder@apex-studio.dev"

# fetch: resilient download helper with retries via aria2
RUN printf '%s\n' '#!/bin/sh' \
    'i=0; until aria2c --console-log-level=error --check-certificate=false --max-tries=5 --retry-wait=2 --connect-timeout=15 --allow-overwrite=true --auto-file-renaming=false "$@"; do' \
    '  i=$((i+1)); [ "$i" -ge 5 ] && { echo "fetch: giving up after $i attempts" >&2; exit 1; }' \
    '  echo "fetch: aria2c failed, retry $i/5 in 2s..." >&2; sleep 2' \
    'done' > /usr/local/bin/fetch && chmod +x /usr/local/bin/fetch

# Cross-execution support:
# If host is x86_64, ensure aarch64 cross-libc & qemu are available to run and verify ARM64 binaries
# If host is aarch64, ensure x86_64 cross-libc & qemu are available to run official NDK x86_64 binaries
RUN arch="$(uname -m)"; \
    if [ "$arch" = "x86_64" ]; then \
        apt-get update && apt-get install -y --no-install-recommends \
            gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
            gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf \
            gcc-multilib g++-multilib \
            libc6-arm64-cross libstdc++-14-dev-arm64-cross \
            libc6-armhf-cross libstdc++-14-dev-armhf-cross \
        && rm -rf /var/lib/apt/lists/*; \
    else \
        apt-get update && apt-get install -y --no-install-recommends \
            libc6-amd64-cross \
        && rm -rf /var/lib/apt/lists/*; \
    fi

# zig (cross C/C++ toolchain & musl/bionic sysroots)
RUN arch="$(uname -m)"; \
    case "$arch" in \
        x86_64)       zig_arch="x86_64" ;; \
        aarch64)      zig_arch="aarch64" ;; \
        armv7l|armv8l) zig_arch="arm" ;; \
        riscv64)      zig_arch="riscv64" ;; \
        ppc64le)      zig_arch="powerpc64le" ;; \
        i686|i386)    zig_arch="x86" ;; \
        *) echo "WARNING: unsupported zig host arch '$arch'; skipping zig"; touch /opt/.no-zig ;; \
    esac; \
    if [ ! -f /opt/.no-zig ]; then \
        case "$ZIG_VERSION" in \
            *dev*) zig_base="https://ziglang.org/builds" ;; \
            *)     zig_base="https://ziglang.org/download/${ZIG_VERSION}" ;; \
        esac; \
        fetch --dir=/tmp -o zig.tar.xz \
            "${zig_base}/zig-${zig_arch}-linux-${ZIG_VERSION}.tar.xz" \
        && tar -xJf /tmp/zig.tar.xz -C /opt \
        && rm /tmp/zig.tar.xz \
        && mv "/opt/zig-${zig_arch}-linux-${ZIG_VERSION}" /opt/zig \
        && chmod -R a+w /opt/zig/lib; \
    fi

ENV PATH="/opt/zig:${PATH}"
ENV CCACHE_DIR=/work/.ccache

WORKDIR /work
