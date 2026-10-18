//! Raw LZMA Stream Decoder.
//!
//! Decodes raw LZMA streams (without container headers) using adaptive Markov
//! probability models, range decoding, rep-match distance registers, and
//! length decoding trees. Supports known-size streams and dynamic EOS streams.

const std = @import("std");
const errors = @import("../utils/errors.zig");
const options_mod = @import("../utils/options.zig");
const range_codec = @import("../utils/range_codec.zig");
const RangeDecoder = range_codec.RangeDecoder;
const state_mod = @import("../utils/state.zig");
const LzmaState = state_mod.LzmaState;

/// Stateful raw LZMA decompressor context.
pub const Decoder = struct {
    options: options_mod.LzmaDecompressOptions,

    pub fn init(options: options_mod.LzmaDecompressOptions) Decoder {
        return Decoder{ .options = options };
    }

    pub fn decode(self: *Decoder, allocator: std.mem.Allocator, src: []const u8) errors.DecompressError![]u8 {
        return decompressRaw(allocator, src, self.options);
    }
};

pub const LzmaDecoder = Decoder;

/// Decompresses data from a raw LZMA stream.
pub fn decompressRaw(allocator: std.mem.Allocator, src: []const u8, options: options_mod.LzmaDecompressOptions) errors.DecompressError![]u8 {
    if (@as(u5, options.lc) + @as(u5, options.lp) > 4 or options.pb > 4) {
        return error.InvalidProperties;
    }
    var state = LzmaState.init(options.lc, options.lp, options.pb);
    var rc = try RangeDecoder.init(src);

    if (options.uncompressed_size) |sz| {
        if (sz > std.math.maxInt(usize) or sz > options.max_output_size) return error.ExceededSizeLimit;
        if (sz == 0) return try allocator.alloc(u8, 0);

        const dest_len = std.math.cast(usize, sz) orelse return error.ExceededSizeLimit;
        const dest = try allocator.alloc(u8, dest_len);
        errdefer allocator.free(dest);

        var out_pos: usize = 0;
        while (out_pos < dest.len) {
            const pos_state = state.getPosState(out_pos);
            if (try rc.decodeBit(&state.is_match[state.state][pos_state]) == 0) {
                const prev_byte = if (out_pos > 0) dest[out_pos - 1] else 0;
                const match_byte = if (out_pos >= state.reps[0]) dest[out_pos - state.reps[0]] else 0;
                dest[out_pos] = try state.decodeLiteral(&rc, out_pos, prev_byte, match_byte);
                out_pos += 1;
            } else {
                var len: u32 = 0;
                if (try rc.decodeBit(&state.is_rep[state.state]) == 0) {
                    state.reps[3] = state.reps[2];
                    state.reps[2] = state.reps[1];
                    state.reps[1] = state.reps[0];
                    len = try state.len_coder.decode(&rc, pos_state);
                    state.updateStateMatch();
                    state.reps[0] = try state.decodeDistance(&rc, len);
                } else {
                    if (try rc.decodeBit(&state.is_rep_g0[state.state]) == 0) {
                        if (try rc.decodeBit(&state.is_rep0_long[state.state][pos_state]) == 0) {
                            state.updateStateShortRep();
                            len = 1;
                        }
                    } else {
                        var dist: u32 = 0;
                        if (try rc.decodeBit(&state.is_rep_g1[state.state]) == 0) {
                            dist = state.reps[1];
                        } else {
                            if (try rc.decodeBit(&state.is_rep_g2[state.state]) == 0) {
                                dist = state.reps[2];
                            } else {
                                dist = state.reps[3];
                                state.reps[3] = state.reps[2];
                            }
                            state.reps[2] = state.reps[1];
                        }
                        state.reps[1] = state.reps[0];
                        state.reps[0] = dist;
                    }
                    if (len == 0) {
                        len = try state.rep_len_coder.decode(&rc, pos_state);
                        state.updateStateRep();
                    }
                }

                if (state.reps[0] == 0xFFFFFFFF) {
                    break;
                }

                if (state.reps[0] == 0 or state.reps[0] > out_pos) return error.CorruptData;
                const rep0 = state.reps[0];
                if (rep0 == 1) {
                    const copy_len = @min(len, @as(u32, @intCast(dest.len - out_pos)));
                    @memset(dest[out_pos .. out_pos + copy_len], dest[out_pos - 1]);
                    out_pos += copy_len;
                } else if (rep0 >= len and out_pos + len <= dest.len) {
                    @memcpy(dest[out_pos .. out_pos + len], dest[out_pos - rep0 .. out_pos - rep0 + len]);
                    out_pos += len;
                } else {
                    var c: u32 = 0;
                    while (c < len and out_pos < dest.len) : (c += 1) {
                        dest[out_pos] = dest[out_pos - rep0];
                        out_pos += 1;
                    }
                }
            }
        }
        return dest;
    } else {
        var out_list: std.ArrayList(u8) = .empty;
        errdefer out_list.deinit(allocator);

        while (true) {
            const out_pos = out_list.items.len;
            if (out_pos > options.max_output_size) return error.ExceededSizeLimit;

            const pos_state = state.getPosState(out_pos);
            if (try rc.decodeBit(&state.is_match[state.state][pos_state]) == 0) {
                const prev_byte = if (out_pos > 0) out_list.items[out_pos - 1] else 0;
                const match_byte = if (out_pos >= state.reps[0]) out_list.items[out_pos - state.reps[0]] else 0;
                const lit = try state.decodeLiteral(&rc, out_pos, prev_byte, match_byte);
                out_list.append(allocator, lit) catch return error.OutOfMemory;
            } else {
                var len: u32 = 0;
                if (try rc.decodeBit(&state.is_rep[state.state]) == 0) {
                    state.reps[3] = state.reps[2];
                    state.reps[2] = state.reps[1];
                    state.reps[1] = state.reps[0];
                    len = try state.len_coder.decode(&rc, pos_state);
                    state.updateStateMatch();
                    state.reps[0] = try state.decodeDistance(&rc, len);
                } else {
                    if (try rc.decodeBit(&state.is_rep_g0[state.state]) == 0) {
                        if (try rc.decodeBit(&state.is_rep0_long[state.state][pos_state]) == 0) {
                            state.updateStateShortRep();
                            len = 1;
                        }
                    } else {
                        var dist: u32 = 0;
                        if (try rc.decodeBit(&state.is_rep_g1[state.state]) == 0) {
                            dist = state.reps[1];
                        } else {
                            if (try rc.decodeBit(&state.is_rep_g2[state.state]) == 0) {
                                dist = state.reps[2];
                            } else {
                                dist = state.reps[3];
                                state.reps[3] = state.reps[2];
                            }
                            state.reps[2] = state.reps[1];
                        }
                        state.reps[1] = state.reps[0];
                        state.reps[0] = dist;
                    }
                    if (len == 0) {
                        len = try state.rep_len_coder.decode(&rc, pos_state);
                        state.updateStateRep();
                    }
                }

                if (state.reps[0] == 0xFFFFFFFF) {
                    break;
                }

                if (state.reps[0] == 0 or state.reps[0] > out_pos) return error.CorruptData;
                const rep0 = state.reps[0];
                try out_list.ensureUnusedCapacity(allocator, len);
                if (rep0 == 1) {
                    const b = out_list.items[out_list.items.len - 1];
                    const start = out_list.items.len;
                    out_list.items.len += len;
                    @memset(out_list.items[start .. start + len], b);
                } else if (rep0 >= len) {
                    const start = out_list.items.len;
                    const src_start = start - rep0;
                    out_list.items.len += len;
                    @memcpy(out_list.items[start .. start + len], out_list.items[src_start .. src_start + len]);
                } else {
                    var c: u32 = 0;
                    while (c < len) : (c += 1) {
                        const b = out_list.items[out_list.items.len - rep0];
                        out_list.appendAssumeCapacity(b);
                    }
                }
            }
        }

        return out_list.toOwnedSlice(allocator) catch return error.OutOfMemory;
    }
}

