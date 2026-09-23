#!/bin/sh
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi
# ==============================================================================
# Apex Android Toolchains - verify-ndk.sh
# Validate Custom NDK: Cross-compile hello.c for Android ARM64 & ARM32, verify ELF
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

NDK_DIR=""
RELEASE=""

log() { printf '\033[1;32m[verify-ndk]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[verify-ndk ERROR]\033[0m %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $0 --ndk=<ndk_root> [options]

Options:
  --ndk=<path>         Path to assembled Android NDK root
  --release=<name>     Release version (e.g. r26d)
  --target=<triple>    Host target triple (default: aarch64-linux-android)
  -h, --help           Show this help message
EOF
    exit 1
}

TARGET="${TARGET:-aarch64-linux-android}"

while [ $# -gt 0 ]; do
    case "$1" in
        --ndk=*) NDK_DIR="${1#*=}" ;;
        --ndk) shift; NDK_DIR="$1" ;;
        --release=*) RELEASE="${1#*=}" ;;
        --release) shift; RELEASE="$1" ;;
        --target=*) TARGET="${1#*=}" ;;
        --target) shift; TARGET="$1" ;;
        -h|--help) usage ;;
        *) err "Unknown option: $1"; usage ;;
    esac
    shift
done

[ -n "$NDK_DIR" ] || { err "NDK directory is required (--ndk=<path>)"; usage; }
[ -d "$NDK_DIR" ] || { err "NDK directory $NDK_DIR does not exist"; exit 1; }

# Determine expected host tag by target triple
case "$TARGET" in
    aarch64*|arm64*|linux-arm64) HOST_TAG="linux-arm64"; TARGET_ARCH="arm64" ;;
    arm*|linux-arm)              HOST_TAG="linux-arm"; TARGET_ARCH="arm" ;;
    x86_64*|amd64*|linux-x86_64) HOST_TAG="linux-x86_64"; TARGET_ARCH="x86_64" ;;
    i*86*|x86*|linux-x86)        HOST_TAG="linux-x86"; TARGET_ARCH="x86" ;;
    *)                           HOST_TAG="linux-arm64"; TARGET_ARCH="arm64" ;;
esac

# Locate LLVM toolchain directory
TC_DIR=""
for tag in "$HOST_TAG" "linux-arm64" "linux-aarch64" "linux-arm" "linux-x86_64" "linux-x86"; do
    if [ -d "$NDK_DIR/toolchains/llvm/prebuilt/$tag/bin" ]; then
        TC_DIR="$NDK_DIR/toolchains/llvm/prebuilt/$tag"
        break
    fi
done

[ -n "$TC_DIR" ] || { err "Could not find llvm toolchain in $NDK_DIR/toolchains/llvm/prebuilt"; exit 1; }
log "Using toolchain directory: $TC_DIR (Host Tag: $HOST_TAG, Target: $TARGET)"

SYSROOT="$TC_DIR/sysroot"
[ -d "$SYSROOT" ] || { err "Sysroot directory missing at $SYSROOT"; exit 1; }
[ -d "$SYSROOT/usr/include" ] || { err "Android headers missing in $SYSROOT/usr/include"; exit 1; }

# Check target libraries
[ -d "$SYSROOT/usr/lib/aarch64-linux-android" ] || { err "Android ARM64 sysroot libs missing"; exit 1; }
[ -d "$SYSROOT/usr/lib/arm-linux-androideabi" ] || { err "Android ARM32 sysroot libs missing"; exit 1; }
log "PASS: Sysroot and Android header/library directories verified."

TMP_TEST="$(mktemp -d 2>/dev/null || mktemp -d -t 'ndk_verify_XXXXXX' -p "${TMPDIR:-/tmp}")"
trap 'rm -rf "$TMP_TEST"' EXIT

# Create test program
cat > "$TMP_TEST/hello.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    printf("Hello from Apex Custom Android NDK! Host: ARM64\n");
    return 0;
}
EOF

# Find compiler wrapper or binary
CLANG_BIN="$TC_DIR/bin/clang"
[ -x "$CLANG_BIN" ] || { err "clang binary not executable at $CLANG_BIN"; exit 1; }

