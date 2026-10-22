const std = @import("std");

const gdk = @import("gdk");
const glib = @import("glib");
const bg = @import("background_media/main.zig");

const log = std.log.scoped(.gtk_gif_player);
const alloc = std.heap.c_allocator;

pub const Animation = struct {
    const Self = @This();

    bytes: []u8,
    decoder: bg.gif.Decoder,
    path: [:0]u8,
    plays: u32 = 1,
    in_flight: bool = false,
    cancelled: bool = false,
    paused: bool = true,
    tick_pending: bool = false,
    timer_id: c_uint = 0,
    stopped: bool = false,
    pending: ?*gdk.Texture = null,
    pending_delay_ms: u32 = 0,
    pending_state: enum { frame, ended, failed } = .frame,
    has_pending: bool = false,
    due: bool = false,
    loop_forever: bool = false,
    on_texture: *const fn (*gdk.Texture) void,
    on_request_next: *const fn (*Self) void,
};

pub const Created = struct {
    anim: *Animation,
    first_texture: *gdk.Texture,
    first_delay_ms: u32,
};

const CreateError = bg.gif.Error || std.mem.Allocator.Error;

pub fn create(
    bytes: []u8,
    path: [:0]const u8,
    on_texture: *const fn (*gdk.Texture) void,
    on_request_next: *const fn (*Animation) void,
) CreateError!Created {
    var decoder = try bg.gif.Decoder.init(alloc, bytes);
    errdefer decoder.deinit();

    const first_frame = (try decoder.next()) orelse return error.InvalidGif;
    const path_copy = try alloc.dupeZ(u8, path);
    errdefer alloc.free(path_copy);

    const anim = try alloc.create(Animation);
    errdefer alloc.destroy(anim);
    anim.* = .{
        .bytes = bytes,
        .decoder = decoder,
        .path = path_copy,
        .on_texture = on_texture,
        .on_request_next = on_request_next,
    };

    return .{
        .anim = anim,
        .first_texture = textureFromCanvas(&anim.decoder),
        .first_delay_ms = first_frame.delay_ms,
    };
}

pub fn delayForFrame(delay_ms: u32, max_fps: u32) u32 {
    return @max(delay_ms, @divTrunc(1000, max_fps));
}

pub fn start(anim: *Animation, delay_ms: u32) void {
    if (anim.decoder.frame_count <= 1 or anim.stopped or anim.cancelled) return;
    anim.timer_id = glib.timeoutAddOnce(delay_ms, onTick, anim);
    anim.on_request_next(anim);
}

pub fn requestNext(anim: *Animation, loop: bool, max_fps: u32) void {
    if (anim.in_flight or anim.has_pending or anim.stopped or anim.cancelled) return;

    const loop_count = anim.decoder.loop_count;
    anim.loop_forever = loop or (loop_count != null and loop_count.? == 0);
    const total_plays: u32 = if (loop_count) |count|
        if (count > 0) @as(u32, count) + 1 else 1
    else
        1;
    const minimum_delay_ms = @divTrunc(1000, max_fps);

    anim.in_flight = true;
    const thread = std.Thread.spawn(.{}, decodeNext, .{
        anim,
        total_plays,
        minimum_delay_ms,
    }) catch {
        anim.in_flight = false;
        stopFailed(anim);
        return;
    };
    thread.detach();
}

pub fn setPaused(anim: *Animation, paused: bool) void {
    anim.paused = paused;
    if (!paused and anim.tick_pending) {
        anim.tick_pending = false;
        advance(anim);
    }
}

pub fn destroy(anim: *Animation) void {
    if (anim.timer_id != 0) {
        _ = glib.Source.remove(anim.timer_id);
        anim.timer_id = 0;
    }
    if (anim.in_flight) {
        anim.cancelled = true;
        return;
    }
    dispose(anim);
}

fn decodeNext(anim: *Animation, total_plays: u32, minimum_delay_ms: u32) void {
    var frame: ?bg.gif.Frame = null;
    if (anim.decoder.next()) |next_frame| {
        frame = next_frame;
    } else |_| {
        anim.pending_state = .failed;
    }

    if (anim.pending_state != .failed and frame == null) {
        if (anim.loop_forever or anim.plays < total_plays) {
            anim.plays +|= 1;
            anim.decoder.rewind();
            if (anim.decoder.next()) |next_frame| {
                frame = next_frame;
            } else |_| {
                anim.pending_state = .failed;
            }
        } else {
            anim.pending_state = .ended;
        }
    }

    if (frame) |decoded_frame| {
        anim.pending = textureFromCanvas(&anim.decoder);
        anim.pending_delay_ms = @max(decoded_frame.delay_ms, minimum_delay_ms);
        anim.pending_state = .frame;
    } else if (anim.pending_state == .frame) {
        anim.pending_state = .failed;
    }

    _ = glib.idleAddOnce(onFrame, anim);
}

fn onFrame(ud: ?*anyopaque) callconv(.c) void {
    const anim: *Animation = @ptrCast(@alignCast(ud orelse return));
    anim.in_flight = false;

    if (anim.cancelled) {
        dispose(anim);
        return;
    }

    anim.has_pending = true;
    if (anim.due) {
        anim.due = false;
        present(anim);
    }
}

fn present(anim: *Animation) void {
    if (!anim.has_pending) return;
    anim.has_pending = false;

    switch (anim.pending_state) {
        .frame => {
            const texture = anim.pending orelse {
                stopFailed(anim);
                return;
            };
            anim.pending = null;
            anim.on_texture(texture);
            anim.timer_id = glib.timeoutAddOnce(anim.pending_delay_ms, onTick, anim);
            anim.on_request_next(anim);
        },
        .ended => {
            anim.stopped = true;
            log.info("background-media: ended", .{});
        },
        .failed => stopFailed(anim),
    }
}

fn onTick(ud: ?*anyopaque) callconv(.c) void {
    const anim: *Animation = @ptrCast(@alignCast(ud orelse return));
    anim.timer_id = 0;
    if (anim.cancelled or anim.stopped) return;
    if (anim.paused) {
        anim.tick_pending = true;
    } else {
        advance(anim);
    }
}

fn advance(anim: *Animation) void {
    if (anim.has_pending) {
        present(anim);
    } else {
        anim.due = true;
    }
}

fn textureFromCanvas(decoder: *const bg.gif.Decoder) *gdk.Texture {
    const bytes = glib.Bytes.new(decoder.canvas.ptr, decoder.canvas.len);
    defer bytes.unref();
    const texture = gdk.MemoryTexture.new(
        @intCast(decoder.width),
        @intCast(decoder.height),
        .r8g8b8a8,
        bytes,
        @as(usize, decoder.width) * 4,
    );
    return texture.as(gdk.Texture);
}

fn stopFailed(anim: *Animation) void {
    if (anim.stopped) return;
    anim.stopped = true;
    log.warn("background-media: animation stopped reason=decode_failed source={s}", .{anim.path});
}

fn dispose(anim: *Animation) void {
    if (anim.pending) |texture| texture.unref();
    anim.decoder.deinit();
    alloc.free(anim.bytes);
    alloc.free(anim.path);
    alloc.destroy(anim);
}
