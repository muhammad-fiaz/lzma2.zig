# Contributing to lzma2.zig
 
Thank you for your interest in contributing to `lzma2.zig`! We welcome bug reports, documentation improvements, optimization ideas, and pull requests.
 
## Code of Conduct
 
Please be respectful and constructive in all issues, pull requests, and discussions, following the [Code of Conduct](CODE_OF_CONDUCT.md).
 
## Tooling & Prerequisites
 
### Mandatory Tooling
- **Zig 0.17.0**: Required compiler toolchain. Download from [ziglang.org/download](https://ziglang.org/download/).
 
### Optional Development Tooling
- **Bun** (or Node.js): Required only for building the VitePress documentation site locally (`docs/`).
- **7-Zip (`7z`) & XZ Utils (`xz`)**: Optional CLI tools for development-time differential testing and external oracle verification. Neither is required to build or test the native library.
- **QEMU**: Optional emulator (`qemu-arm`, `qemu-aarch64`, `qemu-riscv32`) for running non-native cross-compiled test suites locally.
 
## Development Workflow
 
Run the standard validation workflows before submitting changes:
 
```bash
# 1. Format all Zig source files
zig fmt src/ examples/ build.zig build.zig.zon
 
# 2. Check formatting without modifying files
zig fmt --check src/ examples/ build.zig build.zig.zon
 
# 3. Build the static library and verify compilation
zig build
zig build check
 
# 4. Run all unit and integration tests
zig build test --summary all
 
# 5. Run fuzz testing and edge-case validation
zig build fuzz
 
# 6. Run all standalone examples
zig build run-all-examples
 
# 7. Run an individual example
zig build run-basic_compression
zig build run-caller_buffer
zig build run-configured_compression
zig build run-reusable_context
zig build run-error_handling
zig build run-lzma_compression
zig build run-compression_levels
 
# 8. Build the VitePress documentation site (optional)
cd docs
bun install
bun run build
cd ..
```
 
## Adding Regression Tests
 
When fixing a bug or adding format support:
1. Add a targeted test case in the relevant module:
   - For LZMA2 chunking or high-level API: [`src/lzma2.zig`](src/lzma2.zig)
   - For legacy `.lzma` container or raw LZMA: [`src/lzma.zig`](src/lzma.zig)
   - For range codec operations: [`src/utils/range_codec.zig`](src/utils/range_codec.zig)
   - For match finder behaviors: [`src/utils/match_finder.zig`](src/utils/match_finder.zig)
2. Include both valid round-trip tests and malformed/truncated input tests to ensure graceful error return.
3. Verify that tests pass across both `Debug` and `ReleaseSafe` optimization modes.
 
## Coding Conventions
 
1. **Zero External Runtime Dependencies**: Pure native Zig. Do not introduce `@cImport`, link libc, or depend on external compression libraries.
2. **Memory Safety & Allocator Ownership**: Follow Zig standard library idioms. Functions that allocate must accept an explicit `std.mem.Allocator`. Caller-buffer zero-allocation APIs (`compressInto` / `decompressInto`) must be provided alongside allocating ones.
3. **No Decorative Comment Blocks**: Do not use separator lines of repeated `=======` or `-------` in comments. Use normal descriptive doc comments (`///`) on public symbols and concise technical comments for internal algorithms.
4. **Documentation Accuracy**: Every change to public API signatures or options must be updated in `docs/` and verified with `bun run build`.
 
## Reporting Vulnerabilities
 
Do not report security vulnerabilities via public GitHub issues. Follow the private reporting process detailed in [SECURITY.md](SECURITY.md).