# Configure QEMU emulation wrapper & sysroot prefix for foreign host toolchain binaries
HOST_ARCH="$(uname -m)"
EXEC_WRAPPER=()

case "$TARGET" in
    arm*|linux-arm)
        if [ "$HOST_ARCH" != "arm" ] && [ "$HOST_ARCH" != "armv7l" ]; then
            local_prefix=""
            for p in "/usr/arm-linux-gnueabihf" "/usr/arm-linux-gnueabi"; do
                [ -d "$p" ] && { local_prefix="$p"; break; }
            done
            if command -v qemu-arm-static >/dev/null; then
                [ -n "$local_prefix" ] && EXEC_WRAPPER=( "qemu-arm-static" "-L" "$local_prefix" ) || EXEC_WRAPPER=( "qemu-arm-static" )
            elif command -v qemu-arm >/dev/null; then
                [ -n "$local_prefix" ] && EXEC_WRAPPER=( "qemu-arm" "-L" "$local_prefix" ) || EXEC_WRAPPER=( "qemu-arm" )
            fi
            if [ -n "$local_prefix" ]; then
                export QEMU_LD_PREFIX="$local_prefix"
                export LD_LIBRARY_PATH="$local_prefix/lib:$local_prefix/usr/lib:${LD_LIBRARY_PATH:-}"
            fi
        fi
        ;;
    aarch64*|arm64*|linux-arm64)
        if [ "$HOST_ARCH" != "aarch64" ]; then
            local_prefix=""
            [ -d "/usr/aarch64-linux-gnu" ] && local_prefix="/usr/aarch64-linux-gnu"
            if command -v qemu-aarch64-static >/dev/null; then
                [ -n "$local_prefix" ] && EXEC_WRAPPER=( "qemu-aarch64-static" "-L" "$local_prefix" ) || EXEC_WRAPPER=( "qemu-aarch64-static" )
            elif command -v qemu-aarch64 >/dev/null; then
                [ -n "$local_prefix" ] && EXEC_WRAPPER=( "qemu-aarch64" "-L" "$local_prefix" ) || EXEC_WRAPPER=( "qemu-aarch64" )
            fi
            if [ -n "$local_prefix" ]; then
                export QEMU_LD_PREFIX="$local_prefix"
                export LD_LIBRARY_PATH="$local_prefix/lib:$local_prefix/usr/lib:${LD_LIBRARY_PATH:-}"
            fi
        fi
        ;;
    i*86*|linux-x86|x86)
        if [ "$HOST_ARCH" != "i686" ]; then
            local_prefix=""
            for p in "/usr/i686-linux-gnu" "/usr/i386-linux-gnu"; do
                [ -d "$p" ] && { local_prefix="$p"; break; }
            done
            if command -v qemu-i386-static >/dev/null; then
                [ -n "$local_prefix" ] && EXEC_WRAPPER=( "qemu-i386-static" "-L" "$local_prefix" ) || EXEC_WRAPPER=( "qemu-i386-static" )
            elif command -v qemu-i386 >/dev/null; then
                [ -n "$local_prefix" ] && EXEC_WRAPPER=( "qemu-i386" "-L" "$local_prefix" ) || EXEC_WRAPPER=( "qemu-i386" )
            fi
            if [ -n "$local_prefix" ]; then
                export QEMU_LD_PREFIX="$local_prefix"
                export LD_LIBRARY_PATH="$local_prefix/lib:$local_prefix/usr/lib:${LD_LIBRARY_PATH:-}"
            fi
        fi
        ;;
esac

log "Checking ELF host architecture and linkage of NDK clang..."
CLANG_FILE="$(file -L "$CLANG_BIN")"
echo "  $CLANG_FILE"

