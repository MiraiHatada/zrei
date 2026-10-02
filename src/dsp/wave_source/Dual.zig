//! source with detuned two oscillators
const Dual = @This();

const dsp = @import("../../dsp.zig");
const Oscillator = dsp.Oscillator;
const std = @import("std");

osc1: Oscillator,
osc2: Oscillator,
waveform: Oscillator.WaveForm = .saw,
detune_cents: f64,
detune_ratio1: f64,
detune_ratio2: f64,

/// initialize dual oscillator with sample rate, waveform, and detune in cents.
/// "cent" here means semitone divided into 100 pieces. whole 1 octave has 1200 cents.
///
/// * assume `sample_rate` to be positive.
pub fn init(sample_rate: f64, waveform: Oscillator.WaveForm, detune_cents: f64) Dual {
    var self: Dual = .{
        .osc1 = .init(sample_rate),
        .osc2 = .init(sample_rate),
        .waveform = waveform,
        .detune_cents = undefined,
        .detune_ratio1 = undefined,
        .detune_ratio2 = undefined,
    };
    self.setDetune(detune_cents);
    return self;
}

/// set detune width in cents and update cached frequency ratio
pub fn setDetune(self: *Dual, detune_cents: f64) void {
    self.detune_cents = detune_cents;
    const half_cents = self.detune_cents * 0.5;
    self.detune_ratio1 = std.math.pow(f64, 2.0, -half_cents / 1200.0);
    self.detune_ratio2 = std.math.pow(f64, 2.0, half_cents / 1200.0);
}

/// render dual oscillator into `buffer`.
///
/// * outputs are strictly normalized and bounded to [-1.0, 1.0]
pub fn render(self: *Dual, noalias buffer: []f32, frequency: f64) void {
    // nyquist guard
    const lim_nyquist = self.osc1.sample_rate * 0.499;
    const freq1 = @min(frequency * self.detune_ratio1, lim_nyquist);
    const freq2 = @min(frequency * self.detune_ratio2, lim_nyquist);

    const chunk_size: usize = 512;
    var temporary: [chunk_size]f32 = undefined;
    var offset: usize = 0;

    while (offset < buffer.len) {
        const size = @min(chunk_size, buffer.len - offset);
        const chunk = buffer[offset..][0..size];
        const temp = temporary[0..size];

        self.osc1.render(chunk, freq1, self.waveform);
        self.osc2.render(temp, freq2, self.waveform);

        // add up two samples and divide by 2
        for (chunk, temp) |*sample1, sample2| {
            const raw = (sample1.* + sample2) * 0.5;
            sample1.* = std.math.clamp(raw, -1.0, 1.0);
        }

        offset += size;
    }
}

pub fn renderSkip(self: *Dual, buffer: []const f32, frequency: f64) void {
    // nyquist guard still applies to correctly emulate delta phase
    const lim_nyquist = self.osc1.sample_rate * 0.499;
    const freq1 = @min(frequency * self.detune_ratio1, lim_nyquist);
    const freq2 = @min(frequency * self.detune_ratio2, lim_nyquist);

    self.osc1.renderSkip(buffer, freq1);
    self.osc2.renderSkip(buffer, freq2);
}

test "chunk invariance" {
    const testing = std.testing;

    var d1: Dual = .init(44100.0, .saw, 12.0);
    var d2 = d1;

    var full: [64]f32 = undefined;
    d1.render(&full, 330.0);

    var chunked: [64]f32 = undefined;
    d2.render(chunked[0..20], 330.0);
    d2.render(chunked[20..50], 330.0);
    d2.render(chunked[50..64], 330.0);

    for (0..64) |i| {
        try testing.expectApproxEqAbs(full[i], chunked[i], 1e-6);
    }
}

test "render and renderSkip are identical in phase" {
    const testing = std.testing;

    var d1: Dual = .init(44100.0, .saw, 12.0);
    var d2: Dual = .init(44100.0, .saw, 12.0);

    var buffer: [200]f32 = undefined;
    d1.render(&buffer, 330.0);
    d2.renderSkip(&buffer, 330.0);

    try testing.expectApproxEqAbs(d1.osc1.phase, d2.osc1.phase, 1e-10);
    try testing.expectApproxEqAbs(d1.osc2.phase, d2.osc2.phase, 1e-10);
}
