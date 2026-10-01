//! monophonic sequencer
const Sequencer = @This();

const dsp = @import("../dsp.zig");
const Note = dsp.Note;
const Voice = dsp.Voice;
const Letter = dsp.pitch.Letter;
const Tuning = dsp.pitch.Tuning;
const std = @import("std");
const assert = std.debug.assert;

/// sequencer state machine
pub const State = enum {
    ready,
    pressing,
    release,
    tail,
    complete,
};
state: State = .ready,

/// sequence of notes to play
notes: []const Note,
/// cursor of `notes`
note_index: usize = 0,

sample_rate: f64,
bpm: f64,
samples_per_beat: f64,

// components
tuning: Tuning,
voice: Voice,

/// musical cursor in beats
beat: f64 = 0.0,
/// musical cursor in samples
current_sample: usize = 0,
// points to where the current note starts, gates off, and ends
note_start_sample: usize = 0,
note_off_sample: usize = 0,
note_end_sample: usize = 0,

/// initialize sequencer
///
/// * assume `sample_rate` is larger than zero
/// * assume `bpm` is larger than zero
pub fn init(sample_rate: f64, bpm: f64, tuning: Tuning, voice: Voice, notes: []const Note) Sequencer {
    assert(sample_rate > 0.0);
    assert(bpm > 0.0);

    return .{
        .notes = notes,
        .sample_rate = sample_rate,
        .bpm = bpm,
        .samples_per_beat = (60.0 / bpm) * sample_rate,
        .tuning = tuning,
        .voice = voice,
        .state = if (notes.len == 0) .complete else .ready,
    };
}

/// if sequencer has finished playing all notes and release tail
pub fn finished(self: Sequencer) bool {
    return self.state == .complete;
}

/// load next note to machine, assume `self.note_index` is in range of `self.notes`
fn load(self: *Sequencer) void {
    assert(self.note_index < self.notes.len);
    const note = self.notes[self.note_index];
    self.note_start_sample = self.current_sample;

    const next_beat: f64 = self.beat + note.duration;
    const next_sample: usize = @intFromFloat(@round(next_beat * self.samples_per_beat));
    assert(next_sample >= self.note_start_sample);

    const note_samples: usize = next_sample - self.note_start_sample;
    const note_samples_float: f64 = @floatFromInt(note_samples);
    const gate_samples: usize = @min(@as(usize, @round(note_samples_float * note.gate)), note_samples);

    // update note timing and beat cursor
    self.note_off_sample = self.note_start_sample + gate_samples;
    self.note_end_sample = next_sample;
    self.beat = next_beat;

    // update state
    if (note.pitch) |letter| {
        const hz = self.tuning.hzOfNoteLetter(letter);
        self.voice.noteOn(hz);
        self.state = .pressing;
    } else {
        // rest
        self.state = .release;
    }
}

/// advance to next note, or transition to tail state if no more notes
fn advance(self: *Sequencer) void {
    self.note_index += 1;
    if (self.note_index < self.notes.len) {
        self.load();
    } else {
        self.state = .tail;
    }
}

/// render melody into `buffer`
///
/// * assume `buffer` is non-empty
pub fn render(self: *Sequencer, buffer: []f32) void {
    assert(buffer.len > 0);
    var offset: usize = 0;

    while (offset < buffer.len) {
        switch (self.state) {
            .ready => {
                if (self.notes.len == 0) {
                    self.state = .complete;
                } else {
                    self.load();
                }
            },
            .pressing => {
                // until note_off_sample
                const samples_left = self.note_off_sample - self.current_sample;
                const chunk_size = @min(buffer.len - offset, samples_left);
                if (chunk_size > 0) {
                    const chunk = buffer[offset .. offset + chunk_size];
                    self.voice.render(chunk);
                    offset += chunk_size;
                    self.current_sample += chunk_size;
                }

                if (self.current_sample >= self.note_off_sample) {
                    self.voice.noteOff();
                    self.state = .release;
                }
            },
            .release => {
                // until note_end_sample
                const samples_left = self.note_end_sample - self.current_sample;
                const chunk_size = @min(buffer.len - offset, samples_left);
                if (chunk_size > 0) {
                    const chunk = buffer[offset .. offset + chunk_size];
                    self.voice.render(chunk);
                    offset += chunk_size;
                    self.current_sample += chunk_size;
                }

                if (self.current_sample >= self.note_end_sample) {
                    self.advance();
                }
            },
            .tail => {
                // drain remaining (until voice is inactive)
                if (!self.voice.active()) {
                    self.state = .complete;
                    continue;
                }
                const chunk = buffer[offset..];
                self.voice.render(chunk);
                self.current_sample += chunk.len;
                offset += chunk.len;
                if (!self.voice.active()) self.state = .complete;
            },
            .complete => {
                // end state
                const remaining = buffer[offset..];
                @memset(remaining, 0.0);
                self.current_sample += remaining.len;
                return;
            },
        }
    }
}

