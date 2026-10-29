#!/bin/bash
# Builds Tracy release packages inside containers.
#
# Usage: ./build.sh <distro|all> [x11|wayland|all]
#   distro: ubuntu-20.04 ubuntu-22.04 ubuntu-24.04 rhel-8 rhel-9
#
# Packages are written to ./dist. Intermediate build files are kept in the
# docker volume tracy-work-<distro> to speed up rebuilds (remove it with
# "docker volume rm tracy-work-<distro>"). Environment overrides:
#   CONTAINER_ENGINE  docker (default) or podman
#   BASE_IMAGE        base image to use instead of the default (single distro)
#   TRACY_VERSION     Tracy version (default: content of TRACY_VERSION)
#   JOBS              build parallelism inside the container
set -euo pipefail

cd "$(dirname "$0")"

DISTROS=(ubuntu-20.04 ubuntu-22.04 ubuntu-24.04 rhel-8 rhel-9)
VARIANTS=(x11 wayland)
ENGINE=${CONTAINER_ENGINE:-docker}
TRACY_VERSION=${TRACY_VERSION:-$(cat TRACY_VERSION)}

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0" >&2; exit 1; }

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

for distro in "${distros[@]}"; do distro_config "$distro" >/dev/null; done
for variant in "${variants[@]}"; do
    case "$variant" in x11|wayland) ;; *) echo "Unknown variant: $variant" >&2; usage ;; esac
done

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
            -v "tracy-work-$distro:/tmp/tracy-build" \
            "$image" \
            /src/scripts/build-tracy.sh "$variant" "$distro" /dist
    done
done
ls -l dist
