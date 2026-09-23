#!/bin/sh
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi
# ==============================================================================
# Apex Toolchains - build-llvm.sh
# Build fully static native Android (Bionic) & Linux LLVM/Clang with exact AOSP revisions
# Supports native execution on Android (Termux, PRoot, Android apps) and Linux
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_FILE="$ROOT_DIR/metadata/llvm-releases.yaml"

REVISION=""
TARGET="${TARGET:-}"
PLATFORM="${PLATFORM:-}"            # bionic | linux
BUILD_DIR=""
INSTALL_DIR=""
JOBS="$(nproc 2>/dev/null || echo 4)"
BUILD_TYPE="MinSizeRel"
PACKAGE_AFTER_BUILD=true
VERIFY_AFTER_BUILD=true
NDK_DIR="${NDK_DIR:-}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==> WARNING:\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m==> ERROR:\033[0m %s\n' "$*" >&2; }

# Resilient fetch helper with retries
fetch_url() {
    local url="$1" out="$2" i=0
    mkdir -p "$(dirname "$out")"
    while :; do
        rm -f "$out" "$out.aria2"
        if command -v aria2c >/dev/null; then
            if aria2c --console-log-level=error --check-certificate=false \
                       --max-tries=5 --retry-wait=2 --connect-timeout=15 \
                       --allow-overwrite=true --auto-file-renaming=false \
                       --dir="$(dirname "$out")" -o "$(basename "$out")" "$url"; then
                return 0
            fi
        elif curl -fsSL -o "$out" "$url"; then
            return 0
        fi
        i=$((i + 1))
        [ "$i" -ge 5 ] && { err "fetch_url: failed to download $url after $i attempts"; return 1; }
        warn "Download failed, retrying in 2s..."
        sleep 2
    done
}

unpack_archive() {
    local archive="$1" dest="$2"
    mkdir -p "$dest"
    case "$archive" in
        *.tar.gz|*.tgz) tar -xzf "$archive" -C "$dest" ;;
        *.tar.xz)       tar -xJf "$archive" -C "$dest" ;;
        *.tar.bz2)      tar -xjf "$archive" -C "$dest" ;;
        *.zip)          unzip -qq -o "$archive" -d "$dest" ;;
        *) err "Unknown archive format: $archive"; return 1 ;;
    esac
}

fetch_and_unpack() {
    local url="$1" archive="$2" dest="$3"
    if [ ! -f "$archive" ]; then
        fetch_url "$url" "$archive"
    fi
    unpack_archive "$archive" "$dest"
}

usage() {
    cat <<EOF
Usage: $0 --revision=<name> [options]

Options:
  --revision=<name>    LLVM revision to build (e.g. clang-r487747e)
  --target=<triple>    Host execution target (default: aarch64-linux-android for bionic, aarch64-linux-gnu for linux)
                       [aarch64 | armv7a | x86_64 | i686] or full triple
  --platform=<plat>    Target execution environment: bionic (default) | linux
  --jobs=<N>           Build parallelism (default: $JOBS)
  --build-dir=<dir>    Scratch directory for compilation
  --prefix=<dir>       Installation destination prefix
  --ndk-dir=<dir>      Existing Android NDK directory (optional)
  --no-package         Skip packaging after build
  --no-verify          Skip verification after build
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
        --jobs=*) JOBS="${1#*=}" ;;
        --jobs) shift; JOBS="$1" ;;
        --build-dir=*) BUILD_DIR="${1#*=}" ;;
        --build-dir) shift; BUILD_DIR="$1" ;;
        --prefix=*) INSTALL_DIR="${1#*=}" ;;
        --prefix) shift; INSTALL_DIR="$1" ;;
        --ndk-dir=*) NDK_DIR="${1#*=}" ;;
        --ndk-dir) shift; NDK_DIR="$1" ;;
        --no-package) PACKAGE_AFTER_BUILD=false ;;
        --no-verify) VERIFY_AFTER_BUILD=false ;;
        -h|--help) usage ;;
        *) err "Unknown option: $1"; usage ;;
    esac
    shift
done

[ -n "$REVISION" ] || { err "Revision is required (--revision=<name>)"; usage; }

