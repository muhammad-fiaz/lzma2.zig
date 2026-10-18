# Installation & Build Integration

`lzma2.zig` is packaged as a standard Zig package designed for **Zig 0.17.0 or later**. It has zero C dependencies and requires no system libraries.

---

## 1. Requirements

- **Zig Compiler**: Version `0.17.0 or later` (required).
- **Supported Operating Systems**: Linux, Windows, macOS, FreeBSD, NetBSD, and bare-metal targets supported by Zig.

---

## 2. Adding to `build.zig.zon`

You can fetch and record the package dependency automatically with `zig fetch`. The recommended method is to pin to the latest tagged release:

```bash
# Recommended: Latest tagged release (0.0.1)
zig fetch --save https://github.com/muhammad-fiaz/lzma2.zig/archive/refs/tags/0.0.1.tar.gz

# Alternative: Latest development build (main branch)
zig fetch --save git+https://github.com/muhammad-fiaz/lzma2.zig.git
```

Alternatively, you can manually add `lzma2` to your `build.zig.zon`:

```zig
.{
    .name = .my_app,
    .version = "0.1.0",
    .dependencies = .{
        .lzma2 = .{
            .url = "https://github.com/muhammad-fiaz/lzma2.zig/archive/refs/tags/0.0.1.tar.gz",
            .hash = "...", // populated automatically by zig fetch
        },
    },
    .paths = .{ "" },
}
```

---

## 3. Exposing the Module in `build.zig`

In your consumer `build.zig`, import the dependency and add it to your root module:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Resolve lzma2 dependency
    const lzma2_dep = b.dependency("lzma2", .{
        .target = target,
        .optimize = optimize,
    });

    // 2. Create your executable or library
    const exe = b.addExecutable(.{
        .name = "my_app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // 3. Add lzma2 import
    exe.root_module.addImport("lzma2", lzma2_dep.module("lzma2"));

    b.installArtifact(exe);
}
```

---

## 4. Importing in Source Code

Once wired into your build configuration, import `lzma2` in your source files:

```zig
const std = @import("std");
const lzma2 = @import("lzma2");

pub fn main() !void {
    const data = "Test string for compression";
    const compressed = try lzma2.compress(std.heap.page_allocator, data, .{});
    defer std.heap.page_allocator.free(compressed);
}
```
