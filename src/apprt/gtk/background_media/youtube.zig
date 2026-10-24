const std = @import("std");
const source = @import("source.zig");

pub const LiveStatus = enum { recorded, live, upcoming };

pub const Fatal = enum {
    private,
    age_restricted,
    members_only,
    drm,
    upcoming,
    invalid_url,
    unavailable,
    playlist_unsupported,
    no_playable_format,
    bad_json,
};

pub const StderrClass = union(enum) {
    retriable,
    fatal: Fatal,
};

pub const ResolveError = error{
    BadJson,
    PlaylistUnsupported,
    Upcoming,
    NoPlayableFormat,
};

pub const ResolveErrors = std.mem.Allocator.Error || ResolveError;

pub const default_max_height: u32 = 720;

pub const Info = struct {
    id: []const u8,
    title: []const u8,
    live: LiveStatus,
    url: []const u8,
    url_kind: source.Kind,
    format_id: []const u8,
    height: u32,
    fps: f64,
    has_audio: bool,
};

pub const Raw = struct {
    _type: ?[]const u8 = null,
    id: ?[]const u8 = null,
    title: ?[]const u8 = null,
    live_status: ?[]const u8 = null,
    is_live: ?bool = null,
    duration: ?f64 = null,
    formats: ?[]RawFormat = null,

    pub const RawFormat = struct {
        format_id: ?[]const u8 = null,
        url: ?[]const u8 = null,
        protocol: ?[]const u8 = null,
        vcodec: ?[]const u8 = null,
        acodec: ?[]const u8 = null,
        height: ?u32 = null,
        fps: ?f64 = null,
        ext: ?[]const u8 = null,
    };
};

pub const Resolved = struct {
    parsed: std.json.Parsed(Raw),
    info: Info,

    pub fn deinit(self: *Resolved) void {
        self.parsed.deinit();
    }
};

pub fn isYoutubeUrl(url: []const u8) bool {
    return source.classifyUrl(url) == .youtube;
}

pub fn argv(
    buf: *[12][]const u8,
    url: []const u8,
    override: ?[]const u8,
    in_flatpak: bool,
) []const []const u8 {
    var len: usize = 0;
    if (in_flatpak) {
        buf[len] = "flatpak-spawn";
        len += 1;
        buf[len] = "--host";
        len += 1;
        buf[len] = "--watch-bus";
        len += 1;
    }

    buf[len] = override orelse "yt-dlp";
    len += 1;
    inline for (.{ "--ignore-config", "--no-playlist", "--no-warnings", "--no-progress", "-J", "--" }) |arg| {
        buf[len] = arg;
        len += 1;
    }
    buf[len] = url;
    len += 1;
    return buf[0..len];
}

