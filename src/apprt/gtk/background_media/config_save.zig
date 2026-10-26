const std = @import("std");
const Allocator = std.mem.Allocator;

const managed_name = "background-media.ghostty";
const managed_header = "# Managed by the Ghostty background-media panel.\n" ++
    "# \"Save to configuration\" overwrites this file; put your own settings in the main config.\n";
const include_lines = "# Added by the Ghostty background-media panel\n" ++
    "config-file = ?background-media.ghostty\n";

pub const Values = struct {
    source: ?[]const u8,
    fit: []const u8,
    position: []const u8,
    dim: f32,
    blur: f32,
    loop: bool,
    volume: f32,
    play_in_background: bool,
    max_fps: u32,
    background_opacity: f32,
    box_opacity: f32,
    box_round: bool,
    youtube_quality: u32,
};

pub const SavePaths = struct {
    managed_path: []u8,
    main_path: []u8,
    main_changed: bool,
};

/// Writes the managed settings to a writer without filesystem access.
pub fn renderManaged(writer: *std.Io.Writer, values: Values) !void {
    if (values.source) |source| {
        if (std.mem.indexOfAny(u8, source, "\n\r\x00") != null) return error.InvalidValue;
    }

    try writer.writeAll(managed_header);
    if (values.source) |source| {
        try writer.print("background-media = {s}\n", .{source});
    } else {
        try writer.writeAll("# background-media is not set\n");
    }
    try writer.print(
        "background-media-fit = {s}\n" ++
            "background-media-position = {s}\n" ++
            "background-media-dim = {d:.2}\n" ++
            "background-media-blur = {d:.1}\n" ++
            "background-media-loop = {}\n" ++
            "background-media-volume = {d:.2}\n" ++
            "background-media-play-in-background = {}\n" ++
            "background-media-max-fps = {d}\n" ++
            "background-opacity = {d:.2}\n" ++
            "background-media-box-opacity = {d:.2}\n" ++
            "background-media-box-round = {}\n",
        .{
            values.fit,
            values.position,
            values.dim,
            values.blur,
            values.loop,
            values.volume,
            values.play_in_background,
            values.max_fps,
            values.background_opacity,
            values.box_opacity,
            values.box_round,
        },
    );
    if (values.youtube_quality == 0) {
        try writer.writeAll("background-media-youtube-quality = auto\n");
    } else {
        try writer.print("background-media-youtube-quality = {d}\n", .{values.youtube_quality});
    }
}

/// Returns whether the config already references the managed include.
pub fn hasInclude(contents: []const u8) bool {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed_line = std.mem.trim(u8, line, " \t\r");
        if (trimmed_line.len == 0 or trimmed_line[0] == '#') continue;

        const equals_index = std.mem.indexOfScalar(u8, trimmed_line, '=') orelse continue;
        const key = std.mem.trim(u8, trimmed_line[0..equals_index], " \t\r");
        if (!std.mem.eql(u8, key, "config-file")) continue;

        var value = std.mem.trim(u8, trimmed_line[equals_index + 1 ..], " \t\r");
        var stripped_question = false;
        var stripped_quote = false;
        while (true) {
            value = std.mem.trim(u8, value, " \t\r");
            if (!stripped_question and value.len > 0 and value[0] == '?') {
                value = value[1..];
                stripped_question = true;
                continue;
            }
            if (!stripped_quote and value.len >= 2 and
                (value[0] == '"' or value[0] == '\'') and value[value.len - 1] == value[0])
            {
                value = value[1 .. value.len - 1];
                stripped_quote = true;
                continue;
            }
            break;
        }
        if (std.mem.eql(u8, value, managed_name)) return true;
    }
    return false;
}

/// Returns a copy of the config with the managed include appended if absent.
pub fn withInclude(alloc: Allocator, contents: []const u8) ![]u8 {
    var result: std.Io.Writer.Allocating = .init(alloc);
    defer result.deinit();

    try result.writer.writeAll(contents);
    if (hasInclude(contents)) return try result.toOwnedSlice();
    if (contents.len > 0 and contents[contents.len - 1] != '\n') {
        try result.writer.writeAll("\n");
    }
    try result.writer.writeAll(include_lines);
    return try result.toOwnedSlice();
}

