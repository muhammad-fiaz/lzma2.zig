//! Re-export of match_finder module for backward compatibility.
const mod = @import("utils/match_finder.zig");

pub const Match = mod.Match;
pub const MatchFinder = mod.MatchFinder;
pub const MATCH_MIN_LEN = mod.MATCH_MIN_LEN;
pub const MATCH_MAX_LEN = mod.MATCH_MAX_LEN;
