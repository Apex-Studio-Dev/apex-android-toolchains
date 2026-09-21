# Building via CI/CD (GitHub Actions & GitLab CI)

Due to the heavy resource requirements of LLVM and Android NDK builds, all builds are automated to run via **GitHub Actions** and **GitLab CI**.

---

## 1. Triggering via GitHub Actions

### A. Manual Build (workflow_dispatch)

You can trigger builds directly using GitHub Web UI or the `gh` CLI:

#### Build LLVM:
```bash
# Build specific Clang revision
gh workflow run llvm.yml -f revision=clang-r487747e -f platform=bionic

# Build LLVM 18
gh workflow run llvm.yml -f revision=clang-r522817d -f platform=bionic

# Build LLVM 21
gh workflow run llvm.yml -f revision=clang-r574158c -f platform=bionic
```

#### Build Custom NDK:
```bash
# Build NDK r26d (automatically uses prebuilt custom-llvm-r487747e-linux-arm64.tar.xz)
gh workflow run ndk.yml -f release=r26d -f platform=bionic

# Build NDK r28c
gh workflow run ndk.yml -f release=r28c -f platform=bionic

# Build NDK r30
gh workflow run ndk.yml -f release=r30 -f platform=bionic
```

### B. Triggering via Git Tag Push

Pushing release tags automatically triggers the respective build, verification, and release packaging jobs:

```bash
# Trigger LLVM build & release
git tag llvm-r487747e
git push origin llvm-r487747e

# Trigger NDK build & release
git tag ndk-r26d
git push origin ndk-r26d
```

---

## 2. Triggering via GitLab CI

GitLab CI uses the `.gitlab-ci.yml` pipeline configured for Linux ARM64 runners:

- **Web UI Pipeline Run**:
  Navigate to **CI/CD -> Pipelines -> Run Pipeline**.
  Set `TARGET_REVISION=clang-r487747e` or `TARGET_RELEASE=r26d`.
- **Git Tag Trigger**:
  Push tags matching `llvm-*` or `ndk-*`.

---

## 3. Local Script Reference

All CI workflows execute identical scripts located in `scripts/`:

| Script | Purpose |
| :--- | :--- |
| `scripts/fetch-llvm.sh` | Downloads release artifact or shallow-fetches exact AOSP commit |
| `scripts/build-llvm.sh` | Compiles native ARM64 LLVM/Clang with exact commits & patches |
| `scripts/verify-llvm.sh` | Validates ELF AArch64 machine headers and compiler version |
| `scripts/package-llvm.sh` | Packs tarball and computes SHA256/SHA512 checksums |
| `scripts/build-ndk.sh` | Assembles Custom NDK using prebuilt LLVM artifact |
| `scripts/verify-ndk.sh` | Cross-compiles hello.c for Android ARM64 and ARM32 |
| `scripts/package-ndk.sh` | Packs Custom NDK archive and generates checksums |
| `scripts/build-all-llvm.sh`| Orchestrates builds across all 12 LLVM revisions |
| `scripts/build-all-ndk.sh` | Orchestrates builds across all 13 NDK releases |
