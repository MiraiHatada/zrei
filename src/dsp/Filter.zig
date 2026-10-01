//! biquad filter (direct form II transposed)
//!
//!             b0
//! x[n] ───┬───►▷──────────►(+)────────────────┬───► y[n]
//!         │                 ▲                 │
//!         │                 │                 │
//!         │               ┌───┐               │
//!         │               │z⁻¹│               │
//!         │               └───┘               │
//!         │   b1            ▲          -a1    │
//!         ├───►▷──────────►(+)◄─────────◁─────┤
//!         │                 ▲                 │
//!         │                 │                 │
//!         │               ┌───┐               │
//!         │               │z⁻¹│               │
//!         │               └───┘               │
//!         │   b2            ▲          -a2    │
//!         └───►▷──────────►(+)◄─────────◁─────┘
//!
//! zenkashiki:
//!        y[n] = b0 * x[n] + s1[n]
//!       s1[0] = s2[0] = 0
//!     s1[n+1] = b1 * x[n] - a1 * y[n] + s2[n]
//!     s2[n+1] = b2 * x[n] - a2 * y[n]
const Filter = @This();

const std = @import("std");
const assert = std.debug.assert;

s1: f32 = 0.0, // upper z⁻¹
s2: f32 = 0.0, // lower z⁻¹

// a0: f32 = always 1.0; because other coefficients are normalized by a0
b0: f32 = 1.0,
b1: f32 = 0.0,
b2: f32 = 0.0,
a1: f32 = 0.0,
a2: f32 = 0.0,

mode: Mode = .bypass,

pub const Mode = enum { bypass, lowpass, highpass, bandpass };

pub const Params = union(Mode) {
    bypass,
    lowpass: Common,
    highpass: Common,
    bandpass: Common,

    const Common = struct {
        cutoff_hz: f64,
        q: f64,
    };
};

/// not in-place version of `configure`.
///
/// 1. `sample_rate` in Hz, assume it to be positive.
/// 2. `params.[!bypass].cutoff_hz` cutoff frequency in Hz, assume it to be positive and lower than the nyquist frequency.
/// 3. `params.[!bypass].q` quality factor (resonance), assume it to be positive. `1/√2` to be flat.
/// 4. invariants of (2.) and (3.) are ignored when given `mode` is `.bypass`
pub fn init(sample_rate: f64, params: Params) Filter {
    var filter: Filter = .{};
    filter.configure(sample_rate, params);
    return filter;
}

/// configure filter coefficients for specified mode and frequency.
///
/// 1. `sample_rate` in Hz, assume it to be positive.
/// 2. `params.[!bypass].cutoff_hz` cutoff frequency in Hz, assume it to be positive and lower than the nyquist frequency.
/// 3. `params.[!bypass].q` quality factor (resonance), assume it to be positive. `1/√2` to be flat.
/// 4. invariants of (2.) and (3.) are ignored when given `mode` is `.bypass`
pub fn configure(self: *Filter, sample_rate: f64, params: Params) void {
    assert(sample_rate > 0.0);
    self.mode = params;
    switch (params) {
        .bypass => {
            self.b0 = 1.0;
            self.b1 = 0.0;
            self.b2 = 0.0;
            self.a1 = 0.0;
            self.a2 = 0.0;
            return;
        },
        .lowpass, .highpass, .bandpass => |common| {
            const cutoff_hz = common.cutoff_hz;
            const q = common.q;

            assert(0.0 < cutoff_hz);
            assert(cutoff_hz < sample_rate * 0.5);
            assert(q > 0.0);

            // actual complex conjugate calculation
            const omega: f64 = (2.0 * std.math.pi * cutoff_hz) / sample_rate;
            const cos_w: f64 = @cos(omega);
            const sin_w: f64 = @sin(omega);
            const alpha: f64 = sin_w / (2.0 * q);

            // we don't "always" need f64 precision because this component has no accumulation
            // use these only while actual calculation
            var b0: f64 = 1.0;
            var b1: f64 = 0.0;
            var b2: f64 = 0.0;
            const a0: f64 = 1.0 + alpha;
            const a1: f64 = -2.0 * cos_w;
            const a2: f64 = 1.0 - alpha;

            switch (params) {
                .bypass => unreachable,
                .lowpass => {
                    b0 = (1.0 - cos_w) * 0.5;
                    b1 = 1.0 - cos_w;
                    b2 = (1.0 - cos_w) * 0.5;
                },
                .highpass => {
                    b0 = (1.0 + cos_w) * 0.5;
                    b1 = -(1.0 + cos_w);
                    b2 = (1.0 + cos_w) * 0.5;
                },
                .bandpass => {
                    b0 = alpha;
                    b1 = 0.0;
                    b2 = -alpha;
                },
            }

            // a0 normalization
            const inv_a0: f64 = 1.0 / a0;
            self.b0 = @floatCast(b0 * inv_a0);
            self.b1 = @floatCast(b1 * inv_a0);
            self.b2 = @floatCast(b2 * inv_a0);
            self.a1 = @floatCast(a1 * inv_a0);
            self.a2 = @floatCast(a2 * inv_a0);
        },
    }
}

