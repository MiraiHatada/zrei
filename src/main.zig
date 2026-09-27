const zrei = @import("zrei");
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.main);

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    if (args.len < 2) {
        try help(io, Io.File.stderr());
        return 1;
    }

    if (std.mem.eql(u8, args[1], "help") or containsAny(args[1..], &.{ "--help", "-h" })) {
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
            return try runRender(io, args[2..]);
        },
    }
}

const Command = enum {
    render,

    pub fn parse(raw: []const u8) ?Command {
        return std.meta.stringToEnum(Command, raw);
    }
};

fn runRender(io: Io, args: []const []const u8) !u8 {
    const waveform_expr = if (args.len > 0) args[0] else {
        var buffer: [256]u8 = undefined;
        const ls = try io.lockStderr(&buffer, null);
        const terminal = ls.terminal();
        terminal.setColor(.red) catch {};
        terminal.writer.writeAll("specify waveform: [sine, saw, triangle, square]\n") catch {};
        terminal.writer.flush() catch {};
        return 1;
    };
    const out_option: ?[]const u8 = null; // fixme later
    const filepath = out_option orelse "out.wav";
    const file = try Io.Dir.createFile(.cwd(), io, filepath, .{});
    defer file.close(io);
    var file_buffer: [1024]u8 = undefined;
    var writer = file.writerStreaming(io, &file_buffer);

    // process encode
    const rc = zrei.render.wav(&writer.interface, waveform_expr, 5) catch |err| switch (err) {
        error.WriteFailed => return writer.err.?,
    };
    if (rc != .ok) {
        log.err("failed to render waveform: {s}", .{@tagName(rc)});
        return 1;
    }
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
