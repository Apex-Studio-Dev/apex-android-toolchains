# Toolchain Verification Specifications

To guarantee correctness, portability, and reproducibility across Android Bionic and Linux environments, every LLVM build and NDK assembly must satisfy the following verification criteria before release.

---

## 1. LLVM Compiler Verification (`scripts/verify-llvm.sh`)

### A. Host Binary Architecture & ELF Header Validation
The compiler binary itself must run natively on the target host architecture:

| Target Architecture | Expected ELF Class | Expected Machine | File Architecture Pattern |
| :--- | :--- | :--- | :--- |
| **`aarch64-linux-android`** | `ELF64` | `AArch64` | `aarch64` or `ARM aarch64` |
| **`armv7a-linux-androideabi`** | `ELF32` | `ARM` | `ELF 32-bit.*ARM` |
| **`x86_64-linux-android`** | `ELF64` | `Advanced Micro Devices X86-64` | `x86-64` or `x86_64` |
| **`i686-linux-android`** | `ELF32` | `Intel 80386` | `Intel 80386` |

```bash
# Check with file:
file -L $LLVM_DIR/bin/clang

# Check with readelf:
readelf -h $LLVM_DIR/bin/clang | grep -E "Class:|Machine:"
```

### B. Execution Test
Compiler binaries are invoked (via QEMU user-static if running cross-architecture on x86_64 host):
```bash
$LLVM_DIR/bin/clang --version
$LLVM_DIR/bin/clang++ --version
$LLVM_DIR/bin/ld.lld --version
```

### C. Multi-Target Code Generation Test
Validates that the single compiler can generate valid object code for all Android target architectures:
```bash
# Target Android ARM64:
clang --target=aarch64-linux-android30 -c test.c -o test_arm64.o
readelf -h test_arm64.o | grep "Machine:.*AArch64"

# Target Android ARM32:
clang --target=armv7a-linux-androideabi30 -c test.c -o test_arm32.o
readelf -h test_arm32.o | grep "Machine:.*ARM"

# Target Android x86_64:
clang --target=x86_64-linux-android30 -c test.c -o test_x86_64.o
readelf -h test_x86_64.o | grep -E "Machine:.*(Advanced Micro Devices X86-64|x86-64)"

# Target Android x86 32-bit:
clang --target=i686-linux-android30 -c test.c -o test_x86.o
readelf -h test_x86.o | grep -E "Machine:.*(Intel 80386|i386)"
```

---

## 2. NDK Toolchain Verification (`scripts/verify-ndk.sh`)

Every assembled NDK must successfully cross-compile `hello.c` for all target Android architectures using its native Clang binary and Android Bionic sysroot.

### A. Sysroot & Library Verification
```bash
# Sysroot structure check:
[ -d "$TC_DIR/sysroot/usr/include" ]
[ -d "$TC_DIR/sysroot/usr/lib/aarch64-linux-android" ]
[ -d "$TC_DIR/sysroot/usr/lib/arm-linux-androideabi" ]
[ -d "$TC_DIR/sysroot/usr/lib/x86_64-linux-android" ]
[ -d "$TC_DIR/sysroot/usr/lib/i686-linux-android" ]
```

### B. Compilation & Dynamic Link Verification
Each target executable is compiled with dynamic linkage to Android's `libc.so`:

1. **Android ARM64 (`aarch64-linux-android30`)**:
   ```bash
   $TC_DIR/bin/aarch64-linux-android30-clang hello.c -o hello_aarch64
   readelf -h hello_aarch64 | grep "Machine:[[:space:]]*AArch64"
   readelf -d hello_aarch64 | grep "NEEDED.*libc.so"
   ```

2. **Android ARM32 (`armv7a-linux-androideabi30`)**:
   ```bash
   $TC_DIR/bin/armv7a-linux-androideabi30-clang hello.c -o hello_arm32
   readelf -h hello_arm32 | grep "Machine:[[:space:]]*ARM"
   readelf -d hello_arm32 | grep "NEEDED.*libc.so"
   ```

3. **Android x86_64 (`x86_64-linux-android30`)**:
   ```bash
   $TC_DIR/bin/x86_64-linux-android30-clang hello.c -o hello_x86_64
   readelf -h hello_x86_64 | grep -E "Machine:.*(Advanced Micro Devices X86-64|x86-64)"
   ```

4. **Android x86 32-bit (`i686-linux-android30`)**:
   ```bash
   $TC_DIR/bin/i686-linux-android30-clang hello.c -o hello_i686
   readelf -h hello_i686 | grep -E "Machine:.*(Intel 80386|i386)"
   ```

---

## 3. Release Gate Condition

In CI, any failure during step 1 or 2 aborts the job immediately. No broken, unverified, or misconfigured toolchains will ever be packaged or uploaded to GitHub Releases.
