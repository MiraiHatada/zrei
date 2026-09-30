//! source with a single oscillator
const Single = @This();

const dsp = @import("../../dsp.zig");
const Oscillator = dsp.Oscillator;
const std = @import("std");

oscillator: Oscillator,
waveform: Oscillator.WaveForm,

pub fn init(sample_rate: f64, waveform: Oscillator.WaveForm) Single {
    return .{
        .oscillator = .init(sample_rate),
        .waveform = waveform,
    };
}

pub fn render(self: *Single, buffer: []f32, frequency: f64) void {
    self.oscillator.render(buffer, frequency, self.waveform);
    for (buffer) |*s| {
        s.* = std.math.clamp(s.*, -1.0, 1.0);
    }
}

pub fn renderSkip(self: *Single, buffer: []const f32, frequency: f64) void {
    self.oscillator.renderSkip(buffer, frequency);
}

pub fn sampleRate(self: Single) f64 {
    return self.oscillator.sample_rate;
}

test "render and renderSkip are identical in phase" {
    const testing = std.testing;

    var s1: Single = .init(44100.0, .saw);
    var s2: Single = .init(44100.0, .saw);

    var buffer: [128]f32 = undefined;
    s1.render(&buffer, 440.0);
    s2.renderSkip(&buffer, 440.0);

    try testing.expectApproxEqAbs(s1.oscillator.phase, s2.oscillator.phase, 1e-10);
}
