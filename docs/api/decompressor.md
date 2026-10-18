# `lzma2.Decompressor`

Stateful, reusable LZMA2 decompressor context. Allocates internal sliding dictionary buffers once, allowing multiple streams to be decoded with zero repeated allocation overhead.

---

## Type Definition

```zig
pub const Decompressor = struct {
    allocator: std.mem.Allocator,
    options: DecompressOptions,

    pub fn init(allocator: std.mem.Allocator, options: DecompressOptions) !Decompressor;
    pub fn deinit(self: *Decompressor) void;
    pub fn reset(self: *Decompressor, options: DecompressOptions) void;
    pub fn decompress(self: *Decompressor, src: []const u8) ![]u8;
    pub fn decompressBuffer(self: *Decompressor, src: []const u8, dst: []u8) !usize;
};
```

---

## Methods

### `init`
```zig
pub fn init(allocator: std.mem.Allocator, options: DecompressOptions) !Decompressor
```
Initializes the decompressor context and pre-allocates internal state.
- **Errors**: `OutOfMemory`.

### `deinit`
```zig
pub fn deinit(self: *Decompressor) void
```
Frees all internal resources and buffers associated with the decompressor.

### `reset`
```zig
pub fn reset(self: *Decompressor, options: DecompressOptions) void
```
Resets the decompressor's internal state to begin decoding a new stream, optionally updating options.

### `decompress`
```zig
pub fn decompress(self: *Decompressor, src: []const u8) ![]u8
```
Decompresses `src` into a newly allocated output buffer.
- **Returns**: Owned slice containing restored bytes. Must be freed by caller using `self.allocator.free()`.
- **Errors**: `OutOfMemory`, `OutputLimitExceeded`, `CorruptData`, `InvalidControlByte`, `DictionaryOverflow`, `TruncatedInput`.

### `decompressBuffer`
```zig
pub fn decompressBuffer(self: *Decompressor, src: []const u8, dst: []u8) !usize
```
Decompresses `src` directly into caller-provided buffer `dst` with zero heap allocations.
- **Returns**: Number of bytes written to `dst`.
- **Errors**: `DestinationBufferTooSmall`, `CorruptData`, `InvalidControlByte`, `DictionaryOverflow`, `TruncatedInput`.
