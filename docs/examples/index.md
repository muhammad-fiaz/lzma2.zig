# Examples Overview

The `examples/` directory contains standalone, compiling example programs showcasing real-world usage of `lzma2.zig` across all supported codecs, memory models, and streaming patterns.

Every example file can be compiled and executed directly via `zig build`.

---

## Example Directory

| Example Guide | Source File | Codecs / Features | Memory Model |
|---|---|---|---|
| [**Basic Compression**](./basic_compression.md) | [`examples/basic_compression.zig`](https://github.com/muhammad-fiaz/lzma2.zig/blob/main/examples/basic_compression.zig) | LZMA2, `.lzma` Container, Raw LZMA | Dynamic allocation (`smp_allocator`) |
| [**Caller Buffers**](./caller_buffer.md) | [`examples/caller_buffer.zig`](https://github.com/muhammad-fiaz/lzma2.zig/blob/main/examples/caller_buffer.zig) | `compressInto`, `decompressInto`, `lzma.*Into` | **Zero-allocation** (Stack / fixed buffers) |
| [**Configured Compression**](./configured_compression.md) | [`examples/configured_compression.zig`](https://github.com/muhammad-fiaz/lzma2.zig/blob/main/examples/configured_compression.zig) | Presets (0–9), Dict Sizes (4 KiB–1 GiB), `lc/lp/pb`, Match Finder (`.fast`/`.normal`), XZ props | Dynamic allocation |
| [**Reusable Context & Streaming**](./reusable_context.md) | [`examples/reusable_context.zig`](https://github.com/muhammad-fiaz/lzma2.zig/blob/main/examples/reusable_context.zig) | `Compressor.reset()`, `compressStream`, `StreamingCompressor`, `lzma.compressStream` | Context reuse & chunked I/O streams |
| [**Error Handling & Limits**](./error_handling.md) | [`examples/error_handling.zig`](https://github.com/muhammad-fiaz/lzma2.zig/blob/main/examples/error_handling.zig) | Invalid control bytes, Zip bomb defense (`max_output_size`), buffer bounds, invalid headers | Defensive validation & resource limits |
| [**LZMA Codec**](./lzma_compression.md) | [`examples/lzma_compression.zig`](https://github.com/muhammad-fiaz/lzma2.zig/blob/main/examples/lzma_compression.zig) | `.lzma` container, raw headerless LZMA with/without EOS, streaming I/O | Dynamic & zero-allocation |
| [**Compression Levels (0–9)**](./compression_levels.md) | [`examples/compression_levels.zig`](https://github.com/muhammad-fiaz/lzma2.zig/blob/main/examples/compression_levels.zig) | Comprehensive validation of levels 0 through 9 across LZMA and LZMA2 | Dynamic allocation |

---

## What Each Example Covers

### 1. [Basic Compression](./basic_compression.md)
Demonstrates one-shot in-memory compression and decompression for:
- Modern LZMA2 streams (`lzma2.compress` / `lzma2.decompress`)
- Legacy `.lzma` file container format with 13-byte headers (`lzma.compress` / `lzma.decompress` or `lzma2.alone`)
- Raw headerless LZMA streams with EOS markers (`lzma.compressRaw` / `lzma.decompressRaw` or `lzma2.lzma`)

### 2. [Caller-Provided Buffers](./caller_buffer.md)
Demonstrates zero-allocation operations using pre-allocated stack buffers:
- `lzma2.compressInto` and `lzma2.decompressInto`
- `lzma.compressInto` and `lzma.decompressInto`
- `lzma.compressRawInto` and `lzma.decompressRawInto`
- Ideal for embedded environments, kernel modules, and latency-critical systems where dynamic heap allocations are prohibited.

### 3. [Configured Compression](./configured_compression.md)
Demonstrates tuning compression parameters to balance ratio and speed:
- Compression presets from Level 0 (store mode) to Level 9 (maximum compression)
- Custom dictionary sizes from 4 KiB to 1 GiB
- Fine-grained Markov probability tuning with `lc` (literal context), `lp` (literal position), and `pb` (position bits)
- Selecting between `.fast` (greedy) and `.normal` (1-step lookahead) match finder modes
- Converting between dictionary sizes and XZ-compliant 1-byte properties (`dictSizeToProp` / `propToDictSize`)

### 4. [Reusable Context & Streaming I/O](./reusable_context.md)
Demonstrates high-throughput server and pipeline patterns:
- Stateful `Compressor` and `Decompressor` reuse with `.reset()` to avoid repeated allocation churn across sequential jobs
- Explicit I/O stream pipelines using standard duck-typed reader/writer adapters (`compressStream` / `decompressStream`)
- Incremental chunk streaming with `StreamingCompressor` (`write` / `finish`) and `StreamingDecompressor` (`feed` / `take`)
- Legacy `.lzma` archive streaming with `lzma.compressStream` and `lzma.decompressStream`

### 5. [Error Handling & Resource Limits](./error_handling.md)
Demonstrates defensive engineering against corrupted or malicious inputs:
- Catching `error.InvalidControlByte` when decoding malformed LZMA2 chunk headers
- Enforcing `max_output_size` limits to protect against decompression bomb (zip bomb) attacks with `error.ExceededSizeLimit`
- Bounds-checking destination buffers to avoid overflows with `error.OutputTooSmall`
- Rejecting corrupted legacy `.lzma` container headers with `error.InvalidProperties`

### 6. [LZMA Codec](./lzma_compression.md)
Dedicated guide to the raw LZMA (LZMA1) and legacy `.lzma` container features:
- In-memory `.lzma` container compression and decompression
- Raw headerless LZMA streaming with and without End-of-Stream (EOS) markers
- Chunked and reader/writer streaming pipelines for legacy streams

### 7. [Compression Presets & Levels (0–9)](./compression_levels.md)
Validates and demonstrates compression presets across Levels 0 through 9:
- Compares compressed byte lengths, compression presets, and integrity verification across all levels for both LZMA and LZMA2.

---

## Running the Examples

You can run individual examples or execute all of them in sequence using `zig build`:

```bash
# Run individual examples
zig build run-basic_compression
zig build run-caller_buffer
zig build run-configured_compression
zig build run-reusable_context
zig build run-error_handling
zig build run-lzma_compression
zig build run-compression_levels

# Run all examples in sequence
zig build run-all-examples
```
