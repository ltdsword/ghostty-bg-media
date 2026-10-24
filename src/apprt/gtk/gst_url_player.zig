const std = @import("std");

const gdk = @import("gdk");
const glib = @import("glib");
const gobject = @import("gobject");

const log = std.log.scoped(.gtk_gst_url_player);
const alloc = std.heap.c_allocator;

pub const Callbacks = struct {
    frame: *const fn (*gdk.Texture) void,
    failed: *const fn () void,
    ended: *const fn () void,
};

const MapInfo = extern struct {
    memory: ?*anyopaque,
    flags: c_int,
    data: ?[*]u8,
    size: usize,
    maxsize: usize,
    user_data: [4]?*anyopaque,
    _gst_reserved: [4]?*anyopaque,
};

const Api = struct {
    init_check: *const fn (?*c_int, ?*anyopaque, ?*?*glib.Error) callconv(.c) c_int,
    registry_get: *const fn () callconv(.c) ?*anyopaque,
    registry_get_feature_list_by_plugin: *const fn (*anyopaque, [*:0]const u8) callconv(.c) ?*glib.List,
    plugin_feature_set_rank: *const fn (*anyopaque, c_uint) callconv(.c) void,
    plugin_feature_list_free: *const fn (?*glib.List) callconv(.c) void,
    element_factory_make: *const fn ([*:0]const u8, ?[*:0]const u8) callconv(.c) ?*anyopaque,
    parse_bin_from_description: *const fn ([*:0]const u8, c_int, ?*?*glib.Error) callconv(.c) ?*anyopaque,
    bin_get_by_name: *const fn (*anyopaque, [*:0]const u8) callconv(.c) ?*anyopaque,
    element_set_state: *const fn (*anyopaque, c_int) callconv(.c) c_int,
    element_get_bus: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    bus_add_signal_watch: *const fn (*anyopaque) callconv(.c) void,
    bus_remove_signal_watch: *const fn (*anyopaque) callconv(.c) void,
    object_ref_sink: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    object_unref: *const fn (*anyopaque) callconv(.c) void,
    message_parse_error: *const fn (*anyopaque, ?*?*glib.Error, ?*?[*:0]u8) callconv(.c) void,
    element_query_duration: *const fn (*anyopaque, c_int, *i64) callconv(.c) c_int,
    element_query_position: *const fn (*anyopaque, c_int, *i64) callconv(.c) c_int,
    element_seek_simple: *const fn (*anyopaque, c_int, c_int, i64) callconv(.c) c_int,
    app_sink_pull_sample: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    sample_get_buffer: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    sample_get_caps: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    caps_get_structure: *const fn (*anyopaque, c_uint) callconv(.c) ?*anyopaque,
    structure_get_int: *const fn (*anyopaque, [*:0]const u8, *c_int) callconv(.c) c_int,
    buffer_map: *const fn (*anyopaque, *MapInfo, c_int) callconv(.c) c_int,
    buffer_unmap: *const fn (*anyopaque, *MapInfo) callconv(.c) void,
    mini_object_unref: *const fn (*anyopaque) callconv(.c) void,
};

const ApiState = enum { unloaded, loaded, unavailable };

var api_state: ApiState = .unloaded;
var loaded_api: ?Api = null;
var gst_handle: ?*anyopaque = null;
var gst_app_handle: ?*anyopaque = null;
var unavailable_logged = false;

pub const Player = struct {
    pipeline: *anyopaque,
    bus: *anyopaque,
    sink: *anyopaque,
    callbacks: Callbacks,
    sample_signal_id: c_ulong = 0,
    error_signal_id: c_ulong = 0,
    eos_signal_id: c_ulong = 0,
    bus_watch: bool = true,
    generation: std.atomic.Value(u64) = .init(1),
    pending: std.atomic.Value(bool) = .init(false),
    destroyed: std.atomic.Value(bool) = .init(false),
    ref_count: std.atomic.Value(usize) = .init(1),

    fn retain(self: *Player) void {
        _ = self.ref_count.fetchAdd(1, .monotonic);
    }

    fn release(self: *Player) void {
        if (self.ref_count.fetchSub(1, .acq_rel) == 1) alloc.destroy(self);
    }
};

const Frame = struct {
    player: *Player,
    generation: u64,
    bytes: *glib.Bytes,
    width: c_int,
    height: c_int,
};

pub fn available() bool {
    return getApi() != null;
}

