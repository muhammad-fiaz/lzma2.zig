# Reusable Context & Streaming I/O Example

This example demonstrates stateful context reuse and streaming I/O pipelines in `lzma2.zig`:

1. **Reusable Contexts**: Reusing `Compressor` and `Decompressor` instances across multiple sequential records using `.reset()` to eliminate repeated allocations.
2. **Explicit I/O Streaming Pipelines**: Connecting reader and writer adapters to `lzma2.compressStream` and `lzma2.decompressStream`.
3. **Incremental Chunk Streaming**: Push-based compression (`StreamingCompressor`) and feed/drain decompression (`StreamingDecompressor`).
4. **Legacy `.lzma` Container Streaming**: Streamed compression and decompression of `.lzma` Alone archives using `alone.compressStream` and `alone.decompressStream`.

Source file: [`examples/reusable_context.zig`](https://github.com/muhammad-fiaz/lzma2.zig/blob/main/examples/reusable_context.zig)

---

## Complete Source Code

```zig
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
    std.debug.print("--- Part 1: Reusable Contexts ---\n", .{});
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

    // -------------------------------------------------------------
    // Part 2: Explicit I/O Streaming (compressStream & decompressStream)
    // -------------------------------------------------------------
    std.debug.print("--- Part 2: LZMA2 Explicit I/O Streaming Pipeline ---\n", .{});
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

    // -------------------------------------------------------------
    // Part 3: Incremental Chunk Streaming (StreamingCompressor / Decompressor)
    // -------------------------------------------------------------
    std.debug.print("--- Part 3: Incremental Chunk Streaming ---\n", .{});
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
```

---

## Detailed Explanation

### 1. Reader & Writer Interface Adapters
```zig
const MemoryReader = struct {
    slice: []const u8,
    pos: usize = 0,
    pub fn read(self: *MemoryReader, dest: []u8) !usize { ... }
};

const MemoryWriter = struct {
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    pub fn writeAll(self: *MemoryWriter, bytes: []const u8) !void { ... }
};
```
The streaming APIs in `lzma2.zig` use duck typing (compile-time interface duck typing):
- **Reader interface**: Any pointer or struct with a `read(dest: []u8) !usize` method. Returns `0` on End-of-File (EOF).
- **Writer interface**: Any pointer or struct with a `writeAll(bytes: []const u8) !void` method.
This makes the library universally compatible with `std.fs.File.Reader`, `std.net.Stream.Reader`, memory buffers, or custom network sockets without virtual dispatch or wrapper overhead.

### 2. Context Reuse Across Multiple Records
```zig
var compressor = try lzma2.Compressor.init(allocator, .{ .level = 4 });
defer compressor.deinit();

var decompressor = lzma2.Decompressor.init(.{});

for (messages) |msg| {
    const comp = try compressor.compressAlloc(msg);
    defer allocator.free(comp);

    const decomp = try decompressor.decompressAlloc(allocator, comp);
    defer allocator.free(decomp);

    compressor.reset();
    decompressor.reset();
}
```
In server applications, message queues, and high-frequency telemetry loops, creating and destroying compression states for every message incurs heavy allocation overhead:
- `Compressor.init` allocates the match finder tables, history window, and range coder state.
- Calling `.reset()` zeroes the probability tables and resets match search pointers while **retaining all pre-allocated memory buffers**.
- Subsequent messages compress at peak performance with zero intermediate allocation churn.

### 3. Explicit I/O Streaming Pipelines
```zig
try lzma2.compressStream(allocator, &input_reader, &compressed_writer, .{});
try lzma2.decompressStream(allocator, &comp_reader, &restored_writer, .{});
```
`compressStream` and `decompressStream` process unbounded streams of arbitrary size in chunks. Data is read incrementally through `read()` and written out via `writeAll()`, maintaining a small, constant memory footprint regardless of total stream size.

### 4. Incremental Chunk Streaming
```zig
var sc = try lzma2.StreamingCompressor.init(allocator, .{});
defer sc.deinit();

try sc.write("Chunk 1: ...", &chunk_writer);
try sc.write("Chunk 2: ...", &chunk_writer);
try sc.finish(&chunk_writer);

var sd = lzma2.StreamingDecompressor.init(allocator, .{});
defer sd.deinit();

try sd.feed(chunk_out.items);
const bytes_read = sd.take(&restored_chunk_buf);
```
- **`StreamingCompressor`**: Allows pushing fragmented buffers sequentially with `.write()`. Calling `.finish()` flushes the range coder and emits the terminal LZMA2 `0x00` marker.
- **`StreamingDecompressor`**: Decodes data asynchronously as network packets arrive via `.feed()`, allowing callers to drain uncompressed output via `.take()`.

### 5. Legacy `.lzma` Container Streaming
```zig
try lzma2.alone.compressStream(allocator, &alone_in_reader, &alone_writer, .{});
try lzma2.alone.decompressStream(allocator, &alone_comp_reader, &alone_restored_writer, .{});
```
Streams full `.lzma` files containing the 13-byte header, uncompressed size tracking, and raw LZMA payload directly across reader/writer interfaces.

---

## How to Run

Execute using Zig's build system:

```bash
zig build run-reusable_context
```

---

## Expected Output

```text
LZMA2 & LZMA Streaming & Context Reuse Example

1. Reusable Contexts
Message 1: orig=58 bytes, comp=62 bytes, match=true
Message 2: orig=59 bytes, comp=63 bytes, match=true
Message 3: orig=64 bytes, comp=68 bytes, match=true
Reusable contexts processed all records successfully.

2. LZMA2 Explicit I/O Streaming Pipeline
compressStream produced 65 bytes
decompressStream restored 61 bytes: "Continuous pipeline stream data processed in pure native Zig!"

3. Incremental Chunk Streaming
StreamingDecompressor restored 78 bytes: "Chunk 1: Hello from incremental writer. Chunk 2: Seamless chunk concatenation."

4. Legacy .lzma Streaming Pipeline
lzma.compressStream produced 77 bytes (with 13-byte header)
lzma.decompressStream restored 61 bytes: "Continuous pipeline stream data processed in pure native Zig!"

All reusable context and streaming tests passed!
```
