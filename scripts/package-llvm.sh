#!/bin/sh
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi
# ==============================================================================
# Apex Android Toolchains - package-llvm.sh
# Package built LLVM into custom-llvm-<revision>-linux-arm64.tar.xz with checksums
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LLVM_DIR=""
REVISION=""
OUT_DIR="$ROOT_DIR/build/artifacts"

log() { printf '\033[1;32m[package-llvm]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[package-llvm ERROR]\033[0m %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $0 --dir=<llvm_dir> --revision=<rev> [options]

Options:
  --dir=<path>         Path to LLVM installation prefix
  --revision=<name>    LLVM revision (e.g. clang-r487747e)
  --target=<triple>    Host target triple (default: aarch64-linux-android)
  --out-dir=<path>     Output directory for artifact (default: build/artifacts)
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
        --out-dir=*) OUT_DIR="${1#*=}" ;;
        --out-dir) shift; OUT_DIR="$1" ;;
        -h|--help) usage ;;
        *) err "Unknown option: $1"; usage ;;
    esac
    shift
done

[ -n "$LLVM_DIR" ] || { err "LLVM directory is required (--dir=<path>)"; usage; }
[ -n "$REVISION" ] || { err "Revision is required (--revision=<name>)"; usage; }

REVISION_CLEAN="${REVISION#llvm-}"
[ "${REVISION_CLEAN#clang-}" = "$REVISION_CLEAN" ] && REVISION_CLEAN="clang-$REVISION_CLEAN"

mkdir -p "$OUT_DIR"

ARTIFACT_NAME="custom-llvm-${REVISION_CLEAN#clang-}-${TARGET}.tar.xz"
OUT_TAR="$OUT_DIR/$ARTIFACT_NAME"

log "Packaging $LLVM_DIR into $OUT_TAR..."

PARENT_DIR="$(dirname "$LLVM_DIR")"
BASE_DIR="$(basename "$LLVM_DIR")"

# Normalize ELF PT_TLS segment alignment for Android Bionic compatibility
if [ -f "$SCRIPT_DIR/normalize-tls.py" ]; then
    log "Normalizing ELF PT_TLS segment alignment across $LLVM_DIR..."
    python3 "$SCRIPT_DIR/normalize-tls.py" "$LLVM_DIR"
fi

# Archive using maximum compression
(
    cd "$PARENT_DIR"
    tar -cf - "$BASE_DIR" | xz -T0 -9e > "$OUT_TAR"
)

log "Artifact generated: $OUT_TAR"
(
    cd "$OUT_DIR"
    sha256sum "$ARTIFACT_NAME"
)
log "Packaging completed successfully!"