pub fn create(uri: [:0]const u8, volume: f32, callbacks: Callbacks) ?*Player {
    const api = getApi() orelse return null;

    var pipeline: ?*anyopaque = api.element_factory_make("playbin3", null) orelse
        api.element_factory_make("playbin", null) orelse return null;
    _ = api.object_ref_sink(pipeline.?);
    defer if (pipeline) |value| api.object_unref(value);

    var parse_error: ?*glib.Error = null;
    const sink_bin = api.parse_bin_from_description(
        "videoconvert ! videoscale ! appsink name=bgm_sink caps=video/x-raw,format=RGBA,pixel-aspect-ratio=1/1 max-buffers=2 drop=true sync=true emit-signals=true",
        1,
        &parse_error,
    ) orelse {
        if (parse_error) |error_value| error_value.free();
        return null;
    };
    // We own a full ref; playbin takes its own; our deferred unref stays correct.
    _ = api.object_ref_sink(sink_bin);
    defer api.object_unref(sink_bin);
    defer if (parse_error) |error_value| error_value.free();

    var sink: ?*anyopaque = api.bin_get_by_name(sink_bin, "bgm_sink") orelse return null;
    defer if (sink) |value| api.object_unref(value);

    setStringProperty(pipeline.?, "uri", uri);
    setObjectProperty(pipeline.?, "video-sink", sink_bin);
    setVolumeProperties(pipeline.?, volume);
    setBufferingProperties(pipeline.?);

    var bus: ?*anyopaque = api.element_get_bus(pipeline.?) orelse return null;
    defer if (bus) |value| api.object_unref(value);
    api.bus_add_signal_watch(bus.?);
    var bus_watched = true;
    defer if (bus_watched) api.bus_remove_signal_watch(bus.?);

    const player = alloc.create(Player) catch return null;
    player.* = .{
        .pipeline = pipeline.?,
        .bus = bus.?,
        .sink = sink.?,
        .callbacks = callbacks,
    };
    pipeline = null;
    bus = null;
    sink = null;
    bus_watched = false;
    var keep_player = true;
    defer if (keep_player) destroy(player);

    player.sample_signal_id = connectSignal(player.sink, "new-sample", @ptrCast(&onNewSample), player);
    player.error_signal_id = connectSignal(player.bus, "message::error", @ptrCast(&onBusError), player);
    player.eos_signal_id = connectSignal(player.bus, "message::eos", @ptrCast(&onBusEos), player);
    if (player.sample_signal_id == 0 or player.error_signal_id == 0 or player.eos_signal_id == 0) return null;

    keep_player = false;
    return player;
}

pub fn setPlaying(player: *Player, playing: bool) void {
    if (player.destroyed.load(.acquire)) return;
    const api = getApi() orelse return;
    _ = api.element_set_state(player.pipeline, if (playing) 4 else 3);
}

pub fn setVolume(player: *Player, volume: f32) void {
    if (player.destroyed.load(.acquire)) return;
    setVolumeProperties(player.pipeline, volume);
}

pub fn isLive(player: *Player) bool {
    const api = getApi() orelse return true;
    var duration: i64 = 0;
    return api.element_query_duration(player.pipeline, 3, &duration) == 0 or duration <= 0;
}

pub fn timing(player: *Player) ?struct { position_ns: i64, duration_ns: i64 } {
    if (player.destroyed.load(.acquire)) return null;
    const api = getApi() orelse return null;
    var position_ns: i64 = 0;
    var duration_ns: i64 = 0;
    if (api.element_query_position(player.pipeline, 3, &position_ns) == 0 or
        api.element_query_duration(player.pipeline, 3, &duration_ns) == 0 or
        duration_ns <= 0)
    {
        return null;
    }
    return .{ .position_ns = position_ns, .duration_ns = duration_ns };
}

pub fn seekTo(player: *Player, position_ns: i64) void {
    if (player.destroyed.load(.acquire)) return;
    const api = getApi() orelse return;
    _ = api.element_seek_simple(player.pipeline, 3, 1 | 4, position_ns);
}

pub fn rewind(player: *Player) void {
    if (player.destroyed.load(.acquire)) return;
    const api = getApi() orelse return;
    _ = api.element_seek_simple(player.pipeline, 3, 1 | 4, 0);
}

pub fn destroy(player: *Player) void {
    if (player.destroyed.swap(true, .acq_rel)) return;
    const api = getApi() orelse {
        player.release();
        return;
    };

    _ = player.generation.fetchAdd(1, .acq_rel);
    if (player.sample_signal_id != 0) {
        gobject.signalHandlerDisconnect(asObject(player.sink), player.sample_signal_id);
    }
    if (player.error_signal_id != 0) {
        gobject.signalHandlerDisconnect(asObject(player.bus), player.error_signal_id);
    }
    if (player.eos_signal_id != 0) {
        gobject.signalHandlerDisconnect(asObject(player.bus), player.eos_signal_id);
    }
    if (player.bus_watch) api.bus_remove_signal_watch(player.bus);
    api.object_unref(player.bus);
    _ = api.element_set_state(player.pipeline, 1);
    api.object_unref(player.sink);
    api.object_unref(player.pipeline);
    player.release();
}

