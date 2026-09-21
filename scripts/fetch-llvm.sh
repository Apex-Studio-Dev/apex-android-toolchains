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
    local artifact_file="$ARTIFACT_NAME"
    local out_path="$ROOT_DIR/build/artifacts/$artifact_file"
    mkdir -p "$(dirname "$out_path")"

    if [ -f "$out_path" ]; then
        log "Artifact already exists locally: $out_path"
        return 0
    fi

    # Try downloading from Apex-Studio-Dev release first, then fallback
    local urls=(
        "https://github.com/${REPO_OWNER}/apex-android-toolchains/releases/download/${target_tag}/${artifact_file}"
        "https://gitlab.com/${REPO_OWNER}/apex-android-toolchains/-/releases/${target_tag}/downloads/${artifact_file}"
        "https://github.com/${FALLBACK_OWNER}/llvm-custom/releases/download/${target_tag}/${artifact_file}"
        "https://github.com/${FALLBACK_OWNER}/llvm-custom/releases/download/llvm-r26/bolt%2Bclang%2Bclang-tools-extra%2Blld%2Bpolly-r26d-aarch64-linux-musl.tar.xz"
        "https://github.com/${FALLBACK_OWNER}/llvm-custom/releases/download/llvm-r26/bolt%2Bclang%2Bclang-tools-extra%2Blld%2Bpolly-r26d-aarch64-linux-android.tar.xz"
    )

    log "Attempting to fetch released artifact..."
    for u in "${urls[@]}"; do
        log "Checking: $u"
        if curl -fsSL -o "$out_path.tmp" "$u" 2>/dev/null || (command -v aria2c >/dev/null && aria2c -q --allow-overwrite=true -o "$out_path.tmp" "$u"); then
            mv "$out_path.tmp" "$out_path"
            log "Successfully downloaded artifact to $out_path"
            return 0
        fi
    done

    rm -f "$out_path.tmp"
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
