# Architecture & Dependency Model

## Overview

`apex-android-toolchains` is designed as an independent, reproducible toolchain monorepo targeting **Linux ARM64 / Android Bionic Host** environments to cross-compile for:
- **Android ARM64**: `aarch64-linux-android` (arm64-v8a)
- **Android ARM32**: `arm-linux-androideabi` / `armeabi-v7a`

The core architectural goal is strict decoupling between LLVM compiler builds and NDK assembly releases.

---

## Dependency Model

```
+-------------------------------------------------------------+
|                  AOSP Git Repositories                      |
|  toolchain/llvm-project  &  toolchain/llvm_android          |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|               1. Custom LLVM Build (CI)                     |
|  - Native AArch64 binary compilation                        |
|  - Validated as ELF 64-bit Machine: AArch64                 |
|  - Statically linked or Bionic-compatible runtime           |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|               2. LLVM Release & Artifact                    |
|  - Tag: llvm-<revision> (e.g. llvm-r487747e)                |
|  - Artifact: custom-llvm-<rev>-linux-arm64.tar.xz           |
|  - SHA256 & SHA512 Checksums                                |
+-------------------------------------------------------------+
                              |
                              v  (Prebuilt artifact reuse)
+-------------------------------------------------------------+
|               3. Custom NDK Assembly (CI)                   |
|  - Downloads official NDK base skeleton                     |
|  - Fetches matching LLVM artifact (NO LLVM rebuild!)        |
|  - Builds native host tools (GNU make 4.4, yasm 1.3.0)      |
|  - Splices ARM64 LLVM into NDK toolchain directory          |
|  - Configures Bionic/Linux host tags & CMake toolchains     |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|               4. NDK Verification                           |
|  - Compile hello.c -> aarch64-linux-android30 (ARM64)       |
|  - Compile hello.c -> arm-linux-androideabi30 (ARM32)       |
|  - Inspect ELF headers (readelf -h, readelf -d, file)       |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|               5. Custom NDK Release                         |
|  - Tag: ndk-<release> (e.g. ndk-r26d)                       |
|  - Artifact: custom-android-ndk-rXX-linux-arm64.tar.xz      |
|  - SHA256 & SHA512 Checksums                                |
+-------------------------------------------------------------+
```

---

## Host Architecture: Bionic vs Linux ARM64

Standard Linux ARM64 binaries compiled dynamically against glibc require `/lib/ld-linux-aarch64.so.1`. When run on Android (such as in Termux or on-device IDEs), execution fails because Android uses **Bionic libc** and `/system/bin/linker64`.

To provide execution compatibility:
1. **Static Linking / Musl / Bionic Runtime**:
   The compiler binaries are statically linked or targeted to Bionic. This allows the host binaries (`clang`, `clang++`, `ld.lld`, `llvm-*`, `make`, `yasm`) to run natively inside Android/Termux as well as any Linux ARM64 distribution (Ubuntu, Debian, Fedora, Alpine) without linker discrepancies.
2. **Dynamic Target Cross-Compilation**:
   While host tools execute on ARM64, their target outputs link against the NDK's target Bionic sysroot (`$NDK/toolchains/llvm/prebuilt/linux-arm64/sysroot`), correctly producing Android dynamic executables linking against `libc.so`, `libm.so`, `libdl.so`.

---

## Directory Layout in Assembled NDK

```
android-ndk-rXX/
├── build/
│   ├── cmake/
│   │   ├── android.toolchain.cmake       <-- Patched for linux-arm64 / Bionic
│   │   └── android-legacy.toolchain.cmake
│   └── tools/
│       └── ndk_bin_common.sh             <-- Patched HOST_ARCH for aarch64
├── prebuilt/
│   ├── linux-arm64/                      <-- Replaced with native ARM64 make, yasm
│   ├── linux-aarch64 -> linux-arm64      <-- Compatibility symlink
│   └── linux-x86_64 -> linux-arm64       <-- Compatibility symlink
└── toolchains/llvm/prebuilt/
    ├── linux-arm64/
    │   ├── bin/                          <-- ELF 64-bit AArch64 Clang/LLD/LLVM tools
    │   ├── lib/clang/<ver>/              <-- Resource headers and target runtimes
    │   └── sysroot/                      <-- Android headers and bionic target libs
    ├── linux-aarch64 -> linux-arm64      <-- Symlink
    └── linux-x86_64 -> linux-arm64       <-- Symlink
```
