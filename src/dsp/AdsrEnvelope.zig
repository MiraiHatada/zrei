//! apply the adsr envelope to sample buffer
const AdsrEnvelope = @This();

const std = @import("std");
const assert = std.debug.assert;

sample_rate: f64,
params: Params,

state: State = .idle,
current_level: f64 = 0.0,
release_step: f64 = 0.0,

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
    attack_sec: f64,
    decay_sec: f64,
    sustain_level: f64,
    release_sec: f64,
};

/// initialize adsr envelope
///
/// * `sample_rate` - sample rate in Hz
/// * `params` - envelope parameters
/// * err `invalid_sustain_level` :  when `params.sustain_level` not in [0.0, 1.0]
pub fn init(sample_rate: f64, params: Params) union(enum) { ok: AdsrEnvelope, invalid_sustain_level } {
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
                sample.* *= @min(to32(self.current_level), 1.0);

                const tolerance = attack_step * 0.5;
                if (self.current_level >= 1.0 - tolerance) {
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
            const tolerance = decay_step * 0.5;
            for (buffer, 1..) |*sample, i| {
                self.current_level -= decay_step;
                sample.* *= @max(to32(self.current_level), to32(self.params.sustain_level));

                if (self.current_level <= self.params.sustain_level + tolerance) {
                    self.current_level = self.params.sustain_level;
                    self.state = .sustain;
                    break :out i; // consumed samples
                }
            }
            break :out buffer.len;
        },
        .sustain => {
            for (buffer) |*sample| {
                sample.* *= to32(self.params.sustain_level);
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
            const tolerance = self.release_step * 0.5;
            for (buffer, 1..) |*sample, i| {
                self.current_level -= self.release_step;
                sample.* *= @max(to32(self.current_level), 0.0);

                if (self.current_level <= tolerance) {
                    self.current_level = 0.0;
                    self.state = .idle;
                    break :out i; // consumed samples
                }
            }
            break :out buffer.len;
        },
    };
}

inline fn to32(value: f64) f32 {
    return @floatCast(value);
}

test "apply in chunk" {
    const testing = std.testing;

    var env_full = AdsrEnvelope.init(100.0, .{
        .attack_sec = 0.05,
        .decay_sec = 0.05,
        .sustain_level = 0.5,
        .release_sec = 0.05,
    }).ok;
    var env_chunk = env_full;

    var buffer_full: [25]f32 = @splat(1.0);
    var buffer_chunk: [25]f32 = @splat(1.0);

    // apply in one go
    env_full.apply(buffer_full[0..2]);
    env_full.trigger();
    env_full.apply(buffer_full[2..15]);
    env_full.release();
    env_full.apply(buffer_full[15..25]);

    // apply in chunks
    env_chunk.apply(buffer_chunk[0..1]);
    env_chunk.apply(buffer_chunk[1..2]);
    env_chunk.trigger();
    env_chunk.apply(buffer_chunk[2..12]);
    env_chunk.apply(buffer_chunk[12..15]);
    env_chunk.release();
    env_chunk.apply(buffer_chunk[15..16]);
    env_chunk.apply(buffer_chunk[16..20]);
    env_chunk.apply(buffer_chunk[20..25]);

    // are the same
    for (0..25) |i| {
        try testing.expectApproxEqAbs(buffer_full[i], buffer_chunk[i], 1e-6);
    }
    try testing.expectEqual(.idle, env_full.state);
    try testing.expectEqual(.idle, env_chunk.state);
}

test "release from incomplete attack" {
    const testing = std.testing;

    var env = AdsrEnvelope.init(100.0, .{
        .attack_sec = 0.10,
        .decay_sec = 0.05,
        .sustain_level = 0.5,
        .release_sec = 0.05,
    }).ok;

    var buffer: [10]f32 = @splat(1.0);
    env.trigger();
    env.apply(buffer[0..4]);

    try testing.expectApproxEqAbs(0.4, env.current_level, 1e-6);

    env.release();
    env.apply(buffer[4..10]);

    try testing.expectApproxEqAbs(0.32, buffer[4], 1e-6);
    try testing.expectEqual(0.0, buffer[9]);
    try testing.expectEqual(.idle, env.state);
}

test "all zero spec" {
    const testing = std.testing;

    var env = AdsrEnvelope.init(100.0, .{
        .attack_sec = 0.0,
        .decay_sec = 0.0,
        .sustain_level = 0.6,
        .release_sec = 0.0,
    }).ok;

    var buffer: [4]f32 = @splat(1.0);
    env.trigger();
    env.apply(buffer[0..2]);

    try testing.expectApproxEqAbs(1.0, buffer[0], 1e-6);
    try testing.expectApproxEqAbs(0.6, buffer[1], 1e-6);

    env.release();
    env.apply(buffer[2..4]);

    try testing.expectEqual(0.0, buffer[2]);
    try testing.expectEqual(0.0, buffer[3]);
    try testing.expectEqual(.idle, env.state);
}
