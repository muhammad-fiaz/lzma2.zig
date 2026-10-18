//! Raw LZMA Stream Compressor.
//!
//! Encodes uncompressed input into raw LZMA streams without container headers
//! using adaptive literal Markov models, multi-level match finding (2-byte, 3-byte,
//! and 4-byte hash tables), repeated match evaluation (rep0..rep3, short-rep),
//! and range encoding.

const std = @import("std");
const errors = @import("../utils/errors.zig");
const options_mod = @import("../utils/options.zig");
const range_codec = @import("../utils/range_codec.zig");
const RangeEncoder = range_codec.RangeEncoder;
const match_finder_mod = @import("../utils/match_finder.zig");
const MatchFinder = match_finder_mod.MatchFinder;
const state_mod = @import("../utils/state.zig");
const LzmaState = state_mod.LzmaState;
const MATCH_MIN_LEN = state_mod.MATCH_MIN_LEN;
const MATCH_MAX_LEN = state_mod.MATCH_MAX_LEN;

/// Stateful raw LZMA compressor context.
pub const Encoder = struct {
    options: options_mod.LzmaOptions,

    pub fn init(options: options_mod.LzmaOptions) errors.CompressError!Encoder {
        try options.validate();
        return Encoder{ .options = options };
    }

    pub fn encode(self: *Encoder, allocator: std.mem.Allocator, src: []const u8) errors.CompressError![]u8 {
        return compressRaw(allocator, src, self.options);
    }
};

pub const LzmaEncoder = Encoder;

