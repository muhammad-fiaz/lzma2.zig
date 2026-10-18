//! LZMA2 Encoder implementation.
//!
//! Encodes uncompressed data into LZMA2 streams containing compressed LZMA
//! chunks and uncompressed copy chunks, adhering to dictionary limits and
//! chunk boundaries.

const std = @import("std");
const lzma = @import("lzma");
const errors = lzma.errors;
const options_mod = lzma.options;
const Options = options_mod.Options;
const RangeEncoder = lzma.range_codec.RangeEncoder;
const LzmaState = lzma.LzmaState;
const MatchFinder = lzma.match_finder.MatchFinder;

pub const CONTROL_EOF: u8 = 0;
pub const CONTROL_COPY_RESET_DIC: u8 = 1;
pub const CONTROL_COPY_NO_RESET: u8 = 2;
pub const CONTROL_LZMA_MASK: u8 = 0x80;

/// Stateful LZMA2 compressor context.
pub const Compressor = struct {
    options: Options,
    state: LzmaState,
    rc: RangeEncoder,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, options: Options) errors.CompressError!Compressor {
        try options.validate();
        return Compressor{
            .options = options,
            .state = LzmaState.init(options.lc, options.lp, options.pb),
            .rc = RangeEncoder.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Compressor) void {
        self.rc.deinit();
    }

    pub fn reset(self: *Compressor) void {
        self.state.reset();
        self.rc.reset();
    }

    /// Compresses `src` into a newly allocated slice.
    pub fn compressAlloc(self: *Compressor, src: []const u8) errors.CompressError![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);

        if (src.len == 0) {
            out.append(self.allocator, CONTROL_EOF) catch return error.OutOfMemory;
            return out.toOwnedSlice(self.allocator) catch return error.OutOfMemory;
        }

        if (self.options.level == 0) {
            try self.compressStoreAlloc(&out, src);
            return out.toOwnedSlice(self.allocator) catch return error.OutOfMemory;
        }

        try self.compressLzmaAlloc(&out, src);
        return out.toOwnedSlice(self.allocator) catch return error.OutOfMemory;
    }

    /// Compresses `src` into caller-provided destination slice.
    pub fn compressToSlice(self: *Compressor, dest: []u8, src: []const u8) errors.CompressError!usize {
        if (src.len == 0) {
            if (dest.len < 1) return error.OutputTooSmall;
            dest[0] = CONTROL_EOF;
            return 1;
        }

        const allocated = try self.compressAlloc(src);
        defer self.allocator.free(allocated);

        if (allocated.len > dest.len) return error.OutputTooSmall;
        @memcpy(dest[0..allocated.len], allocated);
        return allocated.len;
    }

    fn compressStoreAlloc(self: *Compressor, out: *std.ArrayList(u8), src: []const u8) errors.CompressError!void {
        var pos: usize = 0;
        var is_first: bool = true;

        while (pos < src.len) {
            const chunk_size = @min(src.len - pos, options_mod.CHUNK_PACK_MAX);
            const ctrl = if (is_first) CONTROL_COPY_RESET_DIC else CONTROL_COPY_NO_RESET;
            const u = @as(u16, @intCast(chunk_size - 1));

            out.append(self.allocator, ctrl) catch return error.OutOfMemory;
            out.append(self.allocator, @truncate(u >> 8)) catch return error.OutOfMemory;
            out.append(self.allocator, @truncate(u)) catch return error.OutOfMemory;
            out.appendSlice(self.allocator, src[pos .. pos + chunk_size]) catch return error.OutOfMemory;

            pos += chunk_size;
            is_first = false;
        }

        out.append(self.allocator, CONTROL_EOF) catch return error.OutOfMemory;
    }

    fn compressLzmaAlloc(self: *Compressor, out: *std.ArrayList(u8), src: []const u8) errors.CompressError!void {
        const dict_size = self.options.getDictSize();
        const depth = self.options.getDepth();
        const mode = self.options.getMode();

        var mf = MatchFinder.init(self.allocator, dict_size, depth) catch return error.OutOfMemory;
        defer mf.deinit();

        self.reset();
        var need_init_state: bool = true;
        var need_init_prop: bool = true;
        var pos: usize = 0;

        var has_lookahead = false;
        var lookahead_match: lzma.match_finder.Match = .{ .len = 0, .dist = 0 };

        while (pos < src.len) {
            const chunk_start = pos;
            const max_chunk_unpack = @min(src.len - pos, options_mod.CHUNK_UNPACK_MAX);
            const chunk_target_end = pos + max_chunk_unpack;

            self.rc.reset();

            // Encode symbols into range encoder
            while (pos < chunk_target_end) {
                // Check if buffer is getting full
                if (self.rc.getWritten().len >= 64000 and pos > chunk_start) {
                    break;
                }

                const current_pos = pos;
                const pos_state = self.state.getPosState(current_pos);
                const prev_byte = if (current_pos > 0) src[current_pos - 1] else 0;
                const match_byte = if (current_pos >= self.state.reps[0])
                    src[current_pos - self.state.reps[0]]
                else
                    0;

                // Check repeat matches
                var rep_lens = [4]u32{ 0, 0, 0, 0 };
                for (0..4) |rep_idx| {
                    const r = self.state.reps[rep_idx];
                    if (r <= current_pos and r <= dict_size) {
                        const max_l = @min(src.len - current_pos, lzma.MATCH_MAX_LEN);
                        rep_lens[rep_idx] = MatchFinder.countMatch(src, current_pos - r, current_pos, max_l);
                    }
                }

                // Check normal match: use cached lookahead match if available
                var match: lzma.match_finder.Match = undefined;
                if (has_lookahead) {
                    match = lookahead_match;
                    has_lookahead = false;
                } else {
                    match = mf.findMatch(src, current_pos);
                }
                var best_len = match.len;
                const best_dist = match.dist;

                // 2-byte matches with distance >= 128 cost more than 2 literals
                if (best_len == 2 and best_dist >= 128) {
                    best_len = 0;
                }

                // Check best rep match
                var best_rep_idx: ?usize = null;
                var best_rep_len: u32 = 0;
                if (rep_lens[0] >= 1) {
                    best_rep_len = rep_lens[0];
                    best_rep_idx = 0;
                }
                for (1..4) |idx| {
                    if (rep_lens[idx] >= 2 and rep_lens[idx] > best_rep_len) {
                        best_rep_len = rep_lens[idx];
                        best_rep_idx = idx;
                    }
                }

                var take_rep = (best_rep_idx != null and best_rep_len >= 2) and (best_rep_len >= best_len or
                    best_rep_len + 1 >= best_len or
                    (best_rep_len + 2 >= best_len and best_dist >= 512) or
                    (best_rep_len + 3 >= best_len and best_dist >= 32768));

                if (best_rep_idx != null and best_rep_len >= 2 and !take_rep and best_len >= 2) {
                    const next_pos = current_pos + best_rep_len;
                    if (next_pos < src.len) {
                        var simulated_reps = self.state.reps;
                        const r_idx = best_rep_idx.?;
                        if (r_idx != 0) {
                            const dist = simulated_reps[r_idx];
                            var ri = r_idx;
                            while (ri > 0) : (ri -= 1) {
                                simulated_reps[ri] = simulated_reps[ri - 1];
                            }
                            simulated_reps[0] = dist;
                        }

                        var next_rep_max: u32 = 0;
                        for (simulated_reps) |r| {
                            if (r > 0 and r <= next_pos) {
                                const max_l = @min(src.len - next_pos, lzma.MATCH_MAX_LEN);
                                const l = MatchFinder.countMatch(src, next_pos - r, next_pos, max_l);
                                if (l > next_rep_max) next_rep_max = l;
                            }
                        }
                        if (best_rep_len + next_rep_max > best_len) {
                            take_rep = true;
                        }
                    }
                }

                if (take_rep) {
                    const r_idx = best_rep_idx.?;
                    const r_len = best_rep_len;

                    try self.rc.encodeBit(&self.state.is_match[self.state.state][pos_state], 1);
                    try self.rc.encodeBit(&self.state.is_rep[self.state.state], 1);

                    if (r_idx == 0) {
                        try self.rc.encodeBit(&self.state.is_rep_g0[self.state.state], 0);
                        try self.rc.encodeBit(&self.state.is_rep0_long[self.state.state][pos_state], 1);
                        try self.state.rep_len_coder.encode(&self.rc, pos_state, r_len);
                        self.state.updateStateRep();
                    } else {
                        try self.rc.encodeBit(&self.state.is_rep_g0[self.state.state], 1);
                        var dist: u32 = 0;
                        if (r_idx == 1) {
                            try self.rc.encodeBit(&self.state.is_rep_g1[self.state.state], 0);
                            dist = self.state.reps[1];
                        } else {
                            try self.rc.encodeBit(&self.state.is_rep_g1[self.state.state], 1);
                            if (r_idx == 2) {
                                try self.rc.encodeBit(&self.state.is_rep_g2[self.state.state], 0);
                                dist = self.state.reps[2];
                            } else {
                                try self.rc.encodeBit(&self.state.is_rep_g2[self.state.state], 1);
                                dist = self.state.reps[3];
                                self.state.reps[3] = self.state.reps[2];
                            }
                            self.state.reps[2] = self.state.reps[1];
                        }
                        self.state.reps[1] = self.state.reps[0];
                        self.state.reps[0] = dist;

                        try self.state.rep_len_coder.encode(&self.rc, pos_state, r_len);
                        self.state.updateStateRep();
                    }

                    mf.skip(src, current_pos + 1, r_len - 1);
                    pos += r_len;
                } else if (best_len >= 2) {
                    var take_match = true;
                    const nice_len = self.options.nice_len;
                    if (mode == .normal and current_pos + 1 < src.len and best_len < nice_len) {
                        const next_match = mf.findMatch(src, current_pos + 1);
                        lookahead_match = next_match;
                        has_lookahead = true;

                        var next_len = next_match.len;
                        if (next_len == 2 and next_match.dist >= 128) next_len = 0;

                        const next_better = (next_len >= best_len and next_match.dist < best_dist) or
                            (next_len == best_len + 1 and !MatchFinder.changePair(best_dist, next_match.dist)) or
                            (next_len > best_len + 1) or
                            (next_len + 1 >= best_len and best_len >= 3 and MatchFinder.changePair(next_match.dist, best_dist));

                        var next_rep_better = false;
                        const limit = @max(2, best_len - 1);
                        for (self.state.reps) |r| {
                            if (r > 0 and r <= current_pos + 1) {
                                const max_l = @min(src.len - (current_pos + 1), limit);
                                const rl = MatchFinder.countMatch(src, current_pos + 1 - r, current_pos + 1, max_l);
                                if (rl >= limit) {
                                    next_rep_better = true;
                                    break;
                                }
                            }
                        }

                        if (next_better or next_rep_better) {
                            take_match = false;
                        }
                    }

                    if (take_match) {
                        try self.rc.encodeBit(&self.state.is_match[self.state.state][pos_state], 1);
                        try self.rc.encodeBit(&self.state.is_rep[self.state.state], 0);

                        self.state.reps[3] = self.state.reps[2];
                        self.state.reps[2] = self.state.reps[1];
                        self.state.reps[1] = self.state.reps[0];
                        self.state.reps[0] = best_dist;

                        try self.state.len_coder.encode(&self.rc, pos_state, best_len);
                        self.state.updateStateMatch();
                        try self.state.encodeDistance(&self.rc, best_len, best_dist);

                        if (has_lookahead) {
                            has_lookahead = false;
                            if (best_len > 2) {
                                mf.skip(src, current_pos + 2, best_len - 2);
                            }
                        } else {
                            mf.skip(src, current_pos + 1, best_len - 1);
                        }
                        pos += best_len;
                    } else {
                        if (rep_lens[0] >= 1 and current_pos > 0) {
                            try self.rc.encodeBit(&self.state.is_match[self.state.state][pos_state], 1);
                            try self.rc.encodeBit(&self.state.is_rep[self.state.state], 1);
                            try self.rc.encodeBit(&self.state.is_rep_g0[self.state.state], 0);
                            try self.rc.encodeBit(&self.state.is_rep0_long[self.state.state][pos_state], 0);
                            self.state.updateStateShortRep();
                        } else {
                            try self.rc.encodeBit(&self.state.is_match[self.state.state][pos_state], 0);
                            try self.state.encodeLiteral(&self.rc, current_pos, prev_byte, match_byte, src[current_pos]);
                        }
                        pos += 1;
                    }
                } else if (rep_lens[0] >= 1 and current_pos > 0) {
                    try self.rc.encodeBit(&self.state.is_match[self.state.state][pos_state], 1);
                    try self.rc.encodeBit(&self.state.is_rep[self.state.state], 1);
                    try self.rc.encodeBit(&self.state.is_rep_g0[self.state.state], 0);
                    try self.rc.encodeBit(&self.state.is_rep0_long[self.state.state][pos_state], 0);
                    self.state.updateStateShortRep();
                    pos += 1;
                } else {
                    try self.rc.encodeBit(&self.state.is_match[self.state.state][pos_state], 0);
                    try self.state.encodeLiteral(&self.rc, current_pos, prev_byte, match_byte, src[current_pos]);
                    pos += 1;
                }
            }

            try self.rc.flush();

            const chunk_unpack = pos - chunk_start;
            const pack_size = self.rc.getWritten().len;

            // Check if compressed chunk is smaller than uncompressed
            if (pack_size + 2 >= chunk_unpack or pack_size > options_mod.CHUNK_PACK_MAX) {
                // Emit uncompressed chunk(s)
                var sub_pos: usize = 0;
                while (sub_pos < chunk_unpack) {
                    const sub_len = @min(chunk_unpack - sub_pos, options_mod.CHUNK_PACK_MAX);
                    const ctrl = if (chunk_start + sub_pos == 0) CONTROL_COPY_RESET_DIC else CONTROL_COPY_NO_RESET;
                    const u = @as(u16, @intCast(sub_len - 1));

                    out.append(self.allocator, ctrl) catch return error.OutOfMemory;
                    out.append(self.allocator, @truncate(u >> 8)) catch return error.OutOfMemory;
                    out.append(self.allocator, @truncate(u)) catch return error.OutOfMemory;
                    out.appendSlice(self.allocator, src[chunk_start + sub_pos .. chunk_start + sub_pos + sub_len]) catch return error.OutOfMemory;

                    sub_pos += sub_len;
                }
                self.state.reset();
                need_init_state = true;
            } else {
                // Emit compressed LZMA chunk
                const mode_val: u2 = if (chunk_start == 0)
                    3
                else if (need_init_state)
                    (if (need_init_prop) 2 else 1)
                else
                    0;

                const u = @as(u32, @intCast(chunk_unpack - 1));
                const p = @as(u16, @intCast(pack_size - 1));

                const ctrl = CONTROL_LZMA_MASK | (@as(u8, mode_val) << 5) | @as(u8, @truncate(u >> 16));
                out.append(self.allocator, ctrl) catch return error.OutOfMemory;
                out.append(self.allocator, @truncate(u >> 8)) catch return error.OutOfMemory;
                out.append(self.allocator, @truncate(u)) catch return error.OutOfMemory;
                out.append(self.allocator, @truncate(p >> 8)) catch return error.OutOfMemory;
                out.append(self.allocator, @truncate(p)) catch return error.OutOfMemory;

                if (mode_val >= 2) {
                    out.append(self.allocator, self.options.getPropsByte()) catch return error.OutOfMemory;
                    need_init_prop = false;
                }
                need_init_state = false;

                out.appendSlice(self.allocator, self.rc.getWritten()) catch return error.OutOfMemory;
            }
        }

        out.append(self.allocator, CONTROL_EOF) catch return error.OutOfMemory;
    }
};

