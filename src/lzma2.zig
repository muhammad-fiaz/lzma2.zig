//! lzma2.zig — Native Zig LZMA2 Compression Library
//!
//! A high-performance, type-safe, memory-conscious, standalone implementation
//! of the LZMA2 compression codec written in native Zig for Zig 0.17.0.
//!
//! Author: muhammad-fiaz
//! License: MIT
//! Repository: https://github.com/muhammad-fiaz/lzma2.zig

const std = @import("std");

// Full LZMA support
pub const lzma = @import("lzma");

// Re-export common utilities directly from lzma module
pub const errors = lzma.errors;
pub const options = lzma.options;
pub const range_codec = lzma.range_codec;
pub const match_finder = lzma.match_finder;

// LZMA2 codec submodules
pub const compress_mod = @import("compress/lzma2.zig");
pub const decompress_mod = @import("decompress/lzma2.zig");
pub const compress_streaming = @import("compress/streaming.zig");
pub const decompress_streaming = @import("decompress/streaming.zig");
pub const streaming = struct {
    pub const StreamingCompressor = compress_streaming.StreamingCompressor;
    pub const StreamingDecompressor = decompress_streaming.StreamingDecompressor;
    pub const compressStream = compress_streaming.compressStream;
    pub const decompressStream = decompress_streaming.decompressStream;
};

// Version
pub const version = options.version;
pub const VERSION = options.version;

// Re-export error sets
pub const Error = errors.Error;
pub const CompressError = errors.CompressError;
pub const DecompressError = errors.DecompressError;

// Re-export configuration options and constants
pub const Options = options.Options;
pub const DecompressOptions = options.DecompressOptions;
pub const AloneOptions = options.AloneOptions;
pub const AloneHeader = lzma.AloneHeader;
pub const Mode = options.Mode;
pub const Preset = options.Preset;

pub const DEFAULT_DICT_SIZE = options.DEFAULT_DICT_SIZE;
pub const DEFAULT_LC = options.DEFAULT_LC;
pub const DEFAULT_LP = options.DEFAULT_LP;
pub const DEFAULT_PB = options.DEFAULT_PB;
pub const CHUNK_UNPACK_MAX = options.CHUNK_UNPACK_MAX;
pub const CHUNK_PACK_MAX = options.CHUNK_PACK_MAX;
pub const DICT_SIZE_MIN = options.DICT_SIZE_MIN;
pub const DICT_SIZE_MAX = options.DICT_SIZE_MAX;

pub const propToDictSize = options.propToDictSize;
pub const dictSizeToProp = options.dictSizeToProp;

// Re-export stateful codec contexts
pub const Compressor = compress_mod.Compressor;
pub const Decompressor = decompress_mod.Decompressor;
pub const StreamingCompressor = compress_streaming.StreamingCompressor;
pub const StreamingDecompressor = decompress_streaming.StreamingDecompressor;

// Re-export convenience one-shot functions
pub const compress = compress_mod.compress;
pub const compressInto = compress_mod.compressInto;
pub const compressBuffer = compress_mod.compressBuffer;
pub const decompress = decompress_mod.decompress;
pub const decompressInto = decompress_mod.decompressInto;
pub const decompressBuffer = decompress_mod.decompressBuffer;

// Re-export streaming I/O functions
pub const compressStream = compress_streaming.compressStream;
pub const decompressStream = decompress_streaming.decompressStream;
pub const compressStreamAlone = lzma.compressStream;
pub const decompressStreamAlone = lzma.decompressStream;

// Backward-compatibility aliases
pub const encoder = compress_mod;
pub const decoder = decompress_mod;
pub const alone = lzma.alone;

/// Calculates an upper bound on compressed buffer size for worst-case expansion.
pub fn maxCompressedSize(src_len: usize) usize {
    if (src_len == 0) return 1;
    // Each 64 KiB chunk can add 3 bytes header + 1 EOF byte at the end
    const num_chunks = (src_len + CHUNK_PACK_MAX - 1) / CHUNK_PACK_MAX;
    return src_len + (num_chunks * 3) + 1;
}

