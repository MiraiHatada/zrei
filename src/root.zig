//! zrei

/// [core] dsp module
pub const dsp = struct {
    pub const Oscillator = @import("dsp/Oscillator.zig");
};

/// [core] format module
pub const format = struct {
    pub const wav = @import("format/wav.zig");
};

/// [shell] pipeline module
pub const pipeline = struct {
    pub const render = @import("pipeline/render.zig");
};

test {
    _ = @import("dsp/Oscillator.zig");
    _ = @import("format/wav.zig");
    _ = @import("pipeline/render.zig");
}
