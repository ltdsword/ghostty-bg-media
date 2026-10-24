# Background media features

Linux GTK feature set, inventoried from the current code and project docs.
macOS keeps its inherited `background-video` feature unchanged and ignores `background-media*`.
Status words: **Shipped** (merged and verified by the agent), **Manual check** (merged, needs a human check), **Limitation**, **Not started**.

## At a glance

- Show local PNG, JPEG, WebP, GIF, MP4, WebM, and MKV backgrounds.
- Play direct HTTP(S) video and HLS VOD or live streams.
- Resolve recorded, live, and upcoming YouTube URLs with a separately installed `yt-dlp`.
- Choose image fit and alignment, theme-color dim, and media-only blur.
- Control looping, volume, background playback, and a maximum redraw frame rate.
- Share one media session across tabs and one view across each tab's splits.
- Pause when no window is active, or keep playing in the background by setting a preference.
- Resume a paused HLS or live stream by reconnecting; upcoming streams are polled.
- Seek finite video when its backend exposes a duration and seek position.
- Configure sources and settings from the GTK settings panel without restarting.
- Save panel settings to a managed include file in the Ghostty configuration directory.
- Inspect playback, GStreamer, and `yt-dlp` status in the panel and application logs.
- Bound image and GIF dimensions and file size; decode local media away from the GTK thread.
- Stop direct URL retries after six failures and keep retrying HLS with backoff.
- Keep terminal text sharp above the media and keep `background-image` above the media layer.

## Media sources

| Source | Example | Formats / detection | Backend | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| Static image | `~/Pictures/wall.webp` | PNG, JPEG, WebP. Reads up to 65,536 header bytes and sniffs signatures first; falls back to `.png`, `.jpg`/`.jpeg`, or `.webp`. [`source.zig`](../../src/apprt/gtk/background_media/source.zig), [`header.zig`](../../src/apprt/gtk/background_media/header.zig), [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig); D-009. | GDK texture loader; GNOME glycin loader for WebP. | Manual check | 16,384 px per side, 64 Mi pixels, and 256 MiB per file limits. JPEG/WebP contain fit and live resize/splits still need a human check. |
| Animated GIF | `~/Pictures/loop.gif` | GIF87a/GIF89a signature, with `.gif` extension fallback. [`source.zig`](../../src/apprt/gtk/background_media/source.zig), [`header.zig`](../../src/apprt/gtk/background_media/header.zig), [`gif.zig`](../../src/apprt/gtk/background_media/gif.zig); D-011. | Built-in pure-Zig GIF decoder and GTK texture. | Manual check | Uses GIF frame delays and loop count; delays at or below 10 ms become 100 ms. A one-frame GIF is a still. |
| Local video | `~/Videos/ambient.mp4` | MP4/H.264, WebM, MKV. Sniffs `ftyp` at byte 4 or the EBML signature, then falls back to `.mp4`, `.m4v`, `.mov`, `.webm`, or `.mkv`. [`source.zig`](../../src/apprt/gtk/background_media/source.zig), [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig); D-010, D-021. | `GtkMediaFile` backed by GStreamer in the GNOME runtime. | Manual check | Runtime plugin probing found the listed containers/codecs; the recorded playback probe exercised H.264 MP4. Ghostty loops the retained player by seeking to the start. |
| Direct HTTP(S) video | `https://media.example/video.mp4` | Any HTTP(S) URL not classified as HLS or YouTube is direct; file extension is not required for URL classification. [`source.zig`](../../src/apprt/gtk/background_media/source.zig), [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig); D-014, D-016. | Linux GStreamer URL player using `playbin3` (or `playbin`) and appsink. | Shipped | Software decoding is used for URL playback. Direct sources stop after six failed attempts. |
| HLS VOD and live | `https://media.example/live.m3u8` | HTTP(S) URL path ending in `.m3u8`; a query string does not change path classification. [`source.zig`](../../src/apprt/gtk/background_media/source.zig), [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig); D-014, D-016. | Linux GStreamer URL player. | Shipped | Supports VOD and live playlists. HLS retries indefinitely with a stall watchdog and backoff. |
| YouTube recorded | `https://www.youtube.com/watch?v=…` | Recognized YouTube hostnames, including `youtube.com`, `youtu.be`, and `youtube-nocookie.com`. [`source.zig`](../../src/apprt/gtk/background_media/source.zig), [`youtube.zig`](../../src/apprt/gtk/background_media/youtube.zig), [`youtube_resolver.zig`](../../src/apprt/gtk/youtube_resolver.zig); D-017, D-025, D-026. | User-installed `yt-dlp`, then the GStreamer URL player. | Shipped | Quality defaults to Auto (720p); listed HLS audio is fetched only above zero volume. Recorded playback keeps its position when volume is raised. H.264 segment keyframes render cleanly after the continuity fix. |
| YouTube live/upcoming | `https://www.youtube.com/@channel/live` | Same host classification; `yt-dlp` supplies recorded/live/upcoming state. [`source.zig`](../../src/apprt/gtk/background_media/source.zig), [`youtube.zig`](../../src/apprt/gtk/background_media/youtube.zig), [`live.zig`](../../src/apprt/gtk/background_media/live.zig); D-017, D-018, D-025, D-026. | User-installed `yt-dlp`, then the GStreamer URL player. | Shipped | Quality uses the current video's offered heights. Listed HLS audio is fetched only above zero volume; live playback rejoins at the live edge after a volume-up restart. Upcoming streams are polled; **Go Live** reconnects at the live edge. H.264 segment keyframes render cleanly after the continuity fix. |

