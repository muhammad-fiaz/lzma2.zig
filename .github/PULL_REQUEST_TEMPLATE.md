## Summary

Please provide a concise summary of the changes made and reference any related issues (e.g., `Fixes #12`).

## Motivation & Context

Why is this change required? What problem does it solve or what feature does it implement?

## Implementation Details

- Describe key algorithmic changes, data structures, or protocol modifications.
- Note any changes to the public API surface or memory management contracts.

## Validation & Testing

- [ ] Code follows project formatting standards (`zig fmt --check src examples build.zig build.zig.zon`)
- [ ] Complete unit and integration test suite passes (`zig build test --summary all`)
- [ ] Compilation check passes for library, tests, and examples (`zig build check`)
- [ ] All examples compile and execute successfully (`zig build run-all-examples`)
- [ ] Interoperability verified against upstream reference tools (`xz` / 7-Zip) if applicable
- [ ] Documentation updated or builds cleanly (`bun run docs:build` in `docs/`)

## Compatibility & API Impact

- Does this change introduce breaking API modifications? If so, describe migration path.
- Are there any outstanding limitations or performance considerations?
