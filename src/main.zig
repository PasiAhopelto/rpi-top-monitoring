const std = @import("std");
const metrics = @import("metrics.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var refresh_interval_s: u64 = 10;
    if (args.len > 1) {
        refresh_interval_s = std.fmt.parseInt(u64, args[1], 10) catch 10;
    }

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    // Enter alternative screen and hide cursor
    try stdout.writeAll("\x1b[?1049h\x1b[?25l");
    try stdout.flush();
    defer {
        _ = Io_stdout_writeStreamingAll(io, "\x1b[?25h\x1b[?1049l") catch {};
    }

    var history: std.ArrayListUnmanaged(HistoricalEntry) = .empty;
    defer history.deinit(allocator);

    while (true) {
        const sys_metrics = try metrics.getMetrics(allocator, io);
        
        const timestamp = std.Io.Clock.now(.real, io);
        const now_s = @divTrunc(timestamp.toNanoseconds(), std.time.ns_per_s);

        try history.insert(allocator, 0, .{
            .timestamp = @intCast(now_s),
            .metrics = sys_metrics,
        });

        if (history.items.len > 20) {
            _ = history.orderedRemove(20);
        }

        try stdout.writeAll("\x1b[H\x1b[2J");

        try stdout.writeAll("\x1b[1;36mRPi Top Monitor (v0.1.0)\x1b[0m | ");
        try stdout.print("Refresh: {d}s | Press Ctrl+C to exit\n", .{refresh_interval_s});
        try stdout.writeAll("--------------------------------------------------------------------------------\n");
        
        try stdout.writeAll("\x1b[1;37mTime      CPU Temp  CPU Freq  CPU Load  CPU Gov      GPU Temp  GPU Freq\x1b[0m\n");
        try stdout.writeAll("--------------------------------------------------------------------------------\n");

        for (history.items) |entry| {
            const m = entry.metrics;
            
            var time_buf: [32]u8 = undefined;
            const time_str = try formatTimestamp(entry.timestamp, &time_buf);

            try stdout.print("{s:8}  ", .{time_str});
            try stdout.print("{d:5.1}°C    ", .{m.cpu.temp});
            try stdout.print("{d:4.0}MHz   ", .{m.cpu.freq_mhz});
            try stdout.print("{d:5.1}%    ", .{m.cpu.load_percent});
            
            const gov = std.mem.sliceTo(&m.cpu.governor, 0);
            try stdout.print("{s:10}  ", .{gov});

            try stdout.print("{d:5.1}°C    ", .{m.gpu.temp});
            try stdout.print("{d:4.0}MHz\n", .{m.gpu.freq_mhz});
        }

        try stdout.flush();
        try io.sleep(.fromSeconds(@intCast(refresh_interval_s)), .awake);
    }
}

const HistoricalEntry = struct {
    timestamp: i64,
    metrics: metrics.SystemMetrics,
};

fn formatTimestamp(ts: i64, buf: []u8) ![]const u8 {
    const seconds_in_day = @as(i64, 86400);
    const day_seconds = @rem(ts, seconds_in_day);
    const hours = @divTrunc(day_seconds, 3600);
    const minutes = @divTrunc(@rem(day_seconds, 3600), 60);
    const seconds = @rem(day_seconds, 60);

    return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}:{d:0>2}", .{ hours, minutes, seconds });
}

fn Io_stdout_writeStreamingAll(io: std.Io, bytes: []const u8) !void {
    try std.Io.File.stdout().writeStreamingAll(io, bytes);
}
