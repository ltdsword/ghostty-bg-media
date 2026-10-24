# Background media decisions

Accepted decisions and proposals are recorded newest first. Evidence links point to the milestone
docs and logs.

## D-028 Side-by-side application identity

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **User decision:** “Side by side”.
- **Context:** The Linux background-media build must coexist with official Ghostty and use a
  separate application identity for both package formats.
- **Decision:** Name the package and command `ghostty-bg-media`. The `.deb` installs under
  `/opt/ghostty-bg-media`, provides `/usr/bin/ghostty-bg-media`, and uses
  `/usr/share/applications/io.github.ltdsword.GhosttyBgMedia.desktop`,
  `/usr/share/icons/hicolor/*/apps/io.github.ltdsword.GhosttyBgMedia.png`, and
  `/usr/share/doc/ghostty-bg-media/copyright`. Its launcher sets application ID
  `io.github.ltdsword.GhosttyBgMedia` with Ghostty's `--class`; actions starting with `+`, such as
  `+version`, pass through without that option. The Flatpak uses the same ID. The `.deb` shares
  `~/.config/ghostty/config` with normal Ghostty.
- **Consequences:** The package does not replace `/usr/bin/ghostty`, the official desktop file, or system terminfo; its terminfo stays under `/opt/ghostty-bg-media`. The desktop entry has no D-Bus activation or Ctrl+Alt+T shortcut. Official Ghostty may warn about unrecognized `background-media*` keys in the shared config.
- **Evidence:** [INSTALL](INSTALL.md), [STATUS](STATUS.md), [TEST_MATRIX](TEST_MATRIX.md).

## D-027 Linux packaging formats: Ubuntu 26.04 .deb and Flatpak

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **User decisions:** “.deb 26.04 + Flatpak (Recommended)” and “Add it (Recommended)” for Flatpak audio.
- **Context:** The GTK application requires GTK >= 4.18 and libadwaita >= 1.7 at build time
  ([GTK check](../../src/apprt/gtk/gtk_version.zig),
  [libadwaita check](../../src/apprt/gtk/adw_version.zig)). Ubuntu 24.04 provides GTK 4.14,
  libadwaita 1.5, and GLib 2.80, so it cannot build the native package. Flatpak can provide a
  distro-independent GNOME 50 runtime.
- **Decision:** Ship a native `.deb` for Ubuntu 26.04 amd64 and a single-file Flatpak bundle for
  Ubuntu 24.04 and other distributions. Enable the Flatpak PulseAudio socket so web-video audio
  works when `background-media-volume` is above zero.
- **Consequences:** Ubuntu 24.04 users install the Flatpak bundle and its GNOME 50 runtime from
  Flathub. Flatpak YouTube uses `yt-dlp` installed on the host. Flatpak config lives under
  `~/.var/app/io.github.ltdsword.GhosttyBgMedia/config/ghostty/config` and its media access is
  read-only within the home directory. Downloads will be published in M17.
- **Evidence:** [INSTALL](INSTALL.md), [BUILDING](BUILDING.md), [PLATFORM_COMPATIBILITY](PLATFORM_COMPATIBILITY.md), [TEST_MATRIX](TEST_MATRIX.md).

## D-026 Renumber MPEG-TS continuity counters before tsdemux

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **Context:** YouTube H.264 video was smeared or striped from each HLS segment start until the
  next segment. YouTube TS segments end with adaptation-only packets that still set the payload
  flag (`afc=11`, length 183). YouTube counts these in the continuity counter as MPEG-TS requires,
  but GStreamer 1.28.2's packetizer ignores them. tsdemux then sees a continuity mismatch at the
  next segment's first packet and discards that PES, which contains the segment's IDR keyframe.
- **Decision:** Add a pad probe to every `tsdemux` sink pad in the URL player and renumber
  continuity counters to skip the ignored packets. Stop rewriting if packet alignment is lost;
  reset on DISCONT and flush.
- **Consequences:** The offline comparison produced 3732/3732 frames identical to FFmpeg. In
  Ghostty over slow HLS, continuity mismatches fell from 17 to 0, libav “co located POCs
  unavailable” messages fell from 16 to 0, and the picture was clean. Four unit tests cover the
  counter logic. This affected every build with the URL player since M07 and replaces the earlier
  incorrect broadcast-damage and appsink-QoS explanations.
- **Evidence:** [TEST_MATRIX](TEST_MATRIX.md); [`gst_url_player.zig`](../../src/apprt/gtk/gst_url_player.zig).

## D-025 YouTube quality choice and optional HLS audio

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **User decisions:** “Per-video list + saved max” for quality and “Only when volume > 0” for
  audio.
- **Context:** YouTube sources need a user-selectable quality ceiling and should use separately
  listed HLS audio when available without fetching it while muted.
- **Decision:** Add `background-media-youtube-quality`, accepting `auto` or a height from 1 to
  4320, defaulting to `auto` (720p). Choose the largest offered height at or below the preferred
  maximum, or the video's smallest height if none is below it. Formats above 1080p are VP9 only.
  The panel lists Auto (720p) and the current video's available heights; heights above 1080p are
  labelled “(high CPU)”. On Linux GTK, pair listed HLS video and audio formats through a
  one-variant HLS master playlist passed as a `data:` URI. Fetch audio only when volume is above
  zero; raising volume from zero restarts playback with audio, preserving recorded position and
  rejoining live at the live edge. Lowering volume to zero only mutes. Re-run yt-dlp when quality
  changes, and reject format URLs containing `"`, CR, LF, or NUL. If HLS audio is unavailable,
  retain the prior format choice, usually silent.
