#!/bin/sh
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi
# ==============================================================================
# Apex Android Toolchains - build-ndk.sh
# Build Custom Android NDK for Linux ARM64 (aarch64) Host
# Uses pre-released LLVM artifact without recompilation (unless --rebuild-llvm is given)
# Supports Bionic execution on Android (Termux/Android native) and Linux ARM64
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NDK_META="$ROOT_DIR/metadata/ndk-releases.yaml"
LLVM_META="$ROOT_DIR/metadata/llvm-releases.yaml"

RELEASE=""
PLATFORM="${PLATFORM:-bionic}"    # bionic | linux
REBUILD_LLVM=false
PACKAGE_AFTER_BUILD=true
VERIFY_AFTER_BUILD=true
JOBS="$(nproc 2>/dev/null || echo 4)"

log() { printf '\033[1;34m[build-ndk]==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[build-ndk WARNING]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[build-ndk ERROR]\033[0m %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $0 --release=<version> [options]

Options:
  --release=<ver>      NDK release (e.g. r26d, r27b, r28c, r29, r30)
  --target=<triple>    Host execution target (default: aarch64-linux-android)
                       [aarch64-linux-android | armv7a-linux-androideabi | x86_64-linux-android | i686-linux-android]
  --platform=<plat>    Host execution platform: bionic (default) | linux
  --rebuild-llvm       Force local compilation of LLVM from source
  --jobs=<N>           Build parallelism (default: $JOBS)
  --no-package         Skip archive packaging after build
  --no-verify          Skip compilation verification after build
  -h, --help           Show this help message
EOF
    exit 1
}

TARGET="${TARGET:-aarch64-linux-android}"

while [ $# -gt 0 ]; do
    case "$1" in
        --release=*) RELEASE="${1#*=}" ;;
        --release) shift; RELEASE="$1" ;;
        --target=*) TARGET="${1#*=}" ;;
        --target) shift; TARGET="$1" ;;
        --platform=*) PLATFORM="${1#*=}" ;;
        --platform) shift; PLATFORM="$1" ;;
        --rebuild-llvm) REBUILD_LLVM=true ;;
        --jobs=*) JOBS="${1#*=}" ;;
        --jobs) shift; JOBS="$1" ;;
        --no-package) PACKAGE_AFTER_BUILD=false ;;
        --no-verify) VERIFY_AFTER_BUILD=false ;;
        -h|--help) usage ;;
        *) err "Unknown option: $1"; usage ;;
    esac
    shift
done

[ -n "$RELEASE" ] || { err "Release is required (--release=<version>)"; usage; }

# Canonicalize target architecture
case "$TARGET" in
    aarch64*|arm64*|linux-arm64)
        TARGET_CANONICAL="aarch64-linux-android"
        TARGET_ARCH="arm64"
        HOST_TAG="linux-arm64"
        ZIG_TARGET="aarch64-linux-musl"
        ;;
    arm*|linux-arm)
        TARGET_CANONICAL="armv7a-linux-androideabi"
        TARGET_ARCH="arm"
        HOST_TAG="linux-arm"
        ZIG_TARGET="arm-linux-musleabihf"
        ;;
    x86_64*|amd64*|linux-x86_64)
        TARGET_CANONICAL="x86_64-linux-android"
        TARGET_ARCH="x86_64"
        HOST_TAG="linux-x86_64"
        ZIG_TARGET="x86_64-linux-musl"
        ;;
    i*86*|x86*|linux-x86)
        TARGET_CANONICAL="i686-linux-android"
        TARGET_ARCH="x86"
        HOST_TAG="linux-x86"
        ZIG_TARGET="x86-linux-musl"
        ;;
    *)
        TARGET_CANONICAL="$TARGET"
        TARGET_ARCH="arm64"
        HOST_TAG="linux-arm64"
        ZIG_TARGET="aarch64-linux-musl"
        ;;
esac

# Normalize release: strip ndk- prefix if passed
RELEASE_CLEAN="${RELEASE#ndk-}"
RELEASE_NUM="${RELEASE_CLEAN%%[a-z]*}"
RELEASE_REV="${RELEASE_CLEAN#"$RELEASE_NUM"}"

WORK_DIR="$ROOT_DIR/build/ndk-$RELEASE_CLEAN-$TARGET_CANONICAL"
mkdir -p "$WORK_DIR" "$ROOT_DIR/build/artifacts"

