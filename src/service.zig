const zrei = @import("zrei");
const dsp = zrei.dsp;
const Oscillator = dsp.Oscillator;
const format = zrei.format;
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.service);
const assert = std.debug.assert;

pub const EncodeError = Io.Writer.Error || Allocator.Error;

pub fn encode(sink: *Io.Writer, sec: u16, allocator: Allocator) EncodeError!void {
    const sample_rate: f64 = comptime 48000.0;
    const fmt: format.wav.Format = .{
        .bits_per_sample = 16,
        .channels = 1,
        .sample_rate = sample_rate,
    };
    const buffer_size = @as(usize, @intFromFloat(sample_rate)) * sec;
    const buffer = try allocator.alloc(f32, buffer_size);
    defer allocator.free(buffer);
    var osc: Oscillator = .init(sample_rate);

    osc.render(buffer, 440.0);

    try format.wav.writePcm16(sink, fmt, buffer);
}
