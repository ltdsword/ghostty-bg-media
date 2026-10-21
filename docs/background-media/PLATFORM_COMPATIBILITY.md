# Platform compatibility

This matrix distinguishes source-inherited macOS behavior from verified runtime support. Every
macOS runtime item remains UNVERIFIED until a macOS build and smoke test are recorded.

## Support matrix

| Capability | macOS | Linux / Ubuntu 24.04 | Status |
| --- | --- | --- | --- |
| Original video background | Inherited implementation | Not required | macOS inherited; runtime UNVERIFIED; Linux NOT_STARTED |
| Static background image | Inherited image path | Existing image path; media extension not started | macOS inherited; runtime UNVERIFIED; Linux NOT_STARTED |
| Animated GIF | No added parity commitment | Planned | macOS runtime UNVERIFIED; Linux NOT_STARTED |
| Local MP4 | Inherited AVFoundation path | Planned independent backend | macOS inherited; runtime UNVERIFIED; Linux NOT_STARTED |
| YouTube recorded/live | Inherited resolver/settings | Planned Linux-only resolver/player | macOS inherited; runtime UNVERIFIED; Linux NOT_STARTED |
| Settings UI | Existing Swift/AppKit panel | Planned GTK4 UI | macOS inherited; runtime UNVERIFIED; Linux NOT_STARTED |
| Media dependencies | Existing native stack | Linux-only backend dependencies | macOS inherited; runtime UNVERIFIED; Linux NOT_STARTED |
| Build and test | Separate macOS lane | Separate Linux lane | macOS UNVERIFIED; Linux baseline partial |

Source-level macOS capability notes, including image-format gaps and the protected implementation,
are in [MACOS_BASELINE.md](MACOS_BASELINE.md). The table does not claim feature parity beyond the
inherited paths.

## Configuration precedence

### macOS

- Preserve the existing `background-video*` keys, defaults, player, and UI behavior.
- The panel's `background-video.conf` loads after selected/default config, CLI arguments where
  applicable, and recursive config files. It therefore has last precedence for its six video keys.
- Keep the existing `background-image*` behavior. The audit does not define a new conflict rule
  for simultaneous image and video sources; do not infer one.
- macOS runtime behavior is UNVERIFIED. See [MACOS_BASELINE.md §4](MACOS_BASELINE.md#4-settings-and-persistence).

### Linux

The master plan §3.5 policy is PROPOSED for M03, not implemented: use explicit `background-media`,
otherwise a documented compatibility interpretation of `background-video` if reasonable,
otherwise `background-image`, then the theme background. Existing Linux image/color composition
must remain intact. See MASTER_PLAN.md §3.5 (Agent-Kit workspace `docs/MASTER_PLAN.md#35-configuration-design`)
and [BASELINE.md §§6–7](BASELINE.md#7-configuration-and-reload).

## Recognized but unsupported keys

Behavior is TBD in M03. A recognized key unsupported on the current platform must produce a clear
diagnostic or a documented intentional no-op. It must never select a backend that is absent on that
platform.

## Ownership and dependency isolation

| Area | Owner and boundary |
| --- | --- |
| macOS legacy | Protected `macos/**` implementation, existing Swift UI/player/settings, and inherited behavior |
| Linux implementation | Linux-only GTK controller, view, resolver, decoder, and lifecycle under `src/apprt/gtk/**`; select at the platform composition boundary |
| Shared core | Neutral configuration values, parsing, validation, and defaults only; no GUI, decoder, renderer handle, or platform runtime dependency |
| Distribution | Fork-specific packaging and independent build/validation workflows |

GTK also serves FreeBSD in this repository; Linux media modules and dependencies must be selected
only for Linux. The full protected-path inventory is in
[MACOS_BASELINE.md §9](MACOS_BASELINE.md#9-protected-path-list-for-the-isolation-gate), and the
proposed module boundary is in [BASELINE.md §9](BASELINE.md#9-proposed-linux-module-tree-and-ownership-boundary).

## Verification lanes and acceptance IDs

### Linux

- **Local host:** Ubuntu 24.04.4, GNOME Wayland. The host core test passed in the gate; GTK build
  was skipped because host libadwaita 1.5 is below the 1.7 source floor. GTK launch is UNVERIFIED.
- **Container:** Ubuntu 26.04 GTK build passed after a transient dependency-fetch failure. Both
  container test targets stopped during test-binary compilation with SIGKILL; tests did not start.
  The Wayland launch did not start because Docker Desktop could not resolve `/dev/dri`.
- **Flatpak:** GNOME 50 SDK/runtime setup completed; the app build stopped at bwrap namespace
  creation. App build, install, and launch are UNVERIFIED.
- Evidence: [BUILDING.md](BUILDING.md), [BUILD_ENV_OPTIONS.md](BUILD_ENV_OPTIONS.md), and
  [M01 evidence](evidence/m01/).

### macOS

No macOS build, CI, or runtime lane has produced evidence. Build and runtime remain UNVERIFIED;
an independent CI lane is planned for M15. See [MACOS_BASELINE.md §7](MACOS_BASELINE.md#7-macos-build-recipe).

| Test ID | Current status | Evidence / reason |
| --- | --- | --- |
| ISO-01 — Linux imports macOS frameworks | PASS | host gate (Agent-Kit workspace `notes/m00/gate-full-baseline.log`): no Apple frameworks in GTK code |
| ISO-02 — macOS links Linux media libraries | UNVERIFIED | No macOS build graph/CI run; no Linux media implementation yet |
| ISO-03 — protected macOS paths unchanged | PASS | host gate (Agent-Kit workspace `notes/m00/gate-full-baseline.log`): macOS unchanged since baseline |
| MAC-01 — inherited macOS config/playback | UNVERIFIED | No macOS build or device smoke; see [MACOS_BASELINE.md §6](MACOS_BASELINE.md#6-baseline-behavior-to-regress-against-mac-01) |
| MAC-02 — app works without Linux media dependencies | UNVERIFIED | No macOS build/launch evidence; CI lane planned for M15 |
