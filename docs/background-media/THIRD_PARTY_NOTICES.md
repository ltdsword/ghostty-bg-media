# Background media third-party notices

This inventory records the dependency and license facts measured for the Linux background-media
lanes on 2026-10-24. It is not legal advice.

| Component                                  | Version / license recorded                           | Lane and source                                                              | Redistribution note                                                                        |
| ------------------------------------------ | ---------------------------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| GTK                                        | 4.22.4; LGPL                                         | Native Ubuntu package                                                        | Dynamically supplied by the platform.                                                      |
| GStreamer core, base, good, bad, and libav | 1.28.2; LGPL-2+                                      | Native Ubuntu packages                                                       | Dynamically supplied; no media-related library is statically linked or bundled by Ghostty. |
| GStreamer                                  | Version not specified; LGPL                          | GNOME 50 Flatpak runtime                                                     | Runtime supplied, not bundled by Ghostty.                                                  |
| FFmpeg (`libavcodec62`)                    | 8.0.1; LGPL-2.1+ with GPL-2+ parts in Ubuntu's build | Native Ubuntu package stack                                                  | System package; the GPL-licensed parts of the Ubuntu build are noted here.                 |
| glycin                                     | 2.1.5; LGPL-2.1+ or MPL-2.0                          | Native image-loading stack / GNOME runtime                                   | Platform supplied.                                                                         |
| `org.freedesktop.Platform.codecs-extra`    | License not specified in this evidence               | Installed separately from Flathub by the Flatpak user for H.264/AAC decoding | Not shipped by Ghostty.                                                                    |
| yt-dlp                                     | Unlicense                                            | User-installed host executable; optional `GHOSTTY_YTDLP` override            | Not distributed by Ghostty.                                                                |
| gtk4-layer-shell                           | MIT                                                  | Named by the Flatpak manifest                                                | Manifest component; retain its applicable notice when redistributing it.                   |
| bzip2-redirect                             | License not specified in this evidence               | Named by the Flatpak manifest                                                | Check the component's own notice when redistributing it.                                   |
| Zig and pandoc                             | Build tools; license not specified in this evidence  | Named by the Flatpak manifest                                                | Build tools, not media runtime libraries.                                                  |
| Ghostty                                    | MIT                                                  | Application source                                                           | Retain the project license notice when redistributing Ghostty.                             |

## Lane notes

- **Native Ubuntu:** GStreamer and FFmpeg are dynamically supplied Ubuntu packages. Ubuntu's GTK
  also links GStreamer, so those libraries can appear in process mappings even with media disabled.
  Ghostty's own GStreamer use is through `dlopen`; Ghostty's `NEEDED` list has no GStreamer,
  libsoup, or AV libraries.
- **Flatpak:** The GNOME 50 runtime provides GStreamer. H.264/AAC decoding comes from Flathub's
  `org.freedesktop.Platform.codecs-extra`, installed separately and not shipped in Ghostty's app
  bundle. The manifest names Zig and pandoc as build tools, plus bzip2-redirect and
  gtk4-layer-shell (MIT).
- **Media dependencies:** Ghostty does not use libmpv. No media-related library is statically
  linked or bundled.