/// Inspects whether the provided byte slice begins with a valid LZMA2 control byte.
/// A valid non-empty LZMA2 stream must start with an uncompressed chunk that resets
/// the dictionary (0x01), an LZMA chunk that resets the dictionary (0xE0..0xFF),
/// or an empty stream marker (0x00).
pub fn isLzma2Stream(data: []const u8) bool {
    if (data.len == 0) return false;
    const first = data[0];
    if (first == 0) return true; // Empty stream EOF
    if (first == 1) return true; // Copy chunk with dictionary reset
    if ((first & 0xE0) == 0xE0) return true; // LZMA chunk mode 3 (reset dict + state + props)
    return false;
}

test {
    _ = @import("compress/lzma2.zig");
    _ = @import("decompress/lzma2.zig");
    _ = @import("compress/streaming.zig");
    _ = @import("decompress/streaming.zig");
}

test "lzma2: empty input roundtrip" {
    const empty: []const u8 = "";
    const compressed = try compress(std.testing.allocator, empty, .{});
    defer std.testing.allocator.free(compressed);

    try std.testing.expectEqual(@as(usize, 1), compressed.len);
    try std.testing.expectEqual(@as(u8, 0), compressed[0]);

    const decompressed = try decompress(std.testing.allocator, compressed, .{});
    defer std.testing.allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, empty, decompressed);
}

test "lzma2: single byte roundtrip" {
    const input: []const u8 = "Z";
    const compressed = try compress(std.testing.allocator, input, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompress(std.testing.allocator, compressed, .{});
    defer std.testing.allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, input, decompressed);
}

test "lzma2: short string roundtrip" {
    const input: []const u8 = "Hello, World! Native Zig LZMA2 compression codec.";
    const compressed = try compress(std.testing.allocator, input, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompress(std.testing.allocator, compressed, .{});
    defer std.testing.allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, input, decompressed);
}

test "lzma2: repeated bytes roundtrip" {
    var input: [4096]u8 = undefined;
    @memset(&input, 'B');

    const compressed = try compress(std.testing.allocator, &input, .{});
    defer std.testing.allocator.free(compressed);

    try std.testing.expect(compressed.len < input.len / 10);

    const decompressed = try decompress(std.testing.allocator, compressed, .{});
    defer std.testing.allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, &input, decompressed);
}

test "lzma2: multi-chunk input (> 64 KiB)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const size = 100 * 1024; // 100 KiB
    const large_input = try alloc.alloc(u8, size);
    for (large_input, 0..) |*b, i| {
        b.* = @truncate(i % 251);
    }

    const compressed = try compress(alloc, large_input, .{});
    const decompressed = try decompress(alloc, compressed, .{});

    try std.testing.expectEqualSlices(u8, large_input, decompressed);
}

test "lzma2: incompressible pseudo-random data" {
    var prng = std.Random.DefaultPrng.init(0xCAFE);
    var rand_buf: [8192]u8 = undefined;
    prng.random().bytes(&rand_buf);

    const compressed = try compress(std.testing.allocator, &rand_buf, .{});
    defer std.testing.allocator.free(compressed);

    const decompressed = try decompress(std.testing.allocator, compressed, .{});
    defer std.testing.allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, &rand_buf, decompressed);
}

test "lzma2: caller-buffer zero allocation roundtrip" {
    const message = "Zero-allocation stack buffer test for LZMA2 codec.";
    var comp_buf: [256]u8 = undefined;
    const comp_len = try compressInto(&comp_buf, message, .{});

    var decomp_buf: [256]u8 = undefined;
    const decomp_len = try decompressInto(&decomp_buf, comp_buf[0..comp_len], .{});

    try std.testing.expectEqualSlices(u8, message, decomp_buf[0..decomp_len]);
}