Local image, GIF, and video file classification reads at most 65,536 bytes for header sniffing. An unrecognized signature falls back to the file extension. Configured URLs accept only HTTP or HTTPS.

## Settings

All ten settings are Linux GTK settings and apply on configuration reload. Their definitions are in [`Config.zig`](../../src/config/Config.zig); the GTK controls are in [`media-panel.blp`](../../src/apprt/gtk/ui/1.5/media-panel.blp).

| Key | Default | Range | What it does | Live reload | Panel control |
| --- | --- | --- | --- | --- | --- |
| `background-media` | unset | Local path or HTTP(S) URL | Selects the media source; unset disables media. [`Config.zig`](../../src/config/Config.zig) | Yes | Source entry, **Choose File…**, **Apply**, **Use Configuration**, **Turn Off** |
| `background-media-fit` | `cover` | `contain`, `cover`, `stretch`, `none` | Chooses how media fits the view. [`Config.zig`](../../src/config/Config.zig) | Yes | **Fit** |
| `background-media-position` | `center` | Nine compass positions | Aligns media within the view. [`Config.zig`](../../src/config/Config.zig) | Yes | **Position** |
| `background-media-dim` | `0` | `0..1` | Covers media with the theme background color. [`Config.zig`](../../src/config/Config.zig) | Yes | **Dim** slider |
| `background-media-blur` | `0` | `0..40` px | Blurs the media layer while terminal text stays sharp. [`Config.zig`](../../src/config/Config.zig), [`media_view.zig`](../../src/apprt/gtk/class/media_view.zig) | Yes | **Blur** slider |
| `background-media-loop` | `true` | Boolean | Repeats finite video or GIF; live streams ignore it. [`Config.zig`](../../src/config/Config.zig) | Yes | **Loop** switch |
| `background-media-volume` | `0` | `0..1` | Sets media volume; zero is muted. [`Config.zig`](../../src/config/Config.zig) | Yes | **Volume** slider |
| `background-media-play-in-background` | `false` | Boolean | Keeps playback running when no window is active. [`Config.zig`](../../src/config/Config.zig) | Yes | **Keep playing in background** switch |
| `background-media-max-fps` | `30` | `1..240` | Caps redraw cadence; it does not accelerate video decoding. [`Config.zig`](../../src/config/Config.zig) | Yes | **30 fps** or **60 fps** |
| `background-media-youtube-quality` | `auto` (720p) | `auto` or `1..4320` | Sets the preferred YouTube maximum height; Auto uses 720p. [`Config.zig`](../../src/config/Config.zig) | Yes | **YouTube quality** row for a resolved YouTube source |

