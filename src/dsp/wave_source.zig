//! wavesource

const dsp = @import("../dsp.zig");
const Oscillator = dsp.Oscillator;

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
