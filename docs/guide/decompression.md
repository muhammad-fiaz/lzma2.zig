# Decompression Guide

`lzma2.zig` implements an adaptive, defensive LZMA2 stream decoder. It processes chunked streams, restores dictionary sliding history, and validates property and size headers.

---

## 1. One-Shot Decompression

The simplest way to decode an LZMA2 stream is using `lzma2.decompress()`:

```zig
const std = @import("std");
const lzma2 = @import("lzma2");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const decompressed = try lzma2.decompress(allocator, compressed_data, .{});
    defer allocator.free(decompressed);

    std.debug.print("Restored: {s}\n", .{decompressed});
}
```

---

## 2. Zero-Allocation Caller Buffers

When decoding into an existing stack or static buffer, use `lzma2.decompressInto()`:

```zig
var restored_buf: [1024]u8 = undefined;
const decomp_len = try lzma2.decompressInto(&restored_buf, compressed_data, .{});

const restored_slice = restored_buf[0..decomp_len];
```

If the provided destination slice is smaller than the unpacked stream, `error.OutputTooSmall` is returned.

---

## 3. Protecting Against Decompression Bombs

Malicious actors can craft tiny LZMA2 streams that expand into gigabytes of data. `lzma2.zig` guards against this attack with the `max_output_size` option:

```zig
const decompressed = try lzma2.decompress(allocator, untrusted_data, .{
    .max_output_size = 50 * 1024 * 1024, // Limit to 50 MiB
}) catch |err| switch (err) {
    error.ExceededSizeLimit => {
        std.debug.print("Decompression aborted: payload exceeded limit!\n", .{});
        return;
    },
    else => return err,
};
defer allocator.free(decompressed);
```

---

## 4. Dictionary Size Constraints

LZMA2 streams depend on a sliding dictionary history. You can constrain memory allocation by setting `dict_size_limit` on `DecompressOptions`:

```zig
const decompressed = try lzma2.decompress(allocator, compressed_data, .{
    .dict_size_limit = 8 * 1024 * 1024, // 8 MiB maximum dictionary window
});
defer allocator.free(decompressed);
```

If a compressed match refers to distance beyond the configured dictionary size, the decoder immediately stops and returns `error.CorruptData` or `error.ExceededSizeLimit`.

---

## 5. Detecting LZMA2 Streams

Before invoking decompression, you can quickly verify whether a byte slice begins with a plausible LZMA2 chunk header using `lzma2.isLzma2Stream`:

```zig
if (!lzma2.isLzma2Stream(maybe_lzma2)) {
    std.debug.print("Not an LZMA2 stream!\n", .{});
    return;
}
```

---

## 6. Legacy `.lzma` (Alone) Container Decompression

To decompress files created by legacy LZMA tools:

```zig
const decompressed = try lzma2.alone.decompress(allocator, alone_file_bytes, .{
    .max_output_size = 64 * 1024 * 1024,
});
defer allocator.free(decompressed);
```

The decoder automatically validates the 13-byte header, resolves known or unknown uncompressed sizes, and stops at the EOS marker if present.

---

## 7. Raw LZMA Stream Decompression

For raw headerless LZMA payloads:

```zig
const lzma = @import("lzma");

const decompressed = try lzma.decompressRaw(allocator, raw_payload, .{
    .lc = 3,
    .lp = 0,
    .pb = 2,
    .uncompressed_size = 1024, // or null for streams ending with an EOS marker
});
defer allocator.free(decompressed);
```
