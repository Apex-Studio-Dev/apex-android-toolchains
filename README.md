# apex-android-toolchains

Monorepo for building **Custom Android LLVM/Clang** and **Custom Android NDK** with **Linux ARM64 (aarch64) Host**, supporting execution on **Android Bionic** (Termux, on-device IDEs) and standard Linux ARM64 distributions.

---

## 🎯 Architectures

### Host Execution Platforms (Where the toolchains run)
Supports native execution on Android (Bionic / Termux) and Linux for **all 4 Android architectures**:
1. `aarch64-linux-android` (Android ARM64 / `arm64-v8a`)
2. `armv7a-linux-androideabi` (Android ARM32 / `armeabi-v7a`)
3. `x86_64-linux-android` (Android x86_64 / Waydroid / WSA)
4. `i686-linux-android` (Android x86 32-bit / Emulator)

### Target Architectures (What the toolchains compile code for)
Every single toolchain variant is a full **multi-target cross-compiler** capable of generating code for:
- `arm64-v8a` (`aarch64-linux-android`)
- `armeabi-v7a` (`arm-linux-androideabi`)
- `x86_64` (`x86_64-linux-android`)
- `x86` (`i686-linux-android`)
- `riscv64` (`riscv64-linux-android`)

---

## 📦 Releases Overview

### 1. LLVM Releases (Exact AOSP Revisions)

Built independently, validated as native **ELF 64-bit AArch64**, packaged with SHA256/SHA512 checksums, and reusable by NDK releases without recompilation.

| LLVM Major | Clang Revision | Git Tag | Artifact |
| :---: | :---: | :---: | :--- |
| **LLVM 17** | `clang-r487747c` | `llvm-r487747c` | `custom-llvm-r487747c-linux-arm64.tar.xz` |
| **LLVM 17** | `clang-r487747d` | `llvm-r487747d` | `custom-llvm-r487747d-linux-arm64.tar.xz` |
| **LLVM 17** | `clang-r487747e` | `llvm-r487747e` | `custom-llvm-r487747e-linux-arm64.tar.xz` |
| **LLVM 18** | `clang-r522817`  | `llvm-r522817`  | `custom-llvm-r522817-linux-arm64.tar.xz` |
| **LLVM 18** | `clang-r522817b` | `llvm-r522817b` | `custom-llvm-r522817b-linux-arm64.tar.xz` |
| **LLVM 18** | `clang-r522817c` | `llvm-r522817c` | `custom-llvm-r522817c-linux-arm64.tar.xz` |
| **LLVM 18** | `clang-r522817d` | `llvm-r522817d` | `custom-llvm-r522817d-linux-arm64.tar.xz` |
| **LLVM 19** | `clang-r530567b` | `llvm-r530567b` | `custom-llvm-r530567b-linux-arm64.tar.xz` |
| **LLVM 19** | `clang-r530567d` | `llvm-r530567d` | `custom-llvm-r530567d-linux-arm64.tar.xz` |
| **LLVM 19** | `clang-r530567e` | `llvm-r530567e` | `custom-llvm-r530567e-linux-arm64.tar.xz` |
| **LLVM 21** | `clang-r563880c` | `llvm-r563880c` | `custom-llvm-r563880c-linux-arm64.tar.xz` |
| **LLVM 21** | `clang-r574158c` | `llvm-r574158c` | `custom-llvm-r574158c-linux-arm64.tar.xz` |

### 2. Custom Android NDK Releases

Assembled from official AOSP NDK skeletons, spliced with native ARM64 LLVM artifacts and native ARM64 host tools (`make 4.4`, `yasm 1.3.0`).

| NDK Release | Clang Revision | Git Tag | Artifact |
| :---: | :---: | :---: | :--- |
| `r26`  | `clang-r487747c` | `ndk-r26`  | `custom-android-ndk-r26-linux-arm64.tar.xz` |
| `r26b` | `clang-r487747d` | `ndk-r26b` | `custom-android-ndk-r26b-linux-arm64.tar.xz` |
| `r26c` | `ndk-r26c`       | `ndk-r26c` | `custom-android-ndk-r26c-linux-arm64.tar.xz` |
| `r26d` | `clang-r487747e` | `ndk-r26d` | `custom-android-ndk-r26d-linux-arm64.tar.xz` |
| `r27`  | `clang-r522817`  | `ndk-r27`  | `custom-android-ndk-r27-linux-arm64.tar.xz` |
| `r27b` | `clang-r522817b` | `ndk-r27b` | `custom-android-ndk-r27b-linux-arm64.tar.xz` |
| `r27c` | `clang-r522817c` | `ndk-r27c` | `custom-android-ndk-r27c-linux-arm64.tar.xz` |
| `r27d` | `clang-r522817d` | `ndk-r27d` | `custom-android-ndk-r27d-linux-arm64.tar.xz` |
| `r28`  | `clang-r530567b` | `ndk-r28`  | `custom-android-ndk-r28-linux-arm64.tar.xz` |
| `r28b` | `clang-r530567d` | `ndk-r28b` | `custom-android-ndk-r28b-linux-arm64.tar.xz` |
| `r28c` | `clang-r530567e` | `ndk-r28c` | `custom-android-ndk-r28c-linux-arm64.tar.xz` |
| `r29`  | `clang-r563880c` | `ndk-r29`  | `custom-android-ndk-r29-linux-arm64.tar.xz` |
| `r30`  | `clang-r574158c` | `ndk-r30`  | `custom-android-ndk-r30-linux-arm64.tar.xz` |