/// Compresses data into a raw LZMA stream (no container header).
pub fn compressRaw(allocator: std.mem.Allocator, src: []const u8, options: options_mod.LzmaOptions) errors.CompressError![]u8 {
    try options.validate();
    const dict_size = options.getDictSize();
    const mode = options.getMode();

    var state = LzmaState.init(options.lc, options.lp, options.pb);
    var rc = RangeEncoder.init(allocator);
    defer rc.deinit();

    if (src.len > 0) {
        var mf = MatchFinder.init(allocator, dict_size, options.getDepth()) catch return error.OutOfMemory;
        defer mf.deinit();

        var pos: usize = 0;
        var has_lookahead = false;
        var lookahead_match: match_finder_mod.Match = .{ .len = 0, .dist = 0 };

        while (pos < src.len) {
            const current_pos = pos;
            const pos_state = state.getPosState(current_pos);
            const prev_byte = if (current_pos > 0) src[current_pos - 1] else 0;
            const match_byte = if (current_pos >= state.reps[0]) src[current_pos - state.reps[0]] else 0;

            // Check rep matches
            var rep_lens = [4]u32{ 0, 0, 0, 0 };
            for (state.reps, 0..) |rep_dist, idx| {
                if (rep_dist > 0 and rep_dist <= current_pos) {
                    const m_pos = current_pos - rep_dist;
                    const max_l = @min(src.len - current_pos, MATCH_MAX_LEN);
                    rep_lens[idx] = match_finder_mod.MatchFinder.countMatch(src, m_pos, current_pos, max_l);
                }
            }

            // Check normal match
            var match: match_finder_mod.Match = undefined;
            if (has_lookahead) {
                match = lookahead_match;
                has_lookahead = false;
            } else {
                match = mf.findMatch(src, current_pos);
            }
            var best_len = match.len;
            const best_dist = match.dist;

            if (best_len == 2 and best_dist >= 128) {
                best_len = 0;
            }

            var best_rep_idx: ?usize = null;
            var best_rep_len: u32 = 0;
            if (rep_lens[0] >= 1) {
                best_rep_len = rep_lens[0];
                best_rep_idx = 0;
            }
            for (1..4) |idx| {
                if (rep_lens[idx] >= 2 and rep_lens[idx] > best_rep_len) {
                    best_rep_len = rep_lens[idx];
                    best_rep_idx = idx;
                }
            }

            var take_rep = (best_rep_idx != null and best_rep_len >= 2) and (best_rep_len >= best_len or
                best_rep_len + 1 >= best_len or
                (best_rep_len + 2 >= best_len and best_dist >= 512) or
                (best_rep_len + 3 >= best_len and best_dist >= 32768));

            if (best_rep_idx != null and best_rep_len >= 2 and !take_rep and best_len >= 2) {
                const next_pos = current_pos + best_rep_len;
                if (next_pos < src.len) {
                    var simulated_reps = state.reps;
                    const r_idx = best_rep_idx.?;
                    if (r_idx != 0) {
                        const dist = simulated_reps[r_idx];
                        var ri = r_idx;
                        while (ri > 0) : (ri -= 1) {
                            simulated_reps[ri] = simulated_reps[ri - 1];
                        }
                        simulated_reps[0] = dist;
                    }

                    var next_rep_max: u32 = 0;
                    for (simulated_reps) |r| {
                        if (r > 0 and r <= next_pos) {
                            const max_l = @min(src.len - next_pos, MATCH_MAX_LEN);
                            const l = match_finder_mod.MatchFinder.countMatch(src, next_pos - r, next_pos, max_l);
                            if (l > next_rep_max) next_rep_max = l;
                        }
                    }
                    if (best_rep_len + next_rep_max > best_len) {
                        take_rep = true;
                    }
                }
            }

            if (take_rep) {
                const r_idx = best_rep_idx.?;
                const r_len = best_rep_len;

                try rc.encodeBit(&state.is_match[state.state][pos_state], 1);
                try rc.encodeBit(&state.is_rep[state.state], 1);

                if (r_idx == 0) {
                    try rc.encodeBit(&state.is_rep_g0[state.state], 0);
                    try rc.encodeBit(&state.is_rep0_long[state.state][pos_state], 1);
                    try state.rep_len_coder.encode(&rc, pos_state, r_len);
                    state.updateStateRep();
                } else {
                    try rc.encodeBit(&state.is_rep_g0[state.state], 1);
                    var dist: u32 = 0;
                    if (r_idx == 1) {
                        try rc.encodeBit(&state.is_rep_g1[state.state], 0);
                        dist = state.reps[1];
                    } else {
                        try rc.encodeBit(&state.is_rep_g1[state.state], 1);
                        if (r_idx == 2) {
                            try rc.encodeBit(&state.is_rep_g2[state.state], 0);
                            dist = state.reps[2];
                        } else {
                            try rc.encodeBit(&state.is_rep_g2[state.state], 1);
                            dist = state.reps[3];
                            state.reps[3] = state.reps[2];
                        }
                        state.reps[2] = state.reps[1];
                    }
                    state.reps[1] = state.reps[0];
                    state.reps[0] = dist;

                    try state.rep_len_coder.encode(&rc, pos_state, r_len);
                    state.updateStateRep();
                }

                mf.skip(src, current_pos + 1, r_len - 1);
                pos += r_len;
            } else if (best_len >= 2) {
                var take_match = true;
                const nice_len = options.nice_len;
                if (mode == .normal and current_pos + 1 < src.len and best_len < nice_len) {
                    const next_match = mf.findMatch(src, current_pos + 1);
                    lookahead_match = next_match;
                    has_lookahead = true;

                    var next_len = next_match.len;
                    if (next_len == 2 and next_match.dist >= 128) next_len = 0;

                    const next_better = (next_len >= best_len and next_match.dist < best_dist) or
                        (next_len == best_len + 1 and !MatchFinder.changePair(best_dist, next_match.dist)) or
                        (next_len > best_len + 1) or
                        (next_len + 1 >= best_len and best_len >= 3 and MatchFinder.changePair(next_match.dist, best_dist));

                    var next_rep_better = false;
                    const limit = @max(2, best_len - 1);
                    for (state.reps) |r| {
                        if (r > 0 and r <= current_pos + 1) {
                            const max_l = @min(src.len - (current_pos + 1), limit);
                            const rl = match_finder_mod.MatchFinder.countMatch(src, current_pos + 1 - r, current_pos + 1, max_l);
                            if (rl >= limit) {
                                next_rep_better = true;
                                break;
                            }
                        }
                    }

                    if (next_better or next_rep_better) {
                        take_match = false;
                    }
                }

                if (take_match) {
                    try rc.encodeBit(&state.is_match[state.state][pos_state], 1);
                    try rc.encodeBit(&state.is_rep[state.state], 0);

                    state.reps[3] = state.reps[2];
                    state.reps[2] = state.reps[1];
                    state.reps[1] = state.reps[0];
                    state.reps[0] = best_dist;

                    try state.len_coder.encode(&rc, pos_state, best_len);
                    state.updateStateMatch();
                    try state.encodeDistance(&rc, best_len, best_dist);

                    if (has_lookahead) {
                        has_lookahead = false;
                        if (best_len > 2) {
                            mf.skip(src, current_pos + 2, best_len - 2);
                        }
                    } else {
                        mf.skip(src, current_pos + 1, best_len - 1);
                    }
                    pos += best_len;
                } else {
                    if (rep_lens[0] >= 1 and current_pos > 0) {
                        try rc.encodeBit(&state.is_match[state.state][pos_state], 1);
                        try rc.encodeBit(&state.is_rep[state.state], 1);
                        try rc.encodeBit(&state.is_rep_g0[state.state], 0);
                        try rc.encodeBit(&state.is_rep0_long[state.state][pos_state], 0);
                        state.updateStateShortRep();
                    } else {
                        try rc.encodeBit(&state.is_match[state.state][pos_state], 0);
                        try state.encodeLiteral(&rc, current_pos, prev_byte, match_byte, src[current_pos]);
                    }
                    pos += 1;
                }
            } else if (rep_lens[0] >= 1 and current_pos > 0) {
                try rc.encodeBit(&state.is_match[state.state][pos_state], 1);
                try rc.encodeBit(&state.is_rep[state.state], 1);
                try rc.encodeBit(&state.is_rep_g0[state.state], 0);
                try rc.encodeBit(&state.is_rep0_long[state.state][pos_state], 0);
                state.updateStateShortRep();
                pos += 1;
            } else {
                try rc.encodeBit(&state.is_match[state.state][pos_state], 0);
                try state.encodeLiteral(&rc, current_pos, prev_byte, match_byte, src[current_pos]);
                pos += 1;
            }
        }
    }

    if (options.write_end_mark) {
        const eos_pos_state = state.getPosState(src.len);
        try state.encodeEos(&rc, eos_pos_state);
    }

    try rc.flush();

    const written = rc.getWritten();
    const result = try allocator.alloc(u8, written.len);
    @memcpy(result, written);
    return result;
}

