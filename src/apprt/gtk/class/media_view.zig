const std = @import("std");

const gdk = @import("gdk");
const gobject = @import("gobject");
const gtk = @import("gtk");

const global = @import("../../../global.zig");
const Common = @import("../class.zig").Common;
const pattern = @import("../media_spike_pattern.zig");
const bg = @import("../background_media/main.zig");
const media_loader = @import("../media_loader.zig");
const Application = @import("application.zig").Application;

const log = std.log.scoped(.gtk_media_view);

pub const MediaView = extern struct {
    const Self = @This();
    parent_instance: Parent,
    pub const Parent = gtk.Widget;
    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyMediaView",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    const C = Common(Self, Private);

    pub const Private = struct {
        enabled: bool = false,
        tick_id: c_uint = 0,
        state: bg.state.State = .disabled,
        config_notify_id: c_ulong = 0,
        start_us: i64 = 0,
        frames: u64 = 0,
        fit: bg.layout.Fit = .cover,
        position: bg.layout.Position = .center,
        dim: f32 = 0,
        bg_rgb: struct { r: u8, g: u8, b: u8 } = .{ .r = 0, .g = 0, .b = 0 },

        pub var offset: c_int = 0;
    };

    const private = C.private;
    pub const as = C.as;

    fn init(self: *Self, _: *Class) callconv(.c) void {
        const priv = self.private();
        if (global.environ().getPosix("GHOSTTY_BGM_SPIKE")) |value| {
            priv.enabled = std.mem.eql(u8, value, "1");
        }

        const widget = self.as(gtk.Widget);
        widget.setCanTarget(0);
        widget.setFocusable(0);
        widget.setCanFocus(0);
        widget.setHexpand(1);
        widget.setVexpand(1);

        if (priv.enabled) log.info("GHOSTTY_BGM_SPIKE=1: media view enabled", .{});
    }

    fn realize(self: *Self) callconv(.c) void {
        gtk.Widget.virtual_methods.realize.call(
            Class.parent,
            self.as(gtk.Widget),
        );

        const priv = self.private();
        if (priv.enabled) {
            priv.tick_id = self.as(gtk.Widget).addTickCallback(tick, null, null);
        }

        const app = Application.default();
        priv.config_notify_id = gobject.Object.signals.notify.connect(
            app,
            *Self,
            onConfigNotify,
            self,
            .{ .detail = "config" },
        );
        media_loader.register(self);
        self.applyConfig();
    }

    fn unrealize(self: *Self) callconv(.c) void {
        const priv = self.private();
        media_loader.unregister(self);
        if (priv.config_notify_id != 0) {
            gobject.signalHandlerDisconnect(
                Application.default().as(gobject.Object),
                priv.config_notify_id,
            );
            priv.config_notify_id = 0;
        }

        if (priv.tick_id != 0) {
            self.as(gtk.Widget).removeTickCallback(priv.tick_id);
            priv.tick_id = 0;
        }

        gtk.Widget.virtual_methods.unrealize.call(
            Class.parent,
            self.as(gtk.Widget),
        );
    }

    fn onConfigNotify(
        _: *Application,
        _: *gobject.ParamSpec,
        self: *Self,
    ) callconv(.c) void {
        self.applyConfig();
    }

    fn applyConfig(self: *Self) void {
        const priv = self.private();
        const config_obj = Application.default().getConfig();
        defer config_obj.unref();
        const config = config_obj.get();

        priv.fit = std.meta.stringToEnum(bg.layout.Fit, @tagName(config.@"background-media-fit")).?;
        priv.position = std.meta.stringToEnum(bg.layout.Position, @tagName(config.@"background-media-position")).?;
        priv.dim = config.@"background-media-dim";
        priv.bg_rgb = .{
            .r = config.background.r,
            .g = config.background.g,
            .b = config.background.b,
        };

        if (config.@"background-media") |source| {
            switch (source) {
                .url => |url| {
                    media_loader.request(null);
                    var next_state: bg.state.State = undefined;
                    if (bg.source.classifyUrl(url)) |kind| {
                        next_state = .{ .ready = .{
                            .kind = kind,
                            .media_type = .unknown,
                            .source_id = bg.state.sourceId(url),
                        } };
                    } else {
                        next_state = .{ .failed = .invalid_url };
                    }

                    const changed = !std.meta.eql(priv.state, next_state);
                    const action = bg.state.reconcile(priv.state, next_state);
                    priv.state = next_state;

                    if (next_state == .failed and changed) {
                        log.warn("background-media: {s} state=failed reason={s} source={s}", .{
                            @tagName(action),
                            @tagName(next_state.failed),
                            url,
                        });
                    } else if (action != .none) {
                        switch (next_state) {
                            .disabled => log.info("background-media: {s} state=disabled kind=none type=none", .{
                                @tagName(action),
                            }),
                            .ready => |ready| log.info("background-media: {s} state=ready kind={s} type={s}", .{
                                @tagName(action),
                                @tagName(ready.kind),
                                @tagName(ready.media_type),
                            }),
                            .failed => unreachable,
                        }
                    }
                },
                .path => |path| {
                    const path_value, const optional = switch (path) {
                        .optional => |value| .{ value, true },
                        .required => |value| .{ value, false },
                    };
                    media_loader.request(.{
                        .id = bg.state.sourceId(path_value),
                        .path = path_value,
                        .optional = optional,
                    });
                    priv.state = .disabled;
                },
            }
        } else {
            media_loader.request(null);
            priv.state = .disabled;
        }

        self.as(gtk.Widget).queueDraw();
    }

    pub fn mediaChanged(self: *Self) void {
        self.as(gtk.Widget).queueDraw();
    }

    fn tick(
        widget: *gtk.Widget,
        frame_clock: *gdk.FrameClock,
        _: ?*anyopaque,
    ) callconv(.c) c_int {
        const self: *Self = gobject.ext.cast(Self, widget) orelse return 0;
        const priv = self.private();
        if (priv.start_us == 0) priv.start_us = frame_clock.getFrameTime();
        widget.queueDraw();
        return 1;
    }

    fn snapshot(self: *Self, snap: *gtk.Snapshot) callconv(.c) void {
        const priv = self.private();
        const widget = self.as(gtk.Widget);
        if (priv.enabled) {
            const frame_time = if (widget.getFrameClock()) |clock|
                clock.getFrameTime()
            else
                priv.start_us;
            const t_s: f64 = if (widget.getFrameClock() != null)
                @as(f64, @floatFromInt(frame_time - priv.start_us)) / 1_000_000.0
            else
                0;
            const w: f32 = @floatFromInt(widget.getWidth());
            const h: f32 = @floatFromInt(widget.getHeight());
            const off = pattern.scrollOffset(t_s);

            var row: i32 = -1;
            var y: f32 = -pattern.tile_px;
            while (y <= h) : (y += pattern.tile_px) {
                var col: i32 = -3;
                while (true) : (col += 1) {
                    const x = @as(f32, @floatFromInt(col)) * pattern.tile_px + off;
                    if (x > w) break;

                    const color = pattern.tileColor(col, row, t_s);
                    const rgba = gdk.RGBA{
                        .f_red = color.r,
                        .f_green = color.g,
                        .f_blue = color.b,
                        .f_alpha = color.a,
                    };
                    snap.appendColor(&rgba, &.{
                        .f_origin = .{ .f_x = x, .f_y = y },
                        .f_size = .{ .f_width = pattern.tile_px, .f_height = pattern.tile_px },
                    });
                }
                row += 1;
            }

            var text_buffer: [96:0]u8 = undefined;
            const timestamp = std.fmt.bufPrintZ(
                &text_buffer,
                "BGM SPIKE t={d:.2}s frame={d}",
                .{ t_s, priv.frames },
            ) catch unreachable;
            const layout = widget.createPangoLayout(timestamp.ptr);
            const white = gdk.RGBA{
                .f_red = 1.0,
                .f_green = 1.0,
                .f_blue = 1.0,
                .f_alpha = 1.0,
            };
            snap.save();
            snap.translate(&.{ .f_x = 16, .f_y = 16 });
            snap.appendLayout(layout, &white);
            snap.restore();
            layout.as(gobject.Object).unref();

            priv.frames += 1;
            return;
        }

        const texture_value = media_loader.texture() orelse return;
        const width: f32 = @floatFromInt(widget.getWidth());
        const height: f32 = @floatFromInt(widget.getHeight());
        const dest = bg.layout.destRect(
            priv.fit,
            priv.position,
            @floatFromInt(texture_value.getWidth()),
            @floatFromInt(texture_value.getHeight()),
            width,
            height,
        ) orelse return;

        snap.pushClip(&.{
            .f_origin = .{ .f_x = 0, .f_y = 0 },
            .f_size = .{ .f_width = width, .f_height = height },
        });
        snap.appendTexture(texture_value, &.{
            .f_origin = .{ .f_x = dest.x, .f_y = dest.y },
            .f_size = .{ .f_width = dest.width, .f_height = dest.height },
        });
        if (priv.dim > 0) {
            const color = gdk.RGBA{
                .f_red = @as(f32, @floatFromInt(priv.bg_rgb.r)) / 255.0,
                .f_green = @as(f32, @floatFromInt(priv.bg_rgb.g)) / 255.0,
                .f_blue = @as(f32, @floatFromInt(priv.bg_rgb.b)) / 255.0,
                .f_alpha = priv.dim,
            };
            snap.appendColor(&color, &.{
                .f_origin = .{ .f_x = 0, .f_y = 0 },
                .f_size = .{ .f_width = width, .f_height = height },
            });
        }
        snap.pop();
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,
        var parent: *Parent.Class = undefined;
        pub const Instance = Self;

        fn init(class: *Class) callconv(.c) void {
            gtk.Widget.virtual_methods.realize.implement(class, &realize);
            gtk.Widget.virtual_methods.unrealize.implement(class, &unrealize);
            gtk.Widget.virtual_methods.snapshot.implement(class, &snapshot);
        }

        pub const as = C.Class.as;
    };
};
