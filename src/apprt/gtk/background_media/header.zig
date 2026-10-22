const std = @import("std");
const source = @import("source.zig");
const state = @import("state.zig");

pub const read_len = 65536;

pub const Dimensions = struct { width: u32, height: u32 };

pub const Limits = struct {
    max_side: u32 = 16384,
    max_pixels: u64 = 67_108_864,
    max_file_bytes: u64 = 268_435_456,
};

pub fn dimensions(media_type: source.MediaType, bytes: []const u8) ?Dimensions {
    return switch (media_type) {
        .image_png => pngDimensions(bytes),
        .image_jpeg => jpegDimensions(bytes),
        .image_webp => webpDimensions(bytes),
        .image_gif => gifDimensions(bytes),
        else => null,
    };
}

fn gifDimensions(bytes: []const u8) ?Dimensions {
    if (bytes.len < 10 or (!std.mem.eql(u8, bytes[0..6], "GIF87a") and
        !std.mem.eql(u8, bytes[0..6], "GIF89a"))) return null;

    const width = readLe16(bytes, 6);
    const height = readLe16(bytes, 8);
    if (width == 0 or height == 0) return null;
    return .{ .width = width, .height = height };
}

fn pngDimensions(bytes: []const u8) ?Dimensions {
    if (bytes.len < 24 or !std.mem.eql(u8, bytes[12..16], "IHDR")) return null;
    return .{ .width = readBe32(bytes, 16), .height = readBe32(bytes, 20) };
}

fn jpegDimensions(bytes: []const u8) ?Dimensions {
    if (bytes.len < 2 or bytes[0] != 0xFF or bytes[1] != 0xD8) return null;

    var index: usize = 2;
    while (index < bytes.len) {
        if (bytes[index] != 0xFF) return null;
        while (index < bytes.len and bytes[index] == 0xFF) : (index += 1) {}
        if (index == bytes.len) return null;

        const marker = bytes[index];
        index += 1;
        if (marker == 0xDA) return null;
        if (isJpegStandalone(marker)) continue;

        const seg = index;
        if (bytes.len - seg < 2) return null;
        const segment_len = readBe16(bytes, seg);
        if (segment_len < 2) return null;
        const segment_end = seg + segment_len;
        if (segment_end > bytes.len) return null;

        if (isJpegSof(marker)) {
            if (segment_len < 7 or bytes.len - seg < 7) return null;
            return .{ .height = readBe16(bytes, seg + 3), .width = readBe16(bytes, seg + 5) };
        }

        index = segment_end;
    }
    return null;
}

fn isJpegStandalone(marker: u8) bool {
    return marker == 0x01 or (marker >= 0xD0 and marker <= 0xD9);
}

fn isJpegSof(marker: u8) bool {
    return marker >= 0xC0 and marker <= 0xCF and
        marker != 0xC4 and marker != 0xC8 and marker != 0xCC;
}

fn webpDimensions(bytes: []const u8) ?Dimensions {
    if (bytes.len < 16 or !std.mem.eql(u8, bytes[0..4], "RIFF") or
        !std.mem.eql(u8, bytes[8..12], "WEBP")) return null;

    if (std.mem.eql(u8, bytes[12..16], "VP8 ")) {
        if (bytes.len < 30) return null;
        return .{
            .width = readLe16(bytes, 26) & 0x3FFF,
            .height = readLe16(bytes, 28) & 0x3FFF,
        };
    }

    if (std.mem.eql(u8, bytes[12..16], "VP8L")) {
        if (bytes.len < 25) return null;
        const b0: u32 = bytes[21];
        const b1: u32 = bytes[22];
        const b2: u32 = bytes[23];
        const b3: u32 = bytes[24];
        return .{
            .width = 1 + (b0 | ((b1 & 0x3F) << 8)),
            .height = 1 + ((b1 >> 6) | (b2 << 2) | ((b3 & 0x0F) << 10)),
        };
    }

    if (std.mem.eql(u8, bytes[12..16], "VP8X")) {
        if (bytes.len < 30) return null;
        return .{
            .width = 1 + readLe24(bytes, 24),
            .height = 1 + readLe24(bytes, 27),
        };
    }

    return null;
}

fn readBe16(bytes: []const u8, index: usize) u16 {
    return (@as(u16, bytes[index]) << 8) | bytes[index + 1];
}

fn readBe32(bytes: []const u8, index: usize) u32 {
    return (@as(u32, bytes[index]) << 24) |
        (@as(u32, bytes[index + 1]) << 16) |
        (@as(u32, bytes[index + 2]) << 8) |
        bytes[index + 3];
}

fn readLe16(bytes: []const u8, index: usize) u16 {
    return @as(u16, bytes[index]) | (@as(u16, bytes[index + 1]) << 8);
}

fn readLe24(bytes: []const u8, index: usize) u32 {
    return @as(u32, bytes[index]) |
        (@as(u32, bytes[index + 1]) << 8) |
        (@as(u32, bytes[index + 2]) << 16);
}

pub fn check(dim: Dimensions, file_bytes: u64, limits: Limits) ?state.Failure {
    if (dim.width == 0 or dim.height == 0 or dim.width > limits.max_side or
        dim.height > limits.max_side or file_bytes > limits.max_file_bytes or
        @as(u64, dim.width) * dim.height > limits.max_pixels) return .too_large;
    return null;
}

