//! Options and constants for LZMA2 compression and decompression.

const std = @import("std");
const errors = @import("errors.zig");

/// Library version.
pub const version = "0.0.1";

/// Converts an XZ / LZMA2 1-byte dictionary property (0..40) to dictionary size in bytes.
///
/// Follows the official XZ specification (Section 5.3.1):
/// - Bits 7-6: Reserved, must be 0 (values > 40 return error.InvalidProperties).
/// - Bits 5-0:
///   - If bit 0 is 0: dict_size = 2 << (bits[5:1] + 11)
///   - If bit 0 is 1: dict_size = 3 << (bits[5:1] + 11)
///   - If property is 40 (0x28): dict_size = 0xFFFFFFFF (4 GiB - 1)
pub fn propToDictSize(prop: u8) errors.DecompressError!u32 {
    if (prop > 40) return error.InvalidProperties;
    if (prop == 40) return std.math.maxInt(u32);
    const base: u32 = if ((prop & 1) == 0) 2 else 3;
    const shift: u5 = @truncate((prop >> 1) + 11);
    return base << shift;
}

/// Converts a dictionary size in bytes to the smallest valid XZ / LZMA2 1-byte property (0..40).
///
/// Returns error.InvalidOptions if dictionary size is below 4096 or above DICT_SIZE_MAX.
pub fn dictSizeToProp(dict_size: u32) errors.CompressError!u8 {
    if (dict_size < DICT_SIZE_MIN or dict_size > DICT_SIZE_MAX) {
        return error.InvalidOptions;
    }
    var p: u8 = 0;
    while (p <= 40) : (p += 1) {
        const sz = propToDictSize(p) catch unreachable;
        if (sz >= dict_size) return p;
    }
    return 40;
}

/// Maximum uncompressed size for a single LZMA2 chunk (2 MiB).
pub const CHUNK_UNPACK_MAX: usize = 2 * 1024 * 1024;

/// Maximum compressed size for a single LZMA2 chunk payload (64 KiB).
pub const CHUNK_PACK_MAX: usize = 65536;

/// Minimum supported dictionary size (4 KiB).
pub const DICT_SIZE_MIN: u32 = 4096;

/// Maximum supported dictionary size in this implementation (1 GiB).
pub const DICT_SIZE_MAX: u32 = 1024 * 1024 * 1024;

/// Default dictionary size used by standard compression level 6 (8 MiB).
pub const DEFAULT_DICT_SIZE: u32 = 8 * 1024 * 1024;

/// Default literal context bits (lc).
pub const DEFAULT_LC: u4 = 3;

/// Default literal position bits (lp).
pub const DEFAULT_LP: u4 = 0;

/// Default position bits (pb).
pub const DEFAULT_PB: u4 = 2;

/// Compression algorithm mode.
pub const Mode = enum {
    /// Faster compression, greedy or direct match selection.
    fast,
    /// Higher compression ratio, 1-step lookahead lazy match evaluation.
    normal,
};

/// Preset compression level from 0 (uncompressed / store) to 9 (maximum).
pub const Preset = struct {
    pub const store: u4 = 0;
    pub const fastest: u4 = 1;
    pub const fast: u4 = 3;
    pub const default_level: u4 = 6;
    pub const maximum: u4 = 9;
};