test "lzma2: reusable context roundtrip" {
    var comp = try Compressor.init(std.testing.allocator, .{});
    defer comp.deinit();

    var decomp = Decompressor.init(.{});

    const msgs = [_][]const u8{
        "First reusable stream message payload.",
        "Second reusable stream message with distinct words.",
        "Third stream with repeated patterns 1234567890 1234567890.",
    };

    for (msgs) |msg| {
        const c = try comp.compressAlloc(msg);
        defer std.testing.allocator.free(c);

        const d = try decomp.decompressAlloc(std.testing.allocator, c);
        defer std.testing.allocator.free(d);

        try std.testing.expectEqualSlices(u8, msg, d);
    }
}

test "lzma2: isLzma2Stream header detection" {
    try std.testing.expect(isLzma2Stream(&[_]u8{0x00}));
    try std.testing.expect(isLzma2Stream(&[_]u8{0x01}));
    try std.testing.expect(isLzma2Stream(&[_]u8{0xE0}));
    try std.testing.expect(!isLzma2Stream(&[_]u8{0x02}));
    try std.testing.expect(!isLzma2Stream(&[_]u8{0x55}));
    try std.testing.expect(!isLzma2Stream(&[_]u8{}));
}

test "lzma2: maxCompressedSize bound" {
    try std.testing.expectEqual(@as(usize, 1), maxCompressedSize(0));
    try std.testing.expect(maxCompressedSize(100) > 100);
}

test "lzma2: interoperability with upstream XZ raw LZMA compressed chunk vector" {
    const xz_vector2 = [_]u8{
        0xE0, 0x05, 0x2C, 0x00, 0x41, 0x5D, 0x00, 0x20, 0x9B, 0x8A, 0x86, 0xAB,
        0x18, 0xDB, 0x39, 0x3F, 0xAC, 0x23, 0xDE, 0xF6, 0x31, 0x5D, 0xFD, 0x68,
        0x64, 0x91, 0xB8, 0x07, 0xB5, 0xAB, 0xD4, 0x58, 0x4C, 0xF3, 0xFC, 0x43,
        0x8F, 0xCB, 0xBA, 0x41, 0x23, 0x32, 0x7C, 0xF4, 0x17, 0xD8, 0x17, 0x6A,
        0xA0, 0xDC, 0xFC, 0x67, 0xBF, 0xE3, 0x48, 0x7C, 0xA9, 0x93, 0x23, 0x68,
        0xD2, 0x4C, 0x27, 0xFB, 0x3F, 0xAA, 0x16, 0xC6, 0x47, 0x60, 0xDC, 0x00,
        0x00,
    };

    var expected_buf: [1325]u8 = undefined;
    const phrase = "Antigravity LZMA2 Native Zig Interoperability Check! ";
    for (0..25) |i| @memcpy(expected_buf[i * phrase.len .. (i + 1) * phrase.len], phrase);

    const decompressed = try decompress(std.testing.allocator, &xz_vector2, .{});
    defer std.testing.allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, &expected_buf, decompressed);
}

test "lzma2: legacy alone container file roundtrip" {
    const text = "Checking legacy .lzma file format container roundtrip through root package export.";
    const comp = try alone.compress(std.testing.allocator, text, .{});
    defer std.testing.allocator.free(comp);

    const decomp = try alone.decompress(std.testing.allocator, comp, .{});
    defer std.testing.allocator.free(decomp);

    try std.testing.expectEqualSlices(u8, text, decomp);
}

test "lzma2: raw lzma codec roundtrip" {
    const text = "Checking raw lzma stream codec roundtrip without any container headers.";
    const comp = try lzma.compressRaw(std.testing.allocator, text, .{ .write_end_mark = true });
    defer std.testing.allocator.free(comp);

    const decomp = try lzma.decompressRaw(std.testing.allocator, comp, .{ .uncompressed_size = null });
    defer std.testing.allocator.free(decomp);

    try std.testing.expectEqualSlices(u8, text, decomp);
}

