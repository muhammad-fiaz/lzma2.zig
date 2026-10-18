//! Re-export of options module for backward compatibility.
const mod = @import("utils/options.zig");

pub const version = mod.version;
pub const Options = mod.Options;
pub const DecompressOptions = mod.DecompressOptions;
pub const AloneOptions = mod.AloneOptions;
pub const AloneHeader = mod.AloneHeader;
pub const LzmaOptions = mod.LzmaOptions;
pub const LzmaDecompressOptions = mod.LzmaDecompressOptions;
pub const Mode = mod.Mode;
pub const Preset = mod.Preset;

pub const DEFAULT_DICT_SIZE = mod.DEFAULT_DICT_SIZE;
pub const DEFAULT_LC = mod.DEFAULT_LC;
pub const DEFAULT_LP = mod.DEFAULT_LP;
pub const DEFAULT_PB = mod.DEFAULT_PB;
pub const CHUNK_UNPACK_MAX = mod.CHUNK_UNPACK_MAX;
pub const CHUNK_PACK_MAX = mod.CHUNK_PACK_MAX;
pub const DICT_SIZE_MIN = mod.DICT_SIZE_MIN;
pub const DICT_SIZE_MAX = mod.DICT_SIZE_MAX;

pub const propToDictSize = mod.propToDictSize;
pub const dictSizeToProp = mod.dictSizeToProp;
