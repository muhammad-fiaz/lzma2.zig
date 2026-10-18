//! Re-export of LZMA2 encoder for backward compatibility.
const mod = @import("compress/lzma2.zig");

pub const Compressor = mod.Compressor;
pub const compress = mod.compress;
pub const compressInto = mod.compressInto;
pub const compressBuffer = mod.compressBuffer;
