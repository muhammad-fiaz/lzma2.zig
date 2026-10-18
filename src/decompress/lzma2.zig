//! LZMA2 Decoder implementation.
//!
//! Handles the LZMA2 chunk protocol, control-byte parsing, dictionary and
//! state resets, uncompressed and compressed chunks, and boundary validation.

const std = @import("std");
const lzma = @import("lzma");
const errors = lzma.errors;
const options_mod = lzma.options;
const DecompressOptions = options_mod.DecompressOptions;
const RangeDecoder = lzma.range_codec.RangeDecoder;
const LzmaState = lzma.LzmaState;

pub const CONTROL_EOF: u8 = 0;
pub const CONTROL_COPY_RESET_DIC: u8 = 1;
pub const CONTROL_COPY_NO_RESET: u8 = 2;
pub const CONTROL_LZMA_MASK: u8 = 0x80;

/// Stateful, reusable LZMA2 decompressor context.
pub const Decompressor = struct {
    state: LzmaState,
    dict_reset_needed: bool = true,
    need_props: bool = false,
    options: DecompressOptions,

    pub fn init(options: DecompressOptions) Decompressor {
        return Decompressor{
            .state = LzmaState.init(options_mod.DEFAULT_LC, options_mod.DEFAULT_LP, options_mod.DEFAULT_PB),
            .dict_reset_needed = true,
            .need_props = false,
            .options = options,
        };
    }

    pub fn reset(self: *Decompressor) void {
        self.state.reset();
        self.dict_reset_needed = true;
        self.need_props = false;
    }

    /// Decompresses an entire LZMA2 stream into an allocated buffer.
    pub fn decompressAlloc(self: *Decompressor, allocator: std.mem.Allocator, src: []const u8) errors.DecompressError![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        var in_pos: usize = 0;
        self.reset();

        while (in_pos < src.len) {
            const control = src[in_pos];
            in_pos += 1;

            if (control == CONTROL_EOF) {
                // End of data
                return out.toOwnedSlice(allocator) catch return error.OutOfMemory;
            }

            if ((control & CONTROL_LZMA_MASK) == 0) {
                // Uncompressed chunk
                if (control > CONTROL_COPY_NO_RESET) {
                    return error.InvalidControlByte;
                }

                if (control == CONTROL_COPY_RESET_DIC) {
                    self.dict_reset_needed = false;
                    self.need_props = true;
                } else if (self.dict_reset_needed) {
                    return error.DictionaryResetExpected;
                }

                if (in_pos + 2 > src.len) return error.UnexpectedEof;
                const chunk_size = (@as(usize, src[in_pos]) << 8 | @as(usize, src[in_pos + 1])) + 1;
                in_pos += 2;

                if (src.len - in_pos < chunk_size) return error.UnexpectedEof;
                const chunk_data = src[in_pos .. in_pos + chunk_size];
                in_pos += chunk_size;

                if (self.options.max_output_size - out.items.len < chunk_size) {
                    return error.ExceededSizeLimit;
                }

                out.appendSlice(allocator, chunk_data) catch return error.OutOfMemory;
            } else {
                // LZMA compressed chunk
                const mode: u2 = @truncate((control >> 5) & 3);
                const unpack_high: usize = control & 0x1F;

                if (in_pos + 4 > src.len) return error.UnexpectedEof;
                const unpack_low = @as(usize, src[in_pos]) << 8 | @as(usize, src[in_pos + 1]);
                const unpack_size = (unpack_high << 16 | unpack_low) + 1;
                in_pos += 2;

                const pack_size = (@as(usize, src[in_pos]) << 8 | @as(usize, src[in_pos + 1])) + 1;
                in_pos += 2;

                // Mode checks
                if (mode == 3) {
                    self.dict_reset_needed = false;
                    self.need_props = false;
                    self.state.reset();
                } else if (mode == 2) {
                    if (self.dict_reset_needed) return error.DictionaryResetExpected;
                    self.need_props = false;
                    self.state.reset();
                } else if (mode == 1) {
                    if (self.dict_reset_needed or self.need_props) return error.DictionaryResetExpected;
                    self.state.reset();
                } else {
                    // mode 0: no reset
                    if (self.dict_reset_needed or self.need_props) return error.DictionaryResetExpected;
                }

                if (mode >= 2) {
                    if (in_pos >= src.len) return error.UnexpectedEof;
                    var prop_byte = src[in_pos];
                    in_pos += 1;

                    if (prop_byte >= (9 * 5 * 5)) return error.InvalidProperties;
                    const lc: u4 = @truncate(prop_byte % 9);
                    prop_byte /= 9;
                    const pb: u4 = @truncate(prop_byte / 5);
                    const lp: u4 = @truncate(prop_byte % 5);

                    if (@as(u5, lc) + @as(u5, lp) > 4 or pb > 4) {
                        return error.InvalidProperties;
                    }
                    self.state.setProps(lc, lp, pb);
                }

                if (src.len - in_pos < pack_size) return error.UnexpectedEof;
                const pack_data = src[in_pos .. in_pos + pack_size];
                in_pos += pack_size;

                if (self.options.max_output_size - out.items.len < unpack_size) {
                    return error.ExceededSizeLimit;
                }

                try self.decodeLzmaChunkAlloc(allocator, &out, pack_data, unpack_size);
            }
        }

        return error.UnexpectedEof;
    }

    /// Decompresses directly into a caller-provided destination slice.
    pub fn decompressToSlice(self: *Decompressor, dest: []u8, src: []const u8) errors.DecompressError!usize {
        var out_pos: usize = 0;
        var in_pos: usize = 0;
        self.reset();

        while (in_pos < src.len) {
            const control = src[in_pos];
            in_pos += 1;

            if (control == CONTROL_EOF) {
                return out_pos;
            }

            if ((control & CONTROL_LZMA_MASK) == 0) {
                // Uncompressed chunk
                if (control > CONTROL_COPY_NO_RESET) {
                    return error.InvalidControlByte;
                }

                if (control == CONTROL_COPY_RESET_DIC) {
                    self.dict_reset_needed = false;
                    self.need_props = true;
                } else if (self.dict_reset_needed) {
                    return error.DictionaryResetExpected;
                }

                if (in_pos + 2 > src.len) return error.UnexpectedEof;
                const chunk_size = (@as(usize, src[in_pos]) << 8 | @as(usize, src[in_pos + 1])) + 1;
                in_pos += 2;

                if (src.len - in_pos < chunk_size) return error.UnexpectedEof;
                const chunk_data = src[in_pos .. in_pos + chunk_size];
                in_pos += chunk_size;

                if (dest.len - out_pos < chunk_size) return error.OutputTooSmall;
                if (self.options.max_output_size - out_pos < chunk_size) return error.ExceededSizeLimit;

                @memcpy(dest[out_pos .. out_pos + chunk_size], chunk_data);
                out_pos += chunk_size;
            } else {
                // LZMA compressed chunk
                const mode: u2 = @truncate((control >> 5) & 3);
                const unpack_high: usize = control & 0x1F;

                if (in_pos + 4 > src.len) return error.UnexpectedEof;
                const unpack_low = @as(usize, src[in_pos]) << 8 | @as(usize, src[in_pos + 1]);
                const unpack_size = (unpack_high << 16 | unpack_low) + 1;
                in_pos += 2;

                const pack_size = (@as(usize, src[in_pos]) << 8 | @as(usize, src[in_pos + 1])) + 1;
                in_pos += 2;

                if (mode == 3) {
                    self.dict_reset_needed = false;
                    self.need_props = false;
                    self.state.reset();
                } else if (mode == 2) {
                    if (self.dict_reset_needed) return error.DictionaryResetExpected;
                    self.need_props = false;
                    self.state.reset();
                } else if (mode == 1) {
                    if (self.dict_reset_needed or self.need_props) return error.DictionaryResetExpected;
                    self.state.reset();
                } else {
                    if (self.dict_reset_needed or self.need_props) return error.DictionaryResetExpected;
                }

                if (mode >= 2) {
                    if (in_pos >= src.len) return error.UnexpectedEof;
                    var prop_byte = src[in_pos];
                    in_pos += 1;

                    if (prop_byte >= (9 * 5 * 5)) return error.InvalidProperties;
                    const lc: u4 = @truncate(prop_byte % 9);
                    prop_byte /= 9;
                    const pb: u4 = @truncate(prop_byte / 5);
                    const lp: u4 = @truncate(prop_byte % 5);

                    if (@as(u5, lc) + @as(u5, lp) > 4 or pb > 4) {
                        return error.InvalidProperties;
                    }
                    self.state.setProps(lc, lp, pb);
                }

                if (src.len - in_pos < pack_size) return error.UnexpectedEof;
                const pack_data = src[in_pos .. in_pos + pack_size];
                in_pos += pack_size;

                if (dest.len - out_pos < unpack_size) return error.OutputTooSmall;
                if (self.options.max_output_size - out_pos < unpack_size) return error.ExceededSizeLimit;

                try self.decodeLzmaChunkSlice(dest, &out_pos, pack_data, unpack_size);
            }
        }

        return error.UnexpectedEof;
    }

    fn decodeLzmaChunkAlloc(
        self: *Decompressor,
        allocator: std.mem.Allocator,
        out: *std.ArrayList(u8),
        pack_data: []const u8,
        unpack_size: usize,
    ) errors.DecompressError!void {
        var rc = try RangeDecoder.init(pack_data);
        var decoded: usize = 0;
        out.ensureUnusedCapacity(allocator, unpack_size) catch return error.OutOfMemory;

        while (decoded < unpack_size) {
            const current_pos = out.items.len;
            const pos_state = self.state.getPosState(current_pos);

            if (try rc.decodeBit(&self.state.is_match[self.state.state][pos_state]) == 0) {
                // Literal
                const prev_byte = if (current_pos > 0) out.items[current_pos - 1] else 0;
                const match_byte = if (current_pos >= self.state.reps[0])
                    out.items[current_pos - self.state.reps[0]]
                else
                    0;

                const lit = try self.state.decodeLiteral(&rc, current_pos, prev_byte, match_byte);
                out.appendAssumeCapacity(lit);
                decoded += 1;
            } else {
                // Match
                var len: u32 = 0;
                if (try rc.decodeBit(&self.state.is_rep[self.state.state]) == 0) {
                    // Simple match
                    self.state.reps[3] = self.state.reps[2];
                    self.state.reps[2] = self.state.reps[1];
                    self.state.reps[1] = self.state.reps[0];
                    len = try self.state.len_coder.decode(&rc, pos_state);
                    self.state.updateStateMatch();
                    self.state.reps[0] = try self.state.decodeDistance(&rc, len);
                } else {
                    // Repeated match
                    if (try rc.decodeBit(&self.state.is_rep_g0[self.state.state]) == 0) {
                        if (try rc.decodeBit(&self.state.is_rep0_long[self.state.state][pos_state]) == 0) {
                            // Short rep
                            self.state.updateStateShortRep();
                            len = 1;
                        }
                    } else {
                        var dist: u32 = 0;
                        if (try rc.decodeBit(&self.state.is_rep_g1[self.state.state]) == 0) {
                            dist = self.state.reps[1];
                        } else {
                            if (try rc.decodeBit(&self.state.is_rep_g2[self.state.state]) == 0) {
                                dist = self.state.reps[2];
                            } else {
                                dist = self.state.reps[3];
                                self.state.reps[3] = self.state.reps[2];
                            }
                            self.state.reps[2] = self.state.reps[1];
                        }
                        self.state.reps[1] = self.state.reps[0];
                        self.state.reps[0] = dist;
                    }

                    if (len == 0) {
                        len = try self.state.rep_len_coder.decode(&rc, pos_state);
                        self.state.updateStateRep();
                    }
                }

                if (self.state.reps[0] == 0 or self.state.reps[0] > current_pos) {
                    return error.CorruptData;
                }
                if (decoded + len > unpack_size) {
                    return error.CorruptData;
                }

                const rep0 = self.state.reps[0];
                if (rep0 == 1) {
                    const b = out.items[out.items.len - 1];
                    const start = out.items.len;
                    out.items.len += len;
                    @memset(out.items[start .. start + len], b);
                } else if (rep0 >= len) {
                    const start = out.items.len;
                    const src_start = start - rep0;
                    out.items.len += len;
                    @memcpy(out.items[start .. start + len], out.items[src_start .. src_start + len]);
                } else {
                    var i: u32 = 0;
                    while (i < len) : (i += 1) {
                        const match_pos = out.items.len - rep0;
                        const b = out.items[match_pos];
                        out.appendAssumeCapacity(b);
                    }
                }
                decoded += len;
            }
        }
    }

    fn decodeLzmaChunkSlice(
        self: *Decompressor,
        dest: []u8,
        out_pos: *usize,
        pack_data: []const u8,
        unpack_size: usize,
    ) errors.DecompressError!void {
        var rc = try RangeDecoder.init(pack_data);
        var decoded: usize = 0;

        while (decoded < unpack_size) {
            const current_pos = out_pos.*;
            const pos_state = self.state.getPosState(current_pos);

            if (try rc.decodeBit(&self.state.is_match[self.state.state][pos_state]) == 0) {
                // Literal
                const prev_byte = if (current_pos > 0) dest[current_pos - 1] else 0;
                const match_byte = if (current_pos >= self.state.reps[0])
                    dest[current_pos - self.state.reps[0]]
                else
                    0;

                const lit = try self.state.decodeLiteral(&rc, current_pos, prev_byte, match_byte);
                dest[current_pos] = lit;
                out_pos.* += 1;
                decoded += 1;
            } else {
                // Match
                var len: u32 = 0;
                if (try rc.decodeBit(&self.state.is_rep[self.state.state]) == 0) {
                    // Simple match
                    self.state.reps[3] = self.state.reps[2];
                    self.state.reps[2] = self.state.reps[1];
                    self.state.reps[1] = self.state.reps[0];
                    len = try self.state.len_coder.decode(&rc, pos_state);
                    self.state.updateStateMatch();
                    self.state.reps[0] = try self.state.decodeDistance(&rc, len);
                } else {
                    // Repeated match
                    if (try rc.decodeBit(&self.state.is_rep_g0[self.state.state]) == 0) {
                        if (try rc.decodeBit(&self.state.is_rep0_long[self.state.state][pos_state]) == 0) {
                            // Short rep
                            self.state.updateStateShortRep();
                            len = 1;
                        }
                    } else {
                        var dist: u32 = 0;
                        if (try rc.decodeBit(&self.state.is_rep_g1[self.state.state]) == 0) {
                            dist = self.state.reps[1];
                        } else {
                            if (try rc.decodeBit(&self.state.is_rep_g2[self.state.state]) == 0) {
                                dist = self.state.reps[2];
                            } else {
                                dist = self.state.reps[3];
                                self.state.reps[3] = self.state.reps[2];
                            }
                            self.state.reps[2] = self.state.reps[1];
                        }
                        self.state.reps[1] = self.state.reps[0];
                        self.state.reps[0] = dist;
                    }

                    if (len == 0) {
                        len = try self.state.rep_len_coder.decode(&rc, pos_state);
                        self.state.updateStateRep();
                    }
                }

                if (self.state.reps[0] == 0 or self.state.reps[0] > current_pos) {
                    return error.CorruptData;
                }
                if (decoded + len > unpack_size) {
                    return error.CorruptData;
                }

                const rep0 = self.state.reps[0];
                if (rep0 == 1) {
                    @memset(dest[out_pos.* .. out_pos.* + len], dest[out_pos.* - 1]);
                    out_pos.* += len;
                } else if (rep0 >= len) {
                    @memcpy(dest[out_pos.* .. out_pos.* + len], dest[out_pos.* - rep0 .. out_pos.* - rep0 + len]);
                    out_pos.* += len;
                } else {
                    var i: u32 = 0;
                    while (i < len) : (i += 1) {
                        const match_pos = out_pos.* - rep0;
                        dest[out_pos.*] = dest[match_pos];
                        out_pos.* += 1;
                    }
                }
                decoded += len;
            }
        }
    }
};

