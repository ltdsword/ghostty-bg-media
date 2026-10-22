# Background media decisions

Accepted decisions and proposals are recorded newest first. Evidence links point to the milestone
docs and logs.

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

- **Status:** ACCEPTED
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
