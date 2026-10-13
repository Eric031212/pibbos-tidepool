#!/usr/bin/env python3
"""Generate all of Tidepool's pixel art from text pixel grids.

This is the real art (decided 2026-10-12): every frame is drawn here as
characters mapped to a palette, so it can be tweaked and regenerated.
Hand-drawn replacements stay possible if they keep the same sheet layout
and manifest keys.

Outputs:
    Assets/Skins/pibbo/   sprites.png, manifest.json, preview.gif, sprites@8x.png
    Assets/UI/            ui.png + ui.json (pixel font, emoji icons, speech bubble)

Usage:
    python3 Tools/generate_sprites.py

Requires: Python 3.10+, Pillow
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SKIN_DIR = ROOT / "Assets/Skins/pibbo"
UI_DIR = ROOT / "Assets/UI"

SIZE = 16  # frame size in pixels; the bottom 3 rows are water

PALETTE = {
    "o": (62, 42, 31),     # outline
    "b": (140, 90, 60),    # fur
    "d": (110, 69, 48),    # dark fur / eyelid
    "l": (233, 210, 176),  # cream face
    "e": (42, 27, 18),     # eye / mouth
    "n": (42, 27, 18),     # nose
    "c": (232, 160, 160),  # cheek / tongue
    "p": (90, 58, 40),     # paw
    "s": (244, 199, 184),  # shell
    "S": (217, 150, 127),  # shell ridge
    "h": (108, 123, 168),  # headphone band
    "H": (74, 86, 128),    # headphone cup
    "m": (245, 214, 110),  # yellow: music note, sun, flower centre, spark
    "k": (94, 156, 82),    # kelp / leaf
    "K": (63, 122, 58),    # dark kelp / stem
    "z": (159, 179, 217),  # zzz
    "u": (207, 234, 247),  # bubble
    "w": (111, 183, 217),  # water / raindrop
    "W": (191, 230, 245),  # foam / steam
    "x": (76, 147, 189),   # deep water
    "X": (250, 250, 255),  # snow / star
    "g": (96, 168, 160),   # watering can
    "G": (64, 124, 118),   # watering can dark
    "r": (150, 150, 146),  # rock
    "R": (108, 108, 104),  # rock shadow
    "q": (34, 34, 44),     # sunglasses
    "M": (200, 92, 80),    # mug
    "D": (96, 60, 40),     # cocoa / soil
    "L": (222, 130, 60),   # autumn leaf
    "f": (240, 150, 180),  # petal / flower
    "F": (214, 108, 146),  # dark petal
    "t": (196, 110, 74),   # terracotta pot
    "T": (160, 85, 58),    # pot rim
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


# ---------------------------------------------------------------- helpers

def base():
    return [list(r + r[::-1]) for r in BASE_HALF]


def blank():
    return [["."] * SIZE for _ in range(SIZE)]


def put(grid, points, ch):
    for r, c in points:
        if 0 <= r < SIZE and 0 <= c < SIZE:
            grid[r][c] = ch


def stamp(grid, top, left, rows):
    """Draw a small picture; '.' is transparent."""
    for dr, row in enumerate(rows):
        for dc, ch in enumerate(row):
            if ch != ".":
                put(grid, [(top + dr, left + dc)], ch)


def eyes(grid, style):
    """style: 'lazy' (half-closed), 'open', 'closed' (happy arcs), 'up' (looking up)."""
    if style == "lazy":
        put(grid, [(3, 4), (3, 5), (3, 10), (3, 11)], "d")
        put(grid, [(4, 4), (4, 5), (4, 10), (4, 11)], "e")
    elif style == "open":
        put(grid, [(3, 5), (4, 5), (3, 10), (4, 10)], "e")
    elif style == "closed":
        put(grid, [(4, 4), (3, 5), (3, 10), (4, 11)], "e")
    elif style == "up":
        put(grid, [(3, 5), (3, 10)], "e")


def remove_shell(grid):
    for c in (6, 7, 8, 9):
        grid[10][c] = "b"
        grid[11][c] = "p" if c in (6, 9) else "b"


def shift(grid, dy):
    """Move the otter down by dy rows (content above becomes empty)."""
    return [["."] * SIZE for _ in range(dy)] + grid[: SIZE - dy] if dy > 0 else grid


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


def mouth(grid, size):
    """0 = none, 1 = small 'o', 2 = big yawn."""
    if size == 1:
        put(grid, [(7, 7), (7, 8)], "e")
    elif size == 2:
        put(grid, [(6, 7), (6, 8), (7, 6), (7, 9)], "e")
        put(grid, [(7, 7), (7, 8)], "c")


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
    g = shift(g, [0, 1, 0, 1][i])  # the gentle bob lives in the frames
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


# ---------------------------------------------------------------- actions

def frame_submerged(i):
    """Work mode: under water, a few bubbles."""
    g = water(blank(), i)
    put(g, [(14, c) for c in range(5, 11)], "x")  # shadow under water
    put(g, [[(12, 7)], [(11, 7), (12, 9)], [(10, 8), (11, 9)], [(12, 6)]][i], "u")
    return g


def frame_water(i):
    """Idle: waters the flower on his left with a tiny can."""
    g = base()
    eyes(g, "lazy")
    can = [
        ["..GG.", ".g..g", "gggg.", "gggg.", ".gg.."],   # upright
        ["..GG.", "g...g", "gggg.", "gggg.", ".gg.."],   # tilting
        ["..GG.", "g...g", "gggg.", "gggg.", ".gg.."],
        ["..GG.", "g...g", "gggg.", "gggg.", ".gg.."],
    ][i]
    stamp(g, 6 if i == 0 else 7, 0, can)
    put(g, [(9, 4), (10, 4)], "p")  # paw holding it
    drops = [[], [(9, 0)], [(10, 0), (12, 0)], [(11, 0)]][i]
    put(g, drops, "w")
    return water(g, i)


def frame_crack(i):
    """Idle: cracks the shell on his belly with a rock."""
    g = base()
    eyes(g, "open")
    if i % 2 == 0:
        stamp(g, 8, 7, ["rr", "RR"])
        put(g, [(9, 6), (9, 9)], "p")
    else:
        stamp(g, 9, 7, ["rr", "RR"])
        put(g, [(10, 6), (10, 9)], "p")
        put(g, [(9, 5), (9, 10), (8, 4), (8, 11)], "m")  # tok!
    return water(g, i // 2)


def frame_groom(i):
    """Idle: rubs his face with both paws."""
    g = base()
    eyes(g, "closed")
    top = 4 if i % 2 == 0 else 5
    # paws poke out past the outline so they read against the fur
    put(g, [(top, 1), (top, 2), (top + 1, 2), (top + 1, 3), (top, 14), (top, 13), (top + 1, 13), (top + 1, 12)], "p")
    put(g, [(top - 1, 1), (top - 1, 14)], "o")
    return water(g, i // 2)


def frame_stretch(i):
    """Dawn: big stretch, arms up."""
    g = base()
    eyes(g, "closed")
    if i in (1, 2):
        put(g, [(0, 3), (0, 12)], "p")
        put(g, [(1, 2), (2, 2), (1, 13), (2, 13)], "b")
        mouth(g, 1)
    elif i == 0 or i == 3:
        put(g, [(2, 1), (2, 14)], "p")
    return water(g, i)


def frame_yawn(i):
    """Dawn / dusk / night: a slow yawn."""
    g = base()
    eyes(g, "closed" if i in (1, 2) else "lazy")
    mouth(g, [1, 2, 2, 1][i])
    return water(g, i // 2)


def frame_sunbathe(i):
    """Clear day: sunglasses on, soaking up the sun."""
    g = base()
    put(g, [(3, c) for c in (3, 4, 5, 6, 9, 10, 11, 12)] + [(4, c) for c in (4, 5, 10, 11)], "q")
    put(g, [(3, 7), (3, 8)], "q")
    put(g, [(3, 4) if i % 2 == 0 else (3, 10)], "W")  # glint
    g = shift(g, [0, 0, 1, 1][i])
    put(g, [(0, 15), (1, 15), (0, 14)], "m")  # sun
    if i % 2:
        put(g, [(2, 15), (0, 12)], "m")
    return water(g, i // 2)


def frame_raindrops(i):
    """Rain: happily catches raindrops."""
    g = base()
    eyes(g, "closed")
    mouth(g, 1)
    drops = [
        [(0, 3), (2, 12), (5, 15)],
        [(1, 3), (3, 12), (0, 8)],
        [(2, 3), (4, 12), (1, 8)],
        [(3, 3), (0, 13), (2, 8)],
    ][i]
    put(g, drops, "w")
    return water(g, i)


def frame_cocoa(i):
    """Snow: sips hot cocoa, steam rising."""
    g = base()
    eyes(g, "lazy")
    remove_shell(g)
    stamp(g, 9, 6, ["DDDD", "MMMMM", "MMMMM", "MMMM."])
    put(g, [(10, 10), (11, 10)], "M")
    steam = [[(8, 7), (7, 8), (6, 7)], [(8, 8), (7, 7), (6, 8)]][i % 2]
    put(g, steam, "W")
    flakes = [[(0, 2), (3, 14)], [(1, 2), (4, 14)], [(2, 1), (0, 13)], [(3, 1), (1, 13)]][i]
    put(g, flakes, "X")
    return water(g, i // 2)


def frame_huddle(i):
    """Storm: sinks low and keeps an eye on the sky."""
    g = base()
    eyes(g, "open")
    g = shift(g, [5, 5, 6, 5][i])
    streaks = [[(0, 2), (1, 1), (2, 12), (3, 11)], [(1, 4), (2, 3), (0, 14), (1, 13)],
               [(0, 8), (1, 7), (3, 2), (4, 1)], [(2, 14), (3, 13), (0, 5), (1, 4)]][i]
    put(g, streaks, "w")
    return water(g, i)


def frame_leaf(i):
    """Autumn: a maple leaf drifts down onto his head."""
    g = base()
    eyes(g, "up" if i < 2 else "lazy")
    leaf = ["L.L", "LLL", ".K."]
    stamp(g, [-1, 0, 0, 0][i] + [0, 0, 1, 1][i] - 1, [11, 9, 7, 7][i], leaf)
    return water(g, i // 2)


def frame_petal(i):
    """Spring: a petal lands on his nose."""
    g = base()
    eyes(g, "up" if i < 3 else "open")
    put(g, [[(0, 11), (0, 12)], [(2, 10), (2, 11)], [(4, 9), (3, 9)], [(5, 8), (4, 8)]][i], "f")
    return water(g, i // 2)


def frame_stargaze(i):
    """Clear night: looks up at twinkling stars."""
    g = base()
    eyes(g, "up")
    stars = [[(0, 1), (1, 14)], [(0, 1), (0, 9)], [(1, 14), (0, 9)], [(0, 1), (1, 14), (0, 9)]][i]
    put(g, stars, "X")
    return water(g, i // 2)


# ---------------------------------------------------------------- garden

def garden_stage(stage):
    """The flower on a rock beside Pibbo; one frame per growth stage."""
    g = water(blank(), 0)
    stamp(g, 11, 3, [".rrrrrrr.", "rrrrrrrrr", "RRRRRRRRR"])        # rock at the water line
    stamp(g, 7, 5, ["TTTTTT", ".tttt.", ".tttt.", "..tt.."])        # pot
    put(g, [(7, c) for c in range(6, 10)], "D")                       # soil
    plants = [
        [],
        [(6, 8, "k"), (5, 8, "k"), (5, 9, "k")],
        [(6, 8, "K"), (5, 8, "K"), (4, 8, "K"), (5, 7, "k"), (4, 9, "k"), (3, 9, "k")],
        [(6, 8, "K"), (5, 8, "K"), (4, 8, "K"), (3, 8, "K"), (5, 7, "k"), (4, 9, "k"),
         (6, 6, "k"), (2, 8, "F"), (1, 8, "f")],
        [(6, 8, "K"), (5, 8, "K"), (4, 8, "K"), (3, 8, "K"), (5, 7, "k"), (4, 9, "k"), (6, 6, "k"),
         (1, 8, "f"), (2, 7, "f"), (2, 9, "f"), (3, 7, "F"), (3, 9, "F"), (2, 8, "m")],
        [(6, 8, "K"), (5, 8, "K"), (4, 8, "K"), (5, 7, "k"), (4, 9, "k"), (6, 6, "k"), (5, 10, "k"),
         (0, 8, "f"), (1, 7, "f"), (1, 9, "f"), (2, 6, "f"), (2, 10, "f"), (3, 7, "F"), (3, 9, "F"),
         (1, 8, "m"), (2, 8, "m"), (2, 7, "m"), (2, 9, "m"), (4, 11, "f"), (3, 11, "F")],
    ][stage]
    for r, c, ch in plants:
        put(g, [(r, c)], ch)
    return g


GARDEN_STAGES = 6

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
    "water": (frame_water, 4, 3),
    "crack": (frame_crack, 4, 4),
    "groom": (frame_groom, 4, 4),
    "stretch": (frame_stretch, 4, 2),
    "yawn": (frame_yawn, 4, 2),
    "sunbathe": (frame_sunbathe, 4, 2),
    "raindrops": (frame_raindrops, 4, 4),
    "cocoa": (frame_cocoa, 4, 3),
    "huddle": (frame_huddle, 4, 4),
    "leaf": (frame_leaf, 4, 2),
    "petal": (frame_petal, 4, 2),
    "stargaze": (frame_stargaze, 4, 2),
}


def to_image(grid, palette=PALETTE):
    img = Image.new("RGBA", (len(grid[0]), len(grid)), (0, 0, 0, 0))
    px = img.load()
    for r, row in enumerate(grid):
        for c, ch in enumerate(row):
            if ch in palette:
                px[c, r] = palette[ch] + (255,)
    return img


# ---------------------------------------------------------------- UI: font, icons, bubble

LINE_HEIGHT = 9  # rows 0-1 ascender, 2-6 x-height, 7-8 descender
TEXT = (62, 42, 31)
BUBBLE_FILL = (255, 250, 238)

GLYPHS = {
    "a": ["...", "...", "##.", "..#", ".##", "#.#", ".##"],
    "b": ["#..", "#..", "##.", "#.#", "#.#", "#.#", "##."],
    "c": ["...", "...", ".##", "#..", "#..", "#..", ".##"],
    "d": ["..#", "..#", ".##", "#.#", "#.#", "#.#", ".##"],
    "e": ["...", "...", ".#.", "#.#", "###", "#..", ".##"],
    "f": [".##", "#..", "###", "#..", "#..", "#..", "#.."],
    "g": ["...", "...", ".##", "#.#", "#.#", "#.#", ".##", "..#", "##."],
    "h": ["#..", "#..", "##.", "#.#", "#.#", "#.#", "#.#"],
    "i": ["#", ".", "#", "#", "#", "#", "#"],
    "j": [".#", "..", ".#", ".#", ".#", ".#", ".#", ".#", "#."],
    "k": ["#..", "#..", "#.#", "#.#", "##.", "#.#", "#.#"],
    "l": ["#", "#", "#", "#", "#", "#", "#"],
    "m": [".....", ".....", "####.", "#.#.#", "#.#.#", "#.#.#", "#.#.#"],
    "n": ["...", "...", "##.", "#.#", "#.#", "#.#", "#.#"],
    "o": ["...", "...", ".#.", "#.#", "#.#", "#.#", ".#."],
    "p": ["...", "...", "##.", "#.#", "#.#", "#.#", "##.", "#..", "#.."],
    "q": ["...", "...", ".##", "#.#", "#.#", "#.#", ".##", "..#", "..#"],
    "r": ["...", "...", "#.#", "##.", "#..", "#..", "#.."],
    "s": ["...", "...", ".##", "#..", ".#.", "..#", "##."],
    "t": [".#.", ".#.", "###", ".#.", ".#.", ".#.", "..#"],
    "u": ["...", "...", "#.#", "#.#", "#.#", "#.#", ".##"],
    "v": ["...", "...", "#.#", "#.#", "#.#", "#.#", ".#."],
    "w": [".....", ".....", "#...#", "#...#", "#.#.#", "#.#.#", ".#.#."],
    "x": ["...", "...", "#.#", "#.#", ".#.", "#.#", "#.#"],
    "y": ["...", "...", "#.#", "#.#", "#.#", "#.#", ".##", "..#", "##."],
    "z": ["...", "...", "###", "..#", ".#.", "#..", "###"],
    "0": ["...", "...", "###", "#.#", "#.#", "#.#", "###"],
    "1": ["..", "..", ".#", "##", ".#", ".#", ".#"],
    "2": ["...", "...", "##.", "..#", ".#.", "#..", "###"],
    "3": ["...", "...", "##.", "..#", ".#.", "..#", "##."],
    "4": ["...", "...", "#.#", "#.#", "###", "..#", "..#"],
    "5": ["...", "...", "###", "#..", "##.", "..#", "##."],
    "6": ["...", "...", ".##", "#..", "###", "#.#", "###"],
    "7": ["...", "...", "###", "..#", ".#.", ".#.", ".#."],
    "8": ["...", "...", "###", "#.#", "###", "#.#", "###"],
    "9": ["...", "...", "###", "#.#", "###", "..#", "##."],
    " ": ["..", "..", "..", "..", "..", "..", ".."],
    ".": [".", ".", ".", ".", ".", ".", "#"],
    ",": [".", ".", ".", ".", ".", ".", "#", "#"],
    "!": ["#", "#", "#", "#", "#", ".", "#"],
    "?": ["##.", "..#", "..#", ".#.", ".#.", "...", ".#."],
    ":": [".", ".", ".", "#", ".", ".", "#"],
    "'": ["#", "#"],
    "-": ["...", "...", "...", "...", "###"],
    "(": [".#", "#.", "#.", "#.", "#.", "#.", ".#"],
    ")": ["#.", ".#", ".#", ".#", ".#", ".#", "#."],
    "%": ["#.#", "..#", ".#.", ".#.", ".#.", "#..", "#.#"],
    "/": ["..#", "..#", ".#.", ".#.", ".#.", "#..", "#.."],
    "&": [".#.", "#.#", ".#.", "##.", "#.#", "#.#", ".##"],
    "~": ["....", "....", "....", ".#.#", "#.#.", "....", "...."],
    "+": ["...", "...", "...", ".#.", "###", ".#.", "..."],
    ">": ["...", "...", "#..", ".#.", "..#", ".#.", "#.."],
    "A": [".#.", "#.#", "#.#", "###", "#.#", "#.#", "#.#"],
    "B": ["##.", "#.#", "#.#", "##.", "#.#", "#.#", "##."],
    "C": [".##", "#..", "#..", "#..", "#..", "#..", ".##"],
    "D": ["##.", "#.#", "#.#", "#.#", "#.#", "#.#", "##."],
    "E": ["###", "#..", "#..", "##.", "#..", "#..", "###"],
    "F": ["###", "#..", "#..", "##.", "#..", "#..", "#.."],
    "G": [".##", "#..", "#..", "#.#", "#.#", "#.#", ".##"],
    "H": ["#.#", "#.#", "#.#", "###", "#.#", "#.#", "#.#"],
    "I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
    "J": ["..#", "..#", "..#", "..#", "..#", "#.#", ".#."],
    "K": ["#.#", "#.#", "#.#", "##.", "#.#", "#.#", "#.#"],
    "L": ["#..", "#..", "#..", "#..", "#..", "#..", "###"],
    "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
    "N": ["#..#", "##.#", "##.#", "#.##", "#.##", "#..#", "#..#"],
    "O": [".#.", "#.#", "#.#", "#.#", "#.#", "#.#", ".#."],
    "P": ["##.", "#.#", "#.#", "##.", "#..", "#..", "#.."],
    "Q": [".#.", "#.#", "#.#", "#.#", "#.#", "##.", ".##"],
    "R": ["##.", "#.#", "#.#", "##.", "#.#", "#.#", "#.#"],
    "S": [".##", "#..", "#..", ".#.", "..#", "..#", "##."],
    "T": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", ".#."],
    "U": ["#.#", "#.#", "#.#", "#.#", "#.#", "#.#", "###"],
    "V": ["#.#", "#.#", "#.#", "#.#", "#.#", ".#.", ".#."],
    "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
    "X": ["#.#", "#.#", ".#.", ".#.", ".#.", "#.#", "#.#"],
    "Y": ["#.#", "#.#", "#.#", ".#.", ".#.", ".#.", ".#."],
    "Z": ["###", "..#", ".#.", ".#.", "#..", "#..", "###"],
}

ICON_PALETTE = dict(PALETTE)
ICONS = {
    "🎧": [".........", "..hhhhh..", ".h.....h.", "h.......h", "HH.....HH",
           "HH.....HH", "HH.....HH", ".........", "........."],
    "👋": [".o.o.o...", "olololo..", "olllllo.o", "olllllloo", "ollllllo.",
           ".olllllo.", "..ollllo.", "...oooo..", "........."],
    "☕": ["..W..W...", "...W..W..", "oooooo...", "oDDDDooo.", "oMMMMo.o.",
           "oMMMMooo.", "oMMMMo...", ".oooo....", "........."],
    "🐚": [".........", "....o....", "...oso...", "..osSso..", ".osSsSso.",
           "osSsSsSso", "oSsSsSsSo", ".ooooooo.", "........."],
    "🫧": [".....xx..", "....xuux.", "....xuux.", ".....xx..", ".xx......",
           "xuux..x..", "xuux.xux.", ".xx...x..", "........."],
    "❄": ["....x....", ".x..x..x.", "..x.x.x..", "...xxx...", "xxxxxxxxx",
          "...xxx...", "..x.x.x..", ".x..x..x.", "....x...."],
}

BUBBLE = ["..ooo..", ".oFFFo.", "oFFFFFo", "oFFFFFo", "oFFFFFo", ".oFFFo.", "..ooo.."]
TAIL = ["oFFo", ".oFo", "..oo", "...o"]


def build_ui():
    """Packs glyphs, icons and bubble parts into ui.png with metrics in ui.json."""
    UI_DIR.mkdir(parents=True, exist_ok=True)
    pal = {"#": TEXT, "o": TEXT, "F": BUBBLE_FILL}
    entries = []
    for ch, rows in GLYPHS.items():
        entries.append((ch, rows + ["." * len(rows[0])] * (LINE_HEIGHT - len(rows)), pal))
    for ch, rows in ICONS.items():
        entries.append((ch, rows, ICON_PALETTE))

    columns, cell_w = 16, 10
    rows_needed = (len(entries) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell_w, rows_needed * LINE_HEIGHT + 8), (0, 0, 0, 0))
    glyph_meta = {}
    for k, (ch, rows, palette) in enumerate(entries):
        x, y = (k % columns) * cell_w, (k // columns) * LINE_HEIGHT
        sheet.alpha_composite(to_image(rows, palette), (x, y))
        glyph_meta[ch] = {"x": x, "y": y, "w": len(rows[0])}

    parts_y = rows_needed * LINE_HEIGHT
    sheet.alpha_composite(to_image(BUBBLE, pal), (0, parts_y))
    sheet.alpha_composite(to_image(TAIL, pal), (8, parts_y))
    sheet.save(UI_DIR / "ui.png")

    meta = {
        "lineHeight": LINE_HEIGHT,
        "letterSpacing": 1,
        "glyphs": glyph_meta,
        "bubble": {"x": 0, "y": parts_y, "size": len(BUBBLE), "corner": 3},
        "tail": {"x": 8, "y": parts_y, "w": len(TAIL[0]), "h": len(TAIL)},
        "padding": {"x": 4, "top": 3, "bottom": 2},
    }
    (UI_DIR / "ui.json").write_text(json.dumps(meta, indent=1, ensure_ascii=False) + "\n")


# ---------------------------------------------------------------- skin

def build_skin():
    SKIN_DIR.mkdir(parents=True, exist_ok=True)
    entries = list(STATES.items()) + list(ACTIONS.items())
    max_frames = max(max(n for _, (_, n, _) in entries), GARDEN_STAGES)
    rows = len(entries) + 1  # + garden row
    sheet = Image.new("RGBA", (SIZE * max_frames, SIZE * rows), (0, 0, 0, 0))
    frames = {}
    for row, (name, (fn, n, _)) in enumerate(entries):
        frames[name] = [to_image(fn(i)) for i in range(n)]
        for i, f in enumerate(frames[name]):
            sheet.paste(f, (i * SIZE, row * SIZE))
    garden_row = len(entries)
    garden = [to_image(garden_stage(s)) for s in range(GARDEN_STAGES)]
    for s, f in enumerate(garden):
        sheet.paste(f, (s * SIZE, garden_row * SIZE))
    sheet.save(SKIN_DIR / "sprites.png")

    manifest = {
        "id": "com.tidepool.pibbo",
        "name": "pibbo",
        "author": "tidepool",
        "version": "0.2.0",
        "type": "skin",
        "frameSize": SIZE,
        "states": {},
        "actions": {},
        "garden": {"row": garden_row, "stages": GARDEN_STAGES},
    }
    for row, (name, (_, n, fps)) in enumerate(entries):
        key = "states" if name in STATES else "actions"
        manifest[key][name] = {"row": row, "frames": n, "fps": fps}
    (SKIN_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    write_previews(entries, frames, garden, sheet)


def write_previews(entries, frames, garden, sheet):
    """Animated preview of every clip (3 rows) plus the garden stages, at 6x."""
    scale, pad, label_h, per_row = 6, 12, 22, 7
    cell = SIZE * scale
    items = [(name, frames[name], fps) for name, (_, _, fps) in entries]
    items += [(f"flower {s}", [garden[s]], 1) for s in range(GARDEN_STAGES)]
    n_rows = (len(items) + per_row - 1) // per_row
    width = per_row * (cell + pad) + pad
    height = n_rows * (cell + label_h + pad) + pad
    try:
        font = ImageFont.load_default(size=13)
    except TypeError:
        font = ImageFont.load_default()
    tick = 1 / 12
    gif_frames = []
    for t in range(24):
        canvas = Image.new("RGBA", (width, height), (247, 242, 232, 255))
        d = ImageDraw.Draw(canvas)
        for k, (name, clip, fps) in enumerate(items):
            sprite = clip[int(t * tick * fps) % len(clip)].resize((cell, cell), Image.NEAREST)
            x = pad + (k % per_row) * (cell + pad)
            y = pad + (k // per_row) * (cell + label_h + pad)
            canvas.alpha_composite(sprite, (x, y))
            tw = d.textlength(name, font=font)
            d.text((x + (cell - tw) / 2, y + cell + 4), name, fill=(90, 70, 55), font=font)
        gif_frames.append(canvas.convert("RGB"))
    gif_frames[0].save(SKIN_DIR / "preview.gif", save_all=True, append_images=gif_frames[1:],
                       duration=int(tick * 1000), loop=0)
    sheet.resize((sheet.width * 8, sheet.height * 8), Image.NEAREST).save(SKIN_DIR / "sprites@8x.png")


def main():
    build_skin()
    build_ui()
    print(f"wrote {SKIN_DIR.relative_to(ROOT)} and {UI_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