The panel's available frame-rate buttons are 30 and 60 fps; configuration accepts 1 through 240. macOS ignores all ten `background-media*` keys.

## Display and appearance

- `contain` fits the whole image inside the view; `cover` fills it and crops overflow; `stretch` fills the view without preserving aspect ratio; `none` uses the media's intrinsic size. The nine positions align each result to the center, an edge, or a corner. [`layout.zig`](../../src/apprt/gtk/background_media/layout.zig), [`media_view.zig`](../../src/apprt/gtk/class/media_view.zig).
- Dim overlays the media with the configured theme background color. `0` leaves media unchanged; `1` covers it. [`media_view.zig`](../../src/apprt/gtk/class/media_view.zig).
- Blur is applied to the media snapshot only, from 0 to 40 px; terminal text remains sharp. NaN is treated as 0 and values are clamped when applied. M12 added this setting (D-022). [`media_view.zig`](../../src/apprt/gtk/class/media_view.zig), [`media_overrides.zig`](../../src/apprt/gtk/media_overrides.zig).
- Media is visible through terminal background transparency only when `background-opacity` is below `1`. The terminal renderer draws `background-image` above the media. [Platform compatibility](PLATFORM_COMPATIBILITY.md), [`media_view.zig`](../../src/apprt/gtk/class/media_view.zig).
- Each tab has one media view behind its split tree, so the same tab media spans all its panes. Tabs and windows share the app-wide loader and media session. [Lifecycle](LIFECYCLE.md), [`media_view.zig`](../../src/apprt/gtk/class/media_view.zig), [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig).

## Playback behavior

- Looping for local video is implemented by Ghostty seeking the existing player to the beginning at end of stream (D-021). With looping disabled, finite video holds its final frame. GIF looping uses the GIF loop count when the setting is false and repeats forever when true (D-011). Live streams ignore the loop setting. [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig), [`gif.zig`](../../src/apprt/gtk/background_media/gif.zig), [`live.zig`](../../src/apprt/gtk/background_media/live.zig).
- Volume ranges from muted (`0`) to full (`1`). For YouTube, HLS audio is fetched only when volume is above zero; raising it from zero restarts with audio, preserving recorded position or rejoining live at the edge. Lowering it to zero only mutes (D-025). [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig), [`youtube.zig`](../../src/apprt/gtk/background_media/youtube.zig).
- With **Keep playing in background** off, media pauses when no registered view belongs to an active window (including when the window loses focus or is minimized). With it on, playback continues. Closing the last window releases the source; a later window loads it again. [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig), [Lifecycle](LIFECYCLE.md).
- `background-media-max-fps` caps redraws for video and URL frames; GIF cadence also raises its minimum frame delay to the configured interval. It does not make decoding faster. [`cadence.zig`](../../src/apprt/gtk/background_media/cadence.zig), [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig).
- Pausing local video or HLS used about 0.2–0.3% of one CPU core in the 2026-10-24 measurements. Pause stops playback work; a live URL can be released and reconnected when playback resumes. [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig), [PERFORMANCE.md](PERFORMANCE.md).
- Direct URL sources retry at most six failures. HLS keeps retrying, with exponential delay from 1 s up to 60 s and ±20% jitter; a 20 s frame stall triggers recovery (D-016). [`retry.zig`](../../src/apprt/gtk/background_media/retry.zig), [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig).
- Upcoming YouTube events are polled after 30 s, then 60 s and at most 120 s, with ±20% jitter (D-018). Ended HLS streams stop on end-of-stream; ended YouTube live streams are rechecked once. **Go Live** reconnects at the live edge. [`live.zig`](../../src/apprt/gtk/background_media/live.zig), [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig).

## Settings panel (GTK)

