const zrei = @import("zrei");
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMapUnmanaged;
const ArenaAllocator = std.heap.ArenaAllocator;
const WaveForm = zrei.dsp.Oscillator.WaveForm;
const log = std.log.scoped(.main);

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2 or std.mem.eql(u8, args[1], "help") or containsAny(args[1..], &.{ "--help", "-h" })) {
        help(io, Io.File.stdout()) catch {};
        return 0;
    }

    const cmd = Command.parse(args[1]) orelse {
        werror(io, "unknown command: {s}\n", .{args[1]}) catch {};
        return 1;
    };

    switch (cmd) {
        .render => {
            return try runRender(init.gpa, io, args[2..]);
        },
    }
}

const Command = enum {
    render,

    pub fn parse(raw: []const u8) ?Command {
        return std.meta.stringToEnum(Command, raw);
    }
};

const Parser = struct {
    options: StringHashMap([]const u8),
    argument: ?[]const u8,
    arena: ArenaAllocator,

    pub fn init(arena_child: Allocator) !Parser {
        const arena: ArenaAllocator = .init(arena_child);
        return .{
            .options = .empty,
            .argument = null,
            .arena = arena,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn parse(self: *Parser, args: []const []const u8) Allocator.Error!void {
        const allocator = self.arena.allocator();
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            const dash_dash = std.mem.startsWith(u8, arg, "--");
            const dash = !dash_dash and std.mem.startsWith(u8, arg, "-") and arg.len > 1;
            if (dash_dash or dash) {
                const raw = if (dash_dash) arg[2..] else arg[1..];
                if (raw.len == 0) continue;
                if (std.mem.indexOfScalar(u8, raw, '=')) |equal_index| {
                    const key = raw[0..equal_index];
                    const val = raw[equal_index + 1 ..];
                    try self.options.put(allocator, key, val);
                } else if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                    i += 1;
                    try self.options.put(allocator, raw, args[i]);
                } else {
                    try self.options.put(allocator, raw, "");
                }
            } else {
                if (self.argument == null) {
                    self.argument = arg;
                }
            }
        }
    }
};

fn runRender(allocator: Allocator, io: Io, args: []const []const u8) !u8 {
    if (args.len == 0) {
        helpRender(io, Io.File.stdout()) catch {};
        return 0;
    }
    var parser: Parser = try .init(allocator);
    defer parser.deinit();
    try parser.parse(args);

    const out_option: ?[]const u8 =
        parser.options.get("o") orelse
        parser.options.get("out") orelse
        parser.options.get("output");
    const sample_rate_expr: []const u8 =
        parser.options.get("r") orelse
        parser.options.get("rate") orelse
        "48000";

    const sample_rate: u32 = std.fmt.parseInt(u32, sample_rate_expr, 10) catch {
        werror(io, "invalid sample rate: {s}\n", .{sample_rate_expr}) catch {};
        return 1;
    };

    const waveform_expr: []const u8 = parser.argument orelse {
        werror(io, "specify waveform: [sine, saw, triangle, square]\n", .{}) catch {};
        return 1;
    };

    const waveform = std.meta.stringToEnum(WaveForm, waveform_expr) orelse {
        werror(io, "unknown waveform: {s}\n", .{waveform_expr}) catch {};
        return 1;
    };

    const filepath = out_option orelse "out.wav";
    const file = try Io.Dir.createFile(.cwd(), io, filepath, .{});
    defer file.close(io);
    var file_buffer: [1024]u8 = undefined;
    var writer = file.writerStreaming(io, &file_buffer);

    // process encode
    const rc = zrei.render.wav(&writer.interface, sample_rate, waveform, 5) catch |err| switch (err) {
        error.WriteFailed => return writer.err.?,
    };
    if (rc != .ok) {
        log.err("failed to render waveform: {s}", .{@tagName(rc)});
        return 1;
    }
    try writer.flush();

    var stderr_buffer: [1024]u8 = undefined;
    const stderr = try io.lockStderr(&stderr_buffer, null);
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
        \\  zrei render triangle --rate 44100
        \\
    ;
    try file.writeStreamingAll(io, usage);
}

fn helpRender(io: Io, file: Io.File) !void {
    const usage =
        \\usage:
        \\  zrei render <waveform> [options]
        \\
        \\arguments:
        \\  waveform      any of sine, saw, square, or triangle
        \\
        \\options:
        \\  -r, --rate    sampling rate (default to 48000)
        \\  -o, --output  output file path (default to out.wav)
        \\
    ;
    try file.writeStreamingAll(io, usage);
}

fn werror(io: Io, comptime fmt: []const u8, args: anytype) !void {
    var stderr_buffer: [256]u8 = undefined;
    const stderr = try io.lockStderr(&stderr_buffer, null);
    defer io.unlockStderr();
    const terminal = stderr.terminal();
    terminal.setColor(.red) catch {};
    terminal.writer.print(fmt, args) catch {};
    terminal.setColor(.reset) catch {};
    terminal.writer.flush() catch {};
}

fn containsAny(list: []const []const u8, comptime needles: []const []const u8) bool {
    for (list) |element| {
        inline for (needles) |needle| {
            if (std.mem.eql(u8, element, needle)) return true;
        }
    }
    return false;
}
