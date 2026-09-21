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
  --platform=<plat>    Host execution platform: bionic (default) | linux
  --rebuild-llvm       Force local compilation of LLVM from source
  --jobs=<N>           Build parallelism (default: $JOBS)
  --no-package         Skip archive packaging after build
  --no-verify          Skip compilation verification after build
  -h, --help           Show this help message
EOF
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --release=*) RELEASE="${1#*=}" ;;
        --release) shift; RELEASE="$1" ;;
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

# Normalize release: strip ndk- prefix if passed
RELEASE_CLEAN="${RELEASE#ndk-}"
RELEASE_NUM="${RELEASE_CLEAN%%[a-z]*}"
RELEASE_REV="${RELEASE_CLEAN#"$RELEASE_NUM"}"

WORK_DIR="$ROOT_DIR/build/ndk-$RELEASE_CLEAN"
mkdir -p "$WORK_DIR" "$ROOT_DIR/build/artifacts"

log "Target NDK: $RELEASE_CLEAN (Platform: $PLATFORM, Architecture: aarch64)"

# 1. Query metadata for required LLVM revision and official base
META="$(python3 -c "
import yaml, sys
with open('$NDK_META') as f:
    data = yaml.safe_load(f)
entry = next((r for r in data.get('releases', []) if r['release'] == '$RELEASE_CLEAN'), None)
if not entry:
    sys.exit(1)
