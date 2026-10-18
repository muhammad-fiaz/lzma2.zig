# Errors

`lzma2.zig` uses structured error sets to differentiate decoding corruption, configuration errors, and capacity limits.

---

## `DecompressError`

Errors that may be returned during decompression:

```zig
pub const DecompressError = error{
    /// Input ended prematurely before the end of stream marker or within a chunk.
    TruncatedInput,
    /// Encountered an unrecognized or invalid control byte.
    InvalidControlByte,
    /// Properties byte violated constraints (e.g. lc + lp > 4 or pb > 4).
    InvalidProperties,
    /// Uncompressed chunk size exceeded protocol limits (e.g. > 64 KiB for uncompressed chunks).
    InvalidChunkSize,
    /// Encoded compressed payload was corrupt or range decoder failed.
    CorruptData,
    /// Match back-reference pointed beyond previous decoded data or dictionary boundary.
    DictionaryOverflow,
    /// Decompressed stream exceeded configured max_output_size (decompression bomb guard).
    OutputLimitExceeded,
    /// Destination buffer supplied by caller was too small to hold unpacked output.
    DestinationBufferTooSmall,
    /// Out of memory allocating output slice or dictionary structures.
    OutOfMemory,
};
```

---

## `CompressError`

Errors that may be returned during compression:

```zig
pub const CompressError = error{
    /// Supplied options violated LZMA2 rules (e.g. invalid dictionary size or properties).
    InvalidProperties,
    /// Range encoder or chunk assembler failed during compression.
    CompressFailed,
    /// Destination buffer supplied by caller was too small to hold compressed stream.
    DestinationBufferTooSmall,
    /// Out of memory allocating output slice or internal compressor buffers.
    OutOfMemory,
};
```

---

## `Error`

Combined error set:

```zig
pub const Error = DecompressError || CompressError;
```