pub fn saveInDir(
    alloc: Allocator,
    io: std.Io,
    dir_path: []const u8,
    main_name: []const u8,
    values: Values,
) !SavePaths {
    var managed_contents: std.Io.Writer.Allocating = .init(alloc);
    defer managed_contents.deinit();
    try renderManaged(&managed_contents.writer, values);

    const dir_permissions = modePermissions(0o755, .default_dir);
    const dir_status = try std.Io.Dir.cwd().createDirPathStatus(io, dir_path, dir_permissions);
    var dir = try std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true });
    defer dir.close(io);
    if (dir_status == .created) try dir.setPermissions(io, dir_permissions);

    const existing_contents: ?[]u8 = dir.readFileAlloc(io, main_name, alloc, .unlimited) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    defer if (existing_contents) |contents| alloc.free(contents);

    const existing_stat = if (existing_contents != null)
        try dir.statFile(io, main_name, .{})
    else
        null;
    const main_changed = if (existing_contents) |contents| !hasInclude(contents) else true;
    const main_permissions = if (existing_stat) |stat|
        stat.permissions
    else
        modePermissions(0o644, .default_file);

    try writeAtomic(
        alloc,
        io,
        dir,
        managed_name,
        managed_contents.written(),
        modePermissions(0o644, .default_file),
    );

    if (main_changed) {
        const new_main = if (existing_contents) |contents|
            try withInclude(alloc, contents)
        else
            try withInclude(alloc, "");
        defer alloc.free(new_main);
        try writeAtomic(alloc, io, dir, main_name, new_main, main_permissions);
    }

    const managed_path = try std.fs.path.join(alloc, &.{ dir_path, managed_name });
    errdefer alloc.free(managed_path);
    const main_path = try std.fs.path.join(alloc, &.{ dir_path, main_name });
    errdefer alloc.free(main_path);
    return .{
        .managed_path = managed_path,
        .main_path = main_path,
        .main_changed = main_changed,
    };
}

fn writeAtomic(
    alloc: Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    name: []const u8,
    contents: []const u8,
    permissions: std.Io.File.Permissions,
) !void {
    const tmp_name = try std.fmt.allocPrint(alloc, "{s}.tmp-{d}", .{ name, std.posix.system.getpid() });
    defer alloc.free(tmp_name);
    defer dir.deleteFile(io, tmp_name) catch {};

    {
        var file = try dir.createFile(io, tmp_name, .{ .permissions = permissions });
        defer file.close(io);

        try file.writeStreamingAll(io, contents);
        try file.setPermissions(io, permissions);
        try file.sync(io);
    }

    try dir.rename(tmp_name, dir, name, io);
}

fn modePermissions(mode: u16, fallback: std.Io.File.Permissions) std.Io.File.Permissions {
    if (comptime std.posix.mode_t != u0) return .fromMode(@intCast(mode));
    return fallback;
}

test "renderManaged outputs exact values with and without a source" {
    const testing = std.testing;
    const values: Values = .{
        .source = "file:///tmp/wallpaper.mp4",
        .fit = "cover",
        .position = "center",
        .dim = 0.1,
        .blur = 12,
        .loop = true,
        .volume = 0.75,
        .play_in_background = false,
        .max_fps = 30,
        .background_opacity = 0.7,
        .box_opacity = 0.55,
        .box_round = true,
        .youtube_quality = 1080,
    };

    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try renderManaged(&output.writer, values);
    try testing.expectEqualStrings(
        "# Managed by the Ghostty background-media panel.\n" ++
            "# \"Save to configuration\" overwrites this file; put your own settings in the main config.\n" ++
            "background-media = file:///tmp/wallpaper.mp4\n" ++
            "background-media-fit = cover\n" ++
            "background-media-position = center\n" ++
            "background-media-dim = 0.10\n" ++
            "background-media-blur = 12.0\n" ++
            "background-media-loop = true\n" ++
            "background-media-volume = 0.75\n" ++
            "background-media-play-in-background = false\n" ++
            "background-media-max-fps = 30\n" ++
            "background-opacity = 0.70\n" ++
            "background-media-box-opacity = 0.55\n" ++
            "background-media-box-round = true\n" ++
            "background-media-youtube-quality = 1080\n",
        output.written(),
    );

    output.clearRetainingCapacity();
    var no_source = values;
    no_source.source = null;
    no_source.youtube_quality = 0;
    no_source.box_round = false;
    try renderManaged(&output.writer, no_source);
    try testing.expectEqualStrings(
        "# Managed by the Ghostty background-media panel.\n" ++
            "# \"Save to configuration\" overwrites this file; put your own settings in the main config.\n" ++
            "# background-media is not set\n" ++
            "background-media-fit = cover\n" ++
            "background-media-position = center\n" ++
            "background-media-dim = 0.10\n" ++
            "background-media-blur = 12.0\n" ++
            "background-media-loop = true\n" ++
            "background-media-volume = 0.75\n" ++
            "background-media-play-in-background = false\n" ++
            "background-media-max-fps = 30\n" ++
            "background-opacity = 0.70\n" ++
            "background-media-box-opacity = 0.55\n" ++
            "background-media-box-round = false\n" ++
            "background-media-youtube-quality = auto\n",
        output.written(),
    );
}

