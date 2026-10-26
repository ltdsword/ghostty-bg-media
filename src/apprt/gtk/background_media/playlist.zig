const std = @import("std");
const source = @import("source.zig");

pub const batch_size: u32 = 50;
pub const gap_ms: u32 = 3000;
pub const max_entries: usize = 1000;
pub const max_consecutive_failures: u32 = 5;

pub fn listId(url: []const u8) ?[]const u8 {
    const uri = std.Uri.parse(url) catch return null;
    if (source.classifyUrl(url) != .youtube) return null;
    return queryValue(uri.query, "list");
}

pub fn videoId(url: []const u8) ?[]const u8 {
    const uri = std.Uri.parse(url) catch return null;
    if (source.classifyUrl(url) != .youtube) return null;
    if (queryValue(uri.query, "v")) |id| return id;

    const host = if (uri.host) |component| component.percent_encoded else return null;
    if (!std.ascii.eqlIgnoreCase(host, "youtu.be")) return null;
    const path = uri.path.percent_encoded;
    if (!std.mem.startsWith(u8, path, "/")) return null;
    const id = path[1..][0 .. std.mem.indexOfScalar(u8, path[1..], '/') orelse path[1..].len];
    return validId(id);
}

pub fn watchUrl(allocator: std.mem.Allocator, id: []const u8) ![:0]u8 {
    return try std.fmt.allocPrintSentinel(allocator, "https://www.youtube.com/watch?v={s}", .{id}, 0);
}

pub const Batch = struct {
    ids: [][]u8,
    title: []u8,

    pub fn deinit(self: *Batch, allocator: std.mem.Allocator) void {
        for (self.ids) |id| allocator.free(id);
        allocator.free(self.ids);
        allocator.free(self.title);
    }
};

const RawBatch = struct {
    _type: ?[]const u8 = null,
    title: ?[]const u8 = null,
    entries: ?[]const Entry = null,

    const Entry = struct {
        id: ?[]const u8 = null,
    };
};

