# Getting Started with `lzma2.zig`

`lzma2.zig` provides a pure, native Zig implementation of the LZMA2 compression codec for **Zig 0.17.0**. It has zero external dependencies, uses no C code or `@cImport`, and offers both convenient allocating functions and zero-allocation caller-buffer operations.

---

## 1. Quick Example

Here is a minimal, complete example showing compression and decompression with standard error handling and memory management:

```zig
const std = @import("std");
const lzma2 = @import("lzma2");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const message = "Native LZMA2 compression in pure Zig 0.17.0! High-ratio dictionary encoding.";

    // 1. One-shot compression
    const compressed = try lzma2.compress(allocator, message, .{});
    defer allocator.free(compressed);

    // 2. One-shot decompression
    const decompressed = try lzma2.decompress(allocator, compressed, .{});
    defer allocator.free(decompressed);

    std.debug.print("Original:     {s}\n", .{message});
    std.debug.print("Compressed:   {d} bytes\n", .{compressed.len});
    std.debug.print("Decompressed: {s}\n", .{decompressed});
}
```

---

## 2. Allocator Management & Ownership

- **`lzma2.compress(allocator, src, options)`**:
  Allocates a slice of memory containing the compressed LZMA2 stream. The caller owns the returned slice and must free it using `allocator.free()`.
- **`lzma2.decompress(allocator, src, options)`**:
  Allocates a slice of memory containing the restored uncompressed data. The caller owns the returned slice and must free it using `allocator.free()`.
- **Caller-Buffer Operations**:
  If you prefer not to allocate memory on the heap, use `lzma2.compressBuffer(src, dst, options)` and `lzma2.decompressBuffer(src, dst, options)`. These operate entirely on user-provided slices and perform zero heap allocations.

---

## 3. Reusable Contexts

When compressing or decompressing many streams, reallocating internal dictionary buffers for each call incurs overhead. `lzma2.zig` provides stateful `Compressor` and `Decompressor` structs that allocate their buffers once and can be reset between jobs:

```zig
const std = @import("std");
const lzma2 = @import("lzma2");

pub fn processMany(allocator: std.mem.Allocator, inputs: [][]const u8) !void {
    var compressor = try lzma2.Compressor.init(allocator, .{});
    defer compressor.deinit();

    var decompressor = try lzma2.Decompressor.init(allocator, .{});
    defer decompressor.deinit();

    for (inputs) |input| {
        // Compress
        const comp = try compressor.compress(input);
        defer allocator.free(comp);

        // Decompress
        const restored = try decompressor.decompress(comp);
        defer allocator.free(restored);

        // Reset state for next stream
        compressor.reset(.{});
        decompressor.reset(.{});
    }
}
```

---

## 4. Next Steps

- Check out the [Installation Guide](./installation.md) to add `lzma2.zig` to your `build.zig.zon`.
- Read [Compression](./compression.md) to learn about presets, dictionary sizing, and literal context parameters.
- Explore the [API Reference](/api/) for detailed type and function specifications.
