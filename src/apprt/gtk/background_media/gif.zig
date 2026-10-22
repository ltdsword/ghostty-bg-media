const std = @import("std");

pub const Error = error{ InvalidGif, Truncated, OutOfMemory };

pub const Frame = struct { delay_ms: u32 };

const Gce = struct {
    disposal: u3 = 0,
    transparent: bool = false,
    delay_cs: u16 = 0,
    transparent_index: u8 = 0,
};

const Rect = struct {
    left: usize,
    top: usize,
    width: usize,
    height: usize,
};

const Extension = struct {
    next_offset: usize,
    gce: ?Gce = null,
    loop_count: ?u16 = null,
};

const Scan = struct {
    frame_count: usize = 0,
    loop_count: ?u16 = null,
    trailer_seen: bool = false,
};

pub const Decoder = struct {
    width: u16,
    height: u16,
    loop_count: ?u16,
    frame_count: usize,
    canvas: []u8,

    alloc: std.mem.Allocator,
    bytes: []const u8,
    global_palette: []const u8,
    start_offset: usize,
    offset: usize,
    pending_gce: Gce = .{},
    previous_disposal: u3 = 0,
    previous_rect: Rect = .{ .left = 0, .top = 0, .width = 0, .height = 0 },
    restore_buffer: ?[]u8 = null,
    failed: ?Error = null,
    finished: bool = false,

    /// The input bytes are borrowed and must outlive this decoder.
    pub fn init(alloc: std.mem.Allocator, bytes: []const u8) Error!Decoder {
        if (bytes.len < 6 or (!std.mem.eql(u8, bytes[0..6], "GIF87a") and
            !std.mem.eql(u8, bytes[0..6], "GIF89a"))) return error.InvalidGif;
        if (bytes.len < 13) return error.Truncated;

        const width = readLe16Unchecked(bytes, 6);
        const height = readLe16Unchecked(bytes, 8);
        if (width == 0 or height == 0) return error.InvalidGif;

        const packed_byte = bytes[10];
        var offset: usize = 13;
        var global_palette: []const u8 = &.{};
        if ((packed_byte & 0x80) != 0) {
            const palette_len = paletteSize(packed_byte) * 3;
            global_palette = try take(bytes, &offset, palette_len);
        }
        const start_offset = offset;

        const scan = try scanBlocks(bytes, start_offset, global_palette.len != 0);
        if (scan.frame_count == 0) {
            if (scan.trailer_seen) return error.InvalidGif;
            return error.Truncated;
        }

        const pixels = std.math.mul(usize, width, height) catch return error.OutOfMemory;
        const canvas_len = std.math.mul(usize, pixels, 4) catch return error.OutOfMemory;
        const canvas = alloc.alloc(u8, canvas_len) catch return error.OutOfMemory;
        @memset(canvas, 0);

        return .{
            .width = width,
            .height = height,
            .loop_count = scan.loop_count,
            .frame_count = scan.frame_count,
            .canvas = canvas,
            .alloc = alloc,
            .bytes = bytes,
            .global_palette = global_palette,
            .start_offset = start_offset,
            .offset = start_offset,
        };
    }

    pub fn deinit(self: *Decoder) void {
        if (self.restore_buffer) |buffer| self.alloc.free(buffer);
        self.alloc.free(self.canvas);
        self.* = undefined;
    }

    pub fn next(self: *Decoder) Error!?Frame {
        if (self.failed) |err| return err;
        if (self.finished) return null;

        self.applyPreviousDisposal();
        return self.nextInner() catch |err| {
            self.failed = err;
            return err;
        };
    }

    pub fn rewind(self: *Decoder) void {
        if (self.restore_buffer) |buffer| self.alloc.free(buffer);
        self.restore_buffer = null;
        @memset(self.canvas, 0);
        self.offset = self.start_offset;
        self.pending_gce = .{};
        self.previous_disposal = 0;
        self.previous_rect = .{ .left = 0, .top = 0, .width = 0, .height = 0 };
        self.failed = null;
        self.finished = false;
    }

    fn nextInner(self: *Decoder) Error!?Frame {
        while (true) {
            const marker = try takeByte(self.bytes, &self.offset);
            switch (marker) {
                0x3B => {
                    self.finished = true;
                    return null;
                },
                0x21 => {
                    const extension = try parseExtension(self.bytes, self.offset);
                    self.offset = extension.next_offset;
                    if (extension.gce) |gce| self.pending_gce = gce;
                },
                0x2C => return try self.decodeImage(),
                else => return error.InvalidGif,
            }
        }
    }

    fn decodeImage(self: *Decoder) Error!Frame {
        var offset = self.offset;
        const descriptor = try take(self.bytes, &offset, 9);
        const left = readLe16Unchecked(descriptor, 0);
        const top = readLe16Unchecked(descriptor, 2);
        const frame_width = readLe16Unchecked(descriptor, 4);
        const frame_height = readLe16Unchecked(descriptor, 6);
        const packed_byte = descriptor[8];
        if (frame_width == 0 or frame_height == 0) return error.InvalidGif;

        var palette = self.global_palette;
        if ((packed_byte & 0x80) != 0) {
            palette = try take(self.bytes, &offset, paletteSize(packed_byte) * 3);
        }
        if (palette.len == 0) return error.InvalidGif;

        const minimum_code_size = try takeByte(self.bytes, &offset);
        if (minimum_code_size < 2 or minimum_code_size > 8) return error.InvalidGif;

        const gce = self.pending_gce;
        self.pending_gce = .{};
        const rect = clippedRect(left, top, frame_width, frame_height, self.width, self.height);
        if (gce.disposal == 3 and rect.width != 0 and rect.height != 0) {
            const rect_pixels = std.math.mul(usize, rect.width, rect.height) catch return error.OutOfMemory;
            const restore_len = std.math.mul(usize, rect_pixels, 4) catch return error.OutOfMemory;
            const buffer = self.alloc.alloc(u8, restore_len) catch return error.OutOfMemory;
            self.copyCanvasRectToBuffer(rect, buffer);
            self.restore_buffer = buffer;
        }

        var reader = BitReader{ .blocks = .{ .bytes = self.bytes, .offset = offset } };
        try self.decodeLzw(
            &reader,
            minimum_code_size,
            palette,
            left,
            top,
            frame_width,
            frame_height,
            packed_byte,
            gce,
        );
        try reader.blocks.drain();
        self.offset = reader.blocks.offset;
        self.previous_disposal = gce.disposal;
        self.previous_rect = rect;

        const delay_ms: u32 = if (gce.delay_cs <= 1) 100 else @as(u32, gce.delay_cs) * 10;
        return .{ .delay_ms = delay_ms };
    }

    fn decodeLzw(
        self: *Decoder,
        reader: *BitReader,
        minimum_code_size: u8,
        palette: []const u8,
        left: u16,
        top: u16,
        frame_width: u16,
        frame_height: u16,
        packed_byte: u8,
        gce: Gce,
    ) Error!void {
        const clear_code: u16 = @as(u16, 1) << @as(u4, @intCast(minimum_code_size));
        const end_code = clear_code + 1;
        var code_size: u4 = @as(u4, @intCast(minimum_code_size)) + 1;
        var next_code: u16 = end_code + 1;
        var prefix: [4096]u16 = undefined;
        var suffix: [4096]u8 = undefined;
        var stack: [4096]u8 = undefined;
        var old_code: ?u16 = null;
        var emitted: usize = 0;
        const image_pixels = @as(usize, frame_width) * frame_height;
        const interlaced = (packed_byte & 0x40) != 0;

        while (try reader.readCode(code_size)) |code| {
            if (code == clear_code) {
                code_size = @as(u4, @intCast(minimum_code_size)) + 1;
                next_code = end_code + 1;
                old_code = null;
                continue;
            }
            if (code == end_code) break;

            var string_len: usize = 0;
            var first: u8 = undefined;
            if (code < next_code) {
                const expansion = try expandCode(code, next_code, clear_code, &prefix, &suffix, &stack);
                string_len = expansion.len;
                first = expansion.first;
            } else if (code == next_code) {
                const previous = old_code orelse return error.InvalidGif;
                const expansion = try expandCode(previous, next_code, clear_code, &prefix, &suffix, &stack);
                string_len = expansion.len;
                first = expansion.first;
                if (string_len == stack.len) return error.InvalidGif;
                stack[string_len] = first;
                string_len += 1;
            } else {
                return error.InvalidGif;
            }

            var stack_index = string_len;
            while (stack_index > 0) {
                stack_index -= 1;
                if (emitted < image_pixels) {
                    try self.writeImagePixel(
                        emitted,
                        stack[stack_index],
                        palette,
                        left,
                        top,
                        frame_width,
                        frame_height,
                        interlaced,
                        gce,
                    );
                    emitted += 1;
                }
            }

            if (old_code) |previous| {
                if (next_code < 4096) {
                    prefix[next_code] = previous;
                    suffix[next_code] = first;
                    next_code += 1;
                    if (next_code == (@as(u16, 1) << code_size) and code_size < 12) {
                        code_size += 1;
                    }
                }
            }
            old_code = code;
            if (emitted >= image_pixels) break;
        }
    }

    fn writeImagePixel(
        self: *Decoder,
        ordinal: usize,
        index: u8,
        palette: []const u8,
        left: u16,
        top: u16,
        frame_width: u16,
        frame_height: u16,
        interlaced: bool,
        gce: Gce,
    ) Error!void {
        if (gce.transparent and index == gce.transparent_index) return;
        const palette_index = @as(usize, index) * 3;
        if (palette.len -| palette_index < 3) return error.InvalidGif;

        const row = ordinal / frame_width;
        const col = ordinal % frame_width;
        const image_row = if (interlaced) interlacedRow(row, frame_height) else row;
        const x = @as(usize, left) + col;
        const y = @as(usize, top) + image_row;
        if (x >= self.width or y >= self.height) return;

        const destination = (y * self.width + x) * 4;
        self.canvas[destination] = palette[palette_index];
        self.canvas[destination + 1] = palette[palette_index + 1];
        self.canvas[destination + 2] = palette[palette_index + 2];
        self.canvas[destination + 3] = 255;
    }

    fn applyPreviousDisposal(self: *Decoder) void {
        switch (self.previous_disposal) {
            2 => self.clearCanvasRect(self.previous_rect),
            3 => if (self.restore_buffer) |buffer| self.copyBufferToCanvasRect(self.previous_rect, buffer),
            else => {},
        }
        if (self.restore_buffer) |buffer| self.alloc.free(buffer);
        self.restore_buffer = null;
        self.previous_disposal = 0;
    }

    fn clearCanvasRect(self: *Decoder, rect: Rect) void {
        for (0..rect.height) |row| {
            const start = ((rect.top + row) * self.width + rect.left) * 4;
            @memset(self.canvas[start .. start + rect.width * 4], 0);
        }
    }

    fn copyCanvasRectToBuffer(self: *Decoder, rect: Rect, buffer: []u8) void {
        for (0..rect.height) |row| {
            const start = ((rect.top + row) * self.width + rect.left) * 4;
            const len = rect.width * 4;
            @memcpy(buffer[row * len ..][0..len], self.canvas[start..][0..len]);
        }
    }

    fn copyBufferToCanvasRect(self: *Decoder, rect: Rect, buffer: []const u8) void {
        for (0..rect.height) |row| {
            const start = ((rect.top + row) * self.width + rect.left) * 4;
            const len = rect.width * 4;
            @memcpy(self.canvas[start..][0..len], buffer[row * len ..][0..len]);
        }
    }
};

