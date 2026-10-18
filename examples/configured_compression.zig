//! Configured compression example demonstrating dictionary size, search depth,
//! Markov literal/position properties (lc, lp, pb), and XZ property encoding.

const std = @import("std");
const lzma2 = @import("lzma2");
const lzma = @import("lzma");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    // Repetitive text representing structured logs or protocol data
    const sample_data: []const u8 =
        "timestamp=2026-10-17T19:00:00Z level=INFO service=indexer status=200 latency=1.2ms\n" ++
        "timestamp=2026-10-17T19:00:01Z level=INFO service=indexer status=200 latency=1.1ms\n" ++
        "timestamp=2026-10-17T19:00:02Z level=WARN service=indexer status=429 latency=4.8ms\n" ++
        "timestamp=2026-10-17T19:00:03Z level=INFO service=indexer status=200 latency=1.3ms\n";

    std.debug.print("Original log data size: {d} bytes\n\n", .{sample_data.len});

    // 1. Modern LZMA2 with custom options
    std.debug.print("--- 1. LZMA2 Custom Options ---\n", .{});
    const lzma2_opts = lzma2.Options{
        .level = 9, // Maximum compression
        .dict_size = 1024 * 1024, // 1 MiB sliding dictionary
        .lc = 3, // 3 literal context bits
        .lp = 0, // 0 literal position bits
        .pb = 2, // 2 position bits
        .mode = .normal, // 1-step lookahead optimal parsing
        .nice_len = 128, // Long match threshold
    };

    const compressed = try lzma2.compress(allocator, sample_data, lzma2_opts);
    defer allocator.free(compressed);
    std.debug.print("LZMA2 Level 9 (dict 1 MiB) size: {d} bytes\n", .{compressed.len});

    const decompressed = try lzma2.decompress(allocator, compressed, .{});
    defer allocator.free(decompressed);

    if (!std.mem.eql(u8, sample_data, decompressed)) return error.VerificationFailed;
    std.debug.print("LZMA2 custom options check: PASS\n\n", .{});

    // 2. Legacy .lzma with custom options (@import("lzma"))
    std.debug.print("--- 2. Legacy .lzma Custom Options ---\n", .{});
    const alone_opts = lzma.AloneOptions{
        .level = 7,
        .dict_size = 512 * 1024, // 512 KiB dictionary
        .lc = 4, // 4 literal context bits
        .lp = 0,
        .pb = 2,
    };
    const alone_comp = try lzma.compress(allocator, sample_data, alone_opts);
    defer allocator.free(alone_comp);
    std.debug.print("Legacy .lzma custom options size: {d} bytes\n", .{alone_comp.len});

    const alone_decomp = try lzma.decompress(allocator, alone_comp, .{});
    defer allocator.free(alone_decomp);

    if (!std.mem.eql(u8, sample_data, alone_decomp)) return error.VerificationFailed;
    std.debug.print("Legacy .lzma custom options check: PASS\n\n", .{});

    // 3. Demonstrate XZ-compatible dictionary property encoding
    std.debug.print("--- 3. XZ Dictionary Property Conversion ---\n", .{});
    const prop_1mb = try lzma2.dictSizeToProp(1024 * 1024);
    const decoded_size = try lzma2.propToDictSize(prop_1mb);
    std.debug.print("XZ Dict Property: 1 MiB -> property 0x{X:0>2} -> decoded {d} bytes\n", .{ prop_1mb, decoded_size });
}
