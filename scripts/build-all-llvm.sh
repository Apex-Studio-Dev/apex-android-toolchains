#!/bin/sh
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi
# ==============================================================================
# Apex Android Toolchains - build-all-llvm.sh
# Batch orchestrator to build all 12 exact LLVM releases
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_FILE="$ROOT_DIR/metadata/llvm-releases.yaml"

TARGET="${TARGET:-aarch64-linux-android}"
PLATFORM="${PLATFORM:-bionic}"
REBUILD=false

log() { printf '\033[1;35m[build-all-llvm]==>\033[0m %s\n' "$*"; }

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --target=<triple>    Host target triple (default: aarch64-linux-android)
  --platform=<plat>    Target platform: bionic (default) | linux
  --rebuild            Force rebuilding even if artifact exists
  -h, --help           Show this help message
EOF
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --target=*) TARGET="${1#*=}" ;;
        --target) shift; TARGET="$1" ;;
        --platform=*) PLATFORM="${1#*=}" ;;
        --platform) shift; PLATFORM="$1" ;;
        --rebuild) REBUILD=true ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
    shift
done

# Read all revisions from metadata
REVISIONS=($(python3 -c "
import yaml
with open('$METADATA_FILE') as f:
    data = yaml.safe_load(f)
for r in data.get('releases', []):
    print(r['revision'])
"))

log "Found ${#REVISIONS[@]} LLVM revisions to process: ${REVISIONS[*]} (Target: $TARGET)"

for rev in "${REVISIONS[@]}"; do
    log "------------------------------------------------------------"
    log "Processing LLVM Revision: $rev ($TARGET)"
    log "------------------------------------------------------------"
    
    # Check if artifact exists
    ARTIFACT="custom-llvm-${rev#clang-}-${TARGET}.tar.xz"
    if [ "$REBUILD" = false ] && [ -f "$ROOT_DIR/build/artifacts/$ARTIFACT" ]; then
        log "Artifact $ARTIFACT already exists. Skipping compilation."
        continue
    fi

    "$SCRIPT_DIR/build-llvm.sh" --revision="$rev" --target="$TARGET" --platform="$PLATFORM"
done

log "All LLVM revisions processed successfully!"