const SubBlockReader = struct {
    bytes: []const u8,
    offset: usize,
    remaining: usize = 0,
    terminated: bool = false,

    fn nextByte(self: *SubBlockReader) Error!?u8 {
        if (self.terminated) return null;
        if (self.remaining == 0) {
            if (self.offset >= self.bytes.len) return error.Truncated;
            const block_len = self.bytes[self.offset];
            self.offset += 1;
            if (block_len == 0) {
                self.terminated = true;
                return null;
            }
            self.remaining = block_len;
            if (self.bytes.len - self.offset < self.remaining) return error.Truncated;
        }

        const byte = self.bytes[self.offset];
        self.offset += 1;
        self.remaining -= 1;
        return byte;
    }

    fn drain(self: *SubBlockReader) Error!void {
        while (try self.nextByte()) |_| {}
    }
};

const BitReader = struct {
    blocks: SubBlockReader,
    bits: u32 = 0,
    bit_count: u5 = 0,

    fn readCode(self: *BitReader, code_size: u4) Error!?u16 {
        while (self.bit_count < code_size) {
            const byte = try self.blocks.nextByte() orelse return null;
            self.bits |= @as(u32, byte) << self.bit_count;
            self.bit_count += 8;
        }

        const mask = (@as(u32, 1) << code_size) - 1;
        const code: u16 = @intCast(self.bits & mask);
        self.bits >>= code_size;
        self.bit_count -= code_size;
        return code;
    }
};

