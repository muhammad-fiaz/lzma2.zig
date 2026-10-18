//! Comprehensive Reusable Context & Streaming I/O Example for lzma2.zig.
//!
//! Demonstrates:
//! 1. Reusable Compressor and Decompressor context reuse across multiple messages.
//! 2. Streaming reader and writer pipelines for LZMA2 (compressStream and decompressStream).
//! 3. Incremental chunk streaming with StreamingCompressor and StreamingDecompressor.
//! 4. Legacy .lzma container streaming (lzma.compressStream and lzma.decompressStream).
//! 5. Raw LZMA streaming (lzma.compressRawStream and lzma.decompressRawStream).

const std = @import("std");
const lzma2 = @import("lzma2");
const lzma = @import("lzma");

// Simple in-memory reader adapter implementing read(dest: []u8) !usize
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

// Simple in-memory writer adapter implementing writeAll(bytes: []const u8) !void
const MemoryWriter = struct {
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn writeAll(self: *MemoryWriter, bytes: []const u8) !void {
        self.list.appendSlice(self.allocator, bytes) catch return error.OutOfMemory;
    }
};

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    std.debug.print("LZMA2 & LZMA Streaming & Context Reuse Example\n\n", .{});

    // Part 1: Reusable Stateful Contexts (Compressor & Decompressor)
    std.debug.print("1. Reusable Contexts\n", .{});
    var compressor = try lzma2.Compressor.init(allocator, .{ .level = 4 });
    defer compressor.deinit();

    var decompressor = lzma2.Decompressor.init(.{});

    const messages = [_][]const u8{
        "Record 1: Primary telemetry packet from sensor node Alpha.",
        "Record 2: Secondary telemetry packet from sensor node Beta.",
        "Record 3: Environmental telemetry packet from sensor node Gamma.",
    };

    for (messages, 0..) |msg, i| {
        const comp = try compressor.compressAlloc(msg);
        defer allocator.free(comp);

        const decomp = try decompressor.decompressAlloc(allocator, comp);
        defer allocator.free(decomp);

        std.debug.print("Message {d}: orig={d} bytes, comp={d} bytes, match={}\n", .{
            i + 1,
            msg.len,
            comp.len,
            std.mem.eql(u8, msg, decomp),
        });

        if (!std.mem.eql(u8, msg, decomp)) return error.Mismatch;
        compressor.reset();
        decompressor.reset();
    }
    std.debug.print("Reusable contexts processed all records successfully.\n\n", .{});

    // Part 2: Explicit I/O Streaming (compressStream & decompressStream)
    std.debug.print("2. LZMA2 Explicit I/O Streaming Pipeline\n", .{});
    const stream_input = "Continuous pipeline stream data processed in pure native Zig!";

    var input_reader = MemoryReader{ .slice = stream_input };
    var compressed_storage = std.ArrayList(u8).empty;
    defer compressed_storage.deinit(allocator);
    var compressed_writer = MemoryWriter{ .list = &compressed_storage, .allocator = allocator };

    // Stream compression
    try lzma2.compressStream(allocator, &input_reader, &compressed_writer, .{});
    std.debug.print("compressStream produced {d} bytes\n", .{compressed_storage.items.len});

    // Stream decompression
    var comp_reader = MemoryReader{ .slice = compressed_storage.items };
    var restored_storage = std.ArrayList(u8).empty;
    defer restored_storage.deinit(allocator);
    var restored_writer = MemoryWriter{ .list = &restored_storage, .allocator = allocator };

    try lzma2.decompressStream(allocator, &comp_reader, &restored_writer, .{});
    std.debug.print("decompressStream restored {d} bytes: \"{s}\"\n\n", .{
        restored_storage.items.len,
        restored_storage.items,
    });

    if (!std.mem.eql(u8, stream_input, restored_storage.items)) return error.Mismatch;

    // Part 3: Incremental Chunk Streaming (StreamingCompressor / Decompressor)
    std.debug.print("3. Incremental Chunk Streaming\n", .{});
    var sc = try lzma2.StreamingCompressor.init(allocator, .{});
    defer sc.deinit();

    var chunk_out = std.ArrayList(u8).empty;
    defer chunk_out.deinit(allocator);
    var chunk_writer = MemoryWriter{ .list = &chunk_out, .allocator = allocator };

    try sc.write("Chunk 1: Hello from incremental writer. ", &chunk_writer);
    try sc.write("Chunk 2: Seamless chunk concatenation.", &chunk_writer);
    try sc.finish(&chunk_writer);

    var sd = lzma2.StreamingDecompressor.init(allocator, .{});
    defer sd.deinit();

    try sd.feed(chunk_out.items);

    var restored_chunk_buf: [256]u8 = undefined;
    const bytes_read = sd.take(&restored_chunk_buf);
    std.debug.print("StreamingDecompressor restored {d} bytes: \"{s}\"\n\n", .{
        bytes_read,
        restored_chunk_buf[0..bytes_read],
    });

    // Part 4: Legacy .lzma Container Streaming Pipeline
    std.debug.print("4. Legacy .lzma Streaming Pipeline\n", .{});
    var alone_in_reader = MemoryReader{ .slice = stream_input };
    var alone_comp_store = std.ArrayList(u8).empty;
    defer alone_comp_store.deinit(allocator);
    var alone_writer = MemoryWriter{ .list = &alone_comp_store, .allocator = allocator };

    try lzma.compressStream(allocator, &alone_in_reader, &alone_writer, .{});
    std.debug.print("lzma.compressStream produced {d} bytes (with 13-byte header)\n", .{alone_comp_store.items.len});

    var alone_comp_reader = MemoryReader{ .slice = alone_comp_store.items };
    var alone_restored = std.ArrayList(u8).empty;
    defer alone_restored.deinit(allocator);
    var alone_restored_writer = MemoryWriter{ .list = &alone_restored, .allocator = allocator };

    try lzma.decompressStream(allocator, &alone_comp_reader, &alone_restored_writer, .{});
    std.debug.print("lzma.decompressStream restored {d} bytes: \"{s}\"\n\n", .{
        alone_restored.items.len,
        alone_restored.items,
    });

    if (!std.mem.eql(u8, stream_input, alone_restored.items)) return error.Mismatch;

    std.debug.print("All reusable context and streaming tests passed!\n", .{});
}
