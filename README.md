# apex-android-toolchains

Monorepo for building **Custom Android LLVM/Clang** and **Custom Android NDK** with native execution support across **all 4 Android host architectures**, supporting execution on **Android Bionic** (Termux, on-device IDEs), Android Emulators, and standard Linux distributions.

---

## 🎯 Architecture Support

### 1. Host Execution Architectures (Where the toolchains run)
The toolchain binaries (`clang`, `ld.lld`, `make`, `yasm`, etc.) are built for native execution across 4 distinct host architectures:

| Host Architecture | ABI / Target Triple | Platform / Use Case |
| :--- | :--- | :--- |
| **ARM64** | `aarch64-linux-android` (`arm64-v8a`) | Modern Android smartphones, tablets, Termux |
| **ARM32** | `armv7a-linux-androideabi` (`armeabi-v7a`) | Legacy 32-bit Android devices, IoT devices |
| **x86_64** | `x86_64-linux-android` | Android PC Emulators, WSA, Waydroid Linux |
| **x86 (32-bit)** | `i686-linux-android` | 32-bit Android PC Emulators |

### 2. Target Compilation Architectures (What the toolchains compile for)
Regardless of which host architecture executes the compiler, **every single toolchain binary is a full multi-target cross-compiler** configured with `-DLLVM_TARGETS_TO_BUILD="AArch64;ARM;X86;RISCV"`.

A single Clang binary running on any host can cross-compile C/C++ source code to:
- `arm64-v8a` (`aarch64-linux-android`)
- `armeabi-v7a` (`arm-linux-androideabi`)
- `x86_64` (`x86_64-linux-android`)
- `x86` (`i686-linux-android`)
- `riscv64` (`riscv64-linux-android`)

---

## 🐳 Docker Builder Container

CI and local builds run inside a dedicated, multiplatform builder container:

**`ghcr.io/apex-studio-dev/apex-toolchains-builder:latest`**

- **Supported Container Hosts:** `linux/amd64` (Standard CI runners, PC) and `linux/arm64` (Apple Silicon, ARM64 servers).
- **Pre-installed Cross-Compilers:**
  - `gcc-aarch64-linux-gnu` / `g++-aarch64-linux-gnu`
  - `gcc-arm-linux-gnueabihf` / `g++-arm-linux-gnueabihf`
  - `gcc-i686-linux-gnu` / `g++-i686-linux-gnu`
  - `zig` (for static musl / bionic C/C++ cross-compilation)
- **Host Tools:** Clang 18, LLD, CMake, Ninja, Python 3, ccache, patchelf, aria2, and QEMU user emulation.

> **Note:** The builder container runs on 64-bit hosts (`amd64` and `arm64`) and uses cross-compilers to generate the 4 Android toolchain variants (including 32-bit `armv7a` and `i686`).

---

## 📦 Releases & Artifact Conventions

Artifacts published to GitHub Releases follow consistent, structured naming:

* **LLVM Artifact:** `custom-llvm-<revision>-<target>.tar.xz`
  *(e.g. `custom-llvm-r487747e-aarch64-linux-android.tar.xz`)*
* **NDK Artifact:** `custom-android-ndk-<release>-<target>.tar.xz`
  *(e.g. `custom-android-ndk-r26d-aarch64-linux-android.tar.xz`)*
* **Backward-Compatible Alias:** For ARM64 targets, a symlink `*-linux-arm64.tar.xz` is also provided.
* **Integrity:** Every release includes cryptographic checksums in `SHA256SUMS` and `SHA512SUMS`.

### 1. LLVM Revisions (Exact AOSP Commits)

| LLVM Major | Clang Revision | AOSP Branch / Manifest ID | Git Tag | Available Host Architectures |
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

Assembled from official AOSP NDK skeletons, spliced with native LLVM compiler binaries for the target host, and equipped with native GNU Make 4.4 and Yasm 1.3.0.

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

## ⚡ CI/CD Build Instructions

All builds execute via GitHub Actions using the dedicated builder container with build space optimization and ccache.

### Triggering via GitHub CLI

```bash
# Build LLVM r487747e for all 4 host architectures concurrently:
gh workflow run llvm.yml -f revision=clang-r487747e -f target=all

# Build LLVM for a specific host architecture (e.g. aarch64):
gh workflow run llvm.yml -f revision=clang-r487747e -f target=aarch64-linux-android

# Build Custom NDK r26d for all 4 host architectures:
gh workflow run ndk.yml -f release=r26d -f target=all

# Build Custom NDK r26d for a specific host architecture:
gh workflow run ndk.yml -f release=r26d -f target=aarch64-linux-android
```

