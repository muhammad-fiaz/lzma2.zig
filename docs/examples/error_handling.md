# Error Handling & Resource Limits Example

This example demonstrates defensive error handling and resource protection strategies in `lzma2.zig`:

1. **Corrupt / Invalid Control Bytes**: Detecting malformed LZMA2 chunk headers and returning `error.InvalidControlByte`.
2. **Decompression Bomb Protection**: Enforcing maximum uncompressed output limits via `.max_output_size` to return `error.ExceededSizeLimit`.
3. **Caller Buffer Overflow**: Bounds-checking caller-provided destination buffers and returning `error.OutputTooSmall`.
4. **Corrupt Legacy Headers**: Validating `.lzma` Alone 13-byte headers and rejecting illegal property bytes ($\ge 225$) with `error.InvalidProperties`.

Source file: [`examples/error_handling.zig`](https://github.com/muhammad-fiaz/lzma2.zig/blob/main/examples/error_handling.zig)

---

## Complete Source Code

```zig
//! Error handling example showing how to detect and handle corrupted inputs,
//! insufficient buffers, invalid headers, and decompression limit violations.

const std = @import("std");
const lzma2 = @import("lzma2");

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
    const res4 = lzma2.alone.decompress(allocator, &corrupt_alone, .{});
    if (res4) |_| {
        std.debug.print("Unexpected success with corrupt header!\n", .{});
    } else |err| {
        std.debug.print("   Correctly caught error: {s}\n", .{@errorName(err)});
    }
}
```

---

## Detailed Explanation

### 1. Invalid Control Byte Detection (`error.InvalidControlByte`)
```zig
const invalid_stream = [_]u8{ 0x05, 0x12, 0x34 };
const res1 = lzma2.decompress(allocator, &invalid_stream, .{});
```
In the LZMA2 specification, valid chunk control bytes fall strictly into these ranges:
- `0x00`: Stream termination (EOS).
- `0x01`: Reset dictionary and uncompressed copy chunk.
- `0x02`: Uncompressed copy chunk without dictionary reset.
- `0x80..0xFF`: Compressed LZMA chunks with encoded unpack size, pack size, and reset bits.

Control bytes in the range `0x03..0x7F` (including `0x05`) are reserved and invalid. The decoder immediately halts execution and returns `error.InvalidControlByte`, preventing out-of-bounds reads or undefined behavior.

### 2. Decompression Bomb Protection (`error.ExceededSizeLimit`)
```zig
const res2 = lzma2.decompress(allocator, comp, .{ .max_output_size = 100 });
```
Decompression bombs ("zip bombs") are maliciously crafted compressed streams with astronomical compression ratios designed to trigger out-of-memory crashes on target systems.
- By configuring `.max_output_size` in `lzma2.DecompressOptions`, callers specify the maximum allowable uncompressed byte count.
- The decoder enforces this threshold continuously during both chunk header parsing and range decoding.
- When the threshold is exceeded, the decoder immediately terminates and returns `error.ExceededSizeLimit`, freeing intermediate allocations cleanly.

### 3. Caller Buffer Bounds Protection (`error.OutputTooSmall`)
```zig
var small_buf: [16]u8 = undefined;
const res3 = lzma2.compressInto(&small_buf, large_string, .{});
```
When using zero-allocation functions (`compressInto`, `decompressInto`, `alone.compressInto`, etc.):
- The functions check destination capacity before and throughout encoding.
- If the compressed stream or decompressed payload cannot fit within the provided slice, the operation safely returns `error.OutputTooSmall`.
- No buffer overruns, memory corruption, or partial invalid outputs occur.

### 4. Legacy Header Validation (`error.InvalidProperties`)
```zig
var corrupt_alone: [13]u8 = @splat(0);
corrupt_alone[0] = 230; // 230 >= 225 is invalid
const res4 = lzma2.alone.decompress(allocator, &corrupt_alone, .{});
```
The legacy `.lzma` container format encodes three Markov parameters into the very first byte:
$$\text{property} = (pb \times 5 + lp) \times 9 + lc$$
Given that standard bounds require:
- $lc \in [0, 8]$
- $lp \in [0, 4]$
- $pb \in [0, 4]$

The maximum mathematically permissible value is $(4 \times 5 + 4) \times 9 + 8 = 224$. Any value $\ge 225$ (such as `230`) indicates corrupted file data or an invalid archive format. The `.lzma` container decoder validates this byte prior to allocating memory or beginning range decoding, returning `error.InvalidProperties`.

### 5. Idiomatic Error Handling Pattern
In Zig, errors are handled explicitly using error unions:
```zig
if (lzma2.decompress(allocator, data, .{})) |uncompressed| {
    defer allocator.free(uncompressed);
    // Process decompressed payload
} else |err| switch (err) {
    error.InvalidControlByte, error.CorruptData => {
        // Handle malformed or damaged archive data
    },
    error.ExceededSizeLimit => {
        // Handle decompression bomb or unexpected payload size
    },
    error.OutOfMemory => {
        // Handle allocation failure
    },
    else => return err,
}
```

---

## How to Run

Execute using Zig's build system:

```bash
zig build run-error_handling
```

---

## Expected Output

```text
1. Attempting to decompress invalid control byte 0x05...
   Correctly caught error: InvalidControlByte

2. Attempting decompression with 100-byte output safety limit...
   Correctly caught error: ExceededSizeLimit

3. Attempting to compress into undersized buffer (16 bytes)...
   Correctly caught error: OutputTooSmall

4. Attempting to decompress .lzma container with corrupt property byte (230)...
   Correctly caught error: InvalidProperties
```
