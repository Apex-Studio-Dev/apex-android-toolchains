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

# Archive using maximum compression
(
    cd "$PARENT_DIR"
    tar -cf - "$BASE_DIR" | xz -T0 -9e > "$OUT_TAR"
)

log "Computing cryptographic checksums (SHA256 & SHA512)..."
(
    cd "$OUT_DIR"
    sha256sum "$ARTIFACT_NAME" > "${ARTIFACT_NAME}.sha256"
    sha512sum "$ARTIFACT_NAME" > "${ARTIFACT_NAME}.sha512"
    
    # Append to cumulative checksum files
    sha256sum "$ARTIFACT_NAME" >> SHA256SUMS
    sha512sum "$ARTIFACT_NAME" >> SHA512SUMS
    # Sort and deduplicate
    sort -u -k2 SHA256SUMS -o SHA256SUMS
    sort -u -k2 SHA512SUMS -o SHA512SUMS

    if [ "$TARGET" = "aarch64-linux-android" ] || [ "$TARGET" = "linux-arm64" ]; then
        ln -sf "$ARTIFACT_NAME" "custom-llvm-${REVISION_CLEAN#clang-}-linux-arm64.tar.xz" 2>/dev/null || true
    fi
)

log "Artifact generated: $OUT_TAR"
log "SHA256: $(cat "$OUT_DIR/${ARTIFACT_NAME}.sha256")"
log "Packaging completed successfully!"
