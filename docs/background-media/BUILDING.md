# Background media build environment

Contents: [Host baseline](#host-baseline) · [Native lane: Ubuntu 26.04](#native-lane-ubuntu-2604-d-012) · [Flatpak lane](#flatpak-lane-distribution-and-compatibility-d-004-d-012) · [Testing WebP](#testing-webp-installed-flatpak) · [Developer commands](#developer-commands) · [Test baselines](#test-baselines) · [Manual smoke test](#manual-smoke-test-linux-wayland) · [macOS build](#macos-build-unverified) · [Dependencies and guards](#dependencies-and-guards) · [Media fixtures](#media-fixtures) · [CI job design](#ci-job-design-staged-implementation-in-m15) · [Container recipe](#container-recipe) · [Results](#results) · [Open risks](#what-works-failures-and-open-risks)

## Host baseline

The host is Ubuntu 24.04.4 with GNOME Wayland, per the supplied host context. Measured host versions are GTK 4.14.5 and libadwaita 1.5.0 (`pkg-config --modversion gtk4 libadwaita-1`; [host-dependencies.txt](evidence/m01/docker/host-dependencies.txt)). The source checks require blueprint-compiler >= 0.20.0 ([blueprint.zig](../../src/apprt/gtk/build/blueprint.zig)) and libadwaita >= 1.7.0 ([gresource.zig](../../src/apprt/gtk/build/gresource.zig)). The host libadwaita is below its source floor. The host blueprint-compiler version was not measured. Zig 0.16.0 is mounted read-only from `~/.local/opt/zig/0.16.0` rather than installed in the image.

## Native lane: Ubuntu 26.04 (D-012)

**Status: VERIFIED (2026-10-24).** On Ubuntu 26.04.1, measured versions are GTK 4.22.4,
libadwaita 1.9.1, gtk4-layer-shell 1.3.0, GStreamer 1.28.2, and user-local Zig 0.16.0.
Ubuntu's blueprint-compiler is 0.19; D-013 records the user-local upstream v0.20.0 workaround.

User-installed apt packages: `libgtk-4-dev`, `libadwaita-1-dev`, `blueprint-compiler`,
`libgtk4-layer-shell-dev`, `libxml2-utils`, `gstreamer1.0-plugins-bad`, and `gstreamer1.0-libav`.
`libgtk-4-media-gstreamer` is no longer available on Ubuntu 26.04 because `libgtk-4-1` links
GStreamer directly.

Working commands (from the repository root):

```sh
zig build
GHOSTTY_GTK_BUILD_CMD="zig build" scripts/verify-ghostty.sh --quick
```

URL / YouTube fixtures are documented in [test/background-media/README.md](../../test/background-media/README.md).
The fixture server and fake yt-dlp support URL playback checks; set `GHOSTTY_YTDLP` to select a
yt-dlp executable.

## Flatpak lane: distribution and compatibility (D-004, D-012)

Since D-012 this lane is for distribution and for users whose distro is too old for a native build
(e.g. Ubuntu 24.04); it is no longer the day-to-day dev-run lane. Build it before every milestone
merge so it keeps working. The history below is from the 24.04 host, where it was the only lane.

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

## Testing WebP (installed Flatpak)

WebP uses GNOME's sandboxed glycin loader, which needs the app installed under its Flatpak ID.
`flatpak-builder --run` does not provide that installed-app context, so WebP decoding fails.
Build and install a user-scoped test app:

```sh
flatpak-builder --user --install --install-deps-from=flathub --force-clean --state-dir=<state> <builddir> flatpak/com.mitchellh.ghostty.yml
```

Remove the test install with:

```sh
flatpak uninstall --user com.mitchellh.ghostty
```

The test install uses the upstream app ID `com.mitchellh.ghostty` until M16.

## Developer commands

| Purpose | Command | Where | Baseline result and evidence |
| --- | --- | --- | --- |
| Zig toolchain | `~/.local/opt/zig/0.16.0/zig version` | Host | `0.16.0`; required by [`build.zig.zon`](../../build.zig.zon), selected by [D-003](DECISIONS.md#d-003-zig-toolchain), and recorded in `<workspace>/notes/m00/gate-full-baseline.log`. |
| Format changed Zig files | `zig fmt --check <changed .zig files>` | Host | Clean for M02 changed files; `<workspace>/notes/m02/gate-quick.log`. |
| Core build | `zig build -Dapp-runtime=none -Demit-docs=false` | Host | PASS; `<workspace>/notes/m02/gate-quick.log`. |
| Core tests | `zig build -Dapp-runtime=none -Demit-docs=false test` | Host | PASS; `<workspace>/notes/m00/gate-full-baseline.log`. |
| Spike pattern unit tests | `zig test src/apprt/gtk/media_spike_pattern.zig` | Host | PASS, 5/5; [pattern-tests.txt](evidence/m02/pattern-tests.txt). |
| GTK app build | `flatpak-builder --user --install-deps-from=flathub --force-clean --state-dir=<state> <builddir> flatpak/com.mitchellh.ghostty.yml` | Host Flatpak, GNOME SDK 50 | PASS with the documented `gtk4-layer-shell` `--libdir=lib` fix; [build and smoke evidence](evidence/m01/flatpak-host/smoke-test.txt). |
| Launch app | `flatpak-builder --run <builddir> flatpak/com.mitchellh.ghostty.yml ghostty` | Host Flatpak | Launched and started a shell; [launch evidence](evidence/m01/flatpak-host/launch.txt). |
| Launch spike with opacity | `flatpak-builder --run <builddir> flatpak/com.mitchellh.ghostty.yml env GHOSTTY_BGM_SPIKE=1 ghostty --background-opacity=0.5` | Inside the Flatpak sandbox | PASS (user-confirmed, M02). `flatpak-builder --run` does not forward host environment variables, so `env` must be inside the sandbox command; see [launch evidence](evidence/m02/launch-dmabuf.txt) and [first attempt without env](evidence/m02/launch-attempt1-env-not-forwarded.txt). |
| Quality gate | `<workspace>/scripts/verify-ghostty.sh --quick|--full --dir <repo>` | Host | Quick checks worktree and baseline `git diff --check`, macOS isolation, Apple-framework isolation, Zig version, changed-file formatting and core build. Full mode runs core tests instead of the core build. It skips GTK build unless `GHOSTTY_GTK_BUILD_CMD` is supplied. See `<workspace>/scripts/verify-ghostty.sh`, `<workspace>/notes/m02/gate-quick.log`, and `<workspace>/notes/m00/gate-full-baseline.log`. |

On Ubuntu 24.04 Noble, host `zig build -Dapp-runtime=gtk` is expected to fail the source dependency check: host libadwaita is 1.5.0 and the build requires at least 1.7.0. This host command was not run; use the Flatpak lane above ([host versions](evidence/m01/docker/host-dependencies.txt), [source floor](../../src/apprt/gtk/build/gresource.zig)). The host blueprint-compiler version was not measured.

## Test baselines

| Check | Result | Evidence |
| --- | --- | --- |
| `zig fmt --check` on changed files | Clean | `<workspace>/notes/m02/gate-quick.log` |
| Core build | PASS | `<workspace>/notes/m02/gate-quick.log` |
| Core tests on host | PASS | `<workspace>/notes/m00/gate-full-baseline.log` |
| Pattern unit tests | PASS, 5/5 | [pattern-tests.txt](evidence/m02/pattern-tests.txt) |
| GTK tests | UNVERIFIED: container test-binary compilation ended with SIGKILL before tests ran; likely Docker VM memory pressure. The final Flatpak app strips Zig, so tests are not run there. | [GTK test log](evidence/m01/docker/gtk-test.txt); [Flatpak manifest](../../flatpak/com.mitchellh.ghostty.yml) |
| GTK app build | PASS in Flatpak | [build and smoke evidence](evidence/m01/flatpak-host/smoke-test.txt) |
| Launch and basic smoke | PASS per user: typing, scrolling, selection/copy and new tab | [smoke evidence](evidence/m01/flatpak-host/smoke-test.txt) |
| macOS build, tests and runtime | UNVERIFIED; not run on this Linux host | macOS requirements in [HACKING.md](../../HACKING.md); planned CI lane in M15 of `<workspace>/docs/MASTER_PLAN.md` |

## Manual smoke test (Linux, Wayland)

Run the GTK app in the host Flatpak lane and record the date, environment (Ubuntu/GNOME/Wayland, GPU and renderer), and each result in `evidence/`:

1. Launch Ghostty and confirm the window and shell appear.
2. Type `ls`, then scroll back through output.
3. Select text and copy it with Ctrl+Shift+C; paste it into another app or shell.
4. Open a new tab with Ctrl+Shift+T, then create a split with Ctrl+Shift+O.
5. Resize the window and split; check that the terminal remains responsive.
6. Launch with `--background-opacity=0.5` and check the displayed opacity.
7. With `GHOSTTY_BGM_SPIKE` unset, confirm no media process starts and no media tick callback or work runs.

The user smoke records cover launch, typing, scrolling, selection/copy and a new tab ([M01 record](evidence/m01/flatpak-host/smoke-test.txt)), plus splits and `--background-opacity=0.5` with the spike on both presentation paths ([M02 record](evidence/m02/evidence-summary.txt)). Resize and the unset-environment idle check still need a recorded result; spike-off CPU was 0.0-1.0% ([CPU samples](evidence/m02/cpu-measurements.txt)).

## macOS build (UNVERIFIED)

Use Zig 0.16.0 and install Xcode 26 with the macOS 26 SDK and Metal Toolchain. Select Xcode with `sudo xcode-select --switch /Applications/Xcode.app`, then build with `zig build` ([HACKING.md](../../HACKING.md), [`build.zig.zon`](../../build.zig.zon), [D-003](DECISIONS.md#d-003-zig-toolchain)). The macOS app and inherited background video cannot be built or run from this Linux host. No macOS command was executed here. The independent macOS CI lane is planned for M15 in `<workspace>/docs/MASTER_PLAN.md` and is NOT IMPLEMENTED.

## Dependencies and guards

- Linux GTK dependencies are provided by the GNOME 50 Flatpak SDK/runtime ([manifest](../../flatpak/com.mitchellh.ghostty.yml)). Source checks require blueprint-compiler >= 0.20.0 ([check](../../src/apprt/gtk/build/blueprint.zig)) and libadwaita >= 1.7.0 ([check](../../src/apprt/gtk/build/gresource.zig)). HACKING.md's older blueprint-compiler 0.16.0 minimum is superseded by the source check.
- GTK runtime selection is compile-time gated on `app_runtime == .gtk` ([runtime selection](../../src/apprt.zig)); GTK libraries are added only for that runtime ([shared dependencies](../../src/build/SharedDeps.zig)). The architecture contract keeps Linux GTK/media dependencies out of the macOS graph (rule 15 in `<workspace>/docs/MASTER_PLAN.md`).
- Linux local video uses GTK's GStreamer media backend (D-010); it adds no build dependency. The
  GNOME runtime provides GStreamer, with additional codecs from
  `org.freedesktop.Platform.codecs-extra`. `libmpv` is not used. YouTube still needs a resolver in
  M08. M01 task 3 and architecture rule 15 require optional media features not to prevent normal
  startup, including when media is disabled.

## Media fixtures

The 1280x720, 30 fps, 10-second H.264 MP4 fixture was generated in the sandbox with GStreamer's
`gst-launch-1.0`, using `videotestsrc`, `x264enc` and `mp4mux`. The output is the workspace fixture
`notes/m05/fixtures/test-720p30.mp4`; no fixture binary is committed. See workspace
`notes/m05/runtime-gst-probe.txt` and `plans/reports/research-261022-1227-m05-backend-spike.md`.

## CI job design (staged; implementation in M15)

NOT IMPLEMENTED. Keep two independent jobs, as planned in M15 of `<workspace>/docs/MASTER_PLAN.md`:

- **Linux:** Ubuntu 24.04 runner; install Zig 0.16.0 from a checksum-verified tarball; run core build and tests, `zig fmt`, platform-isolation checks, and the Flatpak GTK app build.
- **macOS:** macOS runner with Xcode 26; run core build/tests and build the macOS app, then apply the inherited `background-video*` regression checklist. Record any manual playback gate separately.

Upstream [`test.yml`](../../.github/workflows/test.yml) uses Namespace runners. Jobs include `skip`, `required`, `build-linux`, `build-macos`, `test` and `test-gtk`; runner labels include `namespace-profile-ghostty-xsm`, `namespace-profile-ghostty-md` and `namespace-profile-ghostty-macos-tahoe`. The fork may not have access to those runners, so these jobs need fork-specific runners/workflows.

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
