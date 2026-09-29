const SuperSaw = @This();

const dsp = @import("../../dsp.zig");
const Oscillator = dsp.Oscillator;

pub fn render(self: *SuperSaw, buffer: []f32, frequency: f64) void {
    _ = self;
    _ = buffer;
    _ = frequency;
    @panic("impl");
}

pub fn renderSkip(self: *SuperSaw, buffer: []f32, frequency: f64) void {
    _ = self;
    _ = buffer;
    _ = frequency;
    @panic("impl");
}
