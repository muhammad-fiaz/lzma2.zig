# Basic Compression & Decompression Example

This example demonstrates one-shot in-memory compression and decompression for all three supported codecs and container formats in `lzma2.zig`:

1. **Modern LZMA2** (`lzma2.compress` / `lzma2.decompress`)
2. **Legacy `.lzma` Container** (`lzma.compress` / `lzma.decompress` or `lzma2.alone`)
3. **Raw LZMA Stream** (`lzma.compressRaw` / `lzma.decompressRaw` or `lzma2.lzma`)

Source file: [`examples/basic_compression.zig`](https://github.com/muhammad-fiaz/lzma2.zig/blob/main/examples/basic_compression.zig)

---

## Complete Source Code

```zig
//! Basic compression and decompression example using lzma2.zig and lzma.zig.
//!
//! Demonstrates one-shot compression and decompression for:
//! 1. Modern LZMA2 streams (`lzma2.compress` / `lzma2.decompress`)
//! 2. Legacy `.lzma` file container format (`lzma.compress` / `lzma.decompress` or `lzma2.alone`)
//! 3. Raw LZMA stream format (`lzma.compressRaw` / `lzma.decompressRaw` or `lzma2.lzma`)

const std = @import("std");
const lzma2 = @import("lzma2");
const lzma = @import("lzma");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const original_text: []const u8 =
        "LZMA2 is a modern container format capable of containing both uncompressed " ++
        "data and LZMA compressed chunks. LZMA is the original format with a 13-byte header.";

    std.debug.print("Original data size: {d} bytes\n\n", .{original_text.len});

    // 1. Modern LZMA2 Format (@import("lzma2"))
    std.debug.print("1. Modern LZMA2 One-Shot\n", .{});
    const lzma2_compressed = try lzma2.compress(allocator, original_text, .{});
    defer allocator.free(lzma2_compressed);
    std.debug.print("LZMA2 compressed size: {d} bytes\n", .{lzma2_compressed.len});

    const lzma2_decompressed = try lzma2.decompress(allocator, lzma2_compressed, .{});
    defer allocator.free(lzma2_decompressed);

    if (!std.mem.eql(u8, original_text, lzma2_decompressed)) return error.VerificationFailed;
    std.debug.print("LZMA2 roundtrip: PASS\n\n", .{});

    // 2. Legacy .lzma Container One-Shot (@import("lzma"))
    std.debug.print("2. Legacy .lzma Container One-Shot\n", .{});
    const alone_compressed = try lzma.compress(allocator, original_text, .{});
    defer allocator.free(alone_compressed);
    std.debug.print("Legacy .lzma file size (13-byte header + stream): {d} bytes\n", .{alone_compressed.len});

    const alone_decompressed = try lzma.decompress(allocator, alone_compressed, .{});
    defer allocator.free(alone_decompressed);

    if (!std.mem.eql(u8, original_text, alone_decompressed)) return error.VerificationFailed;
    std.debug.print("Legacy .lzma roundtrip: PASS\n\n", .{});

    // 3. Raw LZMA Stream Format (Headerless)
    std.debug.print("3. Raw LZMA Stream One-Shot\n", .{});
    const raw_compressed = try lzma.compressRaw(allocator, original_text, .{ .write_end_mark = true });
    defer allocator.free(raw_compressed);
    std.debug.print("Raw LZMA stream size: {d} bytes\n", .{raw_compressed.len});

    const raw_decompressed = try lzma.decompressRaw(allocator, raw_compressed, .{ .uncompressed_size = null });
    defer allocator.free(raw_decompressed);

    if (!std.mem.eql(u8, original_text, raw_decompressed)) return error.VerificationFailed;
    std.debug.print("Raw LZMA roundtrip: PASS\n\n", .{});

    std.debug.print("All basic compression tests passed successfully!\n", .{});
}
```

---

## Detailed Explanation

### 1. Allocator Selection
```zig
const allocator = std.heap.smp_allocator;
```
The example uses `std.heap.smp_allocator` (or `std.heap.page_allocator`) to allocate dynamic memory buffers for the output slices. The returned slices are owned by the caller and must be freed with `defer allocator.free(...)`.

### 2. Modern LZMA2 Compression
```zig
const lzma2_compressed = try lzma2.compress(allocator, original_text, .{});
```
`lzma2.compress` compresses an input slice into raw LZMA2 chunk format using default options (Level 6, 8 MiB dictionary, `.normal` 1-step lookahead match finder). LZMA2 segments data into independent chunks (up to 2 MiB uncompressed, up to 64 KiB compressed), automatically falling back to uncompressed copy chunks if data is incompressible, and terminates with a `0x00` control byte.

### 3. Modern LZMA2 Decompression
```zig
const lzma2_decompressed = try lzma2.decompress(allocator, lzma2_compressed, .{});
```
`lzma2.decompress` parses the LZMA2 chunk control bytes, initializes dictionary and probability states as commanded by chunk headers, decodes range-encoded literals and matches, and returns an allocated slice containing the exact original bytes.

### 4. Legacy `.lzma` Container Format
```zig
const alone_compressed = try lzma.compress(allocator, original_text, .{});
const alone_decompressed = try lzma.decompress(allocator, alone_compressed, .{});
```
`lzma.compress` prepends the official 13-byte header:
- **Byte 0**: Encoded properties `(pb * 5 + lp) * 9 + lc` (typically `0x5D` for default `lc=3, lp=0, pb=2`).
- **Bytes 1–4**: Dictionary size (32-bit little-endian integer).
- **Bytes 5–12**: Uncompressed size (64-bit little-endian integer, or `0xFFFFFFFFFFFFFFFF` for unknown).
Followed by the raw LZMA stream.

### 5. Raw Headerless LZMA
```zig
const raw_compressed = try lzma.compressRaw(allocator, original_text, .{ .write_end_mark = true });
const raw_decompressed = try lzma.decompressRaw(allocator, raw_compressed, .{ .uncompressed_size = null });
```
When raw LZMA is required (such as inside custom archive containers or embedded firmware formats without container metadata), `lzma.compressRaw` produces the bare range-encoded byte stream. The `.write_end_mark = true` option emits an explicit End-of-Stream (EOS) marker (distance `0xFFFFFFFF`), enabling decompression even when the uncompressed length is not known in advance.

---

## How to Run

Execute using Zig's build system:

```bash
zig build run-basic_compression
```

---

## Expected Output

```text
Original data size: 158 bytes

1. Modern LZMA2 One-Shot
LZMA2 compressed size: 135 bytes
LZMA2 roundtrip: PASS

2. Legacy .lzma Container One-Shot
Legacy .lzma file size (13-byte header + stream): 141 bytes
Legacy .lzma roundtrip: PASS

3. Raw LZMA Stream One-Shot
Raw LZMA stream size: 133 bytes
Raw LZMA roundtrip: PASS

All basic compression tests passed successfully!
```
