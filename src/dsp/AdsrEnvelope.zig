//! apply the adsr envelope to sample buffer
const AdsrEnvelope = @This();

const std = @import("std");
const assert = std.debug.assert;

sample_rate: f32,
params: Params,

state: State = .idle,
current_level: f32 = 0.0,
release_step: f32 = 0.0,

/// adsr envelope state
pub const State = enum {
    idle,
    attack,
    decay,
    sustain,
    release,
};

/// adsr envelope parameters
pub const Params = struct {
    attack_sec: f32,
    decay_sec: f32,
    sustain_level: f32,
    release_sec: f32,
};

/// initialize adsr envelope
///
/// * `sample_rate` - sample rate in Hz
/// * `params` - envelope parameters
/// * err `invalid_sustain_level` :  when `params.sustain_level` not in [0.0, 1.0]
pub fn init(sample_rate: f32, params: Params) union(enum) { ok: AdsrEnvelope, invalid_sustain_level } {
    if (params.sustain_level < 0.0 or params.sustain_level > 1.0) {
        return .invalid_sustain_level;
    }
    return .{
        .ok = .{
            .sample_rate = sample_rate,
            .params = params,
        },
    };
}

/// apply envelope to sample buffer, `buffer` is modified in place
///
/// * assumes `buffer` is non-empty
pub fn apply(self: *AdsrEnvelope, buffer: []f32) void {
    var offset: usize = 0;
    while (offset < buffer.len) {
        const consumed = self.consume(buffer[offset..]);
        offset += consumed;
    }
}

/// key press; start attack phase
pub fn trigger(self: *AdsrEnvelope) void {
    self.state = .attack;
    self.release_step = 0.0;
}

/// key release; start release phase if not idle
pub fn release(self: *AdsrEnvelope) void {
    if (self.state != .idle) {
        if (self.params.release_sec <= 0.0 or self.current_level <= 0.0) {
            self.current_level = 0.0;
            self.state = .idle;
        } else {
            // pre calculate release_step to reach 0.0 in release_sec
            self.release_step = self.current_level / (self.params.release_sec * self.sample_rate);
            self.state = .release;
        }
    }
}

fn consume(self: *AdsrEnvelope, buffer: []f32) usize {
    assert(buffer.len > 0);
    return out: switch (self.state) {
        .idle => {
            @memset(buffer, 0.0);
            break :out buffer.len;
        },
        .attack => {
            if (self.params.attack_sec <= 0.0) {
                self.current_level = 1.0;
                // this setting demands immediate max attack, need to consume at least 1 sample
                // buffer[0] *= 1.0; <- max attack is in fact a no-op
                self.state = .decay;
                break :out 1; // consumed 1
            }
            // in order to reach 1.0 in attack_sec
            const attack_step = 1.0 / (self.params.attack_sec * self.sample_rate);
            for (buffer, 1..) |*sample, i| {
                self.current_level += attack_step;
                sample.* *= @min(self.current_level, 1.0);

                if (self.current_level >= 1.0) {
                    self.current_level = 1.0;
                    self.state = .decay;
                    break :out i; // consumed samples
                }
            }
            break :out buffer.len;
        },
        .decay => {
            if (self.params.decay_sec <= 0.0) {
                self.current_level = self.params.sustain_level;
                self.state = .sustain;
                continue :out .sustain;
            }
            // in order to reach sustain_level in decay_sec
            const decay_step = (1.0 - self.params.sustain_level) / (self.params.decay_sec * self.sample_rate);
            for (buffer, 1..) |*sample, i| {
                self.current_level -= decay_step;
                sample.* *= @max(self.current_level, self.params.sustain_level);

                if (self.current_level <= self.params.sustain_level) {
                    self.current_level = self.params.sustain_level;
                    self.state = .sustain;
                    break :out i; // consumed samples
                }
            }
            break :out buffer.len;
        },
        .sustain => {
            for (buffer) |*sample| {
                sample.* *= self.params.sustain_level;
            }
            break :out buffer.len;
        },
        .release => {
            if (self.params.release_sec <= 0.0) {
                self.current_level = 0.0;
                self.state = .idle;
                continue :out .idle;
            }
            assert(self.release_step > 0.0);
            for (buffer, 1..) |*sample, i| {
                self.current_level -= self.release_step;
                sample.* *= @max(self.current_level, 0.0);

                if (self.current_level <= 0.0) {
                    self.current_level = 0.0;
                    self.state = .idle;
                    break :out i; // consumed samples
                }
            }
            break :out buffer.len;
        },
    };
}