Open the panel with the header-bar background-media button or the `background-media` window action. The main menu also has **Background Media…**; there is no default keybinding. [`window.zig`](../../src/apprt/gtk/class/window.zig), [`media_panel.zig`](../../src/apprt/gtk/class/media_panel.zig).

- **Source:** choose a file, enter a path or URL, **Apply** the entry, or restore the configured source with **Use Configuration**.
- **Playback:** view status; **Pause/Play**, **Turn Off**, **Retry**, and **Go Live** when applicable; seek finite video when its backend reports timing; set **Loop**, **Volume**, background playback, and 30/60 fps.
- **YouTube quality:** when the source resolves to YouTube, select Auto (720p) or a height offered by the current video; choices above 1080p are labelled “(high CPU)”. **Save to Configuration** persists the preferred maximum (D-025).
- **Appearance:** choose **Fit** and **Position**, and set **Dim** and **Blur** sliders.
- **Diagnostics:** see whether the GStreamer URL player is available and the selected `yt-dlp` path or missing-tool hint.
- Status includes **No background media**, **Idle**, **Loading**, **Showing** for a still image, **Playing**, **Paused**, **Failed**, **LIVE**, **Waiting for the stream to start**, **Reconnecting**, and **Stream ended**.
- Source and settings changes apply immediately as runtime overrides. **Turn Off** stops playback for the session while preserving the source-box text; **Play** reapplies it. **Save to Configuration** writes `background-media.ghostty` with all ten settings, adds `config-file = ?background-media.ghostty` to the main config once, reloads config, and clears overrides. The managed include loads after the main config and takes precedence. **Reset Changes** restores configured values (D-019). [`media_panel.zig`](../../src/apprt/gtk/class/media_panel.zig), [`config_save.zig`](../../src/apprt/gtk/background_media/config_save.zig).

## Lifecycle and resource use

- One app-wide loader owns the current decoder/player, timers, and `yt-dlp` jobs. Each tab has one view; views share the same paintable and player. [Lifecycle](LIFECYCLE.md), [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig).
- The loader releases the source when its last view unregisters. It retains the last local-video `GtkMediaFile` paused and reuses it for the same source. [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig); D-021.
- A generation counter discards late local-load and resolver results after a source change. [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig), [`youtube_resolver.zig`](../../src/apprt/gtk/youtube_resolver.zig).
- With no source configured, no file-loader worker, media decoder, URL player, or animation timer is started. [`media_view.zig`](../../src/apprt/gtk/class/media_view.zig), [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig).

## Performance

CPU is percent of one core, measured on a Core Ultra 5 235U with ReleaseFast on 2026-10-24. Results are observed samples, not guarantees.

| Scenario | CPU | Notes |
| --- | ---: | --- |
| No media | 0.4% | Idle baseline. [PERFORMANCE.md](PERFORMANCE.md) |
| Static image | 0.6% | Still image. [PERFORMANCE.md](PERFORMANCE.md) |
| GIF | 2.9% | Animated fixture. [PERFORMANCE.md](PERFORMANCE.md) |
| Local 720p/1080p video | ~11% | Combined range from the recorded local-video sample. [PERFORMANCE.md](PERFORMANCE.md) |
| Live HLS 720p | 21% → 19% | M12 YUV path result (D-023). [PERFORMANCE.md](PERFORMANCE.md) |
| HLS 1080p | 69% → 50% | Before and after the M12 YUV path (D-023). [PERFORMANCE.md](PERFORMANCE.md) |
| YouTube | 67% → 54% | Before and after the M12 YUV path (D-023). [PERFORMANCE.md](PERFORMANCE.md) |
| Paused local video or HLS | 0.2–0.3% | Near-idle sample. [PERFORMANCE.md](PERFORMANCE.md) |

M12 adds I420 YUV frames on GTK 4.20 or newer so GDK can convert them on the GPU, reducing frame copies (D-023). Hardware video decoding for URL playback remains disabled: a retest still segfaulted within 12 seconds (D-015). See [PERFORMANCE.md](PERFORMANCE.md).

