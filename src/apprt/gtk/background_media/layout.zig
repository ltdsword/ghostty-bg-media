const std = @import("std");

pub const Fit = enum { contain, cover, stretch, none };

pub const Position = enum {
    center,
    @"top-left",
    @"top-center",
    @"top-right",
    @"center-left",
    @"center-right",
    @"bottom-left",
    @"bottom-center",
    @"bottom-right",
};

pub const Rect = struct { x: f32, y: f32, width: f32, height: f32 };

pub fn destRect(
    fit: Fit,
    position: Position,
    tex_w: f32,
    tex_h: f32,
    view_w: f32,
    view_h: f32,
) ?Rect {
    if (!std.math.isFinite(tex_w) or !std.math.isFinite(tex_h) or
        !std.math.isFinite(view_w) or !std.math.isFinite(view_h) or
        tex_w <= 0 or tex_h <= 0 or view_w <= 0 or view_h <= 0) return null;

    var dest_w = tex_w;
    var dest_h = tex_h;
    switch (fit) {
        .contain => {
            const scale = @min(view_w / tex_w, view_h / tex_h);
            dest_w *= scale;
            dest_h *= scale;
        },
        .cover => {
            const scale = @max(view_w / tex_w, view_h / tex_h);
            dest_w *= scale;
            dest_h *= scale;
        },
        .stretch => {
            dest_w = view_w;
            dest_h = view_h;
        },
        .none => {},
    }

    const x = switch (horizontal(position)) {
        .start => 0,
        .middle => (view_w - dest_w) / 2,
        .end => view_w - dest_w,
    };
    const y = switch (vertical(position)) {
        .start => 0,
        .middle => (view_h - dest_h) / 2,
        .end => view_h - dest_h,
    };
    return .{ .x = x, .y = y, .width = dest_w, .height = dest_h };
}

const Alignment = enum { start, middle, end };

fn horizontal(position: Position) Alignment {
    return switch (position) {
        .center, .@"top-center", .@"bottom-center" => .middle,
        .@"top-left", .@"center-left", .@"bottom-left" => .start,
        .@"top-right", .@"center-right", .@"bottom-right" => .end,
    };
}

fn vertical(position: Position) Alignment {
    return switch (position) {
        .center, .@"center-left", .@"center-right" => .middle,
        .@"top-left", .@"top-center", .@"top-right" => .start,
        .@"bottom-left", .@"bottom-center", .@"bottom-right" => .end,
    };
}

test "all image fits and positions match shader layout" {
    const Case = struct { position: Position, expected: Rect };
    const FitCase = struct {
        fit: Fit,
        center: Rect,
        top_left: Rect,
        bottom_right: Rect,
    };
    const cases = [_]FitCase{
        .{
            .fit = .contain,
            .center = .{ .x = 20, .y = 0, .width = 160, .height = 100 },
            .top_left = .{ .x = 0, .y = 0, .width = 160, .height = 100 },
            .bottom_right = .{ .x = 40, .y = 0, .width = 160, .height = 100 },
        },
        .{
            .fit = .cover,
            .center = .{ .x = 0, .y = -12.5, .width = 200, .height = 125 },
            .top_left = .{ .x = 0, .y = 0, .width = 200, .height = 125 },
            .bottom_right = .{ .x = 0, .y = -25, .width = 200, .height = 125 },
        },
        .{
            .fit = .stretch,
            .center = .{ .x = 0, .y = 0, .width = 200, .height = 100 },
            .top_left = .{ .x = 0, .y = 0, .width = 200, .height = 100 },
            .bottom_right = .{ .x = 0, .y = 0, .width = 200, .height = 100 },
        },
        .{
            .fit = .none,
            .center = .{ .x = 68, .y = 30, .width = 64, .height = 40 },
            .top_left = .{ .x = 0, .y = 0, .width = 64, .height = 40 },
            .bottom_right = .{ .x = 136, .y = 60, .width = 64, .height = 40 },
        },
    };

    for (cases) |fit_case| {
        const positions = [_]Case{
            .{ .position = .center, .expected = fit_case.center },
            .{ .position = .@"top-left", .expected = fit_case.top_left },
            .{ .position = .@"bottom-right", .expected = fit_case.bottom_right },
        };
        for (positions) |position_case| {
            try std.testing.expectEqual(
                position_case.expected,
                destRect(fit_case.fit, position_case.position, 64, 40, 200, 100).?,
            );
        }
    }
}

test "invalid image and view sizes have no destination rectangle" {
    try std.testing.expectEqual(@as(?Rect, null), destRect(.contain, .center, 64, 40, 0, 100));
    try std.testing.expectEqual(@as(?Rect, null), destRect(.contain, .center, 64, 40, 200, 0));
    try std.testing.expectEqual(@as(?Rect, null), destRect(.contain, .center, 0, 40, 200, 100));
    try std.testing.expectEqual(@as(?Rect, null), destRect(.contain, .center, 64, std.math.nan(f32), 200, 100));
}