test "apply basic cycle" {
    const testing = std.testing;

    var env = AdsrEnvelope.init(10.0, .{
        .attack_sec = 0.2,
        .decay_sec = 0.2,
        .sustain_level = 0.5,
        .release_sec = 0.5,
    }).ok;
    var buffer: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 };
    env.trigger();
    env.apply(&buffer);

    try testing.expectApproxEqAbs(0.5, buffer[0], 1e-6);
    try testing.expectApproxEqAbs(1.0, buffer[1], 1e-6);
    try testing.expectApproxEqAbs(0.75, buffer[2], 1e-6);
    try testing.expectApproxEqAbs(0.5, buffer[3], 1e-6);

    buffer = .{ 1.0, 1.0, 1.0, 1.0 };
    env.release();
    env.apply(&buffer);

    try testing.expectApproxEqAbs(0.4, buffer[0], 1e-6);
    try testing.expectApproxEqAbs(0.3, buffer[1], 1e-6);
    try testing.expectApproxEqAbs(0.2, buffer[2], 1e-6);
    try testing.expectApproxEqAbs(0.1, buffer[3], 1e-6);
}

test "apply in chunks" {
    const testing = std.testing;

    var env1 = AdsrEnvelope.init(10.0, .{
        .attack_sec = 0.2,
        .decay_sec = 0.2,
        .sustain_level = 0.5,
        .release_sec = 0.5,
    }).ok;
    var env2 = env1;

    var first: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 };
    env1.trigger();
    env1.apply(&first);

    var second: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 };
    env2.trigger();
    env2.apply(second[0..1]);
    env2.apply(second[1..3]);
    env2.apply(second[3..4]);

    for (0..4) |i| {
        try testing.expectApproxEqAbs(first[i], second[i], 1e-6);
    }
}

test "apply early release" {
    const testing = std.testing;

    var env = AdsrEnvelope.init(10.0, .{
        .attack_sec = 0.4,
        .decay_sec = 0.2,
        .sustain_level = 0.5,
        .release_sec = 0.2,
    }).ok;

    var buffer: [2]f32 = .{ 1.0, 1.0 };
    env.trigger();
    env.apply(&buffer);
    try testing.expectApproxEqAbs(0.5, buffer[1], 1e-6);

    env.release();
    var release_buffer: [3]f32 = .{ 1.0, 1.0, 1.0 };
    env.apply(&release_buffer);

    try testing.expectApproxEqAbs(0.25, release_buffer[0], 1e-6);
    try testing.expectApproxEqAbs(0.0, release_buffer[1], 1e-6);
    try testing.expectApproxEqAbs(0.0, release_buffer[2], 1e-6);
}

test "apply zero params edge" {
    const testing = std.testing;

    var env = AdsrEnvelope.init(10.0, .{
        .attack_sec = 0.0,
        .decay_sec = 0.0,
        .sustain_level = 0.5,
        .release_sec = 0.0,
    }).ok;

    var buffer: [2]f32 = .{ 1.0, 1.0 };
    env.trigger();
    env.apply(&buffer);
    try testing.expectApproxEqAbs(1.0, buffer[0], 1e-6);
    try testing.expectApproxEqAbs(0.5, buffer[1], 1e-6);

    env.release();
    env.apply(&buffer);
    try testing.expectApproxEqAbs(0.0, buffer[0], 1e-6);

    var percussion = AdsrEnvelope.init(10.0, .{
        .attack_sec = 0.1,
        .decay_sec = 0.1,
        .sustain_level = 0.0,
        .release_sec = 0.2,
    }).ok;
    var percussion_buffer: [3]f32 = .{ 1.0, 1.0, 1.0 };
    percussion.trigger();
    percussion.apply(&percussion_buffer);
    try testing.expectApproxEqAbs(1.0, percussion_buffer[0], 1e-6);
    try testing.expectApproxEqAbs(0.0, percussion_buffer[1], 1e-6);
    try testing.expectApproxEqAbs(0.0, percussion_buffer[2], 1e-6);

    percussion.release();
    var release_sample: [1]f32 = .{1.0};
    percussion.apply(&release_sample);
    try testing.expectApproxEqAbs(0.0, release_sample[0], 1e-6);
}

test "apply idle and long sustain" {
    const testing = std.testing;

    var env = AdsrEnvelope.init(10.0, .{
        .attack_sec = 0.1,
        .decay_sec = 0.1,
        .sustain_level = 0.7,
        .release_sec = 0.1,
    }).ok;

    var idle_buffer: [3]f32 = .{ 0.5, 0.8, -0.3 };
    env.apply(&idle_buffer);
    for (idle_buffer) |sample| try testing.expectApproxEqAbs(0.0, sample, 1e-6);

    env.trigger();
    var attack_buffer: [2]f32 = .{ 1.0, 1.0 };
    env.apply(&attack_buffer);

    var sustain_buffer: [16]f32 = @splat(1.0);
    env.apply(&sustain_buffer);
    for (sustain_buffer) |sample| try testing.expectApproxEqAbs(0.7, sample, 1e-6);
}
