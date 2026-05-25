const std = @import("std");
const builtin = @import("builtin");

pub const CpuMetrics = struct {
    temp: f32,
    freq_mhz: f32,
    governor: [32]u8,
    load_percent: f32,
};

pub const GpuMetrics = struct {
    temp: f32,
    freq_mhz: f32,
};

pub const SystemMetrics = struct {
    cpu: CpuMetrics,
    gpu: GpuMetrics,
};

var prev_idle: u64 = 0;
var prev_total: u64 = 0;

pub fn getMetrics(allocator: std.mem.Allocator, io: std.Io) !SystemMetrics {
    if (builtin.os.tag != .linux) {
        return getMockMetrics();
    }

    const cpu_temp = try readCpuTemp(io);
    const cpu_freq = try readCpuFreq(io);
    const cpu_load = try readCpuLoad(io);

    const gpu_temp = try readGpuTemp(allocator, io);
    const gpu_freq = try readGpuFreq(allocator, io);

    var gov_buf = [_]u8{0} ** 32;
    readCpuGovernor(io, &gov_buf);

    return SystemMetrics{
        .cpu = .{
            .temp = cpu_temp,
            .freq_mhz = cpu_freq,
            .governor = gov_buf,
            .load_percent = cpu_load,
        },
        .gpu = .{
            .temp = gpu_temp,
            .freq_mhz = gpu_freq,
        },
    };
}

fn readCpuTemp(io: std.Io) !f32 {
    const path = "/sys/class/thermal/thermal_zone0/temp";
    var file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return 0.0;
    defer file.close(io);

    var buf: [32]u8 = undefined;
    var reader = file.reader(io, &buf);
    const bytes_read = try reader.interface.readSliceShort(&buf);
    
    const line = std.mem.trim(u8, buf[0..bytes_read], " \n\r");
    const temp_milli = std.fmt.parseInt(i32, line, 10) catch return 0.0;
    return @as(f32, @floatFromInt(temp_milli)) / 1000.0;
}

fn readCpuFreq(io: std.Io) !f32 {
    const path = "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq";
    var file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return 0.0;
    defer file.close(io);

    var buf: [32]u8 = undefined;
    var reader = file.reader(io, &buf);
    const bytes_read = try reader.interface.readSliceShort(&buf);
    
    const line = std.mem.trim(u8, buf[0..bytes_read], " \n\r");
    const freq_khz = std.fmt.parseInt(u32, line, 10) catch return 0.0;
    return @as(f32, @floatFromInt(freq_khz)) / 1000.0;
}

fn readCpuGovernor(io: std.Io, out_buf: *[32]u8) void {
    const path = "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor";
    var file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch {
        @memcpy(out_buf[0.."unknown".len], "unknown");
        return;
    };
    defer file.close(io);

    var buf: [64]u8 = undefined;
    var reader = file.reader(io, &buf);
    const bytes_read = reader.interface.readSliceShort(&buf) catch {
        @memcpy(out_buf[0.."unknown".len], "unknown");
        return;
    };
    
    const trimmed = std.mem.trim(u8, buf[0..bytes_read], " \n\r\t\x00");
    const len = @min(trimmed.len, 31);
    @memcpy(out_buf[0..len], trimmed[0..len]);
}

fn readCpuLoad(io: std.Io) !f32 {
    const path = "/proc/stat";
    var file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return 0.0;
    defer file.close(io);

    var buf: [1024]u8 = undefined;
    var reader = file.reader(io, &buf);
    const bytes_read = try reader.interface.readSliceShort(&buf);
    
    var line_it = std.mem.splitScalar(u8, buf[0..bytes_read], '\n');
    const first_line = line_it.next() orelse return 0.0;

    var word_it = std.mem.tokenizeScalar(u8, first_line, ' ');
    _ = word_it.next(); // skip "cpu"

    const user = std.fmt.parseInt(u64, word_it.next() orelse "0", 10) catch 0;
    const nice = std.fmt.parseInt(u64, word_it.next() orelse "0", 10) catch 0;
    const system = std.fmt.parseInt(u64, word_it.next() orelse "0", 10) catch 0;
    const idle = std.fmt.parseInt(u64, word_it.next() orelse "0", 10) catch 0;
    const iowait = std.fmt.parseInt(u64, word_it.next() orelse "0", 10) catch 0;
    const irq = std.fmt.parseInt(u64, word_it.next() orelse "0", 10) catch 0;
    const softirq = std.fmt.parseInt(u64, word_it.next() orelse "0", 10) catch 0;
    const steal = std.fmt.parseInt(u64, word_it.next() orelse "0", 10) catch 0;

    const current_idle = idle + iowait;
    const current_non_idle = user + nice + system + irq + softirq + steal;
    const current_total = current_idle + current_non_idle;

    const total_diff = current_total - prev_total;
    const idle_diff = current_idle - prev_idle;

    prev_total = current_total;
    prev_idle = current_idle;

    if (total_diff == 0) return 0.0;
    return @as(f32, @floatFromInt(total_diff - idle_diff)) / @as(f32, @floatFromInt(total_diff)) * 100.0;
}

fn readGpuTemp(allocator: std.mem.Allocator, io: std.Io) !f32 {
    const result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "vcgencmd", "measure_temp" },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stdout.len == 0) return 0.0;
    var it = std.mem.splitScalar(u8, result.stdout, '=');
    _ = it.next();
    const val_str = it.next() orelse return 0.0;
    const trimmed = std.mem.trimEnd(u8, val_str, "'C\n\r ");
    return std.fmt.parseFloat(f32, trimmed) catch 0.0;
}

fn readGpuFreq(allocator: std.mem.Allocator, io: std.Io) !f32 {
    const result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "vcgencmd", "measure_clock", "core" },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stdout.len == 0) return 0.0;
    var it = std.mem.splitScalar(u8, result.stdout, '=');
    _ = it.next();
    const val_str = it.next() orelse return 0.0;
    const freq_hz = std.fmt.parseInt(u64, std.mem.trim(u8, val_str, " \n\r"), 10) catch 0;
    return @as(f32, @floatFromInt(freq_hz)) / 1000000.0;
}

fn getMockMetrics() SystemMetrics {
    var gov: [32]u8 = [_]u8{0} ** 32;
    @memcpy(gov[0.."ondemand".len], "ondemand");
    return .{
        .cpu = .{
            .temp = 45.5,
            .freq_mhz = 1500.0,
            .governor = gov,
            .load_percent = 12.5,
        },
        .gpu = .{
            .temp = 42.0,
            .freq_mhz = 500.0,
        },
    };
}
