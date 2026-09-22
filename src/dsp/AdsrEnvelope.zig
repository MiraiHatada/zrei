//! apply the adsr envelope to sample buffer
const AdsrEnvelope = @This();

const std = @import("std");
const assert = std.debug.assert;

sample_rate: f32,
params: Params,

state: State = .idle,
current_level: f32 = 0.0,
level_on_release: ?f32 = null,

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
pub fn init(sample_rate: f32, params: Params) AdsrEnvelope {
    return .{
        .sample_rate = sample_rate,
        .params = params,
    };
}

/// apply envelope to sample buffer, step for each sample,
/// buffer is modified in place
///
/// * the machine steps forward `buffer.len` times
pub fn apply(self: *AdsrEnvelope, buffer: []f32) void {
    for (buffer) |*sample| {
        sample.* *= self.next();
    }
}

/// key press; start attack phase
pub fn onKeyPress(self: *AdsrEnvelope) void {
    self.state = .attack;
    self.level_on_release = null;
}

/// key release; start release phase if not idle
pub fn onKeyRelease(self: *AdsrEnvelope) void {
    if (self.state != .idle) {
        self.level_on_release = self.current_level;
        self.state = .release;
    }
}

/// step envelope and return current level
fn next(self: *AdsrEnvelope) f32 {
    switch (self.state) {
        .idle => {
            self.current_level = 0.0;
        },
        .attack => {
            if (self.params.attack_sec <= 0.0) {
                self.current_level = 1.0;
                self.state = .decay;
            } else {
                // in order to reach 1.0 in attack_sec
                const step = 1.0 / (self.params.attack_sec * self.sample_rate);
                self.current_level += step;

                if (self.current_level >= 1.0) {
                    self.current_level = 1.0;
                    self.state = .decay;
                }
            }
        },
        .decay => {
            if (self.params.decay_sec <= 0.0) {
                self.current_level = self.params.sustain_level;
                self.state = .sustain;
            } else {
                // in order to reach sustain_level in decay_sec
                const step = (1.0 - self.params.sustain_level) / (self.params.decay_sec * self.sample_rate);
                self.current_level -= step;

                if (self.current_level <= self.params.sustain_level) {
                    self.current_level = self.params.sustain_level;
                    self.state = .sustain;
                }
            }
        },
        .sustain => {
            // keep sustain level
            self.current_level = self.params.sustain_level;
        },
        .release => {
            assert(self.level_on_release != null);
            const base_level = self.level_on_release.?;

            if (self.params.release_sec <= 0.0) {
                self.current_level = 0.0;
                self.level_on_release = null;
                self.state = .idle;
            } else {
                // in order to reach 0.0 in release_sec
                const step = base_level / (self.params.release_sec * self.sample_rate);
                self.current_level -= step;

                if (self.current_level <= 0.0) {
                    self.current_level = 0.0;
                    self.level_on_release = null;
                    self.state = .idle;
                }
            }
        },
    }

    return self.current_level;
}

test apply {
    const testing = std.testing;

    var env: AdsrEnvelope = .init(10.0, .{
        .attack_sec = 0.2,
        .decay_sec = 0.2,
        .sustain_level = 0.5,
        .release_sec = 0.5,
    });
    var buffer: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 };
    env.onKeyPress();
    env.apply(&buffer);

    try testing.expectApproxEqAbs(0.5, buffer[0], 1e-6);
    try testing.expectApproxEqAbs(1.0, buffer[1], 1e-6);
    try testing.expectApproxEqAbs(0.75, buffer[2], 1e-6);
    try testing.expectApproxEqAbs(0.5, buffer[3], 1e-6);

    buffer = .{ 1.0, 1.0, 1.0, 1.0 };
    env.onKeyRelease();
    env.apply(&buffer);

    try testing.expectApproxEqAbs(0.4, buffer[0], 1e-6);
    try testing.expectApproxEqAbs(0.3, buffer[1], 1e-6);
    try testing.expectApproxEqAbs(0.2, buffer[2], 1e-6);
    try testing.expectApproxEqAbs(0.1, buffer[3], 1e-6);
}
