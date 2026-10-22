const std = @import("std");

const gdk = @import("gdk");
const gobject = @import("gobject");
const gtk = @import("gtk");

const global = @import("../../../global.zig");
const Common = @import("../class.zig").Common;
const pattern = @import("../media_spike_pattern.zig");

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
        start_us: i64 = 0,
        frames: u64 = 0,

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
    }

    fn unrealize(self: *Self) callconv(.c) void {
        const priv = self.private();
        if (priv.tick_id != 0) {
            self.as(gtk.Widget).removeTickCallback(priv.tick_id);
            priv.tick_id = 0;
        }

        gtk.Widget.virtual_methods.unrealize.call(
            Class.parent,
            self.as(gtk.Widget),
        );
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
        if (!priv.enabled) return;

        const widget = self.as(gtk.Widget);
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
