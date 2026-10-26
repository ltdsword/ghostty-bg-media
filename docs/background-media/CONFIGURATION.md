# Background media configuration

The `background-media` settings are Linux GTK settings. macOS ignores them and keeps its existing
`background-video*` behavior. All twelve settings are parsed, validated and reloadable. M04 applies
fit, position and dim to static images; M05 implements the playback settings for local video; M06
adds local GIF playback. No settings remain pending for local media.

The `.deb` shares Ghostty's `~/.config/ghostty/config`. Flatpak uses
`~/.var/app/io.github.ltdsword.GhosttyBgMedia/config/ghostty/config`; see [INSTALL.md](INSTALL.md).

The panel's **Appearance** group includes a **Terminal opacity** slider for `background-opacity`.
It changes the current session as an override. **Save to Configuration** writes it to
`background-media.ghostty` next to the main config; the managed file loads after the main config
and its value takes precedence. The `background-opacity` config key remains shared with Ghostty.
Appearance also includes a **Boxes** slider and **Round and outline boxes** switch; Playback shows
playlist navigation while a playlist is playing.

## Keys

| Key | Type | Default | Range / values | Reload | Platform |
| --- | --- | --- | --- | --- | --- |
| `background-media` | Path or URL | unset | Local path or `http://` / `https://` URL | Config reload | Linux GTK; ignored on macOS |
| `background-media-fit` | Enum | `cover` | `contain`, `cover`, `stretch`, `none` | Config reload | Linux GTK; ignored on macOS |
| `background-media-position` | Enum | `center` | `center`, `top-left`, `top-center`, `top-right`, `center-left`, `center-right`, `bottom-left`, `bottom-center`, `bottom-right` | Config reload | Linux GTK; ignored on macOS |
| `background-media-dim` | `f32` | `0` | `0..1`; theme background tint | Config reload | Linux GTK; ignored on macOS |
| `background-media-blur` | `f32` | `0` | `0..40` px; blurs media only, keeping terminal text sharp | Config reload | Linux GTK; ignored on macOS |
| `background-media-loop` | Boolean | `true` | `true` / `false`; ignored for live streams | Config reload | Linux GTK; ignored on macOS |
| `background-media-volume` | `f32` | `0` | `0..1` | Config reload | Linux GTK; ignored on macOS |
| `background-media-play-in-background` | Boolean | `false` | `true` / `false` | Config reload | Linux GTK; ignored on macOS |
| `background-media-max-fps` | `u32` | `30` | `1..240` | Config reload | Linux GTK; ignored on macOS |
| `background-media-youtube-quality` | Choice | `auto` (720p) | `auto` or `1..4320` | Config reload or panel | Linux GTK; ignored on macOS |
| `background-media-box-opacity` | `f32` | `1` | `0..1` | Config reload | Linux GTK; ignored on macOS |
| `background-media-box-round` | Boolean | `false` | `true` / `false` | Config reload | Linux GTK; ignored on macOS |

The `dim` and `volume` values are clamped to `0..1`; NaN becomes `0`. `max-fps` is clamped to
`1..240`. Blur is clamped to `0..40`; NaN becomes `0`. The default source is unset, so no media is selected.

`background-media-youtube-quality` sets the preferred maximum height for YouTube. Auto uses 720p;
otherwise the largest offered height at or below the preference is selected, falling back to the
video's smallest offered height. Heights above 1080p use VP9 and are labelled “(high CPU)” in the
panel. The panel lists the current video's available heights, and **Save to Configuration** saves
the selected value (D-025).

## Boxes

`background-media-box-opacity` controls cells with their own background colour, including prompt
highlights, diff lines, and ANSI background colours. The default `1` keeps them opaque as before;
selected and inverse cells stay opaque. Below `1`, this setting takes precedence over
`background-opacity-cells` for those cells. `background-media-box-round = true` draws each block of
same-coloured cells as a rounded rectangle with a thin lighter outline.

## YouTube playlists

A YouTube `background-media` URL with `list=` plays playlist entries in order, starting at the
linked video when present or at the first entry. Entries are listed in batches of 50 (about 4 seconds
per batch), up to 1000.
After each video, playback waits a fixed 3 seconds before the next. At the end,
`background-media-loop = true` starts over; otherwise playback stops on the last frame. An
unresolvable video is skipped after 3 seconds; five consecutive failures stop playback with an
error. **Next** skips immediately. If listing fails and the URL has `v=`, that video plays alone.
URLs without `list=` behave as before.

## Sources and visibility

- A local path may start with `~/` or be relative to the configuration file. A leading `?` makes
  the path optional: if it is missing, the media state is disabled without a missing-file warning.
- A required path that is missing or unreadable, or a path with an unsupported media type, enters a
  failed state. These runtime source failures do not prevent Ghostty from starting.
- M04 loads local PNG, JPEG and WebP images. Fit, position and dim apply; one decode runs off the
  GTK thread and its texture is shared by all tabs.
- M05 plays local MP4 (H.264), WebM and MKV through GTK's GStreamer media backend from the GNOME
  runtime, with additional codecs from `org.freedesktop.Platform.codecs-extra`. One shared player
  serves all tabs. `loop` controls repetition; `volume = 0` mutes; `play-in-background = false`
  pauses playback when no Ghostty window is focused. `max-fps` caps redraws by dropping frames; it
  does not speed up decoding. Video load or playback errors warn and draw nothing.
