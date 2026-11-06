#!/usr/bin/env python3
"""Generate src/piece_bitmaps.inc: 16x16 1-bit piece bitmaps from assets/*.bmp.

Sources are Windows BMP v3 files, 60x60 px, 24-bit BGR, uncompressed,
bottom-up rows, pixel data at offset 54. The background key in these assets
is magenta (R=0xFF, G=0x00, B=0xFF) — verified per file, not pure blue.

Downsampling 60->16: each target pixel takes a majority vote over its
aligned source window (boundaries floor(t*60/16) .. floor((t+1)*60/16),
i.e. 3-4 source px per axis). A source pixel is background if its BGR is
within tolerance of the magenta key (R>=0xF0, G<=0x60, B>=0xF0); a tie in
the vote counts as foreground. Output is row-major, 16 rows x 2 bytes,
bit 7 of the first byte = leftmost pixel.

Piece order matches piece_name_ptrs in src/data.asm:
wP wN wB wR wQ wK bP bN bB bR bQ bK.
"""
import struct
import sys
from pathlib import Path

SRC_SIZE = 60
DST_SIZE = 16
BYTES_PER_ROW = DST_SIZE // 8

# Background key tolerance: magenta FF00FF within slack.
BG_R_MIN = 0xF0
BG_G_MAX = 0x60
BG_B_MIN = 0xF0

PIECES = ["wP", "wN", "wB", "wR", "wQ", "wK",
          "bP", "bN", "bB", "bR", "bQ", "bK"]

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = REPO_ROOT / "src" / "piece_bitmaps.inc"


def load_bmp(path):
    """Parse a BMP v3 24-bit uncompressed file into (width, height, rows).

    Returns rows top-to-bottom, each row a list of (r, g, b) tuples.
    """
    data = path.read_bytes()
    if data[:2] != b"BM":
        raise ValueError(f"{path}: not a BMP file")
    _, _, _, data_off = struct.unpack_from("<2sIII", data, 0)
    hdr_size, w, h, planes, bpp, comp = struct.unpack_from("<IiiHHI", data, 14)
    if hdr_size != 40 or bpp != 24 or comp != 0 or planes != 1:
        raise ValueError(f"{path}: expected BMP v3 24-bit uncompressed")
    if w <= 0 or h == 0:
        raise ValueError(f"{path}: bad dimensions {w}x{h}")
    row_stride = (w * 3 + 3) & ~3
    bottom_up = h > 0
    h = abs(h)
    if len(data) < data_off + row_stride * h:
        raise ValueError(f"{path}: truncated pixel data")
    rows = []
    for y in range(h):
        fy = h - 1 - y if bottom_up else y
        base = data_off + fy * row_stride
        row = []
        for x in range(w):
            b, g, r = data[base + x * 3: base + x * 3 + 3]
            row.append((r, g, b))
        rows.append(row)
    return w, h, rows


def is_background(px):
    r, g, b = px
    return r >= BG_R_MIN and g <= BG_G_MAX and b >= BG_B_MIN


def downsample(rows):
    """Majority-vote 60x60 -> 16x16 mask; returns rows of 0/1 top-to-bottom."""
    mask = []
    for ty in range(DST_SIZE):
        y0 = ty * SRC_SIZE // DST_SIZE
        y1 = (ty + 1) * SRC_SIZE // DST_SIZE
        out_row = []
        for tx in range(DST_SIZE):
            x0 = tx * SRC_SIZE // DST_SIZE
            x1 = (tx + 1) * SRC_SIZE // DST_SIZE
            fg = sum(
                1
                for y in range(y0, y1)
                for x in range(x0, x1)
                if not is_background(rows[y][x])
            )
            total = (y1 - y0) * (x1 - x0)
            out_row.append(1 if 2 * fg >= total else 0)
        mask.append(out_row)
    return mask


def mask_to_bytes(mask):
    out = bytearray()
    for row in mask:
        for byte_idx in range(BYTES_PER_ROW):
            val = 0
            for bit in range(8):
                if row[byte_idx * 8 + bit]:
                    val |= 0x80 >> bit
            out.append(val)
    return bytes(out)


def ascii_art(mask):
    return "\n".join("".join("#" if p else "." for p in row) for row in mask)


def main():
    blocks = []
    previews = []
    for name in PIECES:
        _, _, rows = load_bmp(REPO_ROOT / "assets" / f"{name}.bmp")
        if len(rows) != SRC_SIZE or len(rows[0]) != SRC_SIZE:
            raise ValueError(f"{name}.bmp: expected {SRC_SIZE}x{SRC_SIZE}")
        mask = downsample(rows)
        raw = mask_to_bytes(mask)
        lines = [f"    ; {name}"]
        for row_idx in range(DST_SIZE):
            row_bytes = raw[row_idx * BYTES_PER_ROW:(row_idx + 1) * BYTES_PER_ROW]
            hexed = ",".join(f"0x{b:02X}" for b in row_bytes)
            lines.append(f"    db {hexed} ; {name} row {row_idx}")
        blocks.append("\n".join(lines))
        previews.append(f"{name}:\n{ascii_art(mask)}")

    inc = (
        "piece_bitmaps:\n"
        + "\n".join(blocks)
        + "\npiece_bitmaps_end:\n"
        + "piece_bitmaps_size equ piece_bitmaps_end - piece_bitmaps\n"
    )
    OUT_PATH.write_text(inc)

    preview_path = Path("/tmp/piece_preview.txt")
    preview_path.write_text("\n\n".join(previews) + "\n")

    print(f"wrote {OUT_PATH} ({len(inc)} bytes, {len(PIECES) * DST_SIZE * BYTES_PER_ROW} data bytes)")
    print(f"wrote {preview_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