/// Zero-allocation raw LZMA decompression into caller buffer.
pub fn decompressRawInto(dest: []u8, src: []const u8, options: options_mod.LzmaDecompressOptions) errors.DecompressError!usize {
    if (@as(u5, options.lc) + @as(u5, options.lp) > 4 or options.pb > 4) {
        return error.InvalidProperties;
    }
    var state = LzmaState.init(options.lc, options.lp, options.pb);
    var rc = try RangeDecoder.init(src);

    const limit = if (options.uncompressed_size) |sz| @min(sz, dest.len) else dest.len;
    var out_pos: usize = 0;

    while (out_pos < limit) {
        const pos_state = state.getPosState(out_pos);
        if (try rc.decodeBit(&state.is_match[state.state][pos_state]) == 0) {
            const prev_byte = if (out_pos > 0) dest[out_pos - 1] else 0;
            const match_byte = if (out_pos >= state.reps[0]) dest[out_pos - state.reps[0]] else 0;
            dest[out_pos] = try state.decodeLiteral(&rc, out_pos, prev_byte, match_byte);
            out_pos += 1;
        } else {
            var len: u32 = 0;
            if (try rc.decodeBit(&state.is_rep[state.state]) == 0) {
                state.reps[3] = state.reps[2];
                state.reps[2] = state.reps[1];
                state.reps[1] = state.reps[0];
                len = try state.len_coder.decode(&rc, pos_state);
                state.updateStateMatch();
                state.reps[0] = try state.decodeDistance(&rc, len);
            } else {
                if (try rc.decodeBit(&state.is_rep_g0[state.state]) == 0) {
                    if (try rc.decodeBit(&state.is_rep0_long[state.state][pos_state]) == 0) {
                        state.updateStateShortRep();
                        len = 1;
                    }
                } else {
                    var dist: u32 = 0;
                    if (try rc.decodeBit(&state.is_rep_g1[state.state]) == 0) {
                        dist = state.reps[1];
                    } else {
                        if (try rc.decodeBit(&state.is_rep_g2[state.state]) == 0) {
                            dist = state.reps[2];
                        } else {
                            dist = state.reps[3];
                            state.reps[3] = state.reps[2];
                        }
                        state.reps[2] = state.reps[1];
                    }
                    state.reps[1] = state.reps[0];
                    state.reps[0] = dist;
                }
                if (len == 0) {
                    len = try state.rep_len_coder.decode(&rc, pos_state);
                    state.updateStateRep();
                }
            }

            if (state.reps[0] == 0xFFFFFFFF) {
                break;
            }

            if (state.reps[0] == 0 or state.reps[0] > out_pos) return error.CorruptData;
            const rep0 = state.reps[0];
            if (rep0 == 1) {
                const copy_len = @min(len, @as(u32, @intCast(limit - out_pos)));
                @memset(dest[out_pos .. out_pos + copy_len], dest[out_pos - 1]);
                out_pos += copy_len;
            } else if (rep0 >= len and out_pos + len <= limit) {
                @memcpy(dest[out_pos .. out_pos + len], dest[out_pos - rep0 .. out_pos - rep0 + len]);
                out_pos += len;
            } else {
                var c: u32 = 0;
                while (c < len and out_pos < limit) : (c += 1) {
                    dest[out_pos] = dest[out_pos - rep0];
                    out_pos += 1;
                }
            }
        }
    }

    return out_pos;
}