/// process a single sample.
///
/// * [important] assume `self.mode` is not `.bypass`, never checked.
inline fn process(self: *Filter, sample_in: f32) f32 {
    // see the module document comment for detail
    const sample_out: f32 = self.b0 * sample_in + self.s1;
    self.s1 = self.b1 * sample_in - self.a1 * sample_out + self.s2;
    self.s2 = self.b2 * sample_in - self.a2 * sample_out;
    return sample_out;
}

/// apply filter to buffer in-place.
pub fn apply(self: *Filter, noalias buffer: []f32) void {
    if (self.mode == .bypass) return;
    for (buffer) |*sample| {
        sample.* = self.process(sample.*);
    }
}

/// reset internal registers to zero.
pub fn reset(self: *Filter) void {
    self.s1 = 0.0;
    self.s2 = 0.0;
}

test "bypass invariance" {
    const testing = std.testing;

    var filter: Filter = .{};
    var buffer: [4]f32 = .{ 0.1, -0.2, 0.5, -0.9 };
    filter.apply(&buffer);
    try testing.expectEqual(0.1, buffer[0]);
    try testing.expectEqual(-0.2, buffer[1]);
    try testing.expectEqual(0.5, buffer[2]);
    try testing.expectEqual(-0.9, buffer[3]);
}

test "pass dc in lowpass and block in highpass and bandpass" {
    const testing = std.testing;

    const dc: f32 = 1.0; // <- ac/dc <- socket (ac) <- power plant

    // lowpass passes dc
    {
        var lpf: Filter = .{};
        lpf.configure(44100.0, .{ .lowpass = .{
            .cutoff_hz = 1000.0,
            .q = (1.0 / @sqrt(2.0)),
        } });
        var out: f32 = 0.0;
        for (0..200) |_| {
            out = lpf.process(dc);
        }
        try testing.expectApproxEqAbs(1.0, out, 1e-4);
    }

    // highpass blocks dc
    {
        var hpf: Filter = .{};
        hpf.configure(44100.0, .{ .highpass = .{
            .cutoff_hz = 1000.0,
            .q = (1.0 / @sqrt(2.0)),
        } });
        var out: f32 = 0.0;
        for (0..200) |_| {
            out = hpf.process(dc);
        }
        try testing.expectApproxEqAbs(0.0, out, 1e-4);
    }

    // bandpass blocks dc
    {
        var bpf: Filter = .{};
        bpf.configure(44100.0, .{ .bandpass = .{
            .cutoff_hz = 1000.0,
            .q = 1.5,
        } });
        var out: f32 = 0.0;
        for (0..200) |_| {
            out = bpf.process(dc);
        }
        try testing.expectApproxEqAbs(0.0, out, 1e-4);
    }
}

test "apply in chunk" {
    const testing = std.testing;

    var f1: Filter = .{};
    var f2: Filter = .{};
    f1.configure(44100.0, .{ .lowpass = .{ .cutoff_hz = 800.0, .q = 2.0 } });
    f2.configure(44100.0, .{ .lowpass = .{ .cutoff_hz = 800.0, .q = 2.0 } });

    var buffer1: [64]f32 = undefined;
    var buffer2: [64]f32 = undefined;
    for (0..64) |i| {
        const val: f32 = @floatCast(@sin(@as(f64, @floatFromInt(i)) * 0.1));
        buffer1[i] = val;
        buffer2[i] = val;
    }

    f1.apply(&buffer1);

    f2.apply(buffer2[0..16]);
    f2.apply(buffer2[16..48]);
    f2.apply(buffer2[48..64]);

    for (0..64) |i| {
        try testing.expectApproxEqAbs(buffer1[i], buffer2[i], 1e-6);
    }
}