---

## ⚡ CI/CD Build Instructions

All builds run on **GitHub Actions** and **GitLab CI** using the identical scripts in `scripts/`.

### GitHub Actions
```bash
# Build LLVM via workflow_dispatch
gh workflow run llvm.yml -f revision=clang-r487747e -f platform=bionic

# Build NDK via workflow_dispatch (automatically uses prebuilt LLVM artifact)
gh workflow run ndk.yml -f release=r26d -f platform=bionic

# Automatic build & release via Git tags
git tag llvm-r487747e && git push origin llvm-r487747e
git tag ndk-r26d && git push origin ndk-r26d
```

### Docker Builder Container
The toolchains build environment is encapsulated in a dedicated builder image:
`ghcr.io/apex-studio-dev/apex-toolchains-builder:latest`
- Built from `docker/Dockerfile` and automatically published via `.github/workflows/docker-image.yml`.
- Pre-equipped with Clang, LLD, CMake, Ninja, Zig cross-compilers, QEMU ARM64 user emulation, and packaging tools.
- CI workflows automatically pull this container and mount `/mnt/build` into `/work`.

### CI Runner Disk & Swap Optimization
LLVM builds require substantial disk space and swap. CI workflows incorporate `easimon/maximize-build-space@v10`:
1. Cleans unneeded packages (`dotnet`, `android`, `haskell`, `codeql`) to free ~50+ GB.
2. Allocates dedicated swap file on `/mnt`.
3. Moves Docker storage root to `/mnt/docker`.
4. Relocates `$GITHUB_WORKSPACE` to `/mnt/build`.

---

## 🔍 Validation Standards

Every toolchain artifact is validated prior to packaging:
1. **ELF AArch64 Check**:
   ```bash
   file bin/clang
   readelf -h bin/clang | grep "Machine:.*AArch64"
   ```
2. **Compiler Execution**:
   ```bash
   clang --version && clang++ --version && ld.lld --version
   ```
3. **Cross-Compilation Verification**:
   ```bash
   # Android ARM64:
   aarch64-linux-android30-clang hello.c -o hello_aarch64
   readelf -h hello_aarch64 | grep "Machine:.*AArch64"

   # Android ARM32:
   armv7a-linux-androideabi30-clang hello.c -o hello_arm32
   readelf -h hello_arm32 | grep "Machine:.*ARM"
   ```

---

## 📁 Repository Layout

```
apex-android-toolchains/
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
│   ├── build-llvm.sh             # Build native ARM64 LLVM/Clang
│   ├── build-ndk.sh              # Assemble Custom NDK from LLVM artifact
│   ├── build-all-llvm.sh         # Batch build all LLVM revisions
│   ├── build-all-ndk.sh          # Batch build all NDK releases
│   ├── fetch-llvm.sh             # Fetch prebuilt LLVM artifact or AOSP source
│   ├── verify-llvm.sh            # Validate ELF headers & compiler versions
│   ├── verify-ndk.sh             # Validate cross-compilation (ARM64 & ARM32)
│   ├── package-llvm.sh           # Package custom-llvm-*.tar.xz with SHA checksums
│   └── package-ndk.sh            # Package custom-android-ndk-*.tar.xz with SHA checksums
├── docs/
│   ├── ARCHITECTURE.md           # Architecture and dependency model
│   ├── BUILDING.md               # CI/CD and manual build documentation
│   ├── RELEASES.md               # Complete release tables
│   └── VERIFICATION.md           # ELF and cross-compilation verification tests
├── .github/
│   └── workflows/
│       ├── llvm.yml              # GitHub Actions LLVM workflow
│       ├── ndk.yml               # GitHub Actions NDK workflow
│       ├── verify.yml            # CI verification test suite
│       └── release.yml           # Release orchestration workflow
├── .gitlab-ci.yml                # GitLab CI pipeline
└── README.md
```

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
