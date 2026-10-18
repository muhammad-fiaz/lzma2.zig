//! Core LZMA Markov state machine, length coders, and probability models.
//!
//! Shared across LZMA and LZMA2 compression and decompression engines.

const std = @import("std");
const errors = @import("errors.zig");
const range_codec = @import("range_codec.zig");
const RangeDecoder = range_codec.RangeDecoder;
const RangeEncoder = range_codec.RangeEncoder;

// Core Markov model constants
pub const NUM_STATES = 12;
pub const NUM_LIT_STATES = 7;
pub const NUM_POS_STATES_MAX = 16; // 1 << 4

pub const LEN_NUM_LOW_BITS = 3;
pub const LEN_NUM_LOW_SYMBOLS = 1 << LEN_NUM_LOW_BITS; // 8
pub const LEN_NUM_HIGH_BITS = 8;
pub const LEN_NUM_HIGH_SYMBOLS = 1 << LEN_NUM_HIGH_BITS; // 256
pub const MATCH_MIN_LEN = 2;
pub const MATCH_MAX_LEN = MATCH_MIN_LEN + LEN_NUM_LOW_SYMBOLS * 2 + LEN_NUM_HIGH_SYMBOLS - 1; // 273

pub const NUM_POS_SLOT_BITS = 6; // 64 pos slots
pub const NUM_LEN_TO_POS_STATES = 4;
pub const START_POS_MODEL_INDEX = 4;
pub const END_POS_MODEL_INDEX = 14;
pub const NUM_FULL_DISTANCES = 1 << (END_POS_MODEL_INDEX >> 1); // 128
pub const NUM_ALIGN_BITS = 4;
pub const ALIGN_TABLE_SIZE = 1 << NUM_ALIGN_BITS; // 16

pub const LZMA_LIT_SIZE = 0x300; // 768
pub const MAX_LCLP = 4; // LZMA2 restriction: lc + lp <= 4
pub const LIT_PROBS_MAX = (1 << MAX_LCLP) * LZMA_LIT_SIZE; // 16 * 768 = 12288

/// Length coder for normal matches and repeated matches.
pub const LenCoder = struct {
    choice: u16 = range_codec.PROB_INIT_VALUE,
    choice2: u16 = range_codec.PROB_INIT_VALUE,
    low: [NUM_POS_STATES_MAX][LEN_NUM_LOW_SYMBOLS]u16 = @splat(@splat(range_codec.PROB_INIT_VALUE)),
    mid: [NUM_POS_STATES_MAX][LEN_NUM_LOW_SYMBOLS]u16 = @splat(@splat(range_codec.PROB_INIT_VALUE)),
    high: [LEN_NUM_HIGH_SYMBOLS]u16 = @splat(range_codec.PROB_INIT_VALUE),

    pub fn reset(self: *LenCoder) void {
        self.choice = range_codec.PROB_INIT_VALUE;
        self.choice2 = range_codec.PROB_INIT_VALUE;
        for (&self.low) |*row| range_codec.initProbs(row);
        for (&self.mid) |*row| range_codec.initProbs(row);
        range_codec.initProbs(&self.high);
    }

    /// Decodes a match length (2..273).
    pub fn decode(self: *LenCoder, rc: *RangeDecoder, pos_state: usize) errors.DecompressError!u32 {
        if (try rc.decodeBit(&self.choice) == 0) {
            return MATCH_MIN_LEN + try rc.decodeTree(&self.low[pos_state], LEN_NUM_LOW_BITS);
        }
        if (try rc.decodeBit(&self.choice2) == 0) {
            return MATCH_MIN_LEN + LEN_NUM_LOW_SYMBOLS + try rc.decodeTree(&self.mid[pos_state], LEN_NUM_LOW_BITS);
        }
        return MATCH_MIN_LEN + LEN_NUM_LOW_SYMBOLS * 2 + try rc.decodeTree(&self.high, LEN_NUM_HIGH_BITS);
    }

    /// Encodes a match length (2..273).
    pub fn encode(self: *LenCoder, rc: *RangeEncoder, pos_state: usize, len: u32) errors.CompressError!void {
        const symbol = len - MATCH_MIN_LEN;
        if (symbol < LEN_NUM_LOW_SYMBOLS) {
            try rc.encodeBit(&self.choice, 0);
            try rc.encodeTree(&self.low[pos_state], LEN_NUM_LOW_BITS, symbol);
        } else if (symbol < LEN_NUM_LOW_SYMBOLS * 2) {
            try rc.encodeBit(&self.choice, 1);
            try rc.encodeBit(&self.choice2, 0);
            try rc.encodeTree(&self.mid[pos_state], LEN_NUM_LOW_BITS, symbol - LEN_NUM_LOW_SYMBOLS);
        } else {
            try rc.encodeBit(&self.choice, 1);
            try rc.encodeBit(&self.choice2, 1);
            try rc.encodeTree(&self.high, LEN_NUM_HIGH_BITS, symbol - LEN_NUM_LOW_SYMBOLS * 2);
        }
    }
};

