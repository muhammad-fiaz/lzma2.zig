//! Legacy `.lzma` (LZMA-Alone) File Container Decompressor.
//!
//! Parses the classic 13-byte header:
//! - 1 byte properties: `(pb * 5 + lp) * 9 + lc`
//! - 4 bytes dictionary size
//! - 8 bytes uncompressed size
//! and restores the uncompressed payload using the raw LZMA stream decoder.

const std = @import("std");
const errors = @import("../utils/errors.zig");
const options_mod = @import("../utils/options.zig");
const lzma_decomp = @import("lzma.zig");

pub const Header = options_mod.AloneHeader;
pub const DecompressOptions = options_mod.DecompressOptions;

/// Decompresses data from a legacy `.lzma` container format.
pub fn decompress(allocator: std.mem.Allocator, src: []const u8, options: DecompressOptions) errors.DecompressError![]u8 {
    if (src.len < Header.SIZE) return error.UnexpectedEof;

    const hdr = try Header.decodeSlice(src[0..Header.SIZE]);

    if (hdr.uncompressed_size) |sz| {
        if (sz > std.math.maxInt(usize) or sz > options.max_output_size) return error.ExceededSizeLimit;
        if (sz == 0) return try allocator.alloc(u8, 0);
    }

    const decompress_opts = options_mod.LzmaDecompressOptions{
        .lc = hdr.lc,
        .lp = hdr.lp,
        .pb = hdr.pb,
        .dict_size = hdr.dict_size,
        .uncompressed_size = hdr.uncompressed_size,
        .has_end_marker = (hdr.uncompressed_size == null),
        .max_output_size = options.max_output_size,
        .dict_size_limit = options.dict_size_limit,
    };

    return lzma_decomp.decompressRaw(allocator, src[Header.SIZE..], decompress_opts);
}

/// Zero-allocation legacy `.lzma` decompression into a caller-provided destination buffer.
pub fn decompressInto(dest: []u8, src: []const u8, options: DecompressOptions) errors.DecompressError!usize {
    if (src.len < Header.SIZE) return error.UnexpectedEof;

    const hdr = try Header.decodeSlice(src[0..Header.SIZE]);

    if (hdr.uncompressed_size) |sz| {
        if (sz > std.math.maxInt(usize) or sz > options.max_output_size) return error.ExceededSizeLimit;
        if (sz > dest.len) return error.OutputTooSmall;
        if (sz == 0) return 0;
    }

    const decompress_opts = options_mod.LzmaDecompressOptions{
        .lc = hdr.lc,
        .lp = hdr.lp,
        .pb = hdr.pb,
        .dict_size = hdr.dict_size,
        .uncompressed_size = hdr.uncompressed_size,
        .has_end_marker = (hdr.uncompressed_size == null),
        .max_output_size = options.max_output_size,
        .dict_size_limit = options.dict_size_limit,
    };

    return lzma_decomp.decompressRawInto(dest, src[Header.SIZE..], decompress_opts);
}

/// Convenience alias for decompressInto.
pub const decompressBuffer = decompressInto;

/// Streaming legacy .lzma decompression from reader to writer.
pub fn decompressStream(
    allocator: std.mem.Allocator,
    reader: anytype,
    writer: anytype,
    options: options_mod.DecompressOptions,
) errors.DecompressError!void {
    var in_data: std.ArrayList(u8) = .empty;
    defer in_data.deinit(allocator);

    var buf: [65536]u8 = undefined;
    while (true) {
        const n = reader.read(&buf) catch return error.CorruptData;
        if (n == 0) break;
        in_data.appendSlice(allocator, buf[0..n]) catch return error.OutOfMemory;
    }

    const decompressed = try decompress(allocator, in_data.items, options);
    defer allocator.free(decompressed);

    writer.writeAll(decompressed) catch return error.OutputTooSmall;
}

test "container decompressor: roundtrip with container compressor" {
    const allocator = std.testing.allocator;
    const comp_mod = @import("../compress/container.zig");
    const msg = "Testing container roundtrip between compressor and decompressor!";

    const comp = try comp_mod.compress(allocator, msg, .{});
    defer allocator.free(comp);

    const decomp = try decompress(allocator, comp, .{});
    defer allocator.free(decomp);

    try std.testing.expectEqualSlices(u8, msg, decomp);
}

test "container decompressor: short header error" {
    const short_hdr = [_]u8{ 0x5D, 0x00, 0x00, 0x00 };
    try std.testing.expectError(error.UnexpectedEof, decompress(std.testing.allocator, &short_hdr, .{}));
}

test "container decompressor: invalid property byte in header" {
    // 230 >= 9*5*5 (225)
    var bad_hdr: [13]u8 = undefined;
    @memset(&bad_hdr, 0);
    bad_hdr[0] = 230;
    try std.testing.expectError(error.InvalidProperties, decompress(std.testing.allocator, &bad_hdr, .{}));
}

test "container decompressor: decompressInto caller buffer" {
    const comp_mod = @import("../compress/container.zig");
    const msg = "Testing decompressInto for legacy .lzma container.";

    const comp = try comp_mod.compress(std.testing.allocator, msg, .{});
    defer std.testing.allocator.free(comp);

    var out_buf: [256]u8 = undefined;
    const n = try decompressInto(&out_buf, comp, .{});
    try std.testing.expectEqualSlices(u8, msg, out_buf[0..n]);
}
