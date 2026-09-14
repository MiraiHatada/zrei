//! zrei

/// dsp module
pub const dsp = struct {
    pub const Oscillator = @import("dsp/Oscillator.zig");
};

/// format module
pub const format = struct {
    pub const wav = @import("format/wav.zig");
};

test {
    _ = @import("dsp/Oscillator.zig");
    _ = @import("format/wav.zig");
}
