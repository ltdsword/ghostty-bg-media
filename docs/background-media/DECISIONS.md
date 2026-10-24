# Background media decisions

Accepted decisions and proposals are recorded newest first. Evidence links point to the milestone
docs and logs.

## D-020 YouTube backgrounds are video-only

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **Context:** yt-dlp 2026.10 offers no muxed formats for recorded YouTube videos and lists live
  HLS formats without audio.
- **Decision:** Prefer muxed formats when available; otherwise play video-only, preferring HTTPS
  before HLS. Do not merge separate audio, consistent with the limited format selection in master
  plan M08 task 4.
- **Consequences:** YouTube backgrounds are usually silent; volume has no effect for them.

## D-019 GTK panel changes save through a managed include file

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **Context:** Panel changes apply immediately and need an explicit persistence action.
- **Decision:** Keep edits as runtime overrides until Save writes `background-media.ghostty` and
  adds `config-file = ?background-media.ghostty` to the main config.
- **Consequences:** The managed file contains the eight media keys, loads after the main file, and
  therefore takes precedence; saving reloads config and clears overrides.

## D-018 YouTube livestream state and upcoming polling

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **Context:** Livestreams can be upcoming, reconnecting, playing, ended, or failed.
- **Decision:** Use the live state machine; poll upcoming streams after 30 s, then double the delay
  up to 120 s, with ±20% jitter. Go Live reconnects at the live edge.
- **Consequences:** YouTube end gets one re-check; HLS ends on ENDLIST/EOS; the same config does
  not restart after ending.

## D-017 YouTube resolution uses user-installed yt-dlp

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **Context:** YouTube playback requires resolving a signed media URL, which expires.
- **Decision:** Do not bundle yt-dlp; allow `GHOSTTY_YTDLP`, use `flatpak-spawn --host` in Flatpak,
  default to 720p, and resolve again on every reconnect.
- **Consequences:** Users need host yt-dlp; missing yt-dlp logs `ytdlp_missing` and playback fails.

## D-016 URL reconnect policy

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **Context:** HTTP and HLS streams can fail or stall during playback.
- **Decision:** Retry after `min(1000*2^attempt, 60000)` ms with ±20% jitter; direct URLs stop
  after 6 failures, HLS retries forever, and a 20 s stall watchdog triggers recovery.
- **Consequences:** When unfocused with play-in-background disabled, live streams are released and
  reconnect on resume.

## D-015 Software decoding for URL playback

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **Context:** Intel's iHD VA driver crashed in-process after about 60 s of live HLS.
- **Decision:** After GStreamer initialization, demote VA/VAAPI features to rank 0 for URL playback.
- **Consequences:** Revisit hardware decoding in M12; URL playback uses software decoding meanwhile.

## D-014 Linux URL playback uses a GStreamer player

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **Context:** `GtkMediaFile` reads non-file GFiles through GIO/gvfs, which breaks HLS with
  “Upstream URI query failed”.
- **Decision:** Use a Linux-only dlopen'ed GStreamer URL player with playbin3 and appsink.
- **Consequences:** URL playback uses the custom player; local files continue using GtkMediaFile.

## D-013 User-local blueprint-compiler 0.20 on Ubuntu 26.04

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **Context:** Ubuntu 26.04 ships blueprint-compiler 0.19; Ghostty needs version 0.20 or newer.
- **Decision:** Use the upstream v0.20.0 release installed user-locally at
  `~/.local/bin/blueprint-compiler` on PATH, without sudo.
- **Consequences:** The native build uses the user-local compiler instead of Ubuntu's 0.19 package.

## D-012 Native development on Ubuntu 26.04; Flatpak stays the distribution lane

- **Status:** ACCEPTED (native lane VERIFIED 2026-10-24)
- **Date:** 2026-10-24
- **Context:** The developer host moves from Ubuntu 24.04 to 26.04, which ships GNOME 50
  (expected GTK ~4.22, libadwaita ~1.9: at or above the 1.7 source floor). On 24.04 the app could
  only be built in Flatpak (D-004). The `flatpak-builder --run` lane also stopped mapping windows
  mid-M04 (cause unknown), which forced testing through a user-installed Flatpak.