test "render single note" {
    const testing = std.testing;

    const params: Voice.Params = .{
        .source = .{ .single = .{ .waveform = .sine } },
        .filter = .{ .mode = .bypass, .cutoff_hz = 100.0, .q = 0.7071 },
        .envelope = .{
            .attack_sec = 0.01,
            .decay_sec = 0.01,
            .sustain_level = 0.5,
            .release_sec = 0.02,
        },
    };
    const voice: Voice = .init(1000.0, params);
    const tuning: Tuning = .init(440.0, .equal);

    // 1000Hz, BPM 120 -> 1 beat = 500 samples (400 pressing, 100 release)
    const notes: [1]Note = .{
        .{ .pitch = .A4, .duration = 1.0, .gate = 0.8 },
    };
    var seq: Sequencer = .init(1000.0, 120.0, tuning, voice, &notes);
    try testing.expectEqual(.ready, seq.state);

    var buffer: [200]f32 = undefined;

    // 0..200 (ready -> pressing)
    seq.render(&buffer);
    try testing.expectEqual(.pressing, seq.state);
    try testing.expectEqual(200, seq.current_sample);

    // 200..400 (pressing -> release)
    seq.render(&buffer);
    try testing.expectEqual(400, seq.current_sample);
    try testing.expectEqual(.release, seq.state);

    // 400..600 (release -> complete)
    seq.render(&buffer);
    try testing.expectEqual(600, seq.current_sample);
    try testing.expectEqual(.complete, seq.state);
    try testing.expectEqual(true, seq.finished());
}

test "render in chunk, super facade" {
    const testing = std.testing;

    const params: Voice.Params = .{
        .source = .{ .single = .{ .waveform = .saw } },
        .filter = .{ .mode = .bypass, .cutoff_hz = 100.0, .q = 0.7071 },
        .envelope = .{
            .attack_sec = 0.02,
            .decay_sec = 0.02,
            .sustain_level = 0.6,
            .release_sec = 0.02,
        },
    };
    const voice: Voice = .init(1000.0, params);
    const tuning: Tuning = .init(440.0, .equal);
    const notes: [3]Note = .{
        .{ .pitch = .C4, .duration = 0.5, .gate = 0.8 },
        .{ .pitch = null, .duration = 0.25, .gate = 1.0 },
        .{ .pitch = .E4, .duration = 0.75, .gate = 0.8 },
    };
    var seq1: Sequencer = .init(1000.0, 120.0, tuning, voice, &notes);
    var seq2: Sequencer = .init(1000.0, 120.0, tuning, voice, &notes);

    var first: [800]f32 = undefined;
    seq1.render(&first);

    var second: [800]f32 = undefined;
    seq2.render(second[0..64]);
    seq2.render(second[64..197]);
    seq2.render(second[197..512]);
    seq2.render(second[512..800]);

    for (0..800) |i| {
        try testing.expectApproxEqAbs(first[i], second[i], 1e-6);
    }
}

test "real life spec" {
    const testing = std.testing;

    const params: Voice.Params = .{
        .source = .{ .single = .{ .waveform = .sine } },
        .filter = .{ .mode = .bypass, .cutoff_hz = 100.0, .q = 0.7071 },
        .envelope = .{
            .attack_sec = 0.001,
            .decay_sec = 0.001,
            .sustain_level = 0.5,
            .release_sec = 0.001,
        },
    };
    const voice: Voice = .init(48000.0, params);
    const tuning: Tuning = .init(440.0, .equal);

    const note_single: Note = .{ .pitch = .C4, .duration = 0.25, .gate = 0.8 };
    var notes: [100]Note = undefined;
    @memset(&notes, note_single);

    var seq: Sequencer = .init(48000.0, 130.0, tuning, voice, &notes);

    var buffer: [512]f32 = undefined;
    while (!seq.finished()) {
        seq.render(&buffer);
    }

    // 0.25 beat 100 notes = 25 beats
    // 130 BPM = 130/60 beat per sec = 60/130 sec per beat = 60 / 130 * 48000 samples per beat
    const ideal_total_samples: usize = @intFromFloat(@round(25.0 * (60.0 / 130.0) * 48000.0));
    try testing.expectEqual(ideal_total_samples, seq.note_end_sample);
    try testing.expectEqual(.complete, seq.state);
}
