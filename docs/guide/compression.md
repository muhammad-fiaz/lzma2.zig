# Compression Guide

`lzma2.zig` offers flexible, high-ratio LZMA2 compression options ranging from fast single-call functions to zero-allocation caller buffers and stateful compressor contexts.

---

## 1. One-Shot Compression

The simplest way to compress data is using `lzma2.compress()`:

```zig
const std = @import("std");
const lzma2 = @import("lzma2");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const input = "Data to compress...";

    const compressed = try lzma2.compress(allocator, input, .{});
    defer allocator.free(compressed);

    std.debug.print("Compressed to {d} bytes\n", .{compressed.len});
}
```

The returned buffer contains a complete, self-contained LZMA2 stream ending with the `0x00` end-of-stream control byte.

---

## 2. Compression Presets

The `Preset` enum provides 4 preconfigured levels balancing compression ratio against encoding speed:

| Preset | Description | Default Dict Size | Mode | Nice Length |
|---|---|---|---|---|
| `.fastest` | Fastest compression, lowest CPU usage | 64 KiB | `.fast` | 16 |
| `.fast` | Fast compression, suitable for real-time | 1 MiB | `.fast` | 32 |
| `.normal` | Default balanced ratio and performance | 8 MiB | `.normal` | 64 |
| `.maximum` | High-ratio dictionary matching | 32 MiB | `.normal` | 128 |

Example using `.fastest`:

```zig
const compressed = try lzma2.compress(allocator, input, .{
    .preset = .fastest,
});
defer allocator.free(compressed);
```

---

## 3. Custom Compression Options

You can customize individual parameters within `lzma2.Options`:

```zig
const compressed = try lzma2.compress(allocator, input, .{
    .dict_size = 16 * 1024 * 1024, // 16 MiB dictionary
    .preset = .maximum,
    .mode = .normal,
    .lc = 3,                       // Literal context bits (0..8, default 3)
    .lp = 0,                       // Literal position bits (0..4, default 0)
    .pb = 2,                       // Position bits (0..4, default 2)
    .nice_len = 64,                // Match finder nice length
    .match_depth = 64,             // Search chain limit
});
defer allocator.free(compressed);
```

> [!NOTE]
> LZMA2 requires that `lc + lp <= 4` and `pb <= 4`. If the configured options exceed these limits, `compress()` will return `error.InvalidProperties`.

---

## 4. Zero-Allocation Buffer Compression

When heap allocations are forbidden or undesirable, use `lzma2.compressInto()`:

```zig
var out_buffer: [4096]u8 = undefined;
const bytes_written = try lzma2.compressInto(&out_buffer, input, .{});

const compressed_slice = out_buffer[0..bytes_written];
```

If `out_buffer` is too small to accommodate the compressed stream, `error.OutputTooSmall` is returned. You can use `lzma2.maxCompressedSize(input.len)` to compute a safe upper bound on required buffer capacity.

---

## 5. Uncompressed Copy Chunks

If the input is random, encrypted, or otherwise incompressible, `lzma2.zig` automatically falls back to uncompressed copy chunks (`0x01` / `0x02`), ensuring that output size never catastrophically expands on incompressible data.

---

## 6. Legacy `.lzma` (Alone) Container Compression

For compatibility with legacy tools expecting the original 13-byte header `.lzma` file format, use `lzma2.alone`:

```zig
const alone_compressed = try lzma2.alone.compress(allocator, input, .{
    .level = 6,
    .dict_size = 8 * 1024 * 1024,
});
defer allocator.free(alone_compressed);
```

To encode with an unknown uncompressed size and mandatory End-of-Stream (EOS) marker:

```zig
const stream_compressed = try lzma2.alone.compress(allocator, input, .{
    .unknown_size = true,
    .write_end_mark = true,
});
defer allocator.free(stream_compressed);
```

---

## 7. Raw LZMA Stream Compression

For headerless streams embedded in custom containers or firmware formats:

```zig
const lzma = @import("lzma");

const raw_compressed = try lzma.compressRaw(allocator, input, .{
    .lc = 3,
    .lp = 0,
    .pb = 2,
    .write_end_mark = true,
});
defer allocator.free(raw_compressed);
```
