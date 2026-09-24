//! it is called voice both in harmony and in the dsp
const Voice = @This();

const dsp = @import("../dsp.zig");
const Oscillator = dsp.Oscillator;
const AdsrEnvelope = dsp.AdsrEnvelope;
const std = @import("std");
const assert = std.debug.assert;

oscillator: Oscillator,
envelope: AdsrEnvelope,
frequency: f64 = dsp.pitch.a4hz_default,
waveform: Oscillator.WaveForm,

/// initialize voice, ensure consistency between oscillator and envelope
///
/// * assume `adsr_params.sustain_level` within [0.0, 1.0]
pub fn init(sample_rate: f64, waveform: Oscillator.WaveForm, adsr_params: AdsrEnvelope.Params) Voice {
    assert(0.0 <= adsr_params.sustain_level and adsr_params.sustain_level <= 1.0);
    const osc: Oscillator = .init(sample_rate);
    const env: AdsrEnvelope = .init(sample_rate, adsr_params);
    return .{
        .oscillator = osc,
        .envelope = env,
        .waveform = waveform,
    };
}

/// start playing a note of `frequency` Hz
///
/// * assume `frequency` is positive and lower than nyquist frequency
pub fn noteOn(self: *Voice, frequency: f64) void {
    assert(frequency > 0.0);
    assert(frequency < 0.5 * self.oscillator.sample_rate);
    self.frequency = frequency;
    self.envelope.trigger();
}

/// start releasing current note
pub fn noteOff(self: *Voice) void {
    self.envelope.release();
}

/// move pitch to `frequency` Hz without envelope action
///
/// * assume `frequency` is positive and lower than nyquist frequency
pub fn noteMove(self: *Voice, frequency: f64) void {
    assert(frequency > 0.0);
    assert(frequency < 0.5 * self.oscillator.sample_rate);
    self.frequency = frequency;
}

/// render the current voice into `buffer`
///
/// * `buffer` is modified in place
/// * assume `buffer` is non-empty
pub fn render(self: *Voice, buffer: []f32) void {
    assert(buffer.len > 0);
    if (self.envelope.state == .idle) {
        @memset(buffer, 0.0);
        return;
    }
    self.oscillator.render(buffer, self.frequency, self.waveform);
    self.envelope.apply(buffer);
}

/// check if the voice is playing a note (including release phase)
pub fn active(self: Voice) bool {
    return self.envelope.state != .idle;
}

test "render note cycle" {
    const testing = std.testing;

    var voice: Voice = .init(1000.0, .sine, .{
        .attack_sec = 0.01,
        .decay_sec = 0.01,
        .sustain_level = 0.5,
        .release_sec = 0.02,
    });
    var buffer: [20]f32 = undefined;

    voice.noteOn(100.0);
    voice.render(&buffer);
    try testing.expectEqual(true, voice.active());

    voice.noteMove(200.0);
    try testing.expectEqual(200.0, voice.frequency);

    voice.noteOff();
    voice.render(&buffer);
    try testing.expectEqual(false, voice.active());

    voice.render(&buffer);
    for (buffer) |sample| {
        try testing.expectEqual(0.0, sample);
    }
}

test "render in chunk, facade" {
    const testing = std.testing;

    var voice1: Voice = .init(1000.0, .saw, .{
        .attack_sec = 0.02,
        .decay_sec = 0.02,
        .sustain_level = 0.6,
        .release_sec = 0.02,
    });
    var voice2 = voice1;

    voice1.noteOn(100.0);
    voice2.noteOn(100.0);

    var first: [64]f32 = undefined;
    voice1.render(&first);

    var second: [64]f32 = undefined;
    voice2.render(second[0..16]);
    voice2.render(second[16..48]);
    voice2.render(second[48..64]);

    for (0..64) |i| {
        try testing.expectApproxEqAbs(first[i], second[i], 1e-6);
    }
}