test "architecture: width-sensitive arithmetic and boundary regression tests" {
    // 1. RangeEncoder normalization with large low_u32 (no shift overflow in shiftLow)
    var re = range_codec.RangeEncoder.init(std.testing.allocator);
    defer re.deinit();
    re.low = 0xF0E0D0C0B0A09080;
    var prob: u16 = 1024;
    try re.encodeBit(&prob, 1);
    re.range = 0x00000001; // trigger normalization
    try re.encodeBit(&prob, 0);

    // 2. PosSlot calculation for boundary distances (0, 1, 2, 3, 4, 2^30 - 1, 2^31 - 1, 2^32 - 2)
    const slot_0 = lzma.state.getPosSlot(0);
    const slot_1 = lzma.state.getPosSlot(1);
    const slot_max31 = lzma.state.getPosSlot(0x7FFFFFFF);
    const slot_max32 = lzma.state.getPosSlot(0xFFFFFFFE);
    try std.testing.expectEqual(@as(u32, 0), slot_0);
    try std.testing.expectEqual(@as(u32, 1), slot_1);
    try std.testing.expectEqual(@as(u32, 61), slot_max31);
    try std.testing.expectEqual(@as(u32, 63), slot_max32);

    // 3. MatchFinder boundary pos (pos >= maxInt(u32) - 1 safely returns no match)
    var mf = try match_finder.MatchFinder.init(std.testing.allocator, 1024 * 1024, 32);
    defer mf.deinit();
    const dummy_data = "Hello world boundary test";
    const m_boundary = mf.findMatch(dummy_data, std.math.maxInt(u32) - 1);
    try std.testing.expectEqual(@as(u32, 0), m_boundary.len);
    try std.testing.expectEqual(@as(u32, 0), m_boundary.dist);

    // 4. Safe rejection of uncompressed_size > maxInt(usize) in legacy .lzma
    var malformed_hdr: [13]u8 = undefined;
    malformed_hdr[0] = 0x5D; // lc=3, lp=0, pb=2
    std.mem.writeInt(u32, malformed_hdr[1..5], 1024 * 1024, .little);
    // Uncompressed size = 0x7FFFFFFFFFFFFFFF (exceeds 32-bit address space)
    std.mem.writeInt(u64, malformed_hdr[5..13], 0x7FFFFFFFFFFFFFFF, .little);

    var dummy_stream: [18]u8 = undefined;
    @memcpy(dummy_stream[0..13], &malformed_hdr);
    @memset(dummy_stream[13..18], 0);

    const decomp_res = alone.decompress(std.testing.allocator, &dummy_stream, .{ .max_output_size = 1024 });
    try std.testing.expectError(error.ExceededSizeLimit, decomp_res);

    // 5. Safe handling of corrupted/overflow chunk sizes in LZMA2
    const corrupt_uncompressed_chunk = [_]u8{ 0x01, 0xFF, 0xFF, 0xAA }; // Claims 65536 bytes, only 1 byte payload
    try std.testing.expectError(error.UnexpectedEof, decompress(std.testing.allocator, &corrupt_uncompressed_chunk, .{}));

    // 6. Safe rejection of invalid LZMA2 control byte
    const invalid_ctrl = [_]u8{ 0x05, 0x00, 0x00 };
    try std.testing.expectError(error.InvalidControlByte, decompress(std.testing.allocator, &invalid_ctrl, .{}));

    // 7. Missing dictionary reset rejection
    const no_reset_ctrl = [_]u8{ 0x02, 0x00, 0x00, 0x00 }; // Copy without dictionary reset on fresh stream
    try std.testing.expectError(error.DictionaryResetExpected, decompress(std.testing.allocator, &no_reset_ctrl, .{}));

    // 8. Caller buffer exhaustion
    var tiny_dest: [2]u8 = undefined;
    const sample = "Compressed text longer than 2 bytes";
    const comp_sample = try compress(std.testing.allocator, sample, .{});
    defer std.testing.allocator.free(comp_sample);
    try std.testing.expectError(error.OutputTooSmall, decompressInto(&tiny_dest, comp_sample, .{}));
}

