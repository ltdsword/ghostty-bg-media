const std = @import("std");

const adw = @import("adw");
const gio = @import("gio");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");

const gresource = @import("../build/gresource.zig");
const i18n = @import("../../../os/main.zig").i18n;
const ext = @import("../ext.zig");
const Common = @import("../class.zig").Common;
const Application = @import("application.zig").Application;
const bg = @import("../background_media/main.zig");
const media_config_save = @import("../media_config_save.zig");
const media_loader = @import("../media_loader.zig");
const media_overrides = @import("../media_overrides.zig");

const alloc = std.heap.c_allocator;

pub const MediaPanel = extern struct {
    const Self = @This();
    parent_instance: Parent,
    pub const Parent = adw.Dialog;
    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyMediaPanel",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    const Private = struct {
        syncing: bool = false,
        diagnostics_loaded: bool = false,
        status_timer: c_uint = 0,
        opacity_timer: c_uint = 0,
        quality_heights: [12]u32 = [_]u32{0} ** 12,
        quality_len: u8 = 0,

        toast_overlay: *adw.ToastOverlay,
        source_row: *adw.EntryRow,
        choose_button: *gtk.Button,
        fit_row: *adw.ComboRow,
        position_row: *adw.ComboRow,
        dim_scale: *gtk.Scale,
        blur_scale: *gtk.Scale,
        opacity_row: *adw.ActionRow,
        opacity_scale: *gtk.Scale,
        playback_row: *adw.ActionRow,
        retry_button: *gtk.Button,
        live_button: *gtk.Button,
        play_button: *gtk.Button,
        off_button: *gtk.Button,
        seek_row: *adw.ActionRow,
        seek_scale: *gtk.Scale,
        position_label: *gtk.Label,
        duration_label: *gtk.Label,
        loop_row: *adw.SwitchRow,
        volume_scale: *gtk.Scale,
        background_row: *adw.SwitchRow,
        fps30_button: *gtk.ToggleButton,
        fps60_button: *gtk.ToggleButton,
        quality_row: *adw.ComboRow,
        diag_row: *adw.ExpanderRow,
        gst_row: *adw.ActionRow,
        ytdlp_row: *adw.ActionRow,

        pub var offset: c_int = 0;
    };

    fn init(self: *Self, _: *Class) callconv(.c) void {
        gtk.Widget.initTemplate(self.as(gtk.Widget));
    }

    /// Create a panel with one reference retained until the dialog closes.
    pub fn new() *Self {
        const self = gobject.ext.newInstance(Self, .{});
        _ = self.refSink();
        return self.ref();
    }

    pub fn present(self: *Self, parent_: *gtk.Widget) void {
        const parent: *gtk.Widget = if (ext.getAncestor(adw.ApplicationWindow, parent_)) |window|
            window.as(gtk.Widget)
        else if (ext.getAncestor(adw.Window, parent_)) |window|
            window.as(gtk.Widget)
        else
            parent_;

        self.populate();
        self.updateStatus();
        const priv = self.private();
        if (priv.status_timer != 0) _ = glib.Source.remove(priv.status_timer);
        priv.status_timer = glib.timeoutAdd(1000, statusTimeout, self);
        self.as(adw.Dialog).present(parent);
    }

    fn populate(self: *Self) void {
        const priv = self.private();
        const config_obj = Application.default().getConfig();
        defer config_obj.unref();
        const config = config_obj.get();
        const overrides = media_overrides.get();

        priv.syncing = true;
        defer priv.syncing = false;

        const source_text = switch (overrides.source) {
            .unset => if (config.@"background-media") |configured| switch (configured) {
                .url => |url| url,
                .path => |path| switch (path) {
                    .optional => |value| std.fmt.allocPrintSentinel(alloc, "?{s}", .{value}, 0) catch unreachable,
                    .required => |value| value,
                },
            } else "",
            .none => "",
            .value => |value| value,
        };
        priv.source_row.as(gtk.Editable).setText(source_text);
        priv.source_row.as(gtk.Editable).setPosition(-1);

        const fit = overrides.fit orelse std.meta.stringToEnum(
            bg.layout.Fit,
            @tagName(config.@"background-media-fit"),
        ).?;
        const position = overrides.position orelse std.meta.stringToEnum(
            bg.layout.Position,
            @tagName(config.@"background-media-position"),
        ).?;
        priv.fit_row.setSelected(@intCast(@intFromEnum(fit)));
        priv.position_row.setSelected(@intCast(@intFromEnum(position)));
        priv.dim_scale.as(gtk.Range).setValue(@floatCast(overrides.dim orelse config.@"background-media-dim"));
        priv.blur_scale.as(gtk.Range).setValue(@floatCast(overrides.blur orelse config.@"background-media-blur"));
        priv.opacity_scale.as(gtk.Range).setValue(if (overrides.opacity) |value| @floatCast(value) else Application.default().backgroundOpacity());
        self.syncOpacityHint();
        priv.loop_row.setActive(@intFromBool(overrides.loop orelse config.@"background-media-loop"));
        priv.volume_scale.as(gtk.Range).setValue(@floatCast(overrides.volume orelse config.@"background-media-volume"));
        priv.background_row.setActive(@intFromBool(overrides.play_in_background orelse config.@"background-media-play-in-background"));
        const max_fps = overrides.max_fps orelse config.@"background-media-max-fps";
        priv.fps30_button.setActive(@intFromBool(max_fps == 30));
        priv.fps60_button.setActive(@intFromBool(max_fps == 60));
        priv.quality_row.as(gtk.Widget).setVisible(@intFromBool(priv.quality_len > 0));
        selectQuality(priv, priv.quality_heights[0..priv.quality_len], media_loader.youtubeQualities().current);
    }

    fn onSourceApplied(_: *adw.EntryRow, self: *Self) callconv(.c) void {
        const text = std.mem.span(self.private().source_row.as(gtk.Editable).getText());
        media_overrides.setSource(if (text.len == 0) null else text);
        self.updateStatus();
    }

    fn onUseConfiguration(_: *gtk.Button, self: *Self) callconv(.c) void {
        media_overrides.clearSource();
        self.populate();
        self.updateStatus();
    }

    fn onChooseFile(_: *gtk.Button, self: *Self) callconv(.c) void {
        const dialog = gtk.FileDialog.new();
        dialog.setTitle(i18n._("Choose Background Media"));

        const filters = gio.ListStore.new(gtk.FileFilter.getGObjectType());
        defer filters.as(gobject.Object).unref();
        const filter = gtk.FileFilter.new();
        defer filter.as(gobject.Object).unref();
        filter.setName(i18n._("Images and videos"));
        filter.addMimeType("image/*");
        filter.addMimeType("video/*");
        filters.append(filter.as(gobject.Object));
        dialog.setFilters(filters.as(gio.ListModel));

        const parent = ext.getAncestor(gtk.Window, self.as(gtk.Widget)) orelse {
            dialog.as(gobject.Object).unref();
            return;
        };
        _ = self.ref();
        dialog.open(parent, null, fileDialogOpenReady, self);
        dialog.as(gobject.Object).unref();
    }

    fn fileDialogOpenReady(
        source: ?*gobject.Object,
        result: *gio.AsyncResult,
        user_data: ?*anyopaque,
    ) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(user_data.?));
        defer self.unref();
        const dialog = gobject.ext.cast(gtk.FileDialog, source orelse return) orelse return;
        var err: ?*glib.Error = null;
        defer if (err) |error_value| error_value.free();
        const file = dialog.openFinish(result, &err) orelse return;
        defer file.as(gobject.Object).unref();
        const path = file.getPath() orelse return;
        defer glib.free(path);
        self.private().source_row.as(gtk.Editable).setText(path);
        self.private().source_row.as(gtk.Editable).setPosition(-1);
        onSourceApplied(self.private().source_row, self);
    }

    fn onFitChanged(row: *adw.ComboRow, _: *gobject.ParamSpec, self: *Self) callconv(.c) void {
        if (self.private().syncing) return;
        media_overrides.setFit(@enumFromInt(row.getSelected()));
    }

    fn onPositionChanged(row: *adw.ComboRow, _: *gobject.ParamSpec, self: *Self) callconv(.c) void {
        if (self.private().syncing) return;
        media_overrides.setPosition(@enumFromInt(row.getSelected()));
    }

    fn onDimChanged(scale: *gtk.Scale, self: *Self) callconv(.c) void {
        if (self.private().syncing) return;
        media_overrides.setDim(@floatCast(scale.as(gtk.Range).getValue()));
    }

    fn onBlurChanged(scale: *gtk.Scale, self: *Self) callconv(.c) void {
        if (self.private().syncing) return;
        media_overrides.setBlur(@floatCast(scale.as(gtk.Range).getValue()));
    }

    fn onOpacityChanged(scale: *gtk.Scale, self: *Self) callconv(.c) void {
        const priv = self.private();
        if (priv.syncing) return;

        media_overrides.setOpacity(@floatCast(scale.as(gtk.Range).getValue()));
        self.syncOpacityHint();
        if (priv.opacity_timer != 0) {
            _ = glib.Source.remove(priv.opacity_timer);
            priv.opacity_timer = 0;
        }
        priv.opacity_timer = glib.timeoutAdd(120, opacityTimeout, self);
    }

    fn opacityTimeout(user_data: ?*anyopaque) callconv(.c) c_int {
        const self: *Self = @ptrCast(@alignCast(user_data.?));
        self.private().opacity_timer = 0;
        Application.default().applyOpacityOverride();
        return 0;
    }

    fn syncOpacityHint(self: *Self) void {
        const priv = self.private();
        const opacity = priv.opacity_scale.as(gtk.Range).getValue();
        priv.opacity_row.setSubtitle(if (opacity >= 1) i18n._("Media is hidden at 100%. Lower this to show it.") else "");
    }

    fn onLoopChanged(row: *adw.SwitchRow, _: *gobject.ParamSpec, self: *Self) callconv(.c) void {
        if (self.private().syncing) return;
        media_overrides.setLoop(row.getActive() != 0);
    }

    fn onVolumeChanged(scale: *gtk.Scale, self: *Self) callconv(.c) void {
        if (self.private().syncing) return;
        media_overrides.setVolume(@floatCast(scale.as(gtk.Range).getValue()));
    }

    fn onBackgroundChanged(row: *adw.SwitchRow, _: *gobject.ParamSpec, self: *Self) callconv(.c) void {
        if (self.private().syncing) return;
        media_overrides.setPlayInBackground(row.getActive() != 0);
    }

    fn onFpsToggled(button: *gtk.ToggleButton, self: *Self) callconv(.c) void {
        const priv = self.private();
        if (priv.syncing or button.getActive() == 0) return;
        media_overrides.setMaxFps(if (button == priv.fps30_button) 30 else 60);
    }

    fn onQualityChanged(row: *adw.ComboRow, _: *gobject.ParamSpec, self: *Self) callconv(.c) void {
        const priv = self.private();
        if (priv.syncing) return;
        const selected = row.getSelected();
        if (selected == 0) {
            media_overrides.setYoutubeQuality(0);
        } else if (selected <= @as(u32, priv.quality_len)) {
            media_overrides.setYoutubeQuality(priv.quality_heights[@intCast(selected - 1)]);
        }
    }

    fn onTogglePlay(_: *gtk.Button, self: *Self) callconv(.c) void {
        const text = std.mem.span(self.private().source_row.as(gtk.Editable).getText());
        if (media_overrides.get().source == .none and text.len > 0) {
            media_overrides.setSource(text);
            if (media_overrides.get().paused) media_overrides.setPaused(false);
        } else {
            media_overrides.setPaused(!media_overrides.get().paused);
        }
        self.updateStatus();
    }

    fn onTurnOff(_: *gtk.Button, self: *Self) callconv(.c) void {
        media_overrides.setSource(null);
        self.updateStatus();
    }

    fn onSeekChanged(range: *gtk.Range, _: gtk.ScrollType, value: f64, self: *Self) callconv(.c) c_int {
        _ = range;
        if (!self.private().syncing) media_loader.seek(@intFromFloat(value * 1_000_000));
        return 0;
    }

    fn onRetry(_: *gtk.Button, _: *Self) callconv(.c) void {
        media_loader.retry();
    }

    fn onGoLive(_: *gtk.Button, _: *Self) callconv(.c) void {
        media_loader.goLive();
    }

    fn onDiagnosticsExpanded(row: *adw.ExpanderRow, _: *gobject.ParamSpec, self: *Self) callconv(.c) void {
        const priv = self.private();
        if (priv.diagnostics_loaded or row.getExpanded() == 0) return;
        priv.diagnostics_loaded = true;

        const diagnostics = media_loader.diagnostics();
        priv.gst_row.setSubtitle(if (diagnostics.gst_url_player) i18n._("Available") else i18n._("Not available"));
        if (diagnostics.ytdlp.found) {
            const path = diagnostics.ytdlp.path_buf[0..diagnostics.ytdlp.path_len];
            const suffix = if (diagnostics.ytdlp.override) i18n._(" (GHOSTTY_YTDLP)") else "";
            const subtitle = std.fmt.allocPrintSentinel(alloc, "{s}{s}", .{ path, suffix }, 0) catch unreachable;
            defer alloc.free(subtitle);
            priv.ytdlp_row.setSubtitle(subtitle);
        } else {
            priv.ytdlp_row.setSubtitle(i18n._("Not found: install yt-dlp or set GHOSTTY_YTDLP"));
        }
    }

    fn onSave(_: *gtk.Button, self: *Self) callconv(.c) void {
        const config_obj = Application.default().getConfig();
        defer config_obj.unref();
        const config = config_obj.get();
        const overrides = media_overrides.get();

        const source_text = std.mem.span(self.private().source_row.as(gtk.Editable).getText());
        const source = if (source_text.len == 0) null else source_text;
        const fit = overrides.fit orelse std.meta.stringToEnum(
            bg.layout.Fit,
            @tagName(config.@"background-media-fit"),
        ).?;
        const position = overrides.position orelse std.meta.stringToEnum(
            bg.layout.Position,
            @tagName(config.@"background-media-position"),
        ).?;
        const configured_youtube_quality: u32 = switch (config.@"background-media-youtube-quality") {
            .auto => 0,
            .height => |height| height,
        };
        const values: media_config_save.Values = .{
            .source = source,
            .fit = @tagName(fit),
            .position = @tagName(position),
            .dim = overrides.dim orelse config.@"background-media-dim",
            .blur = overrides.blur orelse config.@"background-media-blur",
            .loop = overrides.loop orelse config.@"background-media-loop",
            .volume = overrides.volume orelse config.@"background-media-volume",
            .play_in_background = overrides.play_in_background orelse config.@"background-media-play-in-background",
            .max_fps = overrides.max_fps orelse config.@"background-media-max-fps",
            .background_opacity = overrides.opacity orelse @floatCast(Application.default().backgroundOpacity()),
            .youtube_quality = overrides.youtube_quality orelse configured_youtube_quality,
        };

        var result = media_config_save.save(alloc, values) catch |err| {
            const message = std.fmt.allocPrintSentinel(alloc, std.mem.span(i18n._("Could not save: {s}")), .{@errorName(err)}, 0) catch unreachable;
            defer alloc.free(message);
            self.addToast(message);
            return;
        };
        defer media_config_save.freeResult(alloc, &result);

        const saved_message = std.fmt.allocPrintSentinel(alloc, std.mem.span(i18n._("Saved to {s}")), .{result.managed_path}, 0) catch unreachable;
        defer alloc.free(saved_message);
        _ = self.as(gtk.Widget).activateAction("app.reload-config", null);
        media_overrides.clearAll();
        Application.default().applyOpacityOverride();
        self.addToast(saved_message);
    }

    fn onReset(_: *gtk.Button, self: *Self) callconv(.c) void {
        media_overrides.clearAll();
        Application.default().applyOpacityOverride();
        self.populate();
        self.updateStatus();
    }

    fn statusTimeout(user_data: ?*anyopaque) callconv(.c) c_int {
        const self: *Self = @ptrCast(@alignCast(user_data.?));
        self.updateStatus();
        return 1;
    }

    fn updateStatus(self: *Self) void {
        const priv = self.private();
        const info = media_loader.statusInfo();
        const pb = media_loader.playback();
        const qualities = media_loader.youtubeQualities();
        var buffer: [512:0]u8 = undefined;
        var len: usize = 0;

        {
            const was_syncing = priv.syncing;
            priv.syncing = true;
            priv.quality_row.as(gtk.Widget).setVisible(@intFromBool(qualities.heights.len > 0));
            if (qualities.heights.len != priv.quality_len or
                !std.mem.eql(u32, qualities.heights, priv.quality_heights[0..priv.quality_len]))
            {
                rebuildQualityList(priv, qualities.heights);
                priv.quality_len = @intCast(qualities.heights.len);
                @memcpy(priv.quality_heights[0..qualities.heights.len], qualities.heights);
            }
            selectQuality(priv, qualities.heights, qualities.current);
            priv.syncing = was_syncing;
        }

        priv.seek_row.as(gtk.Widget).setVisible(@intFromBool(pb.seekable));
        priv.off_button.as(gtk.Widget).setSensitive(@intFromBool(info.has_source));
        if (pb.seekable) {
            const was_syncing = priv.syncing;
            priv.syncing = true;
            defer priv.syncing = was_syncing;

            priv.seek_scale.as(gtk.Range).getAdjustment().setUpper(@as(f64, @floatFromInt(pb.duration_us)) / 1_000_000.0);
            priv.seek_scale.as(gtk.Range).setValue(@as(f64, @floatFromInt(pb.position_us)) / 1_000_000.0);
            var position_buf: [32:0]u8 = undefined;
            var duration_buf: [32:0]u8 = undefined;
            priv.position_label.setLabel(formatTime(&position_buf, pb.position_us));
            priv.duration_label.setLabel(formatTime(&duration_buf, pb.duration_us));
        }

        if (!info.has_source) {
            appendStatus(&buffer, &len, std.mem.span(i18n._("No background media")));
        } else {
            const kind = std.mem.span(if (info.kind) |value| switch (value) {
                .local_file => i18n._("Local file"),
                .http_direct => i18n._("Web video"),
                .http_hls => i18n._("HLS stream"),
                .youtube => i18n._("YouTube"),
            } else "");
            appendStatus(&buffer, &len, kind);
            appendStatus(&buffer, &len, " · ");
            switch (info.status) {
                .idle => appendStatus(&buffer, &len, std.mem.span(i18n._("Idle"))),
                .loading => appendStatus(&buffer, &len, std.mem.span(i18n._("Loading"))),
                .ready => appendStatus(&buffer, &len, std.mem.span(if (info.still) i18n._("Showing") else if (info.playing) i18n._("Playing") else i18n._("Paused"))),
                .failed => {
                    appendStatus(&buffer, &len, std.mem.span(i18n._("Failed: ")));
                    appendStatus(&buffer, &len, info.failure);
                },
            }
        }

        if (info.live.is_live) appendStatus(&buffer, &len, std.mem.span(i18n._(" · LIVE")));
        switch (info.live.state) {
            .waiting_upcoming => appendStatus(&buffer, &len, std.mem.span(i18n._(" · Waiting for the stream to start"))),
            .reconnecting => appendReconnectStatus(&buffer, &len, info.attempts),
            .ended => appendStatus(&buffer, &len, std.mem.span(i18n._(" · Stream ended"))),
            else => if (info.retry_pending) appendReconnectStatus(&buffer, &len, info.attempts),
        }

        priv.playback_row.setSubtitle(buffer[0..len :0]);
        priv.retry_button.as(gtk.Widget).setVisible(@intFromBool(info.status == .failed or info.retry_pending));
        priv.live_button.as(gtk.Widget).setVisible(@intFromBool(info.live.is_live));
        priv.play_button.setLabel(if (media_overrides.get().paused or media_overrides.get().source == .none) i18n._("Play") else i18n._("Pause"));
        priv.play_button.as(gtk.Widget).setSensitive(@intFromBool(!info.still));
    }

    fn appendStatus(buffer: *[512:0]u8, len: *usize, text: []const u8) void {
        const count = @min(text.len, buffer.len - len.* - 1);
        @memcpy(buffer[len.*..][0..count], text[0..count]);
        len.* += count;
        buffer[len.*] = 0;
    }

    fn appendReconnectStatus(buffer: *[512:0]u8, len: *usize, attempts: u32) void {
        const suffix = std.fmt.bufPrint(buffer[len.*..], std.mem.span(i18n._(" · Reconnecting (attempt {d})")), .{attempts}) catch return;
        len.* += suffix.len;
        buffer[len.*] = 0;
    }

    fn rebuildQualityList(priv: *Private, heights: []const u32) void {
        const list_model = priv.quality_row.getModel().?;
        const model = gobject.ext.cast(gtk.StringList, list_model) orelse unreachable;
        while (list_model.getNItems() > 0) model.remove(0);
        model.append(i18n._("Auto (720p)"));
        for (heights) |height| {
            const suffix = if (height > 1080) std.mem.span(i18n._(" (high CPU)")) else "";
            const label = std.fmt.allocPrintSentinel(alloc, "{d}p{s}", .{ height, suffix }, 0) catch unreachable;
            defer alloc.free(label);
            model.append(label);
        }
    }

    fn selectQuality(priv: *Private, heights: []const u32, quality: u32) void {
        if (heights.len == 0) return;
        if (quality == 0) {
            priv.quality_row.setSelected(0);
            return;
        }
        var selected: u32 = 1;
        for (heights, 0..) |height, index| {
            if (height > quality) break;
            selected = @intCast(index + 1);
        }
        priv.quality_row.setSelected(selected);
    }

    fn formatTime(buffer: *[32:0]u8, microseconds: i64) [:0]const u8 {
        const total_seconds: u64 = @intCast(@max(microseconds, 0) / 1_000_000);
        const hours = total_seconds / 3600;
        const formatted = if (hours > 0)
            std.fmt.bufPrint(buffer[0..], "{d}:{d:0>2}:{d:0>2}", .{ hours, (total_seconds / 60) % 60, total_seconds % 60 }) catch unreachable
        else
            std.fmt.bufPrint(buffer[0..], "{d}:{d:0>2}", .{ total_seconds / 60, total_seconds % 60 }) catch unreachable;
        buffer[formatted.len] = 0;
        return buffer[0..formatted.len :0];
    }

    fn addToast(self: *Self, title: [*:0]const u8) void {
        const toast = adw.Toast.new(title);
        toast.setTimeout(3);
        self.private().toast_overlay.addToast(toast);
    }

    fn onClosed(_: *adw.Dialog, self: *Self) callconv(.c) void {
        self.stopStatusTimer();
        self.unref();
    }

    fn stopStatusTimer(self: *Self) void {
        const priv = self.private();
        if (priv.status_timer == 0) return;
        _ = glib.Source.remove(priv.status_timer);
        priv.status_timer = 0;
    }

    fn dispose(self: *Self) callconv(.c) void {
        self.stopStatusTimer();
        const priv = self.private();
        if (priv.opacity_timer != 0) {
            _ = glib.Source.remove(priv.opacity_timer);
            priv.opacity_timer = 0;
        }
        gtk.Widget.disposeTemplate(self.as(gtk.Widget), getGObjectType());
        gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
    }

    const C = Common(Self, Private);
    pub const as = C.as;
    pub const ref = C.ref;
    pub const refSink = C.refSink;
    pub const unref = C.unref;
    const private = C.private;

    pub const Class = extern struct {
        parent_class: Parent.Class,
        var parent: *Parent.Class = undefined;
        pub const Instance = Self;

        fn init(class: *Class) callconv(.c) void {
            gtk.Widget.Class.setTemplateFromResource(
                class.as(gtk.Widget.Class),
                comptime gresource.blueprint(.{ .major = 1, .minor = 5, .name = "media-panel" }),
            );

            class.bindTemplateChildPrivate("toast_overlay", .{});
            class.bindTemplateChildPrivate("source_row", .{});
            class.bindTemplateChildPrivate("choose_button", .{});
            class.bindTemplateChildPrivate("fit_row", .{});
            class.bindTemplateChildPrivate("position_row", .{});
            class.bindTemplateChildPrivate("dim_scale", .{});
            class.bindTemplateChildPrivate("blur_scale", .{});
            class.bindTemplateChildPrivate("opacity_row", .{});
            class.bindTemplateChildPrivate("opacity_scale", .{});
            class.bindTemplateChildPrivate("playback_row", .{});
            class.bindTemplateChildPrivate("retry_button", .{});
            class.bindTemplateChildPrivate("live_button", .{});
            class.bindTemplateChildPrivate("play_button", .{});
            class.bindTemplateChildPrivate("off_button", .{});
            class.bindTemplateChildPrivate("seek_row", .{});
            class.bindTemplateChildPrivate("seek_scale", .{});
            class.bindTemplateChildPrivate("position_label", .{});
            class.bindTemplateChildPrivate("duration_label", .{});
            class.bindTemplateChildPrivate("loop_row", .{});
            class.bindTemplateChildPrivate("volume_scale", .{});
            class.bindTemplateChildPrivate("background_row", .{});
            class.bindTemplateChildPrivate("fps30_button", .{});
            class.bindTemplateChildPrivate("fps60_button", .{});
            class.bindTemplateChildPrivate("quality_row", .{});
            class.bindTemplateChildPrivate("diag_row", .{});
            class.bindTemplateChildPrivate("gst_row", .{});
            class.bindTemplateChildPrivate("ytdlp_row", .{});

            class.bindTemplateCallback("closed", &onClosed);
            class.bindTemplateCallback("source_applied", &onSourceApplied);
            class.bindTemplateCallback("choose_file", &onChooseFile);
            class.bindTemplateCallback("use_configuration", &onUseConfiguration);
            class.bindTemplateCallback("fit_changed", &onFitChanged);
            class.bindTemplateCallback("position_changed", &onPositionChanged);
            class.bindTemplateCallback("dim_changed", &onDimChanged);
            class.bindTemplateCallback("blur_changed", &onBlurChanged);
            class.bindTemplateCallback("opacity_changed", &onOpacityChanged);
            class.bindTemplateCallback("loop_changed", &onLoopChanged);
            class.bindTemplateCallback("volume_changed", &onVolumeChanged);
            class.bindTemplateCallback("background_changed", &onBackgroundChanged);
            class.bindTemplateCallback("fps_toggled", &onFpsToggled);
            class.bindTemplateCallback("quality_changed", &onQualityChanged);
            class.bindTemplateCallback("toggle_play", &onTogglePlay);
            class.bindTemplateCallback("turn_off", &onTurnOff);
            class.bindTemplateCallback("seek_changed", &onSeekChanged);
            class.bindTemplateCallback("retry", &onRetry);
            class.bindTemplateCallback("go_live", &onGoLive);
            class.bindTemplateCallback("diagnostics_expanded", &onDiagnosticsExpanded);
            class.bindTemplateCallback("save", &onSave);
            class.bindTemplateCallback("reset", &onReset);

            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
        }

        pub const as = C.Class.as;
        pub const bindTemplateChildPrivate = C.Class.bindTemplateChildPrivate;
        pub const bindTemplateCallback = C.Class.bindTemplateCallback;
    };
};