/// Convenience one-shot function to decompress an LZMA2 stream into a newly allocated buffer.
pub fn decompress(allocator: std.mem.Allocator, src: []const u8, options: DecompressOptions) errors.DecompressError![]u8 {
    var dec = Decompressor.init(options);
    return dec.decompressAlloc(allocator, src);
}

/// Convenience one-shot function to decompress an LZMA2 stream into a caller-provided buffer.
pub fn decompressBuffer(dest: []u8, src: []const u8, options: DecompressOptions) errors.DecompressError!usize {
    var dec = Decompressor.init(options);
    return dec.decompressToSlice(dest, src);
}

/// Alias for decompressBuffer following standard library Into conventions.
pub const decompressInto = decompressBuffer;

test "decoder: rejection of invalid control byte" {
    const bad_header = [_]u8{ 0x05, 0x00, 0x00, 0x00 };
    try std.testing.expectError(error.InvalidControlByte, decompress(std.testing.allocator, &bad_header, .{}));
}

test "decoder: rejection of missing dictionary reset" {
    const no_reset = [_]u8{ 0x02, 0x00, 0x01, 0x41, 0x00 };
    try std.testing.expectError(error.DictionaryResetExpected, decompress(std.testing.allocator, &no_reset, .{}));
}

test "decoder: output size limit exceeded" {
    const copy_chunk = [_]u8{ 0x01, 0x00, 0x04, 'A', 'A', 'A', 'A', 'A', 0x00 };
    const opts = DecompressOptions{ .max_output_size = 3 };
    try std.testing.expectError(error.ExceededSizeLimit, decompress(std.testing.allocator, &copy_chunk, opts));
}

