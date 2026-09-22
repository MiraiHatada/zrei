//! musical note table
//! we are not using full comptime table generation for this
//! , because table has only 128 floatpoints and remain 1KB (fits in L1)
//! , and table is whether "initialized only once" or "drastically changing" as nature
//! , that convinces having the table runtime.
const std = @import("std");
const assert = std.debug.assert;

/// most common A4 frequency in Hz
pub const a4hz_default: f64 = 440.0;

/// musical note number (midi)
pub const Note = enum(u7) {
    C3 = 48,
    Cs3 = 49,
    D3 = 50,
    Ds3 = 51,
    E3 = 52,
    F3 = 53,
    Fs3 = 54,
    G3 = 55,
    Gs3 = 56,
    A3 = 57,
    As3 = 58,
    B3 = 59,

    C4 = 60,
    Cs4 = 61,
    D4 = 62,
    Ds4 = 63,
    E4 = 64,
    F4 = 65,
    Fs4 = 66,
    G4 = 67,
    Gs4 = 68,
    A4 = 69,
    As4 = 70,
    B4 = 71,

    C5 = 72,
    Cs5 = 73,
    D5 = 74,
    Ds5 = 75,
    E5 = 76,
    F5 = 77,
    Fs5 = 78,
    G5 = 79,
    Gs5 = 80,
    A5 = 81,
    As5 = 82,
    B5 = 83,

    _,

    pub inline fn toInt(self: Note) u7 {
        return @intFromEnum(self);
    }

    pub inline fn fromInt(value: u7) Note {
        return @enumFromInt(value);
    }
};

/// musical tuning system
pub const Tuning = struct {
    /// pitch table, 1024 bytes, aiming it to be on L1
    table: [128]f64,
    /// tuning system to use, equal temperament or just intonation
    system: System,
    /// the A4 frequency in Hz
    a4hz: f64,
    /// the tonic note for just intonation
    tonic: Note,

    /// tuning system
    pub const System = enum { equal, just };

    /// just intonation definition
    const just_ratios: [12]f64 = .{
        1.0, // T (1/1)
        16.0 / 15.0, // m2 (16/15)
        9.0 / 8.0, // M2, greater tone (9/8)
        6.0 / 5.0, // m3 (6/5)
        5.0 / 4.0, // M3 (5/4)
        4.0 / 3.0, // P4 (4/3)
        45.0 / 32.0, // dim5/aug4, the tritone (45/32)
        3.0 / 2.0, // P5, perfect fifth (3/2)
        8.0 / 5.0, // m6 (8/5)
        5.0 / 3.0, // M6 (5/3)
        9.0 / 5.0, // m7, seventh note (9/5)
        15.0 / 8.0, // M7, leading note (15/8)
    };

    /// initialize pitch table with given A4 frequency and system
    pub fn init(a4hz: f64, comptime system: System) Tuning {
        var self: Tuning = undefined;
        self.inplace(a4hz, system);
        return self;
    }

    /// initialize pitch table with given A4 frequency and system (inplace)
    pub fn inplace(self: *Tuning, a4hz: f64, comptime system: System) void {
        self.a4hz = a4hz;
        self.system = system;
        self.tonic = .C4;
        switch (system) {
            .equal => {
                for (0..128) |i| {
                    const semitone_steps = @as(f64, @floatFromInt(i)) - 69.00;
                    self.table[i] = a4hz * std.math.pow(f64, 2.0, semitone_steps / 12.0);
                }
            },
            .just => {
                calculateJustTable(&self.table, self.a4hz, self.tonic);
            },
        }
    }

    /// set the tonic note for just intonation and recalculate the pitch table
    ///
    /// * assume `self.system` is just intonation
    pub fn setTonic(self: *Tuning, note: Note) void {
        assert(self.system == .just);
        self.tonic = note;
        calculateJustTable(&self.table, self.a4hz, note);
    }

    /// note frequency in Hz
    pub inline fn hzOfNote(self: Tuning, note: Note) f64 {
        return self.table[@intFromEnum(note)];
    }

    /// frequency of a note number (midi) in Hz
    pub inline fn hzOfNoteNumber(self: Tuning, note_number: u7) f64 {
        return self.table[note_number];
    }

    fn calculateJustTable(table: *[128]f64, a4hz: f64, tonic: Note) void {
        // determine tonic frequency from equal temperament
        const tonic_step = tonic.toInt();
        const tonic_semitone_steps = @as(f64, @floatFromInt(tonic_step)) - 69.0;
        const tonic_hz = a4hz * std.math.pow(f64, 2.0, tonic_semitone_steps / 12.0);

        for (0..128) |i| {
            const diff: i32 = @as(i32, @intCast(i)) - @as(i32, @intCast(tonic_step));
            const oct: i32 = @divFloor(diff, 12);
            const semi: usize = @intCast(@mod(diff, 12));
            const ratio = just_ratios[semi];
            const oct_scale = std.math.pow(f64, 2.0, @as(f64, @floatFromInt(oct)));
            table[i] = tonic_hz * ratio * oct_scale;
        }
    }
};

