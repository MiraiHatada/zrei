//! wavesource

const dsp = @import("../dsp.zig");
const Oscillator = dsp.Oscillator;
const std = @import("std");

pub const WaveSource = union(enum) {
    single: Single,
    dual: Dual,
    super_saw: SuperSaw,

    pub const Params = union(enum) {
        single: struct { waveform: Oscillator.WaveForm },
        dual: struct { waveform: Oscillator.WaveForm, detune_cents: f64 },
        super_saw: struct { detune_cents: f64 },
    };

    pub fn init(sample_rate: f64, params: Params) WaveSource {
        return switch (params) {
            .single => |s| .{ .single = .init(sample_rate, s.waveform) },
            .dual => |d| .{ .dual = .init(sample_rate, d.waveform, d.detune_cents) },
            .super_saw => |ss| .{ .super_saw = .init(sample_rate, ss.detune_cents) },
        };
    }

    pub fn render(self: *WaveSource, noalias buffer: []f32, frequency: f64) void {
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

    const single: WaveSource = .init(44100.0, .{ .single = .{ .waveform = .triangle } });
    const dual: WaveSource = .init(44100.0, .{ .dual = .{ .waveform = .square, .detune_cents = 10.0 } });
    const supersaw: WaveSource = .init(44100.0, .{ .super_saw = .{ .detune_cents = 15.0 } });

    // exhaustiveness
    const coproduct = @typeInfo(WaveSource).@"union".field_names.len;
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
