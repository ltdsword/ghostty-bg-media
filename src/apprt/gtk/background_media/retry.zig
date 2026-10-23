const std = @import("std");
const source = @import("source.zig");

pub const stall_timeout_us: i64 = 20 * std.time.us_per_s;
pub const max_direct_attempts: u32 = 6;
pub const max_delay_ms: u32 = 60_000;

pub fn delayMs(attempt: u32, seed: u64) u32 {
    const base = @min(@as(u32, 1000) << @min(attempt, 6), max_delay_ms);
    const jitter: i64 = @as(i64, @intCast(seed % 401)) - 200;
    const adjustment = @divTrunc(@as(i64, base) * jitter, 1000);
    return @intCast(@max(@as(i64, 1), @as(i64, base) + adjustment));
}

pub fn shouldRetry(kind: source.Kind, failed_attempts: u32) bool {
    return switch (kind) {
        .http_hls => true,
        .http_direct => failed_attempts < max_direct_attempts,
        else => false,
    };
}

pub fn isStalled(last_frame_us: i64, now_us: i64) bool {
    return now_us - last_frame_us >= stall_timeout_us;
}

test "retry delay doubles, caps, and applies bounded jitter" {
    try std.testing.expectEqual(@as(u32, 1000), delayMs(0, 200));
    try std.testing.expectEqual(@as(u32, 2000), delayMs(1, 200));
    try std.testing.expectEqual(@as(u32, 4000), delayMs(2, 200));
    try std.testing.expectEqual(@as(u32, 60_000), delayMs(10, 200));
    try std.testing.expectEqual(@as(u32, 800), delayMs(0, 0));
    try std.testing.expectEqual(@as(u32, 1200), delayMs(0, 400));
    try std.testing.expect(delayMs(0, 0) >= 800 and delayMs(0, 0) <= 1000);
    try std.testing.expect(delayMs(0, 400) >= 1000 and delayMs(0, 400) <= 1200);
    try std.testing.expect(delayMs(0, 0) > 0);
}

test "retry policy caps direct streams and keeps HLS reconnecting" {
    try std.testing.expect(shouldRetry(.http_hls, 0));
    try std.testing.expect(shouldRetry(.http_hls, 100));
    try std.testing.expect(shouldRetry(.http_direct, 5));
    try std.testing.expect(!shouldRetry(.http_direct, 6));
    try std.testing.expect(!shouldRetry(.local_file, 0));
    try std.testing.expect(!shouldRetry(.youtube, 0));
}

test "stall timeout triggers at twenty seconds" {
    try std.testing.expect(!isStalled(0, 19_999_000));
    try std.testing.expect(isStalled(0, 20_000_000));
}