test "renderManaged rejects line breaks and NUL in source" {
    const testing = std.testing;
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    const values: Values = .{
        .source = "bad\nsource",
        .fit = "cover",
        .position = "center",
        .dim = 0,
        .blur = 0,
        .loop = false,
        .volume = 1,
        .play_in_background = false,
        .max_fps = 30,
        .background_opacity = 1.0,
        .box_opacity = 1.0,
        .box_round = false,
        .youtube_quality = 0,
    };
    try testing.expectError(error.InvalidValue, renderManaged(&output.writer, values));
    try testing.expectError(error.InvalidValue, renderManaged(&output.writer, .{
        .source = "bad\rsource",
        .fit = "cover",
        .position = "center",
        .dim = 0,
        .blur = 0,
        .loop = false,
        .volume = 1,
        .play_in_background = false,
        .max_fps = 30,
        .background_opacity = 1.0,
        .box_opacity = 1.0,
        .box_round = false,
        .youtube_quality = 0,
    }));
    try testing.expectError(error.InvalidValue, renderManaged(&output.writer, .{
        .source = "bad\x00source",
        .fit = "cover",
        .position = "center",
        .dim = 0,
        .blur = 0,
        .loop = false,
        .volume = 1,
        .play_in_background = false,
        .max_fps = 30,
        .background_opacity = 1.0,
        .box_opacity = 1.0,
        .box_round = false,
        .youtube_quality = 0,
    }));
}

test "hasInclude recognizes supported forms and ignores comments and other files" {
    const testing = std.testing;
    try testing.expect(hasInclude("config-file = ?background-media.ghostty\n"));
    try testing.expect(hasInclude("config-file = \"background-media.ghostty\"\n"));
    try testing.expect(hasInclude("config-file = background-media.ghostty\n"));
    try testing.expect(hasInclude("  config-file   =   ?background-media.ghostty  \r\n"));
    try testing.expect(hasInclude("config-file = ?\"background-media.ghostty\"\n"));
    try testing.expect(!hasInclude("# config-file = ?background-media.ghostty\n"));
    try testing.expect(!hasInclude("config-file = other.ghostty\n"));
}

test "withInclude appends with correct newline handling" {
    const testing = std.testing;
    const expected = include_lines;

    const empty_result = try withInclude(testing.allocator, "");
    defer testing.allocator.free(empty_result);
    try testing.expectEqualStrings(expected, empty_result);

    const no_newline = try withInclude(testing.allocator, "font-size = 12");
    defer testing.allocator.free(no_newline);
    try testing.expectEqualStrings("font-size = 12\n" ++ expected, no_newline);

    const with_newline = try withInclude(testing.allocator, "font-size = 12\n");
    defer testing.allocator.free(with_newline);
    try testing.expectEqualStrings("font-size = 12\n" ++ expected, with_newline);
}

