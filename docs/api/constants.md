# Constants

The `lzma2` package exposes constants governing chunk sizes, dictionary boundaries, and versioning.

---

## Chunk & Dictionary Limits

| Constant | Value | Description |
|---|---|---|
| `CHUNK_UNPACK_MAX` | `2097152` (2 MiB) | Maximum uncompressed payload per LZMA2 chunk |
| `CHUNK_PACK_MAX` | `65536` (64 KiB) | Maximum compressed payload per LZMA2 chunk |
| `MIN_DICT_SIZE` | `4096` (4 KiB) | Minimum supported dictionary size |
| `DEFAULT_DICT_SIZE` | `8388608` (8 MiB) | Default dictionary size for compression & decompression |
| `MAX_DICT_SIZE` | `268435456` (256 MiB) | Maximum supported dictionary size |

---

## Control Bytes

| Constant | Value | Description |
|---|---|---|
| `CONTROL_EOS` | `0x00` | End-of-stream indicator byte |
| `CONTROL_UNCOMPRESSED_RESET_DICT` | `0x01` | Uncompressed copy chunk with dictionary reset |
| `CONTROL_UNCOMPRESSED_NO_RESET` | `0x02` | Uncompressed copy chunk without dictionary reset |
| `CONTROL_LZMA_MIN` | `0x80` | Minimum control byte value for compressed LZMA chunk |

---

## Package Information

| Constant | Value | Description |
|---|---|---|
| `version` | `"0.1.0"` | Library version string |
