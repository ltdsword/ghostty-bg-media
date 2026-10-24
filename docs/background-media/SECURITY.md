# Background media security

## Scope and threat model

The media layer processes untrusted remote media, remote HLS playlists, and output from
`yt-dlp`. It treats local files chosen by the user, the user's configuration, and the
`GHOSTTY_YTDLP` environment override as user trusted inputs. A URL is a desktop-client request made
by the user; private-network targets are allowed.

This documents the Linux GTK implementation and the 2026-10-24 audit. It is not a claim that
remote media is safe or that every media-library vulnerability is prevented.

## Policies

| Area                        | Policy                                                                                                                                                                                                                                     |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| URL schemes                 | Configured URLs and resolved `yt-dlp` format URLs must use HTTP or HTTPS. Other config schemes are rejected.                                                                                                                               |
| Redirects and network scope | An HTTP redirect to `file://` is rejected by libsoup. Private-network URLs remain allowed when user-chosen.                                                                                                                                |
| yt-dlp invocation           | Use an argv array without a shell: `--ignore-config --no-playlist --no-warnings --no-progress -J -- <url>`. Do not pass cookies or credentials. The executable is `yt-dlp` or the user-provided `GHOSTTY_YTDLP`, never derived from a URL. |
| yt-dlp resource bounds      | Cap stdout at 32 MiB and stderr at 64 KiB; stop resolution after 30 seconds. Timeout or oversized stdout kills the process group and reaps the child.                                                                                      |
| Flatpak subprocess          | Run the host command with `flatpak-spawn --host --watch-bus`.                                                                                                                                                                              |
| Media size                  | Image inputs are limited to 64 Mpixel and 256 MiB per file. GIF canvas size arithmetic is overflow-checked.                                                                                                                                |
| Logs                        | Redact URLs to scheme, host, port, and path, removing user information, query, and fragment. Do not log GStreamer error details containing `://`. YouTube logs contain the video ID and title only.                                        |

## Findings

| ID  | Severity | Finding                                                                                                                                                                         | Status                                                                                                                                          |
| --- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| F1  | Medium   | A resolver timeout or oversized output killed only the direct `yt-dlp` child. Descendants could keep stdout open, leave resolution hanging, and survive as orphans.             | Fixed in `f72a92ffc`: put yt-dlp in its own process group; kill the group and reap on timeout or oversized output.                              |
| F2  | Low      | A remote HLS playlist can name `file://` segments, which hlsdemux2 may read and display locally. No exfiltration path was found; `/dev/zero` failed fast without memory growth. | Open; documented limitation.                                                                                                                    |
| F3  | Low      | Resolved format URLs were not checked for their URL scheme.                                                                                                                     | Fixed in `f72a92ffc`: accept only HTTP(S) format URLs.                                                                                          |
| F4  | Low      | A `yt-dlp` process still running when Ghostty exits can continue until it ends.                                                                                                 | Open; Flatpak's `--watch-bus` handles the host command when its caller disappears, but a running process is not guaranteed to stop on app exit. |

Audit evidence: workspace `notes/m13/research-r1.md`; fault evidence: workspace
`notes/m13/fault-matrix.txt`.

## Reporting

Report suspected vulnerabilities in background media privately to the maintainers of this fork
(`ltdsword/ghostty-bg-media`) through GitHub private vulnerability reporting. Report issues in
unchanged upstream Ghostty code through upstream Ghostty's security channel. Include the affected version or commit, a minimal reproduction, and
sanitized logs. Remove private URLs, credentials, and personal data from reports and attachments.