test "saveInDir creates the main config and managed include" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", alloc);
    defer alloc.free(root);
    const dir_path = try std.fs.path.join(alloc, &.{ root, "nested" });
    defer alloc.free(dir_path);

    const result = try saveInDir(alloc, testing.io, dir_path, "config.ghostty", .{
        .source = null,
        .fit = "contain",
        .position = "top-left",
        .dim = 0.1,
        .blur = 0,
        .loop = false,
        .volume = 0.5,
        .play_in_background = true,
        .max_fps = 24,
        .background_opacity = 1.0,
        .box_opacity = 1.0,
        .box_round = false,
        .youtube_quality = 0,
    });
    defer {
        alloc.free(result.managed_path);
        alloc.free(result.main_path);
    }
    try testing.expect(result.main_changed);

    var dir = try std.Io.Dir.openDirAbsolute(testing.io, dir_path, .{ .iterate = true });
    defer dir.close(testing.io);
    const main_contents = try dir.readFileAlloc(testing.io, "config.ghostty", alloc, .unlimited);
    defer alloc.free(main_contents);
    try testing.expectEqualStrings(include_lines, main_contents);

    const managed_contents = try dir.readFileAlloc(testing.io, managed_name, alloc, .unlimited);
    defer alloc.free(managed_contents);
    try testing.expect(std.mem.indexOf(u8, managed_contents, "# background-media is not set\n") != null);

    const main_stat = try dir.statFile(testing.io, "config.ghostty", .{});
    try testing.expectEqual(@as(u16, 0o644), @as(u16, @intCast(main_stat.permissions.toMode() & 0o777)));
    const dir_stat = try dir.stat(testing.io);
    try testing.expectEqual(@as(u16, 0o755), @as(u16, @intCast(dir_stat.permissions.toMode() & 0o777)));

    var iterator = dir.iterate();
    while (try iterator.next(testing.io)) |entry| {
        try testing.expect(std.mem.indexOf(u8, entry.name, ".tmp-") == null);
    }
}

test "saveInDir preserves existing main config and does not append twice" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const dir_path = try tmp.dir.realPathFileAlloc(testing.io, ".", alloc);
    defer alloc.free(dir_path);
    const original = "font-size = 12\n# keep this line";
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "config.ghostty",
        .data = original,
        .flags = .{ .permissions = modePermissions(0o600, .default_file) },
    });

    const first = try saveInDir(alloc, testing.io, dir_path, "config.ghostty", .{
        .source = "file:///first.mp4",
        .fit = "cover",
        .position = "center",
        .dim = 0.2,
        .blur = 0,
        .loop = true,
        .volume = 0.8,
        .play_in_background = false,
        .max_fps = 30,
        .background_opacity = 1.0,
        .box_opacity = 0.75,
        .box_round = true,
        .youtube_quality = 0,
    });
    defer {
        alloc.free(first.managed_path);
        alloc.free(first.main_path);
    }
    try testing.expect(first.main_changed);

    const expected_main = original ++ "\n" ++ include_lines;
    const after_first = try tmp.dir.readFileAlloc(testing.io, "config.ghostty", alloc, .unlimited);
    defer alloc.free(after_first);
    try testing.expectEqualStrings(expected_main, after_first);
    const first_managed = try tmp.dir.readFileAlloc(testing.io, managed_name, alloc, .unlimited);
    defer alloc.free(first_managed);
    try testing.expect(std.mem.indexOf(u8, first_managed, "file:///first.mp4") != null);

    const second = try saveInDir(alloc, testing.io, dir_path, "config.ghostty", .{
        .source = "file:///second.mp4",
        .fit = "contain",
        .position = "bottom-right",
        .dim = 0.3,
        .blur = 0,
        .loop = false,
        .volume = 0.4,
        .play_in_background = true,
        .max_fps = 60,
        .background_opacity = 1.0,
        .box_opacity = 0.5,
        .box_round = false,
        .youtube_quality = 0,
    });
    defer {
        alloc.free(second.managed_path);
        alloc.free(second.main_path);
    }
    try testing.expect(!second.main_changed);

    const after_second = try tmp.dir.readFileAlloc(testing.io, "config.ghostty", alloc, .unlimited);
    defer alloc.free(after_second);
    try testing.expectEqualStrings(expected_main, after_second);
    const second_managed = try tmp.dir.readFileAlloc(testing.io, managed_name, alloc, .unlimited);
    defer alloc.free(second_managed);
    try testing.expect(std.mem.indexOf(u8, second_managed, "file:///second.mp4") != null);
    try testing.expect(std.mem.indexOf(u8, second_managed, "file:///first.mp4") == null);

    const main_stat = try tmp.dir.statFile(testing.io, "config.ghostty", .{});
    try testing.expectEqual(@as(u16, 0o600), @as(u16, @intCast(main_stat.permissions.toMode() & 0o777)));
    var iterator = tmp.dir.iterate();
    while (try iterator.next(testing.io)) |entry| {
        try testing.expect(std.mem.indexOf(u8, entry.name, ".tmp-") == null);
    }
}