const Expansion = struct { len: usize, first: u8 };

fn expandCode(
    code: u16,
    next_code: u16,
    clear_code: u16,
    prefix: *const [4096]u16,
    suffix: *const [4096]u8,
    stack: *[4096]u8,
) Error!Expansion {
    var current = code;
    var len: usize = 0;
    while (current >= clear_code + 2) {
        if (current >= next_code or len >= stack.len - 1) return error.InvalidGif;
        stack[len] = suffix[current];
        len += 1;
        current = prefix[current];
    }
    if (current >= clear_code) return error.InvalidGif;
    stack[len] = @intCast(current);
    len += 1;
    return .{ .len = len, .first = stack[len - 1] };
}

fn scanBlocks(bytes: []const u8, start: usize, has_global_palette: bool) Error!Scan {
    var result = Scan{};
    var offset = start;
    while (offset < bytes.len) {
        const marker = bytes[offset];
        offset += 1;
        switch (marker) {
            0x3B => {
                result.trailer_seen = true;
                break;
            },
            0x21 => {
                const extension = parseExtension(bytes, offset) catch |err| switch (err) {
                    error.Truncated => break,
                    else => return err,
                };
                offset = extension.next_offset;
                if (result.loop_count == null) result.loop_count = extension.loop_count;
            },
            0x2C => {
                const next_offset = scanImage(bytes, offset, has_global_palette) catch |err| switch (err) {
                    error.Truncated => break,
                    else => return err,
                };
                offset = next_offset;
                result.frame_count += 1;
            },
            else => return error.InvalidGif,
        }
    }
    return result;
}

