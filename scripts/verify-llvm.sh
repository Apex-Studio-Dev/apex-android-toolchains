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

while [ $# -gt 0 ]; do
    case "$1" in
        --dir=*) LLVM_DIR="${1#*=}" ;;
        --dir) shift; LLVM_DIR="$1" ;;
        --revision=*) REVISION="${1#*=}" ;;
        --revision) shift; REVISION="$1" ;;
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

log "==> Verifying LLVM binaries in $BIN_DIR (Revision: ${REVISION:-unspecified})"

# 1. Validate ELF architecture with `file`
log "Checking ELF architecture with 'file'..."
FILE_OUT="$(file -L "$CLANG")"
echo "  $FILE_OUT"

if ! echo "$FILE_OUT" | grep -q "ELF 64-bit"; then
    err "FAIL: $CLANG is not ELF 64-bit!"
    exit 1
fi

if ! echo "$FILE_OUT" | grep -Eq "aarch64|ARM aarch64"; then
    err "FAIL: $CLANG is not ARM64 / AArch64!"
    exit 1
fi
log "PASS: Binary is valid ELF 64-bit AArch64"

# 2. Validate ELF header with `readelf -h`
log "Checking ELF header with 'readelf -h'..."
READELF_OUT="$(readelf -h "$CLANG")"
echo "$READELF_OUT" | grep -E "Class:|Machine:|Type:|Flags:" | sed 's/^/  /'

if ! echo "$READELF_OUT" | grep -q "Class:[[:space:]]*ELF64"; then
    err "FAIL: readelf did not report ELF64!"
    exit 1
fi

if ! echo "$READELF_OUT" | grep -q "Machine:[[:space:]]*AArch64"; then
    err "FAIL: readelf did not report Machine: AArch64!"
    exit 1
fi
log "PASS: readelf confirms Machine: AArch64"

# 3. Test execution: clang --version
log "Executing 'clang --version'..."
"$CLANG" --version | head -n 3 | sed 's/^/  /'

# 4. Test execution: clang++ --version
log "Executing 'clang++ --version'..."
"$CLANGXX" --version | head -n 1 | sed 's/^/  /'

# 5. Test execution: ld.lld --version
log "Executing 'ld.lld --version'..."
"$LLD" --version | head -n 1 | sed 's/^/  /'

# 6. Test basic code generation for AArch64 and ARM targets
TMP_TEST="$(mktemp -d 2>/dev/null || mktemp -d -t 'llvm_test_XXXXXX' -p "${TMPDIR:-/tmp}")"
trap 'rm -rf "$TMP_TEST"' EXIT

cat > "$TMP_TEST/test.c" <<'EOF'
int main(void) { return 0; }
EOF

log "Testing syntax and IR emission for target aarch64-linux-android..."
"$CLANG" -target aarch64-linux-android -c "$TMP_TEST/test.c" -o "$TMP_TEST/test_aarch64.o"
readelf -h "$TMP_TEST/test_aarch64.o" | grep "Machine:" | sed 's/^/  Target ARM64: /'

log "Testing syntax and IR emission for target arm-linux-androideabi..."
"$CLANG" -target arm-linux-androideabi -march=armv7-a -c "$TMP_TEST/test.c" -o "$TMP_TEST/test_arm32.o"
readelf -h "$TMP_TEST/test_arm32.o" | grep "Machine:" | sed 's/^/  Target ARM32: /'

log "All LLVM verifications PASSED successfully!"
