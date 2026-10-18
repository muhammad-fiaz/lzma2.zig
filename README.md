<div align="center">

# lzma2.zig

<a href="https://muhammad-fiaz.github.io/lzma2.zig/"><img src="https://img.shields.io/badge/docs-muhammad--fiaz.github.io-blue" alt="Documentation"></a>
<a href="https://ziglang.org/"><img src="https://img.shields.io/badge/Zig-0.17.0%20or%20later-orange.svg?logo=zig" alt="Zig Version"></a>
<a href="https://github.com/muhammad-fiaz/lzma2.zig"><img src="https://img.shields.io/github/stars/muhammad-fiaz/lzma2.zig" alt="GitHub stars"></a>
<a href="https://github.com/muhammad-fiaz/lzma2.zig/issues"><img src="https://img.shields.io/github/issues/muhammad-fiaz/lzma2.zig" alt="GitHub issues"></a>
<a href="https://github.com/muhammad-fiaz/lzma2.zig/pulls"><img src="https://img.shields.io/github/issues-pr/muhammad-fiaz/lzma2.zig" alt="GitHub pull requests"></a>
<a href="https://github.com/muhammad-fiaz/lzma2.zig"><img src="https://img.shields.io/github/last-commit/muhammad-fiaz/lzma2.zig" alt="GitHub last commit"></a>
<a href="https://github.com/muhammad-fiaz/lzma2.zig/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License"></a>
<a href="https://github.com/muhammad-fiaz/lzma2.zig/actions/workflows/ci.yml"><img src="https://github.com/muhammad-fiaz/lzma2.zig/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<img src="https://img.shields.io/badge/platforms-linux%20%7C%20windows%20%7C%20macos-blue" alt="Supported Platforms">
<a href="https://github.com/muhammad-fiaz/lzma2.zig/releases/latest"><img src="https://img.shields.io/github/v/release/muhammad-fiaz/lzma2.zig?label=Latest%20Release&style=flat-square" alt="Latest Release"></a>
<a href="https://pay.muhammadfiaz.com"><img src="https://img.shields.io/badge/Sponsor-pay.muhammadfiaz.com-ff69b4?style=flat&logo=heart" alt="Sponsor"></a>
<a href="https://github.com/sponsors/muhammad-fiaz"><img src="https://img.shields.io/badge/Sponsor-GitHub-pink?style=social&logo=github" alt="GitHub Sponsors"></a>
<a href="https://hits.sh/muhammad-fiaz/lzma2.zig/"><img src="https://hits.sh/muhammad-fiaz/lzma2.zig.svg?label=Visitors&extraCount=0&color=green" alt="Repo Visitors"></a>

<p><em>Native Zig LZMA2 and LZMA compression library.</em></p>

<b><a href="https://muhammad-fiaz.github.io/lzma2.zig/">Documentation</a> |
<a href="https://muhammad-fiaz.github.io/lzma2.zig/api/">API Reference</a> |
<a href="https://muhammad-fiaz.github.io/lzma2.zig/guide/getting-started">Quick Start</a> |
<a href="CONTRIBUTING.md">Contributing</a></b>

</div>

`lzma2.zig` is a modern, high-performance LZMA2 and legacy LZMA compression library for Zig, providing everything needed to compress and decompress data with high compression ratios, robust streaming pipelines, zero external C dependencies, and zero-allocation caller buffers.

> [!TIP]
> If you build with lzma2.zig, make sure to give it a star.

> [!NOTE]
> **Project maturity:** This project is production-ready, targeting stable **Zig 0.17.0 or later**. Engineered from first principles in 100% native Zig with zero external dependencies, no `@cImport`, and zero C/C++ runtime requirements (`link_libc = false`).
>
> **Comprehensive Native Subsystems:**
> - **Modern LZMA2 Codec**: Chunked protocol with uncompressed copy chunks (`0x01`, `0x02`), compressed LZMA chunks (`0x80`..`0xFF`), all 4 reset modes (state, dictionary, properties), and EOS control byte (`0x00`).
> - **Legacy LZMA (.lzma) Support**: Standard 13-byte Alone header parsing and encoding with declared uncompressed sizes or end-of-stream (EOS) markers, plus raw continuous range-coded streams.
> - **Range Engine & Match Finder**: 32-bit adaptive binary range coder with normalized probability transitions, 12-state Markov models, and multi-level sliding-window match finding.
> - **Zero-Allocation Stack Modes**: Caller-provided output buffers (`compressInto` / `decompressInto`) for constrained systems and embedded environments.
> - **Incremental Streaming**: First-class reader/writer streaming pipelines (`compressStream`, `decompressStream`) with bounded memory usage.
> - **Context Reuse**: Reusable `Compressor` and `Decompressor` contexts eliminate allocation churn across high-frequency compression workloads.
> - **Decompression Bomb Protection**: Built-in `max_output_size` limits and strict bitstream validation protect against memory exhaustion.

**Related Zig projects:**

