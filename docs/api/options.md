# Options & Presets

`lzma2.zig` provides structured types and conversion utilities to configure compression, decompression, and dictionary behavior.

---

## `lzma2.Options`

Configuration struct used by `lzma2.compress()` and `lzma2.Compressor`:

```zig
pub const Options = struct {
    level: u4 = Preset.default_level,   // 0 (store) .. 9 (maximum), default 6
    dict_size: ?u32 = null,             // 4 KiB .. 1 GiB (automatic based on level if null)
    lc: u4 = DEFAULT_LC,                // Literal context bits (0..4, default 3)
    lp: u4 = DEFAULT_LP,                // Literal position bits (0..4, default 0)
    pb: u4 = DEFAULT_PB,                // Position bits (0..4, default 2)
    mode: ?Mode = null,                 // .fast or .normal
    depth: u32 = 0,                     // Match search depth limit (0 = automatic)
    nice_len: u16 = 64,                 // Nice length threshold (2..273)
};
```

### Constraints:
- `dict_size` must be between `4 KiB` and `1 GiB`.
- `lc + lp <= 4` and `pb <= 4` (LZMA2 specification requirement). If violated, compression functions return `error.InvalidOptions`.

---

## `lzma2.Preset`

Standard compression levels:

| Level | Name | Dictionary Size | Search Mode | Depth |
|---|---|---|---|---|
| `0` | `.store` | 4 KiB | N/A (uncompressed copy) | 0 |
| `1` | `.fastest` | 64 KiB | `.fast` | 8 |
| `3` | `.fast` | 1 MiB | `.fast` | 24 |
| `6` | `.default_level` | 8 MiB | `.normal` | 64 |
| `9` | `.maximum` | 64 MiB | `.normal` | 256 |

---

## `lzma2.DecompressOptions`

Configuration struct used by `lzma2.decompress()` and `lzma2.Decompressor`:

```zig
pub const DecompressOptions = struct {
    max_output_size: usize = std.math.maxInt(usize),
    dict_size_limit: usize = 1024 * 1024 * 1024,
};
```

- `max_output_size`: Output cap to prevent decompression bombs. If the unpacked stream exceeds this size, the decoder returns `error.ExceededSizeLimit`.
- `dict_size_limit`: Maximum allowed dictionary memory in bytes. Default is 1 GiB.

---

## Dictionary Property Functions

### `lzma2.propToDictSize`
```zig
pub fn propToDictSize(prop: u8) !u32
```
Converts an XZ / LZMA2 1-byte dictionary property (0..40) to dictionary size in bytes:
- Bits 7-6: Reserved, must be 0 (values > 40 return `error.InvalidProperties`).
- Bits 5-0:
  - If bit 0 is 0: `dict_size = 2 << (bits[5:1] + 11)`
  - If bit 0 is 1: `dict_size = 3 << (bits[5:1] + 11)`
  - If property is 40: `dict_size = 0xFFFFFFFF` (4 GiB - 1)

### `lzma2.dictSizeToProp`
```zig
pub fn dictSizeToProp(dict_size: u32) !u8
```
Converts a dictionary size in bytes to the smallest valid 1-byte property (0..40).
