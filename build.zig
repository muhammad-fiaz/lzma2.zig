const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // LZMA module export: @import("lzma")
    const lzma_mod = b.addModule("lzma", .{
        .root_source_file = b.path("src/lzma.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
    });

    // LZMA2 module export: @import("lzma2")
    const lzma2_mod = b.addModule("lzma2", .{
        .root_source_file = b.path("src/lzma2.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
        .imports = &.{
            .{ .name = "lzma", .module = lzma_mod },
        },
    });

    // Static library artifact
    const lib = b.addLibrary(.{
        .name = "lzma2",
        .root_module = lzma2_mod,
    });
    b.installArtifact(lib);

    // Main test suites
    const test_step = b.step("test", "Run all tests");
    const lzma2_tests = b.addTest(.{
        .root_module = lzma2_mod,
    });
    const run_lzma2_tests = b.addRunArtifact(lzma2_tests);
    test_step.dependOn(&run_lzma2_tests.step);

    const lzma_tests = b.addTest(.{
        .root_module = lzma_mod,
    });
    const run_lzma_tests = b.addRunArtifact(lzma_tests);
    test_step.dependOn(&run_lzma_tests.step);

    // Fuzz testing step (`zig build fuzz`)
    const fuzz_step = b.step("fuzz", "Run fuzz and edge-case validation suite");
    fuzz_step.dependOn(&run_lzma2_tests.step);
    fuzz_step.dependOn(&run_lzma_tests.step);

    // Documentation generation step (`zig build docs`)
    const docs_step = b.step("docs", "Generate documentation");
    const docs = b.addTest(.{
        .root_module = lzma2_mod,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);

    // Standalone examples
    const examples = [_]struct { name: []const u8, file: []const u8 }{
        .{ .name = "basic_compression", .file = "examples/basic_compression.zig" },
        .{ .name = "caller_buffer", .file = "examples/caller_buffer.zig" },
        .{ .name = "configured_compression", .file = "examples/configured_compression.zig" },
        .{ .name = "reusable_context", .file = "examples/reusable_context.zig" },
        .{ .name = "error_handling", .file = "examples/error_handling.zig" },
        .{ .name = "lzma_compression", .file = "examples/lzma_compression.zig" },
        .{ .name = "compression_levels", .file = "examples/compression_levels.zig" },
    };

    const run_all = b.step("run-all-examples", "Run all examples");
    const check_step = b.step("check", "Check compilation of library, tests, and examples");
    check_step.dependOn(&lib.step);
    check_step.dependOn(&lzma2_tests.step);
    check_step.dependOn(&lzma_tests.step);

    inline for (examples) |example| {
        const run_step = b.step(
            "run-" ++ example.name,
            "Run " ++ example.name ++ " example",
        );

        const exe = b.addExecutable(.{
            .name = "example-" ++ example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.file),
                .target = target,
                .optimize = optimize,
                .link_libc = false,
                .imports = &.{
                    .{ .name = "lzma2", .module = lzma2_mod },
                    .{ .name = "lzma", .module = lzma_mod },
                },
            }),
        });

        check_step.dependOn(&exe.step);
        const run_exe = b.addRunArtifact(exe);
        run_step.dependOn(&run_exe.step);
        run_all.dependOn(&run_exe.step);
        run_exe.step.dependOn(&lib.step);
    }
}
