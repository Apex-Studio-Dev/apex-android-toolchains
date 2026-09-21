# Toolchain Verification Specifications

To guarantee correctness, portability, and reproducibility across Android Bionic and Linux ARM64 environments, every LLVM build and NDK assembly must satisfy the following verification criteria.

---

## 1. LLVM Compiler Verification

### A. Host Binary Architecture
The compiler binary itself must run natively on Linux ARM64 (AArch64):
```bash
file $LLVM_DIR/bin/clang
# Expected output:
# ELF 64-bit LSB (executable|shared object), ARM aarch64, version 1 (SYSV)...
```

### B. ELF Machine Header
```bash
readelf -h $LLVM_DIR/bin/clang
# Expected output:
# Class:   ELF64
# Machine: AArch64
```

### C. Execution Test
```bash
$LLVM_DIR/bin/clang --version
$LLVM_DIR/bin/clang++ --version
$LLVM_DIR/bin/ld.lld --version
```

### D. Target IR Code Generation Test
Compiles basic test code targeting Android ARM64 and ARM32:
```bash
# Target Android ARM64:
clang -target aarch64-linux-android -c test.c -o test_aarch64.o
readelf -h test_aarch64.o | grep "Machine:.*AArch64"

# Target Android ARM32:
clang -target arm-linux-androideabi -march=armv7-a -c test.c -o test_arm32.o
readelf -h test_arm32.o | grep "Machine:.*ARM"
```

---

## 2. NDK Toolchain Verification

Every assembled NDK must successfully cross-compile `hello.c` for both target Android architectures using its native ARM64 clang and sysroot.

### A. Target 1: Android ARM64 (`aarch64-linux-android30`)
```bash
$NDK/toolchains/llvm/prebuilt/linux-arm64/bin/aarch64-linux-android30-clang \
  hello.c -o hello_aarch64

# 1. Check file type:
file hello_aarch64
# Output must show: ELF 64-bit LSB (pie|shared object|executable), ARM aarch64

# 2. Check ELF Machine header:
readelf -h hello_aarch64 | grep "Machine:"
# Output: Machine: AArch64

# 3. Check dynamic link:
readelf -d hello_aarch64 | grep NEEDED
# Output must include: libc.so
```

### B. Target 2: Android ARM32 (`arm-linux-androideabi30`)
```bash
$NDK/toolchains/llvm/prebuilt/linux-arm64/bin/armv7a-linux-androideabi30-clang \
  hello.c -o hello_arm32

# 1. Check file type:
file hello_arm32
# Output must show: ELF 32-bit LSB (pie|shared object|executable), ARM

# 2. Check ELF Machine header:
readelf -h hello_arm32 | grep "Machine:"
# Output: Machine: ARM

# 3. Check dynamic link:
readelf -d hello_arm32 | grep NEEDED
# Output must include: libc.so
```