print(f\"{entry['required_llvm']}|{entry['llvm_artifact']}|{entry['official_archive']}|{entry['official_url']}\")
" 2>/dev/null || true)"

if [ -z "$META" ]; then
    err "NDK release $RELEASE_CLEAN not found in $NDK_META"
    exit 1
fi

IFS='|' read -r REQUIRED_LLVM LLVM_ARTIFACT OFFICIAL_ARCHIVE OFFICIAL_URL <<< "$META"
log "Requirements: LLVM revision $REQUIRED_LLVM (Artifact: $LLVM_ARTIFACT)"

# 2. Obtain LLVM artifact (Strict dependency model)
LLVM_TAR="$ROOT_DIR/build/artifacts/$LLVM_ARTIFACT"
HOST_LLVM_DIR="$WORK_DIR/llvm-host"

if [ "$REBUILD_LLVM" = true ]; then
    log "Rebuild flag specified (--rebuild-llvm). Compiling LLVM $REQUIRED_LLVM from source..."
    "$SCRIPT_DIR/build-llvm.sh" --revision="$REQUIRED_LLVM" --platform="$PLATFORM" --jobs="$JOBS"
fi

if [ ! -f "$LLVM_TAR" ]; then
    log "LLVM artifact not found locally. Fetching pre-released artifact..."
    if ! "$SCRIPT_DIR/fetch-llvm.sh" --revision="$REQUIRED_LLVM" --artifact-only --platform="$PLATFORM"; then
        if [ "$REBUILD_LLVM" = false ]; then
            warn "LLVM artifact not found in releases. Falling back to build-llvm.sh..."
            "$SCRIPT_DIR/build-llvm.sh" --revision="$REQUIRED_LLVM" --platform="$PLATFORM" --jobs="$JOBS"
        fi
    fi
fi

if [ ! -f "$LLVM_TAR" ]; then
    err "LLVM artifact $LLVM_TAR is missing and could not be prepared!"
    exit 1
fi

log "Unpacking LLVM artifact $LLVM_ARTIFACT..."
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

# 4. Build host tools natively for ARM64 (make, yasm, toolbox)
log "Building native host tools (GNU make, yasm) for ARM64..."
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
        log "Compiling native GNU Make 4.4 for ARM64..."
        (
            cd "$WORK_DIR"
            rm -rf make-4.4
            tar -xzf "$MAKE_TAR"
            cd make-4.4
            CONF_ARGS=( --prefix="$HOST_TOOLS_DIR" --disable-nls CFLAGS="-O2 -fPIC" )
            if [ "$(uname -m)" != "aarch64" ]; then
                if command -v aarch64-linux-gnu-gcc >/dev/null; then
                    CONF_ARGS+=( --host=aarch64-linux-gnu CC=aarch64-linux-gnu-gcc )
                elif command -v zig >/dev/null; then
                    CONF_ARGS+=( --host=aarch64-linux-musl CC="zig cc -target aarch64-linux-musl" AR="zig ar" RANLIB="zig ranlib" LDFLAGS="-static" )
                fi
            fi
            ./configure "${CONF_ARGS[@]}"
            make -j"$JOBS"
            make install
        )
    elif [ "$(uname -m)" = "aarch64" ] && command -v make >/dev/null; then
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
        log "Compiling native yasm 1.3.0 for ARM64..."
        (
            cd "$WORK_DIR"
            rm -rf yasm-1.3.0
            tar -xzf "$YASM_TAR"
            cd yasm-1.3.0
            CONF_ARGS=( --prefix="$HOST_TOOLS_DIR" --disable-nls CFLAGS="-O2 -fPIC" )
            if [ "$(uname -m)" != "aarch64" ]; then
                if command -v aarch64-linux-gnu-gcc >/dev/null; then
                    CONF_ARGS+=( --host=aarch64-linux-gnu CC=aarch64-linux-gnu-gcc )
                elif command -v zig >/dev/null; then
                    CONF_ARGS+=( --host=aarch64-linux-musl CC="zig cc -target aarch64-linux-musl" AR="zig ar" RANLIB="zig ranlib" LDFLAGS="-static" )
                fi
            fi
            ./configure "${CONF_ARGS[@]}"
            make -j"$JOBS"
            make install
        )
    elif [ "$(uname -m)" = "aarch64" ] && command -v yasm >/dev/null; then
        cp "$(command -v yasm)" "$HOST_TOOLS_DIR/bin/yasm"
    fi
fi

# 5. Splice ARM64 LLVM into official NDK
log "Splicing native Linux ARM64 LLVM into NDK..."

# Strip debugger wrappers not applicable to host
rm -f "$NDK_ROOT"/ndk-lldb "$NDK_ROOT"/ndk-lldb.cmd "$NDK_ROOT"/ndk-gdb "$NDK_ROOT"/ndk-gdb.cmd
rm -f "$PREBUILT_BIN"/ndk-gdb "$PREBUILT_BIN"/ndk-gdb.cmd "$PREBUILT_BIN"/ndkgdb.pyz 2>/dev/null || true
rm -f "$NDK_TOOLCHAIN/bin"/*lldb* 2>/dev/null || true

# Replace ELF tools with our ARM64 ones
find "$NDK_TOOLCHAIN/bin" -type f | while IFS= read -r file; do
    bname="$(basename "$file")"
    if [ -f "$HOST_LLVM_DIR/bin/$bname" ] && file "$file" | grep -q 'ELF'; then
        cp -f "$HOST_LLVM_DIR/bin/$bname" "$file"
    elif file "$file" | grep -q 'Bourne-Again shell script'; then
        sed -i 's,#!/usr/bin/env bash,#!/usr/bin/env sh,' "$file"
    fi
done

# Copy any additional binaries from host LLVM
for bin in clang clang++ ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-ranlib llvm-readelf llvm-strip; do
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
log "Patching host tag and CMake toolchains for ARM64/Bionic..."

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
        sed -i -E 's/linux-x86_64/linux-arm64/g' "$tc" 2>/dev/null || true
    fi
done

# Rename prebuilts directory to linux-arm64 with fallback symlinks
for dir_prefix in "prebuilt" "toolchains/llvm/prebuilt" "shader-tools"; do
    target_path="$NDK_ROOT/$dir_prefix"
    if [ -d "$target_path/linux-x86_64" ]; then
        mv "$target_path/linux-x86_64" "$target_path/linux-arm64"
        ( cd "$target_path" && ln -s "linux-arm64" "linux-x86_64" )
        ( cd "$target_path" && ln -s "linux-arm64" "linux-aarch64" )
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
    "$SCRIPT_DIR/package-ndk.sh" --ndk="$NDK_ROOT" --release="$RELEASE_CLEAN"
fi

log "Custom Android NDK $RELEASE_CLEAN build process completed successfully!"