# Infer platform from target if not explicitly passed
if [ -z "$PLATFORM" ]; then
    case "$TARGET" in
        *-linux-gnu*|linux-gnu*) PLATFORM="linux" ;;
        *-linux-android*|linux-android*) PLATFORM="bionic" ;;
        *) PLATFORM="bionic" ;;
    esac
fi

# Default target if empty
if [ -z "$TARGET" ]; then
    if [ "$PLATFORM" = "linux" ]; then
        TARGET="aarch64-linux-gnu"
    else
        TARGET="aarch64-linux-android"
    fi
fi

# Canonicalize target architecture based on platform
if [ "$PLATFORM" = "linux" ]; then
    case "$TARGET" in
        aarch64-linux-gnu|aarch64|arm64|linux-arm64)
            TARGET_CANONICAL="aarch64-linux-gnu"
            TARGET_ARCH="AArch64"
            TARGET_PROC="aarch64"
            ;;
        arm-linux-gnueabihf|armv7a-linux-gnueabihf|arm|armv7a|linux-arm)
            TARGET_CANONICAL="armv7a-linux-gnueabihf"
            TARGET_ARCH="ARM"
            TARGET_PROC="arm"
            ;;
        x86_64-linux-gnu|x86_64|amd64|linux-x86_64)
            TARGET_CANONICAL="x86_64-linux-gnu"
            TARGET_ARCH="X86"
            TARGET_PROC="x86_64"
            ;;
        i686-linux-gnu|i686|x86|linux-x86)
            TARGET_CANONICAL="i686-linux-gnu"
            TARGET_ARCH="X86"
            TARGET_PROC="i686"
            ;;
        *)
            TARGET_CANONICAL="$TARGET"
            TARGET_ARCH="AArch64"
            TARGET_PROC="aarch64"
            ;;
    esac
else
    # bionic platform
    case "$TARGET" in
        aarch64-linux-android|aarch64|arm64|linux-arm64)
            TARGET_CANONICAL="aarch64-linux-android"
            TARGET_ARCH="AArch64"
            TARGET_PROC="aarch64"
            ;;
        arm-linux-androideabi|armv7a-linux-androideabi|arm|armv7a|linux-arm)
            TARGET_CANONICAL="armv7a-linux-androideabi"
            TARGET_ARCH="ARM"
            TARGET_PROC="arm"
            ;;
        x86_64-linux-android|x86_64|amd64|linux-x86_64)
            TARGET_CANONICAL="x86_64-linux-android"
            TARGET_ARCH="X86"
            TARGET_PROC="x86_64"
            ;;
        i686-linux-android|i686|x86|linux-x86)
            TARGET_CANONICAL="i686-linux-android"
            TARGET_ARCH="X86"
            TARGET_PROC="i686"
            ;;
        *)
            TARGET_CANONICAL="$TARGET"
            TARGET_ARCH="AArch64"
            TARGET_PROC="aarch64"
            ;;
    esac
fi

# Normalize revision
REVISION_CLEAN="${REVISION#llvm-}"
[ "${REVISION_CLEAN#clang-}" = "$REVISION_CLEAN" ] && REVISION_CLEAN="clang-$REVISION_CLEAN"

WORK_DIR="$ROOT_DIR/build/$REVISION_CLEAN-$TARGET_CANONICAL"
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/ninja-build}"
INSTALL_DIR="${INSTALL_DIR:-$WORK_DIR/install}"
mkdir -p "$BUILD_DIR" "$INSTALL_DIR"

log "Configuring build for $REVISION_CLEAN (Target: $TARGET_CANONICAL, Platform: $PLATFORM, Jobs: $JOBS)"

# Read metadata for the revision
META="$(python3 -c "
import yaml, re

metadata_file = '$METADATA_FILE'
rev = '$REVISION_CLEAN'

with open(metadata_file) as f:
    data = yaml.safe_load(f)

entry = next((r for r in data.get('releases', []) if r['revision'] == rev), None)
if not entry:
    # Match by tag or prefix
    entry = next((r for r in data.get('releases', []) if rev.endswith(r['revision'].replace('clang-', ''))), None)

