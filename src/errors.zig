//! Re-export of errors module for backward compatibility.
const mod = @import("utils/errors.zig");
pub const Error = mod.Error;
pub const CompressError = mod.CompressError;
pub const DecompressError = mod.DecompressError;
