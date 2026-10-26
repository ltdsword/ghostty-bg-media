const std = @import("std");

const glib = @import("glib");

const global = @import("../../global.zig");
const playlist = @import("background_media/playlist.zig");
const source = @import("background_media/source.zig");
const youtube = @import("background_media/youtube.zig");

const alloc = std.heap.c_allocator;
const max_stdout_bytes = 32 * 1024 * 1024;
const max_stderr_bytes = 64 * 1024;
const resolve_timeout_ms = 30 * 1000;

pub const Resolved = struct {
    url: [:0]u8,
    url_kind: source.Kind,
    live: youtube.LiveStatus,
    id: []u8,
    title: []u8,
    format_id: []u8,
    height: u32,
    audio_url: ?[:0]u8,
    width: u32,
    bandwidth: u32,
    heights: [12]u32,
    heights_len: u8,
};

pub const Result = union(enum) {
    ok: Resolved,
    fatal: youtube.Fatal,
    retriable: []const u8,
    missing,
};

pub const ListResult = union(enum) {
    ok: playlist.Batch,
    failed: []const u8,
    missing,
};

const Job = struct {
    url: [:0]u8,
    max_fps: u32,
    max_height: u32,
    generation: u64,
    done: *const fn (generation: u64, result: *Result) void,
    result: Result = .missing,
};

const ListJob = struct {
    url: [:0]u8,
    first: u32,
    last: u32,
    generation: u64,
    done: *const fn (generation: u64, result: *ListResult) void,
    result: ListResult = .missing,
};

const CommandResult = union(enum) {
    stdout: []u8,
    missing,
    retriable: []const u8,
    process_failed: youtube.StderrClass,
};

const StderrReader = struct {
    file: std.Io.File,
    bytes: [max_stderr_bytes]u8 = undefined,
    len: usize = 0,
};

const Timeout = struct {
    child: *std.process.Child,
    state: std.atomic.Value(u8) = .init(0),
};

pub fn start(
    url: []const u8,
    max_fps: u32,
    max_height: u32,
    generation: u64,
    done: *const fn (generation: u64, result: *Result) void,
) bool {
    const job = alloc.create(Job) catch return false;
    const owned_url = alloc.dupeZ(u8, url) catch {
        alloc.destroy(job);
        return false;
    };
    job.* = .{
        .url = owned_url,
        .max_fps = max_fps,
        .max_height = max_height,
        .generation = generation,
        .done = done,
    };

    const thread = std.Thread.spawn(.{}, worker, .{job}) catch {
        alloc.free(owned_url);
        alloc.destroy(job);
        return false;
    };
    thread.detach();
    return true;
}

pub fn startList(
    url: []const u8,
    first: u32,
    last: u32,
    generation: u64,
    done: *const fn (generation: u64, result: *ListResult) void,
) bool {
    const job = alloc.create(ListJob) catch return false;
    const owned_url = alloc.dupeZ(u8, url) catch {
        alloc.destroy(job);
        return false;
    };
    job.* = .{
        .url = owned_url,
        .first = first,
        .last = last,
        .generation = generation,
        .done = done,
    };

    const thread = std.Thread.spawn(.{}, listWorker, .{job}) catch {
        alloc.free(owned_url);
        alloc.destroy(job);
        return false;
    };
    thread.detach();
    return true;
}

pub fn freeResult(result: *Result) void {
    switch (result.*) {
        .ok => |resolved| {
            alloc.free(resolved.url);
            alloc.free(resolved.id);
            alloc.free(resolved.title);
            alloc.free(resolved.format_id);
            if (resolved.audio_url) |audio_url| alloc.free(audio_url);
        },
        else => {},
    }
    result.* = .missing;
}

pub fn freeListResult(result: *ListResult) void {
    switch (result.*) {
        .ok => |*batch| batch.deinit(alloc),
        else => {},
    }
    result.* = .missing;
}

fn worker(job: *Job) void {
    job.result = run(job.url, job.max_fps, job.max_height);
    if (glib.idleAddOnce(onDone, job) == 0) freeJob(job);
}

fn listWorker(job: *ListJob) void {
    job.result = runList(job.url, job.first, job.last);
    if (glib.idleAddOnce(onListDone, job) == 0) freeListJob(job);
}

