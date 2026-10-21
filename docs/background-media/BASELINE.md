# Linux Background Media Baseline

Audit target: `24fa0219908a3b474eae4766440c3d3662106a3d`. All source citations below are
repository-root-relative and point to that commit. This is a source and host audit; no application
build, launch, or compositor spike was run. The separate [macOS baseline](./MACOS_BASELINE.md)
owns the macOS implementation deep dive.

## 1. Repository baseline

The task worktree was on `agent/m00-m01-t2` at the baseline commit. The initial
`git status --short --branch` output was `## agent/m00-m01-t2`, with no tracked or untracked
changes.

| Ref | SHA |
| --- | --- |
| `feat/linux-background-media` | `24fa0219908a3b474eae4766440c3d3662106a3d` |
| `mod/background-video` | `24fa0219908a3b474eae4766440c3d3662106a3d` |
| `contributor/mod/background-video` | `24fa0219908a3b474eae4766440c3d3662106a3d` |
| Task branch `agent/m00-m01-t2` | `24fa0219908a3b474eae4766440c3d3662106a3d` |

Remotes from `git remote -v`:

- `contributor` fetch/push: `https://github.com/locphamduc96/ghostty.git`
- `origin` fetch/push: `git@github.com:ltdsword/ghostty-bg-media.git`
- `upstream` fetch/push: `https://github.com/ghostty-org/ghostty.git`

`git merge-base 24fa0219908a upstream/main` returned
`73e4ff10fb2b30d1ab6e6f7f52ef33f3a0593dcc`. `git rev-list --count
24fa0219908a..upstream/main` returned `119`, so this baseline is 119 commits behind
`upstream/main` by that count.

## 2. Diff inventory from the upstream merge base

`git diff --stat 73e4ff10fb2b30d1ab6e6f7f52ef33f3a0593dcc
24fa0219908a3b474eae4766440c3d3662106a3d -- macos/` reported 8 macOS files,
1,422 insertions, and 2 deletions:

- `macos/Sources/App/AppDelegate.swift`
- `macos/Sources/Features/Terminal/BackgroundVideo.swift`
- `macos/Sources/Features/Terminal/BackgroundVideoLogin.swift`
- `macos/Sources/Features/Terminal/BackgroundVideoPanel.swift`
- `macos/Sources/Features/Terminal/TerminalViewContainer.swift`
- `macos/Sources/Features/Terminal/Window Styles/TransparentTitlebarTerminalWindow.swift`
- `macos/Sources/Ghostty/Ghostty.Config.swift`
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`

`git diff --stat 73e4ff10fb2b30d1ab6e6f7f52ef33f3a0593dcc
24fa0219908a3b474eae4766440c3d3662106a3d -- . ':!macos'` reported 4 shared/documentation
files and 204 insertions:

- `BACKGROUND_VIDEO.md`
- `src/apprt/embedded.zig`
- `src/config/Config.zig`
- `src/renderer/generic.zig`

The inherited diff contains no GTK files. Linux work can remain additive under GTK-owned paths;
the macOS changes are summarized in the separate audit linked above.

## 3. Host environment

The following are real outputs from this task host. The `pkg-config` values are in the same order
as the requested package names.

```text
$ uname -a
Linux LAP17124-DatLT12 7.0.0-38-generic #38~24.04.4-Ubuntu SMP PREEMPT_DYNAMIC Mon Sep 14 16:37:11 UTC 2 x86_64 x86_64 x86_64 GNU/Linux

$ lsb_release -a
Distributor ID: Ubuntu
Description: Ubuntu 24.04.4 LTS
Release: 24.04
Codename: noble

$ echo $XDG_SESSION_TYPE
wayland

$ echo $XDG_CURRENT_DESKTOP
ubuntu:GNOME

$ pkg-config --modversion gtk4 libadwaita-1 egl wayland-client
4.14.5
1.5.0
1.5
1.22.0

