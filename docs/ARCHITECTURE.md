# Architecture & Dependency Model

## Overview

`apex-toolchains` is designed as an independent, reproducible toolchain monorepo providing **native execution support across Android (Bionic) and Linux (GNU) host architectures**:
1. **`aarch64-linux-android`** (`arm64-v8a`): Modern 64-bit ARM smartphones, tablets, Termux.
2. **`armv7a-linux-androideabi`** (`armeabi-v7a`): Legacy 32-bit ARM devices and embedded systems.
3. **`x86_64-linux-android`**: 64-bit Android PC emulators, Windows Subsystem for Android (WSA), and Waydroid Linux.
4. **`i686-linux-android`**: 32-bit Android PC emulators.

Regardless of which host executes the compiler, every compiler binary is a complete **multi-target cross-compiler** configured with `-DLLVM_TARGETS_TO_BUILD="AArch64;ARM;X86;RISCV"`, capable of compiling code for all Android ABIs.

---

## Dependency Model & Decoupling

```
+-------------------------------------------------------------+
|                  AOSP Git Repositories                      |
|  toolchain/llvm-project  &  toolchain/llvm_android          |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|               1. Custom LLVM Build (CI)                     |
|  - Multi-arch host compilation (aarch64, arm, x86_64, i686) |
|  - Validated ELF machine types (AArch64, ARM, X86-64, i386) |
|  - Bionic & static musl runtime compatibility               |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|               2. LLVM Release & Artifacts                   |
|  - Tag: llvm-<revision> (e.g. llvm-r487747e)                |
|  - Artifacts: custom-llvm-<rev>-<target>.tar.xz             |
|  - Checksums: SHA256SUMS & SHA512SUMS                       |
+-------------------------------------------------------------+
                              |
                              v  (Prebuilt artifact reuse)
+-------------------------------------------------------------+
|               3. Custom NDK Assembly (CI)                   |
|  - Downloads official NDK base skeleton                     |
|  - Fetches matching LLVM artifact (zero LLVM recompilation) |
|  - Compiles native host tools (GNU make 4.4, yasm 1.3.0)    |
|  - Splices host LLVM into NDK toolchains directory          |
|  - Adapts Bionic host tags, sysroots & CMake toolchains     |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|               4. NDK Verification                           |
|  - Test 1: Compile -> aarch64-linux-android30 (ARM64)       |
|  - Test 2: Compile -> armv7a-linux-androideabi30 (ARM32)    |
|  - Test 3: Compile -> x86_64-linux-android30 (x86_64)       |
|  - Test 4: Compile -> i686-linux-android30 (x86 32-bit)     |
|  - Validates dynamic link to Android Bionic libc.so         |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|               5. Custom NDK Release                         |
|  - Tag: ndk-<release> (e.g. ndk-r26d)                       |
|  - Artifacts: custom-android-ndk-rXX-<target>.tar.xz        |
|  - Checksums: SHA256SUMS & SHA512SUMS                       |
+-------------------------------------------------------------+
```

---

## Host Architecture & Bionic Execution

Standard Linux desktop binaries dynamically linked against glibc require `/lib/ld-linux-*.so`. When executed on Android (Termux, on-device mobile IDEs, or native Android shells), execution fails because Android uses **Bionic libc** and `/system/bin/linker` (or `/system/bin/linker64`).

To guarantee universal execution compatibility:
1. **Static Linking & Bionic Runtimes:**
   Host helper utilities (`make`, `yasm`) are statically compiled via Zig/musl, ensuring zero external libc runtime dependencies. LLVM/Clang binaries are built to run natively against Android Bionic or Linux.
2. **Dynamic Target Cross-Compilation:**
   When the compiler produces target code, it links against the NDK's target Bionic sysroot (`$NDK/toolchains/llvm/prebuilt/<host>/sysroot/usr/lib/<target>`), correctly emitting ELF binaries dynamically linked to Android's `libc.so`, `libm.so`, and `libdl.so`.

---

## Directory Layout in Assembled NDK

Depending on the host target architecture, the prebuilt toolchain directory is mapped appropriately:

| Host Architecture | Toolchain Path | Host Binaries Path |
| :--- | :--- | :--- |
| **`aarch64-linux-android`** | `toolchains/llvm/prebuilt/linux-arm64` | `prebuilt/linux-arm64/bin` |
| **`armv7a-linux-androideabi`** | `toolchains/llvm/prebuilt/linux-arm` | `prebuilt/linux-arm/bin` |
| **`x86_64-linux-android`** | `toolchains/llvm/prebuilt/linux-x86_64` | `prebuilt/linux-x86_64/bin` |
| **`i686-linux-android`** | `toolchains/llvm/prebuilt/linux-x86` | `prebuilt/linux-x86/bin` |

```
android-ndk-rXX/
├── build/
│   ├── cmake/
│   │   ├── android.toolchain.cmake       <-- Configured for all host architectures
│   │   └── android-legacy.toolchain.cmake
│   └── tools/
│       └── ndk_bin_common.sh             <-- Host architecture detection
├── prebuilt/
│   ├── <host_tag>/                       <-- Native GNU Make 4.4 and Yasm 1.3.0
│   └── linux-x86_64 -> <host_tag>        <-- Compatibility symlinks
└── toolchains/llvm/prebuilt/
    ├── <host_tag>/
    │   ├── bin/                          <-- Native Clang, LLD, and LLVM binaries
    │   ├── lib/clang/<ver>/              <-- Compiler runtime headers and builtins
    │   └── sysroot/                      <-- Unified Android Bionic headers and multi-ABI libs:
    │       ├── usr/include/              <-- Android Bionic API headers
    │       └── usr/lib/
    │           ├── aarch64-linux-android/
    │           ├── arm-linux-androideabi/
    │           ├── x86_64-linux-android/
    │           ├── i686-linux-android/
    │           └── riscv64-linux-android/
    └── linux-x86_64 -> <host_tag>        <-- Compatibility symlinks
```
