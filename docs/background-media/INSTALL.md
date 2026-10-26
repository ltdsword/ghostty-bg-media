# Install Ghostty Background Media

Ghostty Background Media is a separate build of Ghostty with background media support. Choose the package for your Linux distribution.

## Downloads

The [bgm-v0.2.1-beta pre-release](https://github.com/ltdsword/ghostty-bg-media/releases/tag/bgm-v0.2.1-beta) provides these files. See [all releases](https://github.com/ltdsword/ghostty-bg-media/releases) for later versions.

| File | Use |
| --- | --- |
| [`.deb` package](https://github.com/ltdsword/ghostty-bg-media/releases/download/bgm-v0.2.1-beta/ghostty-bg-media-bgm-v0.2.1-beta-amd64.deb) (`ghostty-bg-media-bgm-v0.2.1-beta-amd64.deb`) | Ubuntu 26.04 amd64 |
| [Flatpak bundle](https://github.com/ltdsword/ghostty-bg-media/releases/download/bgm-v0.2.1-beta/ghostty-bg-media-bgm-v0.2.1-beta-x86_64.flatpak) (`ghostty-bg-media-bgm-v0.2.1-beta-x86_64.flatpak`) | Ubuntu 24.04 and other Linux distributions |
| [`SHA256SUMS`](https://github.com/ltdsword/ghostty-bg-media/releases/download/bgm-v0.2.1-beta/SHA256SUMS) | Checksums for release files |
| [`ghostty-bg-media-bgm-v0.2.1-beta-manifest.txt`](https://github.com/ltdsword/ghostty-bg-media/releases/download/bgm-v0.2.1-beta/ghostty-bg-media-bgm-v0.2.1-beta-manifest.txt) | Build details for the `.deb` |

To build packages from source, see [BUILDING.md](BUILDING.md).

## Which package

| Linux system | Package |
| --- | --- |
| Ubuntu 26.04, amd64 | `.deb` package |
| Ubuntu 24.04 or another Linux distribution | Flatpak bundle |

Ubuntu 24.04 does not have the GTK and libadwaita versions needed to build the native package. The Flatpak includes the GNOME 50 runtime from Flathub.

## Install (.deb)

Verify the downloaded package from the directory containing it and `SHA256SUMS`:

```sh
sha256sum -c SHA256SUMS --ignore-missing
```

Install the package:

```sh
sudo apt install ./ghostty-bg-media-bgm-v0.2.1-beta-amd64.deb
```

Open **Ghostty Background Media** from the app grid, or run `ghostty-bg-media` in a terminal.

## Install (Flatpak)

On Ubuntu, if Flatpak is not installed, install it first:

```sh
sudo apt install flatpak
```

Add Flathub for your user and install the downloaded bundle. The install pulls the GNOME 50 runtime from Flathub:

```sh
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user ./ghostty-bg-media-bgm-v0.2.1-beta-x86_64.flatpak
```

Run it from the app grid or with:

```sh
flatpak run io.github.ltdsword.GhosttyBgMedia
```

## First run and configuration

The `.deb` uses the normal Ghostty configuration file at `~/.config/ghostty/config`. The Flatpak uses `~/.var/app/io.github.ltdsword.GhosttyBgMedia/config/ghostty/config` because it has its own configuration directory. Add a media setting to the configuration file used by your installation, for example:

```conf
background-media = ~/Pictures/wallpaper.png
background-opacity = 0.7
```

Media is drawn behind the terminal and shows through only where the terminal background is transparent, so set `background-opacity` below `1`. You can also adjust the **Terminal opacity** slider in the panel's **Appearance** group. **Save to Configuration** writes `background-opacity` to `background-media.ghostty` next to the main config; this managed file loads after and overrides the main config value. See [CONFIGURATION.md](CONFIGURATION.md) for other settings and supported media.

The Flatpak can read media files under your home directory. Keep media you want to use inside your home folder.

The `.deb` and official Ghostty share the normal config file. Official Ghostty does not recognize `background-media*` settings and may warn about them.

## YouTube

YouTube playback needs `yt-dlp` installed on the host. The `.deb` recommends it; for Flatpak, install it on Ubuntu with:

```sh
sudo apt install yt-dlp
```

Flatpak runs the host's `yt-dlp` when resolving YouTube videos.

## Running next to official Ghostty

Ghostty Background Media installs as `ghostty-bg-media` and has its own application ID,
`io.github.ltdsword.GhosttyBgMedia`. It can be installed alongside official Ghostty, whose
Flatpak application ID is `com.mitchellh.ghostty`. It does not replace `/usr/bin/ghostty`, the
official desktop entry, or system terminfo.

## Upgrade

For the `.deb`, install the newer package the same way as the first install. For Flatpak, install the newer downloaded bundle with `flatpak install --user ./ghostty-bg-media-bgm-v0.2.1-beta-x86_64.flatpak` (replace the filename with the downloaded release asset).

## Uninstall

Remove the `.deb` and keep your user configuration and media:

```sh
sudo apt remove ghostty-bg-media
```

For Flatpak, remove the app and keep its configuration:

```sh
flatpak uninstall --user io.github.ltdsword.GhosttyBgMedia
```

Add `--delete-data` if you also want to remove its configuration under `~/.var/app`:

```sh
flatpak uninstall --user --delete-data io.github.ltdsword.GhosttyBgMedia
```

Removing either package leaves files in your home directory untouched.

## Troubleshooting

- **No video:** The `.deb` recommends GStreamer media plugins. If recommendations were disabled during installation, install `gstreamer1.0-plugins-good`, `gstreamer1.0-plugins-bad`, and `gstreamer1.0-libav`.
- **YouTube errors:** Install or update `yt-dlp` on the host. Flatpak uses the host copy.
- **Flatpak cannot open a media file:** Move or copy it under your home directory; the Flatpak only has read access to files there.
- **Shell-integration warning:** The warning appears because the host shell cannot read paths inside `/app`. The terminal still works.

## Verify downloads

Run `sha256sum -c SHA256SUMS --ignore-missing` in the directory containing the downloaded release files before installing.
