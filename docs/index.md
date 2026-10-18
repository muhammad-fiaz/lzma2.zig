---
layout: home
title: Native LZMA2 Compression & Decompression Library for Zig
titleTemplate: ":title | lzma2.zig"
description: Type-safe, memory-conscious, native Zig implementation of modern LZMA2 and legacy LZMA compression codecs targeting Zig 0.17.0. High-ratio dictionary encoding, zero external C dependencies, caller-provided buffers, and reusable contexts.
keywords: native lzma2 compression and decompression library for zig, zig lzma2, pure zig compression, 7-zip lzma2, xz lzma2, zig 0.17.0, zero dependencies

hero:
  name: "lzma2.zig"
  text: "Native LZMA2 Compression for Zig"
  tagline: "Native Zig LZMA2 and LZMA compression library."
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: API Reference
      link: /api/
    - theme: alt
      text: Examples
      link: /examples/
    - theme: alt
      text: View on GitHub
      link: https://github.com/muhammad-fiaz/lzma2.zig

features:
  - icon: ⚡
    title: Pure Native Zig (0.17.0)
    details: Engineered from first principles in native Zig without `@cImport`, C compiler requirements, or external runtime dependencies.
  - icon: 🗜️
    title: Dual LZMA2 & LZMA Support
    details: Modern LZMA2 chunk protocol (`lzma2.compress`), legacy `.lzma` 13-byte header files (`lzma.compress`), and raw continuous LZMA streams (`lzma.compressRaw`).
  - icon: 📦
    title: Real LZMA2 Chunk Protocol
    details: Implements the true LZMA2 stream format supporting uncompressed copy chunks (`0x01`/`0x02`), LZMA chunks, all 4 reset modes, and end-of-stream control bytes.
  - icon: 🌊
    title: First-Class Streaming I/O
    details: Incremental chunk-by-chunk and reader/writer streaming pipelines (`compressStream`, `decompressStream`, `compressStreamAlone`) with bounded memory.
  - icon: 🛡️
    title: Defensive & Bomb-Proof
    details: Strict bounds checking, safe handling of corrupted bitstreams, and configurable `max_output_size` guards against decompression bomb attacks.
  - icon: 🔄
    title: Context Reuse & Zero Heap Allocations
    details: Stateful `Compressor` and `Decompressor` contexts eliminate buffer allocation churn; caller-buffer APIs (`compressInto`, `decompressInto`) operate with zero heap overhead.
  - icon: ⚙️
    title: Presets & Configurable Dictionaries
    details: Standard presets (`.fastest`, `.fast`, `.normal`, `.maximum`) and fine-grained controls for dictionary sizes up to 1 GiB and literal context bits.
---

## Installation

Add `lzma2.zig` to your project using `zig fetch`:

```bash
zig fetch --save git+https://github.com/muhammad-fiaz/lzma2.zig.git
```

Then expose the module in your `build.zig`:

```zig
const lzma2_dep = b.dependency("lzma2", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("lzma2", lzma2_dep.module("lzma2"));
```

## Quick Example

Compress and decompress data in just a few lines of idiomatic Zig:

```zig
const std = @import("std");
const lzma2 = @import("lzma2");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const payload = "Native LZMA2 compression in pure Zig 0.17.0! High-ratio dictionary encoding.";

    // One-shot heap compression
    const compressed = try lzma2.compress(allocator, payload, .{});
    defer allocator.free(compressed);

    // One-shot heap decompression
    const restored = try lzma2.decompress(allocator, compressed, .{});
    defer allocator.free(restored);

    std.debug.print("Original size:   {d} bytes\n", .{payload.len});
    std.debug.print("Compressed size: {d} bytes\n", .{compressed.len});
    std.debug.print("Restored:        {s}\n", .{restored});
}
```