- **Consequences:** Quality can be changed by config reload or the panel and is saved by **Save to
  Configuration**. macOS ignores the setting. M16 enables the Flatpak PulseAudio socket, so web-video
  audio plays when volume is above zero (D-027). The `.pot` file was not regenerated. A quality
  change during an in-flight resolve keeps the old result, and the quality row hides briefly while
  re-resolving.
- **Evidence:** [CONFIGURATION](CONFIGURATION.md), [FEATURES](FEATURES.md), [TEST_MATRIX](TEST_MATRIX.md),
  [PERFORMANCE](PERFORMANCE.md).

## D-024 Kill the yt-dlp process group; HTTP(S)-only format URLs

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **Context:** Killing only the yt-dlp child on timeout or oversized stdout left descendants able
  to keep stdout open, hang resolution, and survive as orphans. Resolved format URLs also needed
  an explicit scheme check.
- **Decision:** Spawn yt-dlp in its own process group (`pgid = 0`), kill the whole group after the
  30-second timeout or 32 MiB stdout limit, then reap the child. In Flatpak, use
  `flatpak-spawn --host --watch-bus`. Accept resolved format URLs only when they use HTTP or
  HTTPS.
- **Consequences:** Resolver timeouts report `resolve_timeout` at about 30 seconds, and child
  descendants are killed with the group. A yt-dlp process still running when the app exits can
  continue until it ends.
- **Evidence:** workspace `notes/m13/research-r1.md`; [SECURITY](SECURITY.md).

## D-023 Upload URL frames as YUV textures on GTK 4.20+

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **Context:** CPU conversion of URL video from YUV to RGBA was a significant part of 1080p HLS
  CPU use.
- **Decision:** On GTK 4.20 or newer, request I420 from the URL player appsink and create
  `GdkMemoryTextureBuilder` textures in `g8_b8_r8_420`. Use narrow-range CICP and BT.709 for
  heights of at least 720 pixels, otherwise BT.601. Keep RGBA on older GTK or when the color state
  cannot be built.
- **Consequences:** GDK/GPU converts to RGB and Ghostty copies 1.5 bytes per pixel rather than 4.
  Colors were checked against the RGBA path; the layout math has three tests. Local video is
  unchanged.
- **Evidence:** [PERFORMANCE](PERFORMANCE.md); workspace `notes/m12/color-rgba.png`; workspace
  `notes/m12/color-yuv.png`.

## D-022 Add `background-media-blur`

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **Context:** The Linux GTK media layer needed a user-controlled blur effect while keeping
  terminal text sharp.
- **User decision:** M12 D1, “A: Add blur (Recommended)”.
- **Decision:** Add `background-media-blur`, an `f32` pixel radius clamped to `0..40`, defaulting
  to `0` with NaN mapped to `0`. Apply GTK snapshot blur to the media paintable only; apply dim
  afterward. Add the Appearance panel slider and persist its value.
- **Consequences:** Blur affects the media only and uses GPU work; its cost was not benchmarked
  separately. This is Linux GTK behavior; macOS remains unchanged.
- **Evidence:** [PERFORMANCE](PERFORMANCE.md); workspace `notes/m12/blur-0.png`; workspace
  `notes/m12/blur-20.png`.

## D-021 Keep and reuse local video players; loop in Ghostty

- **Status:** ACCEPTED
- **Date:** 2026-10-24
- **Context:** Freeing a `GtkMediaFile` player leaks threads, file descriptors, and memory; GTK's
  built-in loop reopens the file on every pass.
- **Decision:** Keep the last local-video player paused and reuse it by source ID. Loop video in
  Ghostty by seeking to the start when playback ends.
- **Consequences:** Switching to a different local file still leaks inside GTK, and one paused
  player remains in memory until replaced or app exit. No config or API changes; this stays within
  the D-010 `GtkMediaFile` backend.

## D-020 YouTube backgrounds are video-only
- **Superseded by:** D-025 (2026-10-24).

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
- 2026-10-24 retest: live HLS segfault within 12 s; still disabled.
- **Evidence:** workspace `notes/m12/bench-hw.txt`.

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
     breaks. M15 CI was skipped by the user; M16 completed packaging, with publication planned
     for M17 (see [STATUS](STATUS.md)).
- **Consequences:** Partly supersedes D-004 (Flatpak is no longer the dev-run lane; it remains the
  distribution format). Native runtime media deps (GStreamer plugins and `gstreamer1.0-libav`)
  come from apt and need user approval to install. Evidence from M02–M06
  was gathered in the Flatpak lane and stays valid for it; native-lane results must be recorded
  separately. D-028 records the M16 application identity and coexistence decision.
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
  Noble host with the gtk4-layer-shell `--libdir=lib` manifest fix (see BUILDING.md). D-028 records
  the M16 app-ID/coexistence decision against `com.mitchellh.ghostty`.
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
