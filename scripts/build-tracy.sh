#!/bin/bash
# Builds Tracy (profiler GUI + command line utilities) and packages it as a
# relocatable tarball. Meant to run inside one of the docker/ build images.
#
# Usage: build-tracy.sh <x11|wayland> <distro-tag> <output-dir>
#
# Environment:
#   TRACY_VERSION   Tracy release to build (default: content of TRACY_VERSION)
#   TRACY_REPO      Git repository to clone (default: upstream GitHub)
#   TRACY_SRC       Use an existing source checkout instead of cloning
#   WORK_DIR        Scratch directory (default: /tmp/tracy-build)
#   JOBS            Build parallelism (default: nproc)
#   TRACY_STATIC_LIBSTDCXX=1  Link libstdc++/libgcc statically (set by the
#                   Ubuntu images, whose GCC 13 may come from a PPA)
set -euo pipefail

VARIANT=${1:?variant (x11|wayland) required}
DISTRO=${2:?distro tag (e.g. ubuntu-24.04) required}
OUT_DIR=${3:?output directory required}

HERE=$(cd "$(dirname "$0")" && pwd)
TRACY_VERSION=${TRACY_VERSION:-$(cat "$HERE/../TRACY_VERSION")}
TRACY_REPO=${TRACY_REPO:-https://github.com/wolfpld/tracy.git}
WORK_DIR=${WORK_DIR:-/tmp/tracy-build}
JOBS=${JOBS:-$(nproc)}
WAYLAND_VERSION=${WAYLAND_VERSION:-1.25.0}
ARCH=$(uname -m)

case "$VARIANT" in
    x11|wayland) ;;
    *) echo "Unknown variant '$VARIANT' (expected x11 or wayland)" >&2; exit 1 ;;
esac

mkdir -p "$WORK_DIR" "$OUT_DIR"
OUT_DIR=$(cd "$OUT_DIR" && pwd)
export CPM_SOURCE_CACHE=${CPM_SOURCE_CACHE:-$WORK_DIR/cpm-cache}

log() { printf '\n==> %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Sources

if [ -n "${TRACY_SRC:-}" ]; then
    SRC=$(cd "$TRACY_SRC" && pwd)
else
    SRC="$WORK_DIR/tracy"
    if [ ! -d "$SRC/.git" ]; then
        log "Cloning Tracy v$TRACY_VERSION"
        git clone --depth 1 --branch "v$TRACY_VERSION" "$TRACY_REPO" "$SRC"
    fi
fi
GIT_REV=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo "v$TRACY_VERSION")

log "Toolchain"
gcc --version | head -1
cmake --version | head -1
ldd --version | head -1

COMMON_FLAGS=(
    -G Ninja
    -DCMAKE_BUILD_TYPE=Release
    -DNO_ISA_EXTENSIONS=ON
    -DNO_CCACHE=ON
    -DGIT_REV="$GIT_REV"
)
LINK_FLAGS=""
if [ "${TRACY_STATIC_LIBSTDCXX:-0}" = "1" ]; then
    LINK_FLAGS="-static-libstdc++ -static-libgcc"
fi
COMMON_FLAGS+=(-DCMAKE_EXE_LINKER_FLAGS="$LINK_FLAGS")

# ---------------------------------------------------------------------------
# Wayland client libraries
#
# Tracy's Wayland backend needs libwayland >= 1.22 (core protocol v6) for full
# functionality; Ubuntu 20.04/22.04 and RHEL 8/9 ship older releases. As in
# upstream's AppImage, a pinned libwayland is built and bundled next to the
# executable. The compositor protocol is stable, so this is safe.

WAYLAND_PREFIX="$WORK_DIR/wayland-$WAYLAND_VERSION"
if [ "$VARIANT" = wayland ]; then
    if [ ! -e "$WAYLAND_PREFIX/lib/pkgconfig/wayland-client.pc" ]; then
        log "Building libwayland $WAYLAND_VERSION"
        rm -rf "$WORK_DIR/wayland-src" "$WORK_DIR/wayland-build"
        git clone --depth 1 --branch "$WAYLAND_VERSION" \
            https://gitlab.freedesktop.org/wayland/wayland.git "$WORK_DIR/wayland-src"
        meson setup "$WORK_DIR/wayland-build" "$WORK_DIR/wayland-src" \
            --prefix "$WAYLAND_PREFIX" --libdir lib --buildtype release \
            -Ddocumentation=false -Dtests=false -Ddtd_validation=false
        meson install -C "$WORK_DIR/wayland-build"
    fi
    export PKG_CONFIG_PATH="$WAYLAND_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export PATH="$WAYLAND_PREFIX/bin:$PATH"
fi

# ---------------------------------------------------------------------------
# Profiler GUI

