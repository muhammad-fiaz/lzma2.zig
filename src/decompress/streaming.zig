//! Streaming LZMA2 decompressor.
//!
//! Provides genuine chunk-by-chunk and reader/writer streaming decompression
//! with bounded memory usage, sliding dictionary history, and incremental I/O.

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

/// Incremental streaming LZMA2 decompressor.
pub const StreamingDecompressor = struct {
    allocator: std.mem.Allocator,
    options: DecompressOptions,
    state: LzmaState,
    in_buffer: std.ArrayList(u8),
    history: std.ArrayList(u8),
    out_read_pos: usize = 0,
    total_out: usize = 0,
    dict_reset_needed: bool = true,
    need_props: bool = false,
    finished: bool = false,

    pub fn init(allocator: std.mem.Allocator, options: DecompressOptions) StreamingDecompressor {
        return StreamingDecompressor{
            .allocator = allocator,
            .options = options,
            .state = LzmaState.init(options_mod.DEFAULT_LC, options_mod.DEFAULT_LP, options_mod.DEFAULT_PB),
            .in_buffer = std.ArrayList(u8).empty,
            .history = std.ArrayList(u8).empty,
            .out_read_pos = 0,
            .total_out = 0,
            .dict_reset_needed = true,
            .need_props = false,
            .finished = false,
        };
    }

    pub fn deinit(self: *StreamingDecompressor) void {
        self.in_buffer.deinit(self.allocator);
        self.history.deinit(self.allocator);
    }

    pub fn reset(self: *StreamingDecompressor) void {
        self.state.reset();
        self.in_buffer.clearRetainingCapacity();
        self.history.clearRetainingCapacity();
        self.out_read_pos = 0;
        self.total_out = 0;
        self.dict_reset_needed = true;
        self.need_props = false;
        self.finished = false;
    }

    /// Feeds compressed data chunk into the decompressor.
    pub fn feed(self: *StreamingDecompressor, chunk: []const u8) errors.DecompressError!void {
        if (chunk.len == 0) return;
        self.in_buffer.appendSlice(self.allocator, chunk) catch return error.OutOfMemory;

        var in_pos: usize = 0;
        while (in_pos < self.in_buffer.items.len) {
            const control = self.in_buffer.items[in_pos];
            if (control == CONTROL_EOF) {
                self.finished = true;
                in_pos += 1;
                break;
            }

            if ((control & CONTROL_LZMA_MASK) == 0) {
                // Uncompressed copy chunk
                if (control > CONTROL_COPY_NO_RESET) {
                    return error.InvalidControlByte;
                }

                if (in_pos + 3 > self.in_buffer.items.len) {
                    break; // Wait for full 3-byte header
                }

                const chunk_size = (@as(usize, self.in_buffer.items[in_pos + 1]) << 8 |
                    @as(usize, self.in_buffer.items[in_pos + 2])) + 1;

                if (self.in_buffer.items.len - in_pos < 3 + chunk_size) {
                    break; // Wait for full payload
                }

                if (control == CONTROL_COPY_RESET_DIC) {
                    self.dict_reset_needed = false;
                    self.need_props = true;
                    self.history.clearRetainingCapacity();
                    self.out_read_pos = 0;
                } else if (self.dict_reset_needed) {
                    return error.DictionaryResetExpected;
                }

                if (self.options.max_output_size - self.total_out < chunk_size) {
                    return error.ExceededSizeLimit;
                }

                const chunk_data = self.in_buffer.items[in_pos + 3 .. in_pos + 3 + chunk_size];
                self.history.appendSlice(self.allocator, chunk_data) catch return error.OutOfMemory;
                self.total_out += chunk_size;
                in_pos += 3 + chunk_size;
            } else {
                // LZMA compressed chunk
                const mode: u2 = @truncate((control >> 5) & 3);
                const unpack_high: usize = control & 0x1F;
                const header_size: usize = if (mode >= 2) 6 else 5;

                if (in_pos + header_size > self.in_buffer.items.len) {
                    break; // Wait for full chunk header
                }

                const unpack_low = @as(usize, self.in_buffer.items[in_pos + 1]) << 8 |
                    @as(usize, self.in_buffer.items[in_pos + 2]);
                const unpack_size = (unpack_high << 16 | unpack_low) + 1;

                const pack_size = (@as(usize, self.in_buffer.items[in_pos + 3]) << 8 |
                    @as(usize, self.in_buffer.items[in_pos + 4])) + 1;

                if (self.in_buffer.items.len - in_pos < header_size + pack_size) {
                    break; // Wait for full chunk payload
                }

                // Mode checks
                if (mode == 3) {
                    self.dict_reset_needed = false;
                    self.need_props = false;
                    self.state.reset();
                    self.history.clearRetainingCapacity();
                    self.out_read_pos = 0;
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
                    const prop_byte = self.in_buffer.items[in_pos + 5];
                    if (prop_byte >= (9 * 5 * 5)) return error.InvalidProperties;
                    const lc: u4 = @truncate(prop_byte % 9);
                    const rem = prop_byte / 9;
                    const pb: u4 = @truncate(rem / 5);
                    const lp: u4 = @truncate(rem % 5);

                    if (@as(u5, lc) + @as(u5, lp) > 4 or pb > 4) {
                        return error.InvalidProperties;
                    }
                    self.state.setProps(lc, lp, pb);
                }

                if (self.options.max_output_size - self.total_out < unpack_size) {
                    return error.ExceededSizeLimit;
                }

                const pack_data = self.in_buffer.items[in_pos + header_size .. in_pos + header_size + pack_size];
                try self.decodeLzmaChunk(pack_data, unpack_size);
                self.total_out += unpack_size;
                in_pos += header_size + pack_size;
            }
        }

        if (in_pos > 0) {
            const rem = self.in_buffer.items.len - in_pos;
            if (rem > 0) {
                std.mem.copyForwards(u8, self.in_buffer.items[0..rem], self.in_buffer.items[in_pos..]);
            }
            self.in_buffer.shrinkRetainingCapacity(rem);
        }
    }

    fn decodeLzmaChunk(self: *StreamingDecompressor, pack_data: []const u8, unpack_size: usize) errors.DecompressError!void {
        var rc = try RangeDecoder.init(pack_data);
        var decoded: usize = 0;

        while (decoded < unpack_size) {
            const current_pos = self.total_out + decoded;
            const pos_state = self.state.getPosState(current_pos);

            if (try rc.decodeBit(&self.state.is_match[self.state.state][pos_state]) == 0) {
                // Literal
                const prev_byte = if (self.history.items.len > 0) self.history.items[self.history.items.len - 1] else 0;
                const match_byte = if (self.history.items.len >= self.state.reps[0])
                    self.history.items[self.history.items.len - self.state.reps[0]]
                else
                    0;

                const lit = try self.state.decodeLiteral(&rc, current_pos, prev_byte, match_byte);
                self.history.append(self.allocator, lit) catch return error.OutOfMemory;
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

                if (self.state.reps[0] == 0 or self.state.reps[0] > self.history.items.len) {
                    return error.CorruptData;
                }
                if (decoded + len > unpack_size) {
                    return error.CorruptData;
                }

                var i: u32 = 0;
                while (i < len) : (i += 1) {
                    const match_pos = self.history.items.len - self.state.reps[0];
                    const b = self.history.items[match_pos];
                    self.history.append(self.allocator, b) catch return error.OutOfMemory;
                }
                decoded += len;
            }
        }
    }

    /// Reads decompressed bytes into caller-provided destination slice.
    pub fn take(self: *StreamingDecompressor, dst: []u8) usize {
        const available = self.history.items.len - self.out_read_pos;
        if (available == 0) return 0;

        const to_copy = @min(available, dst.len);
        @memcpy(dst[0..to_copy], self.history.items[self.out_read_pos .. self.out_read_pos + to_copy]);
        self.out_read_pos += to_copy;

        // Slide history if caller has drained enough and history exceeds dict_size_limit margin
        const keep_history = self.options.dict_size_limit;
        if (self.out_read_pos >= 65536 and self.history.items.len > keep_history + 65536) {
            const prune = self.history.items.len - keep_history;
            const slide = @min(self.out_read_pos, prune);
            const rem = self.history.items.len - slide;
            std.mem.copyForwards(u8, self.history.items[0..rem], self.history.items[slide..]);
            self.history.shrinkRetainingCapacity(rem);
            self.out_read_pos -= slide;
        }

        return to_copy;
    }

    /// Checks if decompression has finished.
    pub fn isFinished(self: *const StreamingDecompressor) bool {
        return self.finished and (self.out_read_pos >= self.history.items.len);
    }
};

