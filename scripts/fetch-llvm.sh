#!/bin/sh
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi
# ==============================================================================
# Apex Android Toolchains - fetch-llvm.sh
# Fetch LLVM prebuilt artifact or source code using exact AOSP commits
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_FILE="$ROOT_DIR/metadata/llvm-releases.yaml"

REVISION=""
MODE="auto"           # auto | artifact | source
PLATFORM="${PLATFORM:-bionic}"   # bionic | linux
TARGET="${TARGET:-aarch64-linux-android}"
DEST_DIR=""
REPO_OWNER="${REPO_OWNER:-Apex-Studio-Dev}"
FALLBACK_OWNER="HomuHomu833"

log() { printf '\033[1;32m[fetch-llvm]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[fetch-llvm WARNING]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[fetch-llvm ERROR]\033[0m %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $0 --revision=<rev> [options]

Options:
  --revision=<name>    LLVM revision (e.g. clang-r487747e or llvm-r487747e)
  --target=<triple>    Host target triple (default: aarch64-linux-android)
  --platform=<plat>    Host platform: bionic (default) | linux
  --artifact-only      Only attempt to fetch release artifact
  --source-only        Only fetch exact source from AOSP
  --dest=<path>        Output directory (default: build/<revision>)
  --owner=<github_user> GitHub release owner (default: $REPO_OWNER)
  -h, --help           Show this help message
EOF
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --revision=*) REVISION="${1#*=}" ;;
        --revision) shift; REVISION="$1" ;;
        --target=*) TARGET="${1#*=}" ;;
        --target) shift; TARGET="$1" ;;
        --platform=*) PLATFORM="${1#*=}" ;;
        --platform) shift; PLATFORM="$1" ;;
        --artifact-only) MODE="artifact" ;;
        --source-only) MODE="source" ;;
        --dest=*) DEST_DIR="${1#*=}" ;;
        --dest) shift; DEST_DIR="$1" ;;
        --owner=*) REPO_OWNER="${1#*=}" ;;
        --owner) shift; REPO_OWNER="$1" ;;
        -h|--help) usage ;;
        *) err "Unknown option: $1"; usage ;;
    esac
    shift
done

[ -n "$REVISION" ] || { err "Revision is required (--revision=<name>)"; usage; }

# Canonicalize target architecture
case "$TARGET" in
    aarch64*|arm64*|linux-arm64) TARGET_CANONICAL="aarch64-linux-android" ;;
    arm*|linux-arm)              TARGET_CANONICAL="armv7a-linux-androideabi" ;;
    x86_64*|amd64*|linux-x86_64) TARGET_CANONICAL="x86_64-linux-android" ;;
    i*86*|x86*|linux-x86)        TARGET_CANONICAL="i686-linux-android" ;;
    *)                           TARGET_CANONICAL="$TARGET" ;;
esac

# Normalize revision name (remove llvm- prefix if present)
REVISION_CLEAN="${REVISION#llvm-}"
[ "${REVISION_CLEAN#clang-}" = "$REVISION_CLEAN" ] && REVISION_CLEAN="clang-$REVISION_CLEAN"
TAG_NAME="llvm-${REVISION_CLEAN#clang-}"

DEST_DIR="${DEST_DIR:-$ROOT_DIR/build/$REVISION_CLEAN}"
mkdir -p "$DEST_DIR"

log "Target LLVM revision: $REVISION_CLEAN (tag: $TAG_NAME, platform: $PLATFORM)"

# Extract commit metadata using python (with built-in fallback if PyYAML is missing)
extract_meta() {
    python3 -c "
import sys, os

metadata_file = '$METADATA_FILE'
rev = '$REVISION_CLEAN'

def parse_with_yaml():
    import yaml
    with open(metadata_file) as f:
        data = yaml.safe_load(f)
    entry = next((r for r in data.get('releases', []) if r['revision'] == rev), None)
    if entry:
        return f\"{entry['llvm_version']}|{entry['llvm_project_commit']}|{entry['llvm_android_commit']}|{entry['artifact']}\"
    return None

def parse_fallback():
    with open(metadata_file) as f:
        content = f.read()
    blocks = content.split('  - revision:')
    for b in blocks[1:]:
        lines = [line.strip() for line in b.splitlines()]
        current_rev = lines[0].strip('\"\' ')
        if current_rev == rev:
            props = {}
            for line in lines[1:]:
                if ':' in line and not line.startswith('-'):
                    k, v = line.split(':', 1)
                    props[k.strip()] = v.strip('\"\' ')
            return f\"{props.get('llvm_version')}|{props.get('llvm_project_commit')}|{props.get('llvm_android_commit')}|{props.get('artifact')}\"
    return None

res = None
try:
    res = parse_with_yaml()
except Exception:
    res = parse_fallback()

if res:
    print(res)
else:
    sys.exit(1)
"
}

META="$(extract_meta)"
if [ -z "$META" ]; then
    err "Revision $REVISION_CLEAN not found in $METADATA_FILE"
    exit 1
fi

IFS='|' read -r LLVM_VER LLVM_PROJ_COMMIT LLVM_AND_COMMIT ARTIFACT_NAME <<< "$META"
log "Found metadata: LLVM $LLVM_VER (llvm-project: $LLVM_PROJ_COMMIT, llvm_android: $LLVM_AND_COMMIT)"

