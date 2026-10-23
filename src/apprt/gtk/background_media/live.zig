const std = @import("std");
const youtube = @import("youtube.zig");

pub const State = enum {
    idle,
    resolving,
    waiting_upcoming,
    playing,
    reconnecting,
    ended,
    failed,
};

pub const Event = union(enum) {
    resolved: youtube.LiveStatus,
    first_frame,
    failure,
    fatal_upcoming,
    fatal,
    eos: struct {
        was_live: bool,
        youtube: bool,
    },
    recheck_result: youtube.LiveStatus,
    poll_due,
};

pub fn next(state: State, event: Event) State {
    return switch (event) {
        .resolved => |status| switch (status) {
            .upcoming => .waiting_upcoming,
            .live, .recorded => .resolving,
        },
        .first_frame => .playing,
        .failure => .reconnecting,
        .fatal_upcoming => .waiting_upcoming,
        .fatal => .failed,
        .eos => |info| if (!info.was_live) state else if (info.youtube) .resolving else .ended,
        .recheck_result => |status| if (status == .live) .reconnecting else .ended,
        .poll_due => if (state == .waiting_upcoming) .resolving else state,
    };
}

pub fn upcomingDelayMs(attempt: u32, seed: u64) u32 {
    const base = @min(@as(u32, 30_000) << @min(attempt, 2), 120_000);
    const jitter: i64 = @as(i64, @intCast(seed % 401)) - 200;
    const adjustment = @divTrunc(@as(i64, base) * jitter, 1000);
    return @intCast(@max(@as(i64, 1), @as(i64, base) + adjustment));
}

test "live state transitions follow resolution, playback, retry, end, and upcoming decisions" {
    const cases = [_]struct {
        from: State,
        event: Event,
        to: State,
    }{
        .{ .from = .idle, .event = .{ .resolved = .recorded }, .to = .resolving },
        .{ .from = .idle, .event = .{ .resolved = .live }, .to = .resolving },
        .{ .from = .resolving, .event = .{ .resolved = .upcoming }, .to = .waiting_upcoming },
        .{ .from = .resolving, .event = .first_frame, .to = .playing },
        .{ .from = .playing, .event = .failure, .to = .reconnecting },
        .{ .from = .resolving, .event = .fatal_upcoming, .to = .waiting_upcoming },
        .{ .from = .resolving, .event = .fatal, .to = .failed },
        .{ .from = .playing, .event = .{ .eos = .{ .was_live = false, .youtube = false } }, .to = .playing },
        .{ .from = .playing, .event = .{ .eos = .{ .was_live = true, .youtube = true } }, .to = .resolving },
        .{ .from = .resolving, .event = .{ .recheck_result = .recorded }, .to = .ended },
        .{ .from = .resolving, .event = .{ .recheck_result = .live }, .to = .reconnecting },
        .{ .from = .playing, .event = .{ .eos = .{ .was_live = true, .youtube = false } }, .to = .ended },
        .{ .from = .waiting_upcoming, .event = .poll_due, .to = .resolving },
    };

    for (cases) |case| {
        try std.testing.expectEqual(case.to, next(case.from, case.event));
    }
}

test "upcoming poll delay doubles and caps with zero jitter" {
    try std.testing.expectEqual(@as(u32, 30_000), upcomingDelayMs(0, 200));
    try std.testing.expectEqual(@as(u32, 60_000), upcomingDelayMs(1, 200));
    try std.testing.expectEqual(@as(u32, 120_000), upcomingDelayMs(2, 200));
    try std.testing.expectEqual(@as(u32, 120_000), upcomingDelayMs(3, 200));
}

test "upcoming poll delay applies bounded jitter" {
    try std.testing.expectEqual(@as(u32, 24_000), upcomingDelayMs(0, 0));
    try std.testing.expectEqual(@as(u32, 36_000), upcomingDelayMs(0, 400));
    try std.testing.expect(upcomingDelayMs(2, 0) >= 96_000);
    try std.testing.expect(upcomingDelayMs(2, 400) <= 144_000);
}
