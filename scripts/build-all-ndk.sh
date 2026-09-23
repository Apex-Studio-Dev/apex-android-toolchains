#!/bin/sh
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi
# ==============================================================================
# Apex Toolchains - build-all-ndk.sh
# Batch orchestrator to build all 13 Custom Android NDK releases (r26 - r30)
# strictly reusing pre-released LLVM artifacts
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_FILE="$ROOT_DIR/metadata/ndk-releases.yaml"

TARGET="${TARGET:-}"
PLATFORM="${PLATFORM:-}"
REBUILD_LLVM=false

log() { printf '\033[1;35m[build-all-ndk]==>\033[0m %s\n' "$*"; }

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --target=<triple>    Host target triple (default: aarch64-linux-android for bionic, aarch64-linux-gnu for linux)
  --platform=<plat>    Target execution platform: bionic (default) | linux
  --rebuild-llvm       Force rebuild of LLVM if not present
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
        --rebuild-llvm) REBUILD_LLVM=true ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
    shift
done

# Infer platform from target if not explicitly passed
if [ -z "$PLATFORM" ]; then
    case "$TARGET" in
        *-linux-gnu*|linux-gnu*) PLATFORM="linux" ;;
        *-linux-android*|linux-android*) PLATFORM="bionic" ;;
        *) PLATFORM="bionic" ;;
    esac
fi

# Resolve target list from metadata if TARGET is "all"
if [ "$TARGET" = "all" ]; then
    TARGETS=($(python3 -c "
import yaml
with open('$METADATA_FILE') as f:
    data = yaml.safe_load(f)
targets = data.get('supported_host_platforms', {}).get('$PLATFORM', {}).get('targets', [])
if not targets:
    if '$PLATFORM' == 'linux':
        targets = ['aarch64-linux-gnu', 'armv7a-linux-gnueabihf', 'x86_64-linux-gnu', 'i686-linux-gnu']
    else:
        targets = ['aarch64-linux-android', 'armv7a-linux-androideabi', 'x86_64-linux-android', 'i686-linux-android']
for t in targets:
    print(t)
"))
else
    # Default target if empty
    if [ -z "$TARGET" ]; then
        if [ "$PLATFORM" = "linux" ]; then
            TARGET="aarch64-linux-gnu"
        else
            TARGET="aarch64-linux-android"
        fi
    fi
    TARGETS=("$TARGET")
fi

# Read all releases from metadata
RELEASES=($(python3 -c "
import yaml
with open('$METADATA_FILE') as f:
    data = yaml.safe_load(f)
for r in data.get('releases', []):
    print(r['release'])
"))

log "Found ${#RELEASES[@]} NDK releases to assemble: ${RELEASES[*]}"
log "Target architectures (${#TARGETS[@]}): ${TARGETS[*]} (Platform: $PLATFORM)"

for rel in "${RELEASES[@]}"; do
    for tgt in "${TARGETS[@]}"; do
        log "============================================================"
        log "Assembling Custom Android NDK: $rel ($tgt, Platform: $PLATFORM)"
        log "============================================================"
        
        ARTIFACT="custom-android-ndk-${rel}-${tgt}.tar.xz"
        if [ -f "$ROOT_DIR/build/artifacts/$ARTIFACT" ]; then
            log "Artifact $ARTIFACT already exists. Skipping assembly."
            continue
        fi

        NDK_ARGS=( "--release=$rel" "--target=$tgt" "--platform=$PLATFORM" )
        [ "$REBUILD_LLVM" = true ] && NDK_ARGS+=( "--rebuild-llvm" )

        "$SCRIPT_DIR/build-ndk.sh" "${NDK_ARGS[@]}"
    done
done

log "All Custom Android NDK releases assembled successfully!"