- For **XZ container format** support, check out **[xz.zig](https://github.com/muhammad-fiaz/xz.zig)**.
- For **HTTP client & server** support, check out **[httpx.zig](https://github.com/muhammad-fiaz/httpx.zig)**.
- For **Env.zig** (.env parsing), check out **[env.zig](https://github.com/muhammad-fiaz/env.zig)**.
- For **TUI** support, check out **[tui.zig](https://github.com/muhammad-fiaz/tui.zig)**.
- For **ZON file format** support, check out **[zon.zig](https://github.com/muhammad-fiaz/zon.zig)**.
- For **Spinners/loading/progress bar** support, check out **[loaders.zig](https://github.com/muhammad-fiaz/loaders.zig)**.
- For **Terminal colors & text styles** support, check out **[tint.zig](https://github.com/muhammad-fiaz/tint.zig)**.
- For **MCP** support, check out **[mcp.zig](https://github.com/muhammad-fiaz/mcp.zig)**.
- For **API framework** support, check out **[api.zig](https://github.com/muhammad-fiaz/api.zig)**.
- For **Web framework** support, check out **[zix](https://github.com/muhammad-fiaz/zix)**.
- For **archive/compression** support, check out **[archive.zig](https://github.com/muhammad-fiaz/archive.zig)**.
- For **compression file format** support, check out **[zigx](https://github.com/muhammad-fiaz/zigx)**.
- For **CUDA** support, check out **[cuda.zig](https://github.com/muhammad-fiaz/cuda.zig)**.
- For **Simplified build.zig config** support, check out **[buildx.zig](https://github.com/muhammad-fiaz/buildx.zig)**.
- For **SQLite (zig-native implementation)** support, check out **[sqlite.zig](https://github.com/muhammad-fiaz/sqlite.zig)**.
- For **File downloading** support, check out **[downloader.zig](https://github.com/muhammad-fiaz/downloader.zig)**.
- For **update checker/auto-updater** support, check out **[updater.zig](https://github.com/muhammad-fiaz/updater.zig)**.
- For **Numerical computing** support, check out **[num.zig](https://github.com/muhammad-fiaz/num.zig)**.
- For **Logging** support, check out **[logly.zig](https://github.com/muhammad-fiaz/logly.zig)**.
- For **Data validation and serialization** support, check out **[zigantic](https://github.com/muhammad-fiaz/zigantic)**.
- For **UUID** support, check out **[uuid.zig](https://github.com/muhammad-fiaz/uuid.zig)**.
- For **Key-Value database** support, check out **[zkv.zig](https://github.com/muhammad-fiaz/zkv.zig)**.
- For **Terminal color & text styles** support, check out **[hint.zig](https://github.com/muhammad-fiaz/hint.zig)**.
- For **Brotli compression** support, check out **[brotli.zig](https://github.com/muhammad-fiaz/brotli.zig)**.
- For **Zstd compression** support, check out **[zstd.zig](https://github.com/muhammad-fiaz/zstd.zig)**.
- For **Tree-Sitter** support, check out **[tree-sitter.zig](https://github.com/muhammad-fiaz/tree-sitter.zig)**.

---

<details>
<summary><strong>Features</strong> (click to expand)</summary>

| Feature | Description |
|---------|-------------|
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

<details>
<summary><strong>Prerequisites and Supported Platforms</strong> (click to expand)</summary>

<br>

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| **Zig** | **0.17.0 or later** (required) | Download from [ziglang.org](https://ziglang.org/download/) |
| **Operating System** | Windows 10+, Linux, macOS, Freestanding | Native cross-platform support |

> [!IMPORTANT]
> **Zig 0.17.0 or later is required.** This project targets the stable Zig 0.17.0 and later releases. Earlier Zig versions (0.16.x or older) are not supported.

---

## Supported Platforms

| Platform | x86_64 (64-bit) | aarch64 (ARM64) | x86 (32-bit) | arm / thumb | riscv32 | freestanding |
|----------|:---------------:|:---------------:|:------------:|:-----------:|:-------:|:------------:|
| **Linux** | Yes | Yes | Yes | Yes | Yes | — |
| **Windows** | Yes | Yes | Yes | — | — | — |
| **macOS** | Yes | Yes (Apple Silicon) | — | — | — | — |
| **Freestanding** | — | — | Yes | — | — | Yes |

### Cross-Compilation

```bash
# Build for Linux ARM64 from Windows
zig build -Dtarget=aarch64-linux

# Build for Windows from Linux
zig build -Dtarget=x86_64-windows

# Build for macOS Apple Silicon from Linux
zig build -Dtarget=aarch64-macos

# Build for 32-bit Windows
zig build -Dtarget=x86-windows

# Build for freestanding embedded targets
zig build -Dtarget=x86-freestanding
```

</details>

---

## Installation

### Method 1: Zig Fetch (Recommended)

**Latest Release (0.0.1)**

```bash
zig fetch --save https://github.com/muhammad-fiaz/lzma2.zig/archive/refs/tags/0.0.1.tar.gz
```

> [!NOTE]
> Zig **0.17.0 or later** is required by **0.0.1**.

### Method 2: Zig Fetch (Latest Development Build)

Use this for the latest development build from the `main` branch:

```bash
zig fetch --save git+https://github.com/muhammad-fiaz/lzma2.zig.git
```

### Method 3: Manual `build.zig.zon` Configuration

```zig
.dependencies = .{
    .lzma2 = .{
        .url = "https://github.com/muhammad-fiaz/lzma2.zig/archive/refs/tags/0.0.1.tar.gz",
        .hash = "...", // Run `zig fetch --save <url>` to generate the hash.
    },
},
```

### Method 4: Local Source Checkout

```bash
git clone https://github.com/muhammad-fiaz/lzma2.zig.git
cd lzma2.zig
zig build
```

To use a local checkout from another project:

```zig
.dependencies = .{
    .lzma2 = .{
        .path = "../lzma2.zig",
    },
},
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

## Quick Start

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

## Validation Matrix & Testing

```bash
zig build                    # Build library and install artifacts
zig build test --summary all # Run all 67 unit and integration tests
zig build fuzz               # Run fuzz and edge-case validation suite
zig build check              # Validate compilation of library, tests, and examples
zig fmt --check src/ examples/ build.zig build.zig.zon
```

### Cross-Compilation Validation

Validate compilation across foreign target architectures:

```bash
zig build -Dtarget=aarch64-linux
zig build -Dtarget=x86_64-windows
zig build -Dtarget=aarch64-macos
zig build -Dtarget=x86-freestanding
```

---

## Security & Resource Management

`lzma2.zig` is designed to process untrusted inputs safely. Key protections include:

| Protection | Mechanism |
|---|---|
| **Decompression Bomb (CWE-409)** | `DecompressOptions.max_output_size` caps uncompressed output; `error.ExceededSizeLimit` on breach |
| **Dictionary Memory Bounds** | `DecompressOptions.dict_size_limit` restricts peak allocation before dictionary is created |
| **Zero-Allocation Execution** | `compressInto` / `decompressInto` operate on caller buffers with no heap use; `error.OutputTooSmall` on overflow |
| **Bitstream Integrity** | Chunk control byte validation, range-coded bitstream integrity, and property byte range enforcement |
| **Preset Scaling (0–9)** | Dictionaries from 4 KiB (preset 0) to 64 MiB (preset 9); stateful context reuse via `.reset()` |

See [SECURITY.md](SECURITY.md) for vulnerability reporting guidelines and full resource-exhaustion guidance.

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

## Project Structure

```text
lzma2.zig/
├── src/
│   ├── lzma2.zig                   # Root LZMA2 package entry point & public API
│   ├── lzma.zig                    # Root LZMA package entry point & Markov state
│   ├── compress/
│   │   ├── lzma2.zig               # LZMA2 chunk compressor, copy chunk fallback
│   │   ├── lzma.zig                # Classic raw LZMA stream encoder
│   │   ├── container.zig           # Legacy 13-byte header .lzma file compressor
│   │   └── streaming.zig           # Reader/writer stream compressor pipelines
│   ├── decompress/
│   │   ├── lzma2.zig               # LZMA2 chunk decoder & control-byte parsing
│   │   ├── lzma.zig                # Classic raw LZMA stream decoder
│   │   ├── container.zig           # Legacy 13-byte header .lzma file decompressor
│   │   └── streaming.zig           # Reader/writer stream decompressor pipelines
│   └── utils/
│       ├── range_codec.zig         # 32-bit adaptive binary range encoder/decoder
│       ├── match_finder.zig        # Multi-level sliding-window match finder
│       ├── state.zig               # Markov state transitions, length coders
│       ├── options.zig             # Compression options, presets, converters
│       └── errors.zig              # Structured error sets for compress/decompress
├── examples/                       # Runnable standalone Zig examples
│   ├── basic_compression.zig       # LZMA2, .lzma, and raw LZMA roundtrips
│   ├── caller_buffer.zig           # Zero-allocation stack buffer operations
│   ├── compression_levels.zig      # Presets (levels 0 through 9) validation
│   ├── configured_compression.zig  # Custom Markov parameters & XZ conversion
│   ├── error_handling.zig          # Corrupt headers, bomb limits, buffer overflows
│   ├── lzma_compression.zig        # Full .lzma container and raw stream pipelines
│   └── reusable_context.zig        # Reusable context & chunk streaming
├── docs/                           # VitePress documentation portal
├── build.zig                       # Build system definition
├── build.zig.zon                   # Package metadata
├── README.md
├── SECURITY.md
├── LICENSE
└── CONTRIBUTING.md
```

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

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass: `zig build test --summary all`
5. Submit a pull request

See [CONTRIBUTING.md](CONTRIBUTING.md) for code style guidelines and testing requirements.

## License

MIT License - see [LICENSE](LICENSE) for details.
