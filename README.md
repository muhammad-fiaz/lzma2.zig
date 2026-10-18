<div align="center">

# lzma2.zig

<a href="https://muhammad-fiaz.github.io/lzma2.zig/"><img src="https://img.shields.io/badge/docs-muhammad--fiaz.github.io-blue" alt="Documentation"></a>
<a href="https://ziglang.org/"><img src="https://img.shields.io/badge/Zig-0.17.0-orange.svg?logo=zig" alt="Zig Version"></a>
<a href="https://github.com/muhammad-fiaz/lzma2.zig"><img src="https://img.shields.io/github/stars/muhammad-fiaz/lzma2.zig" alt="GitHub stars"></a>
<a href="https://github.com/muhammad-fiaz/lzma2.zig/issues"><img src="https://img.shields.io/github/issues/muhammad-fiaz/lzma2.zig" alt="GitHub issues"></a>
<a href="https://github.com/muhammad-fiaz/lzma2.zig/pulls"><img src="https://img.shields.io/github/issues-pr/muhammad-fiaz/lzma2.zig" alt="GitHub pull requests"></a>
<a href="https://github.com/muhammad-fiaz/lzma2.zig"><img src="https://img.shields.io/github/last-commit/muhammad-fiaz/lzma2.zig" alt="GitHub last commit"></a>
<a href="https://github.com/muhammad-fiaz/lzma2.zig/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License"></a>
<img src="https://img.shields.io/badge/platforms-linux%20%7C%20windows%20%7C%20macos-blue" alt="Supported Platforms">
<a href="https://github.com/muhammad-fiaz/lzma2.zig/releases/latest"><img src="https://img.shields.io/github/v/release/muhammad-fiaz/lzma2.zig?label=Latest%20Release&style=flat-square" alt="Latest Release"></a>
<a href="https://pay.muhammadfiaz.com"><img src="https://img.shields.io/badge/Sponsor-pay.muhammadfiaz.com-ff69b4?style=flat&logo=heart" alt="Sponsor"></a>
<a href="https://github.com/sponsors/muhammad-fiaz"><img src="https://img.shields.io/badge/Sponsor-GitHub-pink?style=social&logo=github" alt="GitHub Sponsors"></a>
<a href="https://hits.sh/muhammad-fiaz/lzma2.zig/"><img src="https://hits.sh/muhammad-fiaz/lzma2.zig.svg?label=Visitors&extraCount=0&color=green" alt="Repo Visitors"></a>

<p><em>Type-safe, memory-conscious, native Zig implementation of modern LZMA2 and legacy LZMA compression codecs.</em></p>

<b><a href="https://muhammad-fiaz.github.io/lzma2.zig/">Documentation</a> |
<a href="https://muhammad-fiaz.github.io/lzma2.zig/api/">API Reference</a> |
<a href="https://muhammad-fiaz.github.io/lzma2.zig/guide/getting-started">Quick Start</a> |
<a href="CONTRIBUTING.md">Contributing</a></b>

</div>

`lzma2.zig` is a standalone, production-quality compression and decompression library written entirely in native Zig targeting **Zig 0.17.0**. Engineered from first principles with zero external dependencies, no `@cImport`, and zero C/C++ bindings.

> [!NOTE]
> `lzma2.zig` implements both modern **LZMA2** and legacy **LZMA / .lzma** formats:
>
> - **Modern LZMA2**: Chunked protocol with uncompressed copy chunks (`0x01`, `0x02`), compressed LZMA chunks (`0x80`..`0xFF`), all 4 reset modes (state, dictionary, properties), and EOS marker (`0x00`).
> - **Legacy LZMA & .lzma**: Full support for legacy `.lzma` (LZMA-Alone) 13-byte header files with known or unknown uncompressed sizes and end-of-stream (EOS) markers, plus raw headerless LZMA streams.
> - **Full LZMA Range Engine**: 32-bit adaptive binary range encoder and decoder with normalized probability transitions and 12-state Markov models.
> - **Zero-Allocation Buffer Mode**: Caller-provided output buffers (`compressInto` / `decompressInto`) for constrained or real-time environments.
> - **Streaming Pipelines**: First-class support for chunked streaming and reader/writer pipelines via `compressStream` and `decompressStream`.
> - **Reusable Contexts**: Allocate working buffers once with `Compressor` / `Decompressor` and reuse across multiple compression jobs via `.reset()`.
> - **Decompression Bomb Protection**: Configurable `max_output_size` limits to defend against hostile or malformed payloads.

---

<details>
<summary><strong>Features</strong> (click to expand)</summary>

