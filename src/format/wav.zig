//! RIFF WAV format definition module
const builtin = @import("builtin");
const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

/// defines WAV format
pub const Format = struct {
    channels: u16 = 1,
    sample_rate: u32 = 44100,
    bits_per_sample: u16 = 16,
};

/// information you need to construct RIFF WAV header bytes
pub const Header = struct {
    riff_size: u32,
    format_code: FormatCode,
    channels: u16,
    samples_per_sec: u32,
    average_bytes_per_sec: u32,
    block_align: u16,
    bits_per_sample: u16,
    data_size: u32,

    /// from definition, but p much only use for pcm(0x01)
    pub const FormatCode = enum(u16) {
        pcm = 0x0001,
        ieee_float = 0x0003,
        a_law = 0x0006,
        mu_law = 0x0007,
        extensible = 0xFFFE,
    };

    /// initialize RIFF WAV header struct
    ///
    /// * assert 4GB limit including data
    /// * `format.bits_per_sample` must be divisible by 8
    pub fn init(format: Format, frame_count: usize) Header {
        assert(format.channels > 0);
        assert(format.bits_per_sample % 8 == 0);
        const bytes_per_sample: u16 = format.bits_per_sample / 8;
        const block_align: u16 = format.channels * bytes_per_sample;

        // 4GB assertion
        const max_frames = (std.math.maxInt(u32) - 36) / @as(usize, block_align);
        assert(frame_count <= max_frames);

        const data_size: u32 = @intCast(frame_count * block_align);
        const riff_size: u32 = 36 + data_size; // sizeof(the_wave ... data_size) = 36
        return .{
            .riff_size = riff_size,
            .format_code = .pcm,
            .channels = format.channels,
            .samples_per_sec = format.sample_rate,
            .average_bytes_per_sec = format.sample_rate * block_align,
            .block_align = block_align,
            .bits_per_sample = format.bits_per_sample,
            .data_size = data_size,
        };
    }

    /// write RIFF WAV header bytes in little endian to `sink`
    pub fn write(self: Header, sink: *Io.Writer) Io.Writer.Error!void {
        var bytes: [44]u8 = undefined;

        bytes[0..4].* = "RIFF".*;
        std.mem.writeInt(u32, bytes[4..8], self.riff_size, .little);
        bytes[8..12].* = "WAVE".*;
        bytes[12..16].* = "fmt ".*;
        std.mem.writeInt(u32, bytes[16..20], 16, .little); // fmt_size
        std.mem.writeInt(u16, bytes[20..22], @intFromEnum(self.format_code), .little);
        std.mem.writeInt(u16, bytes[22..24], self.channels, .little);
        std.mem.writeInt(u32, bytes[24..28], self.samples_per_sec, .little);
        std.mem.writeInt(u32, bytes[28..32], self.average_bytes_per_sec, .little);
        std.mem.writeInt(u16, bytes[32..34], self.block_align, .little);
        std.mem.writeInt(u16, bytes[34..36], self.bits_per_sample, .little);
        bytes[36..40].* = "data".*;
        std.mem.writeInt(u32, bytes[40..44], self.data_size, .little);

        try sink.writeAll(&bytes);
    }
};

/// integer 16bit quantization
inline fn quantize16i(sample: f32) i16 {
    if (std.math.isNan(sample)) return 0;
    const i16_max_float: f32 = comptime @floatFromInt(std.math.maxInt(i16));
    const i16_min_float: f32 = comptime @floatFromInt(std.math.minInt(i16));
    // de-normalize phase
    const scaled = sample * i16_max_float;
    // compress beyond maximum and minimum (error values)
    const clamped = std.math.clamp(scaled, i16_min_float, i16_max_float);
    // prefer round to floor
    return @intFromFloat(@round(clamped));
}

/// quantize `samples` into i16 and write it to `sink`
pub fn writePcm16(sink: *Io.Writer, format: Format, samples: []const f32) Io.Writer.Error!void {
    assert(format.channels > 0);
    assert(format.bits_per_sample == 16);
    assert(samples.len % format.channels == 0);
    const header: Header = .init(format, samples.len / format.channels);
    try header.write(sink);

    var chunk_buf: [256]i16 = undefined;
    var offset: usize = 0;
    while (offset < samples.len) {
        const chunk_size = @min(samples.len - offset, chunk_buf.len);
        for (0..chunk_size) |i| {
            chunk_buf[i] = quantize16i(samples[offset + i]);
        }
        // fixme: in future there could be a more idiomatic way from SDL
        if (comptime builtin.cpu.arch.endian() != .little) {
            std.mem.byteSwapAllElements(i16, chunk_buf[0..chunk_size]);
        }
        const bytes: []const u8 = std.mem.sliceAsBytes(chunk_buf[0..chunk_size]);
        try sink.writeAll(bytes);
        offset += chunk_size;
    }
}

test "writePcm16: write 16bit mono wav" {
    const testing = std.testing;
    var buffer: [44 + 6]u8 = undefined;
    var sink: Io.Writer = .fixed(&buffer);

    try writePcm16(&sink, .{}, &.{ 0.0, 1.0, -1.0 });

    // headers
    try testing.expectEqualStrings("RIFF", buffer[0..4]);
    try testing.expectEqualStrings("WAVEfmt ", buffer[8..16]);
    try testing.expectEqualStrings("data", buffer[36..40]);

    // riff_size = 36 + 6 bytes, data_size = 6 bytes
    try testing.expectEqual(42, std.mem.readInt(u32, buffer[4..8], .little));
    try testing.expectEqual(6, std.mem.readInt(u32, buffer[40..44], .little));

    // quantized samples
    try testing.expectEqual(0, std.mem.readInt(i16, buffer[44..46], .little));
    try testing.expectEqual(32767, std.mem.readInt(i16, buffer[46..48], .little));
    try testing.expectEqual(-32767, std.mem.readInt(i16, buffer[48..50], .little));
}
