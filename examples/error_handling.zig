//! Error handling example showing how to detect and handle corrupted inputs,
//! insufficient buffers, invalid headers, and decompression limit violations.

const std = @import("std");
const lzma2 = @import("lzma2");
const lzma = @import("lzma");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    // 1. Handling corrupted or invalid LZMA2 stream control byte
    const invalid_stream = [_]u8{ 0x05, 0x12, 0x34 }; // 0x05 is invalid LZMA2 control byte
    std.debug.print("1. Attempting to decompress invalid control byte 0x05...\n", .{});
    const res1 = lzma2.decompress(allocator, &invalid_stream, .{});
    if (res1) |_| {
        std.debug.print("Unexpected success on invalid stream!\n", .{});
    } else |err| {
        std.debug.print("   Correctly caught error: {s}\n", .{@errorName(err)});
    }

    // 2. Handling decompression safety limit (zip bomb protection)
    const large_string =
        "Repeat pattern for decompression bomb test. " ++
        "Repeat pattern for decompression bomb test. " ++
        "Repeat pattern for decompression bomb test. " ++
        "Repeat pattern for decompression bomb test. " ++
        "Repeat pattern for decompression bomb test. " ++
        "Repeat pattern for decompression bomb test. ";
    const comp = try lzma2.compress(allocator, large_string, .{});
    defer allocator.free(comp);

    std.debug.print("\n2. Attempting decompression with 100-byte output safety limit...\n", .{});
    const res2 = lzma2.decompress(allocator, comp, .{ .max_output_size = 100 });
    if (res2) |_| {
        std.debug.print("Unexpected success exceeding limit!\n", .{});
    } else |err| {
        std.debug.print("   Correctly caught error: {s}\n", .{@errorName(err)});
    }

    // 3. Handling caller buffer overflow
    var small_buf: [16]u8 = undefined;
    std.debug.print("\n3. Attempting to compress into undersized buffer (16 bytes)...\n", .{});
    const res3 = lzma2.compressInto(&small_buf, large_string, .{});
    if (res3) |_| {
        std.debug.print("Unexpected success with small buffer!\n", .{});
    } else |err| {
        std.debug.print("   Correctly caught error: {s}\n", .{@errorName(err)});
    }

    // 4. Handling corrupt legacy .lzma header (invalid properties byte > 225)
    var corrupt_alone: [13]u8 = @splat(0);
    corrupt_alone[0] = 230; // 230 >= 225 is an invalid property byte
    std.debug.print("\n4. Attempting to decompress .lzma container with corrupt property byte (230)...\n", .{});
    const res4 = lzma.decompress(allocator, &corrupt_alone, .{});
    if (res4) |_| {
        std.debug.print("Unexpected success with corrupt header!\n", .{});
    } else |err| {
        std.debug.print("   Correctly caught error: {s}\n", .{@errorName(err)});
    }
}
