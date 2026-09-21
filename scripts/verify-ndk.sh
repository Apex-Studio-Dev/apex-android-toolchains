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
  -h, --help           Show this help message
EOF
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --ndk=*) NDK_DIR="${1#*=}" ;;
        --ndk) shift; NDK_DIR="$1" ;;
        --release=*) RELEASE="${1#*=}" ;;
        --release) shift; RELEASE="$1" ;;
        -h|--help) usage ;;
        *) err "Unknown option: $1"; usage ;;
    esac
    shift
done

[ -n "$NDK_DIR" ] || { err "NDK directory is required (--ndk=<path>)"; usage; }
[ -d "$NDK_DIR" ] || { err "NDK directory $NDK_DIR does not exist"; exit 1; }

# Locate LLVM toolchain directory
TC_DIR=""
for tag in "linux-arm64" "linux-aarch64" "linux-x86_64"; do
    if [ -d "$NDK_DIR/toolchains/llvm/prebuilt/$tag/bin" ]; then
        TC_DIR="$NDK_DIR/toolchains/llvm/prebuilt/$tag"
        break
    fi
done

[ -n "$TC_DIR" ] || { err "Could not find llvm toolchain in $NDK_DIR/toolchains/llvm/prebuilt"; exit 1; }
log "Using toolchain directory: $TC_DIR"

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

log "=========================================================="
log "TEST 1: Cross-compiling for Android ARM64 (aarch64-linux-android30)"
log "=========================================================="

ARM64_OUT="$TMP_TEST/hello_aarch64"
ARM64_WRAPPER="$TC_DIR/bin/aarch64-linux-android30-clang"

if [ -x "$ARM64_WRAPPER" ]; then
    "$ARM64_WRAPPER" "$TMP_TEST/hello.c" -o "$ARM64_OUT"
else
    "$CLANG_BIN" --target=aarch64-linux-android30 --sysroot="$SYSROOT" "$TMP_TEST/hello.c" -o "$ARM64_OUT"
fi

[ -f "$ARM64_OUT" ] || { err "FAIL: Failed to produce hello_aarch64"; exit 1; }

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

log "=========================================================="
log "TEST 2: Cross-compiling for Android ARM32 (arm-linux-androideabi30)"
log "=========================================================="

ARM32_OUT="$TMP_TEST/hello_arm32"
ARM32_WRAPPER="$TC_DIR/bin/armv7a-linux-androideabi30-clang"

if [ -x "$ARM32_WRAPPER" ]; then
    "$ARM32_WRAPPER" "$TMP_TEST/hello.c" -o "$ARM32_OUT"
else
    "$CLANG_BIN" --target=armv7a-linux-androideabi30 --sysroot="$SYSROOT" -march=armv7-a "$TMP_TEST/hello.c" -o "$ARM32_OUT"
fi

[ -f "$ARM32_OUT" ] || { err "FAIL: Failed to produce hello_arm32"; exit 1; }

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

log "=========================================================="
log "ALL NDK VERIFICATIONS PASSED FOR RELEASE: ${RELEASE:-unspecified}"
log "=========================================================="