/// Configuration options for LZMA2 compression.
pub const Options = struct {
    /// Compression level from 0 (store uncompressed) to 9 (maximum).
    level: u4 = Preset.default_level,

    /// Dictionary size in bytes. Must be between 4 KiB and 1 GiB.
    /// If null, a sensible default is chosen based on `level`.
    dict_size: ?u32 = null,

    /// Number of literal context bits (0..4). Default is 3.
    lc: u4 = DEFAULT_LC,

    /// Number of literal position bits (0..4). Default is 0.
    /// Note: `lc + lp` must not exceed 4 in LZMA2.
    lp: u4 = DEFAULT_LP,

    /// Number of position bits (0..4). Default is 2.
    pb: u4 = DEFAULT_PB,

    /// Compression search mode. If null, chosen based on `level`.
    mode: ?Mode = null,

    /// Maximum search depth for match finder. 0 means automatic.
    depth: u32 = 0,

    /// Nice length of a match (2..273).
    nice_len: u16 = 64,

    /// Resolves the actual dictionary size to use for this configuration.
    pub fn getDictSize(self: Options) u32 {
        if (self.dict_size) |ds| {
            return std.math.clamp(ds, DICT_SIZE_MIN, DICT_SIZE_MAX);
        }
        return switch (self.level) {
            0 => 4096,
            1 => 64 * 1024,
            2 => 256 * 1024,
            3 => 1024 * 1024,
            4 => 2 * 1024 * 1024,
            5 => 4 * 1024 * 1024,
            6 => 8 * 1024 * 1024,
            7 => 16 * 1024 * 1024,
            8 => 32 * 1024 * 1024,
            9 => 64 * 1024 * 1024,
            else => DEFAULT_DICT_SIZE,
        };
    }

    /// Resolves the effective mode.
    pub fn getMode(self: Options) Mode {
        if (self.mode) |m| return m;
        return if (self.level <= 3) .fast else .normal;
    }

    /// Resolves the effective search depth.
    pub fn getDepth(self: Options) u32 {
        if (self.depth > 0) return self.depth;
        return switch (self.level) {
            0 => 0,
            1 => 8,
            2 => 16,
            3 => 24,
            4 => 32,
            5 => 48,
            6 => 64,
            7 => 96,
            8 => 128,
            9 => 256,
            else => 64,
        };
    }

    /// Computes the encoded LZMA properties byte: `(pb * 5 + lp) * 9 + lc`.
    pub fn getPropsByte(self: Options) u8 {
        const pb_u8: u8 = self.pb;
        const lp_u8: u8 = self.lp;
        const lc_u8: u8 = self.lc;
        return (pb_u8 * 5 + lp_u8) * 9 + lc_u8;
    }

    /// Validates the option parameters.
    pub fn validate(self: Options) errors.CompressError!void {
        if (self.lc > 4 or self.lp > 4 or self.pb > 4) {
            return error.InvalidOptions;
        }
        if (@as(u5, self.lc) + @as(u5, self.lp) > 4) {
            return error.InvalidOptions;
        }
        if (self.dict_size) |ds| {
            if (ds < DICT_SIZE_MIN or ds > DICT_SIZE_MAX) {
                return error.InvalidOptions;
            }
        }
        if (self.nice_len < 2 or self.nice_len > 273) {
            return error.InvalidOptions;
        }
    }
};

/// Configuration options for LZMA2 decompression.
pub const DecompressOptions = struct {
    /// Maximum allowed uncompressed output size in bytes (prevents zip bomb attacks).
    /// Default is no limit (`maxInt(usize)`).
    max_output_size: usize = std.math.maxInt(usize),

    /// Maximum allowed dictionary memory in bytes. Default is 1 GiB.
    dict_size_limit: usize = 1024 * 1024 * 1024,
};

/// Configuration options for raw LZMA compression.
pub const LzmaOptions = struct {
    /// Compression level from 0 to 9.
    level: u4 = Preset.default_level,

    /// Dictionary size in bytes. Must be between 4 KiB and 1 GiB.
    dict_size: ?u32 = null,

    /// Number of literal context bits (0..8 in LZMA). Default is 3.
    lc: u4 = DEFAULT_LC,

    /// Number of literal position bits (0..4 in LZMA). Default is 0.
    lp: u4 = DEFAULT_LP,

    /// Number of position bits (0..4 in LZMA). Default is 2.
    pb: u4 = DEFAULT_PB,

    /// Compression search mode.
    mode: ?Mode = null,

    /// Maximum search depth for match finder.
    depth: u32 = 0,

    /// Nice length of a match (2..273).
    nice_len: u16 = 64,

    /// Whether to encode the End-of-Stream (EOS) marker at the end of the stream.
    write_end_mark: bool = true,

    /// Optional declared uncompressed size if known in advance.
    uncompressed_size: ?u64 = null,

    pub fn getDictSize(self: LzmaOptions) u32 {
        if (self.dict_size) |ds| return std.math.clamp(ds, DICT_SIZE_MIN, DICT_SIZE_MAX);
        return switch (self.level) {
            0 => 4096,
            1 => 64 * 1024,
            2 => 256 * 1024,
            3 => 1024 * 1024,
            4 => 2 * 1024 * 1024,
            5 => 4 * 1024 * 1024,
            6 => 8 * 1024 * 1024,
            7 => 16 * 1024 * 1024,
            8 => 32 * 1024 * 1024,
            9 => 64 * 1024 * 1024,
            else => DEFAULT_DICT_SIZE,
        };
    }

    pub fn getMode(self: LzmaOptions) Mode {
        if (self.mode) |m| return m;
        return if (self.level <= 3) .fast else .normal;
    }

    pub fn getDepth(self: LzmaOptions) u32 {
        if (self.depth > 0) return self.depth;
        return switch (self.level) {
            0 => 0,
            1 => 8,
            2 => 16,
            3 => 24,
            4 => 32,
            5 => 48,
            6 => 64,
            7 => 96,
            8 => 128,
            9 => 256,
            else => 64,
        };
    }

    pub fn getPropsByte(self: LzmaOptions) u8 {
        return (@as(u8, self.pb) * 5 + @as(u8, self.lp)) * 9 + @as(u8, self.lc);
    }

    pub fn validate(self: LzmaOptions) errors.CompressError!void {
        if (self.lc > 4 or self.lp > 4 or self.pb > 4) return error.InvalidOptions;
        if (@as(u5, self.lc) + @as(u5, self.lp) > 4) return error.InvalidOptions;
        if (self.dict_size) |ds| {
            if (ds < DICT_SIZE_MIN or ds > DICT_SIZE_MAX) return error.InvalidOptions;
        }
        if (self.nice_len < 2 or self.nice_len > 273) return error.InvalidOptions;
    }
};

