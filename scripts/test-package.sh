#!/bin/bash
# Smoke test of a Tracy package on a pristine installation of its target
# distribution. Meant to run as root inside the plain distribution image
# (ubuntu:XX.04, rockylinux:X), not inside the build image.
#
# Usage: test-package.sh <tarball>
#
# - installs only the runtime libraries listed in the README,
# - checks that every executable resolves all its shared libraries,
# - runs the command line utilities,
# - X11 flavour: starts tracy-profiler on a virtual X server (Xvfb + Mesa
#   software rendering) and checks it is still running after a few seconds,
# - Wayland flavour: connects tracy-profiler to a headless Weston compositor
#   (where available, i.e. on Ubuntu).
set -euo pipefail

TARBALL=${1:?tarball required}
PKG_NAME=$(basename "$TARBALL" .tar.gz)

log() { printf '\n==> %s\n' "$*"; }

log "Installing runtime dependencies"
ID=$(. /etc/os-release && echo "$ID")
case "$ID" in
    ubuntu|debian)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        # "openssl" pulls in the libssl matching the distribution release.
        apt-get install -y -qq --no-install-recommends \
            libegl1 libgl1 libgl1-mesa-dri libdbus-1-3 libxkbcommon0 libgnutls30 openssl \
            libx11-6 libxext6 libxrandr2 libxinerama1 libxcursor1 libxi6 \
            xvfb >/dev/null
        case "$PKG_NAME" in
            *-wayland-*) apt-get install -y -qq --no-install-recommends weston >/dev/null ;;
        esac
        ;;
    rhel|rocky|almalinux|centos|ol)
        dnf install -y -q \
            libglvnd-egl libglvnd-glx mesa-libEGL mesa-libGL mesa-dri-drivers \
            dbus-libs libxkbcommon openssl-libs gnutls \
            libX11 libXext libXrandr libXinerama libXcursor libXi \
            xorg-x11-server-Xvfb >/dev/null
        ;;
    *) echo "Unsupported distribution $ID" >&2; exit 1 ;;
esac

log "Extracting $PKG_NAME"
DEST=$(mktemp -d)
tar -C "$DEST" -xzf "$TARBALL"
PKG="$DEST/$PKG_NAME"
cat "$PKG/BUILDINFO"

log "Checking shared libraries"
status=0
for exe in "$PKG"/bin/*; do
    if ldd "$exe" | grep "not found"; then
        echo "  -> unresolved libraries in $(basename "$exe")"
        status=1
    fi
done
[ $status -eq 0 ] || exit 1
echo "all libraries resolved"

log "Running command line utilities"
for tool in tracy-capture tracy-csvexport tracy-import-chrome tracy-import-fuchsia tracy-merge tracy-update; do
    # These print their usage and exit non-zero without arguments; a crash
    # or a loader error would not print the program banner.
    out=$("$PKG/bin/$tool" 2>&1 || true)
    if ! echo "$out" | grep -qi "tracy\|usage"; then
        echo "$tool failed:"; echo "$out"; exit 1
    fi
    echo "$tool: $(echo "$out" | head -1)"
done

case "$PKG_NAME" in
    *-x11-*)
        log "Starting tracy-profiler on Xvfb"
        Xvfb :99 -screen 0 1280x1024x24 >/dev/null 2>&1 &
        xvfb_pid=$!
        sleep 2
        export DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 HOME=$DEST
        set +e
        timeout 10 "$PKG/bin/tracy-profiler"
        rc=$?
        set -e
        kill "$xvfb_pid" 2>/dev/null || true
        # 124: killed by timeout, i.e. the GUI was up and running.
        if [ $rc -ne 124 ]; then
            echo "tracy-profiler exited early with status $rc" >&2
            exit 1
        fi
        echo "tracy-profiler ran for 10 seconds"
        ;;
    *-wayland-*)
        if command -v weston >/dev/null; then
            log "Starting tracy-profiler on a headless Weston compositor"
            export XDG_RUNTIME_DIR=$DEST/xdg HOME=$DEST
            mkdir -m 700 "$XDG_RUNTIME_DIR"
            weston --backend=headless-backend.so --socket=wl-test --idle-time=0 >"$DEST/weston.log" 2>&1 &
            weston_pid=$!
            for _ in $(seq 20); do [ -S "$XDG_RUNTIME_DIR/wl-test" ] && break; sleep 0.5; done
            set +e
            out=$(WAYLAND_DISPLAY=wl-test timeout 10 "$PKG/bin/tracy-profiler" 2>&1)
            rc=$?
            set -e
            kill "$weston_pid" 2>/dev/null || true
            echo "$out"
            # The headless compositor has no input seat, which Tracy requires:
            # reaching that check means the connection to the compositor and
            # the protocol negotiation with the bundled libwayland worked.
            if [ $rc -ne 124 ] && ! echo "$out" | grep -q "No wayland seat"; then
                echo "tracy-profiler failed with status $rc" >&2
                exit 1
            fi
        else
            log "Checking tracy-profiler loads (no Wayland compositor available)"
            out=$("$PKG/bin/tracy-profiler" 2>&1 || true)
            echo "$out"
            echo "$out" | grep -qi "wayland" || { echo "unexpected output" >&2; exit 1; }
        fi
        ;;
esac

log "OK: $PKG_NAME"
