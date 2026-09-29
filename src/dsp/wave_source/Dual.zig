const Dual = @This();

const dsp = @import("../../dsp.zig");
const Oscillator = dsp.Oscillator;

waveform: Oscillator.WaveForm,

pub fn render(self: *Dual, buffer: []f32, frequency: f64) void {
    _ = self;
    _ = buffer;
    _ = frequency;
    @panic("impl");
}

pub fn renderSkip(self: *Dual, buffer: []f32, frequency: f64) void {
    _ = self;
    _ = buffer;
    _ = frequency;
    @panic("impl");
}
