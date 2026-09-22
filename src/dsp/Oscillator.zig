//! simple oscillator
const Oscillator = @This();

const std = @import("std");
const assert = std.debug.assert;

/// phase accumulator, 0 ≤ phase < 1
phase: f64,
/// sample rate (samples per sec)
sample_rate: f64,

// alias for the vector type used in simd arithmetic
const VecF32 = @Vector(4, f32);

/// how to sample the phase
const WaveForm = enum { sine, triangle, saw, square };

/// sampling mode (scalar version for testing)
const Mode = enum { scalar, vector };

/// `sample_rate` typically 44.1kHz or 48kHz
pub fn init(sample_rate: f64) Oscillator {
    return .{
        .phase = 0.0,
        .sample_rate = sample_rate,
    };
}

/// an oscillator
///
/// * assumes `frequency` is lower than the nyquist frequency
pub fn render(self: *Oscillator, buffer: []f32, frequency: f64, waveform: WaveForm) void {
    self.renderInner(buffer, frequency, waveform, .vector);
}

/// internally accept the scalar `mode` for examination
fn renderInner(self: *Oscillator, buffer: []f32, frequency: f64, waveform: WaveForm, mode: Mode) void {
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
            .sine => self.renderLoopV(buffer, dt, sampleSineV, sampleSine),
            .saw => self.renderLoopV(buffer, dt, sampleSawV, sampleSaw),
            .square => self.renderLoopV(buffer, dt, sampleSquareV, sampleSquare),
            .triangle => self.renderLoopV(buffer, dt, sampleTriangleV, sampleTriangle),
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
    comptime samplerV: fn (VecF32, VecF32) VecF32,
    comptime samplerScalar: fn (f32, f32) f32,
) void {
    const delta32: f32 = @floatCast(dt);
    const delta32v: VecF32 = @splat(delta32);
    const offsetv: VecF32 = .{ 0.0, 1.0, 2.0, 3.0 };

    var i: usize = 0;
    const vector_bound = buffer.len - (buffer.len % 4);
    while (i < vector_bound) : (i += 4) {
        const basev: VecF32 = @splat(@floatCast(self.phase));
        const basev_forwarded: VecF32 = basev + (offsetv * delta32v);
        // some may exceed 1.0 so modulo 1.0
        const phasev = basev_forwarded - @floor(basev_forwarded);
        const samplev = samplerV(phasev, delta32v);
        buffer[i..][0..4].* = samplev;

        self.phase += 4.0 * dt;
        // modulo 1.0
        self.phase -= @floor(self.phase);
    }

    // remaining
    self.renderLoop(buffer[i..], dt, samplerScalar);
}

fn sampleSine(phase: f32, dt: f32) f32 {
    _ = dt; // sine wave has C^∞ continuity
    return @sin(phase * 2.0 * std.math.pi);
}

fn sampleSineV(phase: VecF32, dt: VecF32) VecF32 {
    _ = dt; // sine wave has C^∞ continuity
    const two: VecF32 = @splat(2.0);
    const pi: VecF32 = @splat(std.math.pi);
    return @sin(phase * two * pi);
}

fn sampleTriangle(phase: f32, dt: f32) f32 {
    const delta_slope: f32 = 8.0 * dt; // katamuki no henkaryo

    var sample = 4.0 * @abs(phase - 0.5) - 1.0;
    // the valley bottom is at phase = 0.5
    var shifted = phase + 0.5;
    if (shifted >= 1.0) shifted -= 1.0; // mod 1.0

    // corrected = sample + (-delta_slope * pbm(top)) + (delta_slope * pbm(bottom))
    // can be factorize to:
    //   corrected = sample + delta_slope * (pbm(bottom) - pbm(top))
    sample += delta_slope * (polyblamp(shifted, dt) - polyblamp(phase, dt));

    return sample;
}

fn sampleTriangleV(phase: VecF32, dt: VecF32) VecF32 {
    const four: VecF32 = @splat(4.0);
    const half: VecF32 = @splat(0.5);
    const one: VecF32 = @splat(1.0);
    const eight: VecF32 = @splat(8.0);

    const delta_slope = eight * dt;

    var sample = four * @abs(phase - half) - one;
    // correct the mountaintop and the valley bottom
    var shifted = phase + half;
    shifted -= @floor(shifted); // mod 1.0
    sample += delta_slope * (polyblampV(shifted, dt) - polyblampV(phase, dt));

    return sample;
}

fn sampleSaw(phase: f32, dt: f32) f32 {
    const naive = 2.0 * phase - 1.0;
    return naive - polyblep(phase, dt);
}

fn sampleSawV(phase: VecF32, dt: VecF32) VecF32 {
    const one: VecF32 = @splat(1.0);
    const two: VecF32 = @splat(2.0);
    const naive = two * phase - one;
    return naive - polyblepV(phase, dt);
}

fn sampleSquare(phase: f32, dt: f32) f32 {
    var sample: f32 = if (phase < 0.5) 1.0 else -1.0;

    // correct the jump at phase = 0.0
    sample += polyblep(phase, dt);
    // correct the fall at phase = 0.5
    var shifted = phase + 0.5;
    if (shifted >= 1.0) shifted -= 1.0; // mod 1.0
    sample -= polyblep(shifted, dt);

    return sample;
}