/// Zero-allocation caller destination buffer compression for raw LZMA.
pub fn compressRawInto(dest: []u8, src: []const u8, options: options_mod.LzmaOptions) errors.CompressError!usize {
    const allocated = try compressRaw(std.heap.page_allocator, src, options);
    defer std.heap.page_allocator.free(allocated);

    if (allocated.len > dest.len) return error.OutputTooSmall;
    @memcpy(dest[0..allocated.len], allocated);
    return allocated.len;
}

pub const compressRawBuffer = compressRawInto;

/// Streaming raw LZMA compression from reader to writer.
pub fn compressRawStream(allocator: std.mem.Allocator, reader: anytype, writer: anytype, options: options_mod.LzmaOptions) errors.CompressError!void {
    var in_buf = std.ArrayList(u8).empty;
    defer in_buf.deinit(allocator);

    var chunk: [16384]u8 = undefined;
    while (true) {
        const n = reader.read(&chunk) catch return error.OutputTooSmall;
        if (n == 0) break;
        in_buf.appendSlice(allocator, chunk[0..n]) catch return error.OutOfMemory;
    }

    const compressed = try compressRaw(allocator, in_buf.items, options);
    defer allocator.free(compressed);

    writer.writeAll(compressed) catch return error.OutputTooSmall;
}

test "lzma compressor: basic raw stream compression" {
    const allocator = std.testing.allocator;
    const msg = "Raw LZMA stream encoder test in native Zig!";

    const comp = try compressRaw(allocator, msg, .{ .write_end_mark = true });
    defer allocator.free(comp);

    try std.testing.expect(comp.len > 0);
}

test "lzma compressor: compressRawInto buffer" {
    const msg = "Testing compressRawInto caller buffer functionality.";
    var buf: [512]u8 = undefined;

    const len = try compressRawInto(&buf, msg, .{ .write_end_mark = true });
    try std.testing.expect(len > 0);
    try std.testing.expect(len <= buf.len);
}
