#!/usr/bin/env python3
"""Offline HTTP fixtures for background-media network tests."""

from __future__ import annotations

import argparse
import http.client
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


HOST = "127.0.0.1"
SEGMENT_COUNT = 10
SEGMENT_SECONDS = 2
LIVE_WINDOW = 5


@dataclass
class Response:
    status: int
    headers: dict[str, str]
    body: bytes


class MediaGenerationError(Exception):
    pass


def media_files_exist(media_dir: Path) -> bool:
    required = [media_dir / "v.mp4", media_dir / "vod.m3u8"]
    required.extend(media_dir / f"vod{index:03d}.ts" for index in range(SEGMENT_COUNT))
    required.extend(media_dir / f"live{index:03d}.ts" for index in range(SEGMENT_COUNT))
    return all(path.is_file() for path in required)


def run_ffmpeg(ffmpeg: str, args: list[str]) -> None:
    try:
        result = subprocess.run(
            [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", *args],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
    except OSError as error:
        raise MediaGenerationError(f"could not run ffmpeg: {error}") from error
    if result.returncode != 0:
        detail = result.stderr.strip() or f"exit code {result.returncode}"
        raise MediaGenerationError(f"ffmpeg failed: {detail}")


def generate_media(media_dir: Path) -> None:
    if media_files_exist(media_dir):
        return

    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise FileNotFoundError("ffmpeg is required to generate fixture media")

    media_dir.mkdir(parents=True, exist_ok=True)
    video = media_dir / "v.mp4"
    run_ffmpeg(
        ffmpeg,
        [
            "-f",
            "lavfi",
            "-i",
            "testsrc2=size=1280x720:rate=30",
            "-t",
            "20",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-g",
            "30",
            "-movflags",
            "+faststart",
            str(video),
        ],
    )
    run_ffmpeg(
        ffmpeg,
        [
            "-i",
            str(video),
            "-c",
            "copy",
            "-hls_time",
            "2",
            "-hls_list_size",
            "0",
            "-hls_playlist_type",
            "vod",
            "-hls_segment_filename",
            str(media_dir / "vod%03d.ts"),
            "-f",
            "hls",
            str(media_dir / "vod.m3u8"),
        ],
    )
    run_ffmpeg(
        ffmpeg,
        [
            "-i",
            str(video),
            "-c",
            "copy",
            "-f",
            "segment",
            "-segment_time",
            "2",
            "-segment_format",
            "mpegts",
            "-segment_start_number",
            "0",
            "-reset_timestamps",
            "1",
            str(media_dir / "live%03d.ts"),
        ],
    )
    if not media_files_exist(media_dir):
        raise MediaGenerationError("ffmpeg did not generate the expected media files")


class FixtureState:
    def __init__(self, outage_every: float = 0, outage_length: float = 0):
        self.started = time.monotonic()
        self.outage_every = outage_every
        self.outage_length = outage_length
        self.manual_outage_until = 0.0
        self.lock = threading.Lock()

    def start_manual_outage(self, seconds: float) -> None:
        with self.lock:
            self.manual_outage_until = max(self.manual_outage_until, time.monotonic() + seconds)

    def is_outage(self, path: str) -> bool:
        if path == "/control" or path.startswith("/control/"):
            return False

        now = time.monotonic()
        with self.lock:
            if now < self.manual_outage_until:
                return True

        if self.outage_every <= 0 or self.outage_length <= 0:
            return False
        elapsed = now - self.started
        if elapsed < self.outage_every:
            return False
        return (elapsed - self.outage_every) % self.outage_every < self.outage_length


class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(
        self,
        address: tuple[str, int],
        media_dir: Path,
        state: FixtureState,
    ):
        self.media_dir = media_dir
        self.fixture_state = state
        super().__init__(address, FixtureHandler)


class FixtureHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format: str, *_args: object) -> None:
        return

    def send_response(self, code: int, message: str | None = None) -> None:
        if self._request_status is None:
            self._request_status = str(code)
        super().send_response(code, message)

    def handle_one_request(self) -> None:
        self._request_status = None
        try:
            super().handle_one_request()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            port = self.client_address[1] if self.client_address else 0
            method = self.command or "-"
            path = self.path or "-"
            status = self._request_status or "DROP"
            print(f"{time.monotonic():.3f} {port} {method} {path} -> {status}", flush=True)

    def do_GET(self) -> None:
        self._dispatch(head=False)

    def do_HEAD(self) -> None:
        self._dispatch(head=True)

    def _dispatch(self, head: bool) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        path = parsed.path
        if head and path != "/vod/v.mp4":
            self.send_error(405)
            return

        if path.startswith("/control/"):
            if path == "/control/outage" and not head:
                self._control_outage(parsed.query)
            else:
                self._send(Response(404, {"Content-Type": "text/plain"}, b"not found\n"), head=head)
            return

        if self.server.fixture_state.is_outage(path):
            self._close_without_response("OUTAGE")
            return

        drop_match = re.fullmatch(r"/drop/(\d+)/(.*)", path)
        if drop_match:
            amount = int(drop_match.group(1))
            target = "/" + drop_match.group(2)
            response = self._resource(target, self.headers.get("Range"))
            self._drop_body(response, amount)
            return

        slow_match = re.fullmatch(r"/slow/(\d+)/(.*)", path)
        if slow_match:
            speed = int(slow_match.group(1))
            if speed <= 0:
                self._send(Response(400, {"Content-Type": "text/plain"}, b"invalid speed\n"), head=head)
                return
            target = "/" + slow_match.group(2)
            response = self._resource(target, self.headers.get("Range"))
            self._send(response, head=head, bytes_per_second=speed)
            return

        self._send(self._resource(path, self.headers.get("Range")), head=head)

    def _control_outage(self, query: str) -> None:
        values = urllib.parse.parse_qs(query).get("seconds", [])
        if len(values) != 1:
            self._send(Response(400, {"Content-Type": "text/plain"}, b"expected seconds=N\n"))
            return
        try:
            seconds = float(values[0])
        except ValueError:
            self._send(Response(400, {"Content-Type": "text/plain"}, b"invalid seconds\n"))
            return
        if seconds < 0:
            self._send(Response(400, {"Content-Type": "text/plain"}, b"invalid seconds\n"))
            return
        self.server.fixture_state.start_manual_outage(seconds)
        self._send(Response(200, {"Content-Type": "text/plain"}, b"ok\n"))

    def _resource(self, path: str, range_header: str | None) -> Response:
        media_dir = self.server.media_dir
        if path == "/vod/v.mp4":
            try:
                body = (media_dir / "v.mp4").read_bytes()
            except OSError:
                return Response(404, {"Content-Type": "text/plain"}, b"not found\n")
            return self._range_response(body, range_header, "video/mp4")

        if path == "/hls/vod.m3u8":
            return self._file_response(media_dir / "vod.m3u8", "application/vnd.apple.mpegurl")

        if re.fullmatch(r"/hls/vod\d{3}\.ts", path):
            name = path.rsplit("/", 1)[-1]
            return self._file_response(media_dir / name, "video/mp2t")

        if path == "/live/live.m3u8":
            sequence = int((time.monotonic() - self.server.fixture_state.started) // SEGMENT_SECONDS)
            lines = [
                "#EXTM3U",
                "#EXT-X-VERSION:3",
                "#EXT-X-TARGETDURATION:2",
                f"#EXT-X-MEDIA-SEQUENCE:{sequence}",
            ]
            for number in range(sequence, sequence + LIVE_WINDOW):
                if number > 0 and number % SEGMENT_COUNT == 0:
                    lines.append("#EXT-X-DISCONTINUITY")
                lines.extend(("#EXTINF:2.000,", f"seg-{number}.ts"))
            body = ("\n".join(lines) + "\n").encode()
            return Response(
                200,
                {
                    "Content-Type": "application/vnd.apple.mpegurl",
                    "Cache-Control": "no-cache",
                },
                body,
            )

        live_end_match = re.fullmatch(r"/live-end/(\d+)/live\.m3u8", path)
        if live_end_match:
            seconds = int(live_end_match.group(1))
            if not 1 <= seconds <= 86400:
                return Response(404, {"Content-Type": "text/plain"}, b"not found\n")
            elapsed = time.monotonic() - self.server.fixture_state.started
            sequence = int(min(elapsed, seconds) // SEGMENT_SECONDS)
            lines = [
                "#EXTM3U",
                "#EXT-X-VERSION:3",
                "#EXT-X-TARGETDURATION:2",
                f"#EXT-X-MEDIA-SEQUENCE:{sequence}",
            ]
            for number in range(sequence, sequence + LIVE_WINDOW):
                if number > 0 and number % SEGMENT_COUNT == 0:
                    lines.append("#EXT-X-DISCONTINUITY")
                lines.extend(("#EXTINF:2.000,", f"seg-{number}.ts"))
            if elapsed >= seconds:
                lines.append("#EXT-X-ENDLIST")
            body = ("\n".join(lines) + "\n").encode()
            return Response(
                200,
                {
                    "Content-Type": "application/vnd.apple.mpegurl",
                    "Cache-Control": "no-cache",
                },
                body,
            )

        live_match = re.fullmatch(r"/live/seg-(\d+)\.ts", path)
        if live_match:
            number = int(live_match.group(1)) % SEGMENT_COUNT
            return self._file_response(media_dir / f"live{number:03d}.ts", "video/mp2t")

        live_end_segment_match = re.fullmatch(r"/live-end/(\d+)/seg-(\d+)\.ts", path)
        if live_end_segment_match:
            seconds = int(live_end_segment_match.group(1))
            if not 1 <= seconds <= 86400:
                return Response(404, {"Content-Type": "text/plain"}, b"not found\n")
            number = int(live_end_segment_match.group(2)) % SEGMENT_COUNT
            return self._file_response(media_dir / f"live{number:03d}.ts", "video/mp2t")

        status_match = re.fullmatch(r"/status/(\d+)/(.*)", path)
        if status_match:
            code = int(status_match.group(1))
            if code not in (404, 403, 500, 503):
                return Response(404, {"Content-Type": "text/plain"}, b"not found\n")
            return Response(code, {"Content-Type": "text/plain"}, f"status {code}\n".encode())

        redirect_match = re.fullmatch(r"/redirect/(.*)", path)
        if redirect_match:
            return Response(
                302,
                {"Location": "/" + redirect_match.group(1), "Content-Type": "text/plain"},
                b"redirect\n",
            )

        return Response(404, {"Content-Type": "text/plain"}, b"not found\n")

    @staticmethod
    def _range_response(body: bytes, range_header: str | None, content_type: str) -> Response:
        headers = {"Content-Type": content_type, "Accept-Ranges": "bytes"}
        if range_header is None:
            return Response(200, headers, body)

        match = re.fullmatch(r"bytes=(\d+)-(\d*)", range_header.strip())
        if match is None:
            return Response(416, {**headers, "Content-Range": f"bytes */{len(body)}"}, b"bad range\n")
        start = int(match.group(1))
        end = int(match.group(2)) if match.group(2) else len(body) - 1
        if start >= len(body) or end < start:
            return Response(416, {**headers, "Content-Range": f"bytes */{len(body)}"}, b"bad range\n")
        end = min(end, len(body) - 1)
        return Response(
            206,
            {**headers, "Content-Range": f"bytes {start}-{end}/{len(body)}"},
            body[start : end + 1],
        )

    @staticmethod
    def _file_response(path: Path, content_type: str) -> Response:
        try:
            body = path.read_bytes()
        except OSError:
            return Response(404, {"Content-Type": "text/plain"}, b"not found\n")
        return Response(200, {"Content-Type": content_type}, body)

    def _send(self, response: Response, head: bool = False, bytes_per_second: int | None = None) -> None:
        self.send_response(response.status)
        for name, value in response.headers.items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(response.body)))
        if bytes_per_second is not None:
            self.send_header("Connection", "close")
            self.close_connection = True
        self.end_headers()
        if head:
            return

        if bytes_per_second is None:
            self.wfile.write(response.body)
            return

        started = time.monotonic()
        sent = 0
        while sent < len(response.body):
            chunk = response.body[sent : sent + 4096]
            self.wfile.write(chunk)
            self.wfile.flush()
            sent += len(chunk)
            delay = sent / bytes_per_second - (time.monotonic() - started)
            if delay > 0:
                time.sleep(delay)

    def _drop_body(self, response: Response, amount: int) -> None:
        self._request_status = "DROP"
        self.send_response(response.status)
        for name, value in response.headers.items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(response.body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        try:
            self.wfile.write(response.body[:amount])
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        try:
            self.connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.connection.close()

    def _close_without_response(self, status: str) -> None:
        self._request_status = status
        self.close_connection = True
        try:
            self.connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.connection.close()


def make_server(
    port: int,
    media_dir: Path,
    outage_every: float = 0,
    outage_length: float = 0,
) -> FixtureServer:
    return FixtureServer(
        (HOST, port),
        media_dir,
        FixtureState(outage_every, outage_length),
    )


def fetch(url: str, headers: dict[str, str] | None = None) -> tuple[int, object, bytes]:
    request = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, response.headers, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.headers, error.read()


def self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="ghostty-http-fixtures-") as temp_dir:
        media_dir = Path(temp_dir)
        generate_media(media_dir)
        server = make_server(0, media_dir)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://{HOST}:{server.server_address[1]}"
        try:
            status, headers, body = fetch(f"{base}/vod/v.mp4")
            assert status == 200 and int(headers["Content-Length"]) == len(body), "v.mp4 full response"

            status, headers, body = fetch(f"{base}/vod/v.mp4", {"Range": "bytes=0-99"})
            assert status == 206 and headers["Content-Range"].startswith("bytes 0-99/"), "Range response"
            assert len(body) == 100, "Range body length"

            status, _headers, _body = fetch(f"{base}/vod/v.mp4", {"Range": "bytes=999999999-"})
            assert status == 416, "bad Range response"

            status, _headers, body = fetch(f"{base}/hls/vod.m3u8")
            assert status == 200 and b"vod000.ts" in body, "VOD playlist lists segments"

            status, _headers, body = fetch(f"{base}/live/live.m3u8")
            sequence_match = re.search(rb"#EXT-X-MEDIA-SEQUENCE:(\d+)", body)
            assert status == 200 and sequence_match is not None, "live playlist has sequence"
            first_sequence = int(sequence_match.group(1))
            first_entries = [line for line in body.decode().splitlines() if line and not line.startswith("#")]
            assert len(first_entries) == LIVE_WINDOW, "live playlist has five entries"

            status, _headers, body = fetch(f"{base}/live-end/3/live.m3u8")
            assert status == 200 and b"#EXT-X-ENDLIST" not in body, "live-end starts without ENDLIST"
            time.sleep(3.5)
            status, _headers, body = fetch(f"{base}/live-end/3/live.m3u8")
            assert status == 200 and b"#EXT-X-ENDLIST" in body, "live-end ends after its deadline"
            ended_playlist = body
            status, _headers, body = fetch(f"{base}/live-end/3/live.m3u8")
            assert status == 200 and body == ended_playlist, "live-end playlist freezes"
            status, _headers, body = fetch(f"{base}/live-end/3/seg-13.ts")
            assert status == 200 and body == (media_dir / "live003.ts").read_bytes(), "live-end segment pool wraps"
            status, _headers, _body = fetch(f"{base}/live-end/0/live.m3u8")
            assert status == 404, "live-end rejects zero seconds"
            status, _headers, _body = fetch(f"{base}/live-end/86401/seg-0.ts")
            assert status == 404, "live-end rejects excessive seconds"

            time.sleep(2.2)
            status, _headers, body = fetch(f"{base}/live/live.m3u8")
            sequence_match = re.search(rb"#EXT-X-MEDIA-SEQUENCE:(\d+)", body)
            entries = [line for line in body.decode().splitlines() if line and not line.startswith("#")]
            assert status == 200 and sequence_match is not None, "live playlist advances"
            assert int(sequence_match.group(1)) > first_sequence and len(entries) == LIVE_WINDOW, "live window advances"

            status, _headers, body = fetch(f"{base}/live/seg-13.ts")
            assert status == 200 and body == (media_dir / "live003.ts").read_bytes(), "live segment pool wraps"

            status, _headers, _body = fetch(f"{base}/status/403/check")
            assert status == 403, "status fault"

            status, _headers, _body = fetch(f"{base}/redirect/hls/vod.m3u8")
            assert status == 200, "redirect reaches fixture resource"

            connection = http.client.HTTPConnection(HOST, server.server_address[1], timeout=10)
            connection.request("GET", "/drop/1000/vod/v.mp4")
            response = connection.getresponse()
            try:
                response.read()
            except http.client.IncompleteRead:
                pass
            else:
                raise AssertionError("drop response is incomplete")
            finally:
                connection.close()

            connection = http.client.HTTPConnection(HOST, server.server_address[1], timeout=10)
            started = time.monotonic()
            connection.request(
                "GET",
                "/slow/200000/vod/v.mp4",
                headers={"Range": "bytes=0-399999"},
            )
            response = connection.getresponse()
            slow_body = response.read()
            elapsed = time.monotonic() - started
            connection.close()
            assert response.status == 206 and len(slow_body) == 400000, "slow response body"
            assert elapsed >= 1.5, "slow response is throttled"

            status, _headers, body = fetch(f"{base}/control/outage?seconds=2")
            assert status == 200 and body.strip() == b"ok", "control starts outage"
            try:
                fetch(f"{base}/status/403/during-outage")
            except (OSError, http.client.HTTPException, urllib.error.URLError):
                pass
            else:
                raise AssertionError("outage request unexpectedly received a response")
            time.sleep(2.5)
            status, _headers, _body = fetch(f"{base}/hls/vod.m3u8")
            assert status == 200, "request succeeds after outage"
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8731)
    parser.add_argument("--media-dir", type=Path)
    parser.add_argument("--outage-every", type=float, default=0)
    parser.add_argument("--outage-length", type=float, default=0)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.port < 0 or args.port > 65535:
        parser.error("--port must be between 0 and 65535")
    if args.outage_every < 0 or args.outage_length < 0:
        parser.error("outage values cannot be negative")
    if (args.outage_every == 0) != (args.outage_length == 0):
        parser.error("--outage-every and --outage-length must both be 0 or both be positive")
    return args


def main() -> int:
    args = parse_args()
    if args.self_test:
        try:
            self_test()
        except FileNotFoundError as error:
            print(str(error), file=sys.stderr)
            return 2
        except Exception as error:
            print(f"SELFTEST FAIL: {error}", file=sys.stderr)
            return 1
        print("SELFTEST PASS")
        return 0

    if shutil.which("ffmpeg") is None:
        print("ffmpeg is required to generate fixture media", file=sys.stderr)
        return 2

    temp_dir: tempfile.TemporaryDirectory[str] | None = None
    try:
        if args.media_dir is None:
            temp_dir = tempfile.TemporaryDirectory(prefix="ghostty-http-fixtures-")
            media_dir = Path(temp_dir.name)
        else:
            media_dir = args.media_dir
        generate_media(media_dir)
        server = make_server(args.port, media_dir, args.outage_every, args.outage_length)
    except (MediaGenerationError, OSError) as error:
        print(str(error), file=sys.stderr)
        if temp_dir is not None:
            temp_dir.cleanup()
        return 1

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        if temp_dir is not None:
            temp_dir.cleanup()
    return 0


if __name__ == "__main__":
    sys.exit(main())