fn run(url: []const u8, max_fps: u32, max_height: u32) Result {
    var environ_map = global.environMap() catch null;
    defer if (environ_map) |*map| map.deinit();
    const override = if (environ_map) |map| map.get("GHOSTTY_YTDLP") else null;

    var argv_buf: [12][]const u8 = undefined;
    const argv = youtube.argv(&argv_buf, url, override, inFlatpak(global.io()));
    const command = runCommand(argv);
    defer switch (command) {
        .stdout => |stdout| alloc.free(stdout),
        else => {},
    };

    switch (command) {
        .missing => return .missing,
        .retriable => |reason| return .{ .retriable = reason },
        .process_failed => |class| return switch (class) {
            .retriable => .{ .retriable = "process_failed" },
            .fatal => |fatal| .{ .fatal = fatal },
        },
        .stdout => |output| {
            var parsed = youtube.resolve(alloc, output, max_height, max_fps) catch |err| switch (err) {
                error.OutOfMemory => return .{ .retriable = "out_of_memory" },
                else => |resolve_err| return .{ .fatal = youtube.fatalOf(@errorCast(resolve_err)) },
            };
            defer parsed.deinit();
            if (parsed.info.live == .upcoming) return .{ .fatal = .upcoming };
            const resolved = copyResolved(parsed.info) catch return .{ .retriable = "out_of_memory" };
            return .{ .ok = resolved };
        },
    }
}

fn runList(url: []const u8, first: u32, last: u32) ListResult {
    var environ_map = global.environMap() catch null;
    defer if (environ_map) |*map| map.deinit();
    const override = if (environ_map) |map| map.get("GHOSTTY_YTDLP") else null;

    var range_buf: [32]u8 = undefined;
    const range = std.fmt.bufPrint(&range_buf, "{d}:{d}", .{ first, last }) catch return .{ .failed = "invalid_range" };
    var argv_buf: [16][]const u8 = undefined;
    const argv = youtube.playlistArgv(&argv_buf, range, url, override, inFlatpak(global.io()));
    const command = runCommand(argv);
    defer switch (command) {
        .stdout => |stdout| alloc.free(stdout),
        else => {},
    };

    switch (command) {
        .missing => return .missing,
        .retriable => |reason| return .{ .failed = reason },
        .process_failed => return .{ .failed = "process_failed" },
        .stdout => |output| {
            return .{ .ok = playlist.parseBatch(alloc, output) catch |err| switch (err) {
                error.OutOfMemory => return .{ .failed = "out_of_memory" },
                error.NotPlaylist => return .{ .failed = "not_playlist" },
                error.BadJson => return .{ .failed = "bad_json" },
            } };
        },
    }
}

fn runCommand(argv: []const []const u8) CommandResult {
    const io = global.io();
    var child = std.process.spawn(io, .{
        .argv = argv,
        .pgid = 0,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    }) catch |err| {
        if (err == error.FileNotFound) return .missing;
        return .{ .retriable = "spawn_failed" };
    };

    const stdout_file = child.stdout.?;
    const stderr_file = child.stderr.?;
    var stderr_reader: StderrReader = .{ .file = stderr_file };
    const stderr_thread = std.Thread.spawn(.{}, readStderr, .{&stderr_reader}) catch {
        killTree(&child, io);
        return .{ .retriable = "thread_start" };
    };
    child.stdout = null;
    child.stderr = null;
    defer stdout_file.close(io);

    var timeout: Timeout = .{ .child = &child };
    const timeout_thread = std.Thread.spawn(.{}, timeoutWorker, .{&timeout}) catch {
        killTree(&child, io);
        stderr_thread.join();
        return .{ .retriable = "thread_start" };
    };

    var output: std.ArrayListUnmanaged(u8) = .empty;
    defer output.deinit(alloc);
    var read_buffer: [8192]u8 = undefined;
    var too_large = false;
    var read_failed = false;
    var out_of_memory = false;
    while (true) {
        const len = stdout_file.readStreaming(io, &.{&read_buffer}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => {
                read_failed = true;
                break;
            },
        };
        if (len == 0) continue;
        if (len > max_stdout_bytes - output.items.len) {
            too_large = true;
            break;
        }
        output.appendSlice(alloc, read_buffer[0..len]) catch {
            out_of_memory = true;
            break;
        };
    }

    var term: ?std.process.Child.Term = null;
    if (too_large or read_failed or out_of_memory) {
        if (timeout.state.cmpxchgStrong(0, 1, .acq_rel, .acquire) == null) {
            killTree(&child, io);
        }
    } else if (timeout.state.load(.acquire) == 2) {
        // The timeout thread is killing the child.
    } else {
        term = child.wait(io) catch wait_result: {
            if (timeout.state.cmpxchgStrong(0, 1, .acq_rel, .acquire) == null) {
                killTree(&child, io);
            }
            break :wait_result null;
        };
        _ = timeout.state.cmpxchgStrong(0, 1, .acq_rel, .acquire);
    }
    timeout_thread.join();
    stderr_thread.join();

    if (timeout.state.load(.acquire) == 2) return .{ .retriable = "timeout" };
    if (too_large) return .{ .retriable = "output_too_large" };
    if (out_of_memory) return .{ .retriable = "out_of_memory" };
    if (read_failed) return .{ .retriable = "read_failed" };

    const process_term = term orelse return .{ .retriable = "wait_failed" };
    switch (process_term) {
        .exited => |code| if (code == 0) return .{ .stdout = output.toOwnedSlice(alloc) catch return .{ .retriable = "out_of_memory" } },
        else => {},
    }

    return .{ .process_failed = youtube.classifyStderr(stderr_reader.bytes[0..stderr_reader.len]) };
}

