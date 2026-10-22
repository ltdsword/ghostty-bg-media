# Background media configuration

The `background-media` settings are Linux GTK settings. macOS ignores them and keeps its existing
`background-video*` behavior. All eight settings are parsed, validated and reloadable. M04 applies
fit, position and dim to static images; M05 implements the remaining playback settings for local
video. No settings remain pending for local media.

## Keys

| Key | Type | Default | Range / values | Reload | Platform |
| --- | --- | --- | --- | --- | --- |
| `background-media` | Path or URL | unset | Local path or `http://` / `https://` URL | Config reload | Linux GTK; ignored on macOS |
| `background-media-fit` | Enum | `cover` | `contain`, `cover`, `stretch`, `none` | Config reload | Linux GTK; ignored on macOS |
| `background-media-position` | Enum | `center` | `center`, `top-left`, `top-center`, `top-right`, `center-left`, `center-right`, `bottom-left`, `bottom-center`, `bottom-right` | Config reload | Linux GTK; ignored on macOS |
| `background-media-dim` | `f32` | `0` | `0..1`; theme background tint | Config reload | Linux GTK; ignored on macOS |
| `background-media-loop` | Boolean | `true` | `true` / `false`; ignored for live streams | Config reload | Linux GTK; ignored on macOS |
| `background-media-volume` | `f32` | `0` | `0..1` | Config reload | Linux GTK; ignored on macOS |
| `background-media-play-in-background` | Boolean | `false` | `true` / `false` | Config reload | Linux GTK; ignored on macOS |
| `background-media-max-fps` | `u32` | `30` | `1..240` | Config reload | Linux GTK; ignored on macOS |

The `dim` and `volume` values are clamped to `0..1`; NaN becomes `0`. `max-fps` is clamped to
`1..240`. The default source is unset, so no media is selected.

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
- The current Flatpak has no audio permission, so non-zero volume is silent there until packaging
  adds audio access in M16.
- Images over 16,384 pixels on either side, over 64 Mi pixels, or files over 256 MiB produce a
  warning and nothing is drawn. Corrupt or unsupported inputs also produce a warning and nothing
  is drawn. GIF remains unsupported until M06.
- WebP decoding uses GNOME's sandboxed glycin loader and requires the user-installed Flatpak app.
  `flatpak-builder --run` does not provide the installed app context needed by glycin, so WebP
  decoding fails there. See [Testing WebP](BUILDING.md#testing-webp-installed-flatpak).
- URLs must use HTTP or HTTPS. Other schemes, including `ftp://` and `file://`, are rejected by
  config parsing and reported through Ghostty's normal config diagnostics, not the media log.
- Direct HTTP(S), HLS (`.m3u8`), and YouTube URLs are recognized by the M03 classifier. Playback is
  staged by source: local static images are M04, local video is M05, GIF is M06, HTTP/HLS is M07,
  and YouTube is M08/M09.
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
local image and video sessions are implemented in M04 and M05, with remote playback in later
milestones.

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
