//! Basic compression and decompression example using lzma2.zig and lzma.zig.
//!
//! Demonstrates one-shot compression and decompression for:
//! 1. Modern LZMA2 streams (`lzma2.compress` / `lzma2.decompress`)
//! 2. Legacy `.lzma` file container format (`lzma.compress` / `lzma.decompress` or `lzma2.alone`)
//! 3. Raw LZMA stream format (`lzma.compressRaw` / `lzma.decompressRaw` or `lzma2.lzma`)

const std = @import("std");
const lzma2 = @import("lzma2");
const lzma = @import("lzma");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const original_text: []const u8 =
        "LZMA2 is a modern container format capable of containing both uncompressed " ++
        "data and LZMA compressed chunks. LZMA is the original format with a 13-byte header.";

    std.debug.print("Original data size: {d} bytes\n\n", .{original_text.len});

    // 1. Modern LZMA2 Format (@import("lzma2"))
    std.debug.print("1. Modern LZMA2 One-Shot\n", .{});
    const lzma2_compressed = try lzma2.compress(allocator, original_text, .{});
    defer allocator.free(lzma2_compressed);
    std.debug.print("LZMA2 compressed size: {d} bytes\n", .{lzma2_compressed.len});

    const lzma2_decompressed = try lzma2.decompress(allocator, lzma2_compressed, .{});
    defer allocator.free(lzma2_decompressed);

    if (!std.mem.eql(u8, original_text, lzma2_decompressed)) return error.VerificationFailed;
    std.debug.print("LZMA2 roundtrip: PASS\n\n", .{});

    // 2. Legacy .lzma Container One-Shot (@import("lzma"))
    std.debug.print("2. Legacy .lzma Container One-Shot\n", .{});
    const alone_compressed = try lzma.compress(allocator, original_text, .{});
    defer allocator.free(alone_compressed);
    std.debug.print("Legacy .lzma file size (13-byte header + stream): {d} bytes\n", .{alone_compressed.len});

    const alone_decompressed = try lzma.decompress(allocator, alone_compressed, .{});
    defer allocator.free(alone_decompressed);

    if (!std.mem.eql(u8, original_text, alone_decompressed)) return error.VerificationFailed;
    std.debug.print("Legacy .lzma roundtrip: PASS\n\n", .{});

    // 3. Raw LZMA Stream Format (Headerless)
    std.debug.print("3. Raw LZMA Stream One-Shot\n", .{});
    const raw_compressed = try lzma.compressRaw(allocator, original_text, .{ .write_end_mark = true });
    defer allocator.free(raw_compressed);
    std.debug.print("Raw LZMA stream size: {d} bytes\n", .{raw_compressed.len});

    const raw_decompressed = try lzma.decompressRaw(allocator, raw_compressed, .{ .uncompressed_size = null });
    defer allocator.free(raw_decompressed);

    if (!std.mem.eql(u8, original_text, raw_decompressed)) return error.VerificationFailed;
    std.debug.print("Raw LZMA roundtrip: PASS\n\n", .{});

    std.debug.print("All basic compression tests passed successfully!\n", .{});
}
