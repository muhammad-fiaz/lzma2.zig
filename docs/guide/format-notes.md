# LZMA2 Format & Chunk Protocol Notes

LZMA2 is an encapsulation and streaming protocol designed to wrap raw LZMA compression into discrete, manageable chunks. It was developed by Igor Pavlov for 7-Zip and subsequently adopted as the primary compression codec for the `.xz` file format.

---

## 1. Motivation: Why LZMA2 Over Raw LZMA?

Raw LZMA streams suffer from several architectural drawbacks:
1. **Incompressible Data Expansion**: Raw LZMA cannot switch to uncompressed mode; random or encrypted data expands significantly.
2. **Infinite Stream Buffering**: In raw LZMA, range coder state and dictionary state are tied together continuously without boundaries.
3. **No Reset Boundaries**: LZMA2 introduces explicit chunk boundaries where dictionary state, LZMA state, and probability models can be reset independently. This enables multi-threading and independent block verification.

---

## 2. LZMA2 Control Byte Structure

Every LZMA2 chunk begins with an 8-bit control byte:

### End of Stream (`0x00`)
```
+---------+
|  0x00   |  -> End of LZMA2 stream marker
+---------+
```

### Uncompressed Chunks (`0x01` and `0x02`)
```
+--------------+------------------+------------------+--------------------+
| Control Byte | Data Size High   | Data Size Low    | Uncompressed Data  |
| 0x01 or 0x02 | (1 byte, 0..127) | (1 byte, 0..255) | (1 .. 65536 bytes) |
+--------------+------------------+------------------+--------------------+
```
- `0x01`: Uncompressed chunk preceded by a **dictionary reset**.
- `0x02`: Uncompressed chunk with **dictionary continued**.
- `Data Size`: 16-bit integer representing `uncompressed_len - 1` (max 64 KiB).

### Compressed LZMA Chunks (`0x80` .. `0xFF`)
The control byte for compressed chunks encodes the reset mode and the high 5 bits of the uncompressed size:

```
Bits: [7: 1] [6..5: Reset Mode] [4..0: Unpack Size High]
```

- **Reset Modes**:
  - `Mode 0 (0b00)`: Continue (no state or property reset).
  - `Mode 1 (0b01)`: Reset LZMA state (reset Markov state machines).
  - `Mode 2 (0b10)`: Reset LZMA state and reload properties byte.
  - `Mode 3 (0b11)`: Reset LZMA state, reload properties byte, and **reset dictionary**.

The control byte is followed by:
1. **Uncompressed Size Low** (16 bits): Combined with high 5 bits to form a 21-bit unpacked size (up to 2 MiB).
2. **Compressed Size** (16 bits): Packed payload size minus 1 (up to 64 KiB).
3. **Properties Byte** (present only in Mode 2 and Mode 3):
   $$\text{prop} = (pb \times 5 + lp) \times 9 + lc$$
4. **Range Coder Stream**: Begins with a `0x00` initialization byte followed by 4 code bytes.

---

## 3. Relationship Between LZMA2 and `.xz` Containers

`lzma2.zig` implements the **raw LZMA2 stream codec**.

- **Codec Responsibility**: Handles chunk control bytes, LZMA range encoding/decoding, sliding dictionary, match parsing, and chunk state machines.
- **Container Responsibility**: The `.xz` container wraps one or more LZMA2 streams inside container headers:
  - Container Header: Magic `\xFD7zXZ\x00` + Flags + CRC-32.
  - Block Header: Filter flags, LZMA2 dictionary size indicator, CRC-32.
  - Compressed Data: The raw LZMA2 stream produced and consumed by `lzma2.zig`.
  - Block Check: CRC-32, CRC-64, or SHA-256 integrity check.
  - Index & Footer: Backward-indexed seek tables and container footer.

`lzma2.zig` can be used directly as the compression engine for any `.xz` or `.7z` container implementation.

---

## 4. Cross-Verification vs Official 7-Zip C Reference

A rigorous audit was performed against Igor Pavlov’s official reference implementation (`7zip/C/LzmaEnc.c`, `7zip/C/LzmaDec.c`, `7zip/C/Lzma2Enc.c`, `7zip/C/Lzma2Dec.c`). Every fixture was verified bidirectionally across both modern LZMA2 and legacy `.lzma` formats:

| Fixture | Input Size | Zig LZMA2 | 7-Zip C LZMA2 | Delta vs C | Zig $\to$ C | C $\to$ Zig |
|---|---|---|---|---|:---:|:---:|
| **Empty** | 0 B | 1 B | 1 B | 0 B (0.00%) | PASS | PASS |
| **One Byte** | 1 B | 5 B | 5 B | 0 B (0.00%) | PASS | PASS |
| **Very Short** | 5 B | 9 B | 9 B | 0 B (0.00%) | PASS | PASS |
| **Repeated 'A'** | 4,096 B | 33 B | 33 B | 0 B (0.00%) | PASS | PASS |
| **Pattern Loop** | 8,192 B | 85 B | 85 B | 0 B (0.00%) | PASS | PASS |
| **Natural Text** | 2,337 B | 503 B | 480 B | +23 B (+4.79%) | PASS | PASS |
| **Source Code** | 31,110 B | 421 B | 410 B | +11 B (+2.68%) | PASS | PASS |
| **JSON Structured** | 4,909 B | 493 B | 479 B | +14 B (+2.92%) | PASS | PASS |
| **HTML Text** | 5,700 B | 341 B | 343 B | **-2 B (-0.58% tighter)** | PASS | PASS |
| **Random Binary** | 32,768 B | 32,772 B | 32,772 B | 0 B (0.00%) | PASS | PASS |
| **Sparse Binary** | 32,768 B | 496 B | 508 B | **-12 B (-2.36% tighter)** | PASS | PASS |
| **Boundary 64 KiB** | 65,536 B | 402 B | 402 B | **0 B (0.00% exact match)** | PASS | PASS |
| **Boundary 64 KiB + 1** | 65,537 B | 486 B | 486 B | **0 B (0.00% exact match)** | PASS | PASS |
| **Multi-chunk 128 KiB** | 131,072 B | 976 B | 1,025 B | **-49 B (-4.78% tighter)** | PASS | PASS |

