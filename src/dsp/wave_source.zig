//! wavesource

const dsp = @import("../dsp.zig");
const Oscillator = dsp.Oscillator;
const std = @import("std");

pub const WaveSource = union(enum) {
    single: Single,
    dual: Dual,
    super_saw: SuperSaw,

    pub fn render(self: *WaveSource, buffer: []f32, frequency: f64) void {
        switch (self.*) {
            inline else => |*source| source.render(buffer, frequency),
        }
    }

    pub fn renderSkip(self: *WaveSource, buffer: []const f32, frequency: f64) void {
        switch (self.*) {
            inline else => |*source| source.renderSkip(buffer, frequency),
        }
    }

    pub const Single = @import("wave_source/Single.zig");
    pub const Dual = @import("wave_source/Dual.zig");
    pub const SuperSaw = @import("wave_source/SuperSaw.zig");
};

test "interface invariant" {
    const testing = std.testing;

    const single: WaveSource = .{ .single = .init(44100.0, .triangle) };
    const dual: WaveSource = .{ .dual = .init(44100.0, .square, 10.0) };
    const supersaw: WaveSource = .{ .super_saw = .init(44100.0, 15.0) };

    // exhaustiveness
    const coproduct = @typeInfo(WaveSource).@"union".fields.len;
    var sources: [coproduct]WaveSource = .{ single, dual, supersaw };

    // interface
    var buffer: [1024]f32 = undefined;
    inline for (&sources) |*source| {
        // render: output invariant [-1.0, 1.0]
        source.render(&buffer, 440.0);
        for (buffer) |sample| {
            try testing.expect(sample <= 1.0);
            try testing.expect(sample >= -1.0);
        }
        // renderSkip: callable
        source.renderSkip(&buffer, 440.0);
    }
}