fn scanImage(bytes: []const u8, start: usize, has_global_palette: bool) Error!usize {
    var offset = start;
    const descriptor = try take(bytes, &offset, 9);
    const width = readLe16Unchecked(descriptor, 4);
    const height = readLe16Unchecked(descriptor, 6);
    const packed_byte = descriptor[8];
    if (width == 0 or height == 0) return error.InvalidGif;

    var has_palette = has_global_palette;
    if ((packed_byte & 0x80) != 0) {
        _ = try take(bytes, &offset, paletteSize(packed_byte) * 3);
        has_palette = true;
    }
    if (!has_palette) return error.InvalidGif;

    const minimum_code_size = try takeByte(bytes, &offset);
    if (minimum_code_size < 2 or minimum_code_size > 8) return error.InvalidGif;
    return try skipSubBlocks(bytes, offset);
}

fn parseExtension(bytes: []const u8, start: usize) Error!Extension {
    var offset = start;
    const label = try takeByte(bytes, &offset);
    if (label == 0xF9) {
        const block_size = try takeByte(bytes, &offset);
        if (block_size != 4) return error.InvalidGif;
        const data = try take(bytes, &offset, 4);
        const terminator = try takeByte(bytes, &offset);
        if (terminator != 0) return error.InvalidGif;
        return .{
            .next_offset = offset,
            .gce = .{
                .disposal = @intCast((data[0] >> 2) & 7),
                .transparent = (data[0] & 1) != 0,
                .delay_cs = readLe16Unchecked(data, 1),
                .transparent_index = data[3],
            },
        };
    }

    if (label == 0xFF) {
        const header_size = try takeByte(bytes, &offset);
        const app_id = try take(bytes, &offset, header_size);
        const is_loop_extension = header_size == 11 and
            (std.mem.eql(u8, app_id, "NETSCAPE2.0") or std.mem.eql(u8, app_id, "ANIMEXTS1.0"));
        var loop_count: ?u16 = null;
        while (true) {
            const block_len = try takeByte(bytes, &offset);
            if (block_len == 0) break;
            const data = try take(bytes, &offset, block_len);
            if (is_loop_extension and loop_count == null and data.len >= 3 and data[0] == 1) {
                loop_count = readLe16Unchecked(data, 1);
            }
        }
        return .{ .next_offset = offset, .loop_count = loop_count };
    }

    return .{ .next_offset = try skipSubBlocks(bytes, offset) };
}

