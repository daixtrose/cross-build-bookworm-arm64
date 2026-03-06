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

# ── Extract --include packages ────────────────────────────────────────
# With --foreign, debootstrap downloads --include packages but only
# queues them for second-stage extraction that never runs. Manually
# extract libc6-dev and linux-libc-dev so the sysroot has the headers,
# linker scripts, and static libraries needed for cross-compilation.
RUN for deb in \
        /opt/bookworm-arm64-sysroot/var/cache/apt/archives/libc6-dev_*_arm64.deb \
        /opt/bookworm-arm64-sysroot/var/cache/apt/archives/linux-libc-dev_*_arm64.deb ; do \
      echo "Extracting $(basename "$deb") ..." \
      && dpkg-deb --extract "$deb" /opt/bookworm-arm64-sysroot/ ; \
    done

# ── Remove host's glibc 2.39 aarch64 headers ─────────────────────────
# The GCC 14 cross-compiler has a built-in include path at
# /usr/aarch64-linux-gnu/include/ (from the libc6-dev-arm64-cross
# package). This path is NOT affected by --sysroot and takes
# precedence over the sysroot's headers.
#
# The host headers define __GLIBC_MINOR__ = 39 and redirect strtoll()
# and friends to __isoc23_strtoll() (glibc 2.38+), which are
# unavailable on Bookworm (glibc 2.36). Remove the C library headers
# so the compiler falls through to the sysroot's glibc 2.36 headers.
# Keep the c++/ subdirectory (libstdc++ headers from GCC 14).
RUN find /usr/aarch64-linux-gnu/include/ -maxdepth 1 \
        -not -name include -not -name c++ -exec rm -rf {} +

# ── strlcpy compatibility shim ────────────────────────────────────────
# strlcpy() was added to glibc in 2.38, but the Bookworm sysroot has
# glibc 2.36. Upstream libmodbus (master) uses strlcpy unconditionally.
# Provide a portable static-inline implementation in the sysroot's
# string.h so autotools configure detects it and code compiles cleanly.
COPY strlcpy_compat.h /tmp/strlcpy_compat.h
RUN cat /tmp/strlcpy_compat.h >> /opt/bookworm-arm64-sysroot/usr/include/string.h \
    && rm /tmp/strlcpy_compat.h

# ── Verification ──────────────────────────────────────────────────────
# Sanity-check that the sysroot has glibc runtime AND development files,
# and that the host headers no longer shadow the sysroot.
RUN ls /opt/bookworm-arm64-sysroot/usr/lib/aarch64-linux-gnu/libc.so.6 \
    && echo "✓ Sysroot contains aarch64 libc.so.6 (runtime)" \
    || (echo "✗ aarch64 libc.so.6 not found in sysroot" && exit 1)
RUN ls /opt/bookworm-arm64-sysroot/usr/lib/aarch64-linux-gnu/libc.so \
    && echo "✓ Sysroot contains aarch64 libc.so (linker script)" \
    || (echo "✗ aarch64 libc.so linker script not found in sysroot" && exit 1)
RUN ls /opt/bookworm-arm64-sysroot/usr/lib/aarch64-linux-gnu/crt1.o \
    && echo "✓ Sysroot contains aarch64 crt1.o (C runtime startup)" \
    || (echo "✗ aarch64 crt1.o not found in sysroot" && exit 1)
RUN grep -q '__GLIBC_MINOR__.*36' /opt/bookworm-arm64-sysroot/usr/include/features.h \
    && echo "✓ Sysroot headers report glibc 2.36" \
    || (echo "✗ Sysroot headers do not report glibc 2.36" && exit 1)
RUN test ! -f /usr/aarch64-linux-gnu/include/features.h \
    && echo "✓ Host glibc 2.39 headers removed (no shadowing)" \
    || (echo "✗ Host glibc 2.39 headers still present" && exit 1)

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
