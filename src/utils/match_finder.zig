//! Multi-level sliding window match finder for LZMA and LZMA2.
//!
//! Uses dedicated 2-byte, 3-byte, and 4-byte hash tables with hash chaining
//! to efficiently locate short and long candidate matches within the dictionary window.

const std = @import("std");

pub const MATCH_MIN_LEN: u32 = 2;
pub const MATCH_MAX_LEN: u32 = 273;

pub const HASH2_BITS: u6 = 16;
pub const HASH2_SIZE: usize = 1 << HASH2_BITS; // 65536
pub const HASH3_BITS: u6 = 16;
pub const HASH3_SIZE: usize = 1 << HASH3_BITS; // 65536
pub const HASH4_BITS: u6 = 16;
pub const HASH4_SIZE: usize = 1 << HASH4_BITS; // 65536

pub const Match = struct {
    len: u32,
    dist: u32, // 1-based distance
};

pub const MatchFinder = struct {
    hash2: []u32,
    hash3: []u32,
    head: []u32,
    chain: []u32,
    head_mask: usize,
    chain_mask: usize,
    dict_size: u32,
    depth: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, dict_size: u32, depth: u32) !MatchFinder {
        const hash2 = try allocator.alloc(u32, HASH2_SIZE);
        errdefer allocator.free(hash2);
        @memset(hash2, std.math.maxInt(u32));

        const hash3 = try allocator.alloc(u32, HASH3_SIZE);
        errdefer allocator.free(hash3);
        @memset(hash3, std.math.maxInt(u32));

        var h4_size: usize = 1 << 16;
        while (h4_size < dict_size and h4_size < (1 << 20)) {
            h4_size <<= 1;
        }
        const head = try allocator.alloc(u32, h4_size);
        errdefer allocator.free(head);
        @memset(head, std.math.maxInt(u32));

        var chain_size: usize = 1 << 16;
        while (chain_size < dict_size and chain_size < (1 << 24)) {
            chain_size <<= 1;
        }
        const chain = try allocator.alloc(u32, chain_size);
        errdefer allocator.free(chain);
        @memset(chain, std.math.maxInt(u32));

        return MatchFinder{
            .hash2 = hash2,
            .hash3 = hash3,
            .head = head,
            .chain = chain,
            .head_mask = h4_size - 1,
            .chain_mask = chain_size - 1,
            .dict_size = dict_size,
            .depth = depth,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MatchFinder) void {
        self.allocator.free(self.hash2);
        self.allocator.free(self.hash3);
        self.allocator.free(self.head);
        self.allocator.free(self.chain);
    }

    pub fn reset(self: *MatchFinder) void {
        @memset(self.hash2, std.math.maxInt(u32));
        @memset(self.hash3, std.math.maxInt(u32));
        @memset(self.head, std.math.maxInt(u32));
        @memset(self.chain, std.math.maxInt(u32));
    }

    inline fn calcHash2(b0: u8, b1: u8) usize {
        return @as(usize, b0) | (@as(usize, b1) << 8);
    }

    inline fn calcHash3(b0: u8, b1: u8, b2: u8) usize {
        const val: u32 = @as(u32, b0) | (@as(u32, b1) << 8) | (@as(u32, b2) << 16);
        return @as(usize, @truncate((val *% 0x1e35a7bd) >> (32 - HASH3_BITS)));
    }

    inline fn calcHash4(self: *const MatchFinder, bytes: *const [4]u8) usize {
        const val = std.mem.readInt(u32, bytes, .little);
        return @as(usize, @truncate((val *% 0x1e35a7bd) >> 12)) & self.head_mask;
    }

    pub inline fn changePair(small_dist: u32, big_dist: u32) bool {
        return (big_dist >> 7) > small_dist;
    }

    /// Compares two memory regions using 64-bit word comparisons and trailing zeros.
    pub inline fn countMatch(src: []const u8, p1: usize, p2: usize, max_len: u32) u32 {
        var l: u32 = 0;
        while (l + 8 <= max_len) {
            const w1 = std.mem.readInt(u64, src[p1 + l ..][0..8], .little);
            const w2 = std.mem.readInt(u64, src[p2 + l ..][0..8], .little);
            if (w1 != w2) {
                const diff = w1 ^ w2;
                return l + (@as(u32, @truncate(@ctz(diff))) >> 3);
            }
            l += 8;
        }
        while (l < max_len and src[p1 + l] == src[p2 + l]) : (l += 1) {}
        return l;
    }

    /// Finds the best match at `pos` in `src`.
    /// Updates hash tables with `pos`.
    pub fn findMatch(self: *MatchFinder, src: []const u8, pos: usize) Match {
        if (pos >= src.len or src.len - pos < MATCH_MIN_LEN) {
            return .{ .len = 0, .dist = 0 };
        }

        if (pos >= std.math.maxInt(u32) - 1) {
            return .{ .len = 0, .dist = 0 };
        }

        const max_len_possible = @min(src.len - pos, MATCH_MAX_LEN);
        if (max_len_possible < MATCH_MIN_LEN) {
            return .{ .len = 0, .dist = 0 };
        }

        var best_len: u32 = 0;
        var best_dist: u32 = 0;

        // 1. Check 2-byte match
        if (src.len - pos >= 2) {
            const h2 = calcHash2(src[pos], src[pos + 1]);
            const cur2 = self.hash2[h2];
            self.hash2[h2] = @intCast(pos);
            if (cur2 != std.math.maxInt(u32) and cur2 < pos) {
                const dist2 = pos - cur2;
                if (dist2 > 0 and dist2 <= self.dict_size and dist2 < 128) {
                    if (src[cur2] == src[pos] and src[cur2 + 1] == src[pos + 1]) {
                        best_len = 2;
                        best_dist = @intCast(dist2);
                    }
                }
            }
        }

        // 2. Check 3-byte match
        if (src.len - pos >= 3) {
            const h3 = calcHash3(src[pos], src[pos + 1], src[pos + 2]);
            const cur3 = self.hash3[h3];
            self.hash3[h3] = @intCast(pos);
            if (cur3 != std.math.maxInt(u32) and cur3 < pos) {
                const dist3 = pos - cur3;
                if (dist3 > 0 and dist3 <= self.dict_size) {
                    const l = countMatch(src, cur3, pos, max_len_possible);
                    if (l >= 3 and (l > best_len or (l == best_len and dist3 < best_dist) or (best_len >= 4 and l + 1 == best_len and changePair(@intCast(dist3), best_dist)))) {
                        best_len = l;
                        best_dist = @intCast(dist3);
                    }
                }
            }
        }

        // 3. Check 4-byte matches using hash chain
        if (src.len - pos >= 4) {
            const h4 = self.calcHash4(src[pos .. pos + 4][0..4]);
            var cur = self.head[h4];
            self.head[h4] = @intCast(pos);
            self.chain[pos & self.chain_mask] = cur;

            var steps: u32 = 0;
            while (cur != std.math.maxInt(u32) and steps < self.depth) : (steps += 1) {
                const dist = pos - cur;
                if (dist == 0 or dist > self.dict_size) break;

                const cur_pos = cur;
                const next_cur = self.chain[cur_pos & self.chain_mask];

                if (src[cur_pos] != src[pos] or src[cur_pos + 1] != src[pos + 1]) {
                    if (next_cur >= cur_pos) break;
                    cur = next_cur;
                    continue;
                }

                if (best_len >= 4 and src[cur_pos + best_len - 2] != src[pos + best_len - 2]) {
                    if (next_cur >= cur_pos) break;
                    cur = next_cur;
                    continue;
                }

                const l = countMatch(src, cur_pos, pos, max_len_possible);

                if (l > best_len) {
                    if (best_len == 0 or l > best_len + 1 or !changePair(best_dist, @intCast(dist))) {
                        best_len = l;
                        best_dist = @intCast(dist);
                        if (best_len == max_len_possible) break;
                    }
                } else if (l == best_len and dist < best_dist) {
                    best_dist = @intCast(dist);
                } else if (best_len >= 3 and l + 1 == best_len and changePair(@intCast(dist), best_dist)) {
                    best_len = l;
                    best_dist = @intCast(dist);
                }

                if (next_cur >= cur_pos) break;
                cur = next_cur;
            }
        }

        if (best_len >= MATCH_MIN_LEN) {
            return .{ .len = best_len, .dist = best_dist };
        }
        return .{ .len = 0, .dist = 0 };
    }

    /// Advances the match finder by `count` positions without searching.
    pub fn skip(self: *MatchFinder, src: []const u8, start_pos: usize, count: usize) void {
        if (start_pos >= src.len) return;
        var p = start_pos;
        const max_count = src.len - start_pos;
        const safe_count = @min(count, max_count);
        const end_pos = start_pos + safe_count;
        while (p < end_pos) : (p += 1) {
            if (p >= std.math.maxInt(u32) - 1) break;
            if (src.len - p >= 2) {
                const h2 = calcHash2(src[p], src[p + 1]);
                self.hash2[h2] = @intCast(p);
            }
            if (src.len - p >= 3) {
                const h3 = calcHash3(src[p], src[p + 1], src[p + 2]);
                self.hash3[h3] = @intCast(p);
            }
            if (src.len - p >= 4) {
                const h4 = self.calcHash4(src[p .. p + 4][0..4]);
                self.chain[p & self.chain_mask] = self.head[h4];
                self.head[h4] = @intCast(p);
            }
        }
    }
};

test "match_finder: match finding and skipping" {
    const allocator = std.testing.allocator;
    var mf = try MatchFinder.init(allocator, 65536, 32);
    defer mf.deinit();

    const data = "ABCDEFG_ABCDEFG_123456789";
    const m1 = mf.findMatch(data, 0);
    try std.testing.expectEqual(@as(u32, 0), m1.len);

    mf.skip(data, 1, 7);

    // At index 8, "ABCDEFG_" repeats from index 0
    const m2 = mf.findMatch(data, 8);
    try std.testing.expect(m2.len >= 7);
    try std.testing.expectEqual(@as(u32, 8), m2.dist);
}

test "match_finder: 2-byte short match detection" {
    const allocator = std.testing.allocator;
    var mf = try MatchFinder.init(allocator, 65536, 32);
    defer mf.deinit();

    const data = "hello world! he";
    _ = mf.findMatch(data, 0); // "he" at index 0
    mf.skip(data, 1, 12);
    const m = mf.findMatch(data, 13); // "he" at index 13
    try std.testing.expect(m.len >= 2);
    try std.testing.expectEqual(@as(u32, 13), m.dist);
}