log "Target NDK: $RELEASE_CLEAN (Host Target: $TARGET_CANONICAL, Host Tag: $HOST_TAG, Platform: $PLATFORM)"

# 1. Query metadata for required LLVM revision and official base
META="$(python3 -c "
import sys, os

metadata_file = '$NDK_META'
rel = '$RELEASE_CLEAN'

def parse_with_yaml():
    import yaml
    with open(metadata_file) as f:
        data = yaml.safe_load(f)
    entry = next((r for r in data.get('releases', []) if r['release'] == rel), None)
    if entry:
        return f\"{entry['required_llvm']}|{entry['llvm_artifact']}|{entry['official_archive']}|{entry['official_url']}\"
    return None

def parse_fallback():
    with open(metadata_file) as f:
        content = f.read()
    blocks = content.split('  - release:')
    for b in blocks[1:]:
        lines = [line.strip() for line in b.splitlines()]
        current_rel = lines[0].strip('\"\' ')
        if current_rel == rel:
            props = {}
            for line in lines[1:]:
                if ':' in line and not line.startswith('-'):
                    k, v = line.split(':', 1)
                    props[k.strip()] = v.strip('\"\' ')
            return f\"{props.get('required_llvm')}|{props.get('llvm_artifact')}|{props.get('official_archive')}|{props.get('official_url')}\"
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
")"

if [ -z "$META" ]; then
    err "NDK release $RELEASE_CLEAN not found in $NDK_META"
    exit 1
fi

IFS='|' read -r REQUIRED_LLVM LLVM_ARTIFACT_DEFAULT OFFICIAL_ARCHIVE OFFICIAL_URL <<< "$META"
log "Requirements: LLVM revision $REQUIRED_LLVM (Target: $TARGET_CANONICAL)"

# 2. Obtain LLVM artifact for this host target
LLVM_TAR="$ROOT_DIR/build/artifacts/custom-llvm-${REQUIRED_LLVM#clang-}-${TARGET_CANONICAL}.tar.xz"
if [ ! -f "$LLVM_TAR" ] && [ "$TARGET_CANONICAL" = "aarch64-linux-android" ]; then
    LLVM_TAR="$ROOT_DIR/build/artifacts/custom-llvm-${REQUIRED_LLVM#clang-}-linux-arm64.tar.xz"
fi
HOST_LLVM_DIR="$WORK_DIR/llvm-host"

if [ "$REBUILD_LLVM" = true ]; then
    log "Rebuild flag specified (--rebuild-llvm). Compiling LLVM $REQUIRED_LLVM for $TARGET_CANONICAL..."
    "$SCRIPT_DIR/build-llvm.sh" --revision="$REQUIRED_LLVM" --target="$TARGET_CANONICAL" --platform="$PLATFORM" --jobs="$JOBS"
fi

if [ ! -f "$LLVM_TAR" ]; then
    log "LLVM artifact not found locally. Fetching pre-released artifact for $TARGET_CANONICAL..."
    if ! "$SCRIPT_DIR/fetch-llvm.sh" --revision="$REQUIRED_LLVM" --target="$TARGET_CANONICAL" --artifact-only --platform="$PLATFORM"; then
        if [ "$REBUILD_LLVM" = false ]; then
            warn "LLVM artifact not found in releases. Falling back to build-llvm.sh..."
            "$SCRIPT_DIR/build-llvm.sh" --revision="$REQUIRED_LLVM" --target="$TARGET_CANONICAL" --platform="$PLATFORM" --jobs="$JOBS"
        fi
    fi
fi

if [ ! -f "$LLVM_TAR" ] && [ "$TARGET_CANONICAL" = "aarch64-linux-android" ] && [ -f "$ROOT_DIR/build/artifacts/custom-llvm-${REQUIRED_LLVM#clang-}-linux-arm64.tar.xz" ]; then
    LLVM_TAR="$ROOT_DIR/build/artifacts/custom-llvm-${REQUIRED_LLVM#clang-}-linux-arm64.tar.xz"
fi

if [ ! -f "$LLVM_TAR" ]; then
    err "LLVM artifact $LLVM_TAR is missing and could not be prepared!"
    exit 1
fi

log "Unpacking LLVM artifact $(basename "$LLVM_TAR")..."
rm -rf "$HOST_LLVM_DIR"
mkdir -p "$HOST_LLVM_DIR"
tar -xf "$LLVM_TAR" -C "$HOST_LLVM_DIR" --strip-components=1