fn getApi() ?*const Api {
    switch (api_state) {
        .loaded => return &loaded_api.?,
        .unavailable => return null,
        .unloaded => {},
    }

    gst_handle = std.c.dlopen("libgstreamer-1.0.so.0", .{ .LAZY = true }) orelse {
        markUnavailable();
        return null;
    };
    gst_app_handle = std.c.dlopen("libgstapp-1.0.so.0", .{ .LAZY = true }) orelse {
        markUnavailable();
        return null;
    };

    const gst = gst_handle.?;
    const app = gst_app_handle.?;
    const api = Api{
        .init_check = symbol(@TypeOf(@as(Api, undefined).init_check), gst, "gst_init_check") orelse return unavailableApi(),
        .registry_get = symbol(@TypeOf(@as(Api, undefined).registry_get), gst, "gst_registry_get") orelse return unavailableApi(),
        .registry_get_feature_list_by_plugin = symbol(@TypeOf(@as(Api, undefined).registry_get_feature_list_by_plugin), gst, "gst_registry_get_feature_list_by_plugin") orelse return unavailableApi(),
        .plugin_feature_set_rank = symbol(@TypeOf(@as(Api, undefined).plugin_feature_set_rank), gst, "gst_plugin_feature_set_rank") orelse return unavailableApi(),
        .plugin_feature_list_free = symbol(@TypeOf(@as(Api, undefined).plugin_feature_list_free), gst, "gst_plugin_feature_list_free") orelse return unavailableApi(),
        .element_factory_make = symbol(@TypeOf(@as(Api, undefined).element_factory_make), gst, "gst_element_factory_make") orelse return unavailableApi(),
        .parse_bin_from_description = symbol(@TypeOf(@as(Api, undefined).parse_bin_from_description), gst, "gst_parse_bin_from_description") orelse return unavailableApi(),
        .bin_get_by_name = symbol(@TypeOf(@as(Api, undefined).bin_get_by_name), gst, "gst_bin_get_by_name") orelse return unavailableApi(),
        .element_set_state = symbol(@TypeOf(@as(Api, undefined).element_set_state), gst, "gst_element_set_state") orelse return unavailableApi(),
        .element_get_bus = symbol(@TypeOf(@as(Api, undefined).element_get_bus), gst, "gst_element_get_bus") orelse return unavailableApi(),
        .bus_add_signal_watch = symbol(@TypeOf(@as(Api, undefined).bus_add_signal_watch), gst, "gst_bus_add_signal_watch") orelse return unavailableApi(),
        .bus_remove_signal_watch = symbol(@TypeOf(@as(Api, undefined).bus_remove_signal_watch), gst, "gst_bus_remove_signal_watch") orelse return unavailableApi(),
        .object_ref_sink = symbol(@TypeOf(@as(Api, undefined).object_ref_sink), gst, "gst_object_ref_sink") orelse return unavailableApi(),
        .object_unref = symbol(@TypeOf(@as(Api, undefined).object_unref), gst, "gst_object_unref") orelse return unavailableApi(),
        .message_parse_error = symbol(@TypeOf(@as(Api, undefined).message_parse_error), gst, "gst_message_parse_error") orelse return unavailableApi(),
        .element_query_duration = symbol(@TypeOf(@as(Api, undefined).element_query_duration), gst, "gst_element_query_duration") orelse return unavailableApi(),
        .element_query_position = symbol(@TypeOf(@as(Api, undefined).element_query_position), gst, "gst_element_query_position") orelse return unavailableApi(),
        .element_seek_simple = symbol(@TypeOf(@as(Api, undefined).element_seek_simple), gst, "gst_element_seek_simple") orelse return unavailableApi(),
        .app_sink_pull_sample = symbol(@TypeOf(@as(Api, undefined).app_sink_pull_sample), app, "gst_app_sink_pull_sample") orelse return unavailableApi(),
        .sample_get_buffer = symbol(@TypeOf(@as(Api, undefined).sample_get_buffer), gst, "gst_sample_get_buffer") orelse return unavailableApi(),
        .sample_get_caps = symbol(@TypeOf(@as(Api, undefined).sample_get_caps), gst, "gst_sample_get_caps") orelse return unavailableApi(),
        .caps_get_structure = symbol(@TypeOf(@as(Api, undefined).caps_get_structure), gst, "gst_caps_get_structure") orelse return unavailableApi(),
        .structure_get_int = symbol(@TypeOf(@as(Api, undefined).structure_get_int), gst, "gst_structure_get_int") orelse return unavailableApi(),
        .buffer_map = symbol(@TypeOf(@as(Api, undefined).buffer_map), gst, "gst_buffer_map") orelse return unavailableApi(),
        .buffer_unmap = symbol(@TypeOf(@as(Api, undefined).buffer_unmap), gst, "gst_buffer_unmap") orelse return unavailableApi(),
        .mini_object_unref = symbol(@TypeOf(@as(Api, undefined).mini_object_unref), gst, "gst_mini_object_unref") orelse return unavailableApi(),
    };

    if (api.init_check(null, null, null) == 0) return unavailableApi();

    var feature_count: usize = 0;
    if (api.registry_get()) |registry| {
        const plugin_names = [_][:0]const u8{ "va", "vaapi" };
        for (plugin_names) |plugin_name| {
            const features = api.registry_get_feature_list_by_plugin(registry, plugin_name) orelse continue;
            var feature: ?*glib.List = features;
            while (feature) |node| : (feature = node.f_next) {
                if (node.f_data) |value| {
                    api.plugin_feature_set_rank(value, 0);
                    feature_count += 1;
                }
            }
            api.plugin_feature_list_free(features);
        }
    }
    log.info("background-media: hardware video decoders disabled for URL playback (features={d})", .{feature_count});

    loaded_api = api;
    api_state = .loaded;
    return &loaded_api.?;
}

