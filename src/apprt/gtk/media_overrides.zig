const std = @import("std");

const bg = @import("background_media/main.zig");
const media_loader = @import("media_loader.zig");

pub const SourceOverride = union(enum) {
    unset,
    none,
    value: [:0]u8,
};

pub const Overrides = struct {
    source: SourceOverride = .unset,
    fit: ?bg.layout.Fit = null,
    position: ?bg.layout.Position = null,
    dim: ?f32 = null,
    blur: ?f32 = null,
    loop: ?bool = null,
    volume: ?f32 = null,
    play_in_background: ?bool = null,
    max_fps: ?u32 = null,
    youtube_quality: ?u32 = null,
    paused: bool = false,
};

pub const ParsedSource = union(enum) {
    url: []const u8,
    path: struct {
        path: []const u8,
        optional: bool,
    },
};

var current: Overrides = .{};
var alloc: std.mem.Allocator = std.heap.c_allocator;
var on_change: *const fn () void = defaultOnChange;

pub fn get() *const Overrides {
    return &current;
}

pub fn setSource(value: ?[]const u8) void {
    if (value) |text| {
        const owned = alloc.dupeZ(u8, text) catch unreachable;
        freeCurrentSource();
        current.source = .{ .value = owned };
    } else {
        freeCurrentSource();
        current.source = .none;
    }
    on_change();
}

pub fn clearSource() void {
    freeCurrentSource();
    current.source = .unset;
    on_change();
}

pub fn setFit(value: bg.layout.Fit) void {
    current.fit = value;
    on_change();
}

pub fn setPosition(value: bg.layout.Position) void {
    current.position = value;
    on_change();
}

pub fn setDim(value: f32) void {
    current.dim = if (std.math.isNan(value)) 0 else std.math.clamp(value, 0, 1);
    on_change();
}

pub fn setBlur(value: f32) void {
    current.blur = if (std.math.isNan(value)) 0 else std.math.clamp(value, 0, 40);
    on_change();
}

pub fn setLoop(value: bool) void {
    current.loop = value;
    on_change();
}

pub fn setVolume(value: f32) void {
    current.volume = std.math.clamp(value, 0, 1);
    on_change();
}

pub fn setPlayInBackground(value: bool) void {
    current.play_in_background = value;
    on_change();
}

pub fn setMaxFps(value: u32) void {
    current.max_fps = std.math.clamp(value, 1, 120);
    on_change();
}

pub fn setYoutubeQuality(value: u32) void {
    current.youtube_quality = std.math.clamp(value, 0, 4320);
    on_change();
}

pub fn setPaused(value: bool) void {
    current.paused = value;
    on_change();
}

pub fn clearAll() void {
    freeCurrentSource();
    current = .{};
    on_change();
}

pub fn parseSource(text: []const u8) ?ParsedSource {
    var value = std.mem.trim(u8, text, " \t\r\n\x0b\x0c");
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        value = value[1 .. value.len - 1];
    }
    if (value.len == 0) return null;

    if (value[0] == '?') {
        const path = value[1..];
        if (path.len == 0) return null;
        return .{ .path = .{ .path = path, .optional = true } };
    }

    if (std.ascii.startsWithIgnoreCase(value, "http://") or
        std.ascii.startsWithIgnoreCase(value, "https://"))
    {
        return .{ .url = value };
    }

    return .{ .path = .{ .path = value, .optional = false } };
}

fn freeCurrentSource() void {
    if (current.source == .value) alloc.free(current.source.value);
}

fn defaultOnChange() void {
    media_loader.reapplyAll();
}

fn noChange() void {}

test "media override source parsing" {
    const testing = std.testing;

    try testing.expectEqualStrings("http://example.test/a", parseSource("http://example.test/a").?.url);
    try testing.expectEqualStrings("HTTPS://example.test/a", parseSource("HTTPS://example.test/a").?.url);

    const path = parseSource(" /tmp/a.png ").?.path;
    try testing.expectEqualStrings("/tmp/a.png", path.path);
    try testing.expect(!path.optional);

    const optional = parseSource("?relative/a.png").?.path;
    try testing.expectEqualStrings("relative/a.png", optional.path);
    try testing.expect(optional.optional);

    try testing.expectEqualStrings("a video.mp4", parseSource("  \"a video.mp4\"  ").?.path.path);
    try testing.expect(parseSource("") == null);
    try testing.expect(parseSource(" \t\r\n ") == null);
}

test "media override clamps values" {
    const old_on_change = on_change;
    on_change = noChange;
    defer on_change = old_on_change;

    setDim(-1);
    try std.testing.expectEqual(@as(f32, 0), current.dim.?);
    setDim(2);
    try std.testing.expectEqual(@as(f32, 1), current.dim.?);
    setDim(std.math.nan(f32));
    try std.testing.expectEqual(@as(f32, 0), current.dim.?);
    setVolume(-1);
    try std.testing.expectEqual(@as(f32, 0), current.volume.?);
    setVolume(2);
    try std.testing.expectEqual(@as(f32, 1), current.volume.?);
    setMaxFps(0);
    try std.testing.expectEqual(@as(u32, 1), current.max_fps.?);
    setMaxFps(240);
    try std.testing.expectEqual(@as(u32, 120), current.max_fps.?);
    setYoutubeQuality(5000);
    try std.testing.expectEqual(@as(u32, 4320), current.youtube_quality.?);
    setYoutubeQuality(1080);
    try std.testing.expectEqual(@as(u32, 1080), current.youtube_quality.?);
    setYoutubeQuality(0);
    try std.testing.expectEqual(@as(u32, 0), current.youtube_quality.?);
    clearAll();
}

test "media override clamps blur" {
    const old_on_change = on_change;
    on_change = noChange;
    defer on_change = old_on_change;

    setBlur(50);
    try std.testing.expectEqual(@as(f32, 40), current.blur.?);
    setBlur(-1);
    try std.testing.expectEqual(@as(f32, 0), current.blur.?);
    setBlur(std.math.nan(f32));
    try std.testing.expectEqual(@as(f32, 0), current.blur.?);
    clearAll();
}

test "media override source ownership and clearing" {
    const old_alloc = alloc;
    const old_on_change = on_change;
    alloc = std.testing.allocator;
    on_change = noChange;
    defer {
        clearAll();
        alloc = old_alloc;
        on_change = old_on_change;
    }

    var source = [_]u8{ 'p', 'a', 't', 'h' };
    setSource(source[0..]);
    source[0] = 'X';
    try std.testing.expectEqualStrings("path", current.source.value);

    setSource("next");
    try std.testing.expectEqualStrings("next", current.source.value);
    clearSource();
    try std.testing.expect(current.source == .unset);
    setSource(null);
    try std.testing.expect(current.source == .none);
}