## Security and robustness

- Configured URL sources accept only HTTP and HTTPS. `yt-dlp` formats are also accepted only when their media URL uses HTTP(S). [`source.zig`](../../src/apprt/gtk/background_media/source.zig), [`youtube.zig`](../../src/apprt/gtk/background_media/youtube.zig).
- Image and GIF loads enforce a 65,536-byte header read and limits of 16,384 px per side, 64 Mi pixels, and 256 MiB per file. Image and GIF decoding runs away from the GTK thread; GStreamer handles local-video decoding. [`header.zig`](../../src/apprt/gtk/background_media/header.zig), [`media_loader.zig`](../../src/apprt/gtk/media_loader.zig).
- URL logging removes credentials, query strings, and fragments. `GHOSTTY_YTDLP` selects an alternate `yt-dlp` executable. [`source.zig`](../../src/apprt/gtk/background_media/source.zig), [`youtube_resolver.zig`](../../src/apprt/gtk/youtube_resolver.zig).
- `yt-dlp` runs in its own process group. M13 kills the group after a 30 s timeout or oversized output; Flatpak runs the host command through `flatpak-spawn --host --watch-bus`. [`youtube_resolver.zig`](../../src/apprt/gtk/youtube_resolver.zig), [`youtube.zig`](../../src/apprt/gtk/background_media/youtube.zig).
- A remote HLS playlist may reference `file://` segments that GStreamer then plays locally; this is assessed as a low risk in the task evidence. An in-flight `yt-dlp` job can outlive app exit until it finishes.

See [SECURITY.md](SECURITY.md) and [TEST_MATRIX.md](TEST_MATRIX.md).

## Platform support

| Platform / lane | Support |
| --- | --- |
| Wayland | Primary Linux lane; verified. [PLATFORM_COMPATIBILITY.md](PLATFORM_COMPATIBILITY.md) |
| X11 via XWayland | Verified 2026-10-24. [PLATFORM_COMPATIBILITY.md](PLATFORM_COMPATIBILITY.md) |
| Native Xorg | Untested. [PLATFORM_COMPATIBILITY.md](PLATFORM_COMPATIBILITY.md) |
| Flatpak | GNOME 50 distribution and compatibility lane; retains runtime codec dependencies. [PLATFORM_COMPATIBILITY.md](PLATFORM_COMPATIBILITY.md), [BUILDING.md](BUILDING.md) |
| macOS | Inherited `background-video` feature remains unchanged. `background-media*` is ignored; no new parity is claimed. [PLATFORM_COMPATIBILITY.md](PLATFORM_COMPATIBILITY.md), [`Config.zig`](../../src/config/Config.zig) |

Linux GTK is the only implementation of `background-media*`. Platform status and verification context: [PLATFORM_COMPATIBILITY.md](PLATFORM_COMPATIBILITY.md), [BUILDING.md](BUILDING.md).

Flatpak plays web-video audio when `background-media-volume` is above zero; its manifest includes the PulseAudio socket (D-027).

## Diagnostics and logs

Search application logs for `background-media:`. Common messages include:

- `loaded type=…` for a local image/GIF.
- `playing type=…` for local video.
- `connecting kind=… source=… attempt=…` for direct/HLS/YouTube URL playback.
- `reconnect reason=… attempt=… delay_ms=… source=…` when a URL player retries.
- `failed reason=…` for source, decode, resolver, or playback failures.

Logged URL sources omit credentials, query strings, and fragments. The panel's Diagnostics section shows GStreamer URL-player availability and whether `yt-dlp` was found. Set `GHOSTTY_YTDLP` to use a non-default executable; in Flatpak, yt-dlp runs on the host through `flatpak-spawn`.

## Developer and test tooling

