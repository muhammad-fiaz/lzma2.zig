# Security Policy

## Supported Versions

| Version | Supported          |
| :---    | :---               |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

Because compression libraries frequently process untrusted input from network sockets, archives, and external storage, all decoders and parsers in `lzma2.zig` are designed to fail safely rather than crash, leak memory, or execute out-of-bounds operations.

**Please do NOT report security vulnerabilities through public GitHub issues or discussions.**

If you discover a security vulnerability, memory safety bug, buffer overrun, decompression bomb vector, or denial-of-service issue (such as an unhandled panic, integer overflow, or infinite loop on malformed input), please report it privately:

- **Email**: [contact@muhammadfiaz.com](mailto:contact@muhammadfiaz.com)
- **Subject**: `[SECURITY] lzma2.zig Vulnerability Report`

Please include in your report:
1. A clear description of the vulnerability and its potential impact.
2. A minimal reproducible example or test payload (e.g., malformed LZMA2 stream).
3. The affected version of `lzma2.zig`, Zig compiler version, and target architecture / OS.
4. Any proposed patches or mitigations if available.

Reports will be reviewed and investigated by the maintainers. Confirmed vulnerabilities and fixes will be coordinated and published through GitHub Security Advisories and release notes.

## Resource Exhaustion & Decompression Bombs

LZMA2 achieves high compression ratios (often exceeding 1,000:1 on repetitive inputs). Hostile payloads ("decompression bombs") can cause excessive CPU and memory consumption if processed without limits.

When handling untrusted data:
- **Configure `max_output_size`**: Specify `DecompressOptions.max_output_size` to enforce an upper bound on decompressed byte count. If decompression exceeds this threshold, the operation terminates immediately with `error.ExceededSizeLimit`.
- **Configure `dict_size_limit`**: Restrict the maximum permitted dictionary size to limit memory consumption by the decompressor.
- **Use Caller-Provided Buffers**: For constrained or embedded environments, use `decompressInto` or `lzma.decompressInto` with fixed-size destination slices. If the output exceeds buffer capacity, the function returns `error.OutputTooSmall` without allocating heap memory.

## Format Validation vs. Security Guarantees

The decoder strictly validates format integrity:
- Chunk control bytes (`0x00`..`0xFF`), reset flags, and chunk lengths are checked on every chunk.
- Invalid control bytes return `error.InvalidControlByte`.
- Corrupt range-coded bitstreams return `error.CorruptData`.
- Legacy `.lzma` headers are validated for permissible property ranges (`lc + lp <= 8`, `pb <= 4`, valid dictionary size).

However, binary format validation alone cannot verify the semantic safety of decompressed content or prevent application-level denial of service. Applications must enforce appropriate output size limits and resource bounds when decompressing untrusted inputs.
