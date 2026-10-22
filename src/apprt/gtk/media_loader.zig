const std = @import("std");

const gdk = @import("gdk");
const glib = @import("glib");

const global = @import("../../global.zig");
const bg = @import("background_media/main.zig");
const MediaView = @import("class/media_view.zig").MediaView;

const log = std.log.scoped(.gtk_media_loader);
const alloc = std.heap.c_allocator;

pub const Request = struct {
    id: u64,
    path: [:0]const u8,
    optional: bool,
};

const Status = enum { idle, loading, ready, failed };

const Loader = struct {
    generation: u64 = 0,
    current_id: u64 = 0,
    status: Status = .idle,
    texture: ?*gdk.Texture = null,
    views: std.ArrayListUnmanaged(*MediaView) = .empty,
};

const Result = union(enum) {
    disabled,
    failed: bg.state.Failure,
    ready: struct {
        texture: *gdk.Texture,
        media_type: bg.source.MediaType,
        dimensions: bg.header.Dimensions,
    },
};

const Job = struct {
    generation: u64,
    id: u64,
    path: [:0]u8,
    optional: bool,
    result: Result = undefined,
};

var loader: Loader = .{};

pub fn register(view: *MediaView) void {
    for (loader.views.items) |registered| {
        if (registered == view) return;
    }
    loader.views.append(alloc, view) catch unreachable;
}

pub fn unregister(view: *MediaView) void {
    for (loader.views.items, 0..) |registered, i| {
        if (registered == view) {
            _ = loader.views.swapRemove(i);
            break;
        }
    }

    if (loader.views.items.len == 0) release();
}

pub fn request(req: ?Request) void {
    const req_value = req orelse {
        release();
        notifyViews();
        return;
    };

    if (loader.current_id == req_value.id and
        (loader.status == .loading or loader.status == .ready)) return;

    release();
    loader.generation += 1;
    loader.current_id = req_value.id;
    loader.status = .loading;

    const path = alloc.dupeZ(u8, req_value.path) catch {
        loader.status = .failed;
        log.warn("background-media: failed reason=unreadable source={s}", .{req_value.path});
        return;
    };
    const job = alloc.create(Job) catch {
        alloc.free(path);
        loader.status = .failed;
        log.warn("background-media: failed reason=unreadable source={s}", .{req_value.path});
        return;
    };
    job.* = .{
        .generation = loader.generation,
        .id = req_value.id,
        .path = path,
        .optional = req_value.optional,
    };

    const thread = std.Thread.spawn(.{}, worker, .{job}) catch {
        freeJob(job);
        loader.status = .failed;
        log.warn("background-media: failed reason=unreadable source={s}", .{req_value.path});
        return;
    };
    thread.detach();
}

pub fn texture() ?*gdk.Texture {
    return loader.texture;
}

fn release() void {
    if (loader.texture) |texture_value| texture_value.unref();
    loader.texture = null;
    loader.current_id = 0;
    loader.status = .idle;
    loader.generation += 1;
}

fn notifyViews() void {
    for (loader.views.items) |view| view.mediaChanged();
}

fn worker(job: *Job) void {
    job.result = load(job);
    _ = glib.idleAddOnce(onDone, job);
}

fn load(job: *Job) Result {
    const file = std.Io.Dir.openFileAbsolute(
        global.io(),
        job.path,
        .{ .mode = .read_only },
    ) catch |err| {
        if (err == error.FileNotFound and job.optional) return .disabled;
        if (err == error.FileNotFound) return .{ .failed = .not_found };
        return .{ .failed = .unreadable };
    };
    defer file.close(global.io());

    const stat = file.stat(global.io()) catch return .{ .failed = .unreadable };
    const limits: bg.header.Limits = .{};
    if (stat.size > limits.max_file_bytes) return .{ .failed = .too_large };

    var reader_buffer: [bg.header.read_len]u8 = undefined;
    var file_reader = file.reader(global.io(), &reader_buffer);
    var head: [bg.header.read_len]u8 = undefined;
    const read_len = file_reader.interface.readSliceShort(&head) catch {
        return .{ .failed = .unreadable };
    };

    const sniffed = bg.source.sniff(head[0..read_len]);
    const media_type = if (sniffed == .unknown) bg.source.fromExtension(job.path) else sniffed;
    switch (media_type) {
        .image_png, .image_jpeg, .image_webp => {},
        else => return .{ .failed = .unsupported_type },
    }

    const dimensions = bg.header.dimensions(media_type, head[0..read_len]) orelse {
        return .{ .failed = .decode_failed };
    };
    if (bg.header.check(dimensions, stat.size, limits)) |failure| {
        return .{ .failed = failure };
    }

    var g_error: ?*glib.Error = null;
    defer if (g_error) |error_value| error_value.free();
    const texture_value = gdk.Texture.newFromFilename(job.path, &g_error) orelse {
        return .{ .failed = .decode_failed };
    };

    return .{ .ready = .{
        .texture = texture_value,
        .media_type = media_type,
        .dimensions = dimensions,
    } };
}

fn onDone(ud: ?*anyopaque) callconv(.c) void {
    const job: *Job = @ptrCast(@alignCast(ud orelse return));
    defer freeJob(job);

    if (job.generation != loader.generation) {
        if (job.result == .ready) job.result.ready.texture.unref();
        return;
    }

    switch (job.result) {
        .disabled => {
            loader.texture = null;
            loader.current_id = 0;
            loader.status = .idle;
        },
        .failed => |failure| {
            loader.texture = null;
            loader.current_id = job.id;
            loader.status = .failed;
            log.warn("background-media: failed reason={s} source={s}", .{
                @tagName(failure),
                job.path,
            });
        },
        .ready => |ready| {
            loader.texture = ready.texture;
            loader.current_id = job.id;
            loader.status = .ready;
            log.info("background-media: loaded type={s} {d}x{d}", .{
                @tagName(ready.media_type),
                ready.dimensions.width,
                ready.dimensions.height,
            });
        },
    }

    notifyViews();
}

fn freeJob(job: *Job) void {
    alloc.free(job.path);
    alloc.destroy(job);
}