### Triggering via Git Tags

Pushing a tag automatically initiates the multi-architecture matrix build and publishes releases:
```bash
# Release LLVM (all 4 architectures):
git tag llvm-r487747e && git push origin llvm-r487747e

# Release NDK (all 4 architectures):
git tag ndk-r26d && git push origin ndk-r26d
```

### CI Strategy Matrix & Optimization
- **Dynamic 2D Matrix:** Dynamically scales jobs based on selected revisions/releases and target architectures. When `target=all` is selected, 4 independent runner VMs execute concurrently.
- **Fail-Fast Disabled (`fail-fast: false`):** Failure in one architecture does not abort builds for the remaining architectures.
- **Build Space Maximization (`easimon/maximize-build-space@v10`):** Removes unneeded pre-installed software on GitHub runners to free ~50+ GB of disk space on `/mnt/build`.
- **OOM Protection:** Uses `-DLLVM_PARALLEL_COMPILE_JOBS=$(nproc)` and enforces `-DLLVM_PARALLEL_LINK_JOBS=1` with `lld` to prevent exit code 137 (OOM-killer).

---

## 🔍 Validation Standards

Every toolchain artifact is validated by [`scripts/verify-llvm.sh`](scripts/verify-llvm.sh) prior to packaging:

1. **ELF Header & Machine Validation:**
   - `aarch64-linux-android`: Verified as `ELF64` and `Machine: AArch64`
   - `armv7a-linux-androideabi`: Verified as `ELF32` and `Machine: ARM`
   - `x86_64-linux-android`: Verified as `ELF64` and `Machine: Advanced Micro Devices X86-64`
   - `i686-linux-android`: Verified as `ELF32` and `Machine: Intel 80386`
2. **Compiler & Tool Execution:**
   - `clang --version`, `clang++ --version`, `ld.lld --version`
3. **Multi-Target Code Generation Verification:**
   Validates that the compiler can generate valid object code for all Android target ABIs:
   ```bash
   clang --target=aarch64-linux-android30 -c test.c -o test_arm64.o
   clang --target=armv7a-linux-androideabi30 -c test.c -o test_arm32.o
   clang --target=x86_64-linux-android30 -c test.c -o test_x86_64.o
   clang --target=i686-linux-android30 -c test.c -o test_x86.o
   ```

---

## 📁 Repository Layout

```
apex-android-toolchains/
├── docker/
│   ├── Dockerfile                # Multiplatform builder container (amd64 & arm64)
│   └── .dockerignore
├── llvm/
│   └── patches/                  # LLVM revision patches
├── ndk/
│   ├── patches/                  # Patches for bionic, cmake, and ndk scripts
│   └── sources/                  # Sources for make 4.4 and yasm 1.3.0
├── metadata/
│   ├── llvm-releases.yaml        # Exact AOSP commits and manifest IDs
│   ├── ndk-releases.yaml         # NDK releases, mapped LLVM & official bases
│   └── releases.yaml             # Unified release matrix
├── scripts/
│   ├── build-llvm.sh             # Build LLVM/Clang with --target support
│   ├── build-ndk.sh              # Assemble Custom NDK with --target support
│   ├── build-all-llvm.sh         # Batch build all LLVM revisions
│   ├── build-all-ndk.sh          # Batch build all NDK releases
│   ├── fetch-llvm.sh             # Fetch prebuilt LLVM artifact or AOSP source
│   ├── verify-llvm.sh            # Dynamic ELF & multi-arch codegen validation
│   ├── package-llvm.sh           # Package custom-llvm-*.tar.xz with SHA checksums
│   └── package-ndk.sh            # Package custom-android-ndk-*.tar.xz with SHA checksums
├── docs/
│   ├── ARCHITECTURE.md           # Architecture and dependency model
│   ├── BUILDING.md               # CI/CD and manual build documentation
│   ├── RELEASES.md               # Complete release tables
│   └── VERIFICATION.md           # ELF and cross-compilation verification tests
├── .github/
│   └── workflows/
│       ├── docker-image.yml      # Multiplatform builder container publish workflow
│       ├── llvm.yml              # Dynamic matrix LLVM build & release workflow
│       ├── ndk.yml               # Dynamic matrix NDK build & release workflow
│       └── release.yml           # Release orchestration workflow
├── .gitlab-ci.yml                # GitLab CI pipeline
└── README.md
```

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