fn skipSubBlocks(bytes: []const u8, start: usize) Error!usize {
    var offset = start;
    while (true) {
        const block_len = try takeByte(bytes, &offset);
        if (block_len == 0) return offset;
        _ = try take(bytes, &offset, block_len);
    }
}

fn take(bytes: []const u8, offset: *usize, count: usize) Error![]const u8 {
    if (offset.* > bytes.len or bytes.len - offset.* < count) return error.Truncated;
    const result = bytes[offset.* .. offset.* + count];
    offset.* += count;
    return result;
}

fn takeByte(bytes: []const u8, offset: *usize) Error!u8 {
    const result = try take(bytes, offset, 1);
    return result[0];
}

fn readLe16Unchecked(bytes: []const u8, offset: usize) u16 {
    return @as(u16, bytes[offset]) | (@as(u16, bytes[offset + 1]) << 8);
}

fn paletteSize(packed_byte: u8) usize {
    return @as(usize, 2) << @as(u3, @intCast(packed_byte & 7));
}

fn clippedRect(
    left: u16,
    top: u16,
    width: u16,
    height: u16,
    canvas_width: u16,
    canvas_height: u16,
) Rect {
    const clipped_left = @min(@as(usize, left), canvas_width);
    const clipped_top = @min(@as(usize, top), canvas_height);
    const clipped_right = @min(@as(usize, left) + width, canvas_width);
    const clipped_bottom = @min(@as(usize, top) + height, canvas_height);
    return .{
        .left = clipped_left,
        .top = clipped_top,
        .width = clipped_right - clipped_left,
        .height = clipped_bottom - clipped_top,
    };
}

fn interlacedRow(row: usize, height: u16) usize {
    const h = @as(usize, height);
    const pass0 = (h + 7) / 8;
    const pass1 = if (h > 4) (h - 5) / 8 + 1 else 0;
    const pass2 = if (h > 2) (h - 3) / 4 + 1 else 0;
    if (row < pass0) return row * 8;
    const after0 = row - pass0;
    if (after0 < pass1) return 4 + after0 * 8;
    const after1 = after0 - pass1;
    if (after1 < pass2) return 2 + after1 * 4;
    return 1 + (after1 - pass2) * 2;
}

test "GIF fixture frames match reference delays and canvas CRCs" {
    const bytes = @embedFile("testdata/vardelay.gif");
    var decoder = try Decoder.init(std.testing.allocator, bytes);
    defer decoder.deinit();

    try std.testing.expectEqual(@as(u16, 320), decoder.width);
    try std.testing.expectEqual(@as(u16, 180), decoder.height);
    try std.testing.expectEqual(@as(?u16, 0), decoder.loop_count);
    try std.testing.expectEqual(@as(usize, 4), decoder.frame_count);

    const delays = [_]u32{ 40, 500, 100, 1000 };
    const crcs = [_]u32{ 0x6fadf75b, 0xff13a9a8, 0xc9dd2bfc, 0x66748634 };
    for (delays, crcs) |delay, crc| try expectFrame(&decoder, delay, crc);
    try std.testing.expect((try decoder.next()) == null);

    decoder.rewind();
    try expectFrame(&decoder, 40, 0x6fadf75b);
}

