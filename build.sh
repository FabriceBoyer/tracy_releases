#!/bin/bash
# Builds Tracy release packages inside containers.
#
# Usage: ./build.sh <distro|all> [x11|wayland|all]
#   distro: ubuntu-20.04 ubuntu-22.04 ubuntu-24.04 rhel-8 rhel-9
#
# Packages are written to ./dist. Environment overrides:
#   CONTAINER_ENGINE  docker (default) or podman
#   BASE_IMAGE        base image to use instead of the default for the distro
#   TRACY_VERSION     Tracy version (default: content of TRACY_VERSION)
#   JOBS              build parallelism inside the container
set -euo pipefail

cd "$(dirname "$0")"

DISTROS=(ubuntu-20.04 ubuntu-22.04 ubuntu-24.04 rhel-8 rhel-9)
VARIANTS=(x11 wayland)
ENGINE=${CONTAINER_ENGINE:-docker}
TRACY_VERSION=${TRACY_VERSION:-$(cat TRACY_VERSION)}

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

# Prints "<dockerfile> <default base image>" for a distro tag.
distro_config() {
    case "$1" in
        ubuntu-20.04|ubuntu-22.04|ubuntu-24.04) echo "docker/ubuntu.Dockerfile ubuntu:${1#ubuntu-}" ;;
        rhel-8|rhel-9) echo "docker/rhel.Dockerfile quay.io/rockylinux/rockylinux:${1#rhel-}" ;;
        *) echo "Unknown distro: $1" >&2; usage ;;
    esac
}

[ $# -ge 1 ] || usage
if [ "$1" = all ]; then distros=("${DISTROS[@]}"); else distros=("$1"); fi
if [ "${2:-all}" = all ]; then variants=("${VARIANTS[@]}"); else variants=("$2"); fi

mkdir -p dist
for distro in "${distros[@]}"; do
    read -r dockerfile default_base < <(distro_config "$distro")
    image="tracy-build:$distro"
    echo "==> Building image $image"
    "$ENGINE" build -f "$dockerfile" --build-arg BASE_IMAGE="${BASE_IMAGE:-$default_base}" -t "$image" .
    for variant in "${variants[@]}"; do
        echo "==> Building Tracy $TRACY_VERSION for $distro ($variant)"
        "$ENGINE" run --rm \
            -e TRACY_VERSION="$TRACY_VERSION" \
            ${JOBS:+-e JOBS="$JOBS"} \
            -v "$PWD:/src:ro" \
            -v "$PWD/dist:/dist" \
            "$image" \
            /src/scripts/build-tracy.sh "$variant" "$distro" /dist
    done
done
ls -l dist