PROFILER_FLAGS=(
    # Vendor the libraries that are not available (or too old) everywhere,
    # so every package is built from the same versions.
    -DDOWNLOAD_CAPSTONE=ON
    -DDOWNLOAD_FREETYPE=ON
    -DDOWNLOAD_LIBCURL=ON
    -DDOWNLOAD_PUGIXML=ON
)
if [ "$VARIANT" = x11 ]; then
    PROFILER_FLAGS+=(
        -DLEGACY=ON
        -DDOWNLOAD_GLFW=ON
        # Pure X11 build: do not let GLFW pick its Wayland backend.
        -DGLFW_BUILD_WAYLAND=OFF
        -DGLFW_BUILD_X11=ON
    )
else
    PROFILER_FLAGS+=(
        -DLEGACY=OFF
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
        -DCMAKE_INSTALL_RPATH='$ORIGIN/../lib'
    )
fi

BUILD="$WORK_DIR/build-$VARIANT"

log "Building tracy-profiler ($VARIANT)"
cmake -S "$SRC/profiler" -B "$BUILD/profiler" "${COMMON_FLAGS[@]}" "${PROFILER_FLAGS[@]}"
cmake --build "$BUILD/profiler" --parallel "$JOBS"

# ---------------------------------------------------------------------------
# Command line utilities (independent from the windowing system)

TOOLS=(capture csvexport import merge update)
for tool in "${TOOLS[@]}"; do
    log "Building $tool"
    cmake -S "$SRC/$tool" -B "$BUILD/$tool" "${COMMON_FLAGS[@]}"
    cmake --build "$BUILD/$tool" --parallel "$JOBS"
done

# ---------------------------------------------------------------------------
# Package

NAME="tracy-$TRACY_VERSION-$DISTRO-$VARIANT-$ARCH"
STAGE="$WORK_DIR/stage/$NAME"
log "Packaging $NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" \
    "$STAGE/share/applications" \
    "$STAGE/share/mime/packages" \
    "$STAGE/share/icons/hicolor/scalable/apps" \
    "$STAGE/share/icons/hicolor/scalable/mimetypes" \
    "$STAGE/share/doc/tracy"

cp "$BUILD/profiler/tracy-profiler" "$STAGE/bin/"
cp "$BUILD/capture/tracy-capture" "$BUILD/capture/tracy-capture-daemon" "$STAGE/bin/"
cp "$BUILD/csvexport/tracy-csvexport" "$STAGE/bin/"
cp "$BUILD/import/tracy-import-chrome" "$BUILD/import/tracy-import-fuchsia" "$STAGE/bin/"
cp "$BUILD/merge/tracy-merge" "$STAGE/bin/"
cp "$BUILD/update/tracy-update" "$STAGE/bin/"
strip "$STAGE"/bin/*

if [ "$VARIANT" = wayland ]; then
    mkdir -p "$STAGE/lib"
    cp -L "$WAYLAND_PREFIX/lib/libwayland-client.so.0" \
          "$WAYLAND_PREFIX/lib/libwayland-cursor.so.0" \
          "$WAYLAND_PREFIX/lib/libwayland-egl.so.1" \
          "$STAGE/lib/"
    strip --strip-unneeded "$STAGE"/lib/*
fi

cp "$SRC/extra/desktop/tracy.desktop" "$STAGE/share/applications/"
cp "$SRC/extra/desktop/application-tracy.xml" "$STAGE/share/mime/packages/"
cp "$SRC/icon/icon.svg" "$STAGE/share/icons/hicolor/scalable/apps/tracy.svg"
cp "$SRC/icon/application-tracy.svg" "$STAGE/share/icons/hicolor/scalable/mimetypes/"
cp "$SRC/LICENSE" "$STAGE/LICENSE"
cp "$SRC/NEWS" "$STAGE/share/doc/tracy/NEWS"

. /etc/os-release
cat > "$STAGE/BUILDINFO" <<INFO
Tracy version : $TRACY_VERSION ($GIT_REV)
Variant       : $VARIANT
Built on      : $PRETTY_NAME ($ARCH)
Compiler      : $(gcc --version | head -1)
glibc         : $(ldd --version | head -1 | awk '{print $NF}')
Build date    : $(date -u +%Y-%m-%dT%H:%M:%SZ)
INFO

log "Runtime dependencies of tracy-profiler"
ldd "$STAGE/bin/tracy-profiler" | tee "$STAGE/share/doc/tracy/ldd-tracy-profiler.txt"
if ldd "$STAGE/bin/tracy-profiler" | grep -q "not found"; then
    echo "Unresolved libraries" >&2
    exit 1
fi
"$STAGE/bin/tracy-capture" -h >/dev/null 2>&1 || true

tar -C "$WORK_DIR/stage" -czf "$OUT_DIR/$NAME.tar.gz" "$NAME"
(cd "$OUT_DIR" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256")
log "Done: $OUT_DIR/$NAME.tar.gz"
