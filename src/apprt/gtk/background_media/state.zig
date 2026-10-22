const std = @import("std");
const source = @import("source.zig");

const Kind = source.Kind;
const MediaType = source.MediaType;

pub const Ready = struct { kind: Kind, media_type: MediaType, source_id: u64 };

pub fn sourceId(value: []const u8) u64 {
    return std.hash.Wyhash.hash(0, value);
}

pub const Failure = enum { not_found, unreadable, unsupported_type, invalid_url, too_large, decode_failed };

pub const State = union(enum) { disabled, ready: Ready, failed: Failure };

pub const Action = enum { none, start, restart, stop };

pub fn reconcile(old: State, new: State) Action {
    return switch (old) {
        .disabled => switch (new) {
            .disabled, .failed => .none,
            .ready => .start,
        },
        .ready => |old_ready| switch (new) {
            .disabled, .failed => .stop,
            .ready => |new_ready| if (old_ready.kind == new_ready.kind and
                old_ready.media_type == new_ready.media_type and
                old_ready.source_id == new_ready.source_id) .none else .restart,
        },
        .failed => switch (new) {
            .disabled => .stop,
            .ready => .start,
            .failed => .none,
        },
    };
}

test "reconcile covers the full state transition table" {
    const old_ready = State{ .ready = .{ .kind = .local_file, .media_type = .image_png, .source_id = sourceId("a") } };
    const same_ready = State{ .ready = .{ .kind = .local_file, .media_type = .image_png, .source_id = sourceId("a") } };
    const different_kind = State{ .ready = .{ .kind = .http_direct, .media_type = .image_png, .source_id = sourceId("a") } };
    const different_media_type = State{ .ready = .{ .kind = .local_file, .media_type = .image_jpeg, .source_id = sourceId("a") } };
    const different_source = State{ .ready = .{ .kind = .local_file, .media_type = .image_png, .source_id = sourceId("b") } };
    const new_failure = State{ .failed = .not_found };
    const different_failure = State{ .failed = .unreadable };

    try std.testing.expectEqual(Action.none, reconcile(.disabled, .disabled));
    try std.testing.expectEqual(Action.start, reconcile(.disabled, old_ready));
    try std.testing.expectEqual(Action.none, reconcile(.disabled, new_failure));
    try std.testing.expectEqual(Action.stop, reconcile(old_ready, .disabled));
    try std.testing.expectEqual(Action.none, reconcile(old_ready, same_ready));
    try std.testing.expectEqual(Action.restart, reconcile(old_ready, different_kind));
    try std.testing.expectEqual(Action.restart, reconcile(old_ready, different_media_type));
    try std.testing.expectEqual(Action.restart, reconcile(old_ready, different_source));
    try std.testing.expectEqual(Action.stop, reconcile(old_ready, new_failure));
    try std.testing.expectEqual(Action.stop, reconcile(new_failure, .disabled));
    try std.testing.expectEqual(Action.start, reconcile(new_failure, old_ready));
    try std.testing.expectEqual(Action.none, reconcile(new_failure, different_failure));
}

test "source IDs are stable and distinguish different sources" {
    try std.testing.expectEqual(sourceId("a"), sourceId("a"));
    try std.testing.expect(sourceId("a") != sourceId("b"));
}