- User decision (2026-10-24, verbatim): "ok update the document to adapt to this change".
- **Decision:** Two lanes built from the same source, with no lane-specific code:
  1. **Development (primary):** native `zig build` on the Ubuntu 26.04 host against system GTK,
     libadwaita and GStreamer. Used for edit/build/run/debug and the quality gate's GTK build.
  2. **Distribution and compatibility:** Flatpak on the GNOME 50 runtime
     (`flatpak/com.mitchellh.ghostty.yml`). It serves users whose distro is too old for a native
     build (e.g. Ubuntu 24.04), and is built before every milestone merge so it never silently
     breaks. M15 CI builds it on every push; M16 ships it.
- **Consequences:** Partly supersedes D-004 (Flatpak is no longer the dev-run lane; it remains the
  distribution format). Native runtime media deps (GStreamer plugins and `gstreamer1.0-libav`)
  come from apt and need user approval to install. Evidence from M02–M06
  was gathered in the Flatpak lane and stays valid for it; native-lane results must be recorded
  separately. M16 still needs an own app ID so a Flatpak install and a native build can coexist.
- **Evidence:** native versions, build and gate results are recorded in
  [BUILDING.md](BUILDING.md#native-lane-ubuntu-2604-d-012).

## D-011 Animated GIF: built-in decoder

- **Status:** ACCEPTED
- **Date:** 2026-10-22
- **Context:** The M06 spike found that GStreamer preserved GIF timing and pixels but did not
  provide loop control and showed one-frame GIFs as blank; gdk-pixbuf animation is deprecated.
- User decision (2026-10-22, verbatim): GIF loop semantics "A: true = forever, false = GIF's own count (Recommended)".
- **Decision:** Use a built-in pure-Zig decoder for animated GIFs in the Linux GTK media path.
- **Consequences:** No new dependency; deterministic CRC tests; extra decoder code to maintain.
- **Evidence:** workspace notes/m06/decoder-probe-mediafile.txt; workspace
  notes/m06/oneframe-probe.txt; workspace notes/m06/loop-probe.txt; workspace
  notes/m06/reference-crc.txt; workspace
  plans/reports/research-261022-1430-m06-gif-spike.md.

## D-010 Linux media backend: GTK/GStreamer

- **Status:** ACCEPTED
- **Date:** 2026-10-22
- **Context:** The M05 backend spike confirmed local H.264 MP4 playback through GTK's GStreamer
  media backend in the GNOME runtime. The spike compared this with libmpv and recorded playback,
  runtime plugin, and resource evidence.
- User decision (2026-10-22, verbatim): backend "A: GTK/GStreamer, no new deps (Recommended)".
- **Decision:** Use GTK/GStreamer's `GtkMediaFile` backend for Linux local video.
- **Consequences:** This adds no build dependency. GStreamer and codecs come from the GNOME runtime
  and `org.freedesktop.Platform.codecs-extra`; libmpv is not used despite the plan's earlier
  preference. If finer control is needed, escalate in M12 to a custom GStreamer pipeline with
  `gtk4paintablesink`. YouTube still needs a resolver in M08.
- **Evidence:** workspace notes/m05/gtk-mediafile-probe.txt; workspace
  notes/m05/runtime-gst-probe.txt; workspace notes/m05/soak-30min.txt; workspace
  plans/reports/research-261022-1227-m05-backend-spike.md.

## D-009 static image decoding and limits

- **Status:** ACCEPTED
- **Date:** 2026-10-22
- **Context:** M04 adds bounded static-image decoding to the Linux GTK media view.
- **User decisions (2026-10-22, verbatim):** decoder "A: GTK/glycin, no new deps (Recommended)";
  install "A: Yes, user install for testing (Recommended)"; limits "A: 16384 px per side, 64 MP,
  256 MiB file (Recommended)".
- **Decision:** Use GTK image loading with GNOME's sandboxed glycin loader for WebP without new
  dependencies. Limit images to 16,384 pixels per side, 64 Mi pixels, and 256 MiB per file; failed
  or unsupported images warn and draw nothing.
- **Consequences:** Glycin's sandboxed WebP loader needs the app installed for the current user;
  WebP decoding fails under `flatpak-builder --run`. Install a test build with
  `flatpak-builder --user --install` and remove it with
  `flatpak uninstall --user com.mitchellh.ghostty`. This uses the upstream app ID until M16.
- **Evidence:** workspace notes/m04/runtime-log-check.txt; workspace
  notes/m04/visual/visual-log.txt; workspace notes/m04/T2-tests.txt; workspace
  plans/reports/scout-261022-1138-m04-static-images.md.

## D-008 background-media config contract

- **Status:** ACCEPTED
- **Date:** 2026-10-22
- **Context:** M03 adds Linux GTK media configuration while preserving the inherited macOS video
  behavior.
- **User decisions (2026-10-22, verbatim labels):** key set "A: 8 core keys now (Recommended)";
  source type "A: Path or http(s) URL (Recommended)"; old key "A: Ignore it (Recommended)";
  enums "A: Separate media enums (Recommended)".
- **Decision:** Define eight reloadable `background-media*` keys for Linux GTK. Accept local paths
  and HTTP(S) URLs, keep separate fit and position enums, and ignore `background-video*` on Linux.
  macOS continues using its existing `background-video*` settings.
- **Consequences:** YouTube and HLS sources are classified now; playback is deferred to later
  milestones. The eight added keys exceeded the completion and Vim syntax generators' former
  `@setEvalBranchQuota(50000)`; their quota is now `100000` in
  `src/extra/{fish,zsh,bash,vim}.zig`. This affects completion/syntax generation on every platform
  and has no runtime effect.
- **Evidence:** workspace notes/m03/T1-config-tests.txt; workspace
  notes/m03/T2-classifier-tests.txt; workspace notes/m03/runtime-log-check.txt; workspace
  notes/m03/runtime-reload-check.txt; workspace notes/m03/gate-quick.txt.

## D-007 Spike switches are environment variables, not config

- **Status:** ACCEPTED
- **Date:** 2026-10-22
- **Context:** M02 needs test switches to expose the GTK spike and exercise CPU presentation.
- **Decision:** `GHOSTTY_BGM_SPIKE` and `GHOSTTY_BGM_FORCE_CPU` are test-only environment variables;
  exactly `1` enables each switch. They are not public config keys and will be removed or replaced
  by `background-media*` configuration in M03/M04.
- **Consequences:** Keep the switches out of public configuration and remove or replace them as
  media configuration is implemented.
- **Evidence:** [COMPOSITOR_ADR.md](COMPOSITOR_ADR.md), [M02 evidence](evidence/m02/).

## D-005 M02 compositor approach

- **Status:** ACCEPTED
- **Date:** 2026-10-22
- **Context:** Linux media must appear behind terminal content without changing the inherited macOS
  path or risking terminal rendering behavior.
- **Decision:** Option A: a `GtkOverlay` in `tab.blp`, with `GhosttyMediaView` as the base child and
  the existing split tree as the overlay child. The spike keeps the terminal renderer unchanged.
  The ranked options and trade-offs are in [BASELINE.md §8](BASELINE.md#8-m02-compositor-options--proposal).
- **Consequences:** Use GTK composition for Linux media. Pivot to Option B only if later evidence
  shows an Option A defect that cannot be fixed there.
- **Evidence:** [COMPOSITOR_ADR.md](COMPOSITOR_ADR.md), [M02 evidence](evidence/m02/).

## D-004 Linux build/dev environment and distribution

- **Status:** ACCEPTED; dev-run part superseded by D-012 (2026-10-24)
- **Date:** 2026-10-22
- **Context:** Noble's GTK 4.14.5 and libadwaita 1.5 are below the required floors, and the host
  lacks Blueprint compiler. A 26.04-built binary requires GLIBC 2.43 and is not runnable on Noble;
  the source-built GTK chain stops on Noble's Cairo floor. The Flatpak app build and launch remain
  UNVERIFIED because bwrap cannot nest in Docker.
- **Decision:** Flatpak-first. GNOME 50 runtime (GTK 4.22, libadwaita 1.9) is the Linux dev-run and
  distribution format. The Ubuntu 26.04 container remains a dev-only compile/test lane. Docker is
  never required for end users or to run the app. This records user decision D24.
- **Consequences:** Host Flatpak tooling installed by the user; the app builds and launches on the
  Noble host with the gtk4-layer-shell `--libdir=lib` manifest fix (see BUILDING.md). M16 needs an
  app-ID/coexistence decision against `com.mitchellh.ghostty`.
- **Evidence:** [BUILDING.md](BUILDING.md), [BUILD_ENV_OPTIONS.md](BUILD_ENV_OPTIONS.md),
  [Flatpak attempt](evidence/m01/flatpak/attempt.txt),
  [host linkage](evidence/m01/docker/host-ldd.txt).

## D-006 Quality gate

- **Status:** ACCEPTED
- **Date:** 2026-10-21
- **Context:** The workspace needs a repeatable Zig-aware gate while GTK host dependencies remain
  below the source floors.
- **Decision:** Use the workspace-local gate for formatting, core build/tests, and macOS-isolation
  checks. Skip the GTK build until the Flatpak build lane exists.
- **Consequences:** A green gate does not claim GTK or macOS app validation. The recorded host gate
  passed its checks and reported the GTK skip.
- **Evidence:** host gate log (Agent-Kit workspace `notes/m00/gate-full-baseline.log`),
  [BUILDING.md](BUILDING.md).

## D-003 Zig toolchain

- **Status:** ACCEPTED
- **Date:** 2026-10-21
- **Context:** The repository requires Zig 0.16.0 and should not depend on an arbitrary system
  package or a modified shell search path.
- **Decision:** Use the official Zig 0.16.0 tarball in a user-local location, verify its SHA-256,
  and make no PATH change.
- **Consequences:** Build lanes use that pinned compiler; the container mounts the user-local copy
  read-only.
- **Evidence:** [BASELINE.md](BASELINE.md), [BUILDING.md](BUILDING.md).

## D-002 Platform isolation and file ownership

- **Status:** ACCEPTED
- **Date:** 2026-10-21
- **Context:** Master plan §§0B–0C require independently owned macOS and Linux adapters, with macOS
  runtime sources protected and shared code restricted to neutral contracts.
- **Decision:** Keep the inherited macOS adapter and settings intact. Put Linux UI, controller,
  decoder, resolver, and lifecycle in Linux-owned GTK modules. Shared configuration may contain only
  platform-neutral data and validation; Linux dependencies must not enter macOS builds.
- **Consequences:** Protected baseline paths are `BACKGROUND_VIDEO.md`,
  `macos/Sources/App/AppDelegate.swift`,
  `macos/Sources/Features/Terminal/BackgroundVideo.swift`,
  `macos/Sources/Features/Terminal/BackgroundVideoLogin.swift`,
  `macos/Sources/Features/Terminal/BackgroundVideoPanel.swift`,
  `macos/Sources/Features/Terminal/TerminalViewContainer.swift`,
  `macos/Sources/Features/Terminal/Window Styles/TransparentTitlebarTerminalWindow.swift`,
  `macos/Sources/Ghostty/Ghostty.Config.swift`,
  `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`, `src/apprt/embedded.zig`,
  `src/config/Config.zig`, and `src/renderer/generic.zig`. The shared Zig paths allow only additive
  Linux work that preserves inherited macOS behavior.
- **Evidence:** MASTER_PLAN.md §§0B–0C (Agent-Kit workspace `docs/MASTER_PLAN.md`),
  [BASELINE.md §9](BASELINE.md#9-proposed-linux-module-tree-and-ownership-boundary),
  [MACOS_BASELINE.md §9](MACOS_BASELINE.md#9-protected-path-list-for-the-isolation-gate).

## D-001 Protected baseline and branches

- **Status:** ACCEPTED
- **Date:** 2026-10-21
- **Context:** The Linux extension must preserve the contributor's macOS branch and history.
- **Decision:** Protect `mod/background-video` at `24fa0219908a`; develop on
  `feat/linux-background-media`. Preserve and verify the `origin`, `contributor`, and `upstream`
  remotes.
- **Consequences:** Do not implement on or rewrite the protected branch. The feature branch is
  additive to the recorded baseline.
- **Evidence:** [BASELINE.md §1](BASELINE.md#1-repository-baseline),
  MASTER_PLAN.md §0A (Agent-Kit workspace `docs/MASTER_PLAN.md`).
