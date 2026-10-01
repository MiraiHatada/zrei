//! musical note for sequencer
const Note = @This();

const dsp = @import("../dsp.zig");
const Letter = dsp.pitch.Letter;
const std = @import("std");
const assert = std.debug.assert;

/// note name or null as rest
pitch: ?Letter,
/// 1.0 for quarter note, 0.5 for eighth note, etc.
duration: f64,
/// note length in (0, 1], 1.0 for tenuto, 0.5 for staccato, etc.
gate: f64 = 0.8,

/// initialize a note
///
/// * assume `duration` is larger than zero
/// * assume 0.0 < `gate` ≤ 1.0
pub fn init(pitch: ?Letter, duration: f64, gate: f64) Note {
    assert(duration > 0.0);
    assert(0.0 < gate);
    assert(gate <= 1.0);
    return .{
        .pitch = pitch,
        .duration = duration,
        .gate = gate,
    };
}

test "basic note" {
    const testing = std.testing;

    const note: Note = .init(.C4, 1.0, 0.8);
    try testing.expectEqual(.C4, note.pitch.?);
    try testing.expectEqual(1.0, note.duration);
    try testing.expectEqual(0.8, note.gate);
}

test "rest note" {
    const testing = std.testing;

    const rest: Note = .init(null, 0.5, 1.0);
    try testing.expectEqual(@as(?Letter, null), rest.pitch);
    try testing.expectEqual(0.5, rest.duration);
    try testing.expectEqual(1.0, rest.gate);
}
