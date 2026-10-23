# Background-media HTTP fixtures

`http_fixture_server.py` starts an offline HTTP server for background-media network tests. It generates a finite MP4, VOD HLS files, and a reusable live HLS segment pool with the host `ffmpeg` executable. Generated media stays in a temporary directory unless `--media-dir` is supplied.

Requirements: Python 3 and `ffmpeg` with `libx264` support. Start the server with:

```sh
python3 test/background-media/http_fixture_server.py
```

The server binds to `127.0.0.1:8731` by default. Pass `--port` to change the port or `--media-dir DIR` to reuse generated media.

## Routes

Use these values with the `background-media=` setting:

| Route | Example |
| --- | --- |
| Finite MP4 with byte ranges: `/vod/v.mp4` | `background-media=http://127.0.0.1:8731/vod/v.mp4` |
| VOD HLS playlist and segments: `/hls/vod.m3u8` | `background-media=http://127.0.0.1:8731/hls/vod.m3u8` |
| VOD HLS segment: `/hls/<seg>.ts` | `background-media=http://127.0.0.1:8731/hls/vod000.ts` |
| Endless sliding live playlist: `/live/live.m3u8` | `background-media=http://127.0.0.1:8731/live/live.m3u8` |
| Status faults: `/status/<code>/<rest>` (`404`, `403`, `500`, `503`) | `background-media=http://127.0.0.1:8731/status/403/test` |
| Redirect: `/redirect/<rest>` | `background-media=http://127.0.0.1:8731/redirect/hls/vod.m3u8` |
| Throttled response: `/slow/<bytes-per-second>/<rest>` | `background-media=http://127.0.0.1:8731/slow/200000/vod/v.mp4` |
| Mid-body disconnect: `/drop/<bytes>/<rest>` | `background-media=http://127.0.0.1:8731/drop/1000/vod/v.mp4` |
| Timed outage control: `/control/outage?seconds=N` | `background-media=http://127.0.0.1:8731/control/outage?seconds=2` |
| Live segment pool: `/live/seg-<n>.ts` | `background-media=http://127.0.0.1:8731/live/seg-13.ts` |

For soak tests, start the fixture server with periodic outages. The first outage begins after 60 seconds and lasts 5 seconds:

```sh
python3 test/background-media/http_fixture_server.py --outage-every 60 --outage-length 5
```

This server is test-only and adds no runtime dependency to Ghostty.
