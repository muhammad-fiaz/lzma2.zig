# Compression Presets & Levels (0–9)

This example validates and demonstrates compression behavior across all supported preset levels (Level 0 through Level 9) for both modern **LZMA2** and legacy **LZMA** formats.

---

## Use Case

Different applications require different trade-offs between compression ratio and encoding throughput:
- **Level 0 (Store mode)**: Emits uncompressed copy chunks (`0x01`/`0x02` in LZMA2). Fast throughput, zero compression ratio overhead.
- **Levels 1–3 (Fast mode)**: Uses greedy match finder heuristics and smaller dictionary depths (8 to 24) for rapid archival and logging.
- **Levels 4–9 (Normal mode)**: Uses optimal 1-step lookahead lazy match evaluation with increasing dictionary sizes (2 MiB to 64 MiB) and deeper search depths (32 to 256) for maximum compression ratio.

---

## Source Code

```zig
//! Compression levels comparison across LZMA and LZMA2 from level 0 to 9.

const std = @import("std");
const lzma2 = @import("lzma2");
const lzma = @import("lzma");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    const payload =
        \\{
        \\  "timestamp": "2026-10-17T20:30:00Z",
        \\  "cluster": "antigravity-prod-cluster-01",
        \\  "nodes": [
        \\    {"id": "node-alpha", "cpu": 14.5, "mem_mb": 4096, "status": "healthy", "region": "us-east-1"},
        \\    {"id": "node-beta",  "cpu": 82.1, "mem_mb": 7820, "status": "warning", "region": "us-east-1"},
        \\    {"id": "node-gamma", "cpu":  5.2, "mem_mb": 1024, "status": "healthy", "region": "us-west-2"},
        \\    {"id": "node-delta", "cpu": 12.0, "mem_mb": 3500, "status": "healthy", "region": "eu-central-1"}
        \\  ],
        \\  "metrics": {
        \\    "requests_per_sec": 128450,
        \\    "p50_latency_ms": 1.25,
        \\    "p95_latency_ms": 3.40,
        \\    "p99_latency_ms": 9.80,
        \\    "error_rate_pct": 0.0012
        \\  },
        \\  "log_summary": "System operating smoothly with nominal variance across all telemetry nodes."
        \\}
    ;

    std.debug.print("LZMA & LZMA2 Compression Presets & Levels Verification (Levels 0 through 9)\n", .{});
    std.debug.print("Input data size: {d} bytes\n\n", .{payload.len});

    std.debug.print("{s:<8} | {s:<18} | {s:<12} | {s:<18} | {s:<10}\n", .{
        "Level", "LZMA2 Size (Ratio)", "LZMA2 Verify", "Alone Size (Ratio)", "Alone Verify",
    });

    inline for (0..10) |lvl_idx| {
        const lvl: u4 = @intCast(lvl_idx);

        // LZMA2
        const lz2_comp = try lzma2.compress(allocator, payload, .{ .level = lvl });
        defer allocator.free(lz2_comp);

        const lz2_decomp = try lzma2.decompress(allocator, lz2_comp, .{});
        defer allocator.free(lz2_decomp);

        const lz2_match = std.mem.eql(u8, payload, lz2_decomp);
        const lz2_pct = (@as(f64, @floatFromInt(lz2_comp.len)) / @as(f64, @floatFromInt(payload.len))) * 100.0;

        // LZMA (.lzma container)
        const lz1_comp = try lzma.compress(allocator, payload, .{ .level = lvl });
        defer allocator.free(lz1_comp);

        const lz1_decomp = try lzma.decompress(allocator, lz1_comp, .{});
        defer allocator.free(lz1_decomp);

        const lz1_match = std.mem.eql(u8, payload, lz1_decomp);
        const lz1_pct = (@as(f64, @floatFromInt(lz1_comp.len)) / @as(f64, @floatFromInt(payload.len))) * 100.0;

        std.debug.print("Level {d:<2} | {d:4} B ({d:.1}%)    | {s:<12} | {d:4} B ({d:.1}%)    | {s:<10}\n", .{
            lvl,
            lz2_comp.len,
            lz2_pct,
            if (lz2_match) "PASS" else "FAIL",
            lz1_comp.len,
            lz1_pct,
            if (lz1_match) "PASS" else "FAIL",
        });

        if (!lz2_match or !lz1_match) return error.VerificationFailed;
    }

    std.debug.print("\nAll compression levels (0-9) verified and matched 100% successfully!\n", .{});
}
```

---

## Expected Output

```text
LZMA & LZMA2 Compression Presets & Levels Verification (Levels 0 through 9)
Input data size: 762 bytes

Level    | LZMA2 Size (Ratio) | LZMA2 Verify | Alone Size (Ratio) | Alone Verify
Level 0  |  766 B (100.5%)    | PASS         |  416 B (54.6%)    | PASS      
Level 1  |  405 B (53.1%)    | PASS         |  411 B (53.9%)    | PASS      
Level 2  |  405 B (53.1%)    | PASS         |  411 B (53.9%)    | PASS      
Level 3  |  405 B (53.1%)    | PASS         |  411 B (53.9%)    | PASS      
Level 4  |  398 B (52.2%)    | PASS         |  404 B (53.0%)    | PASS      
Level 5  |  398 B (52.2%)    | PASS         |  404 B (53.0%)    | PASS      
Level 6  |  398 B (52.2%)    | PASS         |  404 B (53.0%)    | PASS      
Level 7  |  398 B (52.2%)    | PASS         |  404 B (53.0%)    | PASS      
Level 8  |  398 B (52.2%)    | PASS         |  404 B (53.0%)    | PASS      
Level 9  |  398 B (52.2%)    | PASS         |  404 B (53.0%)    | PASS      

All compression levels (0-9) verified and matched 100% successfully!
```

---

## How to Run

```bash
zig build run-compression_levels
```