fn copyResolved(info: youtube.Info) error{OutOfMemory}!Resolved {
    const resolved_url = try alloc.dupeZ(u8, info.url);
    errdefer alloc.free(resolved_url);
    const id = try alloc.dupe(u8, info.id);
    errdefer alloc.free(id);
    const title = try alloc.dupe(u8, info.title);
    errdefer alloc.free(title);
    const format_id = try alloc.dupe(u8, info.format_id);
    errdefer alloc.free(format_id);
    const audio_url = if (info.audio_url) |url| try alloc.dupeZ(u8, url) else null;
    errdefer if (audio_url) |url| alloc.free(url);
    return .{
        .url = resolved_url,
        .url_kind = info.url_kind,
        .live = info.live,
        .id = id,
        .title = title,
        .format_id = format_id,
        .height = info.height,
        .audio_url = audio_url,
        .width = info.width,
        .bandwidth = info.bandwidth,
        .heights = info.heights,
        .heights_len = info.heights_len,
    };
}

fn readStderr(reader: *StderrReader) void {
    const io = global.io();
    defer reader.file.close(io);
    var buffer: [4096]u8 = undefined;
    while (true) {
        const len = reader.file.readStreaming(io, &.{&buffer}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => break,
        };
        if (len == 0) continue;
        const available = reader.bytes.len - reader.len;
        const copy_len = @min(available, len);
        @memcpy(reader.bytes[reader.len..][0..copy_len], buffer[0..copy_len]);
        reader.len += copy_len;
    }
}

/// Kill yt-dlp and everything it started, so no descendant keeps our pipes open.
fn killTree(child: *std.process.Child, io: std.Io) void {
    if (child.id) |pid| std.posix.kill(-pid, std.posix.SIG.KILL) catch {};
    child.kill(io);
}

fn timeoutWorker(timeout: *Timeout) void {
    var elapsed_ms: u32 = 0;
    while (elapsed_ms < resolve_timeout_ms) : (elapsed_ms += 50) {
        if (timeout.state.load(.acquire) != 0) return;
        std.Io.sleep(global.io(), .fromMilliseconds(50), .awake) catch unreachable;
    }
    if (timeout.state.cmpxchgStrong(0, 2, .acq_rel, .acquire) == null) {
        killTree(timeout.child, global.io());
    }
}

fn inFlatpak(io: std.Io) bool {
    const file = std.Io.Dir.openFileAbsolute(io, "/.flatpak-info", .{ .mode = .read_only }) catch return false;
    file.close(io);
    return true;
}

fn onDone(ud: ?*anyopaque) callconv(.c) void {
    const job: *Job = @ptrCast(@alignCast(ud orelse return));
    defer freeJob(job);
    job.done(job.generation, &job.result);
}

fn onListDone(ud: ?*anyopaque) callconv(.c) void {
    const job: *ListJob = @ptrCast(@alignCast(ud orelse return));
    defer freeListJob(job);
    job.done(job.generation, &job.result);
}

fn freeJob(job: *Job) void {
    freeResult(&job.result);
    alloc.free(job.url);
    alloc.destroy(job);
}

fn freeListJob(job: *ListJob) void {
    freeListResult(&job.result);
    alloc.free(job.url);
    alloc.destroy(job);
}
