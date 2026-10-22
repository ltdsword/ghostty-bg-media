pub fn shouldRedraw(last_us: ?i64, now_us: i64, max_fps: u32) bool {
    if (max_fps == 0) return true;
    const last = last_us orelse return true;
    if (now_us < last) return false;

    const interval: i64 = @intCast(1_000_000 / max_fps);
    return now_us - last >= @divTrunc(interval * 9, 10);
}

test "cadence allows an uncapped first frame and 30 fps frames" {
    const std = @import("std");

    try std.testing.expect(shouldRedraw(null, 0, 30));

    var last: ?i64 = null;
    for (0..4) |i| {
        const now: i64 = @intCast(i * 33_333);
        try std.testing.expect(shouldRedraw(last, now, 30));
        last = now;
    }
}

test "cadence drops every other frame from a 60 fps source at a 30 fps cap" {
    const std = @import("std");

    var last: ?i64 = null;
    var redraws: usize = 0;
    for (0..120) |i| {
        const now: i64 = @intCast(i * 16_667);
        if (shouldRedraw(last, now, 30)) {
            redraws += 1;
            last = now;
        }
    }

    try std.testing.expect(redraws >= 59 and redraws <= 61);
}

test "zero max fps is uncapped" {
    const std = @import("std");

    try std.testing.expect(shouldRedraw(10, 10, 0));
    try std.testing.expect(shouldRedraw(10, 0, 0));
}

test "cadence drops a frame when the clock goes backwards" {
    const std = @import("std");

    try std.testing.expect(!shouldRedraw(10_000, 9_999, 30));
}
