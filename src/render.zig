//! waveform rendering pipeline
const format = @import("format.zig");
const dsp = @import("dsp.zig");
const Oscillator = dsp.Oscillator;
const Sequencer = dsp.Sequencer;
const Voice = dsp.Voice;
const Tuning = dsp.pitch.Tuning;
const Note = dsp.Note;
const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

pub const RenderWav = enum {
    ok,
    exceeded_4gb,
    samplerate_too_low,
};

pub fn wav(sink: *Io.Writer, sample_rate: u32, waveform: Oscillator.WaveForm, sec: u16) Io.Writer.Error!RenderWav {
    if (sample_rate < 30000) {
        // G9 approx 12,543 Hz in A4 440Hz, it's nyquist for sample rate of the double of it.
        // drawing a line with room, though i am not confident about this value
        return .samplerate_too_low;
    }
    const fmt: format.wav.Format = .{
        .bits_per_sample = 16,
        .channels = 1,
        .sample_rate = sample_rate,
    };
    const samples_size = @as(usize, sample_rate) * sec;
    const bytes = format.wav.createHeader(fmt, samples_size) catch |err| switch (err) {
        error.Exceeded4Gb => return .exceeded_4gb,
    };
    try sink.writeAll(&bytes);

    // we use 2KB (+1KB) stack buffer here, which is way less than ordinary L1 data cache
    // on paper it allows 16+ polyphony without a cache miss but you know life is not that easy
    var buffer: [512]f32 = undefined;
    var buffer_i16_raw: [512 * 2]u8 = undefined;
    var offset: usize = 0;
    const tuning: Tuning = .init(440.0, .equal);
    const voice: Voice = .init(sample_rate, waveform, .{
        .attack_sec = 0.05,
        .decay_sec = 0.1,
        .sustain_level = 0.5,
        .release_sec = 0.1,
    });
    const notes: [12]Note = .{
        .init(.C4, 1.0, 0.8),  .init(.D4, 0.5, 0.8),
        .init(.E4, 0.5, 0.8),  .init(.F4, 0.5, 0.8),
        .init(.G4, 0.5, 0.8),  .init(.A4, 0.5, 0.8),
        .init(.B4, 0.5, 0.8),  .init(.C5, 0.5, 0.5),
        .init(null, 0.5, 0.8), .init(.G4, 0.5, 0.5),
        .init(null, 0.5, 0.8), .init(.C5, 1.0, 0.8),
    };
    var seq: Sequencer = .init(sample_rate, 120, tuning, voice, &notes);
    while (offset < samples_size) {
        const chunk_size = @min(samples_size - offset, buffer.len);
        const chunk: []f32 = buffer[0..chunk_size];
        seq.render(chunk);
        const data = format.wav.encodePcm16(&buffer_i16_raw, chunk);
        try sink.writeAll(data);
        offset += chunk_size;
    }
    assert(offset == samples_size);
    return .ok;
}

test wav {
    const testing = std.testing;
    const allocator = testing.allocator;
    // 48000 * 2 = 96000
    const buffer: []u8 = try allocator.alloc(u8, 44 + 96000);
    defer allocator.free(buffer);
    var sink = Io.Writer.fixed(buffer);

    const res = try wav(&sink, 48000, .saw, 1);
    try testing.expectEqual(.ok, res);

    try testing.expectEqualStrings("RIFF", buffer[0..4]);
    try testing.expectEqualStrings("WAVEfmt ", buffer[8..16]);
    try testing.expectEqualStrings("data", buffer[36..40]);
    // data_size (u32) == 96000
    try testing.expectEqual(96000, std.mem.readInt(u32, buffer[40..44], .little));
}