if entry:
    ndks = entry.get('ndk_releases', [])
    m = re.search(r'r(\d+)', ndks[0] if ndks else rev)
    ndk_major = m.group(1) if m else '26'
    targets = entry.get('targets') or data.get('llvm_targets') or ['AArch64', 'ARM', 'X86', 'RISCV', 'WebAssembly']
    targets_str = ';'.join(targets)
    print(f\"{entry['llvm_version']}|{entry['llvm_project_commit']}|{entry['llvm_android_commit']}|{ndk_major}|{targets_str}\")
else:
    print('17.0.2|d9f89f4d16663d5012e5c09495f3b30ece3d2362|8443a75fcd5c80245b194f6510b98a11098fe7fe|26|AArch64;ARM;X86;RISCV;WebAssembly')
")"

IFS='|' read -r LLVM_VER LLVM_PROJ_COMMIT LLVM_AND_COMMIT NDK_MAJOR TARGETS_STR <<< "$META"
LLVM_MAJOR="${LLVM_VER%%.*}"
log "Metadata: LLVM $LLVM_VER (Project: $LLVM_PROJ_COMMIT, llvm_android: $LLVM_AND_COMMIT, NDK base: r$NDK_MAJOR, Backends: $TARGETS_STR)"

# 1. Fetch exact source code
SRC_DIR="$WORK_DIR/source"
if [ ! -d "$SRC_DIR/llvm-project" ]; then
    log "Source not found, running fetch-llvm.sh..."
    "$SCRIPT_DIR/fetch-llvm.sh" --revision="$REVISION_CLEAN" --source-only --dest="$WORK_DIR"
fi

LLVM_SRC="$SRC_DIR/llvm-project"
LLVM_AND="$SRC_DIR/llvm_android"

# Ensure $LLVM_SRC is a valid git repository for git apply
git -C "$LLVM_SRC" init -q 2>/dev/null || true

# 2. Apply Android downstream patches from llvm_android
log "Checking and applying Android downstream patches..."
if [ -d "$LLVM_AND/patches" ] && [ -f "$LLVM_AND/patches/PATCHES.json" ]; then
    python3 -c "
import json, os, subprocess, re

patches_json = '$LLVM_AND/patches/PATCHES.json'
src_dir = '$LLVM_SRC'
patches_dir = '$LLVM_AND/patches'
revision = '$REVISION_CLEAN'

match = re.search(r'r(\d+)', revision)
svn_rev = int(match.group(1)) if match else None

subprocess.run(['git', '-C', src_dir, 'reset', '--hard', 'HEAD'], capture_output=True)
subprocess.run(['git', '-C', src_dir, 'clean', '-fd'], capture_output=True)

try:
    with open(patches_json) as f:
        patches = json.load(f)
    applied, skipped = 0, 0
    for entry in patches:
        rel_path = entry.get('rel_patch_path') or entry.get('patch')
        if not rel_path:
            continue
        if svn_rev is not None:
            vr = entry.get('version_range', {}) or {}
            from_v = 0 if vr.get('from') is None else vr.get('from')
            until_v = float('inf') if vr.get('until') is None else vr.get('until')
            if not (from_v <= svn_rev < until_v):
                continue
        platforms = entry.get('platforms', ['android'])
        if platforms and 'android' not in platforms:
            continue
        patch_file = os.path.join(patches_dir, rel_path)
        if not os.path.isfile(patch_file):
            continue
        check = subprocess.run(['git', '-C', src_dir, 'apply', '--check', patch_file], capture_output=True)
        if check.returncode == 0:
            res = subprocess.run(['git', '-C', src_dir, 'apply', '-v', patch_file], capture_output=True)
            if res.returncode == 0:
                applied += 1
            else:
                skipped += 1
        else:
            skipped += 1
    print(f'Applied {applied} patches from llvm_android ({skipped} skipped/clean).')
except Exception as e:
    print('Notice from patch runner:', e)
" || true
fi

# 3. Apply custom global patches if present
GLOBAL_PATCH_DIR="$ROOT_DIR/llvm/patches/global/llvm/$LLVM_PROJ_COMMIT"
if [ -d "$GLOBAL_PATCH_DIR" ]; then
    log "Applying global custom patches for commit $LLVM_PROJ_COMMIT..."
    for p in "$GLOBAL_PATCH_DIR"/*.patch; do
        [ -f "$p" ] || continue
        if git -C "$LLVM_SRC" apply --check "$p" 2>/dev/null; then
            log "Applying patch: $(basename "$p")"
            git -C "$LLVM_SRC" apply "$p" || warn "Could not apply $(basename "$p")"
        fi
    done
fi

# 4. Source tree fixups for cross compilation & Bionic static linking
# Exclude clang-ast-dump from all targets (it is unneeded in cross-compilation and breaks static Bionic link)
_dump="$LLVM_SRC/clang/lib/Tooling/DumpTool/CMakeLists.txt"
if [ -f "$_dump" ] && ! grep -q 'EXCLUDE_FROM_ALL' "$_dump"; then
    printf '\nset_target_properties(clang-ast-dump PROPERTIES EXCLUDE_FROM_ALL ON)\n' >> "$_dump"
    log "Patched clang-ast-dump to EXCLUDE_FROM_ALL for cross compilation"
fi

# Guard llvm-rtdyld on !__ANDROID__
_rtdyld="$LLVM_SRC/llvm/tools/llvm-rtdyld/llvm-rtdyld.cpp"
if [ -f "$_rtdyld" ]; then
    sed -i -E '/^#if defined\(__x86_64__\) && defined\(__ELF__\)( && defined\(__linux__\))?$/ {
        /&& !defined\(__ANDROID__\)/! s/$/ \&\& !defined(__ANDROID__)/
    }' "$_rtdyld" 2>/dev/null || true
fi

# 5. Toolchain and cross-compilation configuration
CROSS_CFLAGS="-fno-sanitize=undefined"
CROSS_CXXFLAGS="$CROSS_CFLAGS"
CROSS_LDFLAGS=""
SYSTEM_NAME="Linux"
TRIPLE="$TARGET_CANONICAL"
LLVM_STATIC=OFF
LLVM_PIC=OFF

if [ "$PLATFORM" = "bionic" ]; then
    API="${ANDROID_API:-24}"
    [ "$TARGET_CANONICAL" = "riscv64-linux-android" ] && [ "$API" -lt 35 ] && API=35
    
    # Locate or download official NDK base for the matching toolchain
    if [ -z "$NDK_DIR" ] || [ ! -d "$NDK_DIR" ]; then
        NDK_CACHE="$ROOT_DIR/build/ndk-cache"
        mkdir -p "$NDK_CACHE"
        case "$NDK_MAJOR" in
            26) NDK_ARCHIVE_NAME="android-ndk-r26d-linux.zip" ;;
            27) NDK_ARCHIVE_NAME="android-ndk-r27c-linux.zip" ;;
            28) NDK_ARCHIVE_NAME="android-ndk-r28c-linux.zip" ;;
            29) NDK_ARCHIVE_NAME="android-ndk-r29-linux.zip" ;;
            30) NDK_ARCHIVE_NAME="android-ndk-r30-linux.zip" ;;
            *)  NDK_ARCHIVE_NAME="android-ndk-r${NDK_MAJOR}-linux.zip" ;;
        esac
        
        NDK_ZIP="$NDK_CACHE/$NDK_ARCHIVE_NAME"
        NDK_UNPACK="$NDK_CACHE/android-ndk-r${NDK_MAJOR}"
        if [ ! -d "$NDK_UNPACK" ]; then
            log "Downloading base official Android NDK ($NDK_ARCHIVE_NAME)..."
            fetch_url "https://dl.google.com/android/repository/$NDK_ARCHIVE_NAME" "$NDK_ZIP"
            log "Unpacking Android NDK to $NDK_UNPACK..."
            mkdir -p "$NDK_UNPACK"
            unzip -qq -o "$NDK_ZIP" -d "$NDK_UNPACK"
        fi
        NDK_DIR="$(find "$NDK_UNPACK" -maxdepth 2 -mindepth 1 -type d -name 'android-ndk-*' | head -n1)"
        if [ -z "$NDK_DIR" ]; then
            NDK_DIR="$NDK_UNPACK"
        fi
    fi
    
    TC="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64"
    if [ ! -d "$TC" ]; then
        # Check host arch if building on aarch64
        TC="$(find "$NDK_DIR/toolchains/llvm/prebuilt" -maxdepth 1 -mindepth 1 -type d | head -n1)"
    fi
    [ -d "$TC" ] || { err "Cannot find NDK toolchains in $NDK_DIR"; exit 1; }

    CROSS_CC="$TC/bin/${TARGET_CANONICAL}${API}-clang"
    CROSS_CXX="${CROSS_CC}++"
    CROSS_AR="$TC/bin/llvm-ar"
    CROSS_RANLIB="$TC/bin/llvm-ranlib"
    CROSS_STRIP="$TC/bin/llvm-strip"
    CROSS_OBJCOPY="$TC/bin/llvm-objcopy"
    CROSS_LD="$TC/bin/ld"
    TRIPLE="${TARGET_CANONICAL}${API}"
    
    # 100% static Bionic compilation: no dynamic glibc or ld-linux dependencies!
    CROSS_CFLAGS="-static -fno-sanitize=undefined -fdata-sections -ffunction-sections"
    CROSS_CXXFLAGS="$CROSS_CFLAGS -fvisibility-inlines-hidden"
    CROSS_LDFLAGS="-static -Wl,-z,max-page-size=16384 -Wl,--gc-sections -Wl,--icf=all"
    LLVM_STATIC=ON
    SYSTEM_NAME="Linux"

    log "Using Android NDK Clang cross-compiler: $CROSS_CC"

    # Avoid AArch64 Bionic libc.a conditional branch relocation out of range (R_AARCH64_CONDBR19)
    # by generating a symbol-ordering file hoisting __set_errno_internal
    mkdir -p "$BUILD_DIR"
    printf '%s\n' __set_errno_internal > "$BUILD_DIR/symbol-order.txt"
    _libc="$(find "$TC/sysroot/usr/lib" -name libc.a 2>/dev/null | grep "/$TARGET_CANONICAL/" | head -n1 || true)"
    if [ -z "$_libc" ]; then
        _libc="$(find "$TC/sysroot/usr/lib" -name libc.a 2>/dev/null | head -n1 || true)"
    fi
    if [ -n "$_libc" ] && [ -f "$_libc" ] && [ -x "$TC/bin/llvm-nm" ]; then
        "$TC/bin/llvm-nm" --print-file-name "$_libc" 2>/dev/null > "$BUILD_DIR/libc.nm" || true
        awk '
          NF == 1 && /:$/ { mem = $0; next }
          $1 ~ /:$/ && NF > 2 { mem = $1 }
          NF >= 2 && $(NF-1) == "U" && $NF == "__set_errno_internal" { ref[mem] = 1; next }
          NF >= 2 && $(NF-1) ~ /^[TtWw]$/ && !(mem in first) { first[mem] = $NF }
          END { for (m in ref) if (m in first) print first[m] }
        ' "$BUILD_DIR/libc.nm" >> "$BUILD_DIR/symbol-order.txt" 2>/dev/null || true
        rm -f "$BUILD_DIR/libc.nm"
    fi
    _so="-Wl,--symbol-ordering-file=$BUILD_DIR/symbol-order.txt -Wl,--no-warn-symbol-ordering"
    echo 'int main(void){return 0;}' > "$BUILD_DIR/so-probe.c"
    if "$CROSS_CC" $CROSS_CFLAGS $CROSS_LDFLAGS $_so "$BUILD_DIR/so-probe.c" -o "$BUILD_DIR/so-probe" >/dev/null 2>&1; then
        CROSS_LDFLAGS="$CROSS_LDFLAGS $_so"
        log "Enabled Bionic symbol ordering for AArch64 conditional branch protection"
    fi
    rm -f "$BUILD_DIR/so-probe.c" "$BUILD_DIR/so-probe"
else
    # Linux (musl or glibc)
    case "$TARGET_PROC" in
        arm) CROSS_PREFIX="arm-linux-gnueabihf-" ;;
        *)   CROSS_PREFIX="${TARGET_PROC}-linux-gnu-" ;;
    esac
    if command -v "${CROSS_PREFIX}gcc" >/dev/null; then
        CROSS_CC="${CROSS_PREFIX}gcc"
        CROSS_CXX="${CROSS_PREFIX}g++"
        CROSS_AR="${CROSS_PREFIX}ar"
        CROSS_RANLIB="${CROSS_PREFIX}ranlib"
        CROSS_STRIP="${CROSS_PREFIX}strip"
        CROSS_OBJCOPY="${CROSS_PREFIX}objcopy"
        CROSS_LD="${CROSS_PREFIX}ld"
    else
        CROSS_CC="clang"
        CROSS_CXX="clang++"
        CROSS_AR="llvm-ar"
        CROSS_RANLIB="llvm-ranlib"
        CROSS_STRIP="llvm-strip"
        CROSS_OBJCOPY="llvm-objcopy"
        CROSS_LD="ld.lld"
    fi
fi

# 6. Build static zlib & zstd for the target (bundled static dependencies)
DEPS_DIR="$WORK_DIR/deps/$TARGET_CANONICAL"
mkdir -p "$DEPS_DIR"

ZLIB_VER="1.3.1"
if [ ! -f "$DEPS_DIR/lib/libz.a" ]; then
    log "Building static zlib $ZLIB_VER for $TARGET_CANONICAL..."
    mkdir -p "$WORK_DIR/deps-src"
    fetch_and_unpack "https://github.com/madler/zlib/releases/download/v$ZLIB_VER/zlib-$ZLIB_VER.tar.xz" \
        "$WORK_DIR/deps-src/zlib-$ZLIB_VER.tar.xz" "$WORK_DIR/deps-src"
    (
        cd "$WORK_DIR/deps-src/zlib-$ZLIB_VER"
        AR="$CROSS_AR" RANLIB="$CROSS_RANLIB" CC="$CROSS_CC" CFLAGS="$CROSS_CFLAGS" \
            ./configure --prefix="$DEPS_DIR" --static
        make -j"$JOBS" install
    )
fi

ZSTD_VER="1.5.7"
if [ ! -f "$DEPS_DIR/lib/libzstd.a" ]; then
    log "Building static zstd $ZSTD_VER for $TARGET_CANONICAL..."
    mkdir -p "$WORK_DIR/deps-src"
    fetch_and_unpack "https://github.com/facebook/zstd/archive/refs/tags/v$ZSTD_VER.tar.gz" \
        "$WORK_DIR/deps-src/zstd-$ZSTD_VER.tar.gz" "$WORK_DIR/deps-src"
    cmake -S "$WORK_DIR/deps-src/zstd-$ZSTD_VER/build/cmake" -B "$BUILD_DIR/zstd" -G Ninja \
        -DCMAKE_C_COMPILER="$CROSS_CC" -DCMAKE_CXX_COMPILER="$CROSS_CXX" -DCMAKE_ASM_COMPILER="$CROSS_CC" \
        -DCMAKE_AR="$CROSS_AR" -DCMAKE_RANLIB="$CROSS_RANLIB" -DCMAKE_STRIP="$CROSS_STRIP" \
        -DCMAKE_LINKER="$CROSS_LD" \
        -DCMAKE_C_FLAGS="$CROSS_CFLAGS" -DCMAKE_CXX_FLAGS="$CROSS_CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$CROSS_LDFLAGS" \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DCMAKE_CROSSCOMPILING=True -DCMAKE_SYSTEM_NAME="$SYSTEM_NAME" \
        -DCMAKE_INSTALL_PREFIX="$DEPS_DIR" \
        -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON -DZSTD_BUILD_PROGRAMS=OFF \
        -DZSTD_BUILD_TESTS=OFF -DZSTD_BUILD_CONTRIB=OFF -DZSTD_MULTITHREAD_SUPPORT=ON
    cmake --build "$BUILD_DIR/zstd" -j"$JOBS" --target install
fi

# 7. Distribution components setup
DIST=()
_want() {
    [ -d "$LLVM_SRC/$2" ] || return 0
    DIST+=("$1"); shift 2
    [ "$#" -gt 0 ] && DIST+=("$@")
    return 0
}
_want clang                  clang/tools/driver
_want clang-resource-headers clang/lib/Headers
_want clang-check            clang/tools/clang-check
_want clang-format           clang/tools/clang-format
_want clang-scan-deps        clang/tools/clang-scan-deps
_want scan-build             clang/tools/scan-build
_want scan-view              clang/tools/scan-view
_want scan-build-py          clang/tools/scan-build-py
_want clang-tidy             clang-tools-extra/clang-tidy
_want clangd                 clang-tools-extra/clangd
_want lld                    lld
_want bolt                   bolt
_want llvm-ar         llvm/tools/llvm-ar         llvm-ranlib llvm-lib llvm-dlltool
_want llvm-objcopy    llvm/tools/llvm-objcopy    llvm-strip
_want llvm-rc         llvm/tools/llvm-rc         llvm-windres
_want llvm-readobj    llvm/tools/llvm-readobj    llvm-readelf
_want llvm-symbolizer llvm/tools/llvm-symbolizer llvm-addr2line
for _t in dsymutil sancov sanstats llvm-config llvm-as llvm-cfi-verify \
          llvm-cov llvm-cxxfilt llvm-dis llvm-dwarfdump llvm-dwp llvm-ifs \
          llvm-link llvm-lipo llvm-ml llvm-modextract llvm-nm \
          llvm-objdump llvm-profdata llvm-size llvm-strings; do
    _want "$_t" "llvm/tools/$_t"
done

LLVM_DIST_COMPONENTS="$(IFS=';'; printf '%s' "${DIST[*]}")"

# Determine enabled LLVM projects:
DEFAULT_PROJECTS="bolt;clang;clang-tools-extra;lld;polly"
LLVM_PROJECTS="${LLVM_PROJECTS:-$DEFAULT_PROJECTS}"
log "Enabled LLVM projects: $LLVM_PROJECTS"

# 8. Configure CMake
log "Running CMake configuration for $REVISION_CLEAN..."
CMAKE_EXTRA_FLAGS=()

# Enable ccache if available
if command -v ccache >/dev/null; then
    log "ccache detected, enabling compiler caching..."
    CMAKE_EXTRA_FLAGS+=(
        "-DLLVM_CCACHE_BUILD=ON"
        "-DCMAKE_C_COMPILER_LAUNCHER=ccache"
        "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
    )
fi

# Older LLVM (<16) requires naming native host compiler for tblgen
if [ -n "$LLVM_MAJOR" ] && [ "$LLVM_MAJOR" -lt 16 ]; then
    CMAKE_EXTRA_FLAGS+=(
        "-DCROSS_TOOLCHAIN_FLAGS_NATIVE=-DCMAKE_C_COMPILER=/usr/bin/cc;-DCMAKE_CXX_COMPILER=/usr/bin/c++"
    )
fi

if [ -d "$LLVM_SRC/lld" ]; then
    CMAKE_EXTRA_FLAGS+=("-DLLD_SYMLINKS_TO_CREATE=lld-link;ld.lld;ld64.lld;wasm-ld;ld")
fi

cmake -S "$LLVM_SRC/llvm" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DCMAKE_PREFIX_PATH="$DEPS_DIR" \
    -DCMAKE_CROSSCOMPILING=True \
    -DCMAKE_SYSTEM_NAME="$SYSTEM_NAME" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$TRIPLE" \
    -DCMAKE_C_COMPILER="$CROSS_CC" \
    -DCMAKE_CXX_COMPILER="$CROSS_CXX" \
    -DCMAKE_ASM_COMPILER="$CROSS_CC" \
    -DCMAKE_LINKER="$CROSS_LD" \
    -DCMAKE_AR="$CROSS_AR" \
    -DCMAKE_RANLIB="$CROSS_RANLIB" \
    -DCMAKE_STRIP="$CROSS_STRIP" \
    ${CROSS_OBJCOPY:+-DCMAKE_OBJCOPY="$CROSS_OBJCOPY"} \
    -DCMAKE_C_FLAGS="$CROSS_CFLAGS" \
    -DCMAKE_CXX_FLAGS="$CROSS_CXXFLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$CROSS_LDFLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$CROSS_LDFLAGS" \
    -DCMAKE_MODULE_LINKER_FLAGS="$CROSS_LDFLAGS" \
    -DLLVM_TARGETS_TO_BUILD="${LLVM_TARGETS:-${TARGETS_STR:-AArch64;ARM;X86;RISCV;WebAssembly}}" \
    -DLLVM_ENABLE_PROJECTS="$LLVM_PROJECTS" \
    -DLLVM_DISTRIBUTION_COMPONENTS="$LLVM_DIST_COMPONENTS" \
    -DLLVM_ENABLE_LTO="${LLVM_LTO:-Thin}" \
    -DLLVM_ENABLE_UNWIND_TABLES=OFF \
    -DLLVM_BUILD_STATIC=$LLVM_STATIC \
    -DBUILD_SHARED_LIBS=OFF \
    -DLLVM_LINK_LLVM_DYLIB=OFF \
    -DLIBCLANG_BUILD_STATIC=ON \
    -DLLVM_ENABLE_PIC=$LLVM_PIC \
    -DCMAKE_SKIP_INSTALL_RPATH=TRUE \
    -DLLVM_ENABLE_ZLIB=FORCE_ON \
    -DLLVM_ENABLE_ZSTD=FORCE_ON \
    -DLLVM_USE_STATIC_ZSTD=ON \
    -DZLIB_LIBRARY="$DEPS_DIR/lib/libz.a" \
    -DZLIB_INCLUDE_DIR="$DEPS_DIR/include" \
    -Dzstd_LIBRARY="$DEPS_DIR/lib/libzstd.a" \
    -Dzstd_INCLUDE_DIR="$DEPS_DIR/include" \
    -DLLVM_BUILD_TOOLS=ON \
    -DLLVM_OPTIMIZED_TABLEGEN=ON \
    -DLLVM_ENABLE_WARNINGS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_BUILD_TESTS=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_BUILD_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_BUILD_EXAMPLES=OFF \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_THREADS=ON \
    -DLLVM_ENABLE_EH=OFF \
    -DLLVM_ENABLE_RTTI=OFF \
    -DLLVM_PARALLEL_COMPILE_JOBS="$JOBS" \
    -DLLVM_PARALLEL_LINK_JOBS=1 \
    -DCLANG_DEFAULT_LINKER=lld \
    -DCLANG_DEFAULT_OBJCOPY=llvm-objcopy \
    -DCLANG_VENDOR="Apex ($REVISION_CLEAN)" \
    "${CMAKE_EXTRA_FLAGS[@]}"

# 9. Build and install distribution components
log "Compiling distribution components for $REVISION_CLEAN ($TARGET_CANONICAL) with $JOBS jobs..."
cmake --build "$BUILD_DIR" -j "$JOBS" --target install-distribution

# 10. Strip installed binaries and libraries
log "Stripping installed binaries..."
find "$INSTALL_DIR/bin" -type f ! -lname '*' | while IFS= read -r f; do
    "$CROSS_STRIP" -s --strip-all "$f" 2>/dev/null || true
done

log "Stripping installed static libraries..."
find "$INSTALL_DIR/lib" -type f -name '*.a' | while IFS= read -r a; do
    "$CROSS_STRIP" --strip-debug "$a" 2>/dev/null || true
done

# Normalize ELF PT_TLS segment alignment across built LLVM
if [ -f "$SCRIPT_DIR/normalize-tls.py" ]; then
    log "Normalizing ELF PT_TLS segment alignment across $INSTALL_DIR..."
    python3 "$SCRIPT_DIR/normalize-tls.py" "$INSTALL_DIR" || true
fi

# 11. Verification
if [ "$VERIFY_AFTER_BUILD" = true ]; then
    log "Verifying built LLVM..."
    "$SCRIPT_DIR/verify-llvm.sh" --dir="$INSTALL_DIR" --revision="$REVISION_CLEAN" --target="$TARGET_CANONICAL" --platform="$PLATFORM"
fi

# 12. Packaging
if [ "$PACKAGE_AFTER_BUILD" = true ]; then
    log "Packaging LLVM artifact..."
    "$SCRIPT_DIR/package-llvm.sh" --dir="$INSTALL_DIR" --revision="$REVISION_CLEAN" --target="$TARGET_CANONICAL"
fi

log "LLVM $REVISION_CLEAN build completed successfully!"
