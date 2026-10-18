//! Streaming LZMA2 compressor.
//!
//! Provides chunk-by-chunk and reader/writer streaming compression
//! with bounded memory usage and incremental I/O.

const std = @import("std");
const lzma = @import("lzma");
const errors = lzma.errors;
const options_mod = lzma.options;
const Options = options_mod.Options;
const encoder_mod = @import("lzma2.zig");
const Compressor = encoder_mod.Compressor;

/// Incremental streaming compressor.
pub const StreamingCompressor = struct {
    allocator: std.mem.Allocator,
    compressor: Compressor,
    buffer: std.ArrayList(u8),
    finished: bool = false,

    pub fn init(allocator: std.mem.Allocator, options: Options) errors.CompressError!StreamingCompressor {
        return StreamingCompressor{
            .allocator = allocator,
            .compressor = try Compressor.init(allocator, options),
            .buffer = std.ArrayList(u8).empty,
            .finished = false,
        };
    }

    pub fn deinit(self: *StreamingCompressor) void {
        self.compressor.deinit();
        self.buffer.deinit(self.allocator);
    }

    pub fn reset(self: *StreamingCompressor) void {
        self.compressor.reset();
        self.buffer.clearRetainingCapacity();
        self.finished = false;
    }

    /// Writes uncompressed data chunk to the compressor and flushes ready compressed chunks to `writer`.
    pub fn write(self: *StreamingCompressor, chunk: []const u8, writer: anytype) errors.CompressError!void {
        if (self.finished) return error.InvalidOptions;
        if (chunk.len == 0) return;
        self.buffer.appendSlice(self.allocator, chunk) catch return error.OutOfMemory;

        while (self.buffer.items.len >= options_mod.CHUNK_UNPACK_MAX) {
            const chunk_to_compress = self.buffer.items[0..options_mod.CHUNK_UNPACK_MAX];
            const comp = try self.compressor.compressAlloc(chunk_to_compress);
            defer self.allocator.free(comp);

            // Write compressed payload except the EOF marker if continuing
            if (comp.len > 1 and comp[comp.len - 1] == 0) {
                writer.writeAll(comp[0 .. comp.len - 1]) catch return error.OutputTooSmall;
            } else {
                writer.writeAll(comp) catch return error.OutputTooSmall;
            }

            const remaining = self.buffer.items.len - options_mod.CHUNK_UNPACK_MAX;
            if (remaining > 0) {
                std.mem.copyForwards(u8, self.buffer.items[0..remaining], self.buffer.items[options_mod.CHUNK_UNPACK_MAX..]);
            }
            self.buffer.shrinkRetainingCapacity(remaining);
        }
    }

    /// Finishes the stream, flushes all remaining uncompressed data, and writes the EOF marker.
    pub fn finish(self: *StreamingCompressor, writer: anytype) errors.CompressError!void {
        if (self.finished) return;
        const comp = try self.compressor.compressAlloc(self.buffer.items);
        defer self.allocator.free(comp);
        writer.writeAll(comp) catch return error.OutputTooSmall;
        self.buffer.clearRetainingCapacity();
        self.finished = true;
    }
};

/// Streams uncompressed data from `reader` and writes compressed LZMA2 stream to `writer`.
pub fn compressStream(
    allocator: std.mem.Allocator,
    reader: anytype,
    writer: anytype,
    options: Options,
) errors.CompressError!void {
    var sc = try StreamingCompressor.init(allocator, options);
    defer sc.deinit();

    var buf: [65536]u8 = undefined;
    while (true) {
        const n = reader.read(&buf) catch return error.OutputTooSmall;
        if (n == 0) break;
        try sc.write(buf[0..n], writer);
    }
    try sc.finish(writer);
}

test "streaming compressor: basic streaming compression" {
    const allocator = std.testing.allocator;
    const msg = "Streaming compressor test in native Zig 0.17.0!";

    var sc = try StreamingCompressor.init(allocator, .{});
    defer sc.deinit();

    var out_list = std.ArrayList(u8).empty;
    defer out_list.deinit(allocator);

    const MemoryWriter = struct {
        list: *std.ArrayList(u8),
        pub fn writeAll(self: @This(), bytes: []const u8) !void {
            try self.list.appendSlice(std.testing.allocator, bytes);
        }
    };
    const writer = MemoryWriter{ .list = &out_list };

    try sc.write(msg[0 .. msg.len / 2], writer);
    try sc.write(msg[msg.len / 2 ..], writer);
    try sc.finish(writer);

    try std.testing.expect(out_list.items.len > 0);
    try std.testing.expectEqual(@as(u8, 0), out_list.items[out_list.items.len - 1]);
}