| Feature | Description |
|---|---|
| **Modern LZMA2 One-Shot** | `lzma2.compress` and `lzma2.decompress` for single-call heap-allocated LZMA2 compression |
| **Legacy .lzma (Alone) Format** | `lzma.compress` / `lzma.decompress` (or `lzma2.alone.*`) supporting 13-byte header legacy files |
| **Raw LZMA Stream Format** | `lzma.compressRaw` and `lzma.decompressRaw` for headerless continuous streams |
| **Caller-Buffer Operations** | `compressInto` and `decompressInto` for zero-heap stack buffer allocation |
| **Streaming Operations** | `compressStream` and `decompressStream` for continuous reader/writer I/O pipelines |
| **Chunked Streaming** | `StreamingCompressor` and `StreamingDecompressor` for incremental piece-by-piece processing |
| **Compression Presets** | Preset levels (0 through 9) configuring dictionary size, match finder depth, and nice length |
| **Configurable Parameters** | Explicit dictionary size (up to 1 GiB), `lc` (literal context bits), `lp` (literal pos bits), `pb` (pos bits), and match finder modes |
| **XZ Property Conversion** | `dictSizeToProp` and `propToDictSize` following official XZ filter specification |
| **Reusable Compressor** | `lzma2.Compressor` (`init`, `compressAlloc`, `compressToSlice`, `reset`, `deinit`) |
| **Reusable Decompressor** | `lzma2.Decompressor` (`init`, `decompressAlloc`, `decompressToSlice`, `reset`) |
| **Stream Detection** | `lzma2.isLzma2Stream(data)` to inspect control bytes without decoding |
| **Resource Limits** | `max_output_size` and `dict_size_limit` controls to guard against resource exhaustion and decompression bombs |
| **Comprehensive Error Set** | Structured `DecompressError` and `CompressError` covering corrupted chunks, truncated input, and dictionary overflow |
| **Zero Dependencies** | Pure native Zig targeting standard toolchain Zig 0.17.0 |

</details>

---

## Format & Compatibility Overview

Understanding the distinction between raw codecs and archive/container formats:

