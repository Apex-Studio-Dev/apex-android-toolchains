# Building via CI/CD (GitHub Actions & GitLab CI)

Due to the heavy resource requirements of LLVM and Android NDK builds, all builds are automated to run via **GitHub Actions** and **GitLab CI** inside dedicated multiplatform Docker builder containers.

---

## 1. Triggering via GitHub Actions

### A. Manual Build (`workflow_dispatch`)

You can trigger builds directly using the GitHub Web UI or the `gh` CLI:

#### Build LLVM:
```bash
# Build LLVM r487747e for all 4 host architectures in parallel:
gh workflow run llvm.yml -f revision=clang-r487747e -f target=all

# Build LLVM for a specific host architecture:
gh workflow run llvm.yml -f revision=clang-r487747e -f target=aarch64-linux-android
gh workflow run llvm.yml -f revision=clang-r487747e -f target=armv7a-linux-androideabi
gh workflow run llvm.yml -f revision=clang-r487747e -f target=x86_64-linux-android
gh workflow run llvm.yml -f revision=clang-r487747e -f target=i686-linux-android
```

#### Build Custom NDK:
```bash
# Build Custom NDK r26d for all 4 host architectures in parallel:
gh workflow run ndk.yml -f release=r26d -f target=all

# Build Custom NDK for a specific host architecture:
gh workflow run ndk.yml -f release=r26d -f target=aarch64-linux-android
gh workflow run ndk.yml -f release=r28c -f target=x86_64-linux-android
```

### B. Triggering via Git Tag Push

Pushing release tags automatically triggers the dynamic matrix build, verification, and release packaging jobs for all 4 host architectures:

```bash
# Trigger LLVM build & release across all 4 architectures:
git tag llvm-r487747e
git push origin llvm-r487747e

# Trigger NDK build & release across all 4 architectures:
git tag ndk-r26d
git push origin ndk-r26d
```

---

## 2. Docker Builder Container

All compilation runs inside a reproducible container:
`ghcr.io/apex-studio-dev/apex-toolchains-builder:latest`

- **Architectures:** Built for `linux/amd64` (GitHub Actions runner standard) and `linux/arm64`.
- **Pre-installed Cross-Compilers:**
  - `gcc-aarch64-linux-gnu` / `g++-aarch64-linux-gnu`
  - `gcc-arm-linux-gnueabihf` / `g++-arm-linux-gnueabihf`
  - `gcc-i686-linux-gnu` / `g++-i686-linux-gnu`
  - `zig`
- **Host Tools:** Clang 18, LLD, CMake, Ninja, Python 3, ccache, patchelf, aria2, and QEMU user emulation (`qemu-user-static`).

---

## 3. Local Script Reference

All CI workflows execute identical scripts located in `scripts/`:

| Script | Purpose |
| :--- | :--- |
| `scripts/fetch-llvm.sh` | Downloads release artifact or shallow-fetches exact AOSP commit |
| `scripts/build-llvm.sh` | Compiles LLVM/Clang with `--target` support for all 4 host architectures |
| `scripts/verify-llvm.sh` | Validates ELF headers and multi-target code generation across all 4 ABIs |
| `scripts/package-llvm.sh` | Packs tarball and computes SHA256/SHA512 checksums |
| `scripts/build-ndk.sh` | Assembles Custom NDK with `--target` support using prebuilt LLVM artifact |
| `scripts/verify-ndk.sh` | Cross-compiles hello.c for Android ARM64, ARM32, x86_64, and x86 |
| `scripts/package-ndk.sh` | Packs Custom NDK archive and generates checksums |
| `scripts/build-all-llvm.sh`| Orchestrates builds across all LLVM revisions |
| `scripts/build-all-ndk.sh` | Orchestrates builds across all NDK releases |