/// Configuration options for raw LZMA decompression.
pub const LzmaDecompressOptions = struct {
    lc: u4 = DEFAULT_LC,
    lp: u4 = DEFAULT_LP,
    pb: u4 = DEFAULT_PB,
    dict_size: u32 = DEFAULT_DICT_SIZE,
    uncompressed_size: ?u64 = null,
    has_end_marker: bool = true,
    max_output_size: usize = std.math.maxInt(usize),
    dict_size_limit: usize = 1024 * 1024 * 1024,
};

/// Header of the legacy `.lzma` (LZMA-Alone) file container format (13 bytes).
pub const AloneHeader = struct {
    pub const SIZE: usize = 13;
    pub const UNKNOWN_SIZE: u64 = std.math.maxInt(u64);

    lc: u4 = DEFAULT_LC,
    lp: u4 = DEFAULT_LP,
    pb: u4 = DEFAULT_PB,
    dict_size: u32 = DEFAULT_DICT_SIZE,
    uncompressed_size: ?u64 = null, // null represents unknown size (0xFFFFFFFFFFFFFFFF)

    pub fn encodeSlice(self: AloneHeader, dest: *[13]u8) void {
        dest[0] = (@as(u8, self.pb) * 5 + @as(u8, self.lp)) * 9 + @as(u8, self.lc);
        std.mem.writeInt(u32, dest[1..5], self.dict_size, .little);
        const sz: u64 = self.uncompressed_size orelse UNKNOWN_SIZE;
        std.mem.writeInt(u64, dest[5..13], sz, .little);
    }

    pub fn getPropsByte(self: AloneHeader) u8 {
        return (@as(u8, self.pb) * 5 + @as(u8, self.lp)) * 9 + @as(u8, self.lc);
    }

    pub const encode = encodeSlice;
    pub const decode = decodeSlice;

    pub fn decodeSlice(src: []const u8) errors.DecompressError!AloneHeader {
        if (src.len < 13) return error.UnexpectedEof;
        const prop = src[0];
        if (prop >= 9 * 5 * 5) return error.InvalidProperties;
        const lc: u4 = @truncate(prop % 9);
        const rem = prop / 9;
        const lp: u4 = @truncate(rem % 5);
        const pb: u4 = @truncate(rem / 5);

        if (@as(u5, lc) + @as(u5, lp) > 4 or pb > 4) {
            return error.InvalidProperties;
        }

        var dict_size = std.mem.readInt(u32, src[1..5], .little);
        if (dict_size < DICT_SIZE_MIN) dict_size = DICT_SIZE_MIN;

        const raw_sz = std.mem.readInt(u64, src[5..13], .little);
        const sz: ?u64 = if (raw_sz == UNKNOWN_SIZE) null else raw_sz;

        return AloneHeader{
            .lc = lc,
            .lp = lp,
            .pb = pb,
            .dict_size = dict_size,
            .uncompressed_size = sz,
        };
    }
};