- M06 decodes local GIFs with the built-in Zig decoder off the GTK window thread. Animated GIFs use
  their per-frame delays; delays of 10 ms or less are treated as 100 ms. A one-frame GIF is shown as
  a still image. `loop = true` repeats forever; `loop = false` follows the GIF's own loop count and
  then holds the last frame. `max-fps` raises the minimum frame delay to `1/max-fps`. GIF playback
  follows the same background pause rule as video. The existing image limits apply. Decoder memory
  is the file bytes plus one canvas, with one additional restore buffer when needed.
- Flatpak plays web-video audio when `background-media-volume` is above zero; the manifest enables
  the PulseAudio socket (D-027).
- Images over 16,384 pixels on either side, over 64 Mi pixels, or files over 256 MiB produce a
  warning and nothing is drawn. Corrupt or unsupported inputs also produce a warning and nothing
  is drawn.
- WebP decoding uses GNOME's sandboxed glycin loader and requires the user-installed Flatpak app.
  `flatpak-builder --run` does not provide the installed app context needed by glycin, so WebP
  decoding fails there. See [Testing WebP](BUILDING.md#testing-webp-installed-flatpak).
- URLs must use HTTP or HTTPS. Other schemes, including `ftp://` and `file://`, are rejected by
  config parsing and reported through Ghostty's normal config diagnostics, not the media log.
- M07 plays direct HTTP(S) video and HLS VOD/live with the GStreamer URL player. Direct URLs stop
  after 6 failed attempts; HLS retries forever, with a 20 s stall watchdog and exponential backoff
  capped at 60 s (±20% jitter). When unfocused with play-in-background disabled, live streams are
  released and reconnect on resume.
- M08 resolves YouTube recorded URLs with user-installed yt-dlp; `GHOSTTY_YTDLP` overrides lookup.
  The default is a maximum of 720p, and signed URLs are re-resolved on reconnect. yt-dlp is not
  bundled; without it playback fails with `ytdlp_missing` (hint: install yt-dlp or set
  `GHOSTTY_YTDLP`). Private, age-gated, members-only, removed, and playlist-only results stop
  without retry. D-025 adds per-video quality choices and pairs listed HLS audio with video when
  volume is above zero; raising volume from zero restarts with audio, preserving recorded position
  or rejoining live at the edge. Without HLS audio, the prior format choice remains, usually silent.
  Channel live URLs such as `https://www.youtube.com/@<channel>/live` work.
- M09 upcoming YouTube streams wait and poll again (30 s, x2, max 120 s, ±20% jitter). Ended
  streams stop cleanly; Go Live from the panel reconnects at the live edge.
- The media layer is visible through terminal background transparency only when
  `background-opacity` is less than `1`.

Examples (use one `background-media` value at a time):

```conf
background-media = "~/Videos/ambient.mp4"
# background-media = "~/Pictures/ambient.gif"
# background-media = "~/Pictures/ambient.webp"
# background-media = "https://www.youtube.com/watch?v=VIDEO_ID"
# background-media = "https://media.example/live.m3u8"
```

## State and reload

Reloading configuration applies changes to `background-media*`. Use Ghostty's reload command,
keybinding, or `SIGUSR2`. The M03 GTK view probes the source and records one of three states:

- `disabled`: no source is configured, or an optional path is missing.
- `ready`: the local file type or URL source kind was recognized.
- `failed`: the path is missing/unreadable, its type is unsupported, or the URL is invalid.

Reconciliation maps a transition to `start` (disabled/failed to ready), `restart` (a different
ready source), `stop` (ready to disabled/failed, or failed to disabled), or `none` (no session
change). A reload with the same ready source does not restart it. These are M03 state actions;
local image, video, and GIF sessions are implemented in M04, M05, and M06, with remote playback in
M07–M09.

The panel's managed `background-media.ghostty` is loaded through `config-file` after command-line
flags, so saved values override `--background-media…` flags. Use `--config-default-files=false` to
test flags alone, or clear the saved values.

## Control panel

The GTK panel opens from **Background Media…** in the main menu. It exposes Source, status with
Retry / Go Live, Appearance, Playback, Diagnostics, Save, and Reset controls. Source, appearance,
and playback changes apply immediately as runtime overrides; they are lost on quit unless saved.
The panel also opens from the header-bar video icon beside **View Open Tabs** in either header
layout; there is no default keybinding. **Turn Off** stops background media for the current session
without clearing the source box; **Play** reapplies the box text. **Keep playing in background**
(`background-media-play-in-background`) keeps playback running when the window loses focus or is
minimized. **Appearance** has a **Boxes** slider and **Round and outline boxes** switch. While a
playlist plays, **Playback** shows a **Playlist** row such as `2 / 3 · <playlist title>` (with `+`
after the count when more entries can be fetched) and **Previous** / **Next** buttons.
Pause is runtime-only. **Save to Configuration** writes the managed `background-media.ghostty`
file next to the main config, with a comment header, all twelve `background-media*` keys, including
both box settings, and `background-opacity`. It appends
`config-file = ?background-media.ghostty` (with a comment) to the main config once, then reloads
configuration and clears the overrides. The managed include loads after the main config, so its
values take precedence. Other main-config lines are not changed; writes use a temporary file and
rename.

## Migrating from macOS `background-video`

Linux ignores every `background-video*` key. Rename the settings you use as follows:

| macOS key | Linux setting |
| --- | --- |
| `background-video` | `background-media` |
| `background-video-play-in-background` | `background-media-play-in-background` |
| `background-video-max-fps` | `background-media-max-fps` |
| `background-video-volume` | `background-media-volume` |
| `background-video-opacity` | No direct media tint equivalent yet; use `background-opacity` to let media show through the terminal background. |
| `background-video-blur` | No Linux equivalent yet; media blur is planned for M12. |
