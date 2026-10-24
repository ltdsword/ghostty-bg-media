const std = @import("std");
const Allocator = std.mem.Allocator;
const cli = @import("../cli.zig");
const formatterpkg = @import("formatter.zig");
const Path = @import("path.zig").Path;

pub const Source = union(enum) {
    path: Path,
    url: [:0]const u8,

    pub fn parseCLI(self: *Source, alloc: Allocator, input: ?[]const u8) !void {
        var value = input orelse return error.ValueRequired;
        value = std.mem.trim(u8, value, cli.args.whitespace);
        if (value.len == 0) return error.ValueRequired;

        if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
            value = value[1 .. value.len - 1];
        }

        if (schemeEnd(value)) |end| {
            const scheme = value[0..end];
            if (!std.ascii.eqlIgnoreCase(scheme, "http") and
                !std.ascii.eqlIgnoreCase(scheme, "https")) return error.InvalidValue;
            self.* = .{ .url = try alloc.dupeZ(u8, value) };
            return;
        }

        self.* = .{ .path = (try Path.parse(alloc, value)) orelse return error.ValueRequired };
    }

    fn schemeEnd(value: []const u8) ?usize {
        if (value.len == 0 or !std.ascii.isAlphabetic(value[0])) return null;

        var i: usize = 1;
        while (i < value.len and (std.ascii.isAlphanumeric(value[i]) or
            value[i] == '+' or value[i] == '.' or value[i] == '-')) : (i += 1)
        {}

        if (i + 3 > value.len or !std.mem.eql(u8, value[i .. i + 3], "://")) return null;
        return i;
    }

    pub fn expand(
        self: *Source,
        alloc: Allocator,
        base: []const u8,
        diags: *cli.DiagnosticList,
    ) !void {
        switch (self.*) {
            .path => |*path| try path.expand(alloc, base, diags),
            .url => {},
        }
    }

    pub fn clone(self: Source, alloc: Allocator) Allocator.Error!Source {
        return switch (self) {
            .path => |path| .{ .path = try path.clone(alloc) },
            .url => |url| .{ .url = try alloc.dupeZ(u8, url) },
        };
    }

    pub fn equal(self: Source, other: Source) bool {
        return switch (self) {
            .path => |path| switch (other) {
                .path => |other_path| switch (path) {
                    .optional => |value| switch (other_path) {
                        .optional => |other_value| std.mem.eql(u8, value, other_value),
                        .required => false,
                    },
                    .required => |value| switch (other_path) {
                        .required => |other_value| std.mem.eql(u8, value, other_value),
                        .optional => false,
                    },
                },
                .url => false,
            },
            .url => |url| switch (other) {
                .path => false,
                .url => |other_url| std.mem.eql(u8, url, other_url),
            },
        };
    }

    pub fn formatEntry(self: *const Source, formatter: formatterpkg.EntryFormatter) !void {
        switch (self.*) {
            .path => |*path| try path.formatEntry(formatter),
            .url => |url| try formatter.formatEntry([]const u8, url),
        }
    }
};

pub const YoutubeQuality = union(enum) {
    auto,
    height: u32,

    pub fn parseCLI(self: *YoutubeQuality, alloc: Allocator, input: ?[]const u8) !void {
        _ = alloc;
        var value = input orelse return error.InvalidValue;
        value = std.mem.trim(u8, value, cli.args.whitespace);
        if (std.mem.eql(u8, value, "auto")) {
            self.* = .auto;
            return;
        }

        if (value.len == 0) return error.InvalidValue;
        for (value) |char| if (!std.ascii.isDigit(char)) return error.InvalidValue;
        const height = std.fmt.parseInt(u32, value, 10) catch return error.InvalidValue;
        if (height == 0 or height > 4320) return error.InvalidValue;
        self.* = .{ .height = height };
    }

    pub fn formatEntry(self: *const YoutubeQuality, formatter: formatterpkg.EntryFormatter) !void {
        switch (self.*) {
            .auto => try formatter.formatEntry([]const u8, "auto"),
            .height => |height| try formatter.formatEntry(u32, height),
        }
    }
};

pub const Fit = enum { contain, cover, stretch, none };

pub const Position = enum {
    center,
    @"top-left",
    @"top-center",
    @"top-right",
    @"center-left",
    @"center-right",
    @"bottom-left",
    @"bottom-center",
    @"bottom-right",
};

test "background_media source parsing" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var http: Source = undefined;
    try http.parseCLI(alloc, "http://example.com/video.mp4");
    try testing.expectEqualStrings("http://example.com/video.mp4", http.url);

    var https: Source = undefined;
    try https.parseCLI(alloc, "HTTPS://example.com/live.m3u8?token=x");
    try testing.expectEqualStrings("HTTPS://example.com/live.m3u8?token=x", https.url);

    var rejected: Source = undefined;
    try testing.expectError(error.InvalidValue, rejected.parseCLI(alloc, "ftp://x"));
    try testing.expectError(error.InvalidValue, rejected.parseCLI(alloc, "file:///x"));

    var path: Source = undefined;
    try path.parseCLI(alloc, "video.mp4");
    try testing.expectEqualStrings("video.mp4", path.path.required);

    var optional: Source = undefined;
    try optional.parseCLI(alloc, "?~/a.mp4");
    try testing.expectEqualStrings("~/a.mp4", optional.path.optional);

    var quoted: Source = undefined;
    try quoted.parseCLI(alloc, "\"a video.mp4\"");
    try testing.expectEqualStrings("a video.mp4", quoted.path.required);

    try testing.expectError(error.ValueRequired, rejected.parseCLI(alloc, ""));
    try testing.expectError(error.ValueRequired, rejected.parseCLI(alloc, null));
}

test "background_media YouTube quality parsing and formatting" {
    const testing = std.testing;
    var quality: YoutubeQuality = undefined;

    try quality.parseCLI(testing.allocator, "auto");
    try testing.expect(quality == .auto);
    var auto_buf: std.Io.Writer.Allocating = .init(testing.allocator);
    defer auto_buf.deinit();
    try quality.formatEntry(formatterpkg.entryFormatter("quality", &auto_buf.writer));
    try testing.expectEqualStrings("quality = auto\n", auto_buf.written());

    try quality.parseCLI(testing.allocator, "1080");
    try testing.expectEqual(@as(u32, 1080), quality.height);
    var height_buf: std.Io.Writer.Allocating = .init(testing.allocator);
    defer height_buf.deinit();
    try quality.formatEntry(formatterpkg.entryFormatter("quality", &height_buf.writer));
    try testing.expectEqualStrings("quality = 1080\n", height_buf.written());

    try testing.expectError(error.InvalidValue, quality.parseCLI(testing.allocator, null));
    try testing.expectError(error.InvalidValue, quality.parseCLI(testing.allocator, ""));
    try testing.expectError(error.InvalidValue, quality.parseCLI(testing.allocator, "0"));
    try testing.expectError(error.InvalidValue, quality.parseCLI(testing.allocator, "4321"));
    try testing.expectError(error.InvalidValue, quality.parseCLI(testing.allocator, "1080p"));
}
