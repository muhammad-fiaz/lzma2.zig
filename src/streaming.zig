//! Re-export of streaming module for backward compatibility.
const lzma2 = @import("lzma2.zig");

pub const StreamingCompressor = lzma2.StreamingCompressor;
pub const StreamingDecompressor = lzma2.StreamingDecompressor;
pub const compressStream = lzma2.compressStream;
pub const decompressStream = lzma2.decompressStream;