fn unavailableApi() ?*const Api {
    markUnavailable();
    return null;
}

fn markUnavailable() void {
    api_state = .unavailable;
    if (unavailable_logged) return;
    unavailable_logged = true;
    log.warn("background-media: failed reason=gstreamer_unavailable", .{});
}

fn symbol(comptime T: type, handle: *anyopaque, name: [:0]const u8) ?T {
    const address = std.c.dlsym(handle, name) orelse return null;
    return @ptrCast(@alignCast(address));
}

fn setStringProperty(object: *anyopaque, name: [:0]const u8, value: [:0]const u8) void {
    var gvalue = gobject.ext.Value.newFrom(value);
    defer gvalue.unset();
    asObject(object).setProperty(name, &gvalue);
}

fn setObjectProperty(object: *anyopaque, name: [:0]const u8, value: *anyopaque) void {
    var gvalue = gobject.ext.Value.new(?*gobject.Object);
    defer gvalue.unset();
    gobject.ext.Value.set(&gvalue, asObject(value));
    asObject(object).setProperty(name, &gvalue);
}

fn setVolumeProperties(object: *anyopaque, volume: f32) void {
    var volume_value = gobject.ext.Value.newFrom(@as(f64, @floatCast(volume)));
    defer volume_value.unset();
    var mute_value = gobject.ext.Value.newFrom(volume == 0);
    defer mute_value.unset();
    const gobj = asObject(object);
    gobj.setProperty("volume", &volume_value);
    gobj.setProperty("mute", &mute_value);
}

fn setBufferingProperties(object: *anyopaque) void {
    var duration_value = gobject.ext.Value.newFrom(@as(i64, 5_000_000_000));
    defer duration_value.unset();
    var size_value = gobject.ext.Value.newFrom(@as(c_int, 8 * 1024 * 1024));
    defer size_value.unset();

    const gobj = asObject(object);
    gobj.setProperty("buffer-duration", &duration_value);
    gobj.setProperty("buffer-size", &size_value);
}

fn asObject(value: *anyopaque) *gobject.Object {
    return @ptrCast(@alignCast(value));
}

extern "c" fn g_signal_connect_data(
    instance: ?*anyopaque,
    detailed_signal: [*:0]const u8,
    c_handler: ?*const anyopaque,
    data: ?*anyopaque,
    destroy_data: ?*const anyopaque,
    connect_flags: c_uint,
) callconv(.c) c_ulong;

fn connectSignal(
    instance: *anyopaque,
    detailed_signal: [:0]const u8,
    callback: *const anyopaque,
    data: *anyopaque,
) c_ulong {
    return g_signal_connect_data(instance, detailed_signal, callback, data, null, 0);
}

