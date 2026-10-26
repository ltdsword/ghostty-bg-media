# Changelog

## Unreleased

### Linux

- Fix playlist Loop: Loop now repeats the current video; with Loop off the playlist moves to the next video and stops after the last one (before, Loop restarted the whole playlist and never stopped on a video).
- Add `background-media-box-border` (`none`, `thin`, `thick`) and a **Box border** panel row.
- Round box corners now use a radius of one cell width (was about half).

## bgm-v0.2.1-beta (2026-10-26)

### Linux

- Fix `background-media-box-round`: it now rounds only the outer corners of each coloured area (at least 4
  cells wide) with no outline, instead of drawing a separate outlined pill around every word highlight,
  panel widget, and tab. The panel switch is now **Round box corners**.

## bgm-v0.2.0-beta (2026-10-26)

### Linux

- Add opacity and optional rounded, outlined boxes for cells with their own background colour.
- Play YouTube playlists in order with a fixed 3-second gap, playlist navigation, and loop or
  stop-at-end behavior.
- Saved panel settings load after command-line flags and override them; see CONFIGURATION.

## bgm-v0.1.0-beta (2026-10-25)

First public pre-release of Ghostty Background Media.

### Linux

- Background media support for PNG, JPEG, WebP, animated GIF, local MP4 (H.264/AAC), WebM and MKV.
- Direct HTTP(S) MP4 and HLS playback, plus YouTube videos and livestreams through user-installed `yt-dlp` (best effort).
- Appearance controls for fit, position, dim, blur, and terminal opacity; loop, pause, seek where supported, Go Live, optional audio, and pause-on-unfocus controls.
- One media decoder is shared across tabs and splits. Audio is muted by default.
- Ubuntu 26.04 amd64 `.deb` and GNOME 50 Flatpak bundle; Flatpak supports web-video audio.
- GTK panel includes a **Terminal opacity** slider in **Appearance**. **Save to Configuration** stores it in `background-media.ghostty`.
- YouTube H.264 playback fix renumbers MPEG-TS continuity counters so H.264 keyframes decode correctly (D-026).

### Known limitations

- No macOS binary is included. The inherited macOS background video is unchanged; the macOS build and smoke test are UNVERIFIED.
- Native Xorg is untested; XWayland was checked.
- YouTube depends on user-installed `yt-dlp`; available formats and livestream behavior vary, so support is best effort.
- URL playback uses software decoding.
