# tracy_releases

Binary builds of the [Tracy profiler](https://github.com/wolfpld/tracy)
(currently **v0.14.1**, see [`TRACY_VERSION`](TRACY_VERSION)) for Linux
distributions that upstream does not ship packages for.

Two flavours are produced for every distribution:

| Flavour   | CMake option   | Windowing                                       |
|-----------|----------------|-------------------------------------------------|
| `wayland` | default        | Native Wayland backend (libwayland bundled)     |
| `x11`     | `-DLEGACY=ON`  | Legacy GLFW/X11 backend (also works on XWayland)|

| Distribution        | Build container            | Compiler       |
|---------------------|----------------------------|----------------|
| Ubuntu 20.04        | `ubuntu:20.04`             | GCC 13 (ubuntu-toolchain-r PPA) |
| Ubuntu 22.04        | `ubuntu:22.04`             | GCC 13 (ubuntu-toolchain-r PPA) |
| Ubuntu 24.04        | `ubuntu:24.04`             | GCC 13         |
| RHEL 8 (compatible) | `rockylinux/rockylinux:8`  | gcc-toolset-13 |
| RHEL 9 (compatible) | `rockylinux/rockylinux:9`  | gcc-toolset-13 |

The RHEL packages are built on Rocky Linux, which is binary compatible with
RHEL, so they also run on AlmaLinux, Rocky Linux, Oracle Linux, etc.

## Download

Grab the archive for your distribution from the
[Releases](../../releases) page, then:

```bash
tar xzf tracy-0.14.1-ubuntu-24.04-wayland-x86_64.tar.gz
./tracy-0.14.1-ubuntu-24.04-wayland-x86_64/bin/tracy-profiler
```

Each archive contains:

```
bin/    tracy-profiler, tracy-capture, tracy-capture-daemon, tracy-csvexport,
        tracy-import-chrome, tracy-import-fuchsia, tracy-merge, tracy-update
lib/    libwayland-{client,cursor,egl} (wayland flavour only)
share/  desktop entry, MIME type and icons
BUILDINFO, LICENSE
```

The archive is relocatable: it can be extracted anywhere (e.g. `/opt/tracy`).
`SHA256SUMS` in the release lists the checksums of all archives.

### Runtime requirements

All third-party libraries Tracy vendors (capstone, zstd, freetype, libcurl,
pugixml, GLFW, ImGui, …) are linked statically. The remaining dependencies
are standard system libraries:

- both flavours: `libEGL`/`libGL` (libglvnd / mesa), `libdbus-1`, OpenSSL
  (`libssl`, `libcrypto`), `libffi` (wayland), `libxkbcommon` (wayland),
  `libX11` & co. (x11);
- an XDG desktop portal is used for the file dialogs.

On a minimal Ubuntu install for instance:

```bash
sudo apt install libegl1 libgl1 libdbus-1-3 libxkbcommon0 libssl3   # libssl1.1 on 20.04
```

On RHEL:

```bash
sudo dnf install libglvnd-egl libglvnd-glx dbus-libs libxkbcommon openssl-libs
```

## Building locally

Only Docker (or Podman, with `CONTAINER_ENGINE=podman`) is required.

```bash
./build.sh ubuntu-22.04 wayland      # one distribution, one flavour
./build.sh rhel-9                    # both flavours
./build.sh all                       # everything
```

Packages are written to `dist/`. Useful environment variables:

| Variable           | Description                                              |
|--------------------|----------------------------------------------------------|
| `TRACY_VERSION`    | Tracy version to build (default: `TRACY_VERSION` file)   |
| `BASE_IMAGE`       | Override the base image (e.g. a registry mirror)         |
| `JOBS`             | Build parallelism inside the container                   |
| `CONTAINER_ENGINE` | `docker` (default) or `podman`                           |

If the build host sits behind a TLS intercepting proxy, drop its CA
certificate(s) as `*.crt` files into `docker/certs/` (ignored by git) before
building the images.

### Layout

| Path                         | Purpose                                            |
|------------------------------|----------------------------------------------------|
| `docker/ubuntu.Dockerfile`   | Ubuntu build image (GCC 13, CMake 3.31, Meson)     |
| `docker/rhel.Dockerfile`     | RHEL-compatible build image (gcc-toolset-13, …)    |
| `docker/common-tools.sh`     | Installs CMake / Meson / Ninja in the images       |
| `scripts/build-tracy.sh`     | Runs inside the container: clone, build, package   |
| `build.sh`                   | Local entry point (builds image + runs container)  |
| `.github/workflows/release.yml` | CI: build matrix and GitHub release             |

### Build notes

- Tracy 0.14 requires C++20 and CMake ≥ 3.25, so a recent GCC and CMake are
  installed in every build image.
- `-DNO_ISA_EXTENSIONS=ON` is used so the binaries do not depend on the CPU
  of the build machine (no `-march=native`).
- The Wayland backend needs libwayland ≥ 1.22, newer than what Ubuntu
  20.04/22.04 and RHEL 8/9 provide. As in upstream's AppImage, libwayland
  1.25.0 is built from source and bundled in `lib/` (found through an
  `$ORIGIN/../lib` RPATH). The Wayland compositor protocol is backward
  compatible, so this works with the distribution compositors.
- On Ubuntu, `libstdc++`/`libgcc` are linked statically because GCC 13 is
  not the system compiler on 20.04 / 22.04. On RHEL, gcc-toolset already
  links only the newer parts of the C++ runtime statically.
- The X11 flavour disables the Wayland platform of GLFW so it is a pure X11
  application.

## Releasing

The workflow [`release.yml`](.github/workflows/release.yml) builds all 10
packages (5 distributions × 2 flavours), each in its own container.

- Every push / pull request: builds and uploads the packages as workflow
  artifacts.
- Pushing a tag `v<tracy version>` (optionally with a package revision, e.g.
  `v0.14.1-2`) builds and publishes a GitHub release with all archives and
  `SHA256SUMS`:

  ```bash
  git tag v0.14.1
  ```

  ```bash
  git push origin v0.14.1
  ```

- Manual run (*Actions → build-and-release → Run workflow*): optionally pick
  another Tracy version and tick *publish* to create the release `v<version>`.

To move to a new Tracy release, update `TRACY_VERSION` and push a new tag.