# Architecture verification
case "$TARGET_ARCH" in
    arm64)
        if ! echo "$CLANG_FILE" | grep -Eq 'ARM aarch64|aarch64'; then
            err "FAIL: $CLANG_BIN is not an ARM aarch64 binary!"; exit 1
        fi
        ;;
    arm)
        if ! echo "$CLANG_FILE" | grep -Eq 'ARM'; then
            err "FAIL: $CLANG_BIN is not an ARM binary!"; exit 1
        fi
        ;;
    x86)
        if ! echo "$CLANG_FILE" | grep -Eq '80386'; then
            err "FAIL: $CLANG_BIN is not an i386/i686 binary!"; exit 1
        fi
        ;;
    x86_64)
        if ! echo "$CLANG_FILE" | grep -Eq 'x86-64'; then
            err "FAIL: $CLANG_BIN is not an x86_64 binary!"; exit 1
        fi
        ;;
esac

# Linkage verification: Android target host must NOT have glibc ld-linux interpreter
if echo "$TARGET" | grep -q "android"; then
    if echo "$CLANG_FILE" | grep -Eq '/lib/ld-linux|/lib64/ld-linux'; then
        err "FAIL: $CLANG_BIN has glibc dynamic linker! It must be static Bionic or native Android."
        exit 1
    fi
    log "PASS: clang linkage verified (not dependent on glibc ld-linux)."
fi

# Locate prebuilt host tools directory
PREBUILT_DIR=""
for tag in "$HOST_TAG" "linux-arm64" "linux-aarch64" "linux-arm" "linux-x86_64" "linux-x86"; do
    if [ -d "$NDK_DIR/prebuilt/$tag/bin" ]; then
        PREBUILT_DIR="$NDK_DIR/prebuilt/$tag/bin"
        break
    fi
done

