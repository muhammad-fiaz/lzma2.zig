//! Legacy `.lzma` (LZMA-Alone) File Container Compressor.
//!
//! Encodes data into the classic 13-byte header format:
//! - 1 byte properties: `(pb * 5 + lp) * 9 + lc`
//! - 4 bytes dictionary size (little-endian u32)
//! - 8 bytes uncompressed size (little-endian u64, or 0xFFFFFFFFFFFFFFFF if unknown)
//! followed by the raw range-encoded LZMA stream payload.

const std = @import("std");
const errors = @import("../utils/errors.zig");
const options_mod = @import("../utils/options.zig");
const lzma_comp = @import("lzma.zig");

pub const Header = options_mod.AloneHeader;
pub const Options = options_mod.AloneOptions;

/// Compresses data into the legacy `.lzma` file container format.
pub fn compress(allocator: std.mem.Allocator, src: []const u8, options: Options) errors.CompressError![]u8 {
    var opts = options;
    if (opts.uncompressed_size == null and !opts.unknown_size) {
        opts.uncompressed_size = src.len;
    }
    const lzma_opts = opts.toLzmaOptions();
    try lzma_opts.validate();

    const raw_compressed = try lzma_comp.compressRaw(allocator, src, lzma_opts);
    defer allocator.free(raw_compressed);

    const out = try allocator.alloc(u8, Header.SIZE + raw_compressed.len);
    errdefer allocator.free(out);

    const hdr = Header{
        .lc = lzma_opts.lc,
        .lp = lzma_opts.lp,
        .pb = lzma_opts.pb,
        .dict_size = lzma_opts.getDictSize(),
        .uncompressed_size = if (opts.unknown_size) null else opts.uncompressed_size,
    };
    hdr.encodeSlice(out[0..Header.SIZE]);
    @memcpy(out[Header.SIZE..], raw_compressed);

    return out;
}

/// Zero-allocation legacy `.lzma` compression into a caller-provided destination buffer.
pub fn compressInto(dest: []u8, src: []const u8, options: Options) errors.CompressError!usize {
    if (dest.len < Header.SIZE) return error.OutputTooSmall;

    var opts = options;
    if (opts.uncompressed_size == null and !opts.unknown_size) {
        opts.uncompressed_size = src.len;
    }
    const lzma_opts = opts.toLzmaOptions();
    try lzma_opts.validate();

    const hdr = Header{
        .lc = lzma_opts.lc,
        .lp = lzma_opts.lp,
        .pb = lzma_opts.pb,
        .dict_size = lzma_opts.getDictSize(),
        .uncompressed_size = if (opts.unknown_size) null else opts.uncompressed_size,
    };
    hdr.encodeSlice(dest[0..Header.SIZE]);

    const payload_len = try lzma_comp.compressRawInto(dest[Header.SIZE..], src, lzma_opts);
    return Header.SIZE + payload_len;
}

/// Convenience alias for compressInto.
pub const compressBuffer = compressInto;

/// Streaming legacy .lzma compression from reader to writer.
pub fn compressStream(
    allocator: std.mem.Allocator,
    reader: anytype,
    writer: anytype,
    options: Options,
) errors.CompressError!void {
    var in_data: std.ArrayList(u8) = .empty;
    defer in_data.deinit(allocator);

    var buf: [65536]u8 = undefined;
    while (true) {
        const n = reader.read(&buf) catch return error.OutputTooSmall;
        if (n == 0) break;
        in_data.appendSlice(allocator, buf[0..n]) catch return error.OutOfMemory;
    }

    const compressed = try compress(allocator, in_data.items, options);
    defer allocator.free(compressed);

    writer.writeAll(compressed) catch return error.OutputTooSmall;
}

test "container compressor: basic .lzma encoding" {
    const allocator = std.testing.allocator;
    const msg = "Legacy .lzma container compression test in Zig!";
    const comp = try compress(allocator, msg, .{});
    defer allocator.free(comp);

    try std.testing.expect(comp.len >= Header.SIZE);
    const hdr = try Header.decodeSlice(comp[0..Header.SIZE]);
    try std.testing.expectEqual(@as(?u64, msg.len), hdr.uncompressed_size);
}

test "container compressor: compressInto buffer" {
    const msg = "Caller-buffer legacy .lzma compression test.";
    var buf: [512]u8 = undefined;
    const len = try compressInto(&buf, msg, .{});
    try std.testing.expect(len >= Header.SIZE);
}

test "container compressor: empty and tiny input regression tests" {
    const allocator = std.testing.allocator;
    const decompress_mod = @import("../decompress/container.zig");

    // Case 1: Empty input (0 bytes)
    // - Default (known size, no EOS): 13-byte header + 5-byte range flush = 18 bytes (7-Zip C parity)
    const empty_no_eos = try compress(allocator, "", .{});
    defer allocator.free(empty_no_eos);
    try std.testing.expectEqual(@as(usize, 18), empty_no_eos.len);
    const dec_empty_1 = try decompress_mod.decompress(allocator, empty_no_eos, .{});
    defer allocator.free(dec_empty_1);
    try std.testing.expectEqual(@as(usize, 0), dec_empty_1.len);

    // - With EOS / unknown size: 13-byte header + 10-byte payload with EOS = 23 bytes (XZ Utils parity)
    const empty_eos = try compress(allocator, "", .{ .unknown_size = true });
    defer allocator.free(empty_eos);
    try std.testing.expectEqual(@as(usize, 23), empty_eos.len);
    const dec_empty_2 = try decompress_mod.decompress(allocator, empty_eos, .{});
    defer allocator.free(dec_empty_2);
    try std.testing.expectEqual(@as(usize, 0), dec_empty_2.len);

    // Case 2: One byte input (1 byte)
    // - Default: 19 bytes (7-Zip C parity)
    const one_no_eos = try compress(allocator, "X", .{});
    defer allocator.free(one_no_eos);
    try std.testing.expectEqual(@as(usize, 19), one_no_eos.len);
    const dec_one_1 = try decompress_mod.decompress(allocator, one_no_eos, .{});
    defer allocator.free(dec_one_1);
    try std.testing.expectEqualStrings("X", dec_one_1);

    // - With EOS: 24 bytes (XZ Utils parity)
    const one_eos = try compress(allocator, "X", .{ .unknown_size = true });
    defer allocator.free(one_eos);
    try std.testing.expectEqual(@as(usize, 24), one_eos.len);
    const dec_one_2 = try decompress_mod.decompress(allocator, one_eos, .{});
    defer allocator.free(dec_one_2);
    try std.testing.expectEqualStrings("X", dec_one_2);

    // Case 3: Five bytes input (5 bytes)
    // - Default: 22 bytes (7-Zip C parity)
    const five_no_eos = try compress(allocator, "Hello", .{});
    defer allocator.free(five_no_eos);
    try std.testing.expectEqual(@as(usize, 22), five_no_eos.len);
    const dec_five_1 = try decompress_mod.decompress(allocator, five_no_eos, .{});
    defer allocator.free(dec_five_1);
    try std.testing.expectEqualStrings("Hello", dec_five_1);

    // - With EOS: 28 bytes (XZ Utils parity)
    const five_eos = try compress(allocator, "Hello", .{ .unknown_size = true });
    defer allocator.free(five_eos);
    try std.testing.expectEqual(@as(usize, 28), five_eos.len);
    const dec_five_2 = try decompress_mod.decompress(allocator, five_eos, .{});
    defer allocator.free(dec_five_2);
    try std.testing.expectEqualStrings("Hello", dec_five_2);
}
