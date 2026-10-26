# Ghostty Background Media bgm-v0.2.1-beta

Ghostty Background Media is an unofficial Ghostty fork that adds image, GIF, video, and livestream backgrounds to the Linux GTK terminal. It is not affiliated with or endorsed by the Ghostty project. This is a public pre-release / beta.

## Downloads

| Asset | For |
| --- | --- |
| [`ghostty-bg-media-bgm-v0.2.1-beta-amd64.deb`](https://github.com/ltdsword/ghostty-bg-media/releases/download/bgm-v0.2.1-beta/ghostty-bg-media-bgm-v0.2.1-beta-amd64.deb) | Ubuntu 26.04 amd64 |
| [`ghostty-bg-media-bgm-v0.2.1-beta-x86_64.flatpak`](https://github.com/ltdsword/ghostty-bg-media/releases/download/bgm-v0.2.1-beta/ghostty-bg-media-bgm-v0.2.1-beta-x86_64.flatpak) | Ubuntu 24.04 and other Linux distributions |
| [`SHA256SUMS`](https://github.com/ltdsword/ghostty-bg-media/releases/download/bgm-v0.2.1-beta/SHA256SUMS) | Checksums for release assets |
| [`ghostty-bg-media-bgm-v0.2.1-beta-manifest.txt`](https://github.com/ltdsword/ghostty-bg-media/releases/download/bgm-v0.2.1-beta/ghostty-bg-media-bgm-v0.2.1-beta-manifest.txt) | `.deb` build details |

### Ubuntu 26.04 amd64 (`.deb`)

Download the `.deb` and `SHA256SUMS` from the links above, then run these three commands to verify, install, and check the version:

```sh
sha256sum -c SHA256SUMS --ignore-missing
sudo apt install ./ghostty-bg-media-bgm-v0.2.1-beta-amd64.deb
ghostty-bg-media +version
```

### Ubuntu 24.04 and other Linux (`.flatpak`)

Download the Flatpak bundle and `SHA256SUMS` from the links above, then run these three commands to verify and install. The Flatpak runtime is downloaded from Flathub.

```sh
sha256sum -c SHA256SUMS --ignore-missing
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user ./ghostty-bg-media-bgm-v0.2.1-beta-x86_64.flatpak
```

See the [installation guide](../INSTALL.md) for configuration, upgrades, and removal.

## What's new on Linux

- **Fixed in 0.2.1:** round box mode no longer draws an outlined pill around every word highlight, panel widget
  or tab; it rounds only the outer corners of each coloured area. bgm-v0.2.0-beta had the old drawing.
- **Boxes:** `background-media-box-opacity` (0–1) makes rows with their own background colour (prompt highlights, diff lines) translucent over the media; `background-media-box-round = true` draws them with rounded corners. Panel: **Boxes** slider, **Round box corners** switch. Defaults keep the old look.
- **YouTube playlists:** links with `list=` (including Mix links) play in order, 3 s between videos, start over when Loop is on, otherwise stop. Panel **Playlist** row with Previous/Next.

Media appears through terminal background transparency. Set `background-opacity` below `1` or use the panel slider.

Upgrading from bgm-v0.1.0-beta or bgm-v0.2.0-beta: install the new `.deb` or Flatpak the same way; your settings are kept.

## Compatibility and testing

- `.deb`: clean install, upgrade, remove, and rollback were verified in an Ubuntu 26.04 amd64 container; the packaged GUI was checked on an Ubuntu 26.04 host.
- Flatpak: install, version command, libraries, H.264/HLS plugins, and uninstall were verified in a fresh Ubuntu 24.04.5 container. The GUI and audio were checked on an Ubuntu 26.04 host. A real Ubuntu 24.04 desktop session was not tested.
- XWayland works; native Xorg is untested.
- macOS behavior is unchanged and inherited background video remains in source. This release has no macOS binary; the macOS build and inherited-video smoke test are UNVERIFIED. macOS users can build from source using the [upstream docs](https://ghostty.org/docs) and [background video notes](../../../BACKGROUND_VIDEO.md).

## Optional dependencies and known limits

The `.deb` recommends GStreamer `good`, `bad`, and `libav` plugins for media formats. YouTube needs `yt-dlp` installed by the user; it is not bundled. YouTube format selection depends on what `yt-dlp` reports, so playback is best effort. URL playback uses software decoding. Playlist playback through several real YouTube videos is only tested with a local test playlist so far.

## Changes since contributor baseline

Since contributor baseline `24fa0219908a`, this fork adds Linux background-media playback and its GTK panel, media controls and configuration, Linux packaging, and release documentation. The inherited macOS background video remains unchanged.

## Credits

Ghostty is by Mitchell Hashimoto and Ghostty contributors ([source](https://github.com/ghostty-org/ghostty), MIT license). The inherited macOS background video is by [locphamduc96](https://github.com/locphamduc96/ghostty). Linux background media in this fork is by ltdsword.
