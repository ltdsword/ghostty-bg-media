const std = @import("std");

const gdk = @import("gdk");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");

const global = @import("../../global.zig");
const bg = @import("background_media/main.zig");
const MediaView = @import("class/media_view.zig").MediaView;
const gif_player = @import("gif_player.zig");
const gst_url_player = @import("gst_url_player.zig");
const youtube_resolver = @import("youtube_resolver.zig");

const log = std.log.scoped(.gtk_media_loader);
const alloc = std.heap.c_allocator;

pub const Request = struct {
    id: u64,
    path: [:0]const u8,
    optional: bool,
};

pub const UrlRequest = struct {
    id: u64,
    url: [:0]const u8,
    kind: bg.source.Kind,
};

pub const Settings = struct {
    loop: bool = true,
    volume: f32 = 0,
    play_in_background: bool = false,
    max_fps: u32 = 30,
};

const ViewEntry = struct {
    view: *MediaView,
    active: bool = false,
};

const Status = enum { idle, loading, ready, failed };

const Loader = struct {
    generation: u64 = 0,
    current_id: u64 = 0,
    status: Status = .idle,
    texture: ?*gdk.Texture = null,
    stream: ?*gtk.MediaFile = null,
    url_player: ?*gst_url_player.Player = null,
    url: ?[:0]u8 = null,
    url_kind: bg.source.Kind = .local_file,
    resolved: ?youtube_resolver.Resolved = null,
    resolving: bool = false,
    resolved_live: bool = false,
    failed_attempts: u32 = 0,
    retry_timer: c_uint = 0,
    watchdog_timer: c_uint = 0,
    last_frame_us: i64 = 0,
    awaiting_first_frame: bool = false,
    url_ended: bool = false,
    anim: ?*gif_player.Animation = null,
    invalidate_handler_id: c_ulong = 0,
    error_handler_id: c_ulong = 0,
    ended_handler_id: c_ulong = 0,
    last_redraw_us: ?i64 = null,
    settings: Settings = .{},
    active_views: usize = 0,
    views: std.ArrayListUnmanaged(ViewEntry) = .empty,
};

