const Single = @This();

const dsp = @import("../../dsp.zig");
const Oscillator = dsp.Oscillator;

oscillator: Oscillator,
waveform: Oscillator.WaveForm,

pub fn render(self: *Single, buffer: []f32, frequency: f64) void {
    self.oscillator.render(buffer, frequency, self.waveform);
}

pub fn renderSkip(self: *Single, buffer: []f32, frequency: f64) void {
    self.oscillator.renderSkip(buffer, frequency);
}
