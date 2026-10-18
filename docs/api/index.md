# API Reference Overview

The `lzma2` package exports top-level compression and decompression functions, streaming engines, dictionary property utilities, options, and error sets.

Import the package:

```zig
const lzma2 = @import("lzma2");
```

---

## Top-Level Functions

### `lzma2.compress`
```zig
pub fn compress(allocator: std.mem.Allocator, src: []const u8, options: Options) ![]u8
```
Compresses `src` into a newly allocated slice containing a complete LZMA2 stream.
- **Parameters**:
  - `allocator`: Memory allocator for the output slice.
  - `src`: Uncompressed input bytes.
  - `options`: Compression parameters (preset, dictionary size, mode).
- **Returns**: Owned slice containing the compressed LZMA2 stream. Must be freed by caller using `allocator.free()`.
- **Errors**: `OutOfMemory`, `InvalidOptions`, `OutputTooSmall`.

---

### `lzma2.decompress`
```zig
pub fn decompress(allocator: std.mem.Allocator, src: []const u8, options: DecompressOptions) ![]u8
```
Decompresses an LZMA2 stream `src` into a newly allocated slice.
- **Parameters**:
  - `allocator`: Memory allocator for the output slice.
  - `src`: Compressed LZMA2 input stream.
  - `options`: Decompression parameters (`dict_size_limit`, `max_output_size`).
- **Returns**: Owned slice containing restored bytes. Must be freed by caller using `allocator.free()`.
- **Errors**: `OutOfMemory`, `ExceededSizeLimit`, `CorruptData`, `InvalidControlByte`, `DictionaryResetExpected`, `UnexpectedEof`.

---

### `lzma2.compressInto` / `lzma2.compressBuffer`
```zig
pub fn compressInto(dst: []u8, src: []const u8, options: Options) !usize
```
Compresses `src` directly into caller-provided buffer `dst` with **zero heap allocations**.
- **Returns**: The number of bytes written to `dst`.
- **Errors**: `OutputTooSmall`, `InvalidOptions`.

---

### `lzma2.decompressInto` / `lzma2.decompressBuffer`
```zig
pub fn decompressInto(dst: []u8, src: []const u8, options: DecompressOptions) !usize
```
Decompresses `src` directly into caller-provided buffer `dst` with **zero heap allocations**.
- **Returns**: The number of bytes written to `dst`.
- **Errors**: `OutputTooSmall`, `CorruptData`, `InvalidControlByte`, `DictionaryResetExpected`, `UnexpectedEof`.

---

### `lzma2.compressStream`
```zig
pub fn compressStream(allocator: std.mem.Allocator, reader: anytype, writer: anytype, options: Options) !void
```
Streams uncompressed data from `reader` and writes compressed LZMA2 chunks to `writer`.

---

### `lzma2.decompressStream`
```zig
pub fn decompressStream(allocator: std.mem.Allocator, reader: anytype, writer: anytype, options: DecompressOptions) !void
```
Streams compressed LZMA2 data from `reader` and writes restored uncompressed data to `writer`.

---

### `lzma2.propToDictSize`
```zig
pub fn propToDictSize(prop: u8) !u32
```
Converts an XZ / LZMA2 1-byte dictionary property (0..40) to dictionary size in bytes according to the official specification. Returns `error.InvalidProperties` if `prop > 40`.

---

### `lzma2.dictSizeToProp`
```zig
pub fn dictSizeToProp(dict_size: u32) !u8
```
Converts a dictionary size in bytes to the smallest valid XZ / LZMA2 1-byte property (0..40). Returns `error.InvalidOptions` if `dict_size < 4096` or `> 1 GiB`.

---

### `lzma2.maxCompressedSize`
```zig
pub fn maxCompressedSize(src_len: usize) usize
```
Returns a safe upper bound on the buffer capacity required to compress `src_len` bytes, accounting for uncompressed chunk expansion and control headers.

---

### `lzma2.isLzma2Stream`
```zig
pub fn isLzma2Stream(data: []const u8) bool
```
Inspects the first byte of `data` to check if it matches a valid LZMA2 chunk control byte (`0x00`, `0x01`, or `0xE0`..`0xFF`). Returns `false` for empty slices or invalid control bytes.

---

## Legacy `.lzma` Container API (`lzma` / `lzma2.alone`)

The `lzma` module provides full support for the legacy `.lzma` (LZMA-Alone) 13-byte header file format:

```zig
const lzma = @import("lzma");
```

