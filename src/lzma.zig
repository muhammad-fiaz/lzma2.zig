//! LZMA Compression Library
//!
//! Provides the core LZMA Markov state machine, length coders, probability models,
//! the legacy `.lzma` single-file container (LZMA-Alone format), and raw LZMA streams.

const std = @import("std");

pub const errors = @import("utils/errors.zig");
pub const options = @import("utils/options.zig");
pub const range_codec = @import("utils/range_codec.zig");
pub const match_finder = @import("utils/match_finder.zig");
pub const state = @import("utils/state.zig");

pub const RangeDecoder = range_codec.RangeDecoder;
pub const RangeEncoder = range_codec.RangeEncoder;

// Core Markov model constants and types forwarded from state.zig
pub const NUM_STATES = state.NUM_STATES;
pub const NUM_LIT_STATES = state.NUM_LIT_STATES;
pub const NUM_POS_STATES_MAX = state.NUM_POS_STATES_MAX;

pub const LEN_NUM_LOW_BITS = state.LEN_NUM_LOW_BITS;
pub const LEN_NUM_LOW_SYMBOLS = state.LEN_NUM_LOW_SYMBOLS;
pub const LEN_NUM_HIGH_BITS = state.LEN_NUM_HIGH_BITS;
pub const LEN_NUM_HIGH_SYMBOLS = state.LEN_NUM_HIGH_SYMBOLS;
pub const MATCH_MIN_LEN = state.MATCH_MIN_LEN;
pub const MATCH_MAX_LEN = state.MATCH_MAX_LEN;

pub const NUM_POS_SLOT_BITS = state.NUM_POS_SLOT_BITS;
pub const NUM_LEN_TO_POS_STATES = state.NUM_LEN_TO_POS_STATES;
pub const START_POS_MODEL_INDEX = state.START_POS_MODEL_INDEX;
pub const END_POS_MODEL_INDEX = state.END_POS_MODEL_INDEX;
pub const NUM_FULL_DISTANCES = state.NUM_FULL_DISTANCES;
pub const NUM_ALIGN_BITS = state.NUM_ALIGN_BITS;
pub const ALIGN_TABLE_SIZE = state.ALIGN_TABLE_SIZE;

pub const LZMA_LIT_SIZE = state.LZMA_LIT_SIZE;
pub const MAX_LCLP = state.MAX_LCLP;
pub const LIT_PROBS_MAX = state.LIT_PROBS_MAX;

pub const LenCoder = state.LenCoder;
pub const LzmaState = state.LzmaState;
pub const getPosSlot = state.getPosSlot;

// Submodules & API Re-exports
pub const compress_container = @import("compress/container.zig");
pub const decompress_container = @import("decompress/container.zig");
pub const compress_raw = @import("compress/lzma.zig");
pub const decompress_raw = @import("decompress/lzma.zig");

// Legacy .lzma single-file container (Alone format)
pub const compress = compress_container.compress;
pub const compressInto = compress_container.compressInto;
pub const compressBuffer = compress_container.compressBuffer;
pub const decompress = decompress_container.decompress;
pub const decompressInto = decompress_container.decompressInto;
pub const decompressBuffer = decompress_container.decompressBuffer;
pub const compressStream = compress_container.compressStream;
pub const decompressStream = decompress_container.decompressStream;
pub const AloneOptions = options.AloneOptions;
pub const AloneHeader = options.AloneHeader;

// Raw LZMA stream format
pub const compressRaw = compress_raw.compressRaw;
pub const compressRawInto = compress_raw.compressRawInto;
pub const compressRawBuffer = compress_raw.compressRawBuffer;
pub const compressRawStream = compress_raw.compressRawStream;
pub const decompressRaw = decompress_raw.decompressRaw;
pub const decompressRawInto = decompress_raw.decompressRawInto;
pub const decompressRawBuffer = decompress_raw.decompressRawBuffer;
pub const decompressRawStream = decompress_raw.decompressRawStream;

pub const Encoder = compress_raw.Encoder;
pub const Decoder = decompress_raw.Decoder;
pub const LzmaEncoder = compress_raw.Encoder;
pub const LzmaDecoder = decompress_raw.Decoder;
pub const LzmaOptions = options.LzmaOptions;
pub const LzmaDecompressOptions = options.LzmaDecompressOptions;

// Backward-compatibility aliases
pub const encoder = compress_raw;
pub const decoder = decompress_raw;
pub const alone = struct {
    pub const compress = compress_container.compress;
    pub const decompress = decompress_container.decompress;
    pub const compressInto = compress_container.compressInto;
    pub const decompressInto = decompress_container.decompressInto;
    pub const Header = options.AloneHeader;
};

test {
    _ = @import("utils/range_codec.zig");
    _ = @import("utils/match_finder.zig");
    _ = @import("utils/options.zig");
    _ = @import("utils/errors.zig");
    _ = @import("utils/state.zig");
    _ = @import("compress/container.zig");
    _ = @import("decompress/container.zig");
    _ = @import("compress/lzma.zig");
    _ = @import("decompress/lzma.zig");
}

test "lzma: getPosSlot calculation" {
    try std.testing.expectEqual(@as(u32, 0), getPosSlot(0));
    try std.testing.expectEqual(@as(u32, 1), getPosSlot(1));
    try std.testing.expectEqual(@as(u32, 2), getPosSlot(2));
    try std.testing.expectEqual(@as(u32, 3), getPosSlot(3));
    try std.testing.expectEqual(@as(u32, 4), getPosSlot(4));
    try std.testing.expectEqual(@as(u32, 5), getPosSlot(6));
}

test "lzma: state machine and length coder reset" {
    var s = LzmaState.init(3, 0, 2);
    try std.testing.expectEqual(@as(u8, 0), s.state);
    try std.testing.expectEqual(@as(u32, 1), s.reps[0]);
    s.updateStateMatch();
    try std.testing.expectEqual(@as(u8, 7), s.state);
    s.reset();
    try std.testing.expectEqual(@as(u8, 0), s.state);
}

test "lzma: raw stream roundtrip with eos marker" {
    const allocator = std.testing.allocator;
    const msg = "Native Zig raw LZMA stream roundtrip test with EOS marker! 1234567890.";

    const compressed = try compressRaw(allocator, msg, .{ .write_end_mark = true });
    defer allocator.free(compressed);

    const decompressed = try decompressRaw(allocator, compressed, .{ .uncompressed_size = null });
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, msg, decompressed);
}

test "lzma: raw stream roundtrip with known size and no eos" {
    const allocator = std.testing.allocator;
    const msg = "Native Zig raw LZMA stream without EOS marker, using known size.";

    const compressed = try compressRaw(allocator, msg, .{ .write_end_mark = false });
    defer allocator.free(compressed);

    const decompressed = try decompressRaw(allocator, compressed, .{ .uncompressed_size = msg.len });
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, msg, decompressed);
}

test "lzma: alone container alias roundtrip" {
    const allocator = std.testing.allocator;
    const msg = "Legacy alone container roundtrip test via lzma.compress/decompress.";

    const comp = try compress(allocator, msg, .{});
    defer allocator.free(comp);

    const decomp = try decompress(allocator, comp, .{});
    defer allocator.free(decomp);

    try std.testing.expectEqualSlices(u8, msg, decomp);
}