# 3. Download and unpack official NDK base
OFFICIAL_ZIP="$WORK_DIR/$OFFICIAL_ARCHIVE"
NDK_UNPACK_DIR="$WORK_DIR/official-ndk"

if [ ! -f "$OFFICIAL_ZIP" ]; then
    log "Downloading official NDK skeleton ($OFFICIAL_ARCHIVE)..."
    if command -v aria2c >/dev/null; then
        aria2c --console-log-level=error --max-tries=5 -x 8 -s 8 \
               --allow-overwrite=true -d "$WORK_DIR" -o "$OFFICIAL_ARCHIVE" "$OFFICIAL_URL"
    else
        curl -fsSL -o "$OFFICIAL_ZIP" "$OFFICIAL_URL"
    fi
fi

log "Unpacking official NDK..."
rm -rf "$NDK_UNPACK_DIR"
mkdir -p "$NDK_UNPACK_DIR"
unzip -qq -o "$OFFICIAL_ZIP" -d "$NDK_UNPACK_DIR"

NDK_ROOT="$(find "$NDK_UNPACK_DIR" -maxdepth 1 -mindepth 1 -type d -name 'android-ndk-*' | head -n 1)"
[ -n "$NDK_ROOT" ] || { err "Failed to find unpacked android-ndk directory"; exit 1; }

NDK_TOOLCHAIN="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64"
PREBUILT_BIN="$NDK_ROOT/prebuilt/linux-x86_64/bin"

# 4. Build host tools natively for target architecture (make, yasm, toolbox)
log "Building native host tools (GNU make, yasm) for $TARGET_CANONICAL..."
HOST_TOOLS_DIR="$WORK_DIR/host-tools"
mkdir -p "$HOST_TOOLS_DIR/bin"

# Helper to download source files if not locally present
fetch_source() {
    local dest="$1"
    local url="$2"
    if [ -f "$dest" ]; then return 0; fi
    mkdir -p "$(dirname "$dest")"
    log "Downloading $(basename "$dest") from $url..."
    if command -v aria2c >/dev/null; then
        aria2c --console-log-level=error --max-tries=5 -x 4 -s 4 --allow-overwrite=true -o "$(basename "$dest")" -d "$(dirname "$dest")" "$url" || curl -fsSL -o "$dest" "$url"
    else
        curl -fsSL -o "$dest" "$url"
    fi
}

# Build make 4.4 if not already built
if [ ! -f "$HOST_TOOLS_DIR/bin/make" ]; then
    MAKE_TAR="$ROOT_DIR/ndk/sources/make-4.4.tar.gz"
    if [ ! -f "$MAKE_TAR" ]; then
        fetch_source "$MAKE_TAR" "https://ftp.gnu.org/gnu/make/make-4.4.tar.gz" || true
    fi
    if [ -f "$MAKE_TAR" ]; then
        log "Compiling native GNU Make 4.4 for $TARGET_CANONICAL..."
        (
            cd "$WORK_DIR"
            rm -rf make-4.4
            tar -xzf "$MAKE_TAR"
            cd make-4.4
            CONF_ARGS=( --prefix="$HOST_TOOLS_DIR" --disable-nls CFLAGS="-O2 -fPIC -Wno-incompatible-pointer-types -Wno-deprecated-non-prototype" )
            CC_CMD=""
            HOST_FLAG=""
            case "$TARGET_ARCH" in
                arm64)
                    if command -v aarch64-linux-gnu-gcc >/dev/null; then
                        CC_CMD="aarch64-linux-gnu-gcc"
                        HOST_FLAG="--host=aarch64-linux-gnu"
                    fi
                    ;;
                arm)
                    if command -v arm-linux-gnueabihf-gcc >/dev/null; then
                        CC_CMD="arm-linux-gnueabihf-gcc"
                        HOST_FLAG="--host=arm-linux-gnueabihf"
                    fi
                    ;;
                x86)
                    if command -v i686-linux-gnu-gcc >/dev/null; then
                        CC_CMD="i686-linux-gnu-gcc"
                        HOST_FLAG="--host=i686-linux-gnu"
                    fi
                    ;;
                x86_64)
                    if [ "$(uname -m)" = "x86_64" ] && command -v gcc >/dev/null; then
                        CC_CMD="gcc"
                    elif command -v x86_64-linux-gnu-gcc >/dev/null; then
                        CC_CMD="x86_64-linux-gnu-gcc"
                        HOST_FLAG="--host=x86_64-linux-gnu"
                    fi
                    ;;
            esac

            if [ -n "$CC_CMD" ]; then
                CONF_ARGS+=( CC="$CC_CMD" )
                [ -n "$HOST_FLAG" ] && CONF_ARGS+=( "$HOST_FLAG" )
            elif command -v zig >/dev/null; then
                CONF_ARGS+=( --host="$TARGET_CANONICAL" CC="zig cc -target $ZIG_TARGET" AR="zig ar" RANLIB="zig ranlib" LDFLAGS="-static" )
            fi
            ./configure "${CONF_ARGS[@]}"
            make -j"$JOBS"
            make install
        )
    elif [ "$(uname -m)" = "$TARGET_ARCH" ] && command -v make >/dev/null; then
        cp "$(command -v make)" "$HOST_TOOLS_DIR/bin/make"
    fi