test "Tuning: equal temperament a4 c4" {
    const testing = std.testing;

    const tuning: Tuning = .init(440.0, .equal);
    try testing.expectApproxEqAbs(440.0, tuning.hzOfNote(.A4), 1e-6);
    // C4 = 440 * 2^(-9/12) ≒ 261.625565
    try testing.expectApproxEqAbs(261.625565, tuning.hzOfNote(.C4), 1e-6);
    try testing.expectEqual(tuning.hzOfNote(.A4), tuning.hzOfNoteNumber(69));
}

test "Tuning: just intonation C major chord" {
    const testing = std.testing;

    const tuning: Tuning = .init(440.0, .just);
    const c3 = tuning.hzOfNote(.C3);
    const c4 = tuning.hzOfNote(.C4);
    const e4 = tuning.hzOfNote(.E4);
    const g4 = tuning.hzOfNote(.G4);
    const c5 = tuning.hzOfNote(.C5);

    // M3: 5/4 = 1.25 exactly
    try testing.expectApproxEqAbs(c4 * 1.25, e4, 1e-6);
    // P5: 3/2 = 1.5 exactly
    try testing.expectApproxEqAbs(c4 * 1.5, g4, 1e-6);
    // octave: 2/1
    try testing.expectApproxEqAbs(c4 * 2.0, c5, 1e-6);
    // bass: 1/2
    try testing.expectApproxEqAbs(c4 * 0.5, c3, 1e-6);
}

test "Tuning: switch tonic in just intonation" {
    const testing = std.testing;

    var tuning: Tuning = .init(440.0, .just);

    // C major
    const c4 = tuning.hzOfNote(.C4);
    const e4 = tuning.hzOfNote(.E4);
    const g4_on_c = tuning.hzOfNote(.G4);

    // in C major chord, E4 is M3 (5/4) and G4 is P5 (3/2)
    try testing.expectApproxEqAbs(c4 * 1.25, e4, 1e-6);
    try testing.expectApproxEqAbs(c4 * 1.5, g4_on_c, 1e-6);

    tuning.setTonic(.G4);

    // G major
    const g4_on_g = tuning.hzOfNote(.G4);
    const b4 = tuning.hzOfNote(.B4);
    const d5 = tuning.hzOfNote(.D5);

    // after changing tonic to G4, B4 is M3 (5/4) and D5 is P5 (3/2)
    try testing.expectApproxEqAbs(g4_on_g * 1.25, b4, 1e-6);
    try testing.expectApproxEqAbs(g4_on_g * 1.5, d5, 1e-6);
}

test "Tuning: all 128 frequencies valid and increasing" {
    const testing = std.testing;

    const eq: Tuning = .init(440.0, .equal);
    const ji: Tuning = .init(440.0, .just);

    try testing.expect(eq.hzOfNoteNumber(0) > 0.0);
    try testing.expect(ji.hzOfNoteNumber(0) > 0.0);

    for (1..128) |i| {
        const current: u7 = @intCast(i);
        const previous: u7 = @intCast(i - 1);

        const hz_eq = eq.hzOfNoteNumber(current);
        const hz_ji = ji.hzOfNoteNumber(current);

        try testing.expect(hz_eq > eq.hzOfNoteNumber(previous));
        try testing.expect(hz_ji > ji.hzOfNoteNumber(previous));
    }
}
