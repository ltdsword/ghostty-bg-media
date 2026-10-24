# Linux background media lifecycle and resource ownership

## Ownership

One app-wide media loader (`src/apprt/gtk/media_loader.zig`) owns the single decoder or stream,
timers, and yt-dlp jobs. Each tab has one `MediaView` (`src/apprt/gtk/ui/1.0/tab.blp`) behind its
split tree. All splits in a tab share that view, so media spans its panes; views draw the loader's
shared paintable. Views register on realize and unregister on unrealize. A view is active while its
window is focused.

## When media plays

Media plays while any window is active, or whenever `background-media-play-in-background` is set.
Otherwise it is paused. If the last window closes while the app keeps running, zero registered
views causes the loader to release the source, with no network activity or decoding. Opening a new
window loads the source again.

## Source switches

The old source is released before a replacement starts. A generation counter discards late file
load and yt-dlp results. A superseded yt-dlp run may finish within its 30-second timeout, but its
result is dropped.

## GTK media workarounds

GTK 4.22.4 with GStreamer 1.28.2 leaks about five threads, five file descriptors, and 18–30 MB
when a `GtkMediaFile` player is freed. Ghostty keeps the last local-video player paused and reuses
it when the same source returns, including after Turn Off → Play or closing and reopening all
windows. This reduced the recorded 15-switch run from 130 threads, 114 file descriptors, and about
1 GB RSS to 38 threads, 54 file descriptors, and about 290 MB RSS. The workaround is recorded in
[D-021](DECISIONS.md#d-021-keep-and-reuse-local-video-players-loop-in-ghostty).

GTK's built-in loop reopened the file on every pass. Ghostty now seeks to the start when the video
ends. In the recorded 12-loop, 60-second check, there was one open file and RSS grew by 1.4 MB.

## Verified behavior

On Ubuntu 26.04.1, the live HLS checks used one HTTP client with one window and one tab, three tabs,
and two windows with three tabs. After all windows closed, there were zero connections and requests
after 8–10 seconds; opening a new window resumed playback. Forty rapid window open/close cycles had
no crash, flat thread and file-descriptor counts, and plateaued RSS. Twenty-five rapid source
switches through config reload, closing windows during YouTube resolution, and panes exiting one by
one completed without a crash or GStreamer criticals; the stream was released when the last pane
exited.

With both `background-image` and `background-media` set, media is below the renderer's image layer,
as required by [PLATFORM_COMPATIBILITY](PLATFORM_COMPATIBILITY.md). This was confirmed in new tabs
and after a config reload changed background and foreground colors. Evidence: workspace
`notes/m11/`.

## Known limits

Switching to a different local video file still leaks inside GTK once per switch. One paused player
stays in memory until it is replaced or the app exits. One idle socket from the first stream session
can survive release, but does not grow.

Rendering across two to four splits, moving windows between monitors, monitor hotplug, and Wayland
occlusion were not verified by the agent; they are manual checklist items
([PANEL_CHECKLIST](PANEL_CHECKLIST.md)). Activity currently follows window focus; occlusion is not
used.
