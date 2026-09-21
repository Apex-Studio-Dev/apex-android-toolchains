# Apex Android Toolchains

[![CI - LLVM Multi-Arch](https://github.com/Apex-Studio-Dev/apex-android-toolchains/actions/workflows/llvm.yml/badge.svg)](https://github.com/Apex-Studio-Dev/apex-android-toolchains/actions/workflows/llvm.yml)
[![CI - NDK Multi-Arch](https://github.com/Apex-Studio-Dev/apex-android-toolchains/actions/workflows/ndk.yml/badge.svg)](https://github.com/Apex-Studio-Dev/apex-android-toolchains/actions/workflows/ndk.yml)
[![Docker Builder Image](https://github.com/Apex-Studio-Dev/apex-android-toolchains/actions/workflows/docker-image.yml/badge.svg)](https://github.com/Apex-Studio-Dev/apex-android-toolchains/actions/workflows/docker-image.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

An enterprise-grade, automated monorepo designed to build **Custom Android LLVM/Clang** and standalone **Custom Android NDK** toolchains with **native execution support across all 4 Android host architectures**, capable of full multi-target cross-compilation.

---

## 📖 Table of Contents

- [Motivation & Overview](#-motivation--overview)
- [Key Features](#-key-features)
- [Architecture Model](#-architecture-model)
  - [Host Execution Platforms](#1-host-execution-platforms-where-the-toolchain-runs)
  - [Multi-Target Code Generation](#2-multi-target-code-generation-what-the-toolchain-compiles-for)
- [Docker Builder Container](#-docker-builder-container)
- [Releases & Artifact Specifications](#-releases--artifact-specifications)
  - [LLVM / Clang Toolchains](#1-llvm--clang-revisions-exact-aosp-commits)
  - [Custom Android NDK Releases](#2-custom-android-ndk-releases)
- [Quick Start & Usage](#-quick-start--usage)
  - [Using with Termux / Android Shell](#1-using-with-termux--android-shell)
  - [Using with Gradle / Android Studio](#2-using-with-gradle--android-studio)
  - [Using with Standalone CMake](#3-using-with-standalone-cmake)
- [CI/CD Build & Release Automation](#-cicd-build--release-automation)
  - [GitHub Actions Dynamic Strategy Matrix](#github-actions-dynamic-strategy-matrix)
  - [Triggering Builds via GitHub CLI](#triggering-builds-via-github-cli)
  - [Publishing Releases via Git Tags](#publishing-releases-via-git-tags)
- [Rigorous Verification Pipeline](#-rigorous-verification-pipeline)
- [Repository Structure](#-repository-structure)
- [Documentation Index](#-documentation-index)
- [License](#-license)

---

## 💡 Motivation & Overview

Official Google Android NDK and LLVM releases only provide prebuilt host compilers for `linux-x86_64`, `darwin-x86_64/arm64`, and `windows-x86_64`. Developers wishing to compile native C/C++ applications directly on Android devices (e.g. inside **Termux**, mobile IDEs, or on-device CI test runners) or on 32-bit Android devices have historically been left without official native toolchains.

**`apex-android-toolchains`** solves this by providing:
1. **Native Execution on Android:** Binaries run directly on Android OS (via Bionic libc) without requiring glibc chroots or PRoot translation layers.
2. **Support for All 4 Android Host Architectures:** Available for `arm64-v8a`, `armeabi-v7a`, `x86_64`, and `x86`.
3. **True Cross-Compilation:** Any single compiler binary—regardless of the host machine it runs on—can target all 5 Android ABIs (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`, and `riscv64`).
4. **Cloud-First CI Engine:** Zero local compilation load on mobile devices. All compilation and packaging run via automated GitHub Actions workflows inside optimized Docker containers.

---

## ✨ Key Features

- ⚡ **Native Execution on 4 Android Host Architectures:**
  Native ELF executables built for `aarch64-linux-android`, `armv7a-linux-androideabi`, `x86_64-linux-android`, and `i686-linux-android`.
- 🌐 **Full Multi-Target Backend:**
  Configured with `-DLLVM_TARGETS_TO_BUILD="AArch64;ARM;X86;RISCV"`. A single compiler can build binaries for any Android device.
- 📦 **Complete Standalone NDK Ecosystem:**
  Spliced with official Google NDK skeletons, equipped with matching AOSP LLVM revisions, native static GNU Make 4.4 and Yasm 1.3.0, and complete Bionic sysroots.
- 🐳 **Prebuilt Multiplatform Builder Container (`ghcr.io`):**
  A dedicated container (`linux/amd64` and `linux/arm64`) equipped with cross-compilers (`gcc-aarch64`, `gcc-armhf`, `gcc-i686`), Zig, Clang 18, LLD, CMake, and Ninja.
- 🔀 **Dynamic 2D Strategy Matrix:**
  GitHub Actions CI dynamically schedules parallel jobs across runners, allowing simultaneous multi-architecture compilation (`target=all`).
- 🛡️ **Automated Pre-Release Verification:**
  Every binary undergoes automated ELF machine header inspection and end-to-end multi-ABI test compilation before release.
- 🚀 **Resource & Linker Optimization:**
  Unlocks ~50+ GB of runner disk space via `easimon/maximize-build-space@v10`, uses `ccache`, and enforces `-DLLVM_PARALLEL_LINK_JOBS=1` to eliminate runner OOM crashes.
- 🔒 **Cryptographic Integrity:**
  Every release artifact includes verified `SHA256SUMS` and `SHA512SUMS`.

---

## 🎯 Architecture Model

### 1. Host Execution Platforms (Where the toolchain runs)

| Host Architecture | Canonical Target Triple | Platform & Use Case |
| :--- | :--- | :--- |
| **ARM64** | `aarch64-linux-android` (`arm64-v8a`) | Modern Android smartphones, tablets, Termux |
| **ARM32** | `armv7a-linux-androideabi` (`armeabi-v7a`) | Legacy 32-bit Android devices, embedded IoT |
| **x86_64** | `x86_64-linux-android` | Android PC Emulators, Windows Subsystem for Android (WSA), Waydroid |
| **x86 (32-bit)** | `i686-linux-android` | 32-bit Android PC Emulators |

### 2. Multi-Target Code Generation (What the toolchain compiles for)

Every single Clang compiler built by this project contains the full backend code generator. Regardless of whether you run Clang on a phone (ARM64) or in an emulator (x86_64), you can cross-compile C/C++ code to:

* `arm64-v8a` (`aarch64-linux-android`)
* `armeabi-v7a` (`arm-linux-androideabi` / `armv7a-linux-androideabi`)
* `x86_64` (`x86_64-linux-android`)
* `x86` (`i686-linux-android`)
* `riscv64` (`riscv64-linux-android`)

---

## 🐳 Docker Builder Container

All compilation runs inside a dedicated, reproducible container published to GitHub Container Registry:

```bash
docker pull ghcr.io/apex-studio-dev/apex-toolchains-builder:latest
```

- **Supported Container Host Platforms:** `linux/amd64` and `linux/arm64`.
- **Cross-Compilation Toolchains:**
  - `gcc-aarch64-linux-gnu` / `g++-aarch64-linux-gnu` (ARM64 cross-compiler)
  - `gcc-arm-linux-gnueabihf` / `g++-arm-linux-gnueabihf` (ARM32 cross-compiler)
  - `gcc-i686-linux-gnu` / `g++-i686-linux-gnu` (x86 32-bit cross-compiler)
  - `zig` (Used for building static, libc-agnostic host helper utilities)
- **Host Build Suite:** Clang 18, LLD, CMake, Ninja, Python 3, ccache, patchelf, aria2, and QEMU user emulation (`qemu-user-static`).

> **Architectural Note:** The builder container runs on 64-bit cloud runners (`amd64` / `arm64`) and cross-compiles the toolchains to all 4 Android host architectures.

---

## 📦 Releases & Artifact Specifications

Artifacts published to GitHub Releases adhere to standard naming conventions:

* **LLVM Artifact:** `custom-llvm-<revision>-<target>.tar.xz`
  *(e.g., `custom-llvm-r487747e-aarch64-linux-android.tar.xz`)*
* **NDK Artifact:** `custom-android-ndk-<release>-<target>.tar.xz`
  *(e.g., `custom-android-ndk-r26d-aarch64-linux-android.tar.xz`)*
* **ARM64 Symlink:** For backward compatibility, `*-linux-arm64.tar.xz` symlinks are provided for ARM64 targets.
* **Checksums:** Verified `SHA256SUMS` and `SHA512SUMS` accompany every release.

### 1. LLVM / Clang Revisions (Exact AOSP Commits)

| LLVM Major | Clang Revision | AOSP Manifest Tag / Branch | Git Tag | Available Host Architectures |
| :---: | :---: | :---: | :---: | :--- |
| **LLVM 17** | `clang-r487747c` | `r487747c` | `llvm-r487747c` | `aarch64`, `armv7a`, `x86_64`, `i686` |
| **LLVM 17** | `clang-r487747d` | `r487747d` | `llvm-r487747d` | `aarch64`, `armv7a`, `x86_64`, `i686` |
| **LLVM 17** | `clang-r487747e` | `r487747e` | `llvm-r487747e` | `aarch64`, `armv7a`, `x86_64`, `i686` |
| **LLVM 18** | `clang-r522817`  | `r522817`  | `llvm-r522817`  | `aarch64`, `armv7a`, `x86_64`, `i686` |
| **LLVM 18** | `clang-r522817b` | `r522817b` | `llvm-r522817b` | `aarch64`, `armv7a`, `x86_64`, `i686` |
| **LLVM 18** | `clang-r522817c` | `r522817c` | `llvm-r522817c` | `aarch64`, `armv7a`, `x86_64`, `i686` |
| **LLVM 18** | `clang-r522817d` | `r522817d` | `llvm-r522817d` | `aarch64`, `armv7a`, `x86_64`, `i686` |
| **LLVM 19** | `clang-r530567b` | `r530567b` | `llvm-r530567b` | `aarch64`, `armv7a`, `x86_64`, `i686` |
| **LLVM 19** | `clang-r530567d` | `r530567d` | `llvm-r530567d` | `aarch64`, `armv7a`, `x86_64`, `i686` |
| **LLVM 19** | `clang-r530567e` | `r530567e` | `llvm-r530567e` | `aarch64`, `armv7a`, `x86_64`, `i686` |
| **LLVM 21** | `clang-r563880c` | `r563880c` | `llvm-r563880c` | `aarch64`, `armv7a`, `x86_64`, `i686` |
| **LLVM 21** | `clang-r574158c` | `r574158c` | `llvm-r574158c` | `aarch64`, `armv7a`, `x86_64`, `i686` |

### 2. Custom Android NDK Releases

| NDK Release | Clang Revision | Git Tag | Official Base Version | Available Host Architectures |
| :---: | :---: | :---: | :---: | :--- |
| `r26`  | `clang-r487747c` | `ndk-r26`  | Android NDK r26  | `aarch64`, `armv7a`, `x86_64`, `i686` |
| `r26b` | `clang-r487747d` | `ndk-r26b` | Android NDK r26b | `aarch64`, `armv7a`, `x86_64`, `i686` |
| `r26c` | `clang-r487747d` | `ndk-r26c` | Android NDK r26c | `aarch64`, `armv7a`, `x86_64`, `i686` |
| `r26d` | `clang-r487747e` | `ndk-r26d` | Android NDK r26d | `aarch64`, `armv7a`, `x86_64`, `i686` |
| `r27`  | `clang-r522817`  | `ndk-r27`  | Android NDK r27  | `aarch64`, `armv7a`, `x86_64`, `i686` |
| `r27b` | `clang-r522817b` | `ndk-r27b` | Android NDK r27b | `aarch64`, `armv7a`, `x86_64`, `i686` |
| `r27c` | `clang-r522817c` | `ndk-r27c` | Android NDK r27c | `aarch64`, `armv7a`, `x86_64`, `i686` |
| `r27d` | `clang-r522817d` | `ndk-r27d` | Android NDK r27d | `aarch64`, `armv7a`, `x86_64`, `i686` |
| `r28`  | `clang-r530567b` | `ndk-r28`  | Android NDK r28  | `aarch64`, `armv7a`, `x86_64`, `i686` |
| `r28b` | `clang-r530567d` | `ndk-r28b` | Android NDK r28b | `aarch64`, `armv7a`, `x86_64`, `i686` |
| `r28c` | `clang-r530567e` | `ndk-r28c` | Android NDK r28c | `aarch64`, `armv7a`, `x86_64`, `i686` |
| `r29`  | `clang-r563880c` | `ndk-r29`  | Android NDK r29  | `aarch64`, `armv7a`, `x86_64`, `i686` |
| `r30`  | `clang-r574158c` | `ndk-r30`  | Android NDK r30  | `aarch64`, `armv7a`, `x86_64`, `i686` |

---

## 🚀 Quick Start & Usage

### 1. Using with Termux / Android Shell

Download the tarball matching your device architecture (most modern phones use `aarch64-linux-android`):

```bash
# 1. Download custom NDK release
wget https://github.com/Apex-Studio-Dev/apex-android-toolchains/releases/download/ndk-r26d/custom-android-ndk-r26d-aarch64-linux-android.tar.xz

# 2. Extract to your preferred location
mkdir -p ~/android-ndk-r26d
tar -xf custom-android-ndk-r26d-aarch64-linux-android.tar.xz -C ~/android-ndk-r26d --strip-components=1

# 3. Export environment variables
export ANDROID_NDK_ROOT=~/android-ndk-r26d
export PATH="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-arm64/bin:$PATH"

# 4. Verify compiler execution directly on your device
aarch64-linux-android30-clang --version
```

### 2. Using with Gradle / Android Studio

In your Android project root, set the path to your custom NDK in `local.properties`:

```properties
ndk.dir=/path/to/custom-android-ndk-r26d
```

In `app/build.gradle`:

```groovy
android {
    ndkVersion "26.3.11579264" // matches NDK r26d

    defaultConfig {
        externalNativeBuild {
            cmake {
                abiFilters 'arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'
            }
        }
    }
}
```

### 3. Using with Standalone CMake

```bash
cmake -B build -S . \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="arm64-v8a" \
  -DANDROID_PLATFORM=android-30 \
  -GNinja

ninja -C build
```

---

## ⚡ CI/CD Build & Release Automation

All compilation workflows run exclusively in cloud CI using GitHub Actions.

### GitHub Actions Dynamic Strategy Matrix

The workflows in [`.github/workflows/llvm.yml`](.github/workflows/llvm.yml) and [`.github/workflows/ndk.yml`](.github/workflows/ndk.yml) implement dynamic 2D matrices:
- **Parallel Multi-Runner Execution:** Selecting `target=all` instantiates 4 separate GitHub Actions runner VMs executing in parallel.
- **Fail-Fast Disabled (`fail-fast: false`):** A failure in one architecture does not interrupt or cancel builds for other architectures.
- **Prebuilt Artifact Reusability:** When assembling NDK releases, CI downloads the matching prebuilt LLVM artifact rather than rebuilding LLVM from source.

### Triggering Builds via GitHub CLI

```bash
# Build LLVM r487747e for all 4 host architectures in parallel:
gh workflow run llvm.yml -f revision=clang-r487747e -f target=all

# Build LLVM for a specific host architecture (e.g. aarch64):
gh workflow run llvm.yml -f revision=clang-r487747e -f target=aarch64-linux-android

# Build Custom NDK r26d for all 4 host architectures in parallel:
gh workflow run ndk.yml -f release=r26d -f target=all

# Build Custom NDK r26d for a specific host architecture:
gh workflow run ndk.yml -f release=r26d -f target=aarch64-linux-android
```

### Publishing Releases via Git Tags

Pushing a versioned tag triggers automated matrix compilation and attaches the resulting tarballs directly to GitHub Releases:

```bash
# Build and release LLVM across all 4 architectures:
git tag llvm-r487747e && git push origin llvm-r487747e

# Build and release Custom NDK across all 4 architectures:
git tag ndk-r26d && git push origin ndk-r26d
```

---

## 🛡️ Rigorous Verification Pipeline

Before packaging and uploading, every toolchain artifact is validated through automated test scripts running inside the Docker container:

### 1. LLVM Verification ([`scripts/verify-llvm.sh`](scripts/verify-llvm.sh))
- **ELF Header Inspection:** Validates binary machine architecture using `file` and `readelf -h`:
  - `aarch64-linux-android` ➔ `Class: ELF64`, `Machine: AArch64`
  - `armv7a-linux-androideabi` ➔ `Class: ELF32`, `Machine: ARM`
  - `x86_64-linux-android` ➔ `Class: ELF64`, `Machine: Advanced Micro Devices X86-64`
  - `i686-linux-android` ➔ `Class: ELF32`, `Machine: Intel 80386`
- **Compiler Sanity Execution:** Executes `clang --version`, `clang++ --version`, and `ld.lld --version` via QEMU user-static emulation.
- **Multi-Target Code Generation Test:** The newly compiled Clang compiles a test program to 4 object files (`.o`), verifying each via `readelf`:
  ```bash
  clang --target=aarch64-linux-android30 -c test.c -o test_arm64.o
  clang --target=armv7a-linux-androideabi30 -c test.c -o test_arm32.o
  clang --target=x86_64-linux-android30 -c test.c -o test_x86_64.o
  clang --target=i686-linux-android30 -c test.c -o test_x86.o
  ```

### 2. NDK Verification ([`scripts/verify-ndk.sh`](scripts/verify-ndk.sh))
- **Sysroot & Library Check:** Verifies header availability in `sysroot/usr/include` and target libraries in `sysroot/usr/lib/<target>`.
- **End-to-End Dynamic Link Verification:** Compiles `hello.c` into native executables linked against Android Bionic `libc.so` for ARM64, ARM32, x86_64, and x86, inspecting dynamic tags (`DT_NEEDED libc.so`).

---

## 📁 Repository Structure

```
apex-android-toolchains/
├── docker/
│   ├── Dockerfile                # Multi-platform builder image definition
│   └── .dockerignore
├── llvm/
│   └── patches/                  # Downstream LLVM revision patches
├── ndk/
│   ├── patches/                  # Patches for bionic sysroots and NDK build scripts
│   └── sources/                  # Source archives for GNU Make 4.4 and Yasm 1.3.0
├── metadata/
│   ├── llvm-releases.yaml        # Exact AOSP commits, manifest IDs, and branches
│   ├── ndk-releases.yaml         # NDK releases, mapped LLVM revisions & base URLs
│   └── releases.yaml             # Unified release matrix
├── scripts/
│   ├── build-llvm.sh             # Compiles LLVM/Clang with multi-arch host support
│   ├── build-ndk.sh              # Assembles Custom NDK with multi-arch host support
│   ├── build-all-llvm.sh         # Batch build coordinator for all LLVM revisions
│   ├── build-all-ndk.sh          # Batch build coordinator for all NDK releases
│   ├── fetch-llvm.sh             # Fetches prebuilt LLVM artifacts or AOSP source trees
│   ├── verify-llvm.sh            # Validates ELF headers & multi-target codegen
│   ├── verify-ndk.sh             # Validates NDK sysroots and end-to-end cross-compilation
│   ├── package-llvm.sh           # Packages custom-llvm-*.tar.xz with SHA checksums
│   └── package-ndk.sh            # Packages custom-android-ndk-*.tar.xz with SHA checksums
├── docs/
│   ├── ARCHITECTURE.md           # Architectural model & host/target decoupling
│   ├── BUILDING.md               # CI/CD and manual build documentation
│   ├── RELEASES.md               # Complete release tables and revision mappings
│   └── VERIFICATION.md           # Detailed ELF and compilation test standards
├── .github/
│   └── workflows/
│       ├── docker-image.yml      # Automated builder container publish workflow
│       ├── llvm.yml              # Dynamic matrix LLVM build & release workflow
│       ├── ndk.yml               # Dynamic matrix NDK build & release workflow
│       └── release.yml           # Release orchestration workflow
├── .gitlab-ci.yml                # GitLab CI pipeline definition
└── README.md
```

---

## 📚 Documentation Index

For in-depth technical documentation, refer to:
- [Architecture & Dependency Model](docs/ARCHITECTURE.md)
- [Building Toolchains & Workflows](docs/BUILDING.md)
- [Release Tables & Version Mappings](docs/RELEASES.md)
- [Verification Standards & Test Specifications](docs/VERIFICATION.md)

---

## 📄 License

This repository is licensed under the **MIT License**. See [LICENSE](LICENSE) for details.

*Android is a trademark of Google LLC. This project is an independent open-source toolchain development initiative by Apex Studio.*
