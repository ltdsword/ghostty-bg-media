# Background media build environment

## Host baseline

The host is Ubuntu 24.04.4 with GNOME Wayland, per the supplied host context. Measured host versions are GTK 4.14.5 and libadwaita 1.5.0 (`pkg-config --modversion gtk4 libadwaita-1`; [host-dependencies.txt](evidence/m01/docker/host-dependencies.txt)). The source checks require blueprint-compiler >= 0.20.0 ([blueprint.zig](../../src/apprt/gtk/build/blueprint.zig)) and libadwaita >= 1.7.0 ([gresource.zig](../../src/apprt/gtk/build/gresource.zig)). The host libadwaita is below its source floor. The host blueprint-compiler version was not measured. Zig 0.16.0 is mounted read-only from `~/.local/opt/zig/0.16.0` rather than installed in the image.

## Primary lane: host Flatpak (D-004)

The user manually installed Flatpak and flatpak-builder once on the Ubuntu 24.04.4 host, then added Flathub for the user:

```sh
sudo apt install flatpak flatpak-builder
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

Build from outside the repository, keeping the state and build directories outside it:

```sh
flatpak-builder --user --install-deps-from=flathub --force-clean --state-dir=<state> <builddir> flatpak/com.mitchellh.ghostty.yml
```

Run the built app without installing it:

```sh
flatpak-builder --run <builddir> flatpak/com.mitchellh.ghostty.yml ghostty
```

| Check | Exit | Time | Result |
| --- | ---: | ---: | --- |
| Build 1, unchanged manifest | 1 | 603 s | `translate-c` could not find `gtk4-layer-shell.h`; the module installed under `/app/lib64`, outside the configured pkg-config path. |
| Build 2, with the `--libdir=lib` fix | 0 | 464 s | Ghostty built successfully. |
| `flatpak-builder --run` launch | Not recorded | — | Ghostty launched with OpenGL 4.6 and started a shell on the host through Flatpak HostCommand. |
| Manual smoke | — | — | User confirmed typing, scrolling, selection/copy, and opening a new tab: “all ok”. |

The `gtk4-layer-shell` Meson module defaults to `lib64` on this host, while the Flatpak build's pkg-config lookup did not find its `.pc` file there. The `config-opts` entry `--libdir=lib` installs the library and pkg-config metadata under `/app/lib`, allowing `translate-c` to find the header. The manual smoke showed the expected default gray window; background media is not implemented yet.

Evidence: [manual smoke test](evidence/m01/flatpak-host/smoke-test.txt), [first build failure](evidence/m01/flatpak-host/build-failure.txt), and [launch log](evidence/m01/flatpak-host/launch.txt).

## Container recipe

The Ubuntu 26.04 image installs the GTK build dependencies from apt, including `libgtk4-layer-shell-dev` when available. It does not install Zig. Apt supplied GTK 4.22.4, libadwaita 1.9.1, and blueprint-compiler 0.19.0-2. The Dockerfile installs upstream blueprint-compiler tag `v0.20.0` because apt's version is below the source floor. The final in-image versions were GTK 4.22.4, libadwaita 1.9.1, and blueprint-compiler 0.20.0. The system layer-shell package was present and linked by the GTK build, so `-fno-sys=gtk4-layer-shell` was not used. See [image-build.txt](evidence/m01/docker/image-build.txt).

This Ubuntu 26.04 container is a secondary, dev-only compile lane; the primary Linux build-and-run lane is host Flatpak above.

The Docker Desktop VM context was selected explicitly:

```sh
docker --context desktop-linux pull ubuntu:26.04
docker --context desktop-linux build -t ghostty-bgm-dev:26.04 -f docs/background-media/build-env/ubuntu-26.04.Dockerfile docs/background-media/build-env
```

Build the GTK app as the host UID/GID with the worktree and read-only Zig mounts:

```sh
docker --context desktop-linux run --rm --user "$(id -u):$(id -g)" -v "$PWD":/src -w /src -v "$HOME/.local/opt/zig/0.16.0":/opt/zig:ro -e ZIG_GLOBAL_CACHE_DIR=/src/.zig-cache/global -e HOME=/tmp ghostty-bgm-dev:26.04 /opt/zig/zig build -Dapp-runtime=gtk -Demit-docs=false
```

Run the requested test commands with the same mounts and environment:

```sh
docker --context desktop-linux run --rm --user "$(id -u):$(id -g)" -v "$PWD":/src -w /src -v "$HOME/.local/opt/zig/0.16.0":/opt/zig:ro -e ZIG_GLOBAL_CACHE_DIR=/src/.zig-cache/global -e HOME=/tmp ghostty-bgm-dev:26.04 /opt/zig/zig build -Dapp-runtime=none test
docker --context desktop-linux run --rm --user "$(id -u):$(id -g)" -v "$PWD":/src -w /src -v "$HOME/.local/opt/zig/0.16.0":/opt/zig:ro -e ZIG_GLOBAL_CACHE_DIR=/src/.zig-cache/global -e HOME=/tmp ghostty-bgm-dev:26.04 /opt/zig/zig build -Dapp-runtime=gtk test
```

The Wayland launch command adds the Wayland socket and `/dev/dri` device, with no X11 or privileged mode:

```sh
docker --context desktop-linux run --rm --user "$(id -u):$(id -g)" -v "$PWD":/src -w /src -v "$HOME/.local/opt/zig/0.16.0":/opt/zig:ro -v "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY":/tmp/xdg/$WAYLAND_DISPLAY --device /dev/dri -e XDG_RUNTIME_DIR=/tmp/xdg -e WAYLAND_DISPLAY=$WAYLAND_DISPLAY -e ZIG_GLOBAL_CACHE_DIR=/src/.zig-cache/global -e HOME=/tmp ghostty-bgm-dev:26.04 /src/zig-out/bin/ghostty --config-default-files=false -e sh -c 'echo GHOSTTY_OK; sleep 20'
```

The CLI help was also run without display/device mounts because Docker Desktop could not resolve `/dev/dri`; it confirms `-e <command>` and the generic `--<key>=<value>` configuration syntax. The exact requested help invocation with `/dev/dri` failed before Ghostty started. No launch workaround was attempted. Visual status: **UNVERIFIED**.

## Results

| Command | Environment | Exit | Wall time | Evidence |
| --- | --- | ---: | --- | --- |
| `docker pull ubuntu:26.04` | Docker Desktop `desktop-linux` | 0 | 19.5 s | [image-pull.txt](evidence/m01/docker/image-pull.txt) |
| `docker build -t ghostty-bgm-dev:26.04 ...` initial sandbox attempt | Docker Desktop `desktop-linux` | 1 | <1 s | [image-build.txt](evidence/m01/docker/image-build.txt) |
| Same Docker image build, cold build then version-recording rebuild | Docker Desktop `desktop-linux` | 0 | about 4 min + 6.85 s | [image-build.txt](evidence/m01/docker/image-build.txt) |
| `zig build -Dapp-runtime=gtk -Demit-docs=false`, first attempt | Ubuntu 26.04 container | 1 | about 60 s | [gtk-build.txt](evidence/m01/docker/gtk-build.txt) |
| Same GTK build, retry | Ubuntu 26.04 container | 0 | about 4 min | [gtk-build.txt](evidence/m01/docker/gtk-build.txt) |
| `zig build -Dapp-runtime=none test` | Ubuntu 26.04 container | 1 | about 3 min 34 s | [none-test.txt](evidence/m01/docker/none-test.txt) |
| `zig build -Dapp-runtime=gtk test` | Ubuntu 26.04 container | 1 | about 3 min 48 s | [gtk-test.txt](evidence/m01/docker/gtk-test.txt) |
| `ghostty --help` with Wayland socket and `/dev/dri` | Ubuntu 26.04 container | 127 | about 1.2 s | [ghostty-help.txt](evidence/m01/docker/ghostty-help.txt) |
| Read-only `ghostty --help` without display/device mounts | Ubuntu 26.04 container | 0 | about 1.6 s | [ghostty-help.txt](evidence/m01/docker/ghostty-help.txt) |
| Wayland launch smoke test | Ubuntu 26.04 container, Docker Desktop VM | 127 | about 1.4 s | [wayland-launch.txt](evidence/m01/docker/wayland-launch.txt) |
| `ldd zig-out/bin/ghostty` | Ubuntu 24.04 host | 0 | 0.18 s | [host-ldd.txt](evidence/m01/docker/host-ldd.txt) |

The initial image build command could not write Buildx state under `~/.docker` in the sandbox. The same build completed with approved access; a later cached rebuild added an explicit record of apt's blueprint-compiler version. The first GTK build attempt failed while Zig fetched a lazy dependency with `HttpConnectionClosing`; a retry completed successfully with no output. Both test commands failed while compiling `ghostty-test`: Zig's compiler process received `SIGKILL` (97/100 and 137/140 steps succeeded, respectively). Test execution did not start, so whether GTK tests need a display is unknown.

Both requested container commands that included `--device /dev/dri` failed before starting Ghostty because the Docker Desktop daemon could not find `/dev/dri`. The smoke test emitted neither `GHOSTTY_OK` nor GL/renderer lines, and no window evidence was produced. Its visual result is **UNVERIFIED**. The separate `--help` invocation succeeded without display/device mounts.

Host `ldd` returned exit 0 but reported that `GLIBC_2.43` is not found and `libgtk4-layer-shell.so.0` is missing. Other direct dependencies, including GTK, libadwaita, and Wayland client libraries, resolved. This does not establish a runnable host binary.

## What works, failures, and open risks

- The Ubuntu 26.04 image builds, records installed dependency versions, and includes the required system gtk4-layer-shell development package.
- The unmodified GTK app builds in the container after retrying one transient Zig dependency fetch failure.
- Both test targets stop during test-binary compilation with `SIGKILL`; no unit-test pass result is available in the container. The kill cause is not proven; the likely cause is memory: the Docker Desktop VM reports 3.6 GiB RAM and 14 CPUs (`docker info`, orchestrator, 2026-10-22), and SIGKILL during compilation is the out-of-memory signature. The same `zig build -Dapp-runtime=none -Demit-docs=false test` passed (exit 0) directly on the Ubuntu 24.04 host with Zig 0.16.0 (orchestrator gate run, 2026-10-21). Retry with more VM memory or `-j` limits before treating it as a code failure.
- Docker Desktop's daemon VM cannot resolve `/dev/dri`; the requested Wayland launch did not start. Window rendering and visual checks are **UNVERIFIED**.
- The container-built binary's host linkage check found a GLIBC 2.43 requirement and missing gtk4-layer-shell library. The Ubuntu 24.04 host has libadwaita 1.5.0, below the source build floor of 1.7.0.

For a distributable Noble package, this run establishes that the tested container-built binary does not meet the host's observed runtime requirements: `ldd` reports missing GLIBC 2.43 and gtk4-layer-shell, and the host's libadwaita is below the source floor. Container tests and Wayland rendering remain unverified.