const Result = union(enum) {
    disabled,
    failed: bg.state.Failure,
    ready: struct {
        texture: *gdk.Texture,
        media_type: bg.source.MediaType,
        dimensions: bg.header.Dimensions,
    },
    animation: struct {
        anim: *gif_player.Animation,
        texture: *gdk.Texture,
        delay_ms: u32,
        dimensions: bg.header.Dimensions,
    },
    video: struct {
        media_type: bg.source.MediaType,
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
var ytdlp_missing_warned = false;

pub fn register(view: *MediaView) void {
    for (loader.views.items) |entry| {
        if (entry.view == view) return;
    }
    loader.views.append(alloc, .{ .view = view }) catch unreachable;
}

pub fn unregister(view: *MediaView) void {
    for (loader.views.items, 0..) |entry, i| {
        if (entry.view == view) {
            if (entry.active) loader.active_views -= 1;
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

pub fn requestUrl(req: UrlRequest) void {
    if (loader.current_id == req.id and
        (loader.status == .loading or loader.status == .ready)) return;

    release();
    loader.generation += 1;
    const url = alloc.dupeZ(u8, req.url) catch {
        loader.current_id = req.id;
        loader.status = .failed;
        var redacted_buf: [512]u8 = undefined;
        log.warn("background-media: failed reason=unreadable source={s}", .{
            bg.source.redactUrl(&redacted_buf, req.url),
        });
        notifyViews();
        return;
    };
    loader.url = url;
    loader.url_kind = req.kind;
    loader.current_id = req.id;
    loader.status = .loading;
    loader.failed_attempts = 0;
    connectUrl();
}

pub fn paintable() ?*gdk.Paintable {
    if (loader.stream) |stream| return stream.as(gdk.Paintable);
    if (loader.texture) |texture_value| return texture_value.as(gdk.Paintable);
    return null;
}

pub fn applySettings(settings: Settings) void {
    loader.settings = settings;
    if (loader.stream) |stream| applyStreamSettings(stream);
    if (loader.url_player) |player| gst_url_player.setVolume(player, settings.volume);
    updatePlayState();
}

pub fn setViewActive(view: *MediaView, active: bool) void {
    for (loader.views.items) |*entry| {
        if (entry.view != view or entry.active == active) continue;
        entry.active = active;
        if (active) {
            loader.active_views += 1;
        } else {
            loader.active_views -= 1;
        }
        updatePlayState();
        return;
    }
}

fn applyStreamSettings(stream: *gtk.MediaFile) void {
    const media_stream = stream.as(gtk.MediaStream);
    media_stream.setLoop(@intFromBool(loader.settings.loop));
    media_stream.setMuted(@intFromBool(loader.settings.volume == 0));
    media_stream.setVolume(@floatCast(loader.settings.volume));
}

fn updatePlayState() void {
    const play = loader.settings.play_in_background or loader.active_views > 0;
    if (loader.url != null) {
        if (!play) {
            if (loader.retry_timer != 0) {
                _ = glib.Source.remove(loader.retry_timer);
                loader.retry_timer = 0;
            }
            if (loader.url_player) |player| {
                if (gst_url_player.isLive(player)) {
                    dropStream();
                    log.info("background-media: live paused (stream released)", .{});
                }
            }
        } else if (loader.url_player == null and loader.retry_timer == 0 and loader.status != .failed) {
            connectUrl();
        }
    }
    if (loader.url_player) |player| gst_url_player.setPlaying(player, play);
    if (loader.stream) |stream| {
        const media_stream = stream.as(gtk.MediaStream);
        if (play) {
            media_stream.play();
        } else {
            media_stream.pause();
        }
    }
    if (loader.anim) |anim| gif_player.setPaused(anim, !play);
}

fn release() void {
    if (loader.anim) |anim| gif_player.destroy(anim);
    loader.anim = null;
    dropStream();
    if (loader.texture) |texture_value| texture_value.unref();
    loader.texture = null;
    if (loader.url) |url| alloc.free(url);
    loader.url = null;
    if (loader.resolved) |resolved| freeResolved(resolved);
    loader.resolved = null;
    loader.resolving = false;
    loader.resolved_live = false;
    if (loader.retry_timer != 0) {
        _ = glib.Source.remove(loader.retry_timer);
        loader.retry_timer = 0;
    }
    if (loader.watchdog_timer != 0) {
        _ = glib.Source.remove(loader.watchdog_timer);
        loader.watchdog_timer = 0;
    }
    loader.failed_attempts = 0;
    loader.awaiting_first_frame = false;
    loader.url_ended = false;
    loader.last_frame_us = 0;
    loader.url_kind = .local_file;
    loader.current_id = 0;
    loader.status = .idle;
    loader.generation += 1;
}

fn dropStream() void {
    if (loader.stream) |stream| {
        const object = stream.as(gobject.Object);
        stream.as(gtk.MediaStream).pause();
        if (loader.invalidate_handler_id != 0) {
            gobject.signalHandlerDisconnect(object, loader.invalidate_handler_id);
        }
        if (loader.error_handler_id != 0) {
            gobject.signalHandlerDisconnect(object, loader.error_handler_id);
        }
        if (loader.ended_handler_id != 0) {
            gobject.signalHandlerDisconnect(object, loader.ended_handler_id);
        }
        stream.unref();
    }
    loader.stream = null;
    loader.invalidate_handler_id = 0;
    loader.error_handler_id = 0;
    loader.ended_handler_id = 0;
    const url_source = loader.url != null or loader.url_player != null;
    if (loader.url_player) |player| gst_url_player.destroy(player);
    loader.url_player = null;
    if (url_source) {
        if (loader.texture) |texture_value| texture_value.unref();
        loader.texture = null;
    }
    loader.last_redraw_us = null;
}

fn connectUrl() void {
    const source_url = loader.url orelse return;
    if (loader.url_kind == .youtube and loader.resolved == null) {
        if (loader.resolving) return;
        loader.resolving = true;
        if (!youtube_resolver.start(source_url, loader.settings.max_fps, loader.generation, onYoutubeResolved)) {
            loader.resolving = false;
            urlFailed("resolve_thread_start");
        }
        return;
    }
    const media_url = if (loader.url_kind == .youtube) loader.resolved.?.url else source_url;
    const player = gst_url_player.create(media_url, loader.settings.volume, .{
        .frame = onUrlFrame,
        .failed = onUrlFailed,
        .ended = onUrlEnded,
    }) orelse {
        urlFailed("player_create");
        return;
    };
    loader.url_player = player;
    loader.url_ended = false;

    const now_us = glib.getMonotonicTime();
    loader.last_frame_us = now_us;
    loader.awaiting_first_frame = true;
    if (loader.watchdog_timer == 0) {
        loader.watchdog_timer = glib.timeoutAdd(1000, onWatchdog, null);
    }
    updatePlayState();

    var redacted_buf: [512]u8 = undefined;
    log.info("background-media: connecting kind={s} source={s} attempt={d}", .{
        @tagName(loader.url_kind),
        bg.source.redactUrl(&redacted_buf, source_url),
        loader.failed_attempts + 1,
    });
}

fn attachStream(stream: *gtk.MediaFile) void {
    loader.stream = stream;
    applyStreamSettings(stream);
    loader.invalidate_handler_id = gdk.Paintable.signals.invalidate_contents.connect(
        stream.as(gdk.Paintable),
        ?*anyopaque,
        onInvalidateContents,
        null,
        .{},
    );
    loader.error_handler_id = gobject.Object.signals.notify.connect(
        stream,
        ?*anyopaque,
        onMediaError,
        null,
        .{ .detail = "error" },
    );
    loader.ended_handler_id = gobject.Object.signals.notify.connect(
        stream,
        ?*anyopaque,
        onMediaEnded,
        null,
        .{ .detail = "ended" },
    );
}

fn urlFailed(reason: []const u8) void {
    const kind = loader.url_kind;
    const retry_kind: bg.source.Kind = if (kind == .youtube)
        (if (loader.resolved_live) .http_hls else .http_direct)
    else
        kind;
    const id = loader.current_id;
    dropStream();
    if (kind == .youtube) {
        if (loader.resolved) |resolved| freeResolved(resolved);
        loader.resolved = null;
        loader.resolving = false;
    }
    const url = loader.url orelse return;
    loader.failed_attempts += 1;

    var redacted_buf: [512]u8 = undefined;
    const redacted_url = bg.source.redactUrl(&redacted_buf, url);
    if (!bg.retry.shouldRetry(retry_kind, loader.failed_attempts)) {
        log.warn("background-media: failed reason=network_gave_up attempts={d} source={s}", .{
            loader.failed_attempts,
            redacted_url,
        });
        release();
        loader.status = .failed;
        loader.current_id = id;
        notifyViews();
        return;
    }

    const delay = bg.retry.delayMs(loader.failed_attempts - 1, @bitCast(glib.getMonotonicTime()));
    log.warn("background-media: reconnect reason={s} attempt={d} delay_ms={d} source={s}", .{
        reason,
        loader.failed_attempts,
        delay,
        redacted_url,
    });
    const play = loader.settings.play_in_background or loader.active_views > 0;
    if (play) loader.retry_timer = glib.timeoutAddOnce(delay, onRetry, null);
    notifyViews();
}

fn onYoutubeResolved(generation: u64, result: *youtube_resolver.Result) void {
    if (generation != loader.generation) return;
    loader.resolving = false;

    switch (result.*) {
        .ok => |resolved| {
            loader.resolved = resolved;
            result.* = .missing;
            loader.resolved_live = resolved.live == .live;
            const title = resolved.title[0..@min(resolved.title.len, 80)];
            log.info("background-media: resolved youtube id={s} title=\"{s}\" format={s} {d}p kind={s} live={s}", .{
                resolved.id,
                title,
                resolved.format_id,
                resolved.height,
                @tagName(resolved.url_kind),
                @tagName(resolved.live),
            });
            connectUrl();
        },
        .fatal => |fatal| {
            loader.status = .failed;
            log.warn("background-media: failed reason={s} source=youtube", .{@tagName(fatal)});
            notifyViews();
        },
        .retriable => |reason| {
            var reason_buf: [128]u8 = undefined;
            const retry_reason = std.fmt.bufPrint(&reason_buf, "resolve_{s}", .{reason}) catch "resolve_failed";
            urlFailed(retry_reason);
        },
        .missing => {
            if (!ytdlp_missing_warned) {
                ytdlp_missing_warned = true;
                log.warn("background-media: failed reason=ytdlp_missing hint=\"install yt-dlp or set GHOSTTY_YTDLP\"", .{});
            }
            loader.status = .failed;
            notifyViews();
        },
    }
}

fn freeResolved(resolved: youtube_resolver.Resolved) void {
    alloc.free(resolved.url);
    alloc.free(resolved.id);
    alloc.free(resolved.title);
    alloc.free(resolved.format_id);
}

fn onRetry(_: ?*anyopaque) callconv(.c) void {
    loader.retry_timer = 0;
    if (loader.url == null) return;
    connectUrl();
}

fn onWatchdog(_: ?*anyopaque) callconv(.c) c_int {
    const url = loader.url orelse {
        loader.watchdog_timer = 0;
        return 0;
    };
    _ = url;

    const now_us = glib.getMonotonicTime();
    const play = loader.settings.play_in_background or loader.active_views > 0;
    if (!play or loader.url_player == null or loader.url_ended) {
        loader.last_frame_us = now_us;
        return 1;
    }
    if (bg.retry.isStalled(loader.last_frame_us, now_us)) urlFailed("stalled");
    return 1;
}

fn notifyViews() void {
    for (loader.views.items) |entry| entry.view.mediaChanged();
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

    var reader_buffer: [bg.header.read_len]u8 = undefined;
    var file_reader = file.reader(global.io(), &reader_buffer);
    var head: [bg.header.read_len]u8 = undefined;
    const read_len = file_reader.interface.readSliceShort(&head) catch {
        return .{ .failed = .unreadable };
    };

    const sniffed = bg.source.sniff(head[0..read_len]);
    const media_type = if (sniffed == .unknown) bg.source.fromExtension(job.path) else sniffed;
    switch (media_type) {
        .video_mp4, .video_webm_mkv => return .{ .video = .{ .media_type = media_type } },
        .image_png, .image_jpeg, .image_webp, .image_gif => {},
        else => return .{ .failed = .unsupported_type },
    }

    const limits: bg.header.Limits = .{};
    if (stat.size > limits.max_file_bytes) return .{ .failed = .too_large };

    const dimensions = bg.header.dimensions(media_type, head[0..read_len]) orelse {
        return .{ .failed = .decode_failed };
    };
    if (bg.header.check(dimensions, stat.size, limits)) |failure| {
        return .{ .failed = failure };
    }

    if (media_type == .image_gif) {
        const byte_count: usize = @intCast(stat.size);
        if (read_len > byte_count) return .{ .failed = .unreadable };
        const bytes = alloc.alloc(u8, byte_count) catch return .{ .failed = .unreadable };
        @memcpy(bytes[0..read_len], head[0..read_len]);
        var offset = read_len;
        while (offset < bytes.len) {
            const count = file_reader.interface.readSliceShort(bytes[offset..]) catch {
                alloc.free(bytes);
                return .{ .failed = .unreadable };
            };
            if (count == 0) {
                alloc.free(bytes);
                return .{ .failed = .unreadable };
            }
            offset += count;
        }

        const created = gif_player.create(bytes, job.path, onAnimationTexture, onAnimationRequest) catch {
            alloc.free(bytes);
            return .{ .failed = .decode_failed };
        };
        return .{ .animation = .{
            .anim = created.anim,
            .texture = created.first_texture,
            .delay_ms = created.first_delay_ms,
            .dimensions = dimensions,
        } };
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
        switch (job.result) {
            .ready => |ready| ready.texture.unref(),
            .animation => |animation| {
                gif_player.destroy(animation.anim);
                animation.texture.unref();
            },
            else => {},
        }
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
        .animation => |animation| {
            loader.texture = animation.texture;
            loader.anim = animation.anim;
            loader.current_id = job.id;
            loader.status = .ready;
            log.info("background-media: loaded type={s} {d}x{d} frames={d}", .{
                @tagName(bg.source.MediaType.image_gif),
                animation.dimensions.width,
                animation.dimensions.height,
                animation.anim.decoder.frame_count,
            });
            if (animation.anim.decoder.frame_count > 1) {
                gif_player.start(
                    animation.anim,
                    gif_player.delayForFrame(animation.delay_ms, loader.settings.max_fps),
                );
            }
            updatePlayState();
        },
        .video => |video| {
            const stream = gtk.MediaFile.newForFilename(job.path);
            loader.current_id = job.id;
            loader.status = .ready;
            attachStream(stream);
            updatePlayState();
            log.info("background-media: playing type={s}", .{@tagName(video.media_type)});
        },
    }

    notifyViews();
}

fn onAnimationTexture(texture: *gdk.Texture) void {
    if (loader.texture) |old_texture| old_texture.unref();
    loader.texture = texture;
    notifyViews();
}

fn onAnimationRequest(anim: *gif_player.Animation) void {
    if (loader.anim != anim) return;
    gif_player.requestNext(anim, loader.settings.loop, loader.settings.max_fps);
}

fn onInvalidateContents(_: *gdk.Paintable, _: ?*anyopaque) callconv(.c) void {
    recordFrame();
}

fn onUrlFrame(texture: *gdk.Texture) void {
    if (loader.texture) |old_texture| old_texture.unref();
    loader.texture = texture;
    recordFrame();
}

fn onUrlFailed() void {
    urlFailed("playback_error");
}

fn onUrlEnded() void {
    const player = loader.url_player orelse return;
    if (gst_url_player.isLive(player)) {
        urlFailed("ended");
    } else if (loader.settings.loop) {
        gst_url_player.rewind(player);
    } else if (!loader.url_ended) {
        loader.url_ended = true;
        log.info("background-media: ended", .{});
    }
}

fn recordFrame() void {
    const now_us = glib.getMonotonicTime();
    loader.last_frame_us = now_us;
    if (loader.awaiting_first_frame) {
        loader.awaiting_first_frame = false;
        if (loader.failed_attempts > 0) {
            log.info("background-media: recovered after attempts={d}", .{loader.failed_attempts});
            loader.failed_attempts = 0;
        }
    }
    if (!bg.cadence.shouldRedraw(loader.last_redraw_us, now_us, loader.settings.max_fps)) return;
    loader.last_redraw_us = now_us;
    notifyViews();
}

fn onMediaError(media_file: *gtk.MediaFile, _: *gobject.ParamSpec, _: ?*anyopaque) callconv(.c) void {
    if (loader.stream != media_file) return;

    const media_stream = media_file.as(gtk.MediaStream);
    const err = media_stream.getError();
    const path = if (media_file.getFile()) |file| file.getPath() else null;
    defer if (path) |path_value| glib.free(path_value);
    log.warn("background-media: failed reason=playback_error source={s} detail={s}", .{
        path orelse "(unknown)",
        if (err) |error_value| error_value.f_message orelse "(no detail)" else "(no detail)",
    });
    release();
    notifyViews();
}

fn onMediaEnded(media_file: *gtk.MediaFile, _: *gobject.ParamSpec, _: ?*anyopaque) callconv(.c) void {
    if (loader.stream == media_file and !loader.settings.loop) {
        log.info("background-media: ended", .{});
    }
}

fn freeJob(job: *Job) void {
    alloc.free(job.path);
    alloc.destroy(job);
}