fn onNewSample(sink: ?*anyopaque, data: ?*anyopaque) callconv(.c) c_int {
    const player: *Player = @ptrCast(@alignCast(data orelse return 0));
    const api = getApi() orelse return 0;
    const generation = player.generation.load(.acquire);

    if (player.destroyed.load(.acquire) or player.pending.swap(true, .acq_rel)) {
        if (api.app_sink_pull_sample(sink orelse player.sink)) |sample| api.mini_object_unref(sample);
        return 0;
    }

    const sample = api.app_sink_pull_sample(sink orelse player.sink) orelse {
        player.pending.store(false, .release);
        return 0;
    };
    const buffer = api.sample_get_buffer(sample) orelse {
        api.mini_object_unref(sample);
        player.pending.store(false, .release);
        return 0;
    };
    const caps = api.sample_get_caps(sample) orelse {
        api.mini_object_unref(sample);
        player.pending.store(false, .release);
        return 0;
    };
    const structure = api.caps_get_structure(caps, 0) orelse {
        api.mini_object_unref(sample);
        player.pending.store(false, .release);
        return 0;
    };

    var width: c_int = 0;
    var height: c_int = 0;
    if (api.structure_get_int(structure, "width", &width) == 0 or
        api.structure_get_int(structure, "height", &height) == 0 or
        width <= 0 or height <= 0)
    {
        api.mini_object_unref(sample);
        player.pending.store(false, .release);
        return 0;
    }

    var map_info = std.mem.zeroes(MapInfo);
    if (api.buffer_map(buffer, &map_info, 1) == 0) {
        api.mini_object_unref(sample);
        player.pending.store(false, .release);
        return 0;
    }
    const data_bytes = map_info.data orelse {
        api.buffer_unmap(buffer, &map_info);
        api.mini_object_unref(sample);
        player.pending.store(false, .release);
        return 0;
    };
    const row_width: usize = @intCast(width);
    if (row_width > map_info.size / 4) {
        api.buffer_unmap(buffer, &map_info);
        api.mini_object_unref(sample);
        player.pending.store(false, .release);
        return 0;
    }
    const stride = row_width * 4;
    if (@as(usize, @intCast(height)) > map_info.size / stride) {
        api.buffer_unmap(buffer, &map_info);
        api.mini_object_unref(sample);
        player.pending.store(false, .release);
        return 0;
    }
    const bytes = glib.Bytes.new(data_bytes[0..map_info.size].ptr, map_info.size);
    api.buffer_unmap(buffer, &map_info);
    api.mini_object_unref(sample);

    const frame = alloc.create(Frame) catch {
        bytes.unref();
        player.pending.store(false, .release);
        return 0;
    };
    frame.* = .{
        .player = player,
        .generation = generation,
        .bytes = bytes,
        .width = width,
        .height = height,
    };
    player.retain();
    _ = glib.idleAddOnce(onFrame, frame);
    return 0;
}

fn onFrame(data: ?*anyopaque) callconv(.c) void {
    const frame: *Frame = @ptrCast(@alignCast(data orelse return));
    defer {
        frame.bytes.unref();
        frame.player.release();
        alloc.destroy(frame);
    }

    const player = frame.player;
    player.pending.store(false, .release);
    if (frame.generation != player.generation.load(.acquire) or
        player.destroyed.load(.acquire)) return;

    const texture = gdk.MemoryTexture.new(
        frame.width,
        frame.height,
        .r8g8b8a8,
        frame.bytes,
        @as(usize, @intCast(frame.width)) * 4,
    );
    player.callbacks.frame(texture.as(gdk.Texture));
}

fn onBusError(_: ?*anyopaque, message: ?*anyopaque, data: ?*anyopaque) callconv(.c) void {
    const player: *Player = @ptrCast(@alignCast(data orelse return));
    if (player.destroyed.load(.acquire)) return;
    const api = getApi() orelse return;
    var error_value: ?*glib.Error = null;
    var debug: ?[*:0]u8 = null;
    api.message_parse_error(message orelse return, &error_value, &debug);
    defer if (error_value) |value| value.free();
    defer if (debug) |value| glib.free(value);

    if (error_value) |value| {
        const detail = value.f_message orelse "(no detail)";
        if (std.mem.indexOf(u8, std.mem.span(detail), "://") == null) {
            log.debug("background-media: playback error detail={s}", .{detail});
        }
    }
    player.callbacks.failed();
}

fn onBusEos(_: ?*anyopaque, _: ?*anyopaque, data: ?*anyopaque) callconv(.c) void {
    const player: *Player = @ptrCast(@alignCast(data orelse return));
    if (player.destroyed.load(.acquire)) return;
    player.callbacks.ended();
}