test "decoder: decompressInto caller buffer" {
    const copy_chunk = [_]u8{ 0x01, 0x00, 0x04, 'H', 'E', 'L', 'L', 'O', 0x00 };
    var out: [16]u8 = undefined;
    const n = try decompressInto(&out, &copy_chunk, .{});
    try std.testing.expectEqual(@as(usize, 5), n);
    try std.testing.expectEqualSlices(u8, "HELLO", out[0..n]);
}

test "decoder: decompress upstream XZ raw copy chunk test vector" {
    const xz_vector = [_]u8{
        0x01, 0x00, 0x37, 0x54, 0x68, 0x65, 0x20, 0x71, 0x75, 0x69, 0x63, 0x6B,
        0x20, 0x62, 0x72, 0x6F, 0x77, 0x6E, 0x20, 0x66, 0x6F, 0x78, 0x20, 0x6A,
        0x75, 0x6D, 0x70, 0x73, 0x20, 0x6F, 0x76, 0x65, 0x72, 0x20, 0x74, 0x68,
        0x65, 0x20, 0x6C, 0x61, 0x7A, 0x79, 0x20, 0x64, 0x6F, 0x67, 0x2E, 0x20,
        0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30, 0x21, 0x00,
    };
    const expected = "The quick brown fox jumps over the lazy dog. 1234567890!";
    const result = try decompress(std.testing.allocator, &xz_vector, .{});
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, expected, result);
}

