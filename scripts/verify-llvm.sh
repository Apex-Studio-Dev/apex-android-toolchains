#!/bin/sh
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi
# ==============================================================================
# Apex Android Toolchains - verify-llvm.sh
# Validate that the LLVM toolchain is native Linux ARM64 (AArch64) and operational
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LLVM_DIR=""
REVISION=""

log() { printf '\033[1;32m[verify-llvm]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[verify-llvm ERROR]\033[0m %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $0 --dir=<llvm_install_dir> [options]

Options:
  --dir=<path>         Path to LLVM installation prefix (contains bin/lib)
  --revision=<name>    Revision name (for reporting)
  -h, --help           Show this help message
EOF
    exit 1
}

TARGET="${TARGET:-aarch64-linux-android}"

while [ $# -gt 0 ]; do
    case "$1" in
        --dir=*) LLVM_DIR="${1#*=}" ;;
        --dir) shift; LLVM_DIR="$1" ;;
        --revision=*) REVISION="${1#*=}" ;;
        --revision) shift; REVISION="$1" ;;
        --target=*) TARGET="${1#*=}" ;;
        --target) shift; TARGET="$1" ;;
        -h|--help) usage ;;
        *) err "Unknown option: $1"; usage ;;
    esac
    shift
done

[ -n "$LLVM_DIR" ] || { err "LLVM directory is required (--dir=<path>)"; usage; }

BIN_DIR="$LLVM_DIR/bin"
[ -d "$BIN_DIR" ] || { err "Directory $BIN_DIR does not exist"; exit 1; }

CLANG="$BIN_DIR/clang"
CLANGXX="$BIN_DIR/clang++"
LLD="$BIN_DIR/ld.lld"

[ -f "$CLANG" ] || [ -L "$CLANG" ] || { err "Missing $CLANG"; exit 1; }
[ -f "$CLANGXX" ] || [ -L "$CLANGXX" ] || { err "Missing $CLANGXX"; exit 1; }
[ -f "$LLD" ] || [ -L "$LLD" ] || { err "Missing $LLD"; exit 1; }

# Determine expected ELF machine by target
case "$TARGET" in
    aarch64*|arm64*|linux-arm64)
        EXPECTED_CLASS="ELF64"
        EXPECTED_MACHINE="AArch64"
        FILE_PATTERN="aarch64|ARM aarch64"
        ;;
    arm*|linux-arm)
        EXPECTED_CLASS="ELF32"
        EXPECTED_MACHINE="ARM"
        FILE_PATTERN="ELF 32-bit.*ARM"
        ;;
    x86_64*|amd64*|linux-x86_64)
        EXPECTED_CLASS="ELF64"
        EXPECTED_MACHINE="Advanced Micro Devices X86-64|x86-64|X86-64"
        FILE_PATTERN="x86-64|x86_64"
        ;;
    i*86*|x86*|linux-x86)
        EXPECTED_CLASS="ELF32"
        EXPECTED_MACHINE="Intel 80386|i386"
        FILE_PATTERN="Intel 80386"
        ;;
    *)
        EXPECTED_CLASS="ELF64"
        EXPECTED_MACHINE="AArch64"
        FILE_PATTERN="aarch64|ARM aarch64"
        ;;
esac

log "==> Verifying LLVM binaries in $BIN_DIR (Revision: ${REVISION:-unspecified}, Target: $TARGET)"

# 1. Validate ELF architecture with `file`
log "Checking ELF architecture with 'file'..."
FILE_OUT="$(file -L "$CLANG")"
echo "  $FILE_OUT"

if ! echo "$FILE_OUT" | grep -Eq "$FILE_PATTERN"; then
    err "FAIL: $CLANG does not match expected architecture pattern ($FILE_PATTERN)!"
    exit 1
fi
log "PASS: Binary matches expected architecture pattern ($FILE_PATTERN)"

# 2. Validate ELF header with `readelf -h`
log "Checking ELF header with 'readelf -h'..."
READELF_OUT="$(readelf -h "$CLANG")"
echo "$READELF_OUT" | grep -E "Class:|Machine:|Type:|Flags:" | sed 's/^/  /'

if ! echo "$READELF_OUT" | grep -Eq "Class:[[:space:]]*$EXPECTED_CLASS"; then
    err "FAIL: readelf did not report $EXPECTED_CLASS!"
    exit 1
fi

if ! echo "$READELF_OUT" | grep -Eq "Machine:[[:space:]]*($EXPECTED_MACHINE)"; then
    err "FAIL: readelf did not report Machine matching ($EXPECTED_MACHINE)!"
    exit 1
fi
log "PASS: readelf confirms Class: $EXPECTED_CLASS, Machine: $EXPECTED_MACHINE"

# 3. Test execution: clang --version
log "Executing 'clang --version'..."
"$CLANG" --version | head -n 3 | sed 's/^/  /'

# 4. Test execution: clang++ --version
log "Executing 'clang++ --version'..."
"$CLANGXX" --version | head -n 1 | sed 's/^/  /'

# 5. Test execution: ld.lld --version
log "Executing 'ld.lld --version'..."
"$LLD" --version | head -n 1 | sed 's/^/  /'

# 6. Test code generation for all 4 Android target architectures
TMP_TEST="$(mktemp -d 2>/dev/null || mktemp -d -t 'llvm_test_XXXXXX' -p "${TMPDIR:-/tmp}")"
trap 'rm -rf "$TMP_TEST"' EXIT

cat > "$TMP_TEST/test.c" <<'EOF'
int main(void) { return 0; }
EOF

log "Testing multi-arch code generation from this single compiler..."
"$CLANG" --target=aarch64-linux-android30 -c "$TMP_TEST/test.c" -o "$TMP_TEST/test_arm64.o"
"$CLANG" --target=armv7a-linux-androideabi30 -c "$TMP_TEST/test.c" -o "$TMP_TEST/test_arm32.o"
"$CLANG" --target=x86_64-linux-android30 -c "$TMP_TEST/test.c" -o "$TMP_TEST/test_x86_64.o"
"$CLANG" --target=i686-linux-android30 -c "$TMP_TEST/test.c" -o "$TMP_TEST/test_x86.o"

readelf -h "$TMP_TEST/test_arm64.o" | grep -q "Machine:[[:space:]]*AArch64" || { err "ARM64 codegen failed"; exit 1; }
readelf -h "$TMP_TEST/test_arm32.o" | grep -q "Machine:[[:space:]]*ARM" || { err "ARM32 codegen failed"; exit 1; }
readelf -h "$TMP_TEST/test_x86_64.o" | grep -Eq "Machine:[[:space:]]*(Advanced Micro Devices X86-64|x86-64|X86-64)" || { err "x86_64 codegen failed"; exit 1; }
readelf -h "$TMP_TEST/test_x86.o" | grep -Eq "Machine:[[:space:]]*(Intel 80386|i386)" || { err "x86 codegen failed"; exit 1; }

log "PASS: Multi-target code generation verified for all 4 Android architectures!"
log "LLVM validation SUCCEEDED for $BIN_DIR"
log "All LLVM verifications PASSED successfully!"
