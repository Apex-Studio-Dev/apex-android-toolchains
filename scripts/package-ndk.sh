#!/bin/sh
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi
# ==============================================================================
# Apex Android Toolchains - package-ndk.sh
# Package assembled Custom NDK into custom-android-ndk-<release>-<target>.tar.xz
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

NDK_DIR=""
RELEASE=""
OUT_DIR="$ROOT_DIR/build/artifacts"

log() { printf '\033[1;32m[package-ndk]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[package-ndk ERROR]\033[0m %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $0 --ndk=<ndk_dir> --release=<version> [options]

Options:
  --ndk=<path>         Path to assembled Android NDK root
  --release=<name>     Release version (e.g. r26d)
  --target=<triple>    Host target triple (default: aarch64-linux-android)
  --out-dir=<path>     Output directory for artifact (default: build/artifacts)
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
        --out-dir=*) OUT_DIR="${1#*=}" ;;
        --out-dir) shift; OUT_DIR="$1" ;;
        -h|--help) usage ;;
        *) err "Unknown option: $1"; usage ;;
    esac
    shift
done

[ -n "$NDK_DIR" ] || { err "NDK directory is required (--ndk=<path>)"; usage; }
[ -n "$RELEASE" ] || { err "Release is required (--release=<version>)"; usage; }

RELEASE_CLEAN="${RELEASE#ndk-}"
mkdir -p "$OUT_DIR"

ARTIFACT_NAME="custom-android-ndk-${RELEASE_CLEAN}-${TARGET}.tar.xz"
OUT_TAR="$OUT_DIR/$ARTIFACT_NAME"

log "Packaging $NDK_DIR into $OUT_TAR..."

PARENT_DIR="$(dirname "$NDK_DIR")"
BASE_DIR="$(basename "$NDK_DIR")"

# Normalize ELF PT_TLS segment alignment for Android Bionic compatibility
if [ -f "$SCRIPT_DIR/normalize-tls.py" ]; then
    log "Normalizing ELF PT_TLS segment alignment across $NDK_DIR..."
    python3 "$SCRIPT_DIR/normalize-tls.py" "$NDK_DIR"
fi

# Compress using xz with multithreading
(
    cd "$PARENT_DIR"
    tar -cf - "$BASE_DIR" | xz -T0 -9e --lzma2=dict=256MiB > "$OUT_TAR"
)

log "Artifact generated: $OUT_TAR"
log "Computing cryptographic checksum (SHA256)..."
(
    cd "$OUT_DIR"
    sha256sum "$ARTIFACT_NAME" > "${ARTIFACT_NAME}.sha256"
    cat "${ARTIFACT_NAME}.sha256"
)
log "NDK Packaging completed successfully!"