test "decoder: rejection of truncated copy chunk header" {
    const truncated_hdr = [_]u8{0x01};
    try std.testing.expectError(error.UnexpectedEof, decompress(std.testing.allocator, &truncated_hdr, .{}));
}

test "decoder: rejection of truncated copy chunk payload" {
    const truncated_payload = [_]u8{ 0x01, 0x00, 0x05, 'A', 'B' };
    try std.testing.expectError(error.UnexpectedEof, decompress(std.testing.allocator, &truncated_payload, .{}));
}

test "decoder: rejection of invalid property byte in compressed chunk" {
    // Mode 3 (0xE0) requires 6-byte header: unpack, pack, prop.
    // Prop byte 230 >= 9*5*5 (225) -> error.InvalidProperties
    const invalid_prop = [_]u8{ 0xE0, 0x00, 0x04, 0x00, 0x05, 230, 0x00, 0x00, 0x00, 0x00, 0x00 };
    try std.testing.expectError(error.InvalidProperties, decompress(std.testing.allocator, &invalid_prop, .{}));
}

test "decoder: rejection of non-zero first byte in range coder payload" {
    // Mode 3 with first range coder byte 0xFF instead of 0x00 (pack size 5 means 6 payload bytes)
    const corrupt_rc = [_]u8{ 0xE0, 0x00, 0x04, 0x00, 0x05, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00 };
    try std.testing.expectError(error.CorruptData, decompress(std.testing.allocator, &corrupt_rc, .{}));
}
