# Background media performance

## Method

Measurements were made on 2026-10-24 with Ubuntu 26.04.1, an Intel Core Ultra 5 235U with
Arrow Lake-U integrated graphics, GTK 4.22.4, and GStreamer 1.28.2. The app used a ReleaseFast
build with `background-media-play-in-background = true`. CPU is percent of one core, sampled for
30 seconds after a 12-second warmup. These are observations from this machine, not performance
guarantees. Evidence: workspace `notes/m12/bench-*.txt`.

The cases were no media, a still image, a 320x180 GIF, local 720p and 1080p video, live HLS at
720p, 1080p HLS VOD, and 1080p YouTube playback.

## Before and after M12

| Case               | CPU before (% of one core) | CPU after M12 (% of one core) | RSS before → after (MB) |
| ------------------ | -------------------------: | ----------------------------: | ----------------------: |
| No media           |                        0.4 |                             — |                     159 |
| Image              |                        0.6 |                             — |                     164 |
| GIF 320x180        |                        2.9 |                             — |                     162 |
| Local 720p / 1080p |                11.2 / 10.9 |                Unchanged path |               193 / 194 |
| Live HLS 720p      |                       21.3 |                          19.2 |               315 → 332 |
| HLS 1080p VOD      |                       68.8 |                          49.9 |               412 → 387 |
| YouTube 1080p      |                       66.5 |                          54.3 |               308 → 298 |

The YUV upload path changes apply to URL video; local video continues to use GTK's existing
hardware-backed media path. The local-video values above were not rerun as an M12 before/after
comparison.

## M12 changes

### YUV frame upload

On GTK 4.20 and newer, a compile-time header check and runtime version check enable I420 output
from the URL player's appsink. Ghostty creates `GdkMemoryTextureBuilder` textures in
`g8_b8_r8_420`, with narrow-range CICP and BT.709 for frame heights of at least 720 pixels, or
BT.601 below that. GDK/GPU converts the texture to RGB. This copies 1.5 bytes per pixel instead of
4 bytes per pixel for RGBA. Older GTK versions keep the RGBA path. If the color state cannot be
built, Ghostty logs once and falls back to RGBA. Layout math is in `background_media/yuv.zig` and
has three tests. Colors were visually checked against the RGBA path in workspace
`notes/m12/color-rgba.png` and workspace `notes/m12/color-yuv.png`.

### Blur

`background-media-blur` is an `f32` radius in pixels, clamped to `0..40`, with default `0` and
NaN mapped to `0`. GTK applies `GtkSnapshot.pushBlur` around only the media paintable; dim is
applied after blur, and terminal text stays sharp. The Appearance panel exposes the slider and
saves it to configuration. Blur is GPU work and was not benchmarked separately. Visual evidence:
workspace `notes/m12/blur-0.png` and workspace `notes/m12/blur-20.png`.

## CPU breakdown and pause behavior

Before M12, the 1080p HLS sample attributed about 33% of one core to software H.264 decode, 16.5%
to CPU videoconvert to RGBA, 16% to the main thread, and 5% to demux. Evidence: workspace
`notes/m12/thread-cpu-hls1080.txt`.

With the panel open during measurement, pausing changed local 1080p playback from 17.5% to 0.2%
CPU, and HLS 1080p from 72.6% to 0.3%. Paused media does no redraw work. Evidence: workspace
`notes/m12/bench-inactive.txt`.

## Hardware decode retest

With VA decoders enabled, HLS 1080p measured 60% CPU and YouTube measured 61%, but live HLS
segfaulted within 12 seconds. URL hardware decoding remains disabled under D-015. Evidence:
workspace `notes/m12/bench-hw.txt`.

## Soak

A two-hour ReleaseFast soak used five-minute samples. Live HLS 720p and YouTube live stayed flat
after warm-up. The local 1080p loop stayed flat through minute 70. At minute 75 that window was
switched from the panel to a second (YouTube esports) livestream; afterward it held both and RSS
reached 487 MB by minute 120. There was no crash and no leak was attributed; file descriptors and
threads were flat at the end.

| Instance / interval | RSS (MB) | File descriptors / threads |
| ------------------- | -------: | -------------------------: |
| Live HLS 720p, start → 60 → 120 min | 303 → 305 → 305 | — |
| YouTube live, start → 60 → 120 min | 300 → 318 → 319 | — |
| Local 1080p, start → minute 70 | 194 → 206 | — |
| After minute-75 switch described above, by minute 120 | 487 | 72 / 57 |

Evidence: workspace `notes/m12/soak.csv`.

## YouTube quality and audio

Measurements used the GStreamer player alone with software decoding and VA demoted. RSS is peak
resident memory; CPU is percent of one core.

| Stream | Peak RSS (MB) | CPU (%) |
| --- | ---: | ---: |
| Audio-only, 128k AAC | 79 | 3 |
| 720p60 H.264 | 149 | 27 |
| 1080p60 H.264 | 219 | 46 |
| 1440p60 VP9 | 111 | 155 |
| 2160p60 VP9 | 207 | 271 |

Ghostty with no media was about 159 MB. In the M14 ReleaseFast build, live 720p with audio used
306 MB / 38% CPU; recorded 720p muted used 313 MB; recorded 1440p VP9 with audio used 416 MB /
88% CPU. These measurements show the high CPU cost of VP9 above 1080p. Evidence: M14 measurements;
see [D-025](DECISIONS.md#d-025-youtube-quality-choice-and-optional-hls-audio).

## Remaining cost

URL playback still uses software decoding because enabling VA decoding caused a live HLS crash.
The next option is to retest hardware decode after GStreamer VA support is stable. Adopting
`gtk4paintablesink` would add a dependency; it was not adopted.
