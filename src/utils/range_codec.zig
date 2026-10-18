//! LZMA Range Coder (Decoder and Encoder).
//!
//! Implements 32-bit range coding with adaptive 11-bit probability models
//! and 5-bit exponential adaptation as specified by the LZMA/LZMA2 standard.

const std = @import("std");
const errors = @import("errors.zig");

pub const BIT_MODEL_TOTAL_BITS: u5 = 11;
pub const BIT_MODEL_TOTAL: u16 = 1 << BIT_MODEL_TOTAL_BITS; // 2048
pub const NUM_MOVE_BITS: u5 = 5;
pub const PROB_INIT_VALUE: u16 = BIT_MODEL_TOTAL >> 1; // 1024 (0x400)
pub const TOP_VALUE: u32 = 1 << 24; // 0x01000000

/// Initializes all probabilities in a slice to `PROB_INIT_VALUE` (1024).
pub fn initProbs(probs: []u16) void {
    @memset(probs, PROB_INIT_VALUE);
}

/// LZMA Range Decoder.
pub const RangeDecoder = struct {
    range: u32,
    code: u32,
    src: []const u8,
    pos: usize,

    /// Initializes a range decoder from an input slice.
    /// In LZMA2, every compressed chunk payload begins with 5 range coder initialization bytes:
    /// byte 0 must be 0x00, followed by 4 code bytes (big-endian).
    pub fn init(src: []const u8) errors.DecompressError!RangeDecoder {
        if (src.len < 5) return error.UnexpectedEof;
        if (src[0] != 0) return error.CorruptData;

        const code = (@as(u32, src[1]) << 24) |
            (@as(u32, src[2]) << 16) |
            (@as(u32, src[3]) << 8) |
            @as(u32, src[4]);

        return RangeDecoder{
            .range = 0xFFFFFFFF,
            .code = code,
            .src = src,
            .pos = 5,
        };
    }

    /// Decodes a single bit using an adaptive probability model.
    pub inline fn decodeBit(self: *RangeDecoder, prob: *u16) errors.DecompressError!u1 {
        if (self.range < TOP_VALUE) {
            if (self.pos >= self.src.len) return error.UnexpectedEof;
            self.range <<= 8;
            self.code = (self.code << 8) | self.src[self.pos];
            self.pos += 1;
        }

        const bound = (self.range >> BIT_MODEL_TOTAL_BITS) * prob.*;
        if (self.code < bound) {
            self.range = bound;
            prob.* += (BIT_MODEL_TOTAL - prob.*) >> NUM_MOVE_BITS;
            return 0;
        } else {
            self.range -= bound;
            self.code -= bound;
            prob.* -= prob.* >> NUM_MOVE_BITS;
            return 1;
        }
    }

    /// Decodes bits with a fixed 0.5 probability (direct bits).
    pub inline fn decodeDirectBits(self: *RangeDecoder, num_bits: u5) errors.DecompressError!u32 {
        var res: u32 = 0;
        var i: u5 = num_bits;
        while (i > 0) : (i -= 1) {
            if (self.range < TOP_VALUE) {
                if (self.pos >= self.src.len) return error.UnexpectedEof;
                self.range <<= 8;
                self.code = (self.code << 8) | self.src[self.pos];
                self.pos += 1;
            }

            self.range >>= 1;
            if (self.code >= self.range) {
                self.code -= self.range;
                res = (res << 1) | 1;
            } else {
                res = (res << 1);
            }
        }
        return res;
    }

    /// Decodes a symbol from a standard binary tree of depth `num_bits`.
    /// The tree probabilities slice must have at least `1 << num_bits` elements.
    pub inline fn decodeTree(self: *RangeDecoder, probs: []u16, num_bits: u5) errors.DecompressError!u32 {
        var node: usize = 1;
        for (0..num_bits) |_| {
            const bit = try self.decodeBit(&probs[node]);
            node = (node << 1) | bit;
        }
        return @intCast(node - (@as(usize, 1) << num_bits));
    }

    /// Decodes a symbol using a reverse binary tree of depth `num_bits`.
    /// Bits decoded at the root are placed at the least significant positions.
    pub inline fn decodeReverseTree(self: *RangeDecoder, probs: []u16, num_bits: u5) errors.DecompressError!u32 {
        var node: usize = 1;
        var res: u32 = 0;
        for (0..num_bits) |bit_idx| {
            const bit = try self.decodeBit(&probs[node]);
            node = (node << 1) | bit;
            res |= @as(u32, bit) << @intCast(bit_idx);
        }
        return res;
    }

    /// Normalizes range decoder if needed at chunk boundary.
    pub fn normalize(self: *RangeDecoder) errors.DecompressError!void {
        while (self.range < TOP_VALUE) {
            if (self.pos >= self.src.len) return error.UnexpectedEof;
            self.range <<= 8;
            self.code = (self.code << 8) | self.src[self.pos];
            self.pos += 1;
        }
    }

    /// Number of bytes read from input slice.
    pub fn getProcessed(self: *const RangeDecoder) usize {
        return self.pos;
    }
};

