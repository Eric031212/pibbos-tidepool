#!/usr/bin/env python3
"""Generate Pibbo's placeholder sprite sheet, manifest, and previews.

Placeholder art only. Final art is drawn by hand in Aseprite and must keep
the same sheet layout (see manifest.json).

Usage:
    python3 Tools/generate_placeholder_sprites.py [output_dir]

Default output_dir: Assets/Placeholder/pibbo
Requires: Pillow
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SIZE = 16  # frame size in pixels
WATER_TOP = 13  # first water row inside a frame

PALETTE = {
    "o": (62, 42, 31),     # outline
    "b": (140, 90, 60),    # fur
    "d": (110, 69, 48),    # dark fur / eyelid
    "l": (233, 210, 176),  # cream face
    "e": (42, 27, 18),     # eye
    "n": (42, 27, 18),     # nose
    "c": (232, 160, 160),  # cheek
    "p": (90, 58, 40),     # paw
    "s": (244, 199, 184),  # shell
    "S": (217, 150, 127),  # shell ridge
    "h": (108, 123, 168),  # headphone band
    "H": (74, 86, 128),    # headphone cup
    "m": (245, 214, 110),  # music note
    "k": (94, 156, 82),    # kelp
    "K": (63, 122, 58),    # dark kelp
    "z": (159, 179, 217),  # zzz
    "u": (207, 234, 247),  # bubble
    "w": (111, 183, 217),  # water
    "W": (191, 230, 245),  # foam
    "x": (76, 147, 189),   # deep water
}

# Left half of Pibbo's base pose (columns 0-7); mirrored to columns 8-15.
BASE_HALF = [
    "........",  # 0
    "....oooo",  # 1  top of head
    "...obbbb",  # 2
    ".dobbbbb",  # 3  ear nubs
    "..obbbbb",  # 4  eyes
    "..obblln",  # 5  muzzle + nose
    "..obclll",  # 6  cheek
    "...oblll",  # 7  chin
    "...obbbb",  # 8  neck
    "..obbbbb",  # 9
    "..obppss",  # 10 paws + shell
    "..obbpSs",  # 11
    "..obbbbb",  # 12
    "..obbbbb",  # 13 (under water)
    "..obbbbb",  # 14
    "...ooooo",  # 15
]


def mirror(half_rows):
    return [list(r + r[::-1]) for r in half_rows]


def base():
    return mirror(BASE_HALF)


def put(grid, points, ch):
    for r, c in points:
        if 0 <= r < SIZE and 0 <= c < SIZE:
            grid[r][c] = ch


def eyes(grid, style):
    """style: 'lazy' (half-closed), 'open', 'closed'."""
    if style == "lazy":
        put(grid, [(3, 4), (3, 5), (3, 10), (3, 11)], "d")
        put(grid, [(4, 4), (4, 5), (4, 10), (4, 11)], "e")
    elif style == "open":
        put(grid, [(3, 5), (4, 5), (3, 10), (4, 10)], "e")
    elif style == "closed":
        put(grid, [(4, 4), (3, 5), (3, 10), (4, 11)], "e")


def remove_shell(grid):
    for c in (6, 7, 8, 9):
        grid[10][c] = "b"
        grid[11][c] = "p" if c in (6, 9) else "b"


def shift(grid, dy):
    """Move the otter down by dy rows (content above becomes empty)."""
    empty = [["."] * SIZE for _ in range(dy)]
    return empty + grid[: SIZE - dy] if dy > 0 else grid


def water(grid, phase):
    for c in range(SIZE):
        grid[13][c] = "W" if (c + phase) % 5 == 0 else "w"
        grid[14][c] = "w"
        grid[15][c] = "x" if (c + phase) % 3 else "w"
    return grid


def headphones(grid):
    put(grid, [(0, c) for c in range(4, 12)], "h")
    put(grid, [(1, 3), (1, 12), (2, 2), (2, 13)], "h")
    put(grid, [(r, c) for r in (3, 4, 5) for c in (0, 1, 14, 15)], "H")


def kelp(grid):
    put(grid, [(9, 2), (9, 3), (10, 4), (10, 5), (10, 6), (11, 7), (11, 8),
               (11, 9), (12, 10), (12, 11), (12, 12)], "k")
    put(grid, [(9, 4), (12, 13)], "K")


def blank():
    return [["."] * SIZE for _ in range(SIZE)]


# ---------------------------------------------------------------- states

def frame_hidden(i):
    g = base()
    eyes(g, "lazy")
    g = shift(g, 8 + (i % 2))  # only eyes and head top above water
    return water(g, i)


def frame_peek(i):
    g = base()
    eyes(g, "lazy" if i == 2 else "open")  # frame 2 is a slow blink
    g = shift(g, [5, 5, 6, 5][i])
    return water(g, i)


def frame_chill(i):
    g = base()
    eyes(g, "lazy")
    g = shift(g, [0, 0, 1, 1][i])
    return water(g, i // 2)


def frame_music(i):
    g = base()
    eyes(g, "closed")
    headphones(g)
    g = shift(g, [0, 1, 0, 1][i])
    note = [(1, 14), (2, 14), (1, 15)] if i < 2 else [(0, 15), (1, 15), (0, 14)]
    put(g, note, "m")
    return water(g, i)


def frame_sleep(i):
    g = base()
    eyes(g, "closed")
    remove_shell(g)
    kelp(g)
    g = shift(g, i)
    if i == 0:
        put(g, [(0, 13), (0, 14), (1, 14), (2, 14), (2, 15)], "z")
    else:
        put(g, [(1, 14), (1, 15), (2, 15)], "z")
    g = water(g, i)
    put(g, [(13, 2), (14, 1), (15, 2), (13, 14), (14, 15), (15, 14)], "K")
    return g


def frame_submerged(i):
    g = water(blank(), i)
    put(g, [(14, c) for c in range(5, 11)], "x")  # shadow under water
    bubbles = [
        [(12, 7)],
        [(11, 7), (12, 9)],
        [(10, 8), (11, 9)],
        [(12, 6)],
    ][i]
    put(g, bubbles, "u")
    return g


# name -> (frame function, frame count, fps). Row order = sheet row order.
STATES = {
    "hidden": (frame_hidden, 2, 2),
    "peek": (frame_peek, 4, 6),
    "chill": (frame_chill, 4, 4),
    "music": (frame_music, 4, 6),
    "sleep": (frame_sleep, 2, 1),
}
ACTIONS = {
    "submerged": (frame_submerged, 4, 2),  # work mode
}


def to_image(grid):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    px = img.load()
    for r in range(SIZE):
        for c in range(SIZE):
            ch = grid[r][c]
            if ch in PALETTE:
                px[c, r] = PALETTE[ch] + (255,)
    return img


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "Assets/Placeholder/pibbo")
    out.mkdir(parents=True, exist_ok=True)

    entries = list(STATES.items()) + list(ACTIONS.items())
    max_frames = max(n for _, n, _ in [v for _, v in entries])
    sheet = Image.new("RGBA", (SIZE * max_frames, SIZE * len(entries)), (0, 0, 0, 0))
    frames = {}
    for row, (name, (fn, n, fps)) in enumerate(entries):
        frames[name] = [to_image(fn(i)) for i in range(n)]
        for i, f in enumerate(frames[name]):
            sheet.paste(f, (i * SIZE, row * SIZE))
    sheet.save(out / "sprites.png")

    manifest = {
        "id": "com.tidepool.pibbo.placeholder",
        "name": "pibbo (placeholder)",
        "author": "tidepool",
        "version": "0.1.0",
        "type": "skin",
        "frameSize": SIZE,
        "states": {},
        "actions": {},
    }
    for row, (name, (_, n, fps)) in enumerate(entries):
        key = "states" if name in STATES else "actions"
        manifest[key][name] = {"row": row, "frames": n, "fps": fps}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    # Animated preview: all states side by side at 8x, 2-second loop.
    scale, pad, label_h = 8, 16, 28
    cell = SIZE * scale
    width = len(entries) * (cell + pad) + pad
    height = cell + label_h + pad * 2
    try:
        font = ImageFont.load_default(size=14)
    except TypeError:
        font = ImageFont.load_default()
    tick = 1 / 12
    gif_frames = []
    for t in range(24):
        canvas = Image.new("RGBA", (width, height), (247, 242, 232, 255))
        d = ImageDraw.Draw(canvas)
        for k, (name, (_, n, fps)) in enumerate(entries):
            idx = int(t * tick * fps) % n
            sprite = frames[name][idx].resize((cell, cell), Image.NEAREST)
            x = pad + k * (cell + pad)
            canvas.alpha_composite(sprite, (x, pad))
            tw = d.textlength(name, font=font)
            d.text((x + (cell - tw) / 2, pad + cell + 8), name, fill=(90, 70, 55), font=font)
        gif_frames.append(canvas.convert("RGB"))
    gif_frames[0].save(out / "preview.gif", save_all=True, append_images=gif_frames[1:],
                       duration=int(tick * 1000), loop=0)
    sheet.resize((sheet.width * 8, sheet.height * 8), Image.NEAREST).save(out / "sprites@8x.png")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
