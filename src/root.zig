//! zrei

/// dsp module
pub const dsp = @import("dsp.zig");

/// format module
pub const format = @import("format.zig");

/// render pipeline
pub const render = @import("render.zig");

// explicit imports for every file with specs
test {
    _ = @import("dsp/Oscillator.zig");
    _ = @import("format/wav.zig");
    _ = @import("render.zig");
}