test "fixture image headers report dimensions and sniff types" {
    const Fixture = struct { bytes: []const u8, media_type: source.MediaType };
    const fixtures = [_]Fixture{
        .{ .bytes = @embedFile("testdata/a.png"), .media_type = .image_png },
        .{ .bytes = @embedFile("testdata/a.jpg"), .media_type = .image_jpeg },
        .{ .bytes = @embedFile("testdata/a-lossy.webp"), .media_type = .image_webp },
        .{ .bytes = @embedFile("testdata/a-lossless.webp"), .media_type = .image_webp },
    };

    for (fixtures) |fixture| {
        try std.testing.expectEqual(fixture.media_type, source.sniff(fixture.bytes));
        try std.testing.expectEqual(
            @as(?Dimensions, .{ .width = 64, .height = 40 }),
            dimensions(fixture.media_type, fixture.bytes),
        );
    }
}

test "truncated PNG keeps dimensions available in its IHDR" {
    const bytes = @embedFile("testdata/corrupt.png");
    try std.testing.expectEqual(source.MediaType.image_png, source.sniff(bytes));
    try std.testing.expectEqual(
        @as(?Dimensions, .{ .width = 64, .height = 40 }),
        dimensions(.image_png, bytes),
    );
}

test "dimension limits reject oversized sides pixels files and zero dimensions" {
    var png = makePngHeader(16385, 1);
    const png_dim = dimensions(.image_png, &png).?;
    try std.testing.expectEqual(state.Failure.too_large, check(png_dim, 24, .{}).?);

    const too_many_pixels = makeVp8xHeader(9000, 9000);
    const too_many_pixels_dim = dimensions(.image_webp, &too_many_pixels).?;
    try std.testing.expectEqual(
        state.Failure.too_large,
        check(too_many_pixels_dim, too_many_pixels.len, .{}).?,
    );

    const at_pixel_limit = makeVp8xHeader(8192, 8192);
    const at_pixel_limit_dim = dimensions(.image_webp, &at_pixel_limit).?;
    try std.testing.expectEqual(@as(?state.Failure, null), check(at_pixel_limit_dim, at_pixel_limit.len, .{}));

    const limits = Limits{};
    try std.testing.expectEqual(
        state.Failure.too_large,
        check(.{ .width = 1, .height = 1 }, limits.max_file_bytes + 1, limits).?,
    );
    try std.testing.expectEqual(
        state.Failure.too_large,
        check(.{ .width = 0, .height = 1 }, 1, limits).?,
    );
}

test "truncated PNG headers and JPEG scans before SOF have no dimensions" {
    const png = makePngHeader(64, 40);
    for (0..24) |length| {
        try std.testing.expectEqual(@as(?Dimensions, null), dimensions(.image_png, png[0..length]));
    }

    const jpeg_before_sof = [_]u8{
        0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x28, 0x00, 0x40,
    };
    try std.testing.expectEqual(@as(?Dimensions, null), dimensions(.image_jpeg, &jpeg_before_sof));
}

test "GIF dimensions use the logical screen descriptor" {
    const fixture = @embedFile("testdata/vardelay.gif");
    try std.testing.expectEqual(
        @as(?Dimensions, .{ .width = 320, .height = 180 }),
        dimensions(.image_gif, fixture),
    );

    const header_only = "GIF89a\x40\x01\xb4\x00\x00\x00";
    try std.testing.expectEqual(
        @as(?Dimensions, .{ .width = 320, .height = 180 }),
        dimensions(.image_gif, header_only),
    );
    try std.testing.expectEqual(@as(?Dimensions, null), dimensions(.image_gif, header_only[0..5]));

    const zero_width = "GIF89a\x00\x00\xb4\x00";
    try std.testing.expectEqual(@as(?Dimensions, null), dimensions(.image_gif, zero_width));
}

fn makePngHeader(width: u32, height: u32) [24]u8 {
    var bytes = [_]u8{0} ** 24;
    @memcpy(bytes[0..8], "\x89PNG\r\n\x1a\n");
    @memcpy(bytes[12..16], "IHDR");
    bytes[16] = @truncate(width >> 24);
    bytes[17] = @truncate(width >> 16);
    bytes[18] = @truncate(width >> 8);
    bytes[19] = @truncate(width);
    bytes[20] = @truncate(height >> 24);
    bytes[21] = @truncate(height >> 16);
    bytes[22] = @truncate(height >> 8);
    bytes[23] = @truncate(height);
    return bytes;
}

fn makeVp8xHeader(width: u32, height: u32) [30]u8 {
    var bytes = [_]u8{0} ** 30;
    @memcpy(bytes[0..4], "RIFF");
    @memcpy(bytes[8..12], "WEBP");
    @memcpy(bytes[12..16], "VP8X");
    storeLe24(&bytes, 24, width - 1);
    storeLe24(&bytes, 27, height - 1);
    return bytes;
}

fn storeLe24(bytes: []u8, index: usize, value: u32) void {
    bytes[index] = @truncate(value);
    bytes[index + 1] = @truncate(value >> 8);
    bytes[index + 2] = @truncate(value >> 16);
}