- The offline HTTP fixture server is `test/background-media/http_fixture_server.py`; it creates media with host `ffmpeg` and binds to `127.0.0.1:8731` by default. Routes include finite byte-range MP4 (`/vod/v.mp4`), HLS VOD (`/hls/vod.m3u8` and `/hls/<seg>.ts`), sliding live HLS (`/live/live.m3u8` and `/live/seg-<n>.ts`), timed live end (`/live-end/<seconds>/…`), HTTP faults (`/status/<code>/<rest>`), redirects, throttled responses (`/slow/…`), mid-body disconnects (`/drop/…`), and timed outages (`/control/outage?seconds=N`). [Fixture README](../../test/background-media/README.md).
- `test/background-media/fake-yt-dlp` provides offline recorded, live, upcoming, ended, private, age-gated, members-only, unavailable, flaky, slow, malformed-JSON, and playlist scenarios. [Fixture README](../../test/background-media/README.md).
- Background-media unit test counts (`test "` declarations): `cadence.zig` 4; `config_save.zig` 6; `gif.zig` 6; `header.zig` 5; `layout.zig` 2; `live.zig` 3; `main.zig` 0; `retry.zig` 3; `source.zig` 5; `state.zig` 2; `youtube.zig` 12; `yuv.zig` 3. Counted from [`background_media/`](../../src/apprt/gtk/background_media/).
- Workspace gate: `scripts/verify-ghostty.sh --quick` checks formatting, isolation, and the core build; `--full` runs core tests instead. It skips the GTK build unless `GHOSTTY_GTK_BUILD_CMD` is supplied. [BUILDING.md](BUILDING.md).

## Known limitations

- Static-image checks remain incomplete for JPEG/WebP contain fit, live resize, and splits. GIF pause/resume, terminal responsiveness, and full RSS release need verification; local video has a recorded late RSS/CPU growth trend. [STATUS.md](STATUS.md).
- The recorded local-video runtime playback probe exercised H.264 MP4, while WebM/MKV were covered by runtime plugin probing. M16 enabled the Flatpak PulseAudio socket and verified web-video audio (D-027). [STATUS.md](STATUS.md), [BUILDING.md](BUILDING.md).
- Switching to a different local video still leaks resources inside GTK. Ghostty retains one paused local-video player until it is replaced or the app exits; one idle network socket may survive a stream release (D-021). [LIFECYCLE.md](LIFECYCLE.md).
- URL playback uses software decoding because VA/VAAPI hardware decoding segfaulted during testing (D-015). Reconnecting URL playback can show a blank frame until recovery.
- WebP decoding needs the installed Flatpak app context; `flatpak-builder --run` does not provide it. [BUILDING.md](BUILDING.md#testing-webp-installed-flatpak), D-009.
- YouTube needs user-installed `yt-dlp`. When yt-dlp lists HLS audio, native Linux GTK fetches it only above zero volume; otherwise the prior format choice is used and may be silent (D-017, D-025). H.264 HLS keyframes are repaired by the continuity-counter fix (D-026).
- Activity follows window focus; occlusion is not tracked. Split rendering, moving between monitors, monitor hotplug, Wayland occlusion, IME, SSH, mouse modes, drag-select/copy, and the panel keystroke-leak check still need human checks. [LIFECYCLE.md](LIFECYCLE.md), [PANEL_CHECKLIST.md](PANEL_CHECKLIST.md).

## Not started / future

- **M14 — Docs/release candidate:** package and handoff documentation.
- **M15 — CI lanes:** skipped by the user on 2026-10-24.
- **M16 — Linux packaging:** done; public downloads are planned for M17. [INSTALL.md](INSTALL.md), [STATUS.md](STATUS.md).
- **M17 — Public beta:** publish after release gates pass.
- **M18 — Optional macOS parity:** requires a separate approval before consideration.
- Manual checks still owed include splits, multi-monitor movement/hotplug, occlusion, IME, SSH, mouse modes, drag-select/copy, and confirming panel typing cannot leak keystrokes to the terminal. [STATUS.md](STATUS.md), [LIFECYCLE.md](LIFECYCLE.md), [PANEL_CHECKLIST.md](PANEL_CHECKLIST.md).
