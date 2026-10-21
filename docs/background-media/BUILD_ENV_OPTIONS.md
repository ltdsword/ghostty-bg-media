# Build environment options: Flatpak and local GNOME dependencies

Assessment date: 2026-10-22

Repository base: `24fa0219908a3b474eae4766440c3d3662106a3d` (`agent/m00-m01-t4-r2`)

Host context: Ubuntu 24.04.4 GNOME Wayland; GTK 4.14.5 and libadwaita 1.5.0. Flatpak and flatpak-builder are absent on the host. No host packages were installed.

This compares (A) the repository Flatpak manifests and (B) a source-built GTK/libadwaita/Blueprint stack for Noble. App/runtime behaviors are **ASSESSED** from source or documentation unless explicitly marked otherwise. The container build outcomes below are execution evidence; neither built Ghostty to a runnable app.

## A. Repository Flatpak

### Manifest and version fit

Both `flatpak/com.mitchellh.ghostty.yml` and the debug manifest use app runtime `org.gnome.Platform` and build SDK `org.gnome.Sdk`, branch `50`; the app command is `ghostty`. Modules provide Zig 0.16.0 as an archive, gtk4-layer-shell 1.1.0, an inline bzip2 redirect, and pandoc 3.6.3. Ghostty is built with `-Dflatpak=true`; the manifest's local source is `..`. The manifests were not changed.

