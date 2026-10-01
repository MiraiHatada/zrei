//! it is called voice both in harmony and in the dsp
const Voice = @This();

const dsp = @import("../dsp.zig");
const WaveSource = dsp.WaveSource;
const Filter = dsp.Filter;
const AdsrEnvelope = dsp.AdsrEnvelope;
const std = @import("std");
const assert = std.debug.assert;

sample_rate: f64,
source: WaveSource,
filter: Filter,
envelope: AdsrEnvelope,
frequency: f64 = dsp.pitch.a4hz_default,

pub const Params = struct {
    source: WaveSource.Params,
    filter: Filter.Params,
    envelope: AdsrEnvelope.Params,
};

/// initialize voice, ensure consistency between oscillator and envelope.
///
/// * assume `sample_rate` to be positive.
/// * assume `params.envelope.sustain_level` within [0.0, 1.0].
/// * assume `params.filter.[!bypass].cutoff_hz` to be positive and lower than the nyquist frequency.
/// * assume `params.filter.[!bypass].q` to be positive.
pub fn init(sample_rate: f64, params: Params) Voice {
    assert(sample_rate > 0.0);
    const src: WaveSource = .init(sample_rate, params.source);
    const filter: Filter = .init(sample_rate, params.filter);
    const env: AdsrEnvelope = .init(sample_rate, params.envelope);
    return .{
        .sample_rate = sample_rate,
        .source = src,
        .filter = filter,
        .envelope = env,
    };
}

/// start playing a note of `frequency` Hz
///
/// * assume `frequency` is positive and lower than nyquist frequency
pub fn noteOn(self: *Voice, frequency: f64) void {
    assert(frequency > 0.0);
    assert(frequency < 0.5 * self.sample_rate);
    self.frequency = frequency;
    if (self.envelope.state == .idle) {
        // idle → attack shall be a complete restart without resonance
        self.filter.reset();
    }
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
    assert(0.0 < frequency);
    assert(frequency < 0.5 * self.sample_rate);
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
        self.source.renderSkip(buffer, self.frequency);
        return;
    }
    self.source.render(buffer, self.frequency);
    self.filter.apply(buffer);
    self.envelope.apply(buffer);
}

/// check if the voice is playing a note (including release phase)
pub fn active(self: Voice) bool {
    return self.envelope.state != .idle;
}

test "render note cycle" {
    const testing = std.testing;

    const params: Params = .{
        .source = .{
            .single = .{ .waveform = .sine },
        },
        .filter = .bypass,
        .envelope = .{
            .attack_sec = 0.01,
            .decay_sec = 0.01,
            .sustain_level = 0.5,
            .release_sec = 0.02,
        },
    };
    var voice: Voice = .init(1000.0, params);
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

    const params: Params = .{
        .source = .{
            .dual = .{ .waveform = .square, .detune_cents = 20.0 },
        },
        .filter = .bypass,
        .envelope = .{
            .attack_sec = 0.02,
            .decay_sec = 0.02,
            .sustain_level = 0.6,
            .release_sec = 0.02,
        },
    };
    var voice1: Voice = .init(1000.0, params);
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
