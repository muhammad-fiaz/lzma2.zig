# Caller-Provided Buffer Example (Zero Allocations)

This example demonstrates zero-allocation compression and decompression using pre-allocated, caller-provided stack buffers. This technique is ideal for embedded systems, real-time audio/telemetry processing, kernel modules, or latency-critical servers where dynamic heap allocations are prohibited or costly.

All three codecs provide dedicated `*Into` functions:
- **LZMA2**: `lzma2.compressInto` / `lzma2.decompressInto`
- **Legacy `.lzma`**: `lzma.compressInto` / `lzma.decompressInto`
- **Raw LZMA**: `lzma.compressRawInto` / `lzma.decompressRawInto`

Source file: [`examples/caller_buffer.zig`](https://github.com/muhammad-fiaz/lzma2.zig/blob/main/examples/caller_buffer.zig)

---

## Complete Source Code

```zig
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
```

---

## Detailed Explanation

### 1. Static Buffer Allocation
```zig
var comp_buf: [512]u8 = undefined;
var decomp_buf: [512]u8 = undefined;
```
The caller allocates fixed memory buffers on the call stack (or in global static storage, or inside DMA buffers). No allocator is passed, guaranteeing zero dynamic heap interactions, zero fragmentation, and zero allocation failure risk during runtime execution.

### 2. Compression into Destination Slice
```zig
const lzma2_comp_size = try lzma2.compressInto(&comp_buf, message, .{ .level = 1 });
```
`lzma2.compressInto` encodes the stream directly into the provided slice `&comp_buf`. If the compressed output exceeds the provided capacity, the function immediately returns `error.OutputTooSmall` without corrupting memory or writing beyond the slice boundary. The return value is the exact number of valid bytes written.

### 3. Decompression into Destination Slice
```zig
const lzma2_decomp_size = try lzma2.decompressInto(&decomp_buf, comp_buf[0..lzma2_comp_size], .{});
```
`lzma2.decompressInto` reads the compressed input from `comp_buf[0..lzma2_comp_size]` and writes decoded uncompressed bytes into `decomp_buf`. It returns the exact count of decompressed bytes. If the uncompressed data would exceed the length of `decomp_buf`, `error.OutputTooSmall` is returned.

### 4. Legacy `.lzma` Container Format
```zig
const alone_comp_size = try lzma.compressInto(&comp_buf, message, .{ .level = 1 });
const alone_decomp_size = try lzma.decompressInto(&decomp_buf, comp_buf[0..alone_comp_size], .{});
```
`lzma.compressInto` automatically writes the 13-byte header at indices `0..13` and the LZMA payload at index `13` onward. `lzma.decompressInto` reads the 13-byte header, verifies the dictionary size and uncompressed size, and decodes the stream into `decomp_buf`.

### 5. Raw Headerless LZMA
```zig
const raw_comp_size = try lzma.compressRawInto(&comp_buf, message, .{ .level = 1, .write_end_mark = false });
const raw_decomp_size = try lzma.decompressRawInto(&decomp_buf, comp_buf[0..raw_comp_size], .{ .uncompressed_size = message.len });
```
When using raw LZMA without container headers, `lzma.decompressRawInto` accepts an optional `.uncompressed_size = message.len` in its options. When the size is known, the decoder finishes precisely when the expected byte count is decoded without requiring an End-of-Stream marker.

---

## How to Run

Execute using Zig's build system:

```bash
zig build run-caller_buffer
```

---

## Expected Output

```text
Input message (84 bytes): "High performance zero-allocation embedded compression using caller-provided buffers."

1. LZMA2 Caller Buffer
LZMA2 compressed into buffer: 87 bytes
LZMA2 decompressed from buffer: 84 bytes
LZMA2 caller-buffer check: PASS

2. Legacy .lzma Caller Buffer
Legacy .lzma compressed into buffer: 93 bytes
Legacy .lzma decompressed from buffer: 84 bytes
Legacy .lzma caller-buffer check: PASS

3. Raw LZMA Caller Buffer
Raw LZMA compressed into buffer: 80 bytes
Raw LZMA decompressed from buffer: 84 bytes
Raw LZMA caller-buffer check: PASS

All caller-buffer operations completed successfully!
```
