const std = @import("std");

pub const I420Layout = struct {
    y_stride: usize,
    c_stride: usize,
    u_offset: usize,
    v_offset: usize,
    size: usize,
    width: usize,
    height: usize,
};

pub fn i420Layout(width: usize, height: usize) ?I420Layout {
    if (width < 2 or height < 2) return null;

    const y_stride = (width + 3) & ~@as(usize, 3);
    const c_width = (width + 1) / 2;
    const c_stride = (c_width + 3) & ~@as(usize, 3);
    const rounded_height = (height + 1) & ~@as(usize, 1);
    const c_height = (height + 1) / 2;
    const u_offset = y_stride * rounded_height;
    const v_offset = u_offset + c_stride * (rounded_height / 2);
    const size = v_offset + c_stride * c_height;

    return .{
        .y_stride = y_stride,
        .c_stride = c_stride,
        .u_offset = u_offset,
        .v_offset = v_offset,
        .size = size,
        .width = width & ~@as(usize, 1),
        .height = height & ~@as(usize, 1),
    };
}

test "I420 layout for 1920x1080" {
    const layout = i420Layout(1920, 1080).?;
    try std.testing.expectEqual(@as(usize, 1920), layout.y_stride);
    try std.testing.expectEqual(@as(usize, 960), layout.c_stride);
    try std.testing.expectEqual(@as(usize, 2073600), layout.u_offset);
    try std.testing.expectEqual(@as(usize, 2592000), layout.v_offset);
    try std.testing.expectEqual(@as(usize, 3110400), layout.size);
}

test "I420 layout for odd 1281x721" {
    const layout = i420Layout(1281, 721).?;
    try std.testing.expectEqual(@as(usize, 1284), layout.y_stride);
    try std.testing.expectEqual(@as(usize, 644), layout.c_stride);
    try std.testing.expectEqual(@as(usize, 927048), layout.u_offset);
    try std.testing.expectEqual(@as(usize, 1159532), layout.v_offset);
    try std.testing.expectEqual(@as(usize, 1392016), layout.size);
    try std.testing.expectEqual(@as(usize, 1280), layout.width);
    try std.testing.expectEqual(@as(usize, 720), layout.height);
}

test "I420 layout rejects dimensions smaller than two" {
    try std.testing.expect(i420Layout(1, 1) == null);
}
