# OCI container image for cross-compiling C++23 (GCC 14) targeting
# Debian Bookworm aarch64 (glibc 2.36).
#
# The image provides:
#   - GCC 14 aarch64-linux-gnu cross-compiler (C++23, std::format)
#   - GCC 14 native x86_64 compiler (for host tools)
#   - Debian Bookworm arm64 sysroot at /opt/bookworm-arm64-sysroot
#   - CMake, autotools, pkg-config, CPack helpers (dpkg-dev, rpm)
#
# The sysroot ensures that the cross-compiled binaries link against
# glibc 2.36 (Bookworm) rather than the host's glibc 2.39 (Ubuntu 24.04),
# making them compatible with Revolution Pi and other Bookworm-based systems.

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# ── Host toolchain & build essentials ─────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        # GCC 14 cross-compiler for aarch64
        g++-14-aarch64-linux-gnu \
        gcc-14-aarch64-linux-gnu \
        binutils-aarch64-linux-gnu \
        # GCC 14 native (for host-side tools during build)
        g++-14 \
        gcc-14 \
        # Build systems
        make \
        ninja-build \
        # Autotools (needed for libmodbus)
        autoconf \
        automake \
        libtool \
        # Package config
        pkg-config \
        # Packaging
        dpkg-dev \
        rpm \
        file \
        # SCM & networking
        git \
        wget \
        ca-certificates \
        # Sysroot creation
        debootstrap \
        qemu-user-static \
    && rm -rf /var/lib/apt/lists/*

# ── CMake 4.2.3 ──────────────────────────────────────────────────────
ARG CMAKE_VERSION=4.2.3
RUN wget -qO- "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" \
    | tar xz -C /opt \
    && ln -s /opt/cmake-${CMAKE_VERSION}-linux-x86_64/bin/cmake  /usr/local/bin/cmake \
    && ln -s /opt/cmake-${CMAKE_VERSION}-linux-x86_64/bin/ctest  /usr/local/bin/ctest \
    && ln -s /opt/cmake-${CMAKE_VERSION}-linux-x86_64/bin/cpack  /usr/local/bin/cpack \
    && cmake --version

# ── Bookworm aarch64 sysroot ─────────────────────────────────────────
# Minimal Debian Bookworm arm64 sysroot with C library development files.
# This provides glibc 2.36 headers and libraries so that cross-compiled
# binaries are compatible with Bookworm-based systems.
#
# --foreign: first-stage only (extract packages, no chroot execution).
# This avoids the need to run arm64 binaries via qemu during the build,
# which fails in unprivileged CI containers. For a cross-compilation
# sysroot we only need headers and libraries, not a bootable chroot.
RUN debootstrap \
        --arch=arm64 \
        --variant=minbase \
        --include=libc6-dev,linux-libc-dev \
        --foreign \
        bookworm \
        /opt/bookworm-arm64-sysroot \
        http://deb.debian.org/debian

# ── Verification ──────────────────────────────────────────────────────
# Sanity-check that the sysroot has the expected glibc version.
# With --foreign the dpkg database is under debootstrap/, so we check
# the extracted libc shared object directly.
RUN ls /opt/bookworm-arm64-sysroot/usr/lib/aarch64-linux-gnu/libc.so.6 \
    && echo "✓ Sysroot contains aarch64 libc" \
    || (echo "✗ aarch64 libc not found in sysroot" && exit 1)

# ── Default compiler symlinks ─────────────────────────────────────────
# Ensure 'gcc' / 'g++' point to version 14
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 100 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 100

# ── Labels ────────────────────────────────────────────────────────────
LABEL org.opencontainers.image.title="cross-build-bookworm-arm64"
LABEL org.opencontainers.image.description="GCC 14 cross-compilation environment targeting Debian Bookworm aarch64 (glibc 2.36)"
LABEL org.opencontainers.image.source="https://github.com/daixtrose/cross-build-bookworm-arm64"
LABEL org.opencontainers.image.licenses="MIT"

WORKDIR /workspace