$ lspci -nnk | grep -A3 -Ei 'vga|3d|display'
00:02.0 VGA compatible controller [0300]: Intel Corporation Arrow Lake-U [Intel Graphics] [8086:7d41]
    Subsystem: Lenovo Device [17aa:233e]
    Kernel driver in use: i915
    Kernel modules: i915, xe
```

Relevant output excerpt from `glxinfo -B`:

```text
$ glxinfo -B
MESA: error: Failed to query drm device.
glx: failed to create dri3 screen
failed to load driver: iris
name of display: :0
direct rendering: Yes
Vendor: Mesa (0xffffffff)
Device: llvmpipe (LLVM 20.1.2, 256 bits) (0xffffffff)
Version: 25.2.8
Accelerated: no
OpenGL core profile version string: 4.5 (Core Profile) Mesa 25.2.8-0ubuntu0.24.04.4

$ nproc
14

$ free -h
               total        used        free      shared  buff/cache   available
Mem:            15Gi        12Gi       550Mi       925Mi       3.3Gi       2.6Gi
Swap:          4.0Gi       173Mi       3.8Gi

$ ~/.local/opt/zig/0.16.0/zig version
0.16.0

$ blueprint-compiler --version
/bin/bash: line 1: blueprint-compiler: command not found
```

The `glxinfo -B` excerpt above was captured inside the worker sandbox, which has no `/dev/dri`
access, so it fell back to software `llvmpipe`. Run outside the sandbox on the same host (orchestrator,
2026-10-21), `glxinfo -B` reports `Device: Mesa Intel(R) Graphics (ARL) (0x7d41)` and
`Accelerated: yes`. Hardware rendering is therefore available on this host; GPU and DMA-BUF
evidence for M02 must be collected outside the worker sandbox.

## 4. Linux build floors

| Dependency | Proven floor at baseline | Host | Evidence |
| --- | --- | --- | --- |
| Zig | `0.16.0` | `0.16.0` | `build.zig.zon:6`; `flake.nix:80` |
| `blueprint-compiler` | `>= 0.20.0` | Absent | Verified refs below; scout dossier D1 |
| `libadwaita-1` | `>= 1.7` | `1.5.0` | Verified source refs below; scout dossier D1 |
| GTK | Effective floor unproven | `4.14.5` | Guards below do not prove a build minimum |

The source floors are `src/apprt/gtk/build/blueprint.zig:36-40,101-108` and
`src/apprt/gtk/build/gresource.zig:28-31`, with libadwaita enforcement at
`src/apprt/gtk/build/blueprint.zig:60-69`.

The local read hook blocked `git show` and `git grep` against `src/apprt/gtk/build/*`. The two
build floors above are taken from the already verified D1 scout dossier, which cites those exact
lines. The host's `blueprint-compiler` command is absent; no compiler version was inferred from
the Ubuntu release.

GTK version guards found by `git grep -n 'atLeast\|runtimeUntil\|runtimeAtLeast'
src/apprt/gtk` include `src/apprt/gtk/class/application.zig:1618` (GTK `>= 4.20`),
`src/apprt/gtk/class/surface.zig:2035` (runtime guard before GTK `4.23.3`) and
`src/apprt/gtk/class/surface.zig:2051` (compile-time GTK `>= 4.22`),
`src/apprt/gtk/class/surface_scrolled_window.zig:69` (runtime guard before `4.20.1`), and
`src/apprt/gtk/winproto/wayland.zig:178` (runtime guard at `4.23.3`). These checks do not prove
an effective GTK floor, so that floor remains unproven. The host's `libadwaita-1` is below the
verified `1.7` floor.

## 5. GTK widget tree and presentation path

`GhosttyTab` contains a `GhosttySplitTree` (`src/apprt/gtk/ui/1.0/tab.blp:3-24`). The split-tree
builder creates a `SurfaceScrolledWindow` for each leaf and a GTK paned widget for each split
(`src/apprt/gtk/class/split_tree.zig:972-1044`). Each surface template has a `terminal_page`
overlay whose child box contains one `GhosttyRenderSurface`; the same template owns input
controllers and foreground UI overlays (`src/apprt/gtk/ui/1.0/surface.blp:15-75,112-150`). When
the core surface is initialized, GTK attaches it to the render widget so the widget can pull
renderer presents (`src/apprt/gtk/class/surface.zig:3526-3538`).

On each GTK snapshot, `RenderSurface.snapshot()` takes the latest queued frame, rebuilds a GDK
texture, applies the required GL Y flip, maps device pixels to CSS size, snaps the origin, then
appends the texture (`src/apprt/gtk/class/render_surface.zig:149-205`). For DMA-BUF frames,
the import builder receives format, modifier, planes, and premultiplication metadata; GTK owns
the FDs until its asynchronous texture build completes
(`src/apprt/gtk/class/render_surface.zig:314-375`). The CPU
path constructs `GdkMemoryTexture` with `r8g8b8a8_premultiplied` pixels and transfers buffer
ownership through `GBytes` (`src/apprt/gtk/class/render_surface.zig:378-428`).

The OpenGL renderer exports DMA-BUF only while presentation health is `.healthy`; failed export
falls back to `readPixelsAlloc()` CPU memory (`src/renderer/OpenGL.zig:273-310`). If GTK cannot
import a DMA-BUF, `RenderSurface` reports `.unhealthy` to request CPU presentation
(`src/apprt/gtk/class/render_surface.zig:156-169`). No user-facing or test-only switch to force
this fallback was found in the audited paths; health feedback follows actual failure.

The current GTK texture path maps one texel to one device pixel and flips the OpenGL Y direction
before snapshot append (`src/apprt/gtk/class/render_surface.zig:182-204`). A GTK-owned background
widget can use the existing snapshot scale and geometry, but it must still be checked at fractional
scales and on resize. Splits are separate surface leaves beneath the tab split tree, so the layer
owner must be
chosen deliberately if a single continuous image should span split panes.

## 6. Background and alpha paths

- `background-opacity` defaults to `1.0`; it is clamped to `[0, 1]` and becomes the alpha byte
  of the renderer's main background color (`src/config/Config.zig:1050-1059`,
  `src/renderer/generic.zig:1668-1674`). The render target clears to transparent black
  (`src/renderer/generic.zig:1910-1917`).
- `background-opacity-cells` defaults to `false` and only applies configured opacity to explicit
  cell backgrounds when enabled (`src/config/Config.zig:1061-1075`,
  `src/renderer/generic.zig:3193-3229`). Selected and
  inverse cells stay opaque; explicit cell backgrounds otherwise stay opaque; cells with no
  explicit background let the already-drawn terminal background through
  (`src/renderer/generic.zig:3201-3228`).
- The GTK window adds its solid `background` CSS class only when `background-opacity >= 1`
  (`src/apprt/gtk/class/window.zig:713-720`). The current tab/surface tree has no media widget
  behind `RenderSurface`. Thus, with alpha-bearing terminal pixels and no such media widget,
  transparent terminal areas reveal the desktop through the GTK window, not an internal media layer.
- `background-video` is documented as macOS-only. The renderer sets its main background alpha to
  zero for this key only inside a compile-time macOS branch; it has no equivalent Linux runtime
  behavior (`src/config/Config.zig:708-723`, `src/renderer/generic.zig:1687-1692`).
- The renderer clears, then draws either the background-image pipeline (which also draws the main
  background color) or the plain background-color pipeline. Kitty images below cell backgrounds
  follow, then cell backgrounds, text, foreground images, and debug overlay
  (`src/renderer/generic.zig:1919-2008`). The background-image shader combines its sampled image
  with the background color, then applies the resulting alpha
  (`src/renderer/shaders/glsl/bg_image.f.glsl:33-62`). A new media layer must define precedence
  with both existing pipelines rather than silently dropping either one.
- Custom shaders run after the background, cells, text, and image layers, using post-process
  textures and transparent clears (`src/renderer/generic.zig:2010-2038`). Their output alpha and
  visual result over a GTK media widget need explicit validation.

## 7. Configuration and reload

The keys below are defined in `src/config/Config.zig`; documentation and defaults are at the cited
lines.

| Key | Type and default | Documentation / definition |
| --- | --- | --- |
| `background-image` | `?Path = null` | `src/config/Config.zig:611-626` |
| `background-image-opacity` | `f32 = 1.0` | `src/config/Config.zig:628-647` |
| `background-image-position` | `BackgroundImagePosition = .center` | `src/config/Config.zig:649-665` |
| `background-image-fit` | `BackgroundImageFit = .contain` | `src/config/Config.zig:667-695` |
| `background-image-repeat` | `bool = false` | `src/config/Config.zig:697-706` |
| `background-video` | `?[:0]const u8 = null` | `src/config/Config.zig:708-723` |
| `background-video-play-in-background` | `bool = false` | `src/config/Config.zig:725-731` |
| `background-video-max-fps` | `u32 = 60` | `src/config/Config.zig:733-740` |
| `background-video-opacity` | `f64 = 0.3` | `src/config/Config.zig:742-744` |
| `background-video-blur` | `f64 = 2` | `src/config/Config.zig:746-751` |
| `background-video-volume` | `f64 = 0` | `src/config/Config.zig:753-754` |

The only Zig runtime consumer found for `background-video` is the derived renderer config and its
macOS-only alpha behavior (`src/renderer/generic.zig:596,658,1687-1692`). The image settings are
copied into `DerivedConfig` and used by the renderer to load PNG/JPEG data, upload it, update its
fit/position/repeat buffer, and react to configuration changes
(`src/renderer/generic.zig:609-613,633-689,2067-2165,2199-2224,2304-2335`). No other Zig
consumers of these keys were found by the source search.

Configuration reload calls `CoreApp.updateConfig` or `CoreSurface.updateConfig`; the resulting
`config_change` action is dispatched to GTK, which wraps the core config and calls the app or
surface `setConfig` (`src/apprt/gtk/class/application.zig:2782-2822,695-705,2216-2230`;
`src/apprt/gtk/class/surface.zig:2153-2159`). The renderer's `changeConfig` replaces
its derived config, prepares a changed image, refreshes image geometry when needed, and marks the
renderer dirty (`src/renderer/generic.zig:2168-2243`).

Config tests are general parsing, cloning, conditional-state, theme, and C API getter tests
co-located under `src/config/Config.zig:4214,10614-11430` and `src/config/CApi.zig:149-247`.
The source search found no test specifically covering `background-image*` or
`background-video*`.

## 8. M02 compositor options — proposal

The comparison follows the ranked criteria in master plan §3.2. Scores are qualitative
expectations from source inspection, not measurements. Both options still need the M02 checkerboard,
alpha patterns, real terminal text, selection/cursor, scale, focus, split/tab, and fallback proof.

### Option A — GTK snapshot/widget under the split tree

**Hook and data flow.** At `src/apprt/gtk/ui/1.0/tab.blp:21-24`, wrap the existing
`GhosttySplitTree` in a `GtkOverlay`: make a `GhosttyBackgroundMediaView` the base child and the
existing split tree an overlay child. This gives one media view the whole tab rectangle, including
all split panes. `Tab` already owns the config and split-tree properties
(`src/apprt/gtk/class/tab.zig:35-103`); it can attach a shared media session to the view. A decoder
or procedural source publishes only the newest frame through a bounded queue. The GTK main thread
owns widgets and `GdkTexture` creation, then queues a redraw; decoding and URL work stay off the
GTK thread. Make the background view non-targetable so keyboard and pointer events continue to
reach terminal surfaces.

**Alpha and presentation.** For the existing renderer output to reveal the internal media child,
the terminal's main background must have alpha, ordinarily by setting `background-opacity < 1`.
The window's solid CSS class is then absent. Explicit cell backgrounds remain opaque by default;
`background-opacity-cells=true` applies the configured alpha to them except selected and inverse
cells. The existing terminal presentation keeps its current DMA-BUF and CPU-memory paths; media
frames use their own GDK texture path. Importable GPU frames may avoid a CPU copy; a CPU decoder
frame needs at least one upload/copy into a GDK texture. Terminal CPU fallback still performs its
existing readback.

**Splits, tabs, scale, and cost.** A view per tab spans the full split tree, while tabs may hold
references to one shared session so they do not start duplicate decoders. Device-pixel sizing,
fractional scale, resize, crop/fit policy, and visibility need testing. Expected extra CPU copies
are zero for a directly importable frame or at least one for a CPU frame. GTK composites the media
and terminal snapshots. No terminal renderer or macOS code needs to change.

**Smallest PoC files.** Add a procedural checkerboard/timestamp `BackgroundMediaView` in
`src/apprt/gtk/class/background_media_view.zig`; export/register it in `src/apprt/gtk/class.zig`;
attach and drive it from `src/apprt/gtk/class/tab.zig`; and add the overlay to
`src/apprt/gtk/ui/1.0/tab.blp`. Use a GTK tick callback for the animated procedural frame and a
config setting below 1 for the alpha proof. Add a temporary test-only way to mark renderer
presentation unhealthy if forced CPU fallback must be exercised; no such switch exists today.

### Option B — renderer-integrated background pass

**Hook and data flow.** Add a media-frame input and a draw step before the current background
pipeline (`src/renderer/generic.zig:1910-1946`). Existing image, cell, text, and shader passes stay
above the media layer. A decoder thread publishes immutable newest-frame
data through a bounded queue; the render thread consumes it and owns graphics uploads/resources.
Use explicit synchronization and frame lifetimes; do not call GTK from the render thread. The
renderer already protects drawing/config work with its draw mutex
(`src/renderer/generic.zig:1720-1728`).

**Alpha and presentation.** The new pass supplies the base image, then existing background color
alpha blends over it; `background-opacity < 1` is still needed to show media through the default
terminal background. Keep cell alpha semantics and post-process shader ordering. The composed frame
continues through the existing exporter: healthy DMA-BUF export/import stays the fast path, while
failed import/export produces the composed CPU readback texture. If a decoder supplies a DMA-BUF,
the renderer must import/synchronize it or copy/upload it into an owned texture. CPU decoded frames
need at least one GPU upload per new frame; terminal CPU fallback adds its existing final readback.

**Splits, tabs, scale, and cost.** Each terminal renderer has its own render target. Sharing one
media session is possible, but a pane-local pass naturally repeats/scales the whole background per
surface unless window-relative crop coordinates are added. Tabs and split visibility must gate frame
consumption/redraws. This option adds renderer texture ownership and synchronization; any change in
`generic.zig` must be guarded at compile time so macOS code generation and behavior remain
unchanged.

**Smallest PoC files.** Add a Linux-only procedural frame producer under
`src/apprt/gtk/background_media/`, a compile-time Linux renderer input and pre-background pass in
`src/renderer/generic.zig`, and the smallest renderer pipeline/shader registration under
`src/renderer/`. Drive a timestamped checkerboard with an explicit frame lifetime; add a temporary
test-only force-unhealthy path to exercise CPU output. No decoder library is needed for this proof.

### Ranked criteria decision table

| Rank / criterion (§3.2) | Option A: GTK | Option B: renderer |
| --- | --- | --- |
| 1. Correct visible result | Good; alpha needs proof | Strong order; custom alpha needs proof |
| 2. No terminal regression | High; renderer unchanged | Medium; shared render pipeline changes |
| 3. DMA-BUF and CPU fallback | High; terminal paths independent | Medium; media import adds work |
| 4. Maintainability/upstream fit | High; GTK-local | Medium; shared renderer extension |
| 5. Testability | High; generated textures | Medium; needs a render test seam |
| 6. GPU/memory footprint | Medium; one GTK view per tab | Medium; per-surface resources |
| 7. GTK/Wayland behavior | High; native snapshots | Medium; frames cross renderer ownership |
| 8. Implementation cost | Lower for first proof | Higher; API, uploads, synchronization |

**Recommendation (proposal):** start with Option A at the tab split-tree boundary. It keeps the
existing renderer, GTK's terminal frame import/fallback, and the macOS tree untouched. If the real
terminal texture cannot preserve the required alpha through GTK snapshots, stop and pivot to Option
B before integrating a decoder. This is a proposal only; no spike code or visual result exists.

## 9. Proposed Linux module tree and ownership boundary

```text
src/config/Config.zig                     # neutral media settings and validation only
src/apprt/gtk/
  background_media/
    controller.zig                        # source policy and session lifecycle
    session.zig                            # shared newest-frame queue and subscribers
    backend.zig                            # decoder/resolver interface; Linux dependencies
    presentation.zig                      # decoded frame to GTK-owned texture
  class/
    background_media_view.zig             # GTK widget; own snapshot/size/visibility hooks
    tab.zig                                # attach shared session to the tab view
  ui/1.0/tab.blp                           # media base child below GhosttySplitTree
macos/**                                   # existing Swift/AppKit implementation; protected
src/renderer/generic.zig                   # only if Option B wins; compile-time Linux branch
```

The GTK adapter owns its controller, source resolution, player and widget lifecycle under
`src/apprt/gtk/**`. `src/config/Config.zig` may hold only platform-neutral values, parsing and
validation; it must not import GTK, AppKit, decoder libraries, or renderer handles. Existing
macOS UI/player/settings stay under `macos/**` and retain their behavior. Linux-only code must not
be imported by the macOS build or by non-Linux GTK builds (GTK also serves FreeBSD in this repo).

For Option A, select the adapter once at the GTK tab composition boundary: conditionally export or
construct the media view in the GTK class registry/tab code only when `builtin.os.tag == .linux`.
The current GTK class registry exports widget classes from `src/apprt/gtk/class.zig:10-15`, and
the tab's current integration point is `src/apprt/gtk/ui/1.0/tab.blp:21-24`. Do not scatter
platform checks through playback logic. The independent macOS app remains selected by its existing
native build path. Option B additionally requires every renderer extension to be compile-time
Linux-only, with no Linux media dependency in the macOS graph.

## 10. Known risks

- The host GPU (Intel Arrow Lake, Mesa, accelerated) is not visible inside the worker sandbox, so
  GPU synchronization, hardware DMA-BUF import, and performance must be measured outside it; all
  remain unverified.
- The host's `libadwaita-1` is `1.5.0`, below the verified `1.7` floor; `blueprint-compiler` is
  absent. No build was run, and this environment cannot establish a clean GTK build baseline.
- The effective GTK floor is unproven. Host GTK is `4.14.5`; version guards show feature gates but
  do not establish a required minimum.
- No force-CPU-presentation control was found. M02 must add a temporary test hook or induce an
  import failure to prove the CPU path, then remove any test-only control if it is not part of the
  final design.
- GTK composition depends on terminal alpha, explicit cell backgrounds, custom shader alpha, and
  the `background-opacity` CSS behavior lining up. The required Wayland visual proof has not run.
- Session sharing, tabs/splits, fractional scaling, crop/fit, decoder frame ownership, and copy
  counts are design questions for the spike; the renderer currently owns a distinct target per
  terminal surface.
- `background-image` and media precedence is undefined. Renderer integration must preserve the
  current image/color and custom shader ordering.
- Backend selection, dependency licensing, remote stream behavior, and resource limits remain
  future implementation decisions. The current audit did not install or select a decoder.
- No build, launch, visual test, or macOS validation was run under this read-only audit task.