fi

# Build yasm if available
if [ ! -f "$HOST_TOOLS_DIR/bin/yasm" ]; then
    YASM_TAR="$ROOT_DIR/ndk/sources/yasm-1.3.0.tar.gz"
    if [ ! -f "$YASM_TAR" ]; then
        fetch_source "$YASM_TAR" "https://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz" || true
    fi
    if [ -f "$YASM_TAR" ]; then
        log "Compiling native yasm 1.3.0 for $TARGET_CANONICAL..."
        (
            cd "$WORK_DIR"
            rm -rf yasm-1.3.0
            tar -xzf "$YASM_TAR"
            cd yasm-1.3.0
            CONF_ARGS=( --prefix="$HOST_TOOLS_DIR" --disable-nls CFLAGS="-O2 -fPIC" )
            if command -v zig >/dev/null; then
                CONF_ARGS+=( --host="$TARGET_CANONICAL" CC="zig cc -target $ZIG_TARGET" AR="zig ar" RANLIB="zig ranlib" LDFLAGS="-static" )
            elif [ "$(uname -m)" != "$TARGET_ARCH" ]; then
                case "$TARGET_ARCH" in
                    arm64) command -v aarch64-linux-gnu-gcc >/dev/null && CONF_ARGS+=( --host=aarch64-linux-gnu CC=aarch64-linux-gnu-gcc ) ;;
                    arm)   command -v arm-linux-gnueabihf-gcc >/dev/null && CONF_ARGS+=( --host=arm-linux-gnueabihf CC=arm-linux-gnueabihf-gcc ) ;;
                    x86)   command -v i686-linux-gnu-gcc >/dev/null && CONF_ARGS+=( --host=i686-linux-gnu CC=i686-linux-gnu-gcc ) ;;
                esac
            fi
            ./configure "${CONF_ARGS[@]}"
            make -j"$JOBS"
            make install
        )
    elif [ "$(uname -m)" = "$TARGET_ARCH" ] && command -v yasm >/dev/null; then
        cp "$(command -v yasm)" "$HOST_TOOLS_DIR/bin/yasm"
    fi
fi

# 5. Splice LLVM into official NDK
log "Splicing native $TARGET_CANONICAL LLVM into NDK..."

