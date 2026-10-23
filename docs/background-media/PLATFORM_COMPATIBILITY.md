# Platform compatibility

This matrix distinguishes source-inherited macOS behavior from verified runtime support. Every
macOS runtime item remains UNVERIFIED until a macOS build and smoke test are recorded.

## Support matrix

| Capability | macOS | Linux / Ubuntu 24.04 | Status |
| --- | --- | --- | --- |
| Original video background | Inherited implementation | Not required | macOS inherited; runtime UNVERIFIED; Linux NOT_STARTED |
| Static background image | Inherited image path | Supported (M04: PNG/JPEG/WebP) | macOS inherited; runtime UNVERIFIED; Linux M04 PARTIAL |
| Animated GIF | No added parity commitment | Supported (M06: built-in decoder) | macOS runtime UNVERIFIED; Linux M06 PARTIAL |
| Local video | Inherited AVFoundation path | Supported (M05: GTK/GStreamer; MP4/H.264, WebM, MKV) | macOS inherited; runtime UNVERIFIED; Linux M05 PARTIAL |
| YouTube recorded/live | Inherited resolver/settings | Planned Linux-only resolver/player | macOS inherited; runtime UNVERIFIED; Linux NOT_STARTED |
| Settings UI | Existing Swift/AppKit panel | Planned GTK4 UI | macOS inherited; runtime UNVERIFIED; Linux NOT_STARTED |
| Media dependencies | Existing native stack | GTK/GStreamer from the GNOME runtime plus `org.freedesktop.Platform.codecs-extra` | macOS inherited; runtime UNVERIFIED; Linux M05 PARTIAL |
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

The M03 config contract is:

| Config values | macOS | Linux / GTK |
| --- | --- | --- |
| Only `background-media` | Ignore `background-media*`; inherited `background-video*` behavior is unchanged | Use `background-media*` |
| Only `background-video` | Existing `background-video*` behavior is unchanged | Ignore `background-video*` |
| Both `background-media` and `background-video` | Ignore `background-media*`; existing `background-video*` behavior is unchanged | Use `background-media*`; ignore `background-video*` |
| `background-image` plus `background-media` | Ignore `background-media*`; preserve existing image behavior | Use `background-media` as the media layer; the terminal renderer draws `background-image` above it |

Linux does not fall back from `background-media` to `background-video`. The terminal renderer's
existing image and color composition remains intact. See [BASELINE.md §§6–7](BASELINE.md#7-configuration-and-reload).

## Recognized but unsupported keys

- The shared config parser recognizes `background-media*` on macOS, but the macOS app ignores
  those keys. Its existing `background-video*` settings remain unchanged.
- Linux recognizes the legacy `background-video*` keys in shared config but ignores them; they are
  not aliases for `background-media*`.
- HTTP(S) YouTube and HLS URLs are recognized by the M03 source classifier, but playback is
  deferred to M07–M09. Recognition does not select a playback backend.
- A rejected URL scheme such as `ftp://` is reported by Ghostty's normal config diagnostics, not
  the media log. The GTK config-errors UI for this case has not been checked.

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

- **Local host:** Ubuntu 24.04.4, GNOME Wayland. The core build passed in the quick gate; GTK build
  was skipped because host libadwaita 1.5 is below the 1.7 source floor. See the host Flatpak visual
  lane for the M02 GTK result.
- **Container:** Ubuntu 26.04 GTK build passed after a transient dependency-fetch failure. Both
  container test targets stopped during test-binary compilation with SIGKILL; tests did not start.
  The Wayland launch did not start because Docker Desktop could not resolve `/dev/dri`.
- **Flatpak M01 lane:** GNOME 50 SDK/runtime setup completed; the M01 build attempt stopped at bwrap
  namespace creation. See [M01 evidence](evidence/m01/).
- **Manual host-Flatpak visual lane (M02): PASS.** On Ubuntu 24.04.4 GNOME Wayland, the spike ran
  through both DMA-BUF and forced-CPU presentation. The user confirmed the animated background,
  terminal interaction, splits, and tabs; see [M02 evidence](evidence/m02/).
- Evidence: [BUILDING.md](BUILDING.md), [BUILD_ENV_OPTIONS.md](BUILD_ENV_OPTIONS.md), [M01 evidence](evidence/m01/), and
  [M02 evidence](evidence/m02/).

### macOS

No macOS build, CI, or runtime lane has produced evidence. Build and runtime remain UNVERIFIED;
an independent CI lane is planned for M15. See [MACOS_BASELINE.md §7](MACOS_BASELINE.md#7-macos-build-recipe).

| Test ID | Current status | Evidence / reason |
| --- | --- | --- |
| ISO-01 — Linux imports macOS frameworks | PASS | [latest quick gate](evidence/m02/gate-quick.txt): no Apple frameworks in GTK code |
| ISO-02 — macOS links Linux media libraries | UNVERIFIED | [latest quick gate](evidence/m02/gate-quick.txt) is not a macOS build; macOS build graph/CI remains unverified |
| ISO-03 — protected macOS paths unchanged | PASS | [latest quick gate](evidence/m02/gate-quick.txt): macOS unchanged since baseline |
| MAC-01 — inherited macOS config/playback | UNVERIFIED | No macOS build or device smoke; see [MACOS_BASELINE.md §6](MACOS_BASELINE.md#6-baseline-behavior-to-regress-against-mac-01) |
| MAC-02 — app works without Linux media dependencies | UNVERIFIED | No macOS build/launch evidence; CI lane planned for M15 |

## Linux build lanes (D-012, 2026-10-24)

- **Native (Ubuntu 26.04 dev host): UNVERIFIED.** Planned primary development lane; requires
  libadwaita >= 1.7 from the distro. Not yet built or run.
- **Flatpak (GNOME 50 runtime): verified M01–M06.** Distribution lane and the supported path for
  distros too old for a native build, including Ubuntu 24.04.
- Both lanes build the same source; no lane-specific code.