/// Combined state and probability tables for an LZMA coder.
pub const LzmaState = struct {
    state: u8 = 0,
    reps: [4]u32 = .{ 1, 1, 1, 1 },

    lc: u4 = 3,
    lp: u4 = 0,
    pb: u4 = 2,

    is_match: [NUM_STATES][NUM_POS_STATES_MAX]u16 = @splat(@splat(range_codec.PROB_INIT_VALUE)),
    is_rep: [NUM_STATES]u16 = @splat(range_codec.PROB_INIT_VALUE),
    is_rep_g0: [NUM_STATES]u16 = @splat(range_codec.PROB_INIT_VALUE),
    is_rep_g1: [NUM_STATES]u16 = @splat(range_codec.PROB_INIT_VALUE),
    is_rep_g2: [NUM_STATES]u16 = @splat(range_codec.PROB_INIT_VALUE),
    is_rep0_long: [NUM_STATES][NUM_POS_STATES_MAX]u16 = @splat(@splat(range_codec.PROB_INIT_VALUE)),

    pos_slot: [NUM_LEN_TO_POS_STATES][1 << NUM_POS_SLOT_BITS]u16 = @splat(@splat(range_codec.PROB_INIT_VALUE)),
    spec_pos: [NUM_FULL_DISTANCES]u16 = @splat(range_codec.PROB_INIT_VALUE),
    pos_align: [ALIGN_TABLE_SIZE]u16 = @splat(range_codec.PROB_INIT_VALUE),

    len_coder: LenCoder = .{},
    rep_len_coder: LenCoder = .{},

    literal_probs: [LIT_PROBS_MAX]u16 = @splat(range_codec.PROB_INIT_VALUE),

    pub fn init(lc: u4, lp: u4, pb: u4) LzmaState {
        var s = LzmaState{
            .lc = lc,
            .lp = lp,
            .pb = pb,
        };
        s.reset();
        return s;
    }

    /// Resets all probabilities and internal state to initial values.
    pub fn reset(self: *LzmaState) void {
        self.state = 0;
        self.reps = .{ 1, 1, 1, 1 };

        for (&self.is_match) |*row| range_codec.initProbs(row);
        range_codec.initProbs(&self.is_rep);
        range_codec.initProbs(&self.is_rep_g0);
        range_codec.initProbs(&self.is_rep_g1);
        range_codec.initProbs(&self.is_rep_g2);
        for (&self.is_rep0_long) |*row| range_codec.initProbs(row);

        for (&self.pos_slot) |*row| range_codec.initProbs(row);
        range_codec.initProbs(&self.spec_pos);
        range_codec.initProbs(&self.pos_align);

        self.len_coder.reset();
        self.rep_len_coder.reset();

        const lclp = @as(u5, self.lc) + @as(u5, self.lp);
        const safe_lclp: u5 = if (lclp > MAX_LCLP) MAX_LCLP else lclp;
        const num_lit_probs = @min((@as(usize, 1) << safe_lclp) * LZMA_LIT_SIZE, self.literal_probs.len);
        range_codec.initProbs(self.literal_probs[0..num_lit_probs]);
    }

    /// Updates properties and resets literal probabilities.
    pub fn setProps(self: *LzmaState, lc: u4, lp: u4, pb: u4) void {
        self.lc = lc;
        self.lp = lp;
        self.pb = pb;
        const lclp = @as(u5, self.lc) + @as(u5, self.lp);
        const safe_lclp: u5 = if (lclp > MAX_LCLP) MAX_LCLP else lclp;
        const num_lit_probs = @min((@as(usize, 1) << safe_lclp) * LZMA_LIT_SIZE, self.literal_probs.len);
        range_codec.initProbs(self.literal_probs[0..num_lit_probs]);
    }

    pub inline fn getPosState(self: *const LzmaState, processed_pos: usize) usize {
        const mask = (@as(usize, 1) << self.pb) - 1;
        return processed_pos & mask;
    }

    pub inline fn getLitSubtree(self: *const LzmaState, processed_pos: usize, prev_byte: u8) usize {
        const lp_mask = (@as(usize, 1) << self.lp) - 1;
        const pos_bits = processed_pos & lp_mask;
        const ctx_bits = @as(usize, prev_byte) >> @intCast(8 - self.lc);
        return ((pos_bits << self.lc) + ctx_bits) * LZMA_LIT_SIZE;
    }

    pub inline fn updateStateLiteral(self: *LzmaState) void {
        if (self.state < 4) {
            self.state = 0;
        } else if (self.state < 10) {
            self.state -= 3;
        } else {
            self.state -= 6;
        }
    }

    pub inline fn updateStateMatch(self: *LzmaState) void {
        self.state = if (self.state < NUM_LIT_STATES) 7 else 10;
    }

    pub inline fn updateStateRep(self: *LzmaState) void {
        self.state = if (self.state < NUM_LIT_STATES) 8 else 11;
    }

    pub inline fn updateStateShortRep(self: *LzmaState) void {
        self.state = if (self.state < NUM_LIT_STATES) 9 else 11;
    }

    // Decoder operations

    /// Decodes a literal byte.
    pub inline fn decodeLiteral(
        self: *LzmaState,
        rc: *RangeDecoder,
        processed_pos: usize,
        prev_byte: u8,
        match_byte: u8,
    ) errors.DecompressError!u8 {
        const base_idx = self.getLitSubtree(processed_pos, prev_byte);
        const probs = self.literal_probs[base_idx .. base_idx + LZMA_LIT_SIZE];

        var symbol: usize = 1;
        if (self.state < NUM_LIT_STATES) {
            while (symbol < 0x100) {
                const bit = try rc.decodeBit(&probs[symbol]);
                symbol = (symbol << 1) | bit;
            }
        } else {
            var match_byte_var = match_byte;
            var offs: usize = 0x100;
            while (symbol < 0x100) {
                const match_bit: u1 = @truncate(match_byte_var >> 7);
                match_byte_var <<= 1;
                const bit = try rc.decodeBit(&probs[if (offs != 0) (0x100 + (@as(usize, match_bit) << 8) + symbol) else symbol]);
                symbol = (symbol << 1) | bit;
                if (bit != match_bit) offs = 0;
            }
        }

        self.updateStateLiteral();
        return @truncate(symbol - 0x100);
    }

    /// Decodes a match distance given its length.
    pub fn decodeDistance(self: *LzmaState, rc: *RangeDecoder, len: u32) errors.DecompressError!u32 {
        const len_to_pos_state = if (len - MATCH_MIN_LEN < NUM_LEN_TO_POS_STATES)
            len - MATCH_MIN_LEN
        else
            NUM_LEN_TO_POS_STATES - 1;

        const pos_slot_val = try rc.decodeTree(&self.pos_slot[len_to_pos_state], NUM_POS_SLOT_BITS);
        if (pos_slot_val < START_POS_MODEL_INDEX) {
            return pos_slot_val + 1;
        }

        const num_direct_bits: u5 = @intCast((pos_slot_val >> 1) - 1);
        var dist: u32 = (2 | (pos_slot_val & 1)) << num_direct_bits;

        if (pos_slot_val < END_POS_MODEL_INDEX) {
            var node: usize = 1;
            var rev_val: u32 = 0;
            for (0..num_direct_bits) |bit_idx| {
                const bit = try rc.decodeBit(&self.spec_pos[dist + node]);
                node = (node << 1) | bit;
                rev_val |= @as(u32, bit) << @intCast(bit_idx);
            }
            dist += rev_val;
        } else {
            const direct_bits: u5 = num_direct_bits - NUM_ALIGN_BITS;
            dist += (try rc.decodeDirectBits(direct_bits)) << NUM_ALIGN_BITS;
            dist += try rc.decodeReverseTree(&self.pos_align, NUM_ALIGN_BITS);
        }

        if (dist == 0xFFFFFFFF) {
            return 0xFFFFFFFF;
        }

        return dist + 1;
    }

    /// Encodes an End-of-Stream (EOS) marker.
    pub fn encodeEos(self: *LzmaState, rc: *RangeEncoder, pos_state: usize) errors.CompressError!void {
        try rc.encodeBit(&self.is_match[self.state][pos_state], 1);
        try rc.encodeBit(&self.is_rep[self.state], 0);
        self.updateStateMatch();
        try self.len_coder.encode(rc, pos_state, MATCH_MIN_LEN);
        try rc.encodeTree(&self.pos_slot[0], NUM_POS_SLOT_BITS, (1 << NUM_POS_SLOT_BITS) - 1);
        const direct_bits: u5 = 30 - NUM_ALIGN_BITS;
        try rc.encodeDirectBits((1 << 26) - 1, direct_bits);
        try rc.encodeReverseTree(&self.pos_align, NUM_ALIGN_BITS, (1 << NUM_ALIGN_BITS) - 1);
    }

    // Encoder operations

    /// Encodes a literal byte.
    pub inline fn encodeLiteral(
        self: *LzmaState,
        rc: *RangeEncoder,
        processed_pos: usize,
        prev_byte: u8,
        match_byte: u8,
        byte: u8,
    ) errors.CompressError!void {
        const base_idx = self.getLitSubtree(processed_pos, prev_byte);
        const probs = self.literal_probs[base_idx .. base_idx + LZMA_LIT_SIZE];

        var symbol: usize = 1;
        if (self.state < NUM_LIT_STATES) {
            var i: usize = 8;
            while (i > 0) {
                i -= 1;
                const bit: u1 = @truncate((byte >> @intCast(i)) & 1);
                try rc.encodeBit(&probs[symbol], bit);
                symbol = (symbol << 1) | bit;
            }
        } else {
            var match_byte_var = match_byte;
            var offs: usize = 0x100;
            var i: usize = 8;
            while (i > 0) {
                i -= 1;
                const match_bit: u1 = @truncate(match_byte_var >> 7);
                match_byte_var <<= 1;
                const bit: u1 = @truncate((byte >> @intCast(i)) & 1);
                const prob_idx = if (offs != 0) (0x100 + (@as(usize, match_bit) << 8) + symbol) else symbol;
                try rc.encodeBit(&probs[prob_idx], bit);
                symbol = (symbol << 1) | bit;
                if (bit != match_bit) offs = 0;
            }
        }

        self.updateStateLiteral();
    }

    /// Encodes a match distance.
    pub fn encodeDistance(self: *LzmaState, rc: *RangeEncoder, len: u32, distance: u32) errors.CompressError!void {
        const dist = distance - 1;
        const len_to_pos_state = if (len - MATCH_MIN_LEN < NUM_LEN_TO_POS_STATES)
            len - MATCH_MIN_LEN
        else
            NUM_LEN_TO_POS_STATES - 1;

        const pos_slot_val = getPosSlot(dist);
        try rc.encodeTree(&self.pos_slot[len_to_pos_state], NUM_POS_SLOT_BITS, pos_slot_val);

        if (pos_slot_val >= START_POS_MODEL_INDEX) {
            const num_direct_bits: u5 = @intCast((pos_slot_val >> 1) - 1);
            const base: u32 = (2 | (pos_slot_val & 1)) << num_direct_bits;
            const dist_reduced = dist - base;

            if (pos_slot_val < END_POS_MODEL_INDEX) {
                var node: usize = 1;
                for (0..num_direct_bits) |bit_idx| {
                    const bit: u1 = @truncate((dist_reduced >> @intCast(bit_idx)) & 1);
                    try rc.encodeBit(&self.spec_pos[base + node], bit);
                    node = (node << 1) | bit;
                }
            } else {
                const direct_bits: u5 = num_direct_bits - NUM_ALIGN_BITS;
                try rc.encodeDirectBits(dist_reduced >> NUM_ALIGN_BITS, direct_bits);
                try rc.encodeReverseTree(&self.pos_align, NUM_ALIGN_BITS, dist_reduced & 0x0F);
            }
        }
    }
};

/// Computes the 6-bit pos_slot for a 0-based distance.
pub fn getPosSlot(dist: u32) u32 {
    if (dist < 4) return dist;
    const msb: u32 = 31 - @clz(dist);
    const second_bit: u32 = (dist >> @intCast(msb - 1)) & 1;
    return (msb << 1) | second_bit;
}

test "state: getPosSlot and LzmaState reset" {
    try std.testing.expectEqual(@as(u32, 0), getPosSlot(0));
    try std.testing.expectEqual(@as(u32, 1), getPosSlot(1));
    var s = LzmaState.init(3, 0, 2);
    try std.testing.expectEqual(@as(u8, 0), s.state);
    s.updateStateMatch();
    try std.testing.expectEqual(@as(u8, 7), s.state);
    s.reset();
    try std.testing.expectEqual(@as(u8, 0), s.state);
}