| Format | Header / Framing | End-of-Stream Handling | Supported in `lzma2.zig` |
|---|---|---|:---:|
| **Raw LZMA2** | Per-chunk control bytes (`0x00`..`0xFF`) | Control byte `0x00` | **Yes** (`lzma2.compress`) |
| **Legacy `.lzma` (Alone)** | 13-byte header (props + dict_size + size) | EOS marker or declared size | **Yes** (`lzma.compress`) |
| **Raw LZMA** | None (pure range-coded stream) | Optional `0xFFFFFFFF` EOS marker | **Yes** (`lzma.compressRaw`) |
| **`.xz` Container** | Stream header, Block headers, CRC, Index | Stream footer | Handled in [`xz.zig`](https://github.com/muhammad-fiaz/xz.zig) |
| **`.7z` Archive** | Multi-file archive directory and headers | Block-level metadata | *External archive format* |

---

## Architecture & Source Code Layout

Every source file in `src/` is organized with clear functionality-based naming:

| Source Module | Primary Functionality | Public Re-exports / Aliases |
|---|---|---|
| [`src/lzma2.zig`](src/lzma2.zig) | Root LZMA2 package entry point, high-level API | Package root (`lzma2`) |
| [`src/lzma.zig`](src/lzma.zig) | Root LZMA package entry point, Markov state machine | Package root (`lzma`) |
| [`src/compress/container.zig`](src/compress/container.zig) | Legacy `.lzma` 13-byte container file compressor | `lzma.compress`, `lzma2.alone.compress` |
| [`src/compress/lzma.zig`](src/compress/lzma.zig) | Classic raw LZMA stream encoder, match finder pipeline | `lzma.compressRaw`, `lzma.Encoder` |
| [`src/compress/lzma2.zig`](src/compress/lzma2.zig) | LZMA2 chunk encoder, copy chunk fallback, reset modes | `lzma2.compress`, `lzma2.Compressor` |
| [`src/compress/streaming.zig`](src/compress/streaming.zig) | Streaming reader/writer pipelines for LZMA2 and `.lzma` | `lzma2.compressStream`, `lzma2.StreamingCompressor` |
| [`src/decompress/container.zig`](src/decompress/container.zig) | Legacy `.lzma` 13-byte container file decompressor | `lzma.decompress`, `lzma2.alone.decompress` |
| [`src/decompress/lzma.zig`](src/decompress/lzma.zig) | Classic raw LZMA stream decoder, reverse-tree decoding | `lzma.decompressRaw`, `lzma.Decoder` |
| [`src/decompress/lzma2.zig`](src/decompress/lzma2.zig) | LZMA2 chunk decoder, control-byte parsing | `lzma2.decompress`, `lzma2.Decompressor` |
| [`src/utils/range_codec.zig`](src/utils/range_codec.zig) | 32-bit adaptive binary range encoder and decoder | `lzma.range_codec`, `lzma2.range_codec` |
| [`src/utils/match_finder.zig`](src/utils/match_finder.zig) | Multi-level sliding-window match finder | `lzma.match_finder`, `lzma2.match_finder` |
| [`src/utils/state.zig`](src/utils/state.zig) | Shared Markov state transitions, length coders, pos slots | `lzma.state`, `lzma.LzmaState` |
| [`src/utils/options.zig`](src/utils/options.zig) | Compression options, presets, property converters | `lzma.options`, `lzma2.options` |
| [`src/utils/errors.zig`](src/utils/errors.zig) | Unified error sets for compression and decompression | `lzma.errors`, `lzma2.errors` |

---

## Installation

### Stable Release (Tagged)

```bash
zig fetch --save https://github.com/muhammad-fiaz/lzma2.zig/archive/refs/tags/0.1.0.tar.gz
```

### Nightly / Latest Development URL

```bash
zig fetch --save git+https://github.com/muhammad-fiaz/lzma2.zig.git
```

### Wire into `build.zig`

```zig
const lzma2_dep = b.dependency("lzma2", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("lzma2", lzma2_dep.module("lzma2"));
exe.root_module.addImport("lzma", lzma2_dep.module("lzma"));
```

---

## Quick Start & Examples

### 1. Modern LZMA2 Compression & Decompression

```zig
const std = @import("std");
const lzma2 = @import("lzma2");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const message = "Native LZMA2 compression in pure Zig 0.17.0! High-ratio dictionary encoding.";

    // 1. Compress with default options (level 6, 8 MiB dictionary)
    const compressed = try lzma2.compress(allocator, message, .{});
    defer allocator.free(compressed);

    // 2. Decompress
    const decompressed = try lzma2.decompress(allocator, compressed, .{});
    defer allocator.free(decompressed);

    std.debug.print("Original:     {s}\n", .{message});
    std.debug.print("Compressed:   {d} bytes\n", .{compressed.len});
    std.debug.print("Decompressed: {s}\n", .{decompressed});
}
```

### 2. Legacy `.lzma` (LZMA-Alone) File Format

```zig
const lzma = @import("lzma");

// Compress into standard 13-byte header .lzma file
const alone_file = try lzma.compress(allocator, message, .{});
defer allocator.free(alone_file);

// Decompress legacy .lzma file
const restored = try lzma.decompress(allocator, alone_file, .{});
defer allocator.free(restored);
```

### 3. Raw LZMA Stream Format

```zig
const lzma = @import("lzma");

// Compress into headerless raw LZMA range-coded stream
const raw_stream = try lzma.compressRaw(allocator, message, .{ .write_end_mark = true });
defer allocator.free(raw_stream);

// Decompress raw LZMA stream
const restored = try lzma.decompressRaw(allocator, raw_stream, .{ .uncompressed_size = null });
defer allocator.free(restored);
```

### 4. Zero-Allocation Caller Buffers

For embedded or latency-critical applications, `compressInto` and `decompressInto` avoid heap allocations entirely:

```zig
var comp_buf: [512]u8 = undefined;
const comp_len = try lzma2.compressInto(&comp_buf, message, .{ .level = 1 });

var decomp_buf: [512]u8 = undefined;
const decomp_len = try lzma2.decompressInto(&decomp_buf, comp_buf[0..comp_len], .{});
```

### 5. Streaming Pipelines & Reusable Contexts

Process arbitrary streams through incremental reader and writer pipelines or reuse compressor contexts:

```zig
// Stream compression
try lzma2.compressStream(allocator, &reader, &writer, .{});

// Stream decompression
try lzma2.decompressStream(allocator, &comp_reader, &decomp_writer, .{});

// Stateful context reuse to eliminate allocation churn
var compressor = try lzma2.Compressor.init(allocator, .{ .level = 6 });
defer compressor.deinit();

const chunk1 = try compressor.compressAlloc("first payload", .{});
defer allocator.free(chunk1);

compressor.reset(); // reuses pre-allocated dictionary and match buffers
const chunk2 = try compressor.compressAlloc("second payload", .{});
defer allocator.free(chunk2);
```

### 6. Configuration & Compression Presets

Configure compression presets (levels 0 through 9) or customize dictionary parameters:

```zig
// Preset levels: 0 (store mode) to 9 (maximum compression)
const opts = lzma2.CompressOptions{
    .level = 9,                     // Preset 9 (64 MiB dictionary)
    .dict_size = 32 * 1024 * 1024,  // Override dictionary to 32 MiB
    .lc = 3,                        // Literal context bits (0..8)
    .lp = 0,                        // Literal position bits (0..4)
    .pb = 2,                        // Position bits (0..4)
    .mode = .normal,                // 1-step lookahead match finder
};
const compressed = try lzma2.compress(allocator, message, opts);
defer allocator.free(compressed);
```

### 7. Defensive Error Handling & Size Limits

Handle corrupted input and defend against decompression bomb attacks:

```zig
const result = lzma2.decompress(allocator, hostile_payload, .{
    .max_output_size = 10 * 1024 * 1024, // 10 MiB threshold
    .dict_size_limit = 32 * 1024 * 1024, // 32 MiB dictionary cap
});

if (result) |decompressed| {
    defer allocator.free(decompressed);
} else |err| switch (err) {
    error.ExceededSizeLimit => std.debug.print("Payload exceeded 10 MiB limit\n", .{}),
    error.InvalidControlByte => std.debug.print("Malformed LZMA2 chunk header\n", .{}),
    error.CorruptData => std.debug.print("Corrupted range-coded bitstream\n", .{}),
    else => std.debug.print("Decompression failed: {}\n", .{err}),
}
```

---

## Runnable Examples

The `examples/` directory contains complete, runnable Zig 0.17.0 programs:

| Example | File | Description |
|---|---|---|
| `basic_compression` | [`examples/basic_compression.zig`](examples/basic_compression.zig) | LZMA2, `.lzma` container, and raw LZMA one-shot roundtrips |
| `caller_buffer` | [`examples/caller_buffer.zig`](examples/caller_buffer.zig) | Zero-allocation stack buffer operations |
| `configured_compression` | [`examples/configured_compression.zig`](examples/configured_compression.zig) | Custom presets, Markov parameters, and XZ property conversion |
| `reusable_context` | [`examples/reusable_context.zig`](examples/reusable_context.zig) | Context reuse, reader/writer streaming, and chunked writers |
| `error_handling` | [`examples/error_handling.zig`](examples/error_handling.zig) | Corrupt headers, zip-bomb size limits, buffer overflows |
| `lzma_compression` | [`examples/lzma_compression.zig`](examples/lzma_compression.zig) | Full `.lzma` container, raw streams with/without EOS, and pipeline streaming |
| `compression_levels` | [`examples/compression_levels.zig`](examples/compression_levels.zig) | Validation of compression presets (levels 0–9) across LZMA and LZMA2 |

Run any example:
```bash
zig build run-basic_compression
zig build run-caller_buffer
zig build run-configured_compression
zig build run-reusable_context
zig build run-error_handling
zig build run-lzma_compression
zig build run-compression_levels
zig build run-all-examples   # Run all examples in sequence
```

---

## Building & Verification

```bash
zig build                    # Build library and install artifacts
zig build test --summary all # Run all 67 unit and integration tests
zig build fuzz               # Run fuzz and edge-case validation suite
zig build check              # Validate compilation of library, tests, and examples
zig fmt --check src/ examples/ build.zig build.zig.zon
```

---

## Security Considerations & Limitations

- **Decompression Bombs**: LZMA2 data can achieve compression ratios exceeding 1,000:1. Always specify `max_output_size` when decompressing untrusted inputs to guard against resource exhaustion.
- **Memory Consumption**: High compression presets (level 7–9) allocate dictionary history buffers up to 64 MiB. In memory-constrained systems, use presets 1–4 or caller-provided buffer modes (`compressInto` / `decompressInto`).
- **Format Validation vs Security**: The decoder strictly rejects malformed chunk headers (`error.InvalidControlByte`), corrupt bitstreams (`error.CorruptData`), and invalid `.lzma` properties (`error.InvalidProperties`). However, callers are responsible for establishing application-level quotas.
- See [SECURITY.md](SECURITY.md) for vulnerability reporting guidelines.

---

## Documentation & API Reference

Comprehensive guides and API reference are available online and in `docs/`:

- [Documentation Portal](https://muhammad-fiaz.github.io/lzma2.zig/)
- [API Reference](https://muhammad-fiaz.github.io/lzma2.zig/api/)
- [Getting Started Guide](https://muhammad-fiaz.github.io/lzma2.zig/guide/getting-started)
- [Format & Chunk Notes](https://muhammad-fiaz.github.io/lzma2.zig/guide/format-notes)

Build docs locally:
```bash
cd docs && bun install && bun run build
```

---

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for code style guidelines and testing requirements.

## License

MIT License - see [LICENSE](LICENSE) for details.