/// Convenience one-shot function to compress data into an allocated slice.
pub fn compress(allocator: std.mem.Allocator, src: []const u8, options: Options) errors.CompressError![]u8 {
    var c = try Compressor.init(allocator, options);
    defer c.deinit();
    return c.compressAlloc(src);
}

/// Convenience one-shot function to compress data into a caller-provided slice.
pub fn compressBuffer(dest: []u8, src: []const u8, options: Options) errors.CompressError!usize {
    var c = try Compressor.init(std.heap.page_allocator, options);
    defer c.deinit();
    return c.compressToSlice(dest, src);
}

/// Alias for compressBuffer following standard library Into conventions.
pub const compressInto = compressBuffer;

test "encoder: empty input produces EOF marker" {
    const comp = try compress(std.testing.allocator, "", .{});
    defer std.testing.allocator.free(comp);
    try std.testing.expectEqual(@as(usize, 1), comp.len);
    try std.testing.expectEqual(@as(u8, 0), comp[0]);
}

test "encoder: level 0 copy chunk" {
    const data = "Uncompressed level 0 copy chunk data";
    const comp = try compress(std.testing.allocator, data, .{ .level = 0 });
    defer std.testing.allocator.free(comp);
    try std.testing.expect(comp.len > data.len);
    try std.testing.expectEqual(@as(u8, 1), comp[0]); // Dictionary reset copy chunk
}

test "encoder: compressInto caller buffer" {
    const data = "Testing caller provided buffer encoding";
    var buf: [256]u8 = undefined;
    const n = try compressInto(&buf, data, .{});
    try std.testing.expect(n > 0);
    try std.testing.expect(n <= buf.len);
}

test "encoder: destination buffer too small returns error" {
    const data = "String that will not fit in 2 bytes";
    var tiny: [2]u8 = undefined;
    try std.testing.expectError(error.OutputTooSmall, compressInto(&tiny, data, .{}));
}
