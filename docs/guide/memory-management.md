# Memory Management & Reusable Contexts

`lzma2.zig` is designed for memory safety and zero unnecessary allocations. This guide explains how memory is managed across the library and how to optimize high-throughput workflows.

---

## 1. Ownership & Lifetime Contracts

`lzma2.zig` follows standard Zig ownership conventions:

- Any function that accepts a `std.mem.Allocator` parameter allocates memory on the caller's behalf.
- The caller is responsible for freeing the returned slice using the same allocator:
  ```zig
  const comp = try lzma2.compress(allocator, data, .{});
  defer allocator.free(comp);
  ```
- Functions ending in `Buffer` (such as `compressBuffer` and `decompressBuffer`) perform **zero heap allocations**. They write directly into caller-provided slices.

---

## 2. Reusable Contexts: `Compressor` and `Decompressor`

In high-throughput services or batch processing pipelines, calling `lzma2.compress()` repeatedly can cause significant allocator overhead as dictionary buffers and range coder states are allocated and freed for each stream.

To avoid this churn, create a stateful engine and call `.reset()` between tasks:

```zig
const std = @import("std");
const lzma2 = @import("lzma2");

pub fn runBatch(allocator: std.mem.Allocator, items: [][]const u8) !void {
    // 1. Allocate context buffers once
    var compressor = try lzma2.Compressor.init(allocator, .{
        .preset = .normal,
        .dict_size = 4 * 1024 * 1024,
    });
    defer compressor.deinit();

    var decompressor = try lzma2.Decompressor.init(allocator, .{
        .dict_size = 4 * 1024 * 1024,
    });
    defer decompressor.deinit();

    for (items) |item| {
        // Compress using reusable context
        const comp = try compressor.compress(item);
        defer allocator.free(comp);

        // Decompress using reusable context
        const orig = try decompressor.decompress(comp);
        defer allocator.free(orig);

        // Reset state for the next item without freeing allocated dictionary memory
        compressor.reset(.{ .preset = .normal });
        decompressor.reset(.{});
    }
}
```

---

## 3. Buffer Bounds & Worst-Case Size

For caller-buffer operations, you need to know how large the destination buffer must be.

- **`lzma2.maxCompressedSize(uncompressed_len)`**:
  Calculates the worst-case compressed buffer capacity required. In LZMA2, uncompressed copy chunks add a tiny header overhead (5 bytes per 64 KiB chunk, plus 1 end-of-stream byte).
- **Decompression Sizing**:
  If the uncompressed size is known ahead of time (e.g., from container metadata or application headers), you can allocate an exact destination slice for `decompressBuffer`. If unknown, `lzma2.decompress()` dynamically manages heap capacity while enforcing `max_output_size`.
