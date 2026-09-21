#!/bin/sh
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi
# ==============================================================================
# Apex Android Toolchains - build-llvm.sh
# Build native Linux ARM64 (aarch64) LLVM/Clang with exact AOSP revisions
# Supports Android Bionic execution (Termux/Android native) and Linux ARM64
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_FILE="$ROOT_DIR/metadata/llvm-releases.yaml"

REVISION=""
TARGET="${TARGET:-aarch64-linux-android}"  # aarch64-linux-android | armv7a-linux-androideabi | x86_64-linux-android | i686-linux-android
PLATFORM="${PLATFORM:-bionic}"            # bionic | linux
BUILD_DIR=""
INSTALL_DIR=""
JOBS="$(nproc 2>/dev/null || echo 4)"
BUILD_TYPE="Release"
PACKAGE_AFTER_BUILD=true
VERIFY_AFTER_BUILD=true

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==> WARNING:\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m==> ERROR:\033[0m %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $0 --revision=<name> [options]

Options:
  --revision=<name>    LLVM revision to build (e.g. clang-r487747e)
  --target=<triple>    Host execution target (default: aarch64-linux-android)
                       [aarch64-linux-android | armv7a-linux-androideabi | x86_64-linux-android | i686-linux-android]
  --platform=<plat>    Target execution environment: bionic (default) | linux
  --jobs=<N>           Build parallelism (default: $JOBS)
  --build-dir=<dir>    Scratch directory for compilation
  --prefix=<dir>       Installation destination prefix
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
        --no-package) PACKAGE_AFTER_BUILD=false ;;
        --no-verify) VERIFY_AFTER_BUILD=false ;;
        -h|--help) usage ;;
        *) err "Unknown option: $1"; usage ;;
    esac
    shift
done

[ -n "$REVISION" ] || { err "Revision is required (--revision=<name>)"; usage; }

# Canonicalize target architecture
case "$TARGET" in
    aarch64-linux-android|aarch64|arm64|linux-arm64)
        TARGET_CANONICAL="aarch64-linux-android"
        TARGET_ARCH="AArch64"
        TARGET_PROC="aarch64"
        CROSS_GCC="aarch64-linux-gnu-gcc"
        CROSS_GXX="aarch64-linux-gnu-g++"
        ;;
    arm-linux-androideabi|armv7a-linux-androideabi|arm|armv7a|linux-arm)
        TARGET_CANONICAL="armv7a-linux-androideabi"
        TARGET_ARCH="ARM"
        TARGET_PROC="arm"
        CROSS_GCC="arm-linux-gnueabihf-gcc"
        CROSS_GXX="arm-linux-gnueabihf-g++"
        ;;
    x86_64-linux-android|x86_64|amd64|linux-x86_64)
        TARGET_CANONICAL="x86_64-linux-android"
        TARGET_ARCH="X86"
        TARGET_PROC="x86_64"
        CROSS_GCC="x86_64-linux-gnu-gcc"
        CROSS_GXX="x86_64-linux-gnu-g++"
        ;;
    i686-linux-android|i686|x86|linux-x86)
        TARGET_CANONICAL="i686-linux-android"
        TARGET_ARCH="X86"
        TARGET_PROC="i686"
        CROSS_GCC="i686-linux-gnu-gcc"
        CROSS_GXX="i686-linux-gnu-g++"
        ;;
    *)
        TARGET_CANONICAL="$TARGET"
        TARGET_ARCH="AArch64"
        TARGET_PROC="aarch64"
        CROSS_GCC="aarch64-linux-gnu-gcc"
        CROSS_GXX="aarch64-linux-gnu-g++"
        ;;
esac

# Normalize revision
REVISION_CLEAN="${REVISION#llvm-}"
[ "${REVISION_CLEAN#clang-}" = "$REVISION_CLEAN" ] && REVISION_CLEAN="clang-$REVISION_CLEAN"

WORK_DIR="$ROOT_DIR/build/$REVISION_CLEAN-$TARGET_CANONICAL"
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/ninja-build}"
INSTALL_DIR="${INSTALL_DIR:-$WORK_DIR/install}"
mkdir -p "$BUILD_DIR" "$INSTALL_DIR"

