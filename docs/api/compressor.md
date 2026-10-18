# `lzma2.Compressor`

Stateful, reusable LZMA2 compressor context. Pre-allocates match finder structures and range coder buffers once, allowing multiple streams to be compressed with zero repeated allocation overhead.

---

## Type Definition

```zig
pub const Compressor = struct {
    allocator: std.mem.Allocator,
    options: Options,

    pub fn init(allocator: std.mem.Allocator, options: Options) !Compressor;
    pub fn deinit(self: *Compressor) void;
    pub fn reset(self: *Compressor, options: Options) void;
    pub fn compress(self: *Compressor, src: []const u8) ![]u8;
    pub fn compressBuffer(self: *Compressor, src: []const u8, dst: []u8) !usize;
};
```

---

## Methods

### `init`
```zig
pub fn init(allocator: std.mem.Allocator, options: Options) !Compressor
```
Initializes the compressor context and allocates internal state.
- **Errors**: `OutOfMemory`.

### `deinit`
```zig
pub fn deinit(self: *Compressor) void
```
Frees all internal resources and buffers associated with the compressor.

### `reset`
```zig
pub fn reset(self: *Compressor, options: Options) void
```
Resets the compressor's state to begin a new stream, optionally updating the configuration options. Does not free underlying allocated capacity.

### `compress`
```zig
pub fn compress(self: *Compressor, src: []const u8) ![]u8
```
Compresses `src` into a newly allocated output buffer.
- **Returns**: Owned slice containing the compressed LZMA2 stream. Must be freed by caller using `self.allocator.free()`.
- **Errors**: `OutOfMemory`, `InvalidProperties`, `CompressFailed`.

### `compressBuffer`
```zig
pub fn compressBuffer(self: *Compressor, src: []const u8, dst: []u8) !usize
```
Compresses `src` directly into caller-provided buffer `dst` with zero heap allocations.
- **Returns**: Number of bytes written to `dst`.
- **Errors**: `DestinationBufferTooSmall`, `InvalidProperties`, `CompressFailed`.