test "adversarial: fuzzing and malformed stream resilience" {
    const text = "Testing adversarial fuzzing and malformed input handling in pure native Zig LZMA2 and LZMA.";
    const comp_lzma2 = try compress(std.testing.allocator, text, .{});
    defer std.testing.allocator.free(comp_lzma2);

    const comp_alone = try alone.compress(std.testing.allocator, text, .{});
    defer std.testing.allocator.free(comp_alone);

    const comp_raw = try lzma.compressRaw(std.testing.allocator, text, .{ .write_end_mark = true });
    defer std.testing.allocator.free(comp_raw);

    // 1. Truncated inputs: every single prefix must safely return an error without panicking
    for (0..comp_lzma2.len - 1) |i| {
        const res = decompress(std.testing.allocator, comp_lzma2[0..i], .{});
        if (res) |d| {
            std.testing.allocator.free(d);
        } else |_| {}
    }

    for (0..comp_alone.len - 1) |i| {
        const res = alone.decompress(std.testing.allocator, comp_alone[0..i], .{});
        if (res) |d| {
            std.testing.allocator.free(d);
        } else |_| {}
    }

    for (0..comp_raw.len - 1) |i| {
        const res = lzma.decompressRaw(std.testing.allocator, comp_raw[0..i], .{ .uncompressed_size = null });
        if (res) |d| {
            std.testing.allocator.free(d);
        } else |_| {}
    }

    // 2. Pseudo-random fuzzing (100 iterations of random garbage inputs)
    var prng = std.Random.DefaultPrng.init(0x12345678);
    const rand = prng.random();
    var random_buf: [256]u8 = undefined;

    for (0..100) |_| {
        const len = rand.uintLessThan(usize, random_buf.len) + 1;
        rand.bytes(random_buf[0..len]);

        const r1 = decompress(std.testing.allocator, random_buf[0..len], .{});
        if (r1) |d| std.testing.allocator.free(d) else |_| {}

        const r2 = alone.decompress(std.testing.allocator, random_buf[0..len], .{});
        if (r2) |d| std.testing.allocator.free(d) else |_| {}

        const r3 = lzma.decompressRaw(std.testing.allocator, random_buf[0..len], .{ .uncompressed_size = null });
        if (r3) |d| std.testing.allocator.free(d) else |_| {}

        var sd = streaming.StreamingDecompressor.init(std.testing.allocator, .{});
        defer sd.deinit();
        _ = sd.feed(random_buf[0..len]) catch {};
    }

    // 3. Bit mutation fuzzing on valid LZMA2 stream
    var mutated: [512]u8 = undefined;
    if (comp_lzma2.len <= mutated.len) {
        @memcpy(mutated[0..comp_lzma2.len], comp_lzma2);
        for (0..comp_lzma2.len) |byte_idx| {
            mutated[byte_idx] ^= 0x55;
            const r = decompress(std.testing.allocator, mutated[0..comp_lzma2.len], .{});
            if (r) |d| std.testing.allocator.free(d) else |_| {}
            mutated[byte_idx] ^= 0x55; // restore
        }
    }
}

