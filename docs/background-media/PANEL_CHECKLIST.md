# Background media panel — manual test checklist

Linux GTK only. Run with an isolated `XDG_CONFIG_HOME` to protect your config.

## Open

- [ ] Click the video icon beside **View Open Tabs** in one header layout. Expected: the panel opens.
- [ ] Repeat in the other header layout. Expected: the panel opens.
- [ ] Choose **Main Menu → Background Media…**. Expected: the panel opens.
- [ ] Check the default keybindings for a panel shortcut. Expected: none is assigned.

## Source

- [ ] Open the source group. Expected: **Choose File…** uses the system accent color.
- [ ] Choose a media file. Expected: its full path appears in the source box.
- [ ] Paste a path or URL into the full-width **Image, video or URL** box. Expected: the text appears as entered.
- [ ] Choose **Use Configuration** on the group title row. Expected: the configured source and values are reapplied.
- [ ] Load a source with a retryable error. Expected: status text appears as a subtitle and **Retry** is available.
- [ ] Open an upcoming live stream. Expected: **Go Live** is available and starts playback at the live edge.

## Playback

- [ ] Pause playback, then resume it. Expected: the control changes between **Pause** and **Play**.
- [ ] Choose **Turn Off**, then **Play**. Expected: media stops for this session, the source box keeps its text, and Play reapplies it.
- [ ] Play finite video. Expected: the seek row shows elapsed and total time, and seeking jumps to the chosen time.
- [ ] Select an image, GIF, or live source. Expected: the seek row is hidden.
- [ ] Change **Loop**. Expected: the selected setting is applied to playback.
- [ ] Change **Volume**. Expected: the selected level is applied; zero mutes.
- [ ] Enable **Keep playing in background**, then minimize the window or move focus away. Expected: playback continues.
- [ ] Select **30 fps** and **60 fps**. Expected: each frame-rate setting can be selected.
- [ ] Check the playback status. Expected: status text appears as a subtitle.
- [ ] Select a still image. Expected: status reads **Showing** and Pause is greyed out. Select a GIF. Expected: status reads **Playing**.
- [ ] Open a retryable failed source and use **Retry**. Expected: the source is retried.

## Appearance

- [ ] Change **Fit**. Expected: the chosen fit is applied.
- [ ] Change **Position**. Expected: the chosen position is applied.
- [ ] Change **Dim**. Expected: the chosen dim level is applied.

## Persistence

- [ ] Change settings and choose **Save to Configuration**. Expected: `background-media.ghostty` is written and the include line is added to the main config once.
- [ ] Restart with the isolated config. Expected: saved settings load from the managed file.
- [ ] Change settings and choose **Reset Changes**. Expected: panel values return to configuration values.
- [ ] Change the source and choose **Use Configuration**. Expected: the configured source is restored.

## Robustness

- [ ] In one session, switch through PNG image, GIF, local MP4, web MP4 fixture, live HLS fixture, YouTube video, and YouTube live. Expected: each type switches without restarting the app.
- [ ] While a YouTube URL is resolving, close and reopen the panel five times. Expected: no crash, playback starts, and the panel reopens.
- [ ] Type into the source box while the terminal is visible. Expected: typed text stays in the panel and does not reach the terminal.
