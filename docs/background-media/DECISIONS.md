# Background media decisions

Accepted decisions and proposals are recorded newest first. Evidence links point to the M00/M01
audit docs and logs.

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
- **Consequences:** Host setup requires a pending manual Flatpak and flatpak-builder install.
  Flatpak app build/launch remain UNVERIFIED. M16 needs an app-ID/coexistence decision against
  `com.mitchellh.ghostty`.
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

## D-005 M02 compositor approach

- **Status:** PROPOSED
- **Date:** 2026-10-21
- **Context:** Linux media must appear behind terminal content without changing the inherited macOS
  path or risking terminal rendering behavior.
- **Decision:** Compare Option A, a GTK snapshot/widget under the split tree, with Option B, a
  renderer-integrated background pass. The ranked decision table and trade-offs are in
  [BASELINE.md §8](BASELINE.md#8-m02-compositor-options--proposal). Defer selection to M02 proof.
- **Consequences:** No compositor implementation is selected. Begin M02 with the GTK-local option;
  pivot only if the visual proof fails.
- **Evidence:** [BASELINE.md §8](BASELINE.md#8-m02-compositor-options--proposal).

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