fn sampleSquareV(phase: VecF32, dt: VecF32) VecF32 {
    // vector constants
    const half: VecF32 = @splat(0.5);
    const one: VecF32 = @splat(1.0);
    const minus_one: VecF32 = @splat(-1.0);

    // determines actual sample (mask ? 1 : 0)
    const mask: @Vector(4, bool) = phase < half;
    var sample = @select(f32, mask, one, minus_one);

    // correct the jump and fall
    var shifted = phase + half;
    shifted -= @floor(shifted); // mod 1.0
    sample = sample + polyblepV(phase, dt) - polyblepV(shifted, dt);

    return sample;
}

/// correct discontinuity (-2.0 fall) where phase = 0.0
///
/// * use `SAMPLE(t) - polyblep(t)` as a corrected value
/// * may also use `SAMPLE(t) + polyblep(t)` as an upside-down correction (i.e. jump)
inline fn polyblep(phase: f32, dt: f32) f32 {
    assert(phase <= 1.0); // our phase is [0.0, 1.0) ; well, but the definition is.
    assert(phase >= 0.0);
    // phase within [0.0, dt)
    if (phase < dt) {
        // normalized step (the first step after fall down)
        const t = phase / dt;
        return (2.0 * t) - (t * t) - 1.0; // to be subtracted: -(-(t - 1)^2)
    }
    // phase within (1.0 - dt, 1.0]
    else if (phase > 1.0 - dt) {
        // normalized step (the last step before fall down)
        const t = (phase - 1.0) / dt;
        return (2.0 * t) + (t * t) + 1.0;
    }

    return 0.0;
}

/// vectored version of `polyblep` function
inline fn polyblepV(phase: VecF32, dt: VecF32) VecF32 {
    // # note: simd shall always stay in branchless
    // early return with @reduce(.And, ...) will have disadvantage in branch prediction
    // which should make it slower than to run through all the simd ariths every time

    // vector constants
    const zero: VecF32 = @splat(0.0);
    const one: VecF32 = @splat(1.0);
    const two: VecF32 = @splat(2.0);

    // the first step after fall down
    const mask_after = phase < dt;
    const correction_after = ret: {
        const t = phase / dt; // todo optimize: phase * inv_dt
        break :ret (two * t) - (t * t) - one;
    };

    // the last step before fall down
    const mask_before = phase > (one - dt);
    const correction_before = ret: {
        const t = (phase - one) / dt; // todo optimize: (phase - one) * inv_dt
        break :ret (two * t) + (t * t) + one;
    };

    var correction = @select(f32, mask_after, correction_after, zero);
    correction = @select(f32, mask_before, correction_before, correction);
    return correction;
}

/// straight up integral of polyblep
///
/// for any function that has a mountaintop at phase = 0.0, \
/// assume `k = f''(before_mountaintop) - f''(after_mountaintop)`, then
/// * `SAMPLE(t) + (k * polyblamp(t))` for mountain top correction
/// * the same stands for valley bottom correction
inline fn polyblamp(phase: f32, dt: f32) f32 {
    assert(phase <= 1.0);
    assert(phase >= 0.0);

    // the step right after mountaintop
    if (phase < dt) {
        const t = phase / dt;
        const d = 1.0 - t;
        return d * d * d / 6.0;
    }
    // the step right before mountaintop
    if (phase > 1.0 - dt) {
        const t = (phase - 1.0) / dt;
        const d = 1.0 + t;
        return d * d * d / 6.0;
    }

    return 0.0;
}

/// vectored version of `polyblamp` function
inline fn polyblampV(phase: VecF32, dt: VecF32) VecF32 {
    const zero: VecF32 = @splat(0.0);
    const one: VecF32 = @splat(1.0);
    const one_six: VecF32 = @splat(1.0 / 6.0);

    // the step right after mountaintop
    const mask_after = phase < dt;
    const correction_after = ret: {
        const t = phase / dt; // todo optimize: phase * inv_dt
        const d = one - t;
        break :ret one_six * d * d * d;
    };

    // the step right before mountaintop
    const mask_before = phase > (one - dt);
    const correction_before = ret: {
        const t = (phase - one) / dt; // todo optimize: (phase - one) * inv_dt
        const d = one + t;
        break :ret one_six * d * d * d;
    };

    var correction = @select(f32, mask_after, correction_after, zero);
    correction = @select(f32, mask_before, correction_before, correction);
    return correction;
}

test "render sine wave" {
    const testing = std.testing;
    var osc: Oscillator = .init(44100.0);
    var buffer: [512]f32 = undefined;

    // la
    osc.render(&buffer, 440.0, .sine);

    // sin(0) is always 0 (wtf)
    try testing.expectApproxEqAbs(@as(f32, 0.0), buffer[0], 1e-5);

    // all samples are within [-1.0, 1.0]
    for (buffer) |s| {
        try testing.expect(-1.0 <= s and s <= 1.0);
    }
}

test "render wave vector same as scalar" {
    const testing = std.testing;
    inline for (std.enums.values(WaveForm)) |form| {
        var osc_s: Oscillator = .init(44100.0);
        var osc_v: Oscillator = .init(44100.0);

        var buf_s: [515]f32 = undefined;
        var buf_v: [515]f32 = undefined;

        osc_s.renderInner(&buf_s, 440.0, form, .scalar);
        osc_v.renderInner(&buf_v, 440.0, form, .vector);

        try testing.expectApproxEqAbs(osc_s.phase, osc_v.phase, 1e-5);

        for (0..515) |idx| {
            try testing.expectApproxEqAbs(buf_s[idx], buf_v[idx], 1e-5);
        }
    }
}