log "Configuring build for $REVISION_CLEAN (Host Target: $TARGET_CANONICAL, Arch: $TARGET_ARCH, Jobs: $JOBS)"

# 1. Fetch exact source code
SRC_DIR="$WORK_DIR/source"
if [ ! -d "$SRC_DIR/llvm-project" ]; then
    log "Source not found, running fetch-llvm.sh..."
    "$SCRIPT_DIR/fetch-llvm.sh" --revision="$REVISION_CLEAN" --source-only --dest="$WORK_DIR"
fi

LLVM_SRC="$SRC_DIR/llvm-project"
LLVM_AND="$SRC_DIR/llvm_android"

# 2. Apply Android downstream patches
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

# Ensure working tree in llvm-project is clean before patching
subprocess.run(['git', '-C', src_dir, 'reset', '--hard', 'HEAD'], capture_output=True)
subprocess.run(['git', '-C', src_dir, 'clean', '-fd'], capture_output=True)

try:
    with open(patches_json) as f:
        patches = json.load(f)
    print(f'Found {len(patches)} total patches in metadata for {revision} (SVN: {svn_rev})')
    applied = 0
    excluded_range = 0
    already_applied = 0
    failed = 0

    for entry in patches:
        rel_path = entry.get('rel_patch_path') or entry.get('patch')
        if not rel_path:
            continue

        # Check version_range filter
        if svn_rev is not None:
            vr = entry.get('version_range', {}) or {}
            from_v = vr.get('from')
            until_v = vr.get('until')
            from_v = 0 if from_v is None else from_v
            until_v = float('inf') if until_v is None else until_v
            if not (from_v <= svn_rev < until_v):
                excluded_range += 1
                continue

        # Check platforms filter
        platforms = entry.get('platforms', ['android'])
        if platforms and 'android' not in platforms:
            continue

        patch_file = os.path.join(patches_dir, rel_path)
        if not os.path.isfile(patch_file):
            continue

        # Check if already applied
        check = subprocess.run(['git', '-C', src_dir, 'apply', '--check', '--reverse', patch_file], capture_output=True)
        if check.returncode == 0:
            already_applied += 1
            continue

        # Check if it applies cleanly
        can_apply = subprocess.run(['git', '-C', src_dir, 'apply', '--check', patch_file], capture_output=True)
        if can_apply.returncode == 0:
            res = subprocess.run(['git', '-C', src_dir, 'apply', '-v', patch_file], capture_output=True, text=True)
            if res.returncode == 0:
                applied += 1
            else:
                print(f'Warning: patch failed {rel_path}: {res.stderr}')
                failed += 1
        else:
            print(f'Notice: patch {rel_path} cannot be applied cleanly; skipping.')
            failed += 1

    print(f'Patch summary: {applied} applied, {already_applied} already applied, {excluded_range} excluded by version_range, {failed} skipped.')
except Exception as e:
    print('Patch manager notice:', e)
" || true
fi

# 3. Configure CMake
log "Running CMake configuration..."
CMAKE_EXTRA_FLAGS=()

# Host-specific compiler flags
CMAKE_EXTRA_FLAGS+=(
    "-DLLVM_DEFAULT_TARGET_TRIPLE=$TARGET_CANONICAL"
    "-DCMAKE_C_FLAGS=-fPIC -Wno-unused-command-line-argument"
    "-DCMAKE_CXX_FLAGS=-fPIC -Wno-unused-command-line-argument"
)

# Detect cross-compilation if build host differs from target host
BUILD_ARCH="$(uname -m)"
if [ "$BUILD_ARCH" != "$TARGET_PROC" ]; then
    log "Host machine is $BUILD_ARCH, cross-compiling for $TARGET_PROC ($TARGET_CANONICAL)..."
    CMAKE_EXTRA_FLAGS+=(
        "-DCMAKE_SYSTEM_NAME=Linux"
        "-DCMAKE_SYSTEM_PROCESSOR=$TARGET_PROC"
    )
    if command -v "$CROSS_GCC" >/dev/null; then
        CMAKE_EXTRA_FLAGS+=(
            "-DCMAKE_C_COMPILER=$CROSS_GCC"
            "-DCMAKE_CXX_COMPILER=$CROSS_GXX"
        )
    fi