test "GIF transparency and loop extension fixtures match reference frames" {
    const transparent_bytes = @embedFile("testdata/transparent.gif");
    var transparent = try Decoder.init(std.testing.allocator, transparent_bytes);
    defer transparent.deinit();
    try std.testing.expectEqual(@as(u16, 200), transparent.width);
    try std.testing.expectEqual(@as(u16, 200), transparent.height);
    try std.testing.expectEqual(@as(?u16, 0), transparent.loop_count);
    try std.testing.expectEqual(@as(usize, 6), transparent.frame_count);
    const transparent_crcs = [_]u32{
        0x3e81157f,
        0xd7d1edec,
        0x9c5981f2,
        0x0d7b0f04,
        0x2d5902ce,
        0x59ef5b26,
    };
    for (transparent_crcs) |crc| try expectFrame(&transparent, 80, crc);
    try std.testing.expect((try transparent.next()) == null);

    const loop_bytes = @embedFile("testdata/loop2.gif");
    var loop_decoder = try Decoder.init(std.testing.allocator, loop_bytes);
    defer loop_decoder.deinit();
    try std.testing.expectEqual(@as(?u16, 2), loop_decoder.loop_count);
    try std.testing.expectEqual(@as(usize, 4), loop_decoder.frame_count);
    const loop_crcs = [_]u32{ 0x6fadf75b, 0xff13a9a8, 0xc9dd2bfc, 0x66748634 };
    for (loop_crcs) |crc| try expectFrame(&loop_decoder, 100, crc);
}

test "GIF without a control extension uses the default delay and no loop count" {
    const bytes = @embedFile("testdata/oneframe.gif");
    var decoder = try Decoder.init(std.testing.allocator, bytes);
    defer decoder.deinit();
    try std.testing.expectEqual(@as(?u16, null), decoder.loop_count);
    try std.testing.expectEqual(@as(usize, 1), decoder.frame_count);
    try expectFrame(&decoder, 100, 0x6fadf75b);
    try std.testing.expect((try decoder.next()) == null);
}

test "truncated GIF keeps complete frames and header-only GIF is rejected" {
    const bytes = @embedFile("testdata/truncated.gif");
    var decoder = try Decoder.init(std.testing.allocator, bytes);
    defer decoder.deinit();
    try std.testing.expect(decoder.frame_count >= 2);
    try expectFrame(&decoder, 40, 0x6fadf75b);
    try expectFrame(&decoder, 500, 0xff13a9a8);
    if (decoder.next()) |frame| {
        try std.testing.expect(frame == null);
    } else |err| {
        try std.testing.expectEqual(error.Truncated, err);
    }

    const header_only = @embedFile("testdata/header-only.gif");
    if (Decoder.init(std.testing.allocator, header_only)) |value| {
        var accepted = value;
        defer accepted.deinit();
        return error.TestUnexpectedResult;
    } else |err| {
        try std.testing.expect(err == error.InvalidGif or err == error.Truncated);
    }
}

test "synthetic GIFs decode minimum-size LZW and interlaced row order" {
    var bytes: [128]u8 = undefined;
    const pixels_2x2 = [_]u8{ 0, 1, 2, 3 };
    const gif_2x2 = makeSyntheticGif(&bytes, 2, 2, false, &pixels_2x2);
    var decoder_2x2 = try Decoder.init(std.testing.allocator, gif_2x2);
    defer decoder_2x2.deinit();
    const frame_2x2 = (try decoder_2x2.next()) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 100), frame_2x2.delay_ms);
    const expected_2x2 = [_]u8{
        10, 20, 30, 255, 40,  50,  60,  255,
        70, 80, 90, 255, 100, 110, 120, 255,
    };
    try std.testing.expectEqualSlices(u8, &expected_2x2, decoder_2x2.canvas);

    const pixels_1x8 = [_]u8{ 0, 1, 2, 3, 0, 1, 2, 3 };
    const gif_1x8 = makeSyntheticGif(&bytes, 1, 8, true, &pixels_1x8);
    var decoder_1x8 = try Decoder.init(std.testing.allocator, gif_1x8);
    defer decoder_1x8.deinit();
    const frame_1x8 = (try decoder_1x8.next()) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 100), frame_1x8.delay_ms);
    const expected = [_]u8{
        10,  20,  30,  255,
        10,  20,  30,  255,
        70,  80,  90,  255,
        40,  50,  60,  255,
        40,  50,  60,  255,
        70,  80,  90,  255,
        100, 110, 120, 255,
        100, 110, 120, 255,
    };
    try std.testing.expectEqualSlices(u8, &expected, decoder_1x8.canvas);
}