pub const decompressRawBuffer = decompressRawInto;

/// Streaming raw LZMA decompression from reader to writer.
pub fn decompressRawStream(allocator: std.mem.Allocator, reader: anytype, writer: anytype, options: options_mod.LzmaDecompressOptions) errors.DecompressError!void {
    var in_buf = std.ArrayList(u8).empty;
    defer in_buf.deinit(allocator);

    var chunk: [16384]u8 = undefined;
    while (true) {
        const n = reader.read(&chunk) catch return error.CorruptData;
        if (n == 0) break;
        in_buf.appendSlice(allocator, chunk[0..n]) catch return error.OutOfMemory;
    }

    const decompressed = try decompressRaw(allocator, in_buf.items, options);
    defer allocator.free(decompressed);

    writer.writeAll(decompressed) catch return error.OutputTooSmall;
}

test "lzma_decoder: caller buffer decompressRawInto" {
    const allocator = std.testing.allocator;
    const lzma_enc = @import("../compress/lzma.zig");
    const msg = "Testing decompressRawInto caller buffer functionality.";

    const comp = try lzma_enc.compressRaw(allocator, msg, .{ .write_end_mark = false });
    defer allocator.free(comp);

    var out_buf: [256]u8 = undefined;
    const dec_len = try decompressRawInto(&out_buf, comp, .{ .uncompressed_size = msg.len });

    try std.testing.expectEqualSlices(u8, msg, out_buf[0..dec_len]);
}

test "lzma_decoder: empty uncompressed size" {
    const allocator = std.testing.allocator;
    const dec = try decompressRaw(allocator, &[_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00 }, .{ .uncompressed_size = 0 });
    defer allocator.free(dec);
    try std.testing.expectEqual(@as(usize, 0), dec.len);
}

test "lzma_decoder: raw stream with EOS marker roundtrip" {
    const allocator = std.testing.allocator;
    const lzma_enc = @import("../compress/lzma.zig");
    const msg = "Raw stream roundtrip with explicit end of stream marker.";

    const comp = try lzma_enc.compressRaw(allocator, msg, .{ .write_end_mark = true });
    defer allocator.free(comp);

    const dec = try decompressRaw(allocator, comp, .{ .uncompressed_size = null });
    defer allocator.free(dec);

    try std.testing.expectEqualSlices(u8, msg, dec);
}

test "lzma_decoder: truncated stream rejection" {
    const allocator = std.testing.allocator;
    const bad_stream = [_]u8{ 0x00, 0x00 };
    try std.testing.expectError(error.UnexpectedEof, decompressRaw(allocator, &bad_stream, .{ .uncompressed_size = 10 }));
}
