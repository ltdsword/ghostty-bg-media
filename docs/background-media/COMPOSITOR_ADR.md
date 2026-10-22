# M02 compositor feasibility spike

## Status

**ACCEPTED — 2026-10-22 — D-005**

## Context

M02 is the hard gate for proving that Linux GTK can display media behind interactive terminal
content before a decoder is added. Master plan §3.2 ranks correct visible output, no terminal
regression, DMA-BUF and CPU fallback, maintainability, testability, resource cost, GTK/Wayland
behavior, and implementation cost. See [BASELINE.md §8](BASELINE.md#8-m02-compositor-options--proposal)
for the source comparison and ranking.

## Options considered

**Option A — GTK composition:** Put a GTK media view beneath the split tree in a `GtkOverlay`.
This keeps terminal rendering and its presentation paths intact, while GTK composes media and
terminal snapshots at the tab boundary. The terminal background needs alpha to reveal the view.

**Option B — renderer-integrated composition:** Add a media-frame input and background pass to
Ghostty's renderer. This gives explicit layer ordering but adds frame ownership, synchronization,
uploads, and Linux-specific changes to shared renderer code. Details and trade-offs are in
[BASELINE.md §8](BASELINE.md#8-m02-compositor-options--proposal).

## Decision

Choose **Option A**: use a `GtkOverlay` in `tab.blp`, with `GhosttyMediaView` as its base child and
the existing split tree as the overlay child. The media view spans the tab's split tree. The
terminal renderer is unchanged, and the macOS tree remains untouched.

## Implementation

| File | Change |
| --- | --- |
| `src/apprt/gtk/ui/1.0/tab.blp` | Wrap the split tree in a `GtkOverlay`; put `GhosttyMediaView` below it. |
| `src/apprt/gtk/class/media_view.zig` | Add the test view, non-targetable and non-focusable, with snapshot drawing and a GTK frame-clock tick. |
| `src/apprt/gtk/media_spike_pattern.zig` | Generate the moving checkerboard, color tiles, and alpha stripes; includes pattern unit tests. |
| `src/apprt/gtk/class/tab.zig` | Register the media view type, bind the `media_overlay` template child, and size the overlay by the split tree (`setMeasureOverlay`). |
| `src/apprt/gtk/class/render_surface.zig` | Let the test hook mark presentation unhealthy to exercise the existing CPU fallback. |

The test view is enabled only when `GHOSTTY_BGM_SPIKE` is exactly `1`. Set
`GHOSTTY_BGM_FORCE_CPU=1` to force CPU presentation; that switch also requires the exact value
`1`. Run the Flatpak command with the variables set inside the sandbox:

```sh
flatpak-builder --run <builddir> flatpak/com.mitchellh.ghostty.yml env GHOSTTY_BGM_SPIKE=1 ghostty --background-opacity=0.5
```

For the CPU run, add `GHOSTTY_BGM_FORCE_CPU=1` after `env`. `flatpak-builder --run` did not forward
the host environment in the first attempt: its log lacks the media-view enabled line. Putting
`env` inside the sandbox makes the switches available to Ghostty. See
[`launch-attempt1-env-not-forwarded.txt`](evidence/m02/launch-attempt1-env-not-forwarded.txt).

## Evidence

CPU figures are `top` percentages from three 5-second samples of an idle shell. The M02 summary is
the source for visual and user-confirmed results; raw launch, CPU, and gate logs are in
[`evidence/m02/`](evidence/m02/).

| Run | Evidence path | Log proof line | User result | CPU % |
| --- | --- | --- | --- | --- |
| DMA-BUF, spike visible | [`launch-dmabuf.txt`](evidence/m02/launch-dmabuf.txt), [`cpu-measurements.txt`](evidence/m02/cpu-measurements.txt) | `GHOSTTY_BGM_SPIKE=1: media view enabled`; no DMA-BUF import failure reported | Animated checkerboard behind readable text; typing, scrolling, select/copy, splits, and new tabs: “All works” | 10.0 / 13.6 / 13.8 |
| Forced CPU, spike visible | [`launch-cpu.txt`](evidence/m02/launch-cpu.txt), [`cpu-measurements.txt`](evidence/m02/cpu-measurements.txt) | `GHOSTTY_BGM_FORCE_CPU=1: forcing CPU presentation` | Same visual and interaction result: “Same, all works” | 30.0 / 23.6 / 14.2 |
| Spike off, visible window | [`cpu-measurements.txt`](evidence/m02/cpu-measurements.txt) | `baseline: spike OFF, DMA-BUF` | Baseline idle shell | 0.0 / 0.8 / 1.0 |
| DMA-BUF, window hidden | [`cpu-measurements.txt`](evidence/m02/cpu-measurements.txt) | `DMA-BUF path, spike on, opacity 0.5, window as left by user` | Compositor paused the frame clock; CPU time stayed constant | 0.0 / 0.0 / 0.0 |
| Pattern unit tests | [`pattern-tests.txt`](evidence/m02/pattern-tests.txt) | `All 5 tests passed.` | — | — |
| Quick gate | [`gate-quick.txt`](evidence/m02/gate-quick.txt) | `verify-ghostty.sh result: PASS (6 checks run)` | Formatting, core build, and isolation checks passed; GTK build skipped on the host because libadwaita 1.5 is below the 1.7 source floor | — |

## Exit gate verdict

**PASS.** On Ubuntu 24.04.4 GNOME Wayland, the user confirmed the animated background behind
terminal text through both DMA-BUF and forced-CPU presentation. Typing, scrolling, selection/copy,
splits, and tabs worked. The macOS-untouched and no-Apple-framework-in-GTK isolation checks passed.
The Flatpak spike build succeeded; the quick gate and its host GTK-build limitation are recorded
above and in the evidence files.

## Not verified

Fractional scale (125%), resize ghosting, custom shaders, `background-image` precedence,
truecolor/per-cell backgrounds, focus visuals, multi-monitor behavior, screenshots, and extra copies
per frame (not instrumented) remain UNVERIFIED.

## Consequences and follow-ups

- The spike environment variables are test-only and are inherited by the child shell.
- The view's tick callback redraws every visible frame; procedural drawing appends one color per tile.
- Media frames must enter as `GdkTexture` on the GTK main thread. M04 and M05 build on `MediaView`.
- `background-opacity < 1` is required for the default terminal background to reveal media.
- Pivot to Option B only if a later milestone finds a defect in Option A that Option A cannot fix.
