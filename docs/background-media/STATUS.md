# Background media project status

Milestone states follow the master plan (Agent-Kit workspace `docs/MASTER_PLAN.md`) §7A. PARTIAL means the
evidence below exists but the milestone exit gate is not complete. M02's implementation commit is
recorded below; M00/M01 have no separate milestone commit recorded.

| Milestone | Owner | State | Commit | Evidence | Blockers | Next task |
| --- | --- | --- | --- | --- | --- | --- |
| M00 — Baselines | T2 audit | PARTIAL | — | [BASELINE](BASELINE.md), [macOS baseline](MACOS_BASELINE.md), gate log (Agent-Kit workspace `notes/m00/gate-full-baseline.log`) | Linux app launch and macOS build/runtime unverified | Complete approved Linux and macOS baseline runs |
| M01 — Build environment | T3–T4 environment | DONE | — | [BUILDING](BUILDING.md), [options](BUILD_ENV_OPTIONS.md), [M01 evidence](evidence/m01/), [host Flatpak](evidence/m01/flatpak-host/) | — | M02 compositor spike |
| M02 — Compositor spike | m02-spike T1 | DONE | b2ed4d4 | [ADR](COMPOSITOR_ADR.md), [M02 evidence](evidence/m02/) | — | M03 config contract (needs user approval) |
| M03 — Domain/config | M03 config | DONE | 0f263d1 | [CONFIGURATION](CONFIGURATION.md), [PLATFORM_COMPATIBILITY](PLATFORM_COMPATIBILITY.md), workspace notes/m03/T1-config-tests.txt, workspace notes/m03/T2-classifier-tests.txt, workspace notes/m03/runtime-log-check.txt, workspace notes/m03/runtime-reload-check.txt, workspace notes/m03/gate-quick.txt | Follow-up gaps below | M04 static images |
| M04 — Static images | M04 static images | PARTIAL | a63e5cf | workspace notes/m04/runtime-log-check.txt; workspace notes/m04/visual/visual-log.txt; workspace notes/m04/T2-tests.txt; workspace notes/m04/visual/png-contain.png; workspace notes/m04/visual/png-cover.png; workspace notes/m04/visual/jpg-cover-narrow.png; workspace notes/m04/visual/webp-cover.png; workspace notes/m04/visual/png-dim-topleft-none.png; workspace notes/m04/visual/nomedia.png | JPEG/WebP contain and live resize/splits not verified | M05 local MP4 |
| M05 — Local MP4 | TBD | NOT_STARTED | — | — | — | Select and integrate a backend after M02 |
| M06 — GIF | TBD | NOT_STARTED | — | — | — | Implement animation timing and disposal |
| M07 — HTTP/HLS | TBD | NOT_STARTED | — | — | — | Add direct streaming and reconnect behavior |
| M08 — YouTube recorded | TBD | NOT_STARTED | — | — | — | Add Linux-only recorded-video resolution |
| M09 — YouTube live | TBD | NOT_STARTED | — | — | — | Add live state and recovery behavior |
| M10 — GTK controls | TBD | NOT_STARTED | — | — | — | Add GTK controls and keyboard UX |
| M11 — Lifecycle | TBD | NOT_STARTED | — | — | — | Verify tabs, splits, windows, and sessions |
| M12 — Effects/performance | TBD | NOT_STARTED | — | — | — | Measure quality and resource use |
| M13 — Security/regression | TBD | NOT_STARTED | — | — | — | Run robustness and compatibility suite |
| M14 — Docs/release candidate | TBD | NOT_STARTED | — | — | — | Prepare package and handoff documentation |
| M15 — CI lanes | TBD | NOT_STARTED | — | — | — | Establish independent Linux/macOS CI |
| M16 — Public packaging | TBD | NOT_STARTED | — | — | App ID/coexistence decision; install gate | Verify clean Flatpak install, upgrade, and removal |
| M17 — Public beta | TBD | NOT_STARTED | — | — | — | Publish only after release gates pass |
| M18 — Optional macOS parity | TBD | NOT_STARTED | — | Approval required | — | Seek approval before considering additive parity |

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
- **Next task:** M05 local MP4.

## How to resume

- Read the master plan in the Agent-Kit workspace: MASTER_PLAN.md (Agent-Kit workspace `docs/MASTER_PLAN.md`).
- Review the durable audit and status docs in `docs/background-media/`.
- Run the workspace gate script: verify-ghostty.sh (Agent-Kit workspace `scripts/verify-ghostty.sh`).
- Review the host baseline log: gate-full-baseline.log (Agent-Kit workspace `notes/m00/gate-full-baseline.log`).
- Find task reports and run records under `.orchestrator/runs/` in the Agent-Kit workspace.