pub fn parseBatch(allocator: std.mem.Allocator, json: []const u8) !Batch {
    const parsed = std.json.parseFromSlice(RawBatch, allocator, json, .{
        .ignore_unknown_fields = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.BadJson,
    };
    defer parsed.deinit();

    if (parsed.value._type == null or !std.mem.eql(u8, parsed.value._type.?, "playlist")) {
        return error.NotPlaylist;
    }

    var ids: std.ArrayList([]u8) = .empty;
    errdefer {
        for (ids.items) |id| allocator.free(id);
        ids.deinit(allocator);
    }
    for (parsed.value.entries orelse &.{}) |entry| {
        const id = validId(entry.id orelse continue) orelse continue;
        const owned_id = try allocator.dupe(u8, id);
        ids.append(allocator, owned_id) catch |err| {
            allocator.free(owned_id);
            return err;
        };
    }
    const owned_ids = try ids.toOwnedSlice(allocator);
    errdefer {
        for (owned_ids) |id| allocator.free(id);
        allocator.free(owned_ids);
    }
    const title = try allocator.dupe(u8, parsed.value.title orelse "");
    return .{ .ids = owned_ids, .title = title };
}

pub const Cursor = struct {
    index: usize,
    count: usize,
    more: bool,
};

pub const Step = union(enum) {
    play: usize,
    fetch_more,
    end,
};

pub fn step(cursor: Cursor, delta: i32, loop: bool) Step {
    if (delta < 0) return .{ .play = cursor.index -| 1 };
    if (delta > 0) {
        if (cursor.index < cursor.count and cursor.count - cursor.index > 1) {
            return .{ .play = cursor.index + 1 };
        }
        if (cursor.more) return .fetch_more;
        if (loop) return .{ .play = 0 };
        return .end;
    }
    return .{ .play = cursor.index };
}

/// What a playlist does when the current video ends: Loop repeats it, otherwise the
/// list moves on after the gap.
pub const AfterEnd = enum { repeat, next };

pub fn afterEnd(loop: bool, was_live: bool) AfterEnd {
    return if (loop and !was_live) .repeat else .next;
}

fn queryValue(query: ?std.Uri.Component, key: []const u8) ?[]const u8 {
    const encoded = if (query) |component| component.percent_encoded else return null;
    var parts = std.mem.splitScalar(u8, encoded, '&');
    while (parts.next()) |part| {
        const separator = std.mem.indexOfScalar(u8, part, '=') orelse continue;
        if (!std.mem.eql(u8, part[0..separator], key)) continue;
        return validId(part[separator + 1 ..]);
    }
    return null;
}

fn validId(id: []const u8) ?[]const u8 {
    if (id.len == 0 or id.len > 64) return null;
    for (id) |char| {
        if (!std.ascii.isAlphanumeric(char) and char != '_' and char != '-') return null;
    }
    return id;
}

test "playlist IDs parse supported YouTube URL forms" {
    try std.testing.expectEqualStrings("RDh8UpC5JbMU0", listId("https://www.youtube.com/watch?v=h8UpC5JbMU0&list=RDh8UpC5JbMU0").?);
    try std.testing.expectEqualStrings("PL_abc-123", listId("https://youtube.com/playlist?list=PL_abc-123").?);
    try std.testing.expectEqualStrings("video_123-abc", videoId("https://youtube.com/watch?v=video_123-abc&list=PL123").?);
    try std.testing.expectEqualStrings("short-id", videoId("https://youtu.be/short-id").?);
    try std.testing.expect(listId("https://youtube.com/watch?v=abc") == null);
    try std.testing.expect(videoId("https://youtube.com/playlist?list=abc") == null);
    try std.testing.expect(listId("https://youtube.com/playlist?list=bad%20id") == null);
    try std.testing.expect(videoId("https://youtu.be/bad.id") == null);

    var long_id: [65]u8 = @splat('a');
    var url_buf: [128]u8 = undefined;
    const long_url = try std.fmt.bufPrint(&url_buf, "https://youtube.com/playlist?list={s}", .{&long_id});
    try std.testing.expect(listId(long_url) == null);
    const long_video_url = try std.fmt.bufPrint(&url_buf, "https://youtu.be/{s}", .{&long_id});
    try std.testing.expect(videoId(long_video_url) == null);
}

test "watchUrl builds a YouTube watch URL" {
    const url = try watchUrl(std.testing.allocator, "abc_123");
    defer std.testing.allocator.free(url);
    try std.testing.expectEqualStrings("https://www.youtube.com/watch?v=abc_123", url);
}

test "parseBatch requires a playlist and skips invalid IDs" {
    var batch = try parseBatch(std.testing.allocator, "{\"_type\":\"playlist\",\"title\":\"Mix\",\"entries\":[{\"id\":\"one\"},{\"id\":null},{\"id\":\"bad.id\"},{\"id\":\"two_2\"}]}");
    defer batch.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("Mix", batch.title);
    try std.testing.expectEqual(@as(usize, 2), batch.ids.len);
    try std.testing.expectEqualStrings("one", batch.ids[0]);
    try std.testing.expectEqualStrings("two_2", batch.ids[1]);

    var untitled = try parseBatch(std.testing.allocator, "{\"_type\":\"playlist\",\"title\":null,\"entries\":[]}");
    defer untitled.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("", untitled.title);

    try std.testing.expectError(error.NotPlaylist, parseBatch(std.testing.allocator, "{}"));
    try std.testing.expectError(error.BadJson, parseBatch(std.testing.allocator, "not json"));
}

test "playlist step covers previous, next, fetch, loop, and end" {
    try std.testing.expectEqual(@as(usize, 0), step(.{ .index = 0, .count = 3, .more = false }, -1, false).play);
    try std.testing.expectEqual(@as(usize, 1), step(.{ .index = 2, .count = 3, .more = false }, -1, false).play);
    try std.testing.expectEqual(@as(usize, 2), step(.{ .index = 1, .count = 3, .more = false }, 1, false).play);
    try std.testing.expectEqual(Step.fetch_more, step(.{ .index = 2, .count = 3, .more = true }, 1, false));
    try std.testing.expectEqual(@as(usize, 0), step(.{ .index = 2, .count = 3, .more = false }, 1, true).play);
    try std.testing.expectEqual(Step.end, step(.{ .index = 2, .count = 3, .more = false }, 1, false));
}

test "playlist loop repeats the current video" {
    try std.testing.expectEqual(AfterEnd.repeat, afterEnd(true, false));
    try std.testing.expectEqual(AfterEnd.next, afterEnd(false, false));
    try std.testing.expectEqual(AfterEnd.next, afterEnd(true, true));
}