test "lzma2: comprehensive 14-fixture roundtrip regression suite" {
    const allocator = std.testing.allocator;

    // 1. Empty (0 B)
    {
        const comp = try compress(allocator, "", .{});
        defer allocator.free(comp);
        const decomp = try decompress(allocator, comp, .{});
        defer allocator.free(decomp);
        try std.testing.expectEqualSlices(u8, "", decomp);

        const comp_a = try alone.compress(allocator, "", .{});
        defer allocator.free(comp_a);
        const decomp_a = try alone.decompress(allocator, comp_a, .{});
        defer allocator.free(decomp_a);
        try std.testing.expectEqualSlices(u8, "", decomp_a);
    }

    // 2. 1-byte
    {
        const data = "X";
        const comp = try compress(allocator, data, .{});
        defer allocator.free(comp);
        const decomp = try decompress(allocator, comp, .{});
        defer allocator.free(decomp);
        try std.testing.expectEqualSlices(u8, data, decomp);

        const comp_a = try alone.compress(allocator, data, .{});
        defer allocator.free(comp_a);
        const decomp_a = try alone.decompress(allocator, comp_a, .{});
        defer allocator.free(decomp_a);
        try std.testing.expectEqualSlices(u8, data, decomp_a);
    }

    // 3. Very short (5 B)
    {
        const data = "Hello";
        const comp = try compress(allocator, data, .{});
        defer allocator.free(comp);
        const decomp = try decompress(allocator, comp, .{});
        defer allocator.free(decomp);
        try std.testing.expectEqualSlices(u8, data, decomp);
    }

    // 4. Repeated 'A' (4 KiB)
    {
        const buf = try allocator.alloc(u8, 4096);
        defer allocator.free(buf);
        @memset(buf, 'A');
        const comp = try compress(allocator, buf, .{});
        defer allocator.free(comp);
        const decomp = try decompress(allocator, comp, .{});
        defer allocator.free(decomp);
        try std.testing.expectEqualSlices(u8, buf, decomp);
    }

    // 5. Pattern loop (8 KiB)
    {
        const pattern = "1234567890abcdefghijklmnopqrstuvwxyz!";
        const buf = try allocator.alloc(u8, 8192);
        defer allocator.free(buf);
        for (0..buf.len) |i| buf[i] = pattern[i % pattern.len];
        const comp = try compress(allocator, buf, .{});
        defer allocator.free(comp);
        const decomp = try decompress(allocator, comp, .{});
        defer allocator.free(decomp);
        try std.testing.expectEqualSlices(u8, buf, decomp);
    }

    // 6. Natural text (~2 KiB)
    {
        const text =
            "Four score and seven years ago our fathers brought forth on this continent, a new nation, " ++
            "conceived in Liberty, and dedicated to the proposition that all men are created equal. " ++
            "Now we are engaged in a great civil war, testing whether that nation, or any nation so conceived " ++
            "and so dedicated, can long endure. We are met on a great battle-field of that war. We have come to " ++
            "dedicate a portion of that field, as a final resting place for those who here gave their lives that " ++
            "that nation might live. It is altogether fitting and proper that we should do this. But, in a larger sense, " ++
            "we can not dedicate -- we can not consecrate -- we can not hallow -- this ground. The brave men, living " ++
            "and dead, who struggled here, have consecrated it, far above our poor power to add or detract.";
        var list = std.ArrayList(u8).empty;
        defer list.deinit(allocator);
        for (0..3) |_| try list.appendSlice(allocator, text);
        const comp = try compress(allocator, list.items, .{});
        defer allocator.free(comp);
        const decomp = try decompress(allocator, comp, .{});
        defer allocator.free(decomp);
        try std.testing.expectEqualSlices(u8, list.items, decomp);
    }

    // 7. Source code (~16 KiB)
    {
        const text = "pub fn compress(allocator: std.mem.Allocator, src: []const u8) ![]u8 { var enc = try Encoder.init(allocator, .{}); return enc.compressAlloc(src); }\n";
        var list = std.ArrayList(u8).empty;
        defer list.deinit(allocator);
        for (0..45) |i| {
            try list.appendSlice(allocator, text);
            var num_buf: [16]u8 = undefined;
            const s = std.fmt.bufPrint(&num_buf, "// var {d}\n", .{i}) catch unreachable;
            try list.appendSlice(allocator, s);
        }
        const comp = try compress(allocator, list.items, .{});
        defer allocator.free(comp);
        const decomp = try decompress(allocator, comp, .{});
        defer allocator.free(decomp);
        try std.testing.expectEqualSlices(u8, list.items, decomp);
    }

    // 8. JSON structured (~6 KiB)
    {
        var list = std.ArrayList(u8).empty;
        defer list.deinit(allocator);
        try list.appendSlice(allocator, "{\"users\":[");
        for (0..50) |i| {
            var b: [128]u8 = undefined;
            const s = std.fmt.bufPrint(&b, "{{\"id\":{d},\"name\":\"User_{d}\",\"active\":{s}}},", .{ i, i, if (i % 2 == 0) "true" else "false" }) catch unreachable;
            try list.appendSlice(allocator, s);
        }
        try list.appendSlice(allocator, "]}");
        const comp = try compress(allocator, list.items, .{});
        defer allocator.free(comp);
        const decomp = try decompress(allocator, comp, .{});
        defer allocator.free(decomp);
        try std.testing.expectEqualSlices(u8, list.items, decomp);
    }

    // 9. HTML markup (~6 KiB)
    {
        const html = "<!DOCTYPE html><html><head><title>Title</title></head><body><div class=\"container\"><p>Paragraph content</p></div></body></html>\n";
        var list = std.ArrayList(u8).empty;
        defer list.deinit(allocator);
        for (0..35) |_| try list.appendSlice(allocator, html);
        const comp = try compress(allocator, list.items, .{});
        defer allocator.free(comp);
        const decomp = try decompress(allocator, comp, .{});
        defer allocator.free(decomp);
        try std.testing.expectEqualSlices(u8, list.items, decomp);
    }

    // 10. Random binary (32 KiB)
    {
        var prng = std.Random.DefaultPrng.init(0xCAFEBABE);
        const buf = try allocator.alloc(u8, 32768);
        defer allocator.free(buf);
        prng.random().bytes(buf);
        const comp = try compress(allocator, buf, .{});
        defer allocator.free(comp);
        const decomp = try decompress(allocator, comp, .{});
        defer allocator.free(decomp);
        try std.testing.expectEqualSlices(u8, buf, decomp);
    }

    // 11. Sparse binary (32 KiB)
    {
        const buf = try allocator.alloc(u8, 32768);
        defer allocator.free(buf);
        @memset(buf, 0);
        for (0..buf.len / 64) |i| buf[i * 64] = @truncate(i);
        const comp = try compress(allocator, buf, .{});
        defer allocator.free(comp);
        const decomp = try decompress(allocator, comp, .{});
        defer allocator.free(decomp);
        try std.testing.expectEqualSlices(u8, buf, decomp);
    }

    // 12. Boundary: exactly 65,536 bytes (1 chunk boundary)
    {
        const buf = try allocator.alloc(u8, 65536);
        defer allocator.free(buf);
        for (0..buf.len) |i| buf[i] = @truncate(i * 3 + (i >> 8));
        const comp = try compress(allocator, buf, .{});
        defer allocator.free(comp);
        const decomp = try decompress(allocator, comp, .{});
        defer allocator.free(decomp);
        try std.testing.expectEqualSlices(u8, buf, decomp);
    }

    // 13. Boundary: 65,537 bytes (forces 2 chunks in LZMA2)
    {
        const buf = try allocator.alloc(u8, 65537);
        defer allocator.free(buf);
        for (0..buf.len) |i| buf[i] = @truncate(i * 5 + (i >> 7));
        const comp = try compress(allocator, buf, .{});
        defer allocator.free(comp);
        const decomp = try decompress(allocator, comp, .{});
        defer allocator.free(decomp);
        try std.testing.expectEqualSlices(u8, buf, decomp);
    }

    // 14. Multi-chunk (128 KiB)
    {
        const buf = try allocator.alloc(u8, 131072);
        defer allocator.free(buf);
        for (0..buf.len) |i| buf[i] = @truncate(i ^ (i >> 4));
        const comp = try compress(allocator, buf, .{});
        defer allocator.free(comp);
        const decomp = try decompress(allocator, comp, .{});
        defer allocator.free(decomp);
        try std.testing.expectEqualSlices(u8, buf, decomp);
    }
}