GNOME 50 release notes and SDK metadata identify GTK 4.22 and libadwaita 1.9 (SDK pins GTK 4.22.5 and libadwaita 1.9.4), above the project's libadwaita 1.7 floor and libadwaita 1.7's GTK 4.17.5 floor. These versions fit on paper. [GNOME 50 developer notes](https://release.gnome.org/50/developers/index.html), [GNOME 50 GTK SDK element](https://github.com/GNOME/gnome-build-meta/blob/gnome-50/elements/sdk/gtk.bst), [GNOME 50 libadwaita SDK element](https://github.com/GNOME/gnome-build-meta/blob/gnome-50/elements/sdk/libadwaita.bst)

### Build attempt

`docker context show` reported `desktop-linux`; Docker Desktop 4.82.0 / Engine 29.6.1 was reachable. `docker pull ubuntu:24.04` exited 0 (image already present). The approved container installed Flatpak and flatpak-builder, added Flathub, copied the source under `.zig-cache/m01-flatpak/source` to preserve the manifest's local `..` path, and resolved/installed GNOME SDK 50, Platform 50, and their GL/codec extensions. It fetched the manifest build sources and reached the first module, `zig`.

The builder then failed with `bwrap: Creating new namespace failed: Operation not permitted` and `Error: module zig: Child process exited with code 1`. The container `docker run` exited 1 after 466 seconds (7m46s). The allowed `seccomp=unconfined` and `apparmor=unconfined` flags did not resolve bubblewrap; no `--privileged` retry was made. Two Git warnings also appeared because the copied worktree `.git` pointer references metadata outside the mounted worktree; those warnings did not stop SDK resolution or source download. No Ghostty build module completed. See [Flatpak attempt](evidence/m01/flatpak/attempt.txt).

A separate disposable-container `flatpak remote-info` query exited 0 and reported current Flathub metadata: GNOME SDK 50 download 838.4 MB / installed 2.3 GB; GNOME Platform 50 download 418.6 MB / installed 1.1 GB. These are advertised ref sizes, not a byte counter for the first attempt. The first command's elapsed time includes apt setup, runtime/SDK resolution and installation, source downloads, and the attempted first module; SDK-only elapsed time was not isolated. A separate fresh-container install of SDK 50 + Platform 50 and related extensions exited 0 in 173 seconds (2m53s); that is the combined ref-install time, not SDK-only. See [runtime size query](evidence/m01/flatpak/runtime-sizes.txt) and [timed ref install](evidence/m01/flatpak/sdk-install.txt).

The intended builder invocation was `flatpak-builder --disable-rofiles-fuse --user --install-deps-from=flathub --force-clean <builddir> com.mitchellh.ghostty.yml`, run from the copied `flatpak/` directory with the build directory in `.zig-cache`. Builder setup and dependency resolution were **VERIFIED**; the app build, install, and launch were not.

### Runtime permissions and terminal integration

Both manifests grant the same permissions:

| Area | Manifest grant |
|---|---|
| Filesystem | `--filesystem=home:ro` |
| GPU/devices | `--device=dri` and broad `--device=all` |
| Windowing | `--share=ipc`, `--socket=wayland`, `--socket=fallback-x11` |
| Host command D-Bus | `--talk-name=org.freedesktop.Flatpak` |

The Flatpak host-command implementation is in [src/os/flatpak.zig](../../src/os/flatpak.zig). [src/termio/Exec.zig](../../src/termio/Exec.zig) routes terminal subprocesses through that API in Flatpak builds; [src/apprt/gtk/class/surface.zig](../../src/apprt/gtk/class/surface.zig) starts Flatpak terminal environments from an empty map before adding selected values. No app-level integration was executed.

| Area | Source assessment | Expected Noble user experience | Evidence |
|---|---|---|---|
| Host shell execution | Manifest grants the Flatpak D-Bus name used by Ghostty's `org.freedesktop.Flatpak.Development` HostCommand interface. Ghostty routes shell execution and cwd checks to that host API. | Shell commands run as the host user outside the app sandbox when the host Flatpak service is available. | ASSESSED |
| SSH (`~/.ssh`, ssh-agent) | HostCommand runs the shell on the host; the app can read home as `home:ro`. The Flatpak terminal environment starts empty and the manifest grants no ssh-agent socket directly. | Host-side SSH files should be visible to the host shell. Agent environment/socket handoff was not verified. | ASSESSED |
| Filesystem | App process gets read-only home access. HostCommand child commands run as the host user; Ghostty checks cwd access through the host. | App can read home configuration but cannot directly write it. Commands in the terminal have normal host-user filesystem access. | ASSESSED |
| Clipboard | Wayland and fallback X11 sockets are granted; there is no separate clipboard permission. | Clipboard access is expected through the windowing connection. Copy/paste and portal behavior were not exercised. | ASSESSED |
| GPU and rendering | DRI, all devices, Wayland, fallback X11, and shared IPC are granted. | Hardware-backed rendering is available where host drivers permit. The broad device grant reduces isolation; rendering was not run. | ASSESSED |
| External media tools | The manifest does not declare `yt-dlp` or libmpv. It does not define a GStreamer plugin/codec set. | Host `yt-dlp` can be used from the host shell if installed. An in-app resolver/player needs packaged tools and runtime/codecs; neither was verified. | ASSESSED |

### Noble install implications and risks

If published as an app ref, Flatpak offers a compile-free install path: install Flatpak, use/add Flathub, then install the app. Users would not need Zig, a source checkout, or the SDK. The Platform ref metadata reports 418.6 MB download / 1.1 GB installed; the build SDK is 838.4 MB / 2.3 GB but is not required for an ordinary app install. The app itself was not built, so app size and clean Noble install/run remain unknown.

M16's install gate requires a clean compile-free Noble install and an explicit packaging identity. The current manifest ID is `com.mitchellh.ghostty` with `default-branch: tip`; a fork still needs a coexistence/identity decision. The manifest exposes read-only home, all devices, and host command execution, so sandbox expectations need to be clear. No final recommendation is made here.

## B. Build local GTK/libadwaita/Blueprint dependencies on Noble

### Dependency chain and Noble versions

libadwaita 1.7.0 requires GLib/GIO >=2.80.0 and GTK >=4.17.5. Its direct dependencies also include FriBidi and AppStream; top-level Meson requires >=0.63.0. [libadwaita 1.7.0 Meson source](https://github.com/GNOME/libadwaita/blob/1.7.0/src/meson.build)

GTK 4.18.0 was selected as a stable release above the GTK 4.17.5 floor. Its Meson source requires GLib >=2.80, Pango >=1.56, Cairo >=1.18.2, HarfBuzz >=8.4.0, FriBidi >=1.0.6, GdkPixbuf >=2.30, Wayland >=1.23 / wayland-protocols >=1.41 when those backends are enabled, Graphene >=1.10, and Epoxy >=1.4. [GTK 4.18.0 Meson source](https://github.com/GNOME/gtk/blob/4.18.0/meson.build)

The Noble container's installed development packages reported GLib 2.80.0, GTK 4.14.5, Pango 1.52.1, Cairo 1.18.0, HarfBuzz 8.3.0, and Graphene 1.10.8. GLib and Graphene meet the listed minima; the installed GTK is below libadwaita's floor, and Pango/Cairo/HarfBuzz are below GTK 4.18.0's minima. GTK setup stopped first at Cairo (`found 1.18.0 but need >=1.18.2`), before later dependency checks. The GTK 4.18.0 source requirements, not the older GTK 4.14.5 requirements, define the attempted stack.

Blueprint 0.20.0's Meson build installs a Python compiler and module. The Ghostty `.blp` inputs import Gtk 4.0 and Adw 1, so compiling the project's UI needs PyGObject and matching Gtk/Adw typelibs. [Blueprint 0.20.0 Meson source](https://github.com/GNOME/blueprint-compiler/blob/v0.20.0/meson.build), [Blueprint packaging documentation](https://gnome.pages.gitlab.gnome.org/blueprint-compiler/packaging.html)

### Build attempt and distribution feasibility

The disposable Ubuntu 24.04 container installed the build prerequisites and cloned GTK 4.18.0, libadwaita 1.7.0, and Blueprint 0.20.0. The GTK Meson setup exited 1 at Cairo 1.18.0 vs >=1.18.2. The libadwaita Meson setup exited 1 at system GTK 4.14.5 vs >=4.17.5. Blueprint 0.20.0 configured, compiled, installed under `/opt/bgm-deps`, and `blueprint-compiler --version` returned `0.20.0`. The container command exited 0 because the script recorded both failed dependency setups and continued to the independent Blueprint build; total command elapsed was 200 seconds (3m20s). See [local dependency attempt](evidence/m01/local-deps/attempt.txt).

The ephemeral prefix contained the Blueprint CLI and Python module (about 1.5 MiB installed). GTK and libadwaita did not build, and no Ghostty binary was produced. The GTK/libadwaita shared objects therefore had no `ldd`/`readelf -d` outputs to inspect; a private-library inventory, RPATH, and package size are unavailable. The compiler CLI is Python-based and does not demonstrate a distributable GTK stack. The compiled Ghostty `.blp` files were not tested against private Gtk/Adw typelibs.

A compile-free Noble `.deb` for this stack would need a maintainer-built package or repository providing GTK >=4.17.5, libadwaita >=1.7, and GTK's dependencies that Noble's versions do not satisfy (at minimum the observed Cairo, Pango, and HarfBuzz gaps). A private stack would need consistent library, typelib, GTK module, and RPATH/search-path handling plus security updates; conflicts with system GTK modules and ABI compatibility would need testing. These are assessed maintenance costs; no package or library was produced to measure them. Asking users to build the dependencies themselves is not a compile-free install. M16 remains unmet by the developer-only `/opt` build.

## Comparison

| Approach | Builds? | Runs on Noble host? | End-user install | Terminal integration | Media tools | Maintenance cost | Evidence level |
|---|---|---|---|---|---|---|---|
| A. Flatpak / GNOME 50 | No app build: blocked at first module by bubblewrap namespace denial. SDK/runtime refs and build sources resolved. | Runtime versions fit the declared floors on paper; app launch not verified. | Compile-free if an app ref is published; Flatpak required. Platform metadata: 418.6 MB download / 1.1 GB installed, plus app. | Host shell through Flatpak HostCommand; home read-only in app; DRI and Wayland/X11 granted. | Host tools can be used from host shell if installed; in-app tools/codecs not verified. | Medium: runtime branch, identity, permissions, and SDK/dependency updates. | Build setup verified; app build/run not verified; runtime permissions assessed. |
| B. Local source dependencies | Partial: Blueprint 0.20 builds; GTK setup and libadwaita setup fail on Noble version gaps. | No full stack/app run. Noble GTK 4.14.5 is below libadwaita's GTK floor. | Compile-free only if maintainers ship the stack or a repository; artifact and size not measured. | Native host shell expected once packaged; no app built/run. | Requires separate tool/backend packaging; not built. | High: private GTK dependency closure, ABI/path isolation, security updates, artifact size. | Meson configure/build executed; no GTK/libadwaita library output or app run. |

## Risks and unresolved questions

- Flatpak app build/install/run, clean Noble installation, actual SSH-agent handoff, clipboard, rendering, and media codec availability remain unverified. Bubblewrap failed without a privileged container; that flag is prohibited by the task.
- The local GTK stack needs newer Cairo, Pango, and HarfBuzz than Noble provides, in addition to GTK/libadwaita; building that dependency closure and measuring a package was outside this attempt's result.
- Open questions: what app ID avoids coexistence conflicts with `com.mitchellh.ghostty`; does HostCommand preserve ssh-agent discovery in practice; can a clean Noble Flatpak install launch; what is the private-stack package size, ABI/RPATH, and update burden once a complete build exists?
