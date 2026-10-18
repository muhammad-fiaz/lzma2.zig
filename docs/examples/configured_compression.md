# Configured Compression Example

This example demonstrates fine-tuning compression options in `lzma2.zig`, including compression presets (levels 0–9), custom dictionary sizes (4 KiB to 1 GiB), Markov probability model parameters (`lc`, `lp`, `pb`), match finder modes, and XZ-compliant 1-byte dictionary property encoding.

Source file: [`examples/configured_compression.zig`](https://github.com/muhammad-fiaz/lzma2.zig/blob/main/examples/configured_compression.zig)

---

## Complete Source Code

```zig
//! Configured compression example demonstrating dictionary size, search depth,
//! Markov literal/position properties (lc, lp, pb), and XZ property encoding.

const std = @import("std");
const lzma2 = @import("lzma2");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    // Repetitive text representing structured logs or protocol data
    const sample_data: []const u8 =
        "timestamp=2026-10-17T19:00:00Z level=INFO service=indexer status=200 latency=1.2ms\n" ++
        "timestamp=2026-10-17T19:00:01Z level=INFO service=indexer status=200 latency=1.1ms\n" ++
        "timestamp=2026-10-17T19:00:02Z level=WARN service=indexer status=429 latency=4.8ms\n" ++
        "timestamp=2026-10-17T19:00:03Z level=INFO service=indexer status=200 latency=1.3ms\n";

    std.debug.print("Original log data size: {d} bytes\n\n", .{sample_data.len});

    // 1. Modern LZMA2 with custom options
    std.debug.print("--- 1. LZMA2 Custom Options ---\n", .{});
    const lzma2_opts = lzma2.Options{
        .level = 9, // Maximum compression
        .dict_size = 1024 * 1024, // 1 MiB sliding dictionary
        .lc = 3, // 3 literal context bits
        .lp = 0, // 0 literal position bits
        .pb = 2, // 2 position bits
        .mode = .normal, // 1-step lookahead optimal parsing
        .nice_len = 128, // Long match threshold
    };

    const compressed = try lzma2.compress(allocator, sample_data, lzma2_opts);
    defer allocator.free(compressed);
    std.debug.print("LZMA2 Level 9 (dict 1 MiB) size: {d} bytes\n", .{compressed.len});

    const decompressed = try lzma2.decompress(allocator, compressed, .{});
    defer allocator.free(decompressed);

    if (!std.mem.eql(u8, sample_data, decompressed)) return error.VerificationFailed;
    std.debug.print("LZMA2 custom options check: PASS\n\n", .{});

    // 2. Legacy .lzma with custom options
    std.debug.print("--- 2. Legacy .lzma Custom Options ---\n", .{});
    const alone_opts = lzma2.AloneOptions{
        .level = 7,
        .dict_size = 512 * 1024, // 512 KiB dictionary
        .lc = 4, // 4 literal context bits
        .lp = 0,
        .pb = 2,
    };
    const alone_comp = try lzma2.alone.compress(allocator, sample_data, alone_opts);
    defer allocator.free(alone_comp);
    std.debug.print("Legacy .lzma custom options size: {d} bytes\n", .{alone_comp.len});

    const alone_decomp = try lzma2.alone.decompress(allocator, alone_comp, .{});
    defer allocator.free(alone_decomp);

    if (!std.mem.eql(u8, sample_data, alone_decomp)) return error.VerificationFailed;
    std.debug.print("Legacy .lzma custom options check: PASS\n\n", .{});

    // 3. Demonstrate XZ-compatible dictionary property encoding
    std.debug.print("--- 3. XZ Dictionary Property Conversion ---\n", .{});
    const prop_1mb = try lzma2.dictSizeToProp(1024 * 1024);
    const decoded_size = try lzma2.propToDictSize(prop_1mb);
    std.debug.print("XZ Dict Property: 1 MiB -> property 0x{X:0>2} -> decoded {d} bytes\n", .{ prop_1mb, decoded_size });
}
```

---

## Detailed Explanation

### 1. Compression Presets (`level`)
`level: u4 = 6` (0 to 9):
- **Level 0**: Store mode (uncompressed copy chunks).
- **Levels 1–3**: Fast mode (smaller dictionary, greedy match selection, shallow search depth).
- **Levels 4–6**: Standard production mode (balanced throughput and ratio, 8 MiB default dictionary).
- **Levels 7–9**: Maximum compression mode (up to 64 MiB dictionary, 1-step lazy lookahead, maximum search depth).

### 2. Dictionary Size (`dict_size`)
The sliding window size in bytes:
- Must be between `4,096` bytes (4 KiB) and `1,073,741,824` bytes (1 GiB).
- Larger dictionaries enable matching redundant data across longer distances, requiring proportionally more RAM during compression and decompression.
- In LZMA2, dictionary sizes are encoded into a single property byte in container headers.

### 3. Markov Literal & Position Bits (`lc`, `lp`, `pb`)
LZMA's statistical modeling uses three bit-depth parameters:
- **`lc` (Literal Context Bits, 0..8, default 3)**: Number of high bits of the previous byte used as context for encoding the next literal. For text and source code, `lc=3` or `lc=4` is optimal. For binary tables or fixed-width records, lower values may be preferable.
- **`lp` (Literal Position Bits, 0..4, default 0)**: Number of low bits of the uncompressed position used to align literal subtrees. For 32-bit aligned data (e.g. 4-byte structs), setting `lp=2` can improve compression.
- **`pb` (Position Bits, 0..4, default 2)**: Number of low bits of current position used for position states in match models (modulo $2^{pb}$). Setting `pb=2` matches 4-byte boundaries.
- **LZMA2 Restriction**: In LZMA2 chunks, `lc + lp <= 4` is strictly enforced by the format specification.

### 4. Match Finder Mode (`mode`)
- **`.fast`**: Uses a greedy match finder that immediately emits the longest match found at the current offset. Fast, ideal for streaming or high-throughput logging.
- **`.normal`**: Evaluates 1-step lazy lookahead. If skipping one byte allows taking a significantly longer match on the next byte, it emits a literal and takes the longer match, achieving higher compression ratios.

### 5. XZ Dictionary Property Conversion
```zig
const prop_1mb = try lzma2.dictSizeToProp(1024 * 1024);
const decoded_size = try lzma2.propToDictSize(prop_1mb);
```
LZMA2 and `.xz` files encode dictionary sizes as a single byte `0x00..0x28` (0 to 40) according to Section 5.3.1 of the XZ specification:
- Property `0x10` (16) encodes a 1 MiB ($2^{20}$) dictionary.
- Property `0x28` (40) encodes the maximum 4 GiB - 1 dictionary.
`lzma2.dictSizeToProp()` and `lzma2.propToDictSize()` allow converting between raw byte counts and standard property bytes.

---

## How to Run

Execute using Zig's build system:

```bash
zig build run-configured_compression
```

---

## Expected Output

```text
Original log data size: 332 bytes

--- 1. LZMA2 Custom Options ---
LZMA2 Level 9 (dict 1 MiB) size: 122 bytes
LZMA2 custom options check: PASS

--- 2. Legacy .lzma Custom Options ---
Legacy .lzma custom options size: 132 bytes
Legacy .lzma custom options check: PASS

--- 3. XZ Dictionary Property Conversion ---
XZ Dict Property: 1 MiB -> property 0x10 -> decoded 1048576 bytes
```
