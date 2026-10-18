//! Zero-allocation compression and decompression using caller-provided buffers.
//!
//! Demonstrates caller-provided stack buffer operations for:
//! 1. Modern LZMA2 streams (`lzma2.compressInto` / `lzma2.decompressInto`)
//! 2. Legacy `.lzma` container files (`lzma.compressInto` / `lzma.decompressInto`)
//! 3. Raw LZMA streams (`lzma.compressRawInto` / `lzma.decompressRawInto`)

const std = @import("std");
const lzma2 = @import("lzma2");
const lzma = @import("lzma");

pub fn main() !void {
    const message = "High performance zero-allocation embedded compression using caller-provided buffers.";
    std.debug.print("Input message ({d} bytes): \"{s}\"\n\n", .{ message.len, message });

    // Static stack buffers for embedded or latency-critical applications
    var comp_buf: [512]u8 = undefined;
    var decomp_buf: [512]u8 = undefined;

    // 1. LZMA2 zero-allocation roundtrip
    std.debug.print("1. LZMA2 Caller Buffer\n", .{});
    const lzma2_comp_size = try lzma2.compressInto(&comp_buf, message, .{ .level = 1 });
    std.debug.print("LZMA2 compressed into buffer: {d} bytes\n", .{lzma2_comp_size});

    const lzma2_decomp_size = try lzma2.decompressInto(&decomp_buf, comp_buf[0..lzma2_comp_size], .{});
    std.debug.print("LZMA2 decompressed from buffer: {d} bytes\n", .{lzma2_decomp_size});

    if (!std.mem.eql(u8, message, decomp_buf[0..lzma2_decomp_size])) return error.VerificationFailed;
    std.debug.print("LZMA2 caller-buffer check: PASS\n\n", .{});

    // 2. Legacy .lzma container zero-allocation roundtrip
    std.debug.print("2. Legacy .lzma Caller Buffer\n", .{});
    const alone_comp_size = try lzma.compressInto(&comp_buf, message, .{ .level = 1 });
    std.debug.print("Legacy .lzma compressed into buffer: {d} bytes\n", .{alone_comp_size});

    const alone_decomp_size = try lzma.decompressInto(&decomp_buf, comp_buf[0..alone_comp_size], .{});
    std.debug.print("Legacy .lzma decompressed from buffer: {d} bytes\n", .{alone_decomp_size});

    if (!std.mem.eql(u8, message, decomp_buf[0..alone_decomp_size])) return error.VerificationFailed;
    std.debug.print("Legacy .lzma caller-buffer check: PASS\n\n", .{});

    // 3. Raw LZMA zero-allocation roundtrip
    std.debug.print("3. Raw LZMA Caller Buffer\n", .{});
    const raw_comp_size = try lzma.compressRawInto(&comp_buf, message, .{ .level = 1, .write_end_mark = false });
    std.debug.print("Raw LZMA compressed into buffer: {d} bytes\n", .{raw_comp_size});

    const raw_decomp_size = try lzma.decompressRawInto(&decomp_buf, comp_buf[0..raw_comp_size], .{ .uncompressed_size = message.len });
    std.debug.print("Raw LZMA decompressed from buffer: {d} bytes\n", .{raw_decomp_size});

    if (!std.mem.eql(u8, message, decomp_buf[0..raw_decomp_size])) return error.VerificationFailed;
    std.debug.print("Raw LZMA caller-buffer check: PASS\n\n", .{});

    std.debug.print("All caller-buffer operations completed successfully!\n", .{});
}
