//! waveform rendering shell
const zrei = @import("root.zig");
const Oscillator = zrei.dsp.Oscillator;
const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

pub const RenderWav = union(enum) { ok, fail: []const u8 };
/// fixme: more specific arguments about sound
pub fn wav(sink: *Io.Writer, sec: u16) Io.Writer.Error!RenderWav {
    const sample_rate: u32 = comptime 48000;
    const fmt: zrei.format.wav.Format = .{
        .bits_per_sample = 16,
        .channels = 1,
        .sample_rate = sample_rate,
    };
    const samples_size = @as(usize, sample_rate) * sec;
    const res = zrei.format.wav.createHeader(fmt, samples_size);
    switch (res) {
        .exceeded_4gb => return .{ .fail = "Riff Wav can't be larger than 4GB" },
        .ok => |bytes| {
            try sink.writeAll(&bytes);
        },
    }

    // we use 2KB (+1KB) stack buffer here, which is way less than ordinary L1 data cache
    // on paper it allows 16+ polyphony without a cache miss but you know life is not that easy
    var buffer: [512]f32 = undefined;
    var buffer_i16_raw: [512 * 2]u8 = undefined;
    var offset: usize = 0;
    var osc: Oscillator = .init(sample_rate);
    while (offset < samples_size) {
        const chunk_size = @min(samples_size - offset, buffer.len);
        const chunk: []f32 = buffer[0..chunk_size];
        osc.render(chunk, 440.0, .square, .vector);
        const data = zrei.format.wav.encodePcm16(&buffer_i16_raw, chunk);
        try sink.writeAll(data);
        offset += chunk_size;
    }
    assert(offset == samples_size);
    return .ok;
}
