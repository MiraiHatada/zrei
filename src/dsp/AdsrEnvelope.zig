//! apply the adsr envelope to sample buffer
const AdsrEnvelope = @This();

const std = @import("std");
const assert = std.debug.assert;

sample_rate: f64,
params: Params,

state: State = .idle,
current_level: f64 = 0.0,

// curve parameters
factor: f64 = 0.0,
bias: f64 = 0.0,

/// phase change on `samples_left` == 0
samples_left: usize = 0,

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
/// * assume `params.sustain_level` within [0.0, 1.0]
pub fn init(sample_rate: f64, params: Params) AdsrEnvelope {
    assert(0.0 <= params.sustain_level and params.sustain_level <= 1.0);
    return .{
        .sample_rate = sample_rate,
        .params = params,
    };
}

/// apply envelope to sample buffer, `buffer` is modified in place
///
/// * assume `buffer` is non-empty
pub fn apply(self: *AdsrEnvelope, buffer: []f32) void {
    assert(buffer.len > 0);
    var offset: usize = 0;
    while (offset < buffer.len) {
        const consumed = self.consume(buffer[offset..]);
        offset += consumed;
    }
}

/// key press; start attack phase
pub fn trigger(self: *AdsrEnvelope) void {
    if (self.current_level >= 1.0) {
        self.current_level = 1.0;
        self.decay();
        return;
    }

    const total_samples = self.secs2samples(self.params.attack_sec);
    if (total_samples == 0) {
        // immediate max attack: at least 1 sample at level 1.0
        self.state = .attack;
        self.current_level = 1.0;
        self.samples_left = 1; // 1 sample
        self.factor = 1.0;
        self.bias = 0.0;
        return;
    }

    self.state = .attack;
    self.samples_left = total_samples;

    // target level is 1.3 for rapid voltage rise in attack phase
    const target = 1.3;
    self.calculateCurve(self.current_level, 1.0, target, total_samples);
}

/// start decay phase
fn decay(self: *AdsrEnvelope) void {
    const total_samples = self.secs2samples(self.params.decay_sec);
    if (total_samples == 0 or self.current_level <= self.params.sustain_level) {
        self.current_level = self.params.sustain_level;
        self.state = .sustain;
        return;
    }

    self.state = .decay;
    self.samples_left = total_samples;

    // target level is beyond actual target by `-Δlevel / 100`
    // because the curve is exponental
    //
    // note: (end - target) / (start - target) here is mathematically constant (1/101)
    const span = self.current_level - self.params.sustain_level;
    const target = self.params.sustain_level - (0.01 * span);
    self.calculateCurve(self.current_level, self.params.sustain_level, target, total_samples);
}

/// key release; start release phase if not idle,
/// idempotent.
pub fn release(self: *AdsrEnvelope) void {
    if (self.state == .idle or self.state == .release) return;

    const total_samples = self.secs2samples(self.params.release_sec);
    if (total_samples == 0 or self.current_level <= 0.0) {
        self.current_level = 0.0;
        self.state = .idle;
        return;
    }

    self.state = .release;
    self.samples_left = total_samples;

    // target level is beyond actual target by `-Δlevel / 100`
    const target = -0.01 * self.current_level;
    self.calculateCurve(self.current_level, 0.0, target, total_samples);
}

/// update infinite impulse response
///
/// * assume `samples` is larger than zero
fn calculateCurve(self: *AdsrEnvelope, start: f64, end: f64, target: f64, samples: usize) void {
    assert(samples > 0);
    const ratio = (end - target) / (start - target);
    const factor = std.math.pow(f64, ratio, 1.0 / @as(f64, @floatFromInt(samples)));
    self.factor = factor;
    self.bias = (1.0 - factor) * target;
}

inline fn nextLevelWithCurve(self: AdsrEnvelope) f64 {
    return (self.current_level * self.factor) + self.bias;
}

fn secs2samples(self: AdsrEnvelope, seconds: f64) usize {
    if (seconds <= 0.0) return 0;
    return @intFromFloat(@round(seconds * self.sample_rate));
}

fn consume(self: *AdsrEnvelope, buffer: []f32) usize {
    assert(buffer.len > 0);
    switch (self.state) {
        .idle => {
            @memset(buffer, 0.0);
            return buffer.len;
        },
        .attack => {
            const count = @min(buffer.len, self.samples_left);
            for (buffer[0..count]) |*sample| {
                self.current_level = self.nextLevelWithCurve();
                sample.* *= @floatCast(@min(self.current_level, 1.0));
            }
            self.samples_left -= count;
            if (self.samples_left == 0) {
                self.current_level = 1.0;
                self.decay();
            }
            return count;
        },
        .decay => {
            const count = @min(buffer.len, self.samples_left);
            for (buffer[0..count]) |*sample| {
                self.current_level = self.nextLevelWithCurve();
                sample.* *= @floatCast(@max(self.current_level, self.params.sustain_level));
            }
            self.samples_left -= count;
            if (self.samples_left == 0) {
                self.current_level = self.params.sustain_level;
                self.state = .sustain;
            }
            return count;
        },
        .sustain => {
            const sustain_level: f32 = @floatCast(self.params.sustain_level);
            for (buffer) |*sample| {
                sample.* *= sustain_level;
            }
            return buffer.len;
        },
        .release => {
            const count = @min(buffer.len, self.samples_left);
            for (buffer[0..count]) |*sample| {
                self.current_level = self.nextLevelWithCurve();
                sample.* *= @floatCast(@max(self.current_level, 0.0));
            }
            self.samples_left -= count;
            if (self.samples_left == 0) {
                self.current_level = 0.0;
                self.state = .idle;
            }
            return count;
        },
    }
}

test "apply in chunk" {
    const testing = std.testing;

    var env_full: AdsrEnvelope = .init(100.0, .{
        .attack_sec = 0.05,
        .decay_sec = 0.05,
        .sustain_level = 0.5,
        .release_sec = 0.05,
    });
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

    for (0..25) |i| {
        try testing.expectApproxEqAbs(buffer_full[i], buffer_chunk[i], 1e-6);
    }
    try testing.expectEqual(.idle, env_full.state);
    try testing.expectEqual(.idle, env_chunk.state);
}

test "release from incomplete attack" {
    const testing = std.testing;

    var env: AdsrEnvelope = .init(100.0, .{
        .attack_sec = 0.10,
        .decay_sec = 0.05,
        .sustain_level = 0.5,
        .release_sec = 0.05,
    });

    var buffer: [10]f32 = @splat(1.0);
    env.trigger();
    env.apply(buffer[0..4]);

    try testing.expect(0.0 < env.current_level and env.current_level < 1.0);

    env.release();
    env.apply(buffer[4..10]);

    try testing.expectEqual(0.0, buffer[9]);
    try testing.expectEqual(.idle, env.state);
}

test "all zero spec" {
    const testing = std.testing;

    var env: AdsrEnvelope = .init(100.0, .{
        .attack_sec = 0.0,
        .decay_sec = 0.0,
        .sustain_level = 0.6,
        .release_sec = 0.0,
    });

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
