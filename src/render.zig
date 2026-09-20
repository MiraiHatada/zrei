//! waveform rendering pipeline
const format = @import("format.zig");
const dsp = @import("dsp.zig");
const Oscillator = dsp.Oscillator;
const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

pub const RenderWav = enum { ok, exceeded_4gb };
/// fixme: more specific arguments about sound
pub fn wav(sink: *Io.Writer, sec: u16) Io.Writer.Error!RenderWav {
    const sample_rate: u32 = comptime 48000;
    const fmt: format.wav.Format = .{
        .bits_per_sample = 16,
        .channels = 1,
        .sample_rate = sample_rate,
    };
    const samples_size = @as(usize, sample_rate) * sec;
    const res = format.wav.createHeader(fmt, samples_size);
    switch (res) {
        .exceeded_4gb => return .exceeded_4gb,
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
        const data = format.wav.encodePcm16(&buffer_i16_raw, chunk);
        try sink.writeAll(data);
        offset += chunk_size;
    }
    assert(offset == samples_size);
    return .ok;
}

test wav {
    const testing = std.testing;
    // 48000 * 2 = 96000
    var buffer: [44 + 96000]u8 = undefined;
    var sink = Io.Writer.fixed(&buffer);

    const res = try wav(&sink, 1);
    try testing.expectEqual(.ok, res);

    try testing.expectEqualStrings("RIFF", buffer[0..4]);
    try testing.expectEqualStrings("WAVEfmt ", buffer[8..16]);
    try testing.expectEqualStrings("data", buffer[36..40]);
    // data_size (u32) == 96000
    try testing.expectEqual(96000, std.mem.readInt(u32, buffer[40..44], .little));
}
