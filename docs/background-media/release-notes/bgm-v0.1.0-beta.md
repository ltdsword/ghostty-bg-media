# Ghostty Background Media bgm-v0.1.0-beta

Ghostty Background Media is an unofficial Ghostty fork that adds image, GIF, video, and livestream backgrounds to the Linux GTK terminal. It is not affiliated with or endorsed by the Ghostty project. This is a public pre-release / beta.

## Downloads

| Asset | For |
| --- | --- |
| [`ghostty-bg-media-bgm-v0.1.0-beta-amd64.deb`](https://github.com/ltdsword/ghostty-bg-media/releases/download/bgm-v0.1.0-beta/ghostty-bg-media-bgm-v0.1.0-beta-amd64.deb) | Ubuntu 26.04 amd64 |
| [`ghostty-bg-media-bgm-v0.1.0-beta-x86_64.flatpak`](https://github.com/ltdsword/ghostty-bg-media/releases/download/bgm-v0.1.0-beta/ghostty-bg-media-bgm-v0.1.0-beta-x86_64.flatpak) | Ubuntu 24.04 and other Linux distributions |
| [`SHA256SUMS`](https://github.com/ltdsword/ghostty-bg-media/releases/download/bgm-v0.1.0-beta/SHA256SUMS) | Checksums for release assets |
| [`ghostty-bg-media-bgm-v0.1.0-beta-manifest.txt`](https://github.com/ltdsword/ghostty-bg-media/releases/download/bgm-v0.1.0-beta/ghostty-bg-media-bgm-v0.1.0-beta-manifest.txt) | `.deb` build details |

### Ubuntu 26.04 amd64 (`.deb`)

Download the `.deb` and `SHA256SUMS` from the links above, then run these three commands to verify, install, and check the version:

```sh
sha256sum -c SHA256SUMS --ignore-missing
sudo apt install ./ghostty-bg-media-bgm-v0.1.0-beta-amd64.deb
ghostty-bg-media +version
```

### Ubuntu 24.04 and other Linux (`.flatpak`)

Download the Flatpak bundle and `SHA256SUMS` from the links above, then run these three commands to verify and install. The Flatpak runtime is downloaded from Flathub.

```sh
sha256sum -c SHA256SUMS --ignore-missing
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user ./ghostty-bg-media-bgm-v0.1.0-beta-x86_64.flatpak
```

See the [installation guide](../INSTALL.md) for configuration, upgrades, and removal.

## What's new on Linux

- PNG, JPEG, WebP, animated GIF, local MP4 (H.264/AAC), WebM and MKV backgrounds.
- Direct HTTP(S) MP4 and HLS, and YouTube videos and livestreams using user-installed `yt-dlp`.
- Fit, position, dim, blur, loop, pause, seek where supported, Go Live, optional sound, and pause-on-unfocus controls. One decoder is shared across tabs and splits; audio starts muted.
- The GTK panel's **Appearance** group now has a **Terminal opacity** slider. **Save to Configuration** stores its value in `background-media.ghostty`.
- Flatpak supports web-video audio when `background-media-volume` is above zero.
- D-026 fixes YouTube H.264 playback by correcting MPEG-TS continuity counters before demuxing.

Media appears through terminal background transparency. Set `background-opacity` below `1` or use the panel slider.

## Compatibility and testing

- `.deb`: clean install, upgrade, remove, and rollback were verified in an Ubuntu 26.04 amd64 container; the packaged GUI was checked on an Ubuntu 26.04 host.
- Flatpak: install, version command, libraries, H.264/HLS plugins, and uninstall were verified in a fresh Ubuntu 24.04.5 container. The GUI and audio were checked on an Ubuntu 26.04 host. A real Ubuntu 24.04 desktop session was not tested.
- XWayland works; native Xorg is untested.
- macOS behavior is unchanged and inherited background video remains in source. This release has no macOS binary; the macOS build and inherited-video smoke test are UNVERIFIED. macOS users can build from source using the [upstream docs](https://ghostty.org/docs) and [background video notes](../../../BACKGROUND_VIDEO.md).

## Optional dependencies and known limits

The `.deb` recommends GStreamer `good`, `bad`, and `libav` plugins for media formats. YouTube needs `yt-dlp` installed by the user; it is not bundled. YouTube format selection depends on what `yt-dlp` reports, so playback is best effort. URL playback uses software decoding.

## Changes since contributor baseline

Since contributor baseline `24fa0219908a`, this fork adds Linux background-media playback and its GTK panel, media controls and configuration, Linux packaging, and release documentation. The inherited macOS background video remains unchanged.

## Credits

Ghostty is by Mitchell Hashimoto and Ghostty contributors ([source](https://github.com/ghostty-org/ghostty), MIT license). The inherited macOS background video is by [locphamduc96](https://github.com/locphamduc96/ghostty). Linux background media in this fork is by ltdsword.