/// Options for compressing with the legacy `.lzma` file format.
pub const AloneOptions = struct {
    level: u4 = Preset.default_level,
    dict_size: ?u32 = null,
    lc: u4 = DEFAULT_LC,
    lp: u4 = DEFAULT_LP,
    pb: u4 = DEFAULT_PB,
    mode: ?Mode = null,
    depth: u32 = 0,
    nice_len: u16 = 64,
    write_end_mark: bool = false,
    uncompressed_size: ?u64 = null,
    unknown_size: bool = false,

    pub fn toLzmaOptions(self: AloneOptions) LzmaOptions {
        const is_unk = self.unknown_size or (self.uncompressed_size == null);
        return LzmaOptions{
            .level = self.level,
            .dict_size = self.dict_size,
            .lc = self.lc,
            .lp = self.lp,
            .pb = self.pb,
            .mode = self.mode,
            .depth = self.depth,
            .nice_len = self.nice_len,
            .write_end_mark = self.write_end_mark or is_unk,
            .uncompressed_size = if (self.unknown_size) null else self.uncompressed_size,
        };
    }
};

test "options: default values and validation" {
    const default_opts = Options{};
    try default_opts.validate();
    try std.testing.expectEqual(DEFAULT_DICT_SIZE, default_opts.getDictSize());
    try std.testing.expectEqual(Mode.normal, default_opts.getMode());
    try std.testing.expectEqual(@as(u8, (2 * 5 + 0) * 9 + 3), default_opts.getPropsByte());
}

test "options: invalid lc + lp" {
    const invalid_opts = Options{ .lc = 3, .lp = 2 }; // lc + lp = 5 > 4
    try std.testing.expectError(error.InvalidOptions, invalid_opts.validate());
}

test "options: custom dictionary size and levels" {
    const custom_opts = Options{ .level = 1, .dict_size = 65536 };
    try custom_opts.validate();
    try std.testing.expectEqual(@as(u32, 65536), custom_opts.getDictSize());
    try std.testing.expectEqual(Mode.fast, custom_opts.getMode());
}

test "options: xz dictionary property encoding and decoding" {
    // 4 KiB (prop 0)
    try std.testing.expectEqual(@as(u32, 4096), try propToDictSize(0));
    try std.testing.expectEqual(@as(u8, 0), try dictSizeToProp(4096));

    // 6 KiB (prop 1)
    try std.testing.expectEqual(@as(u32, 6144), try propToDictSize(1));
    try std.testing.expectEqual(@as(u8, 1), try dictSizeToProp(6144));

    // 8 MiB (prop 22 = 0x16)
    try std.testing.expectEqual(@as(u32, 8 * 1024 * 1024), try propToDictSize(22));
    try std.testing.expectEqual(@as(u8, 22), try dictSizeToProp(8 * 1024 * 1024));

    // prop 40 is max 0xFFFFFFFF
    try std.testing.expectEqual(std.math.maxInt(u32), try propToDictSize(40));

    // Invalid property > 40
    try std.testing.expectError(error.InvalidProperties, propToDictSize(41));
}

test "options: alone header encode and decode" {
    const hdr = AloneHeader{
        .lc = 3,
        .lp = 0,
        .pb = 2,
        .dict_size = 1024 * 1024,
        .uncompressed_size = 42,
    };
    var buf: [13]u8 = undefined;
    hdr.encodeSlice(&buf);

    const decoded = try AloneHeader.decodeSlice(&buf);
    try std.testing.expectEqual(hdr.lc, decoded.lc);
    try std.testing.expectEqual(hdr.lp, decoded.lp);
    try std.testing.expectEqual(hdr.pb, decoded.pb);
    try std.testing.expectEqual(hdr.dict_size, decoded.dict_size);
    try std.testing.expectEqual(hdr.uncompressed_size, decoded.uncompressed_size);

    // Test unknown size
    const hdr_unk = AloneHeader{
        .uncompressed_size = null,
    };
    hdr_unk.encodeSlice(&buf);
    const decoded_unk = try AloneHeader.decodeSlice(&buf);
    try std.testing.expectEqual(@as(?u64, null), decoded_unk.uncompressed_size);
}

test "options: lzma validation" {
    var lz = LzmaOptions{ .lc = 3, .lp = 1, .pb = 2 };
    try lz.validate(); // lc + lp = 4 <= 4 is valid

    lz.lc = 4;
    lz.lp = 1; // lc + lp = 5 > 4 is invalid
    try std.testing.expectError(error.InvalidOptions, lz.validate());
}
