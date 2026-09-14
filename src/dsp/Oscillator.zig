//! simple oscillator
const Oscillator = @This();

const std = @import("std");
const assert = std.debug.assert;

/// phase accumulator, 0 ≤ phase < 1
phase: f64,
/// sample rate (sample per sec)
sample_rate: f64,

/// `sample_rate` typically 44.1kHz or 48kHz
pub fn init(sample_rate: f64) Oscillator {
    return .{
        .phase = 0.0,
        .sample_rate = sample_rate,
    };
}

/// sine wave for now
pub fn render(self: *Oscillator, buffer: []f32, frequency: f64) void {
    // delta phi : how fast phase increases
    const dt = frequency / self.sample_rate;
    // frequency ≤ nyquest frequency
    assert(dt < 0.5);

    for (buffer) |*sample| {
        // sine wave doesn't have a jump
        const phase32: f32 = @floatCast(self.phase);
        sample.* = @sin(phase32 * 2.0 * std.math.pi);

        self.phase += dt;
        if (self.phase >= 1.0) {
            self.phase -= 1.0;
        }
    }
}

test "render sine wave" {
    const testing = std.testing;
    var osc: Oscillator = .{ .phase = 0.0, .sample_rate = 44100.0 };
    var buffer: [512]f32 = undefined;

    // la
    osc.render(&buffer, 440.0);

    // sin(0) is always 0 (wtf)
    try testing.expectApproxEqAbs(@as(f32, 0.0), buffer[0], 1e-6);

    // all samples are within [-1.0, 1.0]
    for (buffer) |s| {
        try testing.expect(s >= -1.0 and s <= 1.0);
    }
}