/// Streams compressed LZMA2 data from `reader` and writes decompressed data to `writer`.
pub fn decompressStream(
    allocator: std.mem.Allocator,
    reader: anytype,
    writer: anytype,
    options: DecompressOptions,
) errors.DecompressError!void {
    var sd = StreamingDecompressor.init(allocator, options);
    defer sd.deinit();

    var in_buf: [16384]u8 = undefined;
    var out_buf: [16384]u8 = undefined;

    while (true) {
        const n = reader.read(&in_buf) catch return error.CorruptData;
        if (n == 0) break;
        try sd.feed(in_buf[0..n]);

        while (true) {
            const out_n = sd.take(&out_buf);
            if (out_n == 0) break;
            writer.writeAll(out_buf[0..out_n]) catch return error.OutputTooSmall;
        }
    }

    // Flush any remaining decompressed data
    while (true) {
        const out_n = sd.take(&out_buf);
        if (out_n == 0) break;
        writer.writeAll(out_buf[0..out_n]) catch return error.OutputTooSmall;
    }

    if (!sd.isFinished()) {
        return error.UnexpectedEof;
    }
}

test "streaming decompressor: 1-byte incremental feed roundtrip" {
    const allocator = std.testing.allocator;
    const lzma2_mod = @import("../compress/lzma2.zig");
    const msg = "Incremental byte-by-byte LZMA2 streaming decompression test in native Zig!";

    const comp = try lzma2_mod.compress(allocator, msg, .{});
    defer allocator.free(comp);

    var sd = StreamingDecompressor.init(allocator, .{});
    defer sd.deinit();

    var restored = std.ArrayList(u8).empty;
    defer restored.deinit(allocator);

    // Feed 1 byte at a time!
    var out_chunk: [16]u8 = undefined;
    for (comp) |byte| {
        try sd.feed(&[_]u8{byte});
        while (true) {
            const n = sd.take(&out_chunk);
            if (n == 0) break;
            try restored.appendSlice(allocator, out_chunk[0..n]);
        }
    }

    while (true) {
        const n = sd.take(&out_chunk);
        if (n == 0) break;
        try restored.appendSlice(allocator, out_chunk[0..n]);
    }

    try std.testing.expect(sd.isFinished());
    try std.testing.expectEqualSlices(u8, msg, restored.items);
}

