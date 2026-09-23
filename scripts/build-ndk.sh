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
if [ ! -d "$NDK_TOOLCHAIN" ]; then
    NDK_TOOLCHAIN="$(find "$NDK_ROOT/toolchains/llvm/prebuilt" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
fi

PREBUILT_BIN="$NDK_ROOT/prebuilt/linux-x86_64/bin"
if [ ! -d "$PREBUILT_BIN" ]; then
    PREBUILT_BIN="$(find "$NDK_ROOT/prebuilt" -mindepth 1 -maxdepth 1 -type d -exec test -d '{}/bin' ';' -print | head -n 1)/bin"
fi

# 4. Build host tools natively for target architecture (make, yasm, ytasm, vsyasm)
log "Building native host tools (GNU make, yasm) for $TARGET_CANONICAL..."
HOST_TOOLS_DIR="$WORK_DIR/host-tools"
mkdir -p "$HOST_TOOLS_DIR/bin"

case "$TARGET_ARCH" in
    arm64)  GNU_TRIPLE="aarch64-linux-gnu" ;;
    arm)    GNU_TRIPLE="arm-linux-gnueabihf" ;;
    x86_64) GNU_TRIPLE="x86_64-linux-gnu" ;;
    x86)    GNU_TRIPLE="i686-linux-gnu" ;;
    *)      GNU_TRIPLE="$TARGET_CANONICAL" ;;
esac

# Setup cross toolchain for host tools
if [ "$PLATFORM" = "bionic" ]; then
    API="${ANDROID_PLATFORM:-25}"
    [ "$TARGET_CANONICAL" = "riscv64-linux-android" ] && API=35
    TC="$NDK_TOOLCHAIN"
    CROSS_CC="$TC/bin/${TARGET_CANONICAL}${API}-clang"
    CROSS_CXX="${CROSS_CC}++"
    if [ -x "$TC/bin/ld.lld" ]; then
        CROSS_LD="$TC/bin/ld.lld"
    elif [ -x "$TC/bin/lld" ]; then
        CROSS_LD="$TC/bin/lld"
    else
        CROSS_LD="ld.lld"
    fi
    CROSS_AR="$TC/bin/llvm-ar"
    CROSS_RANLIB="$TC/bin/llvm-ranlib"
    CROSS_STRIP="$TC/bin/llvm-strip"
    CROSS_OBJCOPY="$TC/bin/llvm-objcopy"
    CROSS_CFLAGS="-O3 -flto -fdata-sections -ffunction-sections -Wno-incompatible-pointer-types -Wno-deprecated-non-prototype -Wno-error=implicit-function-declaration -fstack-protector-strong -static"
    CROSS_CXXFLAGS="-O3 -flto -fdata-sections -ffunction-sections -Wno-incompatible-pointer-types -Wno-deprecated-non-prototype -Wno-error=implicit-function-declaration -fstack-protector-strong -static"
    CROSS_LDFLAGS="-static -Wl,--gc-sections -Wl,--icf=all"
elif command -v "${GNU_TRIPLE}-gcc" >/dev/null; then
    CROSS_CC="${GNU_TRIPLE}-gcc"
    CROSS_CXX="${GNU_TRIPLE}-g++"
    CROSS_LD="${GNU_TRIPLE}-ld"
    CROSS_AR="${GNU_TRIPLE}-ar"
    CROSS_RANLIB="${GNU_TRIPLE}-ranlib"
    CROSS_STRIP="${GNU_TRIPLE}-strip"
    CROSS_OBJCOPY="${GNU_TRIPLE}-objcopy"
    CROSS_CFLAGS="-O2 -fPIC"
    CROSS_CXXFLAGS="-O2 -fPIC"
    CROSS_LDFLAGS="-static-libgcc -static-libstdc++"
else
    CROSS_CC="clang"
    CROSS_CXX="clang++"
    CROSS_LD="ld.lld"
    CROSS_AR="llvm-ar"
    CROSS_RANLIB="llvm-ranlib"
    CROSS_STRIP="llvm-strip"
    CROSS_OBJCOPY="llvm-objcopy"
    CROSS_CFLAGS="-O2"
    CROSS_CXXFLAGS="-O2"
    CROSS_LDFLAGS=""
fi

