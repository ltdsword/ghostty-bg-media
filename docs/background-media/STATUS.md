# Background media project status

Milestone states follow the master plan (Agent-Kit workspace `docs/MASTER_PLAN.md`) §7A. PARTIAL means the
evidence below exists but the milestone exit gate is not complete. M02's implementation commit is
recorded below; M00/M01 have no separate milestone commit recorded.

**Environment change (2026-10-24, D-012/D-013):** the native lane is verified on Ubuntu 26.04.1;
Flatpak remains the distribution lane. M07 and later evidence is from the native lane (BUILDING.md).

| Milestone                    | Owner             | State       | Commit               | Evidence                                                                                                                                                                                                                                                                                                                                                                                              | Blockers                                                                           | Next task                                          |
| ---------------------------- | ----------------- | ----------- | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | -------------------------------------------------- |
| M00 — Baselines              | T2 audit          | PARTIAL     | —                    | [BASELINE](BASELINE.md), [macOS baseline](MACOS_BASELINE.md), gate log (Agent-Kit workspace `notes/m00/gate-full-baseline.log`)                                                                                                                                                                                                                                                                       | Linux app launch and macOS build/runtime unverified                                | Complete approved Linux and macOS baseline runs    |
| M01 — Build environment      | T3–T4 environment | DONE        | —                    | [BUILDING](BUILDING.md), [options](BUILD_ENV_OPTIONS.md), [M01 evidence](evidence/m01/), [host Flatpak](evidence/m01/flatpak-host/)                                                                                                                                                                                                                                                                   | —                                                                                  | M02 compositor spike                               |
| M02 — Compositor spike       | m02-spike T1      | DONE        | b2ed4d4              | [ADR](COMPOSITOR_ADR.md), [M02 evidence](evidence/m02/)                                                                                                                                                                                                                                                                                                                                               | —                                                                                  | M03 config contract (needs user approval)          |
| M03 — Domain/config          | M03 config        | DONE        | 0f263d1              | [CONFIGURATION](CONFIGURATION.md), [PLATFORM_COMPATIBILITY](PLATFORM_COMPATIBILITY.md), workspace notes/m03/T1-config-tests.txt, workspace notes/m03/T2-classifier-tests.txt, workspace notes/m03/runtime-log-check.txt, workspace notes/m03/runtime-reload-check.txt, workspace notes/m03/gate-quick.txt                                                                                             | Follow-up gaps below                                                               | M04 static images                                  |
| M04 — Static images          | M04 static images | PARTIAL     | a63e5cf              | workspace notes/m04/runtime-log-check.txt; workspace notes/m04/visual/visual-log.txt; workspace notes/m04/T2-tests.txt; workspace notes/m04/visual/png-contain.png; workspace notes/m04/visual/png-cover.png; workspace notes/m04/visual/jpg-cover-narrow.png; workspace notes/m04/visual/webp-cover.png; workspace notes/m04/visual/png-dim-topleft-none.png; workspace notes/m04/visual/nomedia.png | JPEG/WebP contain and live resize/splits not verified                              | M05 local MP4                                      |
| M05 — Local video            | M05 local video   | PARTIAL     | —                    | workspace notes/m05/runtime-gst-probe.txt; workspace notes/m05/gtk-mediafile-probe.txt; workspace notes/m05/soak-30min.txt; workspace notes/m05/stress-switch.txt                                                                                                                                                                                                                                     | 30-minute soak shows late RSS/CPU growth                                           | M06 GIF                                            |
| M06 — GIF                    | M06 GIF           | PARTIAL     | —                    | workspace notes/m06/EVIDENCE.md; workspace notes/m06/reference-crc.txt; workspace notes/m06/runtime/cadence-r1.txt; workspace notes/m06/runtime/memory-release-r1.txt                                                                                                                                                                                                                                 | Pause/resume, terminal responsiveness, and full RSS release are not verified       | M07 HTTP/HLS                                       |
| M07 — HTTP/HLS               | TBD               | DONE        | —                    | `test/background-media/http_fixture_server.py`; workspace `plans/reports/soak-261024-0715-m07-live.md`                                                                                                                                                                                                                                                                                                | —                                                                                  | M08 real-YouTube smoke                             |
| M08 — YouTube recorded       | TBD               | DONE        | —                    | `test/background-media/fake-yt-dlp`; workspace `notes/m08/real/`; M14 quality and optional audio (D-025)                                                                                                                                                                                                                                                                                              | —                                                                                  | —                                                  |
| M09 — YouTube live           | TBD               | DONE        | —                    | `test/background-media/http_fixture_server.py`; fake yt-dlp scenarios; workspace `notes/m09/real-soak/`; M14 quality and optional audio (D-025)                                                                                                                                                                                                                                                      | —                                                                                  | —                                                  |
| M10 — GTK controls           | TBD               | DONE        | —                    | workspace `notes/m10/runtime/`, `notes/m10/runtime3/`, `notes/m10/classes/`; [PANEL_CHECKLIST](PANEL_CHECKLIST.md)                                                                                                                                                                                                                                                                                    | keystroke-leak check remains manual                                                | M11 lifecycle                                      |
| M11 — Lifecycle              | TBD               | DONE        | —                    | workspace `notes/m11/`; [LIFECYCLE](LIFECYCLE.md)                                                                                                                                                                                                                                                                                                                                                     | Split rendering and multi-monitor checks are manual                                | M12 performance                                    |
| M12 — Effects/performance    | TBD               | DONE        | fde84cb95, 1340f1e74 | [PERFORMANCE](PERFORMANCE.md), workspace `notes/m12/`                                                                                                                                                                                                                                                                                                                                                 | —                                                                                  | M13 security and robustness                        |
| M13 — Security/regression    | TBD               | PARTIAL     | f72a92ffc            | [SECURITY](SECURITY.md), [TEST_MATRIX](TEST_MATRIX.md), workspace `notes/m13/`                                                                                                                                                                                                                                                                                                                        | Native Xorg untested; macOS items deferred                                        | Complete remaining M13 validation                  |
| M14 — Docs/release candidate | TBD               | NOT_STARTED | —                    | —                                                                                                                                                                                                                                                                                                                                                                                                     | —                                                                                  | Prepare package and handoff documentation          |
| M15 — CI lanes               | TBD               | SKIPPED (user) | —                  | User decision, 2026-10-24                                                                                                                                                                                                                                                                                                                                                                             | —                                                                                  | —                                                  |
| M16 — Public packaging       | TBD               | DONE        | f55670384, 4486a52d0 | [INSTALL](INSTALL.md), [D-027](DECISIONS.md#d-027-linux-packaging-formats-ubuntu-2604-deb-and-flatpak), [D-028](DECISIONS.md#d-028-side-by-side-application-identity), [TEST_MATRIX](TEST_MATRIX.md), clean-install evidence below                                                                                                                                                                  | Publish downloads in M17                                                           | Publish packages in M17                            |
| M17 — Public beta            | TBD               | NOT_STARTED | —                    | —                                                                                                                                                                                                                                                                                                                                                                                                     | —                                                                                  | Publish only after release gates pass              |
| M18 — Optional macOS parity  | TBD               | NOT_STARTED | —                    | Approval required                                                                                                                                                                                                                                                                                                                                                                                     | —                                                                                  | Seek approval before considering additive parity   |

## M00 — Fork inheritance and baselines

- **Milestone:** M00 — Fork inheritance, repository audit, dual-platform baselines
- **Status:** PARTIAL
- **Branch / commit:** `feat/linux-background-media` is recorded at baseline `24fa0219908a`; the
  audit task branch was `agent/m00-m01-t2` at that SHA.
- **Changed files:** `docs/background-media/BASELINE.md`,
  `docs/background-media/MACOS_BASELINE.md`.
- **Decisions:** D-001 and D-002 are ACCEPTED; D-005 records the M02 compositor proposal.
- **Build commands + results:** Host `zig build -Dapp-runtime=none -Demit-docs=false test`
  passed in the M00/M01 gate. GTK build was skipped because host libadwaita 1.5 is below the
  source floor 1.7.
- **Automated tests + results:** The same host core test passed; macOS build was not run.
- **Manual visual/functional tests + environment:** Linux app launch and macOS playback were not
  run; both remain UNVERIFIED.
- **Performance / resource measurements:** No media performance measurements.
- **Platform-isolation check:** macOS file inventory and Linux/macOS ownership boundaries are
  documented; the gate's macOS-untouched and no-Apple-framework-in-GTK checks passed.
- **Linux evidence:** [baseline](BASELINE.md),
  gate log (Agent-Kit workspace `notes/m00/gate-full-baseline.log`).
- **macOS CI evidence:** UNVERIFIED; no macOS runner result is recorded.
- **Remaining risks:** No target-host GTK build/launch and no macOS build or runtime validation.
- **Next task:** Complete the approved Linux build/launch lane and establish macOS CI evidence.

## M01 — Developer environment and checks

- **Milestone:** M01 — Developer environment, reproducible build and checks
- **Status:** DONE
- **Branch / commit:** `feat/linux-background-media` at baseline `24fa0219908a`; no M01 commit is
  recorded.
- **Changed files:** `docs/background-media/BUILDING.md`,
  `docs/background-media/BUILD_ENV_OPTIONS.md`, and `docs/background-media/evidence/m01/`.
- **Developer commands:** [developer commands and test baselines](BUILDING.md#developer-commands).
- **Decisions:** D-003, D-004, and D-006 are ACCEPTED. Flatpak is the Linux development-run and
  distribution format; the Ubuntu 26.04 container remains a dev-only compile/test lane.
- **Build commands + results:** Host Flatpak build 1 failed with exit 1 after 603 seconds because
  `gtk4-layer-shell` installed under `/app/lib64` and `translate-c` could not find its header.
  Build 2 with the `--libdir=lib` manifest fix succeeded with exit 0 after 464 seconds.
- **Automated tests + results:** Host `zig build -Dapp-runtime=none -Demit-docs=false test`
  passed. Both container test targets stopped during test-binary compilation with SIGKILL; test
  execution did not start.
- **Manual visual/functional tests + environment:** The Flatpak app launched on Ubuntu 24.04.4
  GNOME Wayland. The user confirmed typing, scrolling, selection/copy, and opening a new tab:
  “all ok”. The window showed the expected default gray background; media is not implemented yet.
- **Performance / resource measurements:** No media performance measurements.
- **Platform-isolation check:** The host gate's macOS-untouched and no-Apple-framework-in-GTK
  checks passed; macOS build evidence is absent.
- **Linux evidence:** [host Flatpak smoke test](evidence/m01/flatpak-host/smoke-test.txt),
  [first build failure](evidence/m01/flatpak-host/build-failure.txt),
  [launch log](evidence/m01/flatpak-host/launch.txt).
- **macOS CI evidence:** UNVERIFIED; a separate CI lane is planned for M15.
- **Remaining risks:** Container test targets remain open after SIGKILL during compilation; test
  execution did not start. macOS build/runtime validation also remains open. Neither blocks M01.
- **Next task:** M02 compositor spike.

## M02 — Compositor feasibility spike

- **Milestone:** M02 — Compositor feasibility spike: frame behind terminal
- **Status:** DONE (exit gate passed)
- **Branch / commit:** M02 implementation at `b2ed4d4`; this documentation task starts from that commit.
- **Changed files:** GTK spike files listed in [COMPOSITOR_ADR.md](COMPOSITOR_ADR.md), the ADR, and `docs/background-media/evidence/m02/`.
- **Decisions:** D-005 and D-007 are ACCEPTED.
- **Build commands + results:** The Flatpak spike build succeeded (binary size 30,251,640 bytes). The quick gate's core build passed; its host GTK build was skipped because host libadwaita 1.5 is below the required 1.7 source floor.
- **Automated tests + results:** `gate-quick.txt` reports PASS (6 checks run), including formatting, core build, and isolation checks. Spike-pattern unit tests: 5/5 passed with Zig 0.16.0 on the host ([pattern-tests.txt](evidence/m02/pattern-tests.txt)).
- **Manual visual/functional tests + environment:** Ubuntu 24.04.4 GNOME Wayland, Flatpak GNOME 50 runtime. User confirmed the animated checkerboard behind readable terminal text through DMA-BUF and forced-CPU paths; typing, scrolling, selection/copy, splits, and new tabs worked.
- **Performance / resource measurements:** Visible idle shell: DMA-BUF 10.0 / 13.6 / 13.8% CPU; forced CPU 30.0 / 23.6 / 14.2%; spike-off baseline 0.0 / 0.8 / 1.0%. Hidden-window DMA-BUF samples were 0.0% x3. Each set is three 5-second `top` samples.
- **Platform-isolation check:** PASS; quick gate reports macOS unchanged since baseline and no Apple frameworks in GTK code.
- **Linux evidence:** [M02 evidence](evidence/m02/), including launch logs, CPU samples, and quick gate.
- **macOS CI evidence:** UNVERIFIED; no macOS build or runtime result is recorded.
- **Remaining risks:** Fractional scale, resize ghosting, custom shaders, background-image precedence, truecolor/per-cell backgrounds, focus visuals, multi-monitor behavior, screenshots, and copies per frame remain UNVERIFIED. Visible redraw is every frame; extra copies were not instrumented.
- **Next task:** M03 config contract (needs user approval).

## M03 — Media domain model, configuration, settings migration

- **Status:** DONE; the config tests, classifier tests, and runtime log check passed.
- **Branch / commit:** M03 implementation at `0f263d1d6b2e992b4d083f5bcd12756ad657bbcc`.
- **Configuration contract:** Eight Linux GTK `background-media*` keys; `background-video*` is
  ignored on Linux and unchanged on macOS. See [CONFIGURATION.md](CONFIGURATION.md) and
  [PLATFORM_COMPATIBILITY.md](PLATFORM_COMPATIBILITY.md).
- **Automated tests + results:** Config tests 84/84 passed (workspace
  `notes/m03/T1-config-tests.txt`); classifier tests 7/7 passed (workspace
  `notes/m03/T2-classifier-tests.txt`).
- **Runtime checks:** Eight source startup cases passed in the Flatpak build (workspace
  `notes/m03/runtime-log-check.txt`). Live configuration reload via `SIGUSR2` with a
  `--config-file` passed (workspace `notes/m03/runtime-reload-check.txt`).
- **Build/gate:** The quick gate passed (6 checks), including the core build; the GTK build was
  skipped because host libadwaita 1.5 is below the 1.7 source floor (workspace
  `notes/m03/gate-quick.txt`). The GTK app itself was built in the Flatpak lane (GNOME 50) and
  used for the runtime checks above.
- **Completion generation:** The eight new keys exceeded the prior 50,000 comptime branch quota.
  Fish, Zsh, Bash completions and Vim syntax generation now use 100,000 in
  `src/extra/{fish,zsh,bash,vim}.zig`. This affects every platform's generation and has no runtime
  effect.
- **Known gaps:** GTK config-errors UI for rejected schemes was not checked; each tab view probes
  and logs independently (shared session planned in M04); local header reads are synchronous on
  the GTK thread (async work planned in M04); macOS build remains UNVERIFIED.
- **Next task:** M04 static images.

## M04 — Static images

- **Status:** PARTIAL.
- **Static image behavior:** Local PNG, JPEG and WebP load in the GTK media view. Fit, position and
  dim apply; decoding runs off the GTK thread and a shared texture serves all tabs. Limits are
  16,384 pixels per side, 64 Mi pixels and 256 MiB per file.
- **Automated tests + results:** T2 reports 13/13 tests passed (workspace notes/m04/T2-tests.txt).
- **Runtime checks:** PNG and JPEG loaded. The installed-app visual run loaded WebP; its earlier
  `flatpak-builder --run` check failed with `decode_failed`, consistent with glycin requiring an
  installed Flatpak. Corrupt, oversized, GIF, and required-missing inputs warned with no media
  drawn; an optional missing path stayed silent (workspace notes/m04/runtime-log-check.txt;
  workspace notes/m04/visual/visual-log.txt).
- **Visual checks:** PNG contain and cover, JPEG cover, WebP cover, and PNG dim/position are
  recorded in workspace notes/m04/visual/visual-log.txt and the matching screenshots listed in the
  M04 row above. The no-media screenshot records the empty-media fallback.
- **Remaining gaps:** JPEG and WebP contain, live resize, and split behavior are not verified, so
  the M04 exit gate is incomplete.
- **Next task:** M05 local video.

## M05 — Local video

- **Status:** PARTIAL.
- **Backend:** D-010 accepts GTK/GStreamer. GTK's GStreamer-backed media file plays local MP4
  (H.264), WebM and MKV using the GNOME runtime and `org.freedesktop.Platform.codecs-extra`.
- **Playback behavior:** One shared player serves all tabs. Loop, volume, background playback and
  the redraw cap are configurable. A zero volume mutes; with background playback disabled, playback
  pauses when no Ghostty window is focused. `max-fps` drops redraw frames and does not speed up
  decoding. Load and playback errors warn and draw nothing.
- **Runtime checks:** The H.264 MP4 probe played and looped without errors, with about 30 content
  invalidations per second (workspace notes/m05/gtk-mediafile-probe.txt). The runtime probe found
  GStreamer 1.26.11, its MP4/WebM/MKV demuxers and video decoders, and the codecs-extra extension
  (workspace notes/m05/runtime-gst-probe.txt). Source switching kept the app alive after 40
  switches with no panic or critical messages (workspace notes/m05/stress-switch.txt).
- **Soak:** The 30-minute loop run ended with zero recorded errors and no crash. RSS rose from
  215,260 KiB at 30 seconds to 225,200 KiB at 30 minutes (about 9.7 MiB); CPU samples rose into
  30–36% late in the run from mostly low-to-mid 20% readings earlier (workspace
  notes/m05/soak-30min.txt). This does not meet the exit gate's no-growth requirement.
- **Audio:** At the time of M05, the Flatpak had no audio permission. M16 later enabled its
  PulseAudio socket; web-video audio was verified on the host (D-027).
- **Remaining gaps:** The soak shows an RSS/CPU growth trend, so M05 remains PARTIAL despite the
  playback and switch checks. The runtime probe confirms available plugins, but only the H.264 MP4
  playback probe is recorded.
- **Next task:** M06 GIF.

## M06 — Animated GIF

- **Status:** PARTIAL; timing, decoder CRC, and repeated source-switch evidence exists, but the full
  exit gate is incomplete.
- **Decision:** D-011 selects the built-in pure-Zig decoder with no new dependency.
- **Automated tests + results:** Decoder frame CRCs match the Pillow references; the evidence index
  records 24/24 tests passing (workspace notes/m06/reference-crc.txt).
- **Runtime checks:** Variable-delay GIFs measured intervals around 40, 100, 500, and 1,000 ms. A
  1080p GIF with 30 ms frame delays measured 33 ms median and 36 ms maximum; `max-fps = 5` measured
  a 200 ms minimum. `loop = false` reached the recorded end state (workspace
  notes/m06/runtime/cadence-r1.txt).
- **Visual check:** The GIF rendered behind terminal text in the focused-window capture (workspace
  notes/m06/visual/gif-pib-false.png).
- **Memory and lifecycle:** The source-switch run completed 135 switches with the app alive and no
  panic. Media-off RSS plateaued at 295,748 KiB after rounds two and three, compared with 141,384
  KiB before the run; this does not demonstrate return to the initial RSS (workspace
  notes/m06/runtime/memory-release-r1.txt).
- **Remaining gaps:** Pause/resume when unfocused was not exercised in-app, and terminal
  responsiveness was not recorded (workspace notes/m06/EVIDENCE.md). Full memory release after a
  source change is also not established by the RSS measurements.
- **Next task:** M07 HTTP/HLS.

## M07 — HTTP/HLS

- **Status:** DONE; the exit gate passed.
- **Decision:** D-014 uses a Linux-only GStreamer URL player; D-015 disables hardware decoding for
  URL playback; D-016 defines reconnect behavior.
- **Automated tests + results:** Fixture server: `test/background-media/http_fixture_server.py`.
- **Runtime checks:** Direct, redirect, HLS VOD, and live paths were exercised. A 60-minute live
  soak had no crash, recovered all 5/5 outages, averaged 21.5%
  CPU, and reached 367 MB RSS before flattening (workspace
  `plans/reports/soak-261024-0715-m07-live.md`). A 404 gave up after 6 attempts; a 25-second
  outage recovered after 5 attempts; unfocus released a live stream. After the soak, an appsink
  floating-reference bug (two GStreamer CRITICALs per connect) was fixed; short live and reconnect
  runs then logged 0 CRITICALs.
- **Remaining gaps:** Reconnecting leaves a blank frame until recovery (M13); CPU use is about 21%
  (watch in M12).
- **Next task:** M08 real-YouTube smoke.

## M08 — YouTube recorded

- **Status:** DONE (exit gate: public video plays on Ubuntu 26.04; tests offline).
- **Decision:** D-017 uses user-installed yt-dlp, with `GHOSTTY_YTDLP` override; Flatpak runs it on
  the host, defaults to 720p, and re-resolves on reconnect. D-020 originally selected video-only
  formats; D-025 adds a quality choice and optional HLS audio when volume is above zero.
- **Automated tests + results:** Fake yt-dlp scenarios behave as expected for HLS 720p, MP4-only
  360p, live, fatal results, flaky recovery, timeout/reconnect, and a missing executable.
- **Runtime checks:** Big Buck Bunny selected video-only format 298 (HTTPS, avc1, 720p), played,
  and advanced; an ended live URL failed once with `unavailable`, without retry, as designed
  (workspace `notes/m08/real/`).
- **Remaining gaps:** yt-dlp is not bundled and must be installed by the user. M16 later enabled
  Flatpak audio through the PulseAudio socket (D-027).
- **Next task:** —

## M09 — Livestreams

- **Status:** DONE.
- **Decision:** D-018 uses a live state machine with upcoming polling and explicit Go Live behavior.
  D-025 adds a quality choice and optional HLS audio when volume is above zero.
- **Automated tests + results:** The `/live-end/<s>/` fixture route and fake yt-dlp scenarios
  `upcomingthen` and `liveended001` were exercised.
- **Runtime checks:** The Lofi Girl live stream played as HLS video-only format 232 (720p); the
  panel showed LIVE and there were 0 GStreamer CRITICALs. The 60-minute real-live soak had no
  crash, was still playing at the end, averaged 29.6% CPU, and RSS was 314 MB at 1 minute, 342 MB
  at 30 minutes, and 344 MB at 60 minutes (flat in the second half; workspace
  `notes/m09/real-soak/`).
- **Remaining gaps:** The two-hour soak found no leak attributed; real-live outage recovery is
  covered only by fixtures.
- **Next task:** —

## M10 — GTK controls

- **Status:** DONE (exit gate: each media type configurable without editing code or restarting).
- **Decision:** D-019 keeps panel edits as runtime overrides until the user explicitly saves them
  to the managed include file.
- **Automated tests + results:** AT-SPI GUI checks covered opening and populating the panel,
  pause/play, dim, and save output (workspace `notes/m10/runtime/`). `zig build test` runs the
  background_media unit tests and panel-override tests; they pass.
- **Runtime checks:** The panel opened from the header-bar video icon in both header layouts and
  from Main Menu; there is no default keybinding. It groups Source, Playback, Appearance, and
  Diagnostics, with Reset Changes and Save to Configuration. A GUI run switched through PNG, GIF,
  local MP4, web MP4, live HLS, YouTube video, and YouTube live without restart; seek appeared only
  for local MP4, web MP4, and YouTube video, with 0 GStreamer CRITICALs. The panel was closed and reopened
  five times while a YouTube URL resolved; playback started and there was no crash. With Keep
  playing in background enabled, the timer advanced while the window was minimized. The user
  verified seek jumps, GStreamer availability and yt-dlp path in Diagnostics, 30/60 fps buttons,
  and Save writing `background-media.ghostty`. Turn Off stopped media for the session while keeping
  the source text; Play reapplied it and the button reads Play. Still images show Showing and GIFs show Playing rather
  than Paused (workspace `notes/m10/runtime/`,
  `notes/m10/runtime3/`, `notes/m10/classes/`).
- **Remaining gaps:** The check that typing in the panel does not send keys to the terminal remains
  manual. There is no default keybinding by choice. The blur slider is deferred to M12. The UI is
  Linux-only; macOS is unaffected.
- **Next task:** M11 lifecycle.

## M11 — Lifecycle

- **Status:** DONE (exit gate: no duplicate subscriptions, no dangling sessions after the last
  window, and no crash on rapid close/reopen).
- **Decision:** D-021 keeps and reuses the last local-video player and loops in Ghostty.
- **Runtime checks:** The live fixture used one HTTP client across one-window/one-tab, three-tab,
  and two-window/three-tab setups. Closing all windows left zero connections and requests after
  8–10 seconds; a new window resumed playback. Forty rapid window cycles and 25 rapid source
  switches completed without a crash or GStreamer criticals. Local-video reuse and looping checks
  passed; the background image remained above media.
- **Remaining gaps:** A different local file still triggers GTK's per-switch leak; one paused
  player remains in memory, and one idle socket may survive release. Split rendering, multi-monitor
  movement and hotplug, and Wayland occlusion were not verified by the agent; they are manual
  checklist items.
- **Platform:** Linux only; macOS deferred by user decision.

## M12 — Effects and performance

- **Status:** DONE.
- **Commits:** `fde84cb95` adds the `background-media-blur` setting and Appearance panel slider;
  `1340f1e74` adds YUV texture upload for URL video.
- **Decisions:** D-022 records the user-approved blur setting; D-023 selects I420 YUV textures on
  GTK 4.20 or newer. URL hardware decoding remains disabled under D-015 after the retest segfault.
- **Performance:** On Ubuntu 26.04.1 with an Intel Core Ultra 5 235U / Arrow Lake-U iGPU, GTK
  4.22.4, GStreamer 1.28.2, ReleaseFast, and play-in-background enabled, the 30-second samples
  after a 12-second warmup changed live HLS 720p from 21.3% to 19.2% CPU, HLS 1080p VOD from
  68.8% to 49.9%, and YouTube 1080p from 66.5% to 54.3%. CPU is percent of one core. Local
  video stayed on the unchanged path. See [PERFORMANCE](PERFORMANCE.md).
- **Pause:** With the panel open, local 1080p changed from 17.5% to 0.2% CPU and HLS 1080p from
  72.6% to 0.3%; paused media does no redraw work.
- **Soak:** The two-hour ReleaseFast soak used five-minute samples. Live HLS 720p measured
  303 → 305 → 305 MB and YouTube live 300 → 318 → 319 MB at start/60/120 minutes. Local 1080p
  measured 194 → 206 MB through minute 70. At minute 75 that window was switched from the panel to
  a second (YouTube esports) livestream; afterward it held both and RSS reached 487 MB by minute
  120. File descriptors and threads were flat at 72 / 57. No crash occurred and no leak was
  attributed. Evidence: workspace `notes/m12/soak.csv`.
- **Remaining cost:** URL playback uses software decoding. Enabling VA decoders measured 60% for
  HLS 1080p and 61% for YouTube, but live HLS segfaulted within 12 seconds. `gtk4paintablesink`
  would add a dependency and was not adopted.

## M13 — Security, robustness, compatibility

- **Status:** PARTIAL; Linux security and robustness evidence is recorded; the full exit gate is
  incomplete.
- **Commit:** `f72a92ffc` runs yt-dlp in its own process group. A 30-second timeout or 32 MiB
  stdout limit kills the group and reaps the child. Flatpak uses
  `flatpak-spawn --host --watch-bus`; resolved format URLs must be HTTP(S).
- **Audit:** yt-dlp uses an argv array without a shell, passes no cookies or credentials, and has
  a 64 KiB stderr cap. Config URLs accept HTTP(S); private-network targets are allowed when
  user-chosen. Redirects to `file://` are rejected by libsoup. Logs redact URLs and suppress
  GStreamer error details containing `://`. Image inputs are limited to 64 Mpixel and 256 MiB;
  GIF canvas arithmetic is overflow-checked. See [SECURITY](SECURITY.md) and workspace
  `notes/m13/research-r1.md`.
- **Fault checks:** The debug-build matrix recorded 18 cases. Every case left the process alive,
  the main loop responsive to a D-Bus action, and zero CRITICAL messages. Corrupt media, missing
  files, HTTP failures, resolver failures, oversized output, hangs, and mid-body disconnects
  produced the recorded failure or retry states in [TEST_MATRIX](TEST_MATRIX.md); evidence is
  workspace `notes/m13/fault-matrix.txt`.
- **Platform and isolation:** X11 through XWayland played local video, live HLS, GIF, and PNG;
  terminal text remained over the media. Native Xorg is untested. With media disabled there are
  zero media threads; Ghostty uses GStreamer through `dlopen`, and the executable's NEEDED list
  has no GStreamer, libsoup, or AV libraries. The path audit against `24fa0219908a` found no
  changes in `macos/`, `BACKGROUND_VIDEO.md`, `src/apprt/embedded.zig`, or the
  `background_video` block in `src/renderer/generic.zig`; `background-video` semantics are
  unchanged.
- **Completed checks:** The user reported all five human terminal regression rows passed on
  2026-10-24. Ghostty's original `zig build test` passed with exit 0 at `d782a3414` after the soak.
- **Remaining gaps:** Native Xorg is untested. All macOS items—build, inherited video smoke, and
  link audit—are deferred by the 2026-10-24 user decision. The remote-HLS `file://` segment
  behavior and a yt-dlp process that outlives app exit remain low-risk open findings.

## M14 extension: YouTube audio and quality

- **What:** `background-media-youtube-quality` accepts `auto` or a preferred height from 1 to
  4320; Auto means 720p. The current video's offered heights appear in the GTK panel, and heights
  above 1080p are marked “(high CPU)”. Listed HLS audio is paired with video only when volume is
  above zero; raising volume from zero restarts with audio, preserving recorded position or
  rejoining live at the live edge. The setting can be changed by reload or panel and saved through
  **Save to Configuration**. See [D-025](DECISIONS.md#d-025-youtube-quality-choice-and-optional-hls-audio).
- **Evidence:** M14 GUI checks covered live playback with audio, no audio stream while muted,
  volume-up restart behavior, and 1440p VP9 selection. GStreamer-only peak RSS / CPU measurements
  covered audio-only, H.264 720p/1080p, and VP9 1440p/2160p. Ghostty ReleaseFast samples covered
  live 720p with audio, recorded 720p muted, and recorded 1440p VP9 with audio. The two-hour soak,
  full `zig build test`, and user manual regression results are recorded in
  [PERFORMANCE](PERFORMANCE.md) and [TEST_MATRIX](TEST_MATRIX.md).
- **Open items:** M16 enabled the Flatpak PulseAudio socket and verified web-video audio (D-027).
  The `.pot` file was not regenerated. A quality change
  during an in-flight resolve keeps the old result, and the quality row hides briefly while
  re-resolving.

## H.264 YouTube keyframe fix (D-026)

GStreamer 1.28.2's MPEG-TS packetizer ignores YouTube adaptation-only packets that still set the
payload flag. The next segment then appears to have a continuity mismatch and tsdemux discards its
IDR keyframe. The URL player now renumbers continuity counters with a pad probe on each tsdemux
sink pad, stopping if packet alignment is lost and resetting on DISCONT/flush. The offline
comparison yielded 3732/3732 frames identical to FFmpeg; slow-HLS continuity mismatches fell
17 → 0, libav “co located POCs unavailable” messages fell 16 → 0, and the picture was clean. Four
unit tests passed. This affected every build with the URL player since M07 and replaces the earlier
incorrect broadcast-damage and appsink-QoS explanations. See [D-026](DECISIONS.md#d-026-renumber-mpeg-ts-continuity-counters-before-tsdemux).

## M16 — Packaging

- **Status:** DONE for package tooling and clean-install evidence. The `.deb` tooling merged as
  `f55670384`; the Flatpak bundle as `4486a52d0`. Public downloads are planned for M17.
- **Evidence:** In a fresh Ubuntu 26.04 container, `.deb` install with recommendations, `+version`,
  dependency resolution, desktop-file validation, coexistence with Ubuntu Ghostty 1.3.0, upgrade,
  remove, purge, reinstall, and downgrade all passed. On the Ubuntu 26.04.1 host, the packaged GUI
  found its resources, played web video, and owned its application D-Bus name. The 17.9 MB Flatpak
  installed beside official Ghostty, played video and audio, owned its own D-Bus name, and
  uninstalled with its exported desktop entry and data. See [INSTALL](INSTALL.md), [D-027](DECISIONS.md#d-027-linux-packaging-formats-ubuntu-2604-deb-and-flatpak), [D-028](DECISIONS.md#d-028-side-by-side-application-identity), and [TEST_MATRIX](TEST_MATRIX.md).
- **Not verified:** Flatpak installation on a real Ubuntu 24.04 system; `sudo apt install` on the
  user's desktop. The container covers package install mechanics.
- **Known:** Flatpak prints a shell-integration warning because the host shell cannot read `/app`
  paths; the terminal works.

## How to resume

- Read the master plan in the Agent-Kit workspace: MASTER_PLAN.md (Agent-Kit workspace `docs/MASTER_PLAN.md`).
- Review the durable audit and status docs in `docs/background-media/`.
- Run the workspace gate script: verify-ghostty.sh (Agent-Kit workspace `scripts/verify-ghostty.sh`).
- Review the host baseline log: gate-full-baseline.log (Agent-Kit workspace `notes/m00/gate-full-baseline.log`).
- Find task reports and run records under `.orchestrator/runs/` in the Agent-Kit workspace.
