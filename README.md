# cross-build-bookworm-arm64

OCI container image for cross-compiling **C++23** applications with **GCC 14** targeting **Debian Bookworm aarch64** (glibc 2.36).

## Purpose

When cross-compiling on Ubuntu 24.04 (glibc 2.39) with `g++-14-aarch64-linux-gnu`, the resulting binaries require glibc ≥ 2.38 and a matching libstdc++. These are unavailable on Debian Bookworm (glibc 2.36), which is the basis for devices such as the [Revolution Pi](https://revolutionpi.com/).

This image solves the problem by providing a **Bookworm aarch64 sysroot** alongside the GCC 14 cross-compiler. By pointing `--sysroot=/opt/bookworm-arm64-sysroot` and linking with `-static-libstdc++ -static-libgcc`, the resulting binaries:

- Use **C++23** features (`std::format`, `std::print`, etc.) from GCC 14
- Link against **glibc 2.36** symbols (Bookworm-compatible)
- Embed libstdc++/libgcc statically (no `GLIBCXX_3.4.32` issues)
- Keep libc dynamic (NSS/DNS resolution works)

## Contents

| Component | Version | Path |
|---|---|---|
| GCC 14 aarch64 cross-compiler | 14.x (Ubuntu 24.04) | `aarch64-linux-gnu-g++-14` |
| GCC 14 native compiler | 14.x (Ubuntu 24.04) | `g++-14` |
| Bookworm aarch64 sysroot | glibc 2.36 | `/opt/bookworm-arm64-sysroot` |
| CMake | 3.28+ | `cmake` |
| Autotools | autoconf, automake, libtool | — |
| Packaging | dpkg-dev, rpm | — |

## Usage

### Pull the image

```bash
# Docker
docker pull ghcr.io/daixtrose/cross-build-bookworm-arm64:latest

# Podman
podman pull ghcr.io/daixtrose/cross-build-bookworm-arm64:latest
```

### Use in GitHub Actions

```yaml
jobs:
  build-aarch64:
    runs-on: ubuntu-24.04
    container:
      image: ghcr.io/daixtrose/cross-build-bookworm-arm64:latest
    steps:
      - uses: actions/checkout@v4
      - name: Configure
        run: cmake --preset linux-aarch64-release
      - name: Build
        run: cmake --build --preset linux-aarch64-release --parallel
```

### CMake toolchain file

```cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc-14)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++-14)
set(CMAKE_STRIP aarch64-linux-gnu-strip)

# Link against Bookworm's glibc 2.36
set(CMAKE_SYSROOT /opt/bookworm-arm64-sysroot)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
```

### Compile a test program

```bash
docker run --rm -v "$PWD:/workspace" ghcr.io/daixtrose/cross-build-bookworm-arm64:latest \
  aarch64-linux-gnu-g++-14 -std=c++23 \
    --sysroot=/opt/bookworm-arm64-sysroot \
    -static-libstdc++ -static-libgcc \
    -o /workspace/hello /workspace/hello.cpp
```

## Building locally

```bash
# With Buildah (OCI native)
buildah bud --format oci -t cross-build-bookworm-arm64:latest -f Containerfile .

# With Docker
docker build -t cross-build-bookworm-arm64:latest -f Containerfile .

# With Podman
podman build --format oci -t cross-build-bookworm-arm64:latest -f Containerfile .
```

## Schedule

The image is automatically rebuilt monthly (1st of each month) to pick up security updates from the Ubuntu 24.04 base image.

## License

[MIT](LICENSE)