# Build GNU Make 4.4
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
            CONF_ARGS=(
                --prefix="$HOST_TOOLS_DIR"
                --build=x86_64-linux-gnu
                --host="$TARGET_CANONICAL"
                --disable-posix-spawn
                --disable-nls
                CC="$CROSS_CC"
                CXX="$CROSS_CXX"
                LD="$CROSS_LD"
                AR="$CROSS_AR"
                RANLIB="$CROSS_RANLIB"
                STRIP="$CROSS_STRIP"
                OBJCOPY="$CROSS_OBJCOPY"
                CFLAGS="$CROSS_CFLAGS"
                CXXFLAGS="$CROSS_CXXFLAGS"
                LDFLAGS="$CROSS_LDFLAGS"
                ac_cv_lib_elf_elf_begin=no
                am_cv_func_iconv=no
                ac_cv_func_pselect=no
                ac_cv_func_getloadavg=no
            )
            ./configure "${CONF_ARGS[@]}"
            make -j"$JOBS"
            make install
        )
    fi
fi

# Build YASM 1.3.0
if [ ! -f "$HOST_TOOLS_DIR/bin/yasm" ]; then
    YASM_TAR="$ROOT_DIR/ndk/sources/yasm-1.3.0.tar.gz"
    if [ ! -f "$YASM_TAR" ]; then
        fetch_source "$YASM_TAR" "https://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz" || true
    fi
    if [ -f "$YASM_TAR" ]; then
        log "Compiling native YASM 1.3.0 for $TARGET_CANONICAL..."
        (
            cd "$WORK_DIR"
            rm -rf yasm-1.3.0
            tar -xzf "$YASM_TAR"
            cd yasm-1.3.0
            CONF_ARGS=(
                --prefix="$HOST_TOOLS_DIR"
                --build=x86_64-linux-gnu
                --host="$TARGET_CANONICAL"
                --disable-nls
                CC="$CROSS_CC"
                CXX="$CROSS_CXX"
                LD="$CROSS_LD"
                AR="$CROSS_AR"
                RANLIB="$CROSS_RANLIB"
                STRIP="$CROSS_STRIP"
                OBJCOPY="$CROSS_OBJCOPY"
                CC_FOR_BUILD="/usr/bin/cc"
                CCLD_FOR_BUILD="/usr/bin/cc"
                CFLAGS_FOR_BUILD="-O2"
                LDFLAGS_FOR_BUILD=""
                CFLAGS="$CROSS_CFLAGS -Wno-error=date-time"
                CXXFLAGS="$CROSS_CXXFLAGS -Wno-error=date-time"
                LDFLAGS="$CROSS_LDFLAGS"
            )
            ./configure "${CONF_ARGS[@]}"
            # Ensure host tools are compiled with host cc if needed
            for gen in genperf genmacro genversion genstring; do
                make CC=/usr/bin/cc CCLD=/usr/bin/cc "$gen" 2>/dev/null || true
            done
            make -j"$JOBS"
            make install
            # Ensure ytasm and vsyasm are also present in $HOST_TOOLS_DIR/bin
            for extra in ytasm vsyasm; do
                if [ -f "$WORK_DIR/yasm-1.3.0/$extra" ]; then
                    cp -f "$WORK_DIR/yasm-1.3.0/$extra" "$HOST_TOOLS_DIR/bin/$extra"
                elif [ -f "$HOST_TOOLS_DIR/bin/yasm" ]; then
                    cp -f "$HOST_TOOLS_DIR/bin/yasm" "$HOST_TOOLS_DIR/bin/$extra"
                fi
            done
        )
    fi
fi