# Strip debugger wrappers not applicable to host
rm -f "$NDK_ROOT"/ndk-lldb "$NDK_ROOT"/ndk-lldb.cmd "$NDK_ROOT"/ndk-gdb "$NDK_ROOT"/ndk-gdb.cmd
rm -f "$PREBUILT_BIN"/ndk-gdb "$PREBUILT_BIN"/ndk-gdb.cmd "$PREBUILT_BIN"/ndkgdb.pyz 2>/dev/null || true
rm -f "$NDK_TOOLCHAIN/bin"/*lldb* 2>/dev/null || true

# Replace ELF tools with our host LLVM ones
find "$NDK_TOOLCHAIN/bin" -type f | while IFS= read -r file; do
    bname="$(basename "$file")"
    if [ -f "$HOST_LLVM_DIR/bin/$bname" ] && file "$file" | grep -q 'ELF'; then
        cp -f "$HOST_LLVM_DIR/bin/$bname" "$file"
    elif file "$file" | grep -q 'Bourne-Again shell script'; then
        sed -i 's,#!/usr/bin/env bash,#!/usr/bin/env sh,' "$file"
    fi
done

# Copy any additional binaries from host LLVM
for bin in clang clang++ ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-ranlib llvm-readelf llvm-strip clang-format clang-tidy clangd llvm-bolt; do
    if [ -f "$HOST_LLVM_DIR/bin/$bin" ]; then
        cp -f "$HOST_LLVM_DIR/bin/$bin" "$NDK_TOOLCHAIN/bin/$bin"
    fi
done

# Update shebangs for portability across bionic and linux
for sh_file in "$NDK_ROOT/build/tools/ndk_bin_common.sh" "$NDK_ROOT/build/ndk-build"; do
    [ -f "$sh_file" ] && sed -i 's,#!/usr/bin/env bash,#!/usr/bin/env sh,' "$sh_file"
done

# Copy host make and yasm
if [ -f "$HOST_TOOLS_DIR/bin/make" ]; then
    mkdir -p "$PREBUILT_BIN"
    cp -f "$HOST_TOOLS_DIR/bin/make" "$PREBUILT_BIN/make"
fi
if [ -f "$HOST_TOOLS_DIR/bin/yasm" ]; then
    cp -f "$HOST_TOOLS_DIR/bin/yasm" "$PREBUILT_BIN/yasm"
    cp -f "$HOST_TOOLS_DIR/bin/yasm" "$NDK_TOOLCHAIN/bin/yasm"
fi

# Copy clang headers / runtime libraries
if [ -d "$HOST_LLVM_DIR/lib/clang" ]; then
    cp -Rf "$HOST_LLVM_DIR/lib/clang" "$NDK_TOOLCHAIN/lib/"
fi

# 6. Adjust host directory layout and CMake toolchains
log "Patching host tag and CMake toolchains for $TARGET_CANONICAL..."

# Normalize HOST_ARCH in ndk_bin_common.sh
if [ -f "$NDK_ROOT/build/tools/ndk_bin_common.sh" ]; then
    sed -i -E '/case \$HOST_ARCH in/,/esac/ c\
case $HOST_ARCH in\
  armv5te|armv6|armv6l|armv7|armv7l|armv8l) HOST_ARCH=arm;;\
  aarch64|arm64) HOST_ARCH=arm64;;\
  i?86) HOST_ARCH=x86;;\
  amd64|x86_64) HOST_ARCH=x86_64;;\
  *) HOST_ARCH=$HOST_ARCH;;\
esac' "$NDK_ROOT/build/tools/ndk_bin_common.sh"
fi

# Patch cmake toolchain files
for tc in "$NDK_ROOT/build/cmake/android.toolchain.cmake" "$NDK_ROOT/build/cmake/android-legacy.toolchain.cmake"; do
    if [ -f "$tc" ]; then
        sed -i -E "s/linux-x86_64/$HOST_TAG/g" "$tc" 2>/dev/null || true
    fi
done

# Rename prebuilts directory to host tag with fallback symlinks
for dir_prefix in "prebuilt" "toolchains/llvm/prebuilt" "shader-tools"; do
    target_path="$NDK_ROOT/$dir_prefix"
    if [ -d "$target_path/linux-x86_64" ] && [ "$HOST_TAG" != "linux-x86_64" ]; then
        mv "$target_path/linux-x86_64" "$target_path/$HOST_TAG"
        ( cd "$target_path" && ln -sf "$HOST_TAG" "linux-x86_64" )
        ( cd "$target_path" && ln -sf "$HOST_TAG" "linux-aarch64" )
    fi
done

log "NDK assembly complete at $NDK_ROOT"

# 7. Verification
if [ "$VERIFY_AFTER_BUILD" = true ]; then
    log "Verifying assembled NDK cross-compilation capability..."
    "$SCRIPT_DIR/verify-ndk.sh" --ndk="$NDK_ROOT" --release="$RELEASE_CLEAN"
fi

# 8. Package
if [ "$PACKAGE_AFTER_BUILD" = true ]; then
    log "Packaging Custom NDK..."
    "$SCRIPT_DIR/package-ndk.sh" --ndk="$NDK_ROOT" --release="$RELEASE_CLEAN" --target="$TARGET_CANONICAL"
fi

log "Custom Android NDK $RELEASE_CLEAN ($TARGET_CANONICAL) build process completed successfully!"