pub fn resolve(
    alloc: std.mem.Allocator,
    json: []const u8,
    max_height: u32,
    fps_cap: u32,
) ResolveErrors!Resolved {
    const parsed = std.json.parseFromSlice(Raw, alloc, json, .{
        .ignore_unknown_fields = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.BadJson,
    };
    errdefer parsed.deinit();

    const raw = parsed.value;
    if (raw._type != null and std.mem.eql(u8, raw._type.?, "playlist")) {
        return error.PlaylistUnsupported;
    }

    const live = liveStatus(raw.live_status, raw.is_live);
    const formats: []const Raw.RawFormat = raw.formats orelse &.{};
    const chosen = chooseFormat(formats, max_height, fps_cap) orelse {
        return if (live == .upcoming) error.Upcoming else error.NoPlayableFormat;
    };
    const format = formats[chosen];
    const protocol = format.protocol.?;
    const has_audio = hasAudio(format.acodec);

    return .{
        .parsed = parsed,
        .info = .{
            .id = raw.id orelse "",
            .title = raw.title orelse "",
            .live = live,
            .url = format.url.?,
            .url_kind = if (isHls(protocol)) .http_hls else .http_direct,
            .format_id = format.format_id orelse "",
            .height = format.height.?,
            .fps = format.fps orelse 0,
            .has_audio = has_audio,
        },
    };
}

pub fn fatalOf(err: ResolveError) Fatal {
    return switch (err) {
        error.BadJson => .bad_json,
        error.PlaylistUnsupported => .playlist_unsupported,
        error.Upcoming => .upcoming,
        error.NoPlayableFormat => .no_playable_format,
    };
}

pub fn classifyStderr(stderr: []const u8) StderrClass {
    if (containsIgnoreCase(stderr, "private video")) return .{ .fatal = .private };
    if (containsIgnoreCase(stderr, "sign in to confirm your age") or
        containsIgnoreCase(stderr, "age-restricted")) return .{ .fatal = .age_restricted };
    if (containsIgnoreCase(stderr, "members-only") or
        containsIgnoreCase(stderr, "join this channel")) return .{ .fatal = .members_only };
    if (containsIgnoreCase(stderr, "drm")) return .{ .fatal = .drm };
    if (containsIgnoreCase(stderr, "will begin") or
        containsIgnoreCase(stderr, "premieres in")) return .{ .fatal = .upcoming };
    if (containsIgnoreCase(stderr, "unsupported url")) return .{ .fatal = .invalid_url };
    if (containsIgnoreCase(stderr, "video unavailable") or
        containsIgnoreCase(stderr, "not available")) return .{ .fatal = .unavailable };
    return .retriable;
}

fn liveStatus(live_status: ?[]const u8, is_live: ?bool) LiveStatus {
    if (is_live == true) return .live;
    if (live_status) |status| {
        if (std.mem.eql(u8, status, "is_live")) return .live;
        if (std.mem.eql(u8, status, "is_upcoming")) return .upcoming;
    }
    return .recorded;
}

fn chooseFormat(formats: []const Raw.RawFormat, max_height: u32, fps_cap: u32) ?usize {
    for (0..4) |tier| {
        var best: ?usize = null;
        for (formats, 0..) |format, index| {
            if (!eligible(format, max_height)) continue;
            const format_tier = tierOf(format) orelse continue;
            if (format_tier != tier) continue;
            if (best) |best_index| {
                if (!isBetter(format, formats[best_index], fps_cap)) continue;
            }
            best = index;
        }
        if (best) |index| return index;
    }
    return null;
}

fn eligible(format: Raw.RawFormat, max_height: u32) bool {
    const url = format.url orelse return false;
    if (url.len == 0) return false;
    if (!std.ascii.startsWithIgnoreCase(url, "https://") and
        !std.ascii.startsWithIgnoreCase(url, "http://")) return false;
    const codec = format.vcodec orelse return false;
    if (std.mem.eql(u8, codec, "none")) return false;
    if (!std.mem.startsWith(u8, codec, "avc1") and
        !std.mem.startsWith(u8, codec, "vp09") and
        !std.mem.startsWith(u8, codec, "vp9")) return false;
    const protocol = format.protocol orelse return false;
    if (!isHls(protocol) and !std.mem.eql(u8, protocol, "https")) return false;
    const height = format.height orelse return false;
    return height <= max_height;
}

fn tierOf(format: Raw.RawFormat) ?usize {
    const protocol = format.protocol orelse return null;
    const has_audio = hasAudio(format.acodec);
    if (isHls(protocol) and has_audio) return 0;
    if (std.mem.eql(u8, protocol, "https") and has_audio) return 1;
    if (std.mem.eql(u8, protocol, "https") and !has_audio) return 2;
    if (isHls(protocol) and !has_audio) return 3;
    return null;
}

fn isBetter(candidate: Raw.RawFormat, current: Raw.RawFormat, fps_cap: u32) bool {
    const candidate_height = candidate.height.?;
    const current_height = current.height.?;
    if (candidate_height != current_height) return candidate_height > current_height;

    const candidate_fps = candidate.fps orelse 0;
    const current_fps = current.fps orelse 0;
    if (fps_cap > 0) {
        const cap = @as(f64, @floatFromInt(fps_cap));
        const candidate_within_cap = candidate_fps <= cap;
        const current_within_cap = current_fps <= cap;
        if (candidate_within_cap != current_within_cap) return candidate_within_cap;
    }
    return candidate_fps < current_fps;
}

fn hasAudio(acodec: ?[]const u8) bool {
    const codec = acodec orelse return false;
    return !std.mem.eql(u8, codec, "none");
}

fn isHls(protocol: []const u8) bool {
    return std.mem.eql(u8, protocol, "m3u8") or std.mem.eql(u8, protocol, "m3u8_native");
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(haystack, needle) != null;
}

test "argv builds yt-dlp arguments for normal and Flatpak execution" {
    const url = "https://youtube.com/watch?v=abc";
    const expected_plain = [_][]const u8{
        "yt-dlp", "--ignore-config", "--no-playlist", "--no-warnings", "--no-progress", "-J", "--", url,
    };
    const expected_override = [_][]const u8{
        "/custom/yt-dlp", "--ignore-config", "--no-playlist", "--no-warnings", "--no-progress", "-J", "--", url,
    };
    const expected_flatpak = [_][]const u8{
        "flatpak-spawn", "--host", "--watch-bus", "yt-dlp", "--ignore-config", "--no-playlist", "--no-warnings", "--no-progress", "-J", "--", url,
    };
    const expected_flatpak_override = [_][]const u8{
        "flatpak-spawn", "--host", "--watch-bus", "/custom/yt-dlp", "--ignore-config", "--no-playlist", "--no-warnings", "--no-progress", "-J", "--", url,
    };
    var buf: [12][]const u8 = undefined;

    try std.testing.expectEqualSlices([]const u8, &expected_plain, argv(&buf, url, null, false));
    try std.testing.expectEqualSlices([]const u8, &expected_override, argv(&buf, url, "/custom/yt-dlp", false));
    try std.testing.expectEqualSlices([]const u8, &expected_flatpak, argv(&buf, url, null, true));
    try std.testing.expectEqualSlices([]const u8, &expected_flatpak_override, argv(&buf, url, "/custom/yt-dlp", true));
}

test "YouTube URL check only accepts classified YouTube URLs" {
    try std.testing.expect(isYoutubeUrl("https://www.youtube.com/watch?v=abc"));
    try std.testing.expect(!isYoutubeUrl("https://example.com/video.mp4"));
    try std.testing.expect(!isYoutubeUrl("not a URL"));
}

test "resolve classifies live status values" {
    const cases = [_]struct {
        json: []const u8,
        expected: LiveStatus,
    }{
        .{ .json = "{\"live_status\":\"is_live\",\"formats\":[{\"url\":\"https://cdn.example/live\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"height\":360}]}", .expected = .live },
        .{ .json = "{\"is_live\":true,\"formats\":[{\"url\":\"https://cdn.example/live\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"height\":360}]}", .expected = .live },
        .{ .json = "{\"live_status\":\"is_upcoming\",\"formats\":[{\"url\":\"https://cdn.example/live\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"height\":360}]}", .expected = .upcoming },
        .{ .json = "{\"live_status\":\"not_live\",\"formats\":[{\"url\":\"https://cdn.example/live\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"height\":360}]}", .expected = .recorded },
        .{ .json = "{\"live_status\":\"was_live\",\"formats\":[{\"url\":\"https://cdn.example/live\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"height\":360}]}", .expected = .recorded },
        .{ .json = "{\"live_status\":\"post_live\",\"formats\":[{\"url\":\"https://cdn.example/live\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"height\":360}]}", .expected = .recorded },
        .{ .json = "{\"live_status\":null,\"formats\":[{\"url\":\"https://cdn.example/live\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"height\":360}]}", .expected = .recorded },
        .{ .json = "{\"formats\":[{\"url\":\"https://cdn.example/live\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"height\":360}]}", .expected = .recorded },
    };

    for (cases) |case| {
        var resolved = try resolve(std.testing.allocator, case.json, default_max_height, 0);
        defer resolved.deinit();
        try std.testing.expectEqual(case.expected, resolved.info.live);
    }
}

test "resolve reports playlist and malformed JSON errors" {
    try std.testing.expectError(error.PlaylistUnsupported, resolve(std.testing.allocator, "{\"_type\":\"playlist\"}", default_max_height, 0));
    try std.testing.expectError(error.BadJson, resolve(std.testing.allocator, "not json", default_max_height, 0));
    try std.testing.expectEqual(Fatal.playlist_unsupported, fatalOf(error.PlaylistUnsupported));
    try std.testing.expectEqual(Fatal.bad_json, fatalOf(error.BadJson));
}

test "format tiers prefer HLS audio, then HTTPS audio, then HTTPS video, then HLS video" {
    const hls_json = "{\"formats\":[{\"format_id\":\"hls\",\"url\":\"https://cdn.example/hls\",\"protocol\":\"m3u8_native\",\"vcodec\":\"avc1\",\"acodec\":\"aac\",\"height\":360},{\"format_id\":\"https\",\"url\":\"https://cdn.example/direct\",\"protocol\":\"https\",\"vcodec\":\"vp09\",\"acodec\":\"opus\",\"height\":720}]}";
    var hls = try resolve(std.testing.allocator, hls_json, default_max_height, 0);
    defer hls.deinit();
    try std.testing.expectEqualStrings("hls", hls.info.format_id);
    try std.testing.expectEqual(source.Kind.http_hls, hls.info.url_kind);

    const https_json = "{\"formats\":[{\"format_id\":\"video\",\"url\":\"https://cdn.example/video\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"acodec\":\"none\",\"height\":720},{\"format_id\":\"audio\",\"url\":\"https://cdn.example/audio\",\"protocol\":\"https\",\"vcodec\":\"vp9\",\"acodec\":\"opus\",\"height\":360}]}";
    var https = try resolve(std.testing.allocator, https_json, default_max_height, 0);
    defer https.deinit();
    try std.testing.expectEqualStrings("audio", https.info.format_id);
    try std.testing.expectEqual(source.Kind.http_direct, https.info.url_kind);

    const video_json = "{\"formats\":[{\"format_id\":\"video\",\"url\":\"https://cdn.example/video\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"acodec\":\"none\",\"height\":720}]}";
    var video = try resolve(std.testing.allocator, video_json, default_max_height, 0);
    defer video.deinit();
    try std.testing.expectEqualStrings("video", video.info.format_id);
    try std.testing.expect(!video.info.has_audio);

    const video_priority_json = "{\"formats\":[{\"format_id\":\"hls-video\",\"url\":\"https://cdn.example/hls-video.m3u8\",\"protocol\":\"m3u8_native\",\"vcodec\":\"avc1\",\"acodec\":\"none\",\"height\":720},{\"format_id\":\"https-video\",\"url\":\"https://cdn.example/https-video\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"acodec\":\"none\",\"height\":720}]}";
    var video_priority = try resolve(std.testing.allocator, video_priority_json, default_max_height, 0);
    defer video_priority.deinit();
    try std.testing.expectEqualStrings("https-video", video_priority.info.format_id);
}

test "live HLS without audio resolves" {
    const json = "{\"live_status\":\"is_live\",\"formats\":[{\"format_id\":\"232\",\"url\":\"https://cdn.example/live.m3u8\",\"protocol\":\"m3u8_native\",\"vcodec\":\"avc1.4D401F\",\"acodec\":\"none\",\"height\":720},{\"format_id\":\"270\",\"url\":\"https://cdn.example/1080.m3u8\",\"protocol\":\"m3u8_native\",\"vcodec\":\"avc1.640028\",\"acodec\":\"none\",\"height\":1080}]}";
    var resolved = try resolve(std.testing.allocator, json, default_max_height, 0);
    defer resolved.deinit();
    try std.testing.expectEqualStrings("232", resolved.info.format_id);
    try std.testing.expectEqual(source.Kind.http_hls, resolved.info.url_kind);
    try std.testing.expect(!resolved.info.has_audio);
    try std.testing.expectEqual(LiveStatus.live, resolved.info.live);
}

test "format selection excludes unsupported codecs and excessive height" {
    const json = "{\"formats\":[{\"format_id\":\"av01\",\"url\":\"https://cdn.example/av01\",\"protocol\":\"https\",\"vcodec\":\"av01.0\",\"acodec\":\"aac\",\"height\":720},{\"format_id\":\"too-tall\",\"url\":\"https://cdn.example/tall\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"acodec\":\"aac\",\"height\":1080},{\"format_id\":\"valid\",\"url\":\"https://cdn.example/valid\",\"protocol\":\"https\",\"vcodec\":\"vp09.00\",\"acodec\":\"aac\",\"height\":720}]}";
    var resolved = try resolve(std.testing.allocator, json, default_max_height, 0);
    defer resolved.deinit();
    try std.testing.expectEqualStrings("valid", resolved.info.format_id);
}

test "format selection uses the fps cap and then the lower fps" {
    const json = "{\"formats\":[{\"format_id\":\"60\",\"url\":\"https://cdn.example/60\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"acodec\":\"aac\",\"height\":720,\"fps\":60},{\"format_id\":\"30\",\"url\":\"https://cdn.example/30\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"acodec\":\"aac\",\"height\":720,\"fps\":30}]}";

    var capped = try resolve(std.testing.allocator, json, default_max_height, 30);
    defer capped.deinit();
    try std.testing.expectEqualStrings("30", capped.info.format_id);

    var uncapped = try resolve(std.testing.allocator, json, default_max_height, 0);
    defer uncapped.deinit();
    try std.testing.expectEqualStrings("30", uncapped.info.format_id);
}

test "resolve tolerates missing and null fields" {
    const json = "{\"id\":null,\"title\":null,\"live_status\":null,\"is_live\":null,\"duration\":null,\"unknown\":\"ignored\",\"formats\":[{\"format_id\":null,\"url\":\"https://cdn.example/video\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"acodec\":null,\"height\":360,\"fps\":null,\"ext\":null,\"unknown\":1}]}";
    var resolved = try resolve(std.testing.allocator, json, default_max_height, 0);
    defer resolved.deinit();
    try std.testing.expectEqualStrings("", resolved.info.id);
    try std.testing.expectEqualStrings("", resolved.info.title);
    try std.testing.expectEqualStrings("", resolved.info.format_id);
    try std.testing.expectEqual(@as(f64, 0), resolved.info.fps);
    try std.testing.expect(!resolved.info.has_audio);
}

test "resolve reports upcoming when no format is playable" {
    try std.testing.expectError(error.Upcoming, resolve(std.testing.allocator, "{\"live_status\":\"is_upcoming\"}", default_max_height, 0));
    try std.testing.expectEqual(Fatal.upcoming, fatalOf(error.Upcoming));
    try std.testing.expectError(error.NoPlayableFormat, resolve(std.testing.allocator, "{}", default_max_height, 0));
    try std.testing.expectEqual(Fatal.no_playable_format, fatalOf(error.NoPlayableFormat));
}

test "format selection rejects non-HTTP format URLs" {
    const file_json = "{\"formats\":[{\"url\":\"file:///etc/passwd\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"height\":360}]}";
    try std.testing.expectError(error.NoPlayableFormat, resolve(std.testing.allocator, file_json, default_max_height, 0));

    const https_json = "{\"formats\":[{\"url\":\"https://cdn.example/v\",\"protocol\":\"https\",\"vcodec\":\"avc1\",\"height\":360}]}";
    var resolved = try resolve(std.testing.allocator, https_json, default_max_height, 0);
    defer resolved.deinit();
    try std.testing.expectEqualStrings("https://cdn.example/v", resolved.info.url);
}

test "stderr classification follows the fatal substring priority" {
    const cases = [_]struct {
        text: []const u8,
        expected: StderrClass,
    }{
        .{ .text = "PRIVATE VIDEO and unsupported URL", .expected = .{ .fatal = .private } },
        .{ .text = "Sign in to confirm your age", .expected = .{ .fatal = .age_restricted } },
        .{ .text = "Members-only video", .expected = .{ .fatal = .members_only } },
        .{ .text = "DRM protected", .expected = .{ .fatal = .drm } },
        .{ .text = "Premieres in 2 hours", .expected = .{ .fatal = .upcoming } },
        .{ .text = "Unsupported URL", .expected = .{ .fatal = .invalid_url } },
        .{ .text = "Video unavailable", .expected = .{ .fatal = .unavailable } },
        .{ .text = "HTTP Error 503", .expected = .retriable },
        .{ .text = "request timed out", .expected = .retriable },
    };
    for (cases) |case| {
        try std.testing.expectEqual(case.expected, classifyStderr(case.text));
    }
}
