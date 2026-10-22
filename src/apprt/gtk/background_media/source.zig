const std = @import("std");

pub const Kind = enum { local_file, http_direct, http_hls, youtube };

pub const MediaType = enum {
    unknown,
    image_png,
    image_jpeg,
    image_webp,
    image_gif,
    video_mp4,
    video_webm_mkv,
};

pub const sniff_len = 16;

pub fn classifyUrl(url: []const u8) ?Kind {
    const uri = std.Uri.parse(url) catch return null;
    if (!std.ascii.eqlIgnoreCase(uri.scheme, "http") and
        !std.ascii.eqlIgnoreCase(uri.scheme, "https")) return null;

    const host = if (uri.host) |component| component.percent_encoded else return null;
    if (isYoutubeHost(host)) return .youtube;
    if (std.mem.endsWith(u8, uri.path.percent_encoded, ".m3u8")) return .http_hls;
    return .http_direct;
}

fn isYoutubeHost(host: []const u8) bool {
    const hosts = .{
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "music.youtube.com",
        "youtu.be",
        "youtube-nocookie.com",
        "www.youtube-nocookie.com",
    };

    inline for (hosts) |youtube_host| {
        if (std.ascii.eqlIgnoreCase(host, youtube_host)) return true;
    }
    return false;
}

pub fn sniff(header: []const u8) MediaType {
    if (header.len >= 8 and std.mem.eql(u8, header[0..8], "\x89PNG\r\n\x1a\n")) return .image_png;
    if (header.len >= 3 and std.mem.eql(u8, header[0..3], "\xff\xd8\xff")) return .image_jpeg;
    if (header.len >= 6 and (std.mem.eql(u8, header[0..6], "GIF87a") or
        std.mem.eql(u8, header[0..6], "GIF89a"))) return .image_gif;
    if (header.len >= 12 and std.mem.eql(u8, header[0..4], "RIFF") and
        std.mem.eql(u8, header[8..12], "WEBP")) return .image_webp;
    if (header.len >= 8 and std.mem.eql(u8, header[4..8], "ftyp")) return .video_mp4;
    if (header.len >= 4 and std.mem.eql(u8, header[0..4], "\x1a\x45\xdf\xa3")) return .video_webm_mkv;
    return .unknown;
}

pub fn fromExtension(path: []const u8) MediaType {
    const extension = std.fs.path.extension(path);
    if (std.ascii.eqlIgnoreCase(extension, ".png")) return .image_png;
    if (std.ascii.eqlIgnoreCase(extension, ".jpg") or std.ascii.eqlIgnoreCase(extension, ".jpeg")) return .image_jpeg;
    if (std.ascii.eqlIgnoreCase(extension, ".webp")) return .image_webp;
    if (std.ascii.eqlIgnoreCase(extension, ".gif")) return .image_gif;
    if (std.ascii.eqlIgnoreCase(extension, ".mp4") or std.ascii.eqlIgnoreCase(extension, ".m4v") or
        std.ascii.eqlIgnoreCase(extension, ".mov")) return .video_mp4;
    if (std.ascii.eqlIgnoreCase(extension, ".webm") or std.ascii.eqlIgnoreCase(extension, ".mkv")) return .video_webm_mkv;
    return .unknown;
}

test "URL classification covers source kinds and media URLs" {
    try std.testing.expectEqual(Kind.local_file, .local_file);

    const youtube_urls = [_][]const u8{
        "https://youtube.com/watch?v=abc",
        "https://www.youtube.com/watch?v=abc",
        "https://m.youtube.com/watch?v=abc",
        "https://music.youtube.com/watch?v=abc",
        "https://youtu.be/abc",
        "https://youtube-nocookie.com/embed/abc",
        "https://www.youtube-nocookie.com/embed/abc",
        "HTTPS://YOUTU.BE/x",
        "https://www.youtube.com/live/abc",
    };
    for (youtube_urls) |url| {
        try std.testing.expectEqual(@as(?Kind, .youtube), classifyUrl(url));
    }

    try std.testing.expectEqual(@as(?Kind, .http_hls), classifyUrl("https://cdn.example/a.m3u8?token=1"));
    try std.testing.expectEqual(@as(?Kind, .http_direct), classifyUrl("https://e.com/v.mp4"));
    try std.testing.expectEqual(@as(?Kind, .http_direct), classifyUrl("http://example.com/media"));
    try std.testing.expectEqual(@as(?Kind, .http_direct), classifyUrl("https://youtube.com.evil.example/watch"));
    try std.testing.expectEqual(@as(?Kind, null), classifyUrl("not a url"));
    try std.testing.expectEqual(@as(?Kind, null), classifyUrl("file:///tmp/video.mp4"));
}