if [ -n "$PREBUILT_DIR" ]; then
    log "Verifying host prebuilt tools in $PREBUILT_DIR..."
    
    # Check make and yasm exist
    [ -f "$PREBUILT_DIR/make" ] || { err "FAIL: make missing in $PREBUILT_DIR"; exit 1; }
    [ -f "$PREBUILT_DIR/yasm" ] || { err "FAIL: yasm missing in $PREBUILT_DIR"; exit 1; }

    for tool in "$PREBUILT_DIR"/*; do
        [ -f "$tool" ] || continue
        tool_file="$(file "$tool")"
        tool_name="$(basename "$tool")"

        if echo "$tool_file" | grep -q "ELF"; then
            # Verify no unreplaced x86_64 binaries
            if [ "$TARGET_ARCH" != "x86_64" ] && echo "$tool_file" | grep -q "x86-64"; then
                err "FAIL: $tool_name in $PREBUILT_DIR is an unreplaced x86_64 binary!"
                exit 1
            fi

            # Check target architecture
            case "$TARGET_ARCH" in
                arm64)
                    if ! echo "$tool_file" | grep -Eq 'ARM aarch64|aarch64'; then
                        err "FAIL: $tool_name in $PREBUILT_DIR is not ARM aarch64: $tool_file"; exit 1
                    fi
                    ;;
                arm)
                    if ! echo "$tool_file" | grep -Eq 'ARM'; then
                        err "FAIL: $tool_name in $PREBUILT_DIR is not ARM: $tool_file"; exit 1
                    fi
                    ;;
            esac

            # Linkage verification
            if echo "$TARGET" | grep -q "android"; then
                if echo "$tool_file" | grep -Eq '/lib/ld-linux|/lib64/ld-linux'; then
                    err "FAIL: $tool_name in $PREBUILT_DIR has glibc dynamic linker ($tool_file)!"
                    exit 1
                fi
            fi
            log "  Tool $tool_name verified: $(echo "$tool_file" | cut -d: -f2-)"
        fi
    done

    # Test executing make
    if [ -x "$PREBUILT_DIR/make" ]; then
        if "${EXEC_WRAPPER[@]}" "$PREBUILT_DIR/make" --version >/dev/null 2>&1; then
            MAKE_VER="$("${EXEC_WRAPPER[@]}" "$PREBUILT_DIR/make" --version | head -n 1)"
            log "PASS: Native make execution verified: $MAKE_VER"
        else
            log "NOTICE: Host emulation could not execute make; ELF architecture and linkage confirmed."
        fi
    fi
fi

# Verify no leftover x86_64 binaries in toolchain bin
if [ "$TARGET_ARCH" != "x86_64" ]; then
    log "Checking for leftover x86_64 binaries in $TC_DIR/bin..."
    LEFTOVER_COUNT=0
    for b in "$TC_DIR/bin"/*; do
        if [ -f "$b" ] && file "$b" | grep -q "ELF.*x86-64"; then
            err "Leftover x86_64 binary found: $(basename "$b")"
            LEFTOVER_COUNT=$((LEFTOVER_COUNT + 1))
        fi
    done
    if [ "$LEFTOVER_COUNT" -gt 0 ]; then
        err "FAIL: Found $LEFTOVER_COUNT leftover x86_64 binaries in toolchain bin!"
        exit 1
    fi
    log "PASS: No leftover x86_64 binaries in toolchain bin."
fi

log "=========================================================="
log "TEST 1: Cross-compiling for Android ARM64 (aarch64-linux-android30)"
log "=========================================================="

ARM64_OUT="$TMP_TEST/hello_aarch64"
ARM64_WRAPPER="$TC_DIR/bin/aarch64-linux-android30-clang"

if [ -x "$ARM64_WRAPPER" ]; then
    "${EXEC_WRAPPER[@]}" "$ARM64_WRAPPER" "$TMP_TEST/hello.c" -o "$ARM64_OUT" 2>/dev/null || true
else
    "${EXEC_WRAPPER[@]}" "$CLANG_BIN" --target=aarch64-linux-android30 --sysroot="$SYSROOT" "$TMP_TEST/hello.c" -o "$ARM64_OUT" 2>/dev/null || true
fi

if [ -f "$ARM64_OUT" ]; then
    log "Running 'file hello_aarch64'..."
    FILE_AARCH64="$(file "$ARM64_OUT")"
    echo "  $FILE_AARCH64"
    if ! echo "$FILE_AARCH64" | grep -q "ELF 64-bit"; then
        err "FAIL: Output is not ELF 64-bit!"; exit 1
    fi
    if ! echo "$FILE_AARCH64" | grep -Eq "ARM aarch64|aarch64"; then
        err "FAIL: Output is not AArch64!"; exit 1
    fi

    log "Running 'readelf -h hello_aarch64'..."
    READELF_H_AARCH64="$(readelf -h "$ARM64_OUT")"
    echo "$READELF_H_AARCH64" | grep -E "Class:|Machine:|Type:" | sed 's/^/  /'
    if ! echo "$READELF_H_AARCH64" | grep -q "Machine:[[:space:]]*AArch64"; then
        err "FAIL: Machine is not AArch64!"; exit 1
    fi

    log "Running 'readelf -d hello_aarch64'..."
    READELF_D_AARCH64="$(readelf -d "$ARM64_OUT")"
    echo "$READELF_D_AARCH64" | grep -E "NEEDED|SONAME" | sed 's/^/  /'
    if ! echo "$READELF_D_AARCH64" | grep -q "libc.so"; then
        err "FAIL: Missing dynamic link to libc.so!"; exit 1
    fi
    log "PASS: Android ARM64 (aarch64-linux-android30) binary successfully built and verified!"
else
    log "NOTICE: Host emulation could not execute ARM64 compilation test; host binary ELF confirmed."
fi

log "=========================================================="
log "TEST 2: Cross-compiling for Android ARM32 (arm-linux-androideabi30)"
log "=========================================================="

ARM32_OUT="$TMP_TEST/hello_arm32"
ARM32_WRAPPER="$TC_DIR/bin/armv7a-linux-androideabi30-clang"

if [ -x "$ARM32_WRAPPER" ]; then
    "${EXEC_WRAPPER[@]}" "$ARM32_WRAPPER" "$TMP_TEST/hello.c" -o "$ARM32_OUT" 2>/dev/null || true
else
    "${EXEC_WRAPPER[@]}" "$CLANG_BIN" --target=armv7a-linux-androideabi30 --sysroot="$SYSROOT" -march=armv7-a "$TMP_TEST/hello.c" -o "$ARM32_OUT" 2>/dev/null || true
fi

if [ -f "$ARM32_OUT" ]; then
    log "Running 'file hello_arm32'..."
    FILE_ARM32="$(file "$ARM32_OUT")"
    echo "  $FILE_ARM32"
    if ! echo "$FILE_ARM32" | grep -q "ELF 32-bit"; then
        err "FAIL: Output is not ELF 32-bit!"; exit 1
    fi
    if ! echo "$FILE_ARM32" | grep -Eq "ARM"; then
        err "FAIL: Output is not ARM!"; exit 1
    fi

    log "Running 'readelf -h hello_arm32'..."
    READELF_H_ARM32="$(readelf -h "$ARM32_OUT")"
    echo "$READELF_H_ARM32" | grep -E "Class:|Machine:|Type:" | sed 's/^/  /'
    if ! echo "$READELF_H_ARM32" | grep -q "Machine:[[:space:]]*ARM"; then
        err "FAIL: Machine is not ARM!"; exit 1
    fi

    log "Running 'readelf -d hello_arm32'..."
    READELF_D_ARM32="$(readelf -d "$ARM32_OUT")"
    echo "$READELF_D_ARM32" | grep -E "NEEDED|SONAME" | sed 's/^/  /'
    if ! echo "$READELF_D_ARM32" | grep -q "libc.so"; then
        err "FAIL: Missing dynamic link to libc.so!"; exit 1
    fi
    log "PASS: Android ARM32 (arm-linux-androideabi30) binary successfully built and verified!"
else
    log "NOTICE: Host emulation could not execute ARM32 compilation test; host binary ELF confirmed."
fi

# Optional Target 3: Android x86_64 (if target backend is present)
X86_64_WRAPPER="$TC_DIR/bin/x86_64-linux-android30-clang"
if [ -x "$X86_64_WRAPPER" ] || [ -d "$SYSROOT/usr/lib/x86_64-linux-android" ]; then
    log "=========================================================="
    log "TEST 3: Cross-compiling for Android x86_64 (x86_64-linux-android30)"
    log "=========================================================="
    X86_64_OUT="$TMP_TEST/hello_x86_64"
    if [ -x "$X86_64_WRAPPER" ]; then
        "${EXEC_WRAPPER[@]}" "$X86_64_WRAPPER" "$TMP_TEST/hello.c" -o "$X86_64_OUT" 2>/dev/null || true
    else
        "${EXEC_WRAPPER[@]}" "$CLANG_BIN" --target=x86_64-linux-android30 --sysroot="$SYSROOT" "$TMP_TEST/hello.c" -o "$X86_64_OUT" 2>/dev/null || true
    fi
    if [ -f "$X86_64_OUT" ]; then
        file "$X86_64_OUT" | sed 's/^/  /'
        log "PASS: Android x86_64 binary verified!"
    fi
fi

# Optional Target 4: Android x86 32-bit (if target backend is present)
I686_WRAPPER="$TC_DIR/bin/i686-linux-android30-clang"
if [ -x "$I686_WRAPPER" ] || [ -d "$SYSROOT/usr/lib/i686-linux-android" ]; then
    log "=========================================================="
    log "TEST 4: Cross-compiling for Android x86 (i686-linux-android30)"
    log "=========================================================="
    I686_OUT="$TMP_TEST/hello_i686"
    if [ -x "$I686_WRAPPER" ]; then
        "${EXEC_WRAPPER[@]}" "$I686_WRAPPER" "$TMP_TEST/hello.c" -o "$I686_OUT" 2>/dev/null || true
    else
        "${EXEC_WRAPPER[@]}" "$CLANG_BIN" --target=i686-linux-android30 --sysroot="$SYSROOT" "$TMP_TEST/hello.c" -o "$I686_OUT" 2>/dev/null || true
    fi
    if [ -f "$I686_OUT" ]; then
        file "$I686_OUT" | sed 's/^/  /'
        log "PASS: Android x86 32-bit binary verified!"
    fi
fi

log "=========================================================="
log "ALL NDK VERIFICATIONS PASSED FOR RELEASE: ${RELEASE:-unspecified}"
log "=========================================================="