fetch_artifact() {
    local target_tag="$TAG_NAME"
    local candidates=()
    candidates+=( "custom-llvm-${REVISION_CLEAN#clang-}-${TARGET_CANONICAL}.tar.xz" )
    if [ "$TARGET_CANONICAL" = "aarch64-linux-android" ]; then
        candidates+=( "custom-llvm-${REVISION_CLEAN#clang-}-linux-arm64.tar.xz" )
        if [ -n "$ARTIFACT_NAME" ] && [ "$ARTIFACT_NAME" != "custom-llvm-${REVISION_CLEAN#clang-}-${TARGET_CANONICAL}.tar.xz" ] && [ "$ARTIFACT_NAME" != "custom-llvm-${REVISION_CLEAN#clang-}-linux-arm64.tar.xz" ]; then
            candidates+=( "$ARTIFACT_NAME" )
        fi
    fi

    # 1. Check if artifact already exists locally
    for art in "${candidates[@]}"; do
        local check_path="$ROOT_DIR/build/artifacts/$art"
        if [ -f "$check_path" ]; then
            log "Artifact already exists locally: $check_path"
            if [ "$TARGET_CANONICAL" = "aarch64-linux-android" ]; then
                (
                    cd "$ROOT_DIR/build/artifacts"
                    ln -sf "custom-llvm-${REVISION_CLEAN#clang-}-${TARGET_CANONICAL}.tar.xz" "custom-llvm-${REVISION_CLEAN#clang-}-linux-arm64.tar.xz" 2>/dev/null || true
                    ln -sf "custom-llvm-${REVISION_CLEAN#clang-}-linux-arm64.tar.xz" "custom-llvm-${REVISION_CLEAN#clang-}-${TARGET_CANONICAL}.tar.xz" 2>/dev/null || true
                )
            fi
            return 0
        fi
    done

    # 2. Try downloading candidates from releases
    log "Attempting to fetch released artifact for $TARGET_CANONICAL..."
    for art in "${candidates[@]}"; do
        local out_path="$ROOT_DIR/build/artifacts/$art"
        mkdir -p "$(dirname "$out_path")"

        local urls=(
            "https://github.com/${REPO_OWNER}/apex-android-toolchains/releases/download/${target_tag}/${art}"
            "https://gitlab.com/${REPO_OWNER}/apex-android-toolchains/-/releases/${target_tag}/downloads/${art}"
            "https://github.com/${FALLBACK_OWNER}/llvm-custom/releases/download/${target_tag}/${art}"
        )
        if [ "$TARGET_CANONICAL" = "aarch64-linux-android" ]; then
            urls+=(
                "https://github.com/${FALLBACK_OWNER}/llvm-custom/releases/download/llvm-r26/bolt%2Bclang%2Bclang-tools-extra%2Blld%2Bpolly-r26d-aarch64-linux-musl.tar.xz"
                "https://github.com/${FALLBACK_OWNER}/llvm-custom/releases/download/llvm-r26/bolt%2Bclang%2Bclang-tools-extra%2Blld%2Bpolly-r26d-aarch64-linux-android.tar.xz"
            )
        fi

        for u in "${urls[@]}"; do
            log "Checking: $u"
            if curl -fsSL -o "$out_path.tmp" "$u" 2>/dev/null || (command -v aria2c >/dev/null && aria2c -q --allow-overwrite=true -o "$out_path.tmp" "$u" 2>/dev/null); then
                mv "$out_path.tmp" "$out_path"
                log "Successfully downloaded artifact to $out_path"
                if [ "$TARGET_CANONICAL" = "aarch64-linux-android" ]; then
                    (
                        cd "$ROOT_DIR/build/artifacts"
                        ln -sf "$art" "custom-llvm-${REVISION_CLEAN#clang-}-${TARGET_CANONICAL}.tar.xz" 2>/dev/null || true
                        ln -sf "$art" "custom-llvm-${REVISION_CLEAN#clang-}-linux-arm64.tar.xz" 2>/dev/null || true
                    )
                fi
                return 0
            fi
        done
        rm -f "$out_path.tmp"
    done

    return 1
}

fetch_source() {
    local src_dir="$DEST_DIR/source"
    mkdir -p "$src_dir"

    log "Fetching llvm-project at commit $LLVM_PROJ_COMMIT..."
    local proj_dir="$src_dir/llvm-project"
    if [ ! -d "$proj_dir/.git" ]; then
        rm -rf "$proj_dir"
        git init "$proj_dir"
        git -C "$proj_dir" remote add origin https://android.googlesource.com/toolchain/llvm-project
    fi
    git -C "$proj_dir" fetch --depth 1 origin "$LLVM_PROJ_COMMIT"
    git -C "$proj_dir" checkout -q FETCH_HEAD

    log "Fetching llvm_android at commit $LLVM_AND_COMMIT..."
    local and_dir="$src_dir/llvm_android"
    if [ ! -d "$and_dir/.git" ]; then
        rm -rf "$and_dir"
        git init "$and_dir"
        git -C "$and_dir" remote add origin https://android.googlesource.com/toolchain/llvm_android
    fi
    git -C "$and_dir" fetch --depth 1 origin "$LLVM_AND_COMMIT"
    git -C "$and_dir" checkout -q FETCH_HEAD

    log "Sources successfully fetched into $src_dir"
}

case "$MODE" in
    artifact)
        if fetch_artifact; then
            log "LLVM artifact ready."
            exit 0
        else
            err "Failed to fetch LLVM artifact."
            exit 1
        fi
        ;;
    source)
        fetch_source
        ;;
    auto)
        if fetch_artifact; then
            log "LLVM artifact fetched successfully. Rebuild skipped."
            exit 0
        else
            warn "No released artifact found. Falling back to fetching exact AOSP source..."
            fetch_source
        fi
        ;;
esac
