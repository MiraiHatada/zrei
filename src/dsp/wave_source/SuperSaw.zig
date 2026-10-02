//! source with 7 detuned saw oscillators
const SuperSaw = @This();

const dsp = @import("../../dsp.zig");
const Oscillator = dsp.Oscillator;
const std = @import("std");
const assert = std.debug.assert;

oscillators: [7]Oscillator,
detune_cents: f64,
detune_ratios: [7]f64,

const detune_weights: [7]f64 = .{
    0.0, // center
    -0.25,
    0.25,
    -0.50,
    0.50,
    -1.00,
    1.00,
};

// the outer the lower
const gain_weights: [7]f32 = .{
    1.0, // center
    0.5,
    0.5,
    0.4,
    0.4,
    0.3,
    0.3,
};

// 1.0 + 0.5*2 + 0.4*2 + 0.3*2 = 3.4
const total_gain: f32 = 3.4;
const norm_factor: f32 = 1.0 / total_gain;

/// initialize 7-saw ensemble with sample rate and detune in cents.
/// "cent" here means semitone divided into 100 pieces. whole 1 octave has 1200 cents.
///
/// * assume `sample_rate` to be positive.
/// * assume `detune_cents` to be non-negative.
pub fn init(sample_rate: f64, detune_cents: f64) SuperSaw {
    var self: SuperSaw = .{
        .oscillators = undefined,
        .detune_cents = undefined,
        .detune_ratios = undefined,
    };

    // golden rate (phi) shifted initial phases
    const phi: f64 = (@sqrt(5.0) - 1.0) / 2.0;
    for (&self.oscillators, 0..) |*osc, i| {
        osc.* = .init(sample_rate);
        const step: f64 = @floatFromInt(i);
        osc.phase = step * phi - @floor(step * phi);
    }

    self.setDetune(detune_cents);
    return self;
}

/// set detune width in cents and update cached frequency ratios.
///
/// * assume `detune_cents` to be non-negative.
pub fn setDetune(self: *SuperSaw, detune_cents: f64) void {
    assert(detune_cents >= 0.0);
    self.detune_cents = detune_cents;
    for (0..7) |i| {
        const cents = self.detune_cents * detune_weights[i];
        self.detune_ratios[i] = std.math.pow(f64, 2.0, cents / 1200.0);
    }
}

/// render 7-saw ensemble into `buffer`.
///
/// * outputs are strictly normalized and bounded to [-1.0, 1.0]
pub fn render(self: *SuperSaw, noalias buffer: []f32, frequency: f64) void {
    // nyquist guards
    const lim_nyquist = self.oscillators[0].sample_rate * 0.499;
    var freqs: [7]f64 = undefined;
    for (0..7) |i| {
        freqs[i] = @min(frequency * self.detune_ratios[i], lim_nyquist);
    }

    const chunk_size: usize = 512;
    var temporary: [chunk_size]f32 = undefined;
    var offset: usize = 0;

    while (offset < buffer.len) {
        const size = @min(chunk_size, buffer.len - offset);
        const chunk = buffer[offset..][0..size];

        // center oscillator
        self.oscillators[0].render(chunk, freqs[0], .saw);

        // side oscillators
        const temp = temporary[0..size];
        inline for (1..7) |i| {
            self.oscillators[i].render(temp, freqs[i], .saw);
            const weight: f32 = gain_weights[i];
            for (chunk, temp) |*acc, sample| {
                acc.* += sample * weight;
            }
        }

        for (chunk) |*sample| {
            const raw = sample.* * norm_factor;
            sample.* = std.math.clamp(raw, -1.0, 1.0);
        }
        offset += size;
    }
}

pub fn renderSkip(self: *SuperSaw, buffer: []const f32, frequency: f64) void {
    // nyquist guard still applies to correctly emulate delta phase
    const lim_nyquist = self.oscillators[0].sample_rate * 0.499;
    for (0..7) |i| {
        const freq = @min(frequency * self.detune_ratios[i], lim_nyquist);
        self.oscillators[i].renderSkip(buffer, freq);
    }
}

test "chunk invariance" {
    const testing = std.testing;

    var ss1: SuperSaw = .init(44100.0, 25.0);
    var ss2 = ss1;

    var full: [64]f32 = undefined;
    ss1.render(&full, 220.0);

    var chunked: [64]f32 = undefined;
    ss2.render(chunked[0..20], 220.0);
    ss2.render(chunked[20..50], 220.0);
    ss2.render(chunked[50..64], 220.0);

    for (0..64) |i| {
        try testing.expectApproxEqAbs(full[i], chunked[i], 1e-6);
    }
}

test "render and renderSkip are identical in phase" {
    const testing = std.testing;

    var ss1: SuperSaw = .init(44100.0, 25.0);
    var ss2: SuperSaw = .init(44100.0, 25.0);

    var buffer: [300]f32 = undefined;
    ss1.render(&buffer, 220.0);
    ss2.renderSkip(&buffer, 220.0);

    for (0..7) |i| {
        try testing.expectApproxEqAbs(ss1.oscillators[i].phase, ss2.oscillators[i].phase, 1e-10);
    }
}

test "supersaw high frequency nyquist safety" {
    const testing = std.testing;

    var ss: SuperSaw = .init(44100.0, 50.0);
    var buffer: [64]f32 = undefined;
    ss.render(&buffer, 21500.0);

    for (buffer) |sample| {
        try testing.expect(-1.0 <= sample and sample <= 1.0);
    }
}