test "all fixture prefixes can initialize and drain without leaks or crashes" {
    const fixtures = [_][]const u8{
        @embedFile("testdata/vardelay.gif"),
        @embedFile("testdata/transparent.gif"),
    };
    for (fixtures) |bytes| {
        for (0..bytes.len + 1) |length| try exercisePrefix(bytes[0..length]);
    }
}

fn expectFrame(decoder: *Decoder, delay_ms: u32, crc: u32) !void {
    const frame = (try decoder.next()) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(delay_ms, frame.delay_ms);
    try std.testing.expectEqual(crc, try normalizedCrc(std.testing.allocator, decoder.canvas));
}

fn normalizedCrc(alloc: std.mem.Allocator, canvas: []const u8) !u32 {
    const copy = try alloc.dupe(u8, canvas);
    defer alloc.free(copy);
    var offset: usize = 0;
    while (offset < copy.len) : (offset += 4) {
        if (copy[offset + 3] == 0) @memset(copy[offset .. offset + 4], 0);
    }
    return std.hash.Crc32.hash(copy);
}

fn exercisePrefix(bytes: []const u8) !void {
    var decoder = Decoder.init(std.testing.allocator, bytes) catch return;
    defer decoder.deinit();
    while (true) {
        const frame = decoder.next() catch break;
        if (frame == null) break;
    }
}

fn makeSyntheticGif(
    buffer: *[128]u8,
    width: u16,
    height: u16,
    interlaced: bool,
    pixels: []const u8,
) []const u8 {
    var len: usize = 0;
    appendTestBytes(buffer, &len, "GIF89a");
    appendTestLe16(buffer, &len, width);
    appendTestLe16(buffer, &len, height);
    appendTestByte(buffer, &len, 0x81);
    appendTestByte(buffer, &len, 0);
    appendTestByte(buffer, &len, 0);
    appendTestBytes(buffer, &len, &.{
        10,  20,  30,
        40,  50,  60,
        70,  80,  90,
        100, 110, 120,
    });
    appendTestByte(buffer, &len, 0x2C);
    appendTestLe16(buffer, &len, 0);
    appendTestLe16(buffer, &len, 0);
    appendTestLe16(buffer, &len, width);
    appendTestLe16(buffer, &len, height);
    appendTestByte(buffer, &len, if (interlaced) 0x40 else 0);
    appendTestByte(buffer, &len, 2);

    var compressed: [32]u8 = .{0} ** 32;
    var bit_offset: usize = 0;
    for (pixels) |pixel| {
        appendTestCode(&compressed, &bit_offset, 4);
        appendTestCode(&compressed, &bit_offset, pixel);
    }
    appendTestCode(&compressed, &bit_offset, 5);
    const compressed_len = (bit_offset + 7) / 8;
    appendTestByte(buffer, &len, @intCast(compressed_len));
    appendTestBytes(buffer, &len, compressed[0..compressed_len]);
    appendTestByte(buffer, &len, 0);
    appendTestByte(buffer, &len, 0x3B);
    return buffer[0..len];
}

fn appendTestCode(bytes: *[32]u8, bit_offset: *usize, code: u8) void {
    for (0..3) |bit| {
        if ((code & (@as(u8, 1) << @as(u3, @intCast(bit)))) != 0) {
            const byte_index = bit_offset.* / 8;
            const bit_index: u3 = @intCast(bit_offset.* % 8);
            bytes[byte_index] |= @as(u8, 1) << bit_index;
        }
        bit_offset.* += 1;
    }
}

fn appendTestByte(bytes: *[128]u8, len: *usize, byte: u8) void {
    bytes[len.*] = byte;
    len.* += 1;
}

fn appendTestLe16(bytes: *[128]u8, len: *usize, value: u16) void {
    appendTestByte(bytes, len, @truncate(value));
    appendTestByte(bytes, len, @truncate(value >> 8));
}

fn appendTestBytes(bytes: *[128]u8, len: *usize, data: []const u8) void {
    @memcpy(bytes[len.*..][0..data.len], data);
    len.* += data.len;
}
