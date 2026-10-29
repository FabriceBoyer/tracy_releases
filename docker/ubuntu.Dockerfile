# Build environment for Tracy on Ubuntu 20.04 / 22.04 / 24.04.
#
# Tracy 0.14 needs a C++20 compiler (GCC >= 13 is used everywhere for
# consistency) and CMake >= 3.25, which the older releases do not ship.
# GCC 13 comes from the ubuntu-toolchain-r PPA on 20.04 / 22.04; CMake is
# installed from the official Kitware binary tarball.

ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ARG CMAKE_VERSION=3.31.6
ARG GCC_VERSION=13
# Signing key fingerprint of ppa:ubuntu-toolchain-r/test
ARG TOOLCHAIN_PPA_FINGERPRINT=60C317803A41BA51845E371A1E9377A2BA9EF27F

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Optional extra CA certificates (e.g. behind a TLS intercepting proxy).
COPY docker/certs/ /usr/local/share/ca-certificates/

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates curl git file xz-utils pkg-config make patch \
        python3 python3-venv gnupg \
 && update-ca-certificates \
 && if ! apt-cache show "g++-${GCC_VERSION}" >/dev/null 2>&1; then \
        . /etc/os-release \
     && mkdir -p /etc/apt/keyrings \
     && curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${TOOLCHAIN_PPA_FINGERPRINT}" \
        | gpg --dearmor -o /etc/apt/keyrings/ubuntu-toolchain-r.gpg \
     && echo "deb [signed-by=/etc/apt/keyrings/ubuntu-toolchain-r.gpg] https://ppa.launchpadcontent.net/ubuntu-toolchain-r/test/ubuntu ${VERSION_CODENAME} main" \
        > /etc/apt/sources.list.d/ubuntu-toolchain-r.list ; \
    fi \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
        "gcc-${GCC_VERSION}" "g++-${GCC_VERSION}" binutils \
        libegl-dev libgl-dev libxkbcommon-dev libdbus-1-dev libssl-dev \
        libffi-dev libexpat1-dev \
        libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev libxext-dev \
 && update-alternatives --install /usr/bin/gcc gcc "/usr/bin/gcc-${GCC_VERSION}" 100 \
 && update-alternatives --install /usr/bin/g++ g++ "/usr/bin/g++-${GCC_VERSION}" 100 \
 && update-alternatives --install /usr/bin/cc cc "/usr/bin/gcc-${GCC_VERSION}" 100 \
 && update-alternatives --install /usr/bin/c++ c++ "/usr/bin/g++-${GCC_VERSION}" 100 \
 && rm -rf /var/lib/apt/lists/*

COPY docker/common-tools.sh /tmp/common-tools.sh
RUN CMAKE_VERSION=${CMAKE_VERSION} PYTHON=python3 sh /tmp/common-tools.sh && rm /tmp/common-tools.sh

ENV PATH=/opt/tools/bin:/opt/cmake/bin:${PATH} \
    TRACY_STATIC_LIBSTDCXX=1

RUN git config --system --add safe.directory '*'

WORKDIR /work
