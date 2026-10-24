const std = @import("std");
const Allocator = std.mem.Allocator;

const bg = @import("background_media/main.zig");

pub const Values = bg.config_save.Values;

pub const SaveResult = struct {
    managed_path: []u8,
    main_path: []u8,
    main_changed: bool,
};

pub fn freeResult(alloc: Allocator, result: *SaveResult) void {
    alloc.free(result.managed_path);
    alloc.free(result.main_path);
    result.* = undefined;
}

pub fn save(alloc: Allocator, values: Values) !SaveResult {
    const configpkg = @import("../../config.zig");
    const global = @import("../../global.zig");

    const main_path = try configpkg.preferredDefaultFilePath(alloc);
    defer alloc.free(main_path);
    const dir_path = std.fs.path.dirname(main_path) orelse return error.BadPathName;
    const main_name = std.fs.path.basename(main_path);
    const saved = try bg.config_save.saveInDir(alloc, global.io(), dir_path, main_name, values);
    return .{
        .managed_path = saved.managed_path,
        .main_path = saved.main_path,
        .main_changed = saved.main_changed,
    };
}
