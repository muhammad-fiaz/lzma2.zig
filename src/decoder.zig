//! Re-export of LZMA2 decoder for backward compatibility.
const mod = @import("decompress/lzma2.zig");

pub const Decompressor = mod.Decompressor;
pub const decompress = mod.decompress;
pub const decompressInto = mod.decompressInto;
pub const decompressBuffer = mod.decompressBuffer;
