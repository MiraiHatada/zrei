const service = @import("service.zig");
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.main);

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    // empty argument falls back to help with exit code 0 for ci
    if (args.len < 2 or std.mem.eql(u8, args[1], "help") or containsAny(args[1..], &.{ "--help", "-h" })) {
        try help(io, Io.File.stdout());
        return 0;
    }

    var stderr_buf: [1024]u8 = undefined;
    const stderr = try io.lockStderr(&stderr_buf, null);
    defer io.unlockStderr();
    const terminal = stderr.terminal();

    const cmd = Command.parse(args[1]) orelse {
        terminal.setColor(.red) catch {};
        terminal.writer.print("unknown command: {s}\n", .{args[1]}) catch {};
        terminal.setColor(.reset) catch {};
        terminal.writer.flush() catch {};
        return 1;
    };

    switch (cmd) {
        .render => {
            return try runRender(io, init.gpa, args[2..]);
        },
    }
}

const Command = enum {
    render,

    pub fn parse(raw: []const u8) ?Command {
        return std.meta.stringToEnum(Command, raw);
    }
};

fn runRender(io: Io, allocator: Allocator, args: []const []const u8) !u8 {
    _ = args;
    _ = allocator;
    const out_option: ?[]const u8 = null;
    const filepath = ret: {
        // gotta check if absolute path?
        break :ret out_option orelse "out.wav";
    };
    const file = try Io.Dir.createFile(.cwd(), io, filepath, .{});
    defer file.close(io);
    var file_buf: [1024]u8 = undefined;
    var writer = file.writerStreaming(io, &file_buf);

    // process encode
    service.encode(&writer.interface, 5) catch |err| switch (err) {
        error.WriteFailed => return writer.err.?,
        else => |e| return e,
    };
    try writer.flush();

    var stderr_buf: [1024]u8 = undefined;
    const stderr = try io.lockStderr(&stderr_buf, null);
    defer io.unlockStderr();
    const terminal = stderr.terminal();

    terminal.setColor(.green) catch {};
    terminal.writer.print("rendered: {s}\n", .{filepath}) catch {};
    terminal.setColor(.reset) catch {};
    terminal.writer.flush() catch {};
    return 0;
}

fn help(io: Io, file: Io.File) !void {
    const usage =
        \\usage:
        \\  zrei <command> [options]
        \\
        \\commands:
        \\  render       render waveform to wav file
        \\  help         show this help message
        \\
        \\options:
        \\  -h, --help   show this help message
        \\
        \\example:
        \\  zrei render --freq 440 --wave sine -o out.wav
        \\
    ;
    try file.writeStreamingAll(io, usage);
}

fn containsAny(list: []const []const u8, comptime needles: []const []const u8) bool {
    for (list) |element| {
        inline for (needles) |needle| {
            if (std.mem.eql(u8, element, needle)) return true;
        }
    }
    return false;
}