test "streaming decompressor: reader/writer stream roundtrip" {
    const allocator = std.testing.allocator;
    const lzma2_mod = @import("../compress/lzma2.zig");
    const msg = "Reader/writer streaming pipeline roundtrip verification for pure native Zig LZMA2.";

    const comp = try lzma2_mod.compress(allocator, msg, .{});
    defer allocator.free(comp);

    const MemoryReader = struct {
        slice: []const u8,
        pos: usize = 0,
        pub fn read(self: *@This(), dest: []u8) !usize {
            if (self.pos >= self.slice.len) return 0;
            const n = @min(self.slice.len - self.pos, dest.len);
            @memcpy(dest[0..n], self.slice[self.pos .. self.pos + n]);
            self.pos += n;
            return n;
        }
    };

    const MemoryWriter = struct {
        list: *std.ArrayList(u8),
        pub fn writeAll(self: @This(), bytes: []const u8) !void {
            try self.list.appendSlice(std.testing.allocator, bytes);
        }
    };

    var reader = MemoryReader{ .slice = comp };
    var out_list = std.ArrayList(u8).empty;
    defer out_list.deinit(allocator);
    const writer = MemoryWriter{ .list = &out_list };

    try decompressStream(allocator, &reader, writer, .{});

    try std.testing.expectEqualSlices(u8, msg, out_list.items);
}

test "streaming decompressor: corrupt control byte error" {
    const allocator = std.testing.allocator;
    var sd = StreamingDecompressor.init(allocator, .{});
    defer sd.deinit();

    // 0x05 is invalid LZMA2 control byte
    try std.testing.expectError(error.InvalidControlByte, sd.feed(&[_]u8{0x05}));
}

test "streaming decompressor: dictionary reset expected error" {
    const allocator = std.testing.allocator;
    var sd = StreamingDecompressor.init(allocator, .{});
    defer sd.deinit();

    // 0x02 is uncompressed copy WITHOUT dictionary reset, but stream must start with reset
    try std.testing.expectError(error.DictionaryResetExpected, sd.feed(&[_]u8{ 0x02, 0x00, 0x00, 0x42 }));
}
