# Build environment for Tracy on RHEL 8 / 9 compatible systems
# (Rocky Linux is used as a freely available, binary compatible base).
#
# GCC 13 comes from gcc-toolset-13 (AppStream). Binaries built with a
# gcc-toolset only depend on the system libstdc++, newer symbols are linked
# statically by the toolset, so they run on a stock RHEL install.

ARG BASE_IMAGE=quay.io/rockylinux/rockylinux:9
FROM ${BASE_IMAGE}

ARG CMAKE_VERSION=3.31.6
ARG GCC_TOOLSET=gcc-toolset-13

# Optional extra CA certificates (e.g. behind a TLS intercepting proxy).
COPY docker/certs/ /etc/pki/ca-trust/source/anchors/

RUN update-ca-trust \
 && dnf install -y dnf-plugins-core \
 && . /etc/os-release \
 && case "${VERSION_ID%%.*}" in \
        8) dnf config-manager --set-enabled powertools; PY_PKG=python3.11 ;; \
        *) dnf config-manager --set-enabled crb; PY_PKG=python3 ;; \
    esac \
 && dnf install -y --allowerasing \
        ${GCC_TOOLSET}-gcc ${GCC_TOOLSET}-gcc-c++ ${GCC_TOOLSET}-binutils \
        ca-certificates curl git file xz tar gzip make patch pkgconf-pkg-config \
        ${PY_PKG} \
        libglvnd-devel mesa-libEGL-devel mesa-libGL-devel \
        libxkbcommon-devel dbus-devel openssl-devel gnutls-devel libffi-devel expat-devel \
        libX11-devel libXrandr-devel libXinerama-devel libXcursor-devel libXi-devel libXext-devel \
 && dnf clean all \
 && ln -sf "$(command -v python3.11 || command -v python3)" /usr/local/bin/build-python

COPY docker/common-tools.sh /tmp/common-tools.sh
RUN CMAKE_VERSION=${CMAKE_VERSION} PYTHON=/usr/local/bin/build-python sh /tmp/common-tools.sh && rm /tmp/common-tools.sh

# Equivalent of "scl enable gcc-toolset-13" for non-interactive shells.
ENV PATH=/opt/rh/${GCC_TOOLSET}/root/usr/bin:/opt/tools/bin:/opt/cmake/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/rh/${GCC_TOOLSET}/root/usr/lib64 \
    PKG_CONFIG_PATH=/opt/rh/${GCC_TOOLSET}/root/usr/lib64/pkgconfig \
    CC=gcc CXX=g++

RUN git config --system --add safe.directory '*'

WORKDIR /work