### `lzma.compress`
```zig
pub fn compress(allocator: std.mem.Allocator, src: []const u8, options: AloneOptions) ![]u8
```
Compresses `src` into the standard 13-byte header `.lzma` file format. Automatically populates uncompressed size or emits an EOS marker if `unknown_size = true`.

### `lzma.decompress`
```zig
pub fn decompress(allocator: std.mem.Allocator, src: []const u8, options: DecompressOptions) ![]u8
```
Decompresses a legacy `.lzma` file, validating header properties and uncompressed size bounds.

### `lzma.compressInto` / `lzma.decompressInto`
Zero-allocation buffer-to-buffer compression and decompression for `.lzma` container files.

### `lzma.compressStream` / `lzma.decompressStream`
Streaming reader/writer adapters for `.lzma` container files.

---

## Raw LZMA Stream API (`lzma` / `lzma2.lzma`)

### `lzma.compressRaw`
```zig
pub fn compressRaw(allocator: std.mem.Allocator, src: []const u8, options: LzmaOptions) ![]u8
```
Compresses `src` into a raw LZMA stream without container headers. Supports repeated matches (rep0..3), short-rep, and optional EOS markers.

### `lzma.decompressRaw`
```zig
pub fn decompressRaw(allocator: std.mem.Allocator, src: []const u8, options: LzmaDecompressOptions) ![]u8
```
Decompresses a raw LZMA stream given known unpack size or EOS marker.

### `lzma.compressRawInto` / `lzma.decompressRawInto`
Zero-allocation caller-buffer compression and decompression for headerless raw LZMA streams.

### `lzma.compressRawStream` / `lzma.decompressRawStream`
Streaming reader/writer pipelines for headerless raw LZMA streams.

---

## Submodule Architecture

| Submodule | File | Description |
|---|---|---|
| `lzma2` | [`src/lzma2.zig`](file:///c:/Users/user/Downloads/lzma2/src/lzma2.zig) | Root LZMA2 package entry point, high-level API |
| `lzma` | [`src/lzma.zig`](file:///c:/Users/user/Downloads/lzma2/src/lzma.zig) | Root LZMA package entry point, Markov state machine |
| `lzma.compress_container` | [`src/compress/container.zig`](file:///c:/Users/user/Downloads/lzma2/src/compress/container.zig) | Legacy `.lzma` 13-byte container compressor |
| `lzma.compress_raw` | [`src/compress/lzma.zig`](file:///c:/Users/user/Downloads/lzma2/src/compress/lzma.zig) | Classic raw LZMA stream encoder |
| `lzma2.compress_mod` | [`src/compress/lzma2.zig`](file:///c:/Users/user/Downloads/lzma2/src/compress/lzma2.zig) | LZMA2 chunk encoder, copy fallback |
| `lzma2.streaming` | [`src/compress/streaming.zig`](file:///c:/Users/user/Downloads/lzma2/src/compress/streaming.zig) | Streaming pipelines and chunked stream state |
| `lzma.decompress_container` | [`src/decompress/container.zig`](file:///c:/Users/user/Downloads/lzma2/src/decompress/container.zig) | Legacy `.lzma` 13-byte container decompressor |
| `lzma.decompress_raw` | [`src/decompress/lzma.zig`](file:///c:/Users/user/Downloads/lzma2/src/decompress/lzma.zig) | Classic raw LZMA stream decoder |
| `lzma2.decompress_mod` | [`src/decompress/lzma2.zig`](file:///c:/Users/user/Downloads/lzma2/src/decompress/lzma2.zig) | LZMA2 chunk decoder, control-byte parsing |
| `lzma.range_codec` | [`src/utils/range_codec.zig`](file:///c:/Users/user/Downloads/lzma2/src/utils/range_codec.zig) | Adaptive binary range encoder and decoder |
| `lzma.match_finder` | [`src/utils/match_finder.zig`](file:///c:/Users/user/Downloads/lzma2/src/utils/match_finder.zig) | Sliding-window match finder (2B, 3B, 4B hashing) |
| `lzma.state` | [`src/utils/state.zig`](file:///c:/Users/user/Downloads/lzma2/src/utils/state.zig) | Markov state machine, length coders, pos slots |
| `lzma.options` | [`src/utils/options.zig`](file:///c:/Users/user/Downloads/lzma2/src/utils/options.zig) | Options, presets, and XZ property converters |
| `lzma.errors` | [`src/utils/errors.zig`](file:///c:/Users/user/Downloads/lzma2/src/utils/errors.zig) | Unified error sets for compression and decompression |
