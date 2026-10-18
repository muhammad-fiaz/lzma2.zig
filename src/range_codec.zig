//! Re-export of range_codec module for backward compatibility.
const mod = @import("utils/range_codec.zig");

pub const RangeEncoder = mod.RangeEncoder;
pub const RangeDecoder = mod.RangeDecoder;
pub const BIT_MODEL_TOTAL_BITS = mod.BIT_MODEL_TOTAL_BITS;
pub const BIT_MODEL_TOTAL = mod.BIT_MODEL_TOTAL;
pub const PROB_INIT_VALUE = mod.PROB_INIT_VALUE;
pub const NUM_MOVE_BITS = mod.NUM_MOVE_BITS;
pub const TOP_VALUE = mod.TOP_VALUE;