/// LZMA Range Encoder writing to a dynamic or static destination buffer.
pub const RangeEncoder = struct {
    low: u64 = 0,
    range: u32 = 0xFFFFFFFF,
    cache: u8 = 0,
    cache_size: u32 = 0,
    out: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RangeEncoder {
        return RangeEncoder{
            .out = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RangeEncoder) void {
        self.out.deinit(self.allocator);
    }

    pub fn reset(self: *RangeEncoder) void {
        self.low = 0;
        self.range = 0xFFFFFFFF;
        self.cache = 0;
        self.cache_size = 0;
        self.out.clearRetainingCapacity();
    }

    fn shiftLow(self: *RangeEncoder) errors.CompressError!void {
        const low_u32: u32 = @truncate(self.low);
        const high: u32 = @truncate(self.low >> 32);
        self.low = (@as(u64, low_u32) << 8) & 0xFFFFFFFF;

        if (low_u32 < 0xFF000000 or high != 0) {
            self.out.ensureUnusedCapacity(self.allocator, 1 + self.cache_size) catch return error.OutOfMemory;
            self.out.appendAssumeCapacity(self.cache +% @as(u8, @truncate(high)));
            self.cache = @truncate(low_u32 >> 24);
            const h: u8 = @truncate(high +% 0xFF);
            while (self.cache_size > 0) : (self.cache_size -= 1) {
                self.out.appendAssumeCapacity(h);
            }
        } else {
            self.cache_size += 1;
        }
    }

    /// Encodes a single bit using an adaptive probability model.
    pub inline fn encodeBit(self: *RangeEncoder, prob: *u16, bit: u1) errors.CompressError!void {
        const new_bound = (self.range >> BIT_MODEL_TOTAL_BITS) * prob.*;
        if (bit == 0) {
            self.range = new_bound;
            prob.* += (BIT_MODEL_TOTAL - prob.*) >> NUM_MOVE_BITS;
        } else {
            self.low += new_bound;
            self.range -= new_bound;
            prob.* -= prob.* >> NUM_MOVE_BITS;
        }
        if (self.range < TOP_VALUE) {
            self.range <<= 8;
            try self.shiftLow();
        }
    }

    /// Encodes direct bits (fixed probability 0.5).
    pub inline fn encodeDirectBits(self: *RangeEncoder, value: u32, num_bits: u5) errors.CompressError!void {
        var i: usize = num_bits;
        while (i > 0) {
            i -= 1;
            self.range >>= 1;
            if (((value >> @intCast(i)) & 1) != 0) {
                self.low += self.range;
            }
            if (self.range < TOP_VALUE) {
                self.range <<= 8;
                try self.shiftLow();
            }
        }
    }

    /// Encodes a symbol using a standard binary tree.
    pub inline fn encodeTree(self: *RangeEncoder, probs: []u16, num_bits: u5, value: u32) errors.CompressError!void {
        var node: usize = 1;
        var i: usize = num_bits;
        while (i > 0) {
            i -= 1;
            const bit: u1 = @truncate((value >> @intCast(i)) & 1);
            try self.encodeBit(&probs[node], bit);
            node = (node << 1) | bit;
        }
    }

    /// Encodes a symbol using a reverse binary tree.
    pub inline fn encodeReverseTree(self: *RangeEncoder, probs: []u16, num_bits: u5, value: u32) errors.CompressError!void {
        var node: usize = 1;
        for (0..num_bits) |bit_idx| {
            const bit: u1 = @truncate((value >> @intCast(bit_idx)) & 1);
            try self.encodeBit(&probs[node], bit);
            node = (node << 1) | bit;
        }
    }

    /// Flushes remaining bytes from the range encoder to complete the stream.
    pub fn flush(self: *RangeEncoder) errors.CompressError!void {
        for (0..5) |_| {
            try self.shiftLow();
        }
    }

    /// Returns the encoded byte slice.
    pub fn getWritten(self: *const RangeEncoder) []const u8 {
        return self.out.items;
    }
};

test "range_codec: single bit encode and decode" {
    var enc = RangeEncoder.init(std.testing.allocator);
    defer enc.deinit();

    var prob: u16 = PROB_INIT_VALUE;
    try enc.encodeBit(&prob, 1);
    try enc.flush();

    var dec = try RangeDecoder.init(enc.getWritten());

    var dec_prob: u16 = PROB_INIT_VALUE;
    const bit = try dec.decodeBit(&dec_prob);
    try std.testing.expectEqual(@as(u1, 1), bit);
}

test "range_codec: direct bits encode and decode" {
    var enc = RangeEncoder.init(std.testing.allocator);
    defer enc.deinit();

    try enc.encodeDirectBits(0xAB, 8);
    try enc.encodeDirectBits(0x05, 4);
    try enc.flush();

    var dec = try RangeDecoder.init(enc.getWritten());

    const val1 = try dec.decodeDirectBits(8);
    const val2 = try dec.decodeDirectBits(4);

    try std.testing.expectEqual(@as(u32, 0xAB), val1);
    try std.testing.expectEqual(@as(u32, 0x05), val2);
}

test "range_codec: tree and reverse tree encode and decode" {
    var enc = RangeEncoder.init(std.testing.allocator);
    defer enc.deinit();

    var tree_probs: [64]u16 = @splat(PROB_INIT_VALUE);
    var rev_tree_probs: [64]u16 = @splat(PROB_INIT_VALUE);

    try enc.encodeTree(&tree_probs, 5, 23);
    try enc.encodeReverseTree(&rev_tree_probs, 5, 19);
    try enc.flush();

    var dec = try RangeDecoder.init(enc.getWritten());

    var dec_tree_probs: [64]u16 = @splat(PROB_INIT_VALUE);
    var dec_rev_tree_probs: [64]u16 = @splat(PROB_INIT_VALUE);

    const tree_val = try dec.decodeTree(&dec_tree_probs, 5);
    const rev_tree_val = try dec.decodeReverseTree(&dec_rev_tree_probs, 5);

    try std.testing.expectEqual(@as(u32, 23), tree_val);
    try std.testing.expectEqual(@as(u32, 19), rev_tree_val);
}
