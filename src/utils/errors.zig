//! Error types for lzma2.zig
//!
//! Provides granular errors for compression, decompression,
//! input validation, format parsing, and resource limits.

const std = @import("std");

/// Errors that can occur during LZMA2 decompression.
pub const DecompressError = error{
    /// Input data is truncated or contains invalid packet framing.
    CorruptData,
    /// Stream ended before an expected chunk boundary or end-of-stream marker.
    UnexpectedEof,
    /// Control byte is unknown or not permitted in current decoder state.
    InvalidControlByte,
    /// Header is malformed or contains unexpected fields.
    InvalidHeader,
    /// Property byte is out of valid range (lc + lp > 4, or pb > 4).
    InvalidProperties,
    /// First chunk did not reset dictionary, or stream state is uninitialized.
    DictionaryResetExpected,
    /// Destination buffer is too small to receive uncompressed output.
    OutputTooSmall,
    /// Uncompressed output exceeded configured safety size limit.
    ExceededSizeLimit,
    /// Required memory allocation failed.
    OutOfMemory,
};

/// Errors that can occur during LZMA2 compression.
pub const CompressError = error{
    /// Destination buffer provided by caller has insufficient capacity.
    OutputTooSmall,
    /// Configuration options are invalid or unsupported.
    InvalidOptions,
    /// Required memory allocation failed.
    OutOfMemory,
};

/// Unified error set combining all LZMA2 codec errors.
pub const Error = DecompressError || CompressError;

test "errors: error sets verify" {
    const err1: Error = error.CorruptData;
    const err2: Error = error.InvalidOptions;
    try std.testing.expect(err1 == error.CorruptData);
    try std.testing.expect(err2 == error.InvalidOptions);
}
