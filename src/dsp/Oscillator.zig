//! simple oscillator
const Oscillator = @This();

const std = @import("std");
const assert = std.debug.assert;

/// phase accumulator, 0 ≤ phase < 1
phase: f64,
/// sample rate (sample per sec)
sample_rate: f64,

/// how to sample the phase
pub const WaveForm = enum { sine, triangle, saw, square };

/// `sample_rate` typically 44.1kHz or 48kHz
pub fn init(sample_rate: f64) Oscillator {
    return .{
        .phase = 0.0,
        .sample_rate = sample_rate,
    };
}

/// sine wave for now
///
/// assumes `frequency` is lower than the nyquist frequency
pub fn render(self: *Oscillator, buffer: []f32, frequency: f64, waveform: WaveForm) void {
    // delta phi : how fast phase increases
    const dt = frequency / self.sample_rate;
    // frequency < nyquist_frequency
    // an interesting behaviour where dt = 0.5; sine wave always points to 0
    assert(dt < 0.5);

    // outer dispatch
    switch (waveform) {
        .sine => self.renderLoop(buffer, dt, sampleSine),
        .saw => self.renderLoop(buffer, dt, sampleSaw),
        .square => self.renderLoop(buffer, dt, sampleSquare),
        .triangle => self.renderLoop(buffer, dt, sampleTriangle),
    }
}

inline fn renderLoop(self: *Oscillator, buffer: []f32, dt: f64, comptime sampler: fn (f32, f32) f32) void {
    const delta32: f32 = @floatCast(dt);
    for (buffer) |*sample| {
        // sine wave doesn't have a jump
        const phase32: f32 = @floatCast(self.phase);
        sample.* = sampler(phase32, delta32);

        self.phase += dt;
        if (self.phase >= 1.0) {
            self.phase -= 1.0;
        }
    }
}

fn sampleSine(phase: f32, dt: f32) f32 {
    _ = dt;
    return @sin(phase * 2.0 * std.math.pi);
}

fn sampleTriangle(phase: f32, dt: f32) f32 {
    _ = dt;
    return 4.0 * @abs(phase - 0.5) - 1.0;
}

fn sampleSaw(phase: f32, dt: f32) f32 {
    _ = dt;
    return 2.0 * phase - 1.0;
}

fn sampleSquare(phase: f32, dt: f32) f32 {
    _ = dt;
    return if (phase < 0.5) 1.0 else -1.0;
}

test "render sine wave" {
    const testing = std.testing;
    var osc: Oscillator = .{ .phase = 0.0, .sample_rate = 44100.0 };
    var buffer: [512]f32 = undefined;

    // la
    osc.render(&buffer, 440.0, .sine);

    // sin(0) is always 0 (wtf)
    try testing.expectApproxEqAbs(@as(f32, 0.0), buffer[0], 1e-6);

    // all samples are within [-1.0, 1.0]
    for (buffer) |s| {
        try testing.expect(-1.0 <= s and s <= 1.0);
    }
}
