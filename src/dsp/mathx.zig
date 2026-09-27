//! extended math functions
//!
//! [important]
//! `@sin` falls back to scalar `call sinf` 4 times for vectors in current zig's implementation on llvm21.
//! this module provides an extended sin(x) for vectors, however supposed to be removed once `@sin` gets improved

const std = @import("std");
const assert = std.debug.assert;

pub const VecF32 = @Vector(4, f32);

/// sine for a 4-lane vector with normalized phase in [0, 1) where 1 turn = 2π
/// uses 9th-degree minimax polynomial on quarter-symmetric triangle wave mapping.
pub fn @"sinV[0,1)Normalized"(normalized: VecF32) VecF32 {
    const half: VecF32 = @splat(0.5);
    const one: VecF32 = @splat(1.0);
    const neg_one: VecF32 = @splat(-1.0);
    const three_quarters: VecF32 = @splat(0.75);
    const four: VecF32 = @splat(4.0);

    // black magic to generate sin[-1, 1] from phase of [0, 1)
    const p_shifted = normalized + three_quarters;
    const p = p_shifted - @floor(p_shifted);
    const u = four * @abs(p - half) - one;

    // horner's method application only to odd powers
    // even powers are always zeros .. i suppose
    const c1: VecF32 = @splat(1.5707963);
    const c3: VecF32 = @splat(-0.6459641);
    const c5: VecF32 = @splat(0.0796926);
    const c7: VecF32 = @splat(-0.0046817);
    const c9: VecF32 = @splat(0.0001604);
    const u_sq = u * u;
    var poly = c9;
    poly = c7 + u_sq * poly;
    poly = c5 + u_sq * poly;
    poly = c3 + u_sq * poly;
    poly = c1 + u_sq * poly;
    const val = u * poly;
    return @min(@max(val, neg_one), one);
}

fn tof32(x: usize) f32 {
    return @floatFromInt(x);
}

test "sine common points" {
    const testing = std.testing;
    const phase: VecF32 = .{ 0.0, 0.25, 0.5, 0.75 };

    const res = @"sinV[0,1)Normalized"(phase);
    try testing.expectEqual(0.0, res[0]); // sin 0
    try testing.expectEqual(1.0, res[1]); // sin π/2
    try testing.expectEqual(0.0, res[2]); // sin π
    try testing.expectEqual(-1.0, res[3]); // sin 3π/2
}

test "vectored sine perfect spec" {
    const testing = std.testing;
    const steps: usize = 2000;
    const two_pi: f32 = 2.0 * std.math.pi;
    var i: usize = 0;
    while (i < steps) : (i += 4) {
        const p0 = tof32(i) / tof32(steps);
        const p1 = tof32(i + 1) / tof32(steps);
        const p2 = tof32(i + 2) / tof32(steps);
        const p3 = tof32(i + 3) / tof32(steps);
        const pv: VecF32 = .{ p0, p1, p2, p3 };

        const res = @"sinV[0,1)Normalized"(pv);
        inline for (0..4) |subscript| {
            const p = pv[subscript];
            const expected = @sin(p * two_pi);
            const actual = res[subscript];
            try testing.expectApproxEqAbs(expected, actual, 1e-5);
        }
    }
}