# Strip all host tools
for b in "$HOST_TOOLS_DIR/bin"/*; do
    [ -f "$b" ] && "$CROSS_STRIP" -s --strip-all "$b" 2>/dev/null || true
done

# 5. Splice LLVM and native tools into official NDK
log "Splicing native $TARGET_CANONICAL LLVM into NDK..."

# Strip debugger wrappers not applicable to host
rm -f "$NDK_ROOT"/ndk-lldb "$NDK_ROOT"/ndk-lldb.cmd "$NDK_ROOT"/ndk-gdb "$NDK_ROOT"/ndk-gdb.cmd
rm -f "$PREBUILT_BIN"/ndk-gdb "$PREBUILT_BIN"/ndk-gdb.cmd "$PREBUILT_BIN"/ndkgdb.pyz 2>/dev/null || true
rm -f "$NDK_TOOLCHAIN/bin"/*lldb* 2>/dev/null || true

# Replace ELF tools with our host LLVM ones, and drop unreplaced x86_64 binaries
find "$NDK_TOOLCHAIN/bin" -type f | while IFS= read -r file; do
    bname="$(basename "$file")"
    if [ -f "$HOST_LLVM_DIR/bin/$bname" ] && file "$file" | grep -q 'ELF'; then
        cp -f "$HOST_LLVM_DIR/bin/$bname" "$file"
    elif file "$file" | grep -q 'Bourne-Again shell script'; then
        sed -i 's,#!/usr/bin/env bash,#!/usr/bin/env sh,' "$file"
    elif ! file "$file" | grep -Eq 'Python script|Perl script|ASCII text'; then
        # Any remaining unreplaced ELF binary is host x86_64; remove it to prevent execution failures on target
        rm -f "$file"
    fi
done

# Copy any additional binaries from host LLVM
for bin in clang clang++ ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-ranlib llvm-readelf llvm-strip clang-format clang-tidy clangd llvm-bolt; do
    if [ -f "$HOST_LLVM_DIR/bin/$bin" ]; then
        cp -f "$HOST_LLVM_DIR/bin/$bin" "$NDK_TOOLCHAIN/bin/$bin"
    fi
done

# Copy native GNU Make, Yasm, Ytasm, and Vsyasm into prebuilt
rm -f "$PREBUILT_BIN"/*asm
if [ -f "$HOST_TOOLS_DIR/bin/make" ]; then
    mkdir -p "$PREBUILT_BIN"
    cp -f "$HOST_TOOLS_DIR/bin/make" "$PREBUILT_BIN/make"
fi
if [ -f "$HOST_TOOLS_DIR/bin/yasm" ]; then
    cp -f "$HOST_TOOLS_DIR/bin/yasm" "$PREBUILT_BIN/yasm"
    cp -f "$HOST_TOOLS_DIR/bin/yasm" "$NDK_TOOLCHAIN/bin/yasm"
fi
if [ -f "$HOST_TOOLS_DIR/bin/ytasm" ]; then
    cp -f "$HOST_TOOLS_DIR/bin/ytasm" "$PREBUILT_BIN/ytasm"
fi
if [ -f "$HOST_TOOLS_DIR/bin/vsyasm" ]; then
    cp -f "$HOST_TOOLS_DIR/bin/vsyasm" "$PREBUILT_BIN/vsyasm"
fi

# Strip copied binaries
for b in "$PREBUILT_BIN/make" "$PREBUILT_BIN/yasm" "$PREBUILT_BIN/ytasm" "$PREBUILT_BIN/vsyasm" "$NDK_TOOLCHAIN/bin/yasm"; do
    [ -f "$b" ] && "$CROSS_STRIP" -s --strip-all "$b" 2>/dev/null || true
done

# Clean up any leftover unreplaced x86_64 ELF binaries in $PREBUILT_BIN
if [ "$TARGET_ARCH" != "x86_64" ]; then
    find "$PREBUILT_BIN" -type f | while IFS= read -r file; do
        if file "$file" | grep -q 'ELF.*x86-64'; then
            rm -f "$file"
        fi
    done
fi

# Copy helper scripts
if [ -f "$ROOT_DIR/ndk/patches/ndk/scripts/clang-tidy.sh" ]; then
    cp -f "$ROOT_DIR/ndk/patches/ndk/scripts/clang-tidy.sh" "$NDK_TOOLCHAIN/bin/clang-tidy.sh"
    chmod +x "$NDK_TOOLCHAIN/bin/clang-tidy.sh"
fi
if [ -f "$ROOT_DIR/ndk/patches/ndk/scripts/ndk-which" ]; then
    cp -f "$ROOT_DIR/ndk/patches/ndk/scripts/ndk-which" "$PREBUILT_BIN/ndk-which"
    chmod +x "$PREBUILT_BIN/ndk-which"
fi

# Remove unused x86_64 host resources
rm -rf "$NDK_TOOLCHAIN/python3"
rm -rf "$NDK_TOOLCHAIN/musl"
rm -rf "$NDK_ROOT/simpleperf"
find "$NDK_TOOLCHAIN/lib" -maxdepth 1 -mindepth 1 -not -name clang -exec rm -rf {} + 2>/dev/null || true
find "$NDK_TOOLCHAIN" -maxdepth 5 -path "*/lib/clang/[0-9][0-9]/lib/*" -not -name linux -exec rm -rf {} + 2>/dev/null || true

# Copy clang headers / runtime libraries
if [ -d "$HOST_LLVM_DIR/lib/clang" ]; then
    cp -Rf "$HOST_LLVM_DIR/lib/clang" "$NDK_TOOLCHAIN/lib/"
fi

# Update shebangs for portability across bionic and linux
for sh_file in "$NDK_ROOT/build/tools/ndk_bin_common.sh" "$NDK_ROOT/build/tools/make_standalone_toolchain.py" "$NDK_ROOT/build/ndk-build"; do
    [ -f "$sh_file" ] && sed -i 's,#!/usr/bin/env bash,#!/usr/bin/env sh,' "$sh_file"
done
for sh_bin in "$NDK_ROOT/ndk-gdb" "$NDK_ROOT/ndk-lldb" "$NDK_ROOT/ndk-stack" "$NDK_ROOT/ndk-which" "$PREBUILT_BIN/ndk-gdb" "$PREBUILT_BIN/ndk-stack" "$PREBUILT_BIN/ndk-which"; do
    if [ -f "$sh_bin" ]; then
        sed -i 's,#!/bin/bash,#!/bin/sh,' "$sh_bin"
        sed -i 's,#!/usr/bin/env bash,#!/usr/bin/env sh,' "$sh_bin"
        sed -i "s|linux-x86_64|$HOST_TAG|g" "$sh_bin"
    fi
done

# 6. Adjust host directory layout and CMake toolchains
log "Patching host tag and CMake toolchains for $TARGET_CANONICAL..."

# Normalize HOST_ARCH in ndk_bin_common.sh
if [ -f "$NDK_ROOT/build/tools/ndk_bin_common.sh" ]; then
    sed -i -E '/case \$HOST_ARCH in/,/esac/ c\
case $HOST_ARCH in\
  armv5te|armv6|armv6l|armv7|armv7l|armv8l) HOST_ARCH=arm;;\
  armv8b) HOST_ARCH=arm_be;;\
  aarch64|arm64) HOST_ARCH=arm64;;\
  aarch64_be) HOST_ARCH=arm64_be;;\
  i?86) HOST_ARCH=x86;;\
  amd64|x86_64) HOST_ARCH=x86_64;;\
  riscv64) HOST_ARCH=riscv64;;\
  *) HOST_ARCH=$HOST_ARCH;;\
esac' "$NDK_ROOT/build/tools/ndk_bin_common.sh"
fi

# Patch cmake toolchain files to dynamically resolve uname -m on Android/Termux
for tc in "$NDK_ROOT/build/cmake/android.toolchain.cmake" "$NDK_ROOT/build/cmake/android-legacy.toolchain.cmake"; do
    if [ -f "$tc" ]; then
        sed -i -E '/^if\(CMAKE_HOST_SYSTEM_NAME STREQUAL Linux\)$/,/^endif\(\)$/c\
if(CMAKE_HOST_SYSTEM_NAME STREQUAL Linux OR CMAKE_HOST_SYSTEM_NAME STREQUAL Android)\
    execute_process(\
        COMMAND uname -m\
        OUTPUT_VARIABLE HOST_ARCH\
        OUTPUT_STRIP_TRAILING_WHITESPACE\
    )\
\
    if(HOST_ARCH STREQUAL "aarch64")\
        set(ARCH "arm64")\
    elseif(HOST_ARCH MATCHES "^armv[0-9]+l$")\
        set(ARCH "arm")\
    elseif(HOST_ARCH STREQUAL "arm64" OR HOST_ARCH STREQUAL "arm64e")\
        set(ARCH "arm64")\
    elseif(HOST_ARCH STREQUAL "amd64")\
        set(ARCH "x86_64")\
    elseif(HOST_ARCH MATCHES "^i[3-6]86$")\
        set(ARCH "x86")\
    else()\
        set(ARCH "${HOST_ARCH}")\
    endif()\
\
    set(ANDROID_HOST_TAG "linux-${ARCH}")\
\
elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL Darwin)\
    set(ANDROID_HOST_TAG "darwin-x86_64")\
elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL Windows)\
    set(ANDROID_HOST_TAG "windows-x86_64")\
endif()' "$tc"
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

# Normalize ELF PT_TLS segment alignment across assembled NDK
if [ -f "$SCRIPT_DIR/normalize-tls.py" ]; then
    log "Normalizing ELF PT_TLS segment alignment across $NDK_ROOT..."
    python3 "$SCRIPT_DIR/normalize-tls.py" "$NDK_ROOT" || true
fi

# 7. Verification
if [ "$VERIFY_AFTER_BUILD" = true ]; then
    log "Verifying assembled NDK cross-compilation capability..."
    "$SCRIPT_DIR/verify-ndk.sh" --ndk="$NDK_ROOT" --release="$RELEASE_CLEAN" --target="$TARGET_CANONICAL"
fi

# 8. Package
if [ "$PACKAGE_AFTER_BUILD" = true ]; then
    log "Packaging Custom NDK..."
    "$SCRIPT_DIR/package-ndk.sh" --ndk="$NDK_ROOT" --release="$RELEASE_CLEAN" --target="$TARGET_CANONICAL"
fi

log "Custom Android NDK $RELEASE_CLEAN ($TARGET_CANONICAL) build process completed successfully!"
