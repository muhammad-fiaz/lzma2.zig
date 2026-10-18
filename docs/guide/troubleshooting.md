# Troubleshooting & Frequently Asked Questions

This guide covers common errors, edge cases, and architectural questions when integrating `lzma2.zig`.

---

## 1. Common Errors & Solutions

### `error.InvalidControlByte`
- **Cause**: The decoder encountered a byte other than `0x00`, `0x01`, `0x02`, or `0x80`..`0xFF` at a chunk boundary.
- **Common Cause**: You may be passing a complete `.xz` archive file rather than a raw LZMA2 stream. Remember that `.xz` files begin with the container header `\xFD7zXZ\x00` rather than an LZMA2 control byte.
- **Fix**: Strip the container header or pass only the raw LZMA2 block stream to `lzma2.decompress()`.

### `error.DestinationBufferTooSmall`
- **Cause**: When using `compressBuffer()` or `decompressBuffer()`, the destination slice does not have enough capacity to hold the output.
- **Fix for Compression**: Use `lzma2.maxCompressedSize(input_len)` to allocate an adequate destination buffer.
- **Fix for Decompression**: Provide a larger buffer or switch to `lzma2.decompress(allocator, ...)`, which automatically grows the output slice.

### `error.OutputLimitExceeded`
- **Cause**: The stream attempted to decompress more bytes than allowed by `max_output_size`.
- **Fix**: If the input is trusted and legitimately large, increase `max_output_size` in `DecompressOptions`.

### `error.DictionaryOverflow`
- **Cause**: A match back-reference in the stream points to a distance beyond the configured dictionary window or prior decoded output.
- **Fix**: Ensure the decoder's `dict_size` is at least as large as the dictionary size used during compression.

---

## 2. Frequently Asked Questions (FAQ)

### Can `lzma2.zig` open `.xz` or `.7z` files directly?
`lzma2.zig` is a codec library for the raw LZMA2 stream protocol. Full `.xz` and `.7z` archives include archive headers, block metadata, and integrity checksums (such as CRC-32 and CRC-64). To unpack these archives, use an archive container parser and pass the extracted LZMA2 blocks to `lzma2.zig`.

### Is `lzma2.zig` thread-safe?
All top-level functions (`compress`, `decompress`, `compressBuffer`, `decompressBuffer`) are fully re-entrant and thread-safe. When using stateful `Compressor` or `Decompressor` instances, each thread must own its own instance.

### Does `lzma2.zig` support streaming reader/writer interfaces?
Yes, using the caller-buffer and chunked APIs. Native `std.Io.Reader` and `std.Io.Writer` adapters can feed chunk buffers incrementally into `Compressor` and `Decompressor`.
