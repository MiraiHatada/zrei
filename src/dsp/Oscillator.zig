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

/// sampling mode
pub const Mode = enum { scalar, vector };

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
pub fn render(self: *Oscillator, buffer: []f32, frequency: f64, waveform: WaveForm, mode: Mode) void {
    // delta phi : how fast phase increases
    const dt = frequency / self.sample_rate;
    // frequency < nyquist_frequency
    // an interesting behaviour where dt = 0.5; sine wave always points to 0
    assert(dt < 0.5);

    if (mode == .scalar) {
        switch (waveform) {
            .sine => self.renderLoop(buffer, dt, sampleSine),
            .saw => self.renderLoop(buffer, dt, sampleSaw),
            .square => self.renderLoop(buffer, dt, sampleSquare),
            .triangle => self.renderLoop(buffer, dt, sampleTriangle),
        }
    } else {
        switch (waveform) {
            .saw => self.renderLoopV(buffer, dt, sampleSawV, sampleSaw),
            else => @panic("todoooo"),
        }
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

inline fn renderLoopV(
    self: *Oscillator,
    buffer: []f32,
    dt: f64,
    comptime samplerV: fn (@Vector(4, f32), @Vector(4, f32)) @Vector(4, f32),
    comptime samplerScalar: fn (f32, f32) f32,
) void {
    const delta32: f32 = @floatCast(dt);
    const delta32v: @Vector(4, f32) = @splat(delta32);
    const offsetv: @Vector(4, f32) = .{ 0.0, 1.0, 2.0, 3.0 };

    var i: usize = 0;
    const vector_bound = buffer.len - (buffer.len % 4);
    while (i < vector_bound) : (i += 4) {
        const basev: @Vector(4, f32) = @splat(@floatCast(self.phase));
        const basev_forwarded: @Vector(4, f32) = basev + (offsetv * delta32v);
        // some may exceed 1.0 so modulo 1.0
        const phasev = basev_forwarded - @floor(basev_forwarded);
        const samplev = samplerV(phasev, delta32v);
        buffer[i..][0..4].* = samplev;

        self.phase += 4.0 * dt;
        // modulo 1.0
        self.phase -= @floor(self.phase);
    }

    // remainig
    self.renderLoop(buffer[i..], dt, samplerScalar);
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

fn sampleSawV(phase: @Vector(4, f32), dt: @Vector(4, f32)) @Vector(4, f32) {
    _ = dt;
    const one: @Vector(4, f32) = comptime @splat(1.0);
    const two: @Vector(4, f32) = comptime @splat(2.0);
    return two * phase - one;
}

fn sampleSquare(phase: f32, dt: f32) f32 {
    _ = dt;
    return if (phase < 0.5) 1.0 else -1.0;
}

test "render sine wave" {
    const testing = std.testing;
    var osc: Oscillator = .init(44100.0);
    var buffer: [512]f32 = undefined;

    // la
    osc.render(&buffer, 440.0, .sine, .scalar);

    // sin(0) is always 0 (wtf)
    try testing.expectApproxEqAbs(@as(f32, 0.0), buffer[0], 1e-6);

    // all samples are within [-1.0, 1.0]
    for (buffer) |s| {
        try testing.expect(-1.0 <= s and s <= 1.0);
    }
}

test "render saw wave vector same as scalar" {
    const testing = std.testing;
    var osc_s: Oscillator = .init(44100.0);
    var osc_v: Oscillator = .init(44100.0);

    var buf_s: [515]f32 = undefined;
    var buf_v: [515]f32 = undefined;

    osc_s.render(&buf_s, 440.0, .saw, .scalar);
    osc_v.render(&buf_v, 440.0, .saw, .vector);

    try testing.expectApproxEqAbs(osc_s.phase, osc_v.phase, 1e-6);

    for (0..515) |idx| {
        try testing.expectApproxEqAbs(buf_s[idx], buf_v[idx], 1e-6);
    }
}
