const zrei = @import("zrei");
const Oscillator = zrei.dsp.Oscillator;
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.service);
const assert = std.debug.assert;

pub fn encode(sink: *Io.Writer, sec: u16) Io.Writer.Error!void {
    const sample_rate: u32 = comptime 48000;
    const fmt: zrei.format.wav.Format = .{
        .bits_per_sample = 16,
        .channels = 1,
        .sample_rate = sample_rate,
    };
    const samples_size = @as(usize, sample_rate) * sec;
    try zrei.format.wav.writeHeader(sink, fmt, samples_size);

    // we use 2KB stack buffer here, which is way less than ordinary L1 data cache
    // on paper it allows 16+ polyphony without a cache miss but you know life is not that easy
    var buffer: [512]f32 = undefined;
    var offset: usize = 0;
    var osc: Oscillator = .init(sample_rate);
    while (offset < samples_size) {
        const chunk_size = @min(samples_size - offset, buffer.len);
        const chunk: []f32 = buffer[0..chunk_size];
        osc.render(chunk, 440.0);
        try zrei.format.wav.writePcm16(sink, chunk);
        offset += chunk_size;
    }
    assert(offset == samples_size);
}
