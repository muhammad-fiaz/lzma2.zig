//! Comprehensive LZMA Compression and Decompression Example using @import("lzma").
//!
//! Demonstrates:
//! 1. Legacy .lzma single-file container (LZMA-Alone format) with 13-byte header.
//! 2. Raw headerless LZMA stream encoding with EOS end-marker and known uncompressed sizes.
//! 3. Zero-allocation caller-provided buffer operations (compressInto / decompressInto).
//! 4. I/O streaming pipelines with readers and writers.

const std = @import("std");
const lzma = @import("lzma");

const MemoryReader = struct {
    slice: []const u8,
    pos: usize = 0,

    pub fn read(self: *MemoryReader, dest: []u8) !usize {
        if (self.pos >= self.slice.len) return 0;
        const n = @min(self.slice.len - self.pos, dest.len);
        @memcpy(dest[0..n], self.slice[self.pos .. self.pos + n]);
        self.pos += n;
        return n;
    }
};

const MemoryWriter = struct {
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn writeAll(self: *MemoryWriter, bytes: []const u8) !void {
        self.list.appendSlice(self.allocator, bytes) catch return error.OutOfMemory;
    }
};

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const document: []const u8 =
        "The LZMA algorithm combines LZ77 dictionary compression with range encoding " ++
        "and adaptive Markov probability trees. The standalone .lzma container wraps " ++
        "the raw bitstream with a 13-byte header encoding properties, dictionary size, " ++
        "and 64-bit uncompressed size.";

    std.debug.print("LZMA Comprehensive Example\n", .{});
    std.debug.print("Original input size: {d} bytes\n\n", .{document.len});

    // 1. Legacy .lzma Container Format (13-byte header)
    std.debug.print("1. Legacy .lzma Container (13-byte header)\n", .{});
    const container_comp = try lzma.compress(allocator, document, .{ .level = 6 });
    defer allocator.free(container_comp);
    std.debug.print("Container compressed size: {d} bytes (header 13 bytes + compressed stream)\n", .{container_comp.len});

    const parsed_header = try lzma.AloneHeader.decode(container_comp[0..13]);
    std.debug.print("Parsed header: dict_size={d} bytes, uncompressed_size={?d}, props=0x{X:0>2}\n", .{
        parsed_header.dict_size,
        parsed_header.uncompressed_size,
        parsed_header.getPropsByte(),
    });

    const container_decomp = try lzma.decompress(allocator, container_comp, .{});
    defer allocator.free(container_decomp);
    if (!std.mem.eql(u8, document, container_decomp)) return error.VerificationFailed;
    std.debug.print("Container roundtrip: PASS\n\n", .{});

    // 2. Raw LZMA Stream (No header, with EOS marker)
    std.debug.print("2. Raw Headerless LZMA Stream (EOS marker)\n", .{});
    const raw_eos = try lzma.compressRaw(allocator, document, .{ .write_end_mark = true });
    defer allocator.free(raw_eos);
    std.debug.print("Raw stream with EOS marker size: {d} bytes\n", .{raw_eos.len});

    const raw_eos_decomp = try lzma.decompressRaw(allocator, raw_eos, .{ .uncompressed_size = null });
    defer allocator.free(raw_eos_decomp);
    if (!std.mem.eql(u8, document, raw_eos_decomp)) return error.VerificationFailed;
    std.debug.print("Raw stream (EOS) roundtrip: PASS\n\n", .{});

    // 3. Raw LZMA Stream (No header, known uncompressed size, no EOS)
    std.debug.print("3. Raw Headerless LZMA Stream (Known size, no EOS)\n", .{});
    const raw_no_eos = try lzma.compressRaw(allocator, document, .{ .write_end_mark = false });
    defer allocator.free(raw_no_eos);
    std.debug.print("Raw stream without EOS size: {d} bytes (saved ~6 bytes EOS marker)\n", .{raw_no_eos.len});

    const raw_no_eos_decomp = try lzma.decompressRaw(allocator, raw_no_eos, .{ .uncompressed_size = document.len });
    defer allocator.free(raw_no_eos_decomp);
    if (!std.mem.eql(u8, document, raw_no_eos_decomp)) return error.VerificationFailed;
    std.debug.print("Raw stream (Known size) roundtrip: PASS\n\n", .{});

    // 4. Zero-Allocation Caller Buffer Operations
    std.debug.print("4. Zero-Allocation Caller Buffers\n", .{});
    var comp_buffer: [1024]u8 = undefined;
    var decomp_buffer: [1024]u8 = undefined;

    const enc_len = try lzma.compressInto(&comp_buffer, document, .{ .level = 5 });
    std.debug.print("compressInto caller buffer: {d} bytes\n", .{enc_len});

    const dec_len = try lzma.decompressInto(&decomp_buffer, comp_buffer[0..enc_len], .{});
    std.debug.print("decompressInto caller buffer: {d} bytes\n", .{dec_len});
    if (!std.mem.eql(u8, document, decomp_buffer[0..dec_len])) return error.VerificationFailed;
    std.debug.print("Caller-buffer roundtrip: PASS\n\n", .{});

    // 5. Streaming I/O Pipelines
    std.debug.print("5. Streaming I/O Pipelines\n", .{});
    var in_stream = MemoryReader{ .slice = document };
    var out_stream_storage = std.ArrayList(u8).empty;
    defer out_stream_storage.deinit(allocator);
    var out_stream = MemoryWriter{ .list = &out_stream_storage, .allocator = allocator };

    try lzma.compressStream(allocator, &in_stream, &out_stream, .{});
    std.debug.print("lzma.compressStream written {d} bytes\n", .{out_stream_storage.items.len});

    var comp_reader = MemoryReader{ .slice = out_stream_storage.items };
    var final_storage = std.ArrayList(u8).empty;
    defer final_storage.deinit(allocator);
    var final_writer = MemoryWriter{ .list = &final_storage, .allocator = allocator };

    try lzma.decompressStream(allocator, &comp_reader, &final_writer, .{});
    if (!std.mem.eql(u8, document, final_storage.items)) return error.VerificationFailed;
    std.debug.print("Streaming pipeline roundtrip: PASS\n\n", .{});

    std.debug.print("All LZMA operations completed successfully!\n", .{});
}
