#!/bin/sh
# Installs build tools that are either missing or too old in the distro
# repositories: CMake (Kitware binaries) and Meson / Ninja (PyPI, in a venv).
set -eu

: "${CMAKE_VERSION:?}"
: "${PYTHON:=python3}"

arch=$(uname -m)
curl -fsSL "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-${arch}.tar.gz" \
    | tar -xz -C /opt
mv "/opt/cmake-${CMAKE_VERSION}-linux-${arch}" /opt/cmake

# Use the system trust store (it may contain extra CA certificates).
for bundle in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt; do
    if [ -f "$bundle" ]; then export PIP_CERT="$bundle"; break; fi
done

"$PYTHON" -m venv /opt/tools
/opt/tools/bin/pip install --no-cache-dir --upgrade pip
/opt/tools/bin/pip install --no-cache-dir meson ninja