fi

# Enable ccache if available
if command -v ccache >/dev/null; then
    log "ccache detected, enabling compiler caching..."
    CMAKE_EXTRA_FLAGS+=(
        "-DLLVM_CCACHE_BUILD=ON"
        "-DCMAKE_C_COMPILER_LAUNCHER=ccache"
        "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
    )
fi

# RAM & Linker Optimization (Prevent Runner OOM)
CMAKE_EXTRA_FLAGS+=(
    "-DLLVM_PARALLEL_COMPILE_JOBS=$JOBS"
    "-DLLVM_PARALLEL_LINK_JOBS=1"
)

# Determine enabled LLVM projects:
# clang, lld, clang-tools-extra, polly across all architectures.
# bolt is supported on 64-bit ELF architectures (AArch64, X86-64).
DEFAULT_PROJECTS="clang;lld;clang-tools-extra;polly"
if [ "$TARGET_ARCH" = "AArch64" ] || { [ "$TARGET_ARCH" = "X86" ] && [ "$TARGET_PROC" = "x86_64" ]; }; then
    DEFAULT_PROJECTS="$DEFAULT_PROJECTS;bolt"
fi
LLVM_PROJECTS="${LLVM_PROJECTS:-$DEFAULT_PROJECTS}"
log "Enabled LLVM projects: $LLVM_PROJECTS"

cmake -S "$LLVM_SRC/llvm" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DLLVM_TARGETS_TO_BUILD="${LLVM_TARGETS:-AArch64;ARM;X86;RISCV}" \
    -DLLVM_ENABLE_PROJECTS="$LLVM_PROJECTS" \
    -DLLVM_BUILD_TOOLS=ON \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_BUILD_TESTS=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_BUILD_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_BUILD_EXAMPLES=OFF \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_ZLIB=ON \
    -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_ENABLE_THREADS=ON \
    -DLLVM_TARGET_ARCH="$TARGET_ARCH" \
    -DCLANG_DEFAULT_LINKER=lld \
    -DCLANG_DEFAULT_OBJCOPY=llvm-objcopy \
    -DCLANG_VENDOR="Apex-Android ($REVISION_CLEAN)" \
    "${CMAKE_EXTRA_FLAGS[@]}"

# 4. Build
log "Compiling LLVM ($REVISION_CLEAN for $TARGET_CANONICAL) with $JOBS jobs..."
cmake --build "$BUILD_DIR" -j "$JOBS" --target install

# 5. Strip binaries safely across architectures
log "Stripping installed binaries..."
STRIP_BIN="strip"
if [ -f "$INSTALL_DIR/bin/llvm-strip" ]; then
    STRIP_BIN="$INSTALL_DIR/bin/llvm-strip"
elif command -v "${TARGET_PROC}-linux-gnu-strip" >/dev/null; then
    STRIP_BIN="${TARGET_PROC}-linux-gnu-strip"
fi
find "$INSTALL_DIR/bin" -type f -exec "$STRIP_BIN" --strip-unneeded {} + 2>/dev/null || true

# 6. Verification
if [ "$VERIFY_AFTER_BUILD" = true ]; then
    log "Verifying built LLVM..."
    "$SCRIPT_DIR/verify-llvm.sh" --dir="$INSTALL_DIR" --revision="$REVISION_CLEAN" --target="$TARGET_CANONICAL"
fi

# 7. Packaging
if [ "$PACKAGE_AFTER_BUILD" = true ]; then
    log "Packaging LLVM artifact..."
    "$SCRIPT_DIR/package-llvm.sh" --dir="$INSTALL_DIR" --revision="$REVISION_CLEAN" --target="$TARGET_CANONICAL"
fi

log "LLVM $REVISION_CLEAN build completed successfully!"
