const std = @import("std");

pub const Rgba = struct { r: f32, g: f32, b: f32, a: f32 };

pub const tile_px: f32 = 48;

pub fn tileColor(col: i32, row: i32, t_s: f64) Rgba {
    const alpha: f32 = if (@mod(col, 8) == 7) 0.5 else 1.0;
    if (((col + row) & 1) != 0) return .{ .r = 0.15, .g = 0.15, .b = 0.15, .a = alpha };

    const hue = fract(t_s * 0.1 + @as(f64, @floatFromInt(col + row)) * 0.03);
    var color = hsvToRgb(hue, 0.7, 0.9);
    color.a = alpha;
    return color;
}

pub fn scrollOffset(t_s: f64) f32 {
    return @floatCast(@mod(t_s * 60.0, @as(f64, tile_px) * 2));
}

pub fn fract(x: f64) f64 {
    return x - @floor(x);
}

fn hsvToRgb(h: f64, s: f64, v: f64) Rgba {
    const chroma = v * s;
    const h6 = h * 6.0;
    const x = chroma * (1.0 - @abs(@mod(h6, 2.0) - 1.0));
    const m = v - chroma;

    const rgb = if (h6 < 1.0)
        .{ chroma, x, 0.0 }
    else if (h6 < 2.0)
        .{ x, chroma, 0.0 }
    else if (h6 < 3.0)
        .{ 0.0, chroma, x }
    else if (h6 < 4.0)
        .{ 0.0, x, chroma }
    else if (h6 < 5.0)
        .{ x, 0.0, chroma }
    else
        .{ chroma, 0.0, x };

    return .{
        .r = @floatCast(rgb[0] + m),
        .g = @floatCast(rgb[1] + m),
        .b = @floatCast(rgb[2] + m),
        .a = 1.0,
    };
}

test "tile parity alternates" {
    const even = tileColor(0, 0, 0);
    const odd = tileColor(1, 0, 0);
    try std.testing.expect(even.r != odd.r or even.g != odd.g or even.b != odd.b);
}

test "tile alpha stripe" {
    try std.testing.expectEqual(@as(f32, 0.5), tileColor(7, 0, 0).a);
    try std.testing.expectEqual(@as(f32, 1.0), tileColor(6, 0, 0).a);
}

test "scroll offset stays in two-tile range" {
    const offset = scrollOffset(1.5);
    try std.testing.expect(offset >= 0 and offset < tile_px * 2);
}

test "HSV primary red" {
    const red = hsvToRgb(0, 1, 1);
    try std.testing.expect(@abs(red.r - 1.0) < 1e-6);
    try std.testing.expect(@abs(red.g) < 1e-6);
    try std.testing.expect(@abs(red.b) < 1e-6);
}

test "tile colors stay in range" {
    for (0..16) |col| {
        for (0..8) |row| {
            const color = tileColor(@intCast(col), @intCast(row), 12.5);
            try std.testing.expect(color.r >= 0 and color.r <= 1);
            try std.testing.expect(color.g >= 0 and color.g <= 1);
            try std.testing.expect(color.b >= 0 and color.b <= 1);
            try std.testing.expect(color.a >= 0 and color.a <= 1);
        }
    }
}