test "sniff recognizes supported media signatures" {
    try std.testing.expectEqual(MediaType.image_png, sniff("\x89PNG\r\n\x1a\n"));
    try std.testing.expectEqual(MediaType.image_jpeg, sniff("\xff\xd8\xff\x00"));
    try std.testing.expectEqual(MediaType.image_jpeg, sniff("\xff\xd8\xff"));
    try std.testing.expectEqual(MediaType.image_gif, sniff("GIF87a"));
    try std.testing.expectEqual(MediaType.image_gif, sniff("GIF89a"));
    try std.testing.expectEqual(MediaType.image_webp, sniff("RIFF\x00\x00\x00\x00WEBP"));
    try std.testing.expectEqual(MediaType.video_mp4, sniff("\x00\x00\x00\x00ftypisom"));
    try std.testing.expectEqual(MediaType.video_mp4, sniff("\x00\x00\x00\x00ftypqt  "));
    try std.testing.expectEqual(MediaType.video_webm_mkv, sniff("\x1a\x45\xdf\xa3\x00"));
    try std.testing.expectEqual(MediaType.unknown, sniff("unrecognized"));
}

test "sniff handles truncated headers without reading past them" {
    const headers = [_][]const u8{
        "\x89PNG\r\n\x1a\n",
        "\xff\xd8\xff\x00",
        "GIF89a",
        "RIFF\x00\x00\x00\x00WEBP",
        "\x00\x00\x00\x00ftypisom",
        "\x1a\x45\xdf\xa3",
    };

    for (headers) |header| {
        for (0..3) |length| {
            try std.testing.expectEqual(MediaType.unknown, sniff(header[0..length]));
        }
    }

    try std.testing.expectEqual(MediaType.unknown, sniff("\x89PN"));
    try std.testing.expectEqual(MediaType.unknown, sniff("GIF"));
    try std.testing.expectEqual(MediaType.unknown, sniff("RIF"));
    try std.testing.expectEqual(MediaType.unknown, sniff("\x00\x00\x00"));
    try std.testing.expectEqual(MediaType.unknown, sniff("\x1a\x45\xdf"));
}

test "extension fallback recognizes supported extensions" {
    try std.testing.expectEqual(MediaType.image_png, fromExtension("image.png"));
    try std.testing.expectEqual(MediaType.image_jpeg, fromExtension("image.jpg"));
    try std.testing.expectEqual(MediaType.image_jpeg, fromExtension("image.jpeg"));
    try std.testing.expectEqual(MediaType.image_webp, fromExtension("image.webp"));
    try std.testing.expectEqual(MediaType.image_gif, fromExtension("image.gif"));
    try std.testing.expectEqual(MediaType.video_mp4, fromExtension("video.mp4"));
    try std.testing.expectEqual(MediaType.video_mp4, fromExtension("video.m4v"));
    try std.testing.expectEqual(MediaType.video_mp4, fromExtension("video.mov"));
    try std.testing.expectEqual(MediaType.video_webm_mkv, fromExtension("video.webm"));
    try std.testing.expectEqual(MediaType.video_webm_mkv, fromExtension("video.mkv"));
    try std.testing.expectEqual(MediaType.video_mp4, fromExtension("video.MP4"));
    try std.testing.expectEqual(MediaType.unknown, fromExtension("video.avi"));
}
