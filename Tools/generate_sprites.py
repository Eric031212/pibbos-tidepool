#!/usr/bin/env python3
"""Generate all of Tidepool's pixel art from text pixel grids.

This is the real art (decided 2026-10-12): every frame is drawn here as
characters mapped to a palette, so it can be tweaked and regenerated.
Hand-drawn replacements stay possible if they keep the same sheet layout
and manifest keys.

Outputs:
    Assets/Skins/pibbo/   sprites.png, manifest.json, preview.gif, sprites@8x.png
    Assets/UI/            ui.png + ui.json (pixel font, emoji icons, speech bubble)
    Assets/AppIcon/       AppIcon.icns + AppIcon.png (Pibbo in his tide pool; needs macOS iconutil)
    Assets/Games/         games.png + games.json (game window frame, game art), preview-games.png

Usage:
    python3 Tools/generate_sprites.py

Requires: Python 3.10+, Pillow
"""
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SKIN_DIR = ROOT / "Assets/Skins/pibbo"
UI_DIR = ROOT / "Assets/UI"
ICON_DIR = ROOT / "Assets/AppIcon"
GAMES_DIR = ROOT / "Assets/Games"

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
    "j": (176, 88, 36),    # pumpkin ridge
    "y": (255, 226, 120),  # candle glow
    "Y": (250, 176, 70),   # candle glow, dimmer
    "v": (52, 44, 64),     # bat
    "C": (214, 92, 72),    # crab
    "Q": (150, 58, 46),    # crab dark
    "B": (198, 160, 118),  # friend otter's fur (lighter than Pibbo)
    "A": (166, 128, 92),   # friend otter's dark fur / paws
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
    g = shift(g, [1, 0, 1, 0][i])  # the gentle bob lives in the frames; head down on the beat
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


def frame_unplug(i):
    """Music stops: lifts the headphones off and sets them aside (plays once)."""
    g = base()
    if i == 0:
        eyes(g, "closed")
        headphones(g)
    elif i == 1:  # lifting
        eyes(g, "closed")
        put(g, [(0, c) for c in range(4, 12)] + [(1, 3), (1, 12)], "h")
        put(g, [(r, c) for r in (2, 3) for c in (1, 2, 13, 14)], "H")
        put(g, [(4, 1), (4, 14)], "p")
    elif i == 2:  # held above his head
        eyes(g, "open")
        put(g, [(0, c) for c in range(3, 13)], "h")
        put(g, [(r, c) for r in (0, 1) for c in (1, 2, 13, 14)], "H")
        put(g, [(2, 1), (2, 14)], "p")
    else:  # set down beside him
        eyes(g, "lazy")
        put(g, [(9, 13), (9, 14)], "h")
        put(g, [(10, 14), (10, 15), (11, 14), (11, 15)], "H")
    return water(g, 0)


BACK_BODY = [
    "..........oooo..",
    "..pp.psp..obbbbo",
    ".obbbbbbbbblelbo",
    ".obllllllbblnlco",
    ".obbbbbbbbbbbbo.",
    "..oooooooooooo..",
]


def frame_backfloat(i):
    """Petted: rolls onto his back and floats, a little heart rising."""
    g = blank()
    body = BACK_BODY
    stamp(g, 7 + [0, 0, 1, 1][i], 0, body)
    heart = ["f.f", "fff", ".f."]
    stamp(g, [4, 3, 2, 1][i], 6 + (i % 2), heart)
    g = water(g, i // 2)
    # the body floats on the surface: draw it back over the top water row
    for c, ch in enumerate(body[5 if i < 2 else 4]):
        if ch != ".":
            put(g, [(12 + [0, 0, 1, 1][i] - (0 if i < 2 else 1), c)], ch)
    return g


def frame_holdpaw(i):
    """Cursor resting on him: reaches up and holds your 'paw', swaying."""
    g = base()
    eyes(g, "closed")
    put(g, [(6, 4), (6, 11)], "c")
    # a chunky raised arm on his right, swaying a pixel side to side
    col = 12 if i % 2 == 0 else 13
    top = 0 if i < 2 else 1
    arm = ["opo", "opp", ".bbo", ".bbo"]
    stamp(g, top, col - 1, arm)
    put(g, [(top + 4, col), (top + 4, col + 1)], "b")
    return water(g, i // 2)


def frame_friendpaw(i):
    """Holding paws with the friend otter on his left (holdpaw, mirrored)."""
    g = frame_holdpaw(i)
    return [row[::-1] for row in g[:13]] + g[13:]  # mirror the otter, keep the water as is


def frame_admire(i):
    """After the rain: looks up at the rainbow, a little 'oh'."""
    g = base()
    eyes(g, "up")
    if i >= 2:
        mouth(g, 1)
    return water(g, i // 2)


def frame_look(i):
    """A splash nearby: turns to look at it."""
    g = base()
    put(g, [(3, 4), (4, 4), (3, 9), (4, 9)], "e")  # eyes glance left
    if i == 1:
        put(g, [(0, 1), (1, 1), (3, 1)], "m")  # !
    return water(g, i)


def frame_ripple(i):
    """Effect drawn over the water where you clicked (transparent elsewhere)."""
    g = blank()
    if i == 0:
        put(g, [(10, 7), (9, 8), (11, 9), (10, 6)], "u")
        put(g, [(12, 7), (12, 8)], "W")
    elif i == 1:
        put(g, [(11, 5), (10, 10)], "u")
        put(g, [(13, c) for c in (6, 7, 8, 9)] + [(12, 5), (12, 10)], "W")
    elif i == 2:
        put(g, [(13, c) for c in (3, 4, 11, 12)] + [(12, 5), (12, 10), (14, 6), (14, 9)], "W")
    else:
        put(g, [(13, c) for c in (1, 2, 13, 14)] + [(14, 4), (14, 11)], "W")
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


def frame_note(i):
    """Opens a message in a bottle and reads the note, eyes moving along it."""
    g = base()
    remove_shell(g)
    put(g, [(4, 5), (4, 10)] if i % 2 == 0 else [(4, 6), (4, 11)], "e")  # reading left to right
    stamp(g, 8, 4, ["XXXXXXXX", "XzzXzzzX", "XXXXXXXX", "XzzzXzzX"])
    put(g, [(9, 3), (11, 3), (9, 12), (11, 12)], "p")  # paws holding the note
    return water(g, i // 2)


def frame_wish(i):
    """Saw a shooting star: paws together, eyes shut, making a wish."""
    g = base()
    eyes(g, "closed")
    put(g, [(7, 7), (7, 8), (8, 7), (8, 8)], "p")  # paws together under his chin
    put(g, [(6, 6), (6, 9)], "o")
    sparkles = [[(1, 2), (3, 14)], [(0, 13), (2, 1)], [(1, 14), (3, 2)], [(0, 2), (2, 13)]][i]
    put(g, sparkles, "y")
    return water(g, i // 2)


def frame_game(i):
    """Pixel Tide is on: headphones on, playing the little handheld, paws mashing."""
    g = base()
    headphones(g)
    remove_shell(g)
    put(g, [(4, 5), (4, 10)], "e")  # eyes down on the screen
    stamp(g, 7, 5, ["oooooo", "okkkko", "orRrMo", "oooooo"])
    put(g, [[(8, 7)], [(8, 8)], [(8, 9)], [(8, 8)]][i], "m")  # the game on its screen
    put(g, [(9, 4), (9, 11)] if i % 2 == 0 else [(10, 4), (10, 11)], "p")  # paws mashing
    return water(shift(g, [0, 1, 0, 1][i]), i // 2)


def frame_flip(i):
    """The secret: a flip out of the water with a big splash (plays once)."""
    if i == 0:  # crouch
        g = water(shift(base(), 3), 0)
        splash(g)
        return g
    if i in (1, 3):  # flying, side-on
        g = blank()
        body = BACK_BODY if i == 1 else [row[::-1] for row in BACK_BODY]
        stamp(g, 1 if i == 1 else 2, 0, body)
        g = water(g, 1)
        put(g, [(10, 2), (11, 13), (9, 7)], "W")
        return g
    if i == 2:  # upside down at the top
        g = base()
        eyes(g, "closed")
        upside = [row[:] for row in g[:12]][::-1]
        g = water(upside + [["."] * SIZE for _ in range(4)], 0)
        return g
    if i == 4:  # back into the water: a big splash
        g = water(blank(), 1)
        splash(g, wide=True)
        put(g, [(9, 4), (8, 7), (9, 11), (10, 6), (10, 9)], "W")
        return g
    g = base()  # pops back up, very pleased
    eyes(g, "closed")
    mouth(g, 1)
    g = water(shift(g, 1), 0)
    put(g, [(2, 1), (1, 14)], "W")
    return g


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


# ---------------------------------------------------------------- transitions
# In-between frames played once when Pibbo switches clips, so he glides
# between poses instead of jumping. Clips share transitions through their pose
# (how high he sits in the water); a few prop changes get their own. Keys are
# "from>to", each side a clip name or "@pose" (the app picks the most specific).

POSES = {"hidden": "low", "peek": "peek", "huddle": "peek", "submerged": "under", "backfloat": "back"}
NO_POSE = {"ripple"}  # an effect layer, never switched to
TRANSITION_FPS = 10


def splash(grid, wide=False):
    """Drops thrown up where he breaks the surface."""
    put(grid, [(12, 3), (11, 2), (12, 12), (11, 13)], "W")
    if wide:
        put(grid, [(10, 1), (10, 14)], "W")


def bubble_trail(grid, i):
    put(grid, [[(12, 7)], [(11, 8), (12, 6)]][i % 2], "u")


def slide(shifts, eye_style, splash_at=(), bubbles=False):
    """Rise or sink through the water line, one shift per frame."""
    def fn(i):
        g = base()
        eyes(g, eye_style)
        g = water(shift(g, shifts[i]), i)
        if i in splash_at:
            splash(g)
        if bubbles:
            bubble_trail(g, i)
        return g
    return fn


def roll_over(i):
    """Chill -> back-float: tucks in with a splash, then lands on his back."""
    if i == 0:
        g = base()
        eyes(g, "closed")
        g = water(shift(g, 2), 0)
        splash(g)
        return g
    g = blank()
    stamp(g, 9, 0, BACK_BODY)
    g = water(g, 1)
    splash(g, wide=True)
    return g


def roll_back(i):
    return roll_over(1 - i)


def headphones_on(i):
    return frame_unplug([2, 1][i])  # held above his head, then lowered on


def doze(i):
    """Eyes droop and the kelp wraps around him before he falls asleep."""
    g = base()
    eyes(g, "lazy" if i == 0 else "closed")
    remove_shell(g)
    wrap = [(9, 2), (9, 3), (10, 4), (10, 5), (10, 6)] if i == 0 else \
           [(9, 2), (9, 3), (10, 4), (10, 5), (10, 6), (11, 7), (11, 8), (11, 9)]
    put(g, wrap, "k")
    return water(g, i)


def wake(i):
    """Blinks awake while the kelp slips away."""
    g = base()
    eyes(g, "closed" if i == 0 else "lazy")
    remove_shell(g)
    put(g, [(10, 4), (10, 5), (11, 6), (11, 7), (12, 8)] if i == 0 else [(12, 3), (12, 4), (12, 5)], "k")
    return water(g, i)


def glasses(row):
    def fn(i):
        g = base()
        eyes(g, "lazy")
        r = row(i)
        put(g, [(r, c) for c in (3, 4, 5, 6, 7, 8, 9, 10, 11, 12)] + [(r + 1, c) for c in (4, 5, 10, 11)], "q")
        return water(g, 0)
    return fn


def mug(rows):
    """The cocoa mug comes up out of the water (or goes back down)."""
    def fn(i):
        g = base()
        eyes(g, "lazy")
        remove_shell(g)
        stamp(g, rows[i], 6, ["DDDD", "MMMMM", "MMMMM", "MMMM."])
        return water(g, i)
    return fn


def reach(i):
    """Halfway up to hold your paw."""
    g = base()
    eyes(g, "closed")
    stamp(g, 3, 11, ["opo", "opp", ".bbo", ".bbo"])
    return water(g, 0)


def can(rows):
    """The watering can comes up from beside him (or goes away)."""
    def fn(i):
        g = base()
        eyes(g, "lazy")
        stamp(g, rows[i], 0, ["..GG.", ".g..g", "gggg.", "gggg.", ".gg.."])
        put(g, [(rows[i] + 3, 4), (rows[i] + 4, 4)], "p")
        return water(g, i)
    return fn


# key -> (frame function, frame count, fps)
TRANSITIONS = {
    # rising and sinking between poses
    "@under>@low": (slide([12, 10], "lazy", bubbles=True), 2, TRANSITION_FPS),
    "@under>@peek": (slide([11, 8, 6], "open", bubbles=True), 3, TRANSITION_FPS),
    "@under>@up": (slide([11, 7, 4, 2, 1], "lazy", splash_at=(2,)), 5, TRANSITION_FPS),
    "@low>@under": (slide([10, 12], "closed", bubbles=True), 2, TRANSITION_FPS),
    "@peek>@under": (slide([7, 9, 11], "closed", bubbles=True), 3, TRANSITION_FPS),
    "@up>@under": (slide([1, 3, 6, 9, 12], "closed", splash_at=(2,), bubbles=True), 5, TRANSITION_FPS),
    "@low>@peek": (slide([7, 6], "open"), 2, TRANSITION_FPS),
    "@low>@up": (slide([6, 3, 1], "lazy", splash_at=(1,)), 3, TRANSITION_FPS),
    "@peek>@low": (slide([6, 7], "lazy"), 2, TRANSITION_FPS),
    "@peek>@up": (slide([3, 1], "lazy", splash_at=(0,)), 2, TRANSITION_FPS),
    "@up>@low": (slide([1, 3, 6], "lazy", splash_at=(2,)), 3, TRANSITION_FPS),
    "@up>@peek": (slide([2, 4], "open"), 2, TRANSITION_FPS),
    # rolling onto his back and back up
    "@up>@back": (roll_over, 2, 8),
    "@back>@up": (roll_back, 2, 8),
    # props coming and going
    "@up>music": (headphones_on, 2, 6),
    "@up>sleep": (doze, 2, 4),
    "sleep>@up": (wake, 2, 5),
    "@up>sunbathe": (glasses(lambda i: [1, 2][i]), 2, 6),
    "sunbathe>@up": (glasses(lambda i: [2, 1][i]), 2, 6),
    "@up>cocoa": (mug([12, 10]), 2, 8),
    "cocoa>@up": (mug([10, 12]), 2, 8),
    "@up>holdpaw": (reach, 1, 8),
    "holdpaw>@up": (reach, 1, 8),
    "@up>water": (can([9, 8]), 2, 8),
    "water>@up": (can([8, 9]), 2, 8),
}


def pose_of(name):
    return POSES.get(name, "up")


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

# The meadow: a long rock to the left of the flower that slowly fills up over
# a few months after the flower blooms (World.Garden.meadowDays). Each stage
# keeps everything from the ones before; nothing ever wilts or resets.
MEADOW_PLANTS = [
    [],                                                                   # bare rock
    [(10, 4, "k"), (10, 5, "K"), (10, 6, "k"), (11, 4, "K"), (10, 7, "k")],  # moss
    [(8, 12, "M"), (9, 11, "M"), (9, 12, "X"), (9, 13, "M"), (10, 12, "l"),  # mushrooms
     (9, 14, "M"), (10, 14, "l")],
    [(7, 5, "k"), (8, 4, "k"), (8, 5, "K"), (8, 6, "k"), (9, 3, "k"),       # succulent
     (9, 4, "K"), (9, 5, "k"), (9, 6, "K"), (9, 7, "k"), (10, 4, "K"), (10, 5, "K"), (10, 6, "K")],
    [(3, 9, "h"), (2, 9, "h"), (3, 8, "h"), (3, 10, "h"), (4, 9, "h"),     # a little blue flower
     (3, 9, "m"), (5, 9, "K"), (6, 9, "K"), (7, 9, "K"), (8, 9, "K"), (9, 9, "K"), (10, 9, "K"),
     (7, 8, "k"), (8, 10, "k")],
    [(11, 13, "L"), (12, 12, "L"), (12, 13, "L"), (12, 14, "L"), (13, 12, "L"), (13, 14, "L")],  # starfish
    [(10, 2, "s"), (10, 3, "S"), (9, 2, "s"), (2, 12, "f"), (2, 14, "f"), (3, 13, "q")],  # shell, butterfly
]
MEADOW_STAGES = len(MEADOW_PLANTS)


def meadow_stage(stage):
    g = water(blank(), 0)
    stamp(g, 11, 2, [".rrrrrrrrrrrrr", "rrrrrrrrrrrrrr", "RRRRRRRRRRRRRR"])
    for plants in MEADOW_PLANTS[: stage + 1]:
        for r, c, ch in plants:
            put(g, [(r, c)], ch)
    return g


def frame_shooting_star(i):
    """A shooting star streaking down over the pool, right to left (plays once)."""
    g = blank()
    path = [(0, 15), (1, 13), (2, 11), (3, 9), (4, 7), (5, 5)]
    if i < 5:
        put(g, [path[i]], "X")
        if i >= 1:
            put(g, [path[i - 1]], "y")
        if i >= 2:
            put(g, [path[i - 2]], "Y")
    else:  # it fades into a little twinkle
        r, c = path[4]
        put(g, [(r, c - 1), (r - 1, c), (r + 1, c), (r, c + 1)], "Y")
    return g


SHOOTING_STAR_FRAMES = 6


# ---------------------------------------------------------------- weather in the pool
# Overlays drawn over every cell of the pool (Pibbo's, the flower's, the
# meadow's), transparent elsewhere. The ripples sit in the water rows, so the
# app's water light recolours them with the rest of the pool.

def frame_rain(i):
    """Raindrops falling and little rings spreading on the water."""
    g = blank()
    drops = [[(1, 3), (5, 11), (9, 7)], [(3, 3), (7, 11), (0, 14), (11, 7)],
             [(5, 3), (9, 11), (2, 14), (1, 6)], [(7, 3), (11, 11), (4, 14), (3, 6)]][i]
    for r, c in drops:
        put(g, [(r, c), (r + 1, c)], "w")
    rings = [[(13, 6), (13, 8)], [(13, 2), (13, 4), (13, 12), (13, 14)], [(13, 9), (13, 11), (14, 10)], [(13, 1), (13, 3)]][i]
    put(g, rings, "W")
    return g


def frame_snowfall(i):
    """Snowflakes drifting down over the pool."""
    g = blank()
    flakes = [[(1, 2), (4, 9), (8, 13), (10, 5)], [(2, 3), (5, 8), (9, 14), (11, 4)],
              [(3, 2), (6, 9), (0, 13), (12, 5)], [(4, 3), (7, 8), (1, 14), (0, 6)]][i]
    put(g, flakes, "X")
    return g


def snow_cover(cell):
    """Snow resting on the rocks and the pot rim. cell 0: the flower's rock, 1: the meadow's."""
    g = blank()
    if cell == 0:
        put(g, [(10, 4), (11, 3), (11, 11), (10, 10)], "X")
        put(g, [(6, c) for c in (5, 6, 7, 9, 10)], "X")  # pot rim (the stem keeps col 8)
    else:
        put(g, [(10, c) for c in range(3, 16) if c % 5 != 1], "X")
        put(g, [(11, 2)], "X")
    return g


# ---------------------------------------------------------------- visitors
# Each visit is one sequence played once on a layer that moves along the pool
# in whole art pixels (`path`: the layer's left edge per frame, in art pixels
# from the window's left edge: meadow 0-15, flower 16-31, Pibbo 32-47).
# Frames are transparent outside the visitor; nothing in the water rows except
# splashes, so the pool's own water shows through.

FRIEND = {"b": "B", "d": "A", "p": "A"}  # Pibbo's colours -> the friend's


def recolor(grid, mapping):
    return [[mapping.get(ch, ch) for ch in row] for row in grid]


def no_water(grid):
    """Clears the water rows so the visitor sits in the pool's own water."""
    return [row if r < 13 else ["."] * SIZE for r, row in enumerate(grid)]


def crab_frame(legs, wave=False):
    g = blank()
    if wave:
        put(g, [(9, 0), (9, 4)], "C")
    put(g, [(10, 1), (10, 3)], "e")                     # eyes on stalks
    put(g, [(11, c) for c in range(5)], "C")
    put(g, [(11, 0), (11, 4)] if not wave else [], "Q")  # claws down while walking
    put(g, [(12, c) for c in ((0, 2, 4) if legs else (1, 3))], "Q")
    return g


def visit_crab():
    walk_in = list(range(2, 20, 2))          # 9 steps along the shore toward Pibbo
    frames = [crab_frame(i % 2) for i in range(len(walk_in))]
    frames += [crab_frame(i % 2, wave=True) for i in range(4)]  # waves its claws
    frames += [crab_frame(i % 2) for i in range(len(walk_in))]
    path = walk_in + [walk_in[-1]] * 4 + walk_in[::-1]
    return frames, path, 4


def gull_frame(pose, top=6, left=1):
    """pose: stand, hop, look (head turned back), fly (wings up), glide (wings out)."""
    g = blank()
    if pose in ("fly", "glide"):
        body = {"fly": ["R.....R", ".RXXXR.", "..XXXem", "...m..."],
                "glide": [".......", "RRXXXRR", "..XXXem", "......."]}[pose]
        stamp(g, top, left, body)
        return g
    head = "...XXe." if pose != "look" else "..eXX.."
    beak = "...XXXm" if pose != "look" else ".mXXX.."
    stamp(g, top - (1 if pose == "hop" else 0), left, [head, beak, ".RXXXX.", "RRXXXX.", "..m.m.."])
    return g


GIFT_FEATHER = [(9, 1, "R"), (9, 2, "X"), (9, 3, "X"), (9, 4, "r"),         # vane, edged in grey
                (10, 2, "r"), (10, 3, "X"), (10, 4, "X"), (10, 5, "R"), (10, 6, "R")]  # and its quill


def gift_frame():
    """The seagull's present, lying on the meadow rock for good (meadow cell)."""
    g = blank()
    for r, c, ch in GIFT_FEATHER:
        put(g, [(r, c)], ch)
    return g


def carry(g, top, left, pose):
    """A little feather held in the beak (just right of it)."""
    if pose in ("fly", "glide"):
        put(g, [(top + 2, left + 7), (top + 3, left + 7)], "X")
    else:
        put(g, [(top + 1, left + 7), (top + 2, left + 7)], "X")
    return g


def visit_seagull_gift():
    """The seagull's fifth visit: it brings a feather, sets it on the rock, flies off."""
    seq = [("glide", 0, 6, True), ("fly", 2, 4, True), ("glide", 4, 2, True),
           ("stand", 6, 1, True), ("stand", 6, 1, True), ("hop", 6, 1, True),
           ("look", 6, 1, False), ("look", 6, 1, False), ("stand", 6, 1, False), ("hop", 6, 1, False),
           ("stand", 6, 1, False), ("stand", 6, 1, False), ("fly", 4, 3, False), ("glide", 2, 6, False), ("fly", 0, 9, False)]
    frames = []
    for k, (pose, top, left, holding) in enumerate(seq):
        g = gull_frame(pose, top, left)
        if holding:
            carry(g, top - (1 if pose == "hop" else 0), left, pose)
        elif k >= 6:  # dropped while it looks round: from now on it lies on the rock
            for r, c, ch in GIFT_FEATHER:
                if g[r][c] == ".":
                    put(g, [(r, c)], ch)
        frames.append(g)
    return frames, [0] * len(frames), 3


def visit_seagull():
    frames = [gull_frame("glide", 0, 6), gull_frame("fly", 2, 4), gull_frame("glide", 4, 2)]  # coming down
    frames += [gull_frame("stand")] * 2 + [gull_frame("hop"), gull_frame("stand"), gull_frame("hop"), gull_frame("stand")]
    frames += [gull_frame("look")] * 2 + [gull_frame("stand")] * 2
    frames += [gull_frame("fly", 4, 3), gull_frame("glide", 2, 6), gull_frame("fly", 0, 9)]  # off again
    return frames, [0] * len(frames), 3


def fish_frame(i):
    g = blank()
    fish = [None, (11, 12, ["LLm"]), (8, 11, [".mL.", "LLLL", ".L.."]), (7, 12, ["LLL", "mLL", "..L"]),
            (9, 13, ["L.", "LL", "Lm"]), None, None][i]
    if fish:
        stamp(g, fish[0], fish[1], fish[2])
    splash = [[(13, 12), (13, 14)], [(13, 11), (13, 15)], [], [], [(12, 13)],
              [(11, 12), (11, 14), (12, 13), (13, 11), (13, 15)], [(13, 10), (13, 15)]][i]
    put(g, splash, "W")
    return g


def visit_fish():
    frames = [fish_frame(i) for i in range(7)]
    return frames, [16] * len(frames), 6


def friend_swim(i):
    g = base()
    eyes(g, "lazy")
    remove_shell(g)
    return no_water(recolor(shift(g, [5, 6][i % 2]), FRIEND))


def friend_hold(i):
    return no_water(recolor(shift(frame_holdpaw(i), 1), FRIEND))


def visit_friend():
    swim_in = list(range(-12, 20, 2))         # from off the left edge to just beside Pibbo
    frames = [friend_swim(i) for i in range(len(swim_in))]
    frames += [friend_hold(i % 4) for i in range(10)]
    frames += [friend_swim(i) for i in range(len(swim_in))]
    path = swim_in + [swim_in[-1]] * 10 + swim_in[::-1]
    return frames, path, 3


VISIT_WRAP = 8  # long visits wrap onto further rows, 8 frames per row (keeps the sheet narrow)

VISITORS = {
    "crab": visit_crab,
    "seagull": visit_seagull,
    "seagullGift": visit_seagull_gift,
    "fish": visit_fish,
    "friend": visit_friend,
}


# Things that drift by with the season while Pibbo is out: a tiny item in the
# top-left corner of its cell; the app moves the layer across the pool.
def frame_drift(season, i):
    g = blank()
    item = {
        "spring": [["f.", "Ff"], [".f", "fF"]],          # a petal turning
        "summer": [[".X.", "XWX", ".R."], ["X.X", ".W.", ".R."]],  # dandelion fluff
        "autumn": [["LL", ".L"], ["L.", "LL"]],          # a leaf tumbling
    }[season][i]
    stamp(g, 0, 0, item)
    return g


DRIFT_SEASONS = ["spring", "summer", "autumn"]


# The rainbow after rain: one arc over the whole pool (meadow, flower, Pibbo),
# split into three cells. Half see-through, so the flower shows behind it.
RAINBOW_BANDS = [(222, 96, 92), (240, 168, 84), (244, 218, 112), (130, 196, 120), (112, 160, 214)]
RAINBOW_ALPHA = 170


def rainbow_cells():
    width = SIZE * 3
    img = Image.new("RGBA", (width, SIZE), (0, 0, 0, 0))
    px = img.load()
    cx, cy = width / 2 - 0.5, SIZE - 0.5
    for x in range(width):
        for y in range(SIZE - 1):  # stops just above the water's lowest row
            # elliptical distance: 1.0 on the outer edge of the arc
            d = (((x - cx) / (width / 2 - 1)) ** 2 + ((y - cy) / (SIZE - 1.5)) ** 2) ** 0.5
            band = int((1 - d) * 18)  # each band ~1 pixel wide at the top
            if 0 <= band < len(RAINBOW_BANDS):
                px[x, y] = RAINBOW_BANDS[band] + (RAINBOW_ALPHA,)
    return [img.crop((k * SIZE, 0, (k + 1) * SIZE, SIZE)) for k in range(3)]


WEATHER_EFFECTS = {
    "rain": (frame_rain, 4, 6),
    "snow": (frame_snowfall, 4, 2),
}


def frame_bottle(i):
    """A message in a bottle bobbing in the channel left of the flower's rock.
    It brings its own strip of water, so it shows even while the garden hides."""
    g = water(blank(), 0)
    top = [8, 8, 9, 9][i]
    stamp(g, top, 0, [".D.", ".G.", "GuG", "GXG", "GXG", "GuG", "GGG"])  # cork, neck, glass, note
    pool = water(blank(), 0)
    for r in range(14, 16):  # the water covers its underside
        for c in range(3):
            g[r][c] = pool[r][c]
    return g

# ---------------------------------------------------------------- holiday outfits
# Hats are 3 rows tall and sit *on* the head (there is only one free row above
# it in a 16x16 frame): their bottom row covers the head's top outline and the
# row below it. Keys match World.Holiday raw values.
OUTFITS = {
    "halloween": ["..K..", ".LLL.", "LLLLL"],                 # pumpkin hat
    "christmas": ["....MMX", ".MMMMM.", "XXXXXXX"],           # Santa hat
    "newYear": ["..X..", ".hmh.", "hmhmh"],                   # party hat
    "lunarNewYear": [".M.M.", "MMmMM", ".M.M."],              # red flower knot
}
NO_OUTFIT = {"submerged", "ripple"}  # no otter visible in these


# ---------------------------------------------------------------- holiday decor
# Animated extras drawn over the flower's frame (same 16x16 cell, transparent
# elsewhere) while a holiday is on. Keys match World.Holiday raw values.

def frame_decor_halloween(i):
    """A jack-o'-lantern bobbing in the water in front of the rock, its candle
    flickering, and a little bat flapping above the flower."""
    g = blank()
    top = [9, 9, 10, 10][i]
    glow = "y" if i in (0, 3) else "Y"
    stamp(g, top, 0, ["..K..", ".LjL.", "LyLyL", "LLLLL", "jyyyj"])
    put(g, [(top + 2, 1), (top + 2, 3), (top + 4, 1), (top + 4, 2), (top + 4, 3)], glow)
    # it floats: the water covers its bottom (same pattern as the garden's water)
    pool = water(blank(), 0)
    for r in range(14, 16):
        for c in range(5):
            if g[r][c] != ".":
                g[r][c] = pool[r][c]
    bat = [["v.....v", "vv.v.vv", ".vvvvv."], ["..v.v..", ".vvvvv.", "vv...vv"]][i % 2]
    stamp(g, [1, 2, 1, 0][i], 0, bat)
    return g


def frame_decor_christmas_pot(i):
    """Christmas: a string of tiny lights around the flower pot, twinkling."""
    g = blank()
    spots = [(8, 5), (9, 6), (8, 7), (9, 8), (8, 9), (9, 10)]
    colors = ["M", "m", "h", "k"]
    for k, spot in enumerate(spots):
        put(g, [spot], colors[(k + i) % len(colors)])
    return g


def frame_decor_christmas_tree(i):
    """Christmas: a little tree with a star on the meadow rock, lights blinking."""
    g = blank()
    stamp(g, 2, 11, ["..m..", "..K..", ".KKK.", ".KKK.", "KKKKK", ".KKK.", "KKKKK", "KKKKK", "..D.."])
    lights = [[(4, 13), (6, 12), (8, 14), (9, 12)], [(5, 12), (6, 14), (8, 11), (9, 14)]][i % 2]
    for k, spot in enumerate(lights):
        put(g, [spot], ["M", "m", "h", "y"][k])
    if i % 2:
        put(g, [(1, 13), (2, 12), (2, 14)], "y")  # the star twinkles
    return g


def bunting(g, i):
    """A string of little flags sagging across the meadow rock."""
    line = [(2, 0), (2, 1), (3, 2), (3, 3), (4, 4), (4, 5), (4, 6), (5, 7), (5, 8), (4, 9), (4, 10), (4, 11), (3, 12), (3, 13), (2, 14), (2, 15)]
    put(g, line, "R")
    colors = ["M", "m", "h", "f"]
    for k, (r, c) in enumerate(line[1::3]):
        color = colors[(k + i) % len(colors)]
        put(g, [(r + 1, c), (r + 1, c + 1), (r + 2, c + (i % 2))], color)  # flags flutter
    return g


def frame_decor_newyear_bunting(i):
    return bunting(blank(), i)


def frame_decor_newyear_fireworks(i):
    """New Year's nights: little fireworks bursting above the flower."""
    g = blank()
    bursts = [  # (row, col, radius, colour) per frame; radius 0 = a rocket going up
        [(6, 3, 0, "y")], [(3, 3, 0, "y")], [(2, 3, 1, "M")], [(2, 3, 2, "f")],
        [(2, 3, 3, "Y"), (6, 13, 0, "y")], [(3, 13, 0, "y")], [(2, 13, 1, "h")], [(2, 13, 2, "u")],
    ][i]
    for r, c, radius, color in bursts:
        if radius == 0:
            put(g, [(r, c), (r + 1, c)], color)
        else:
            put(g, [(r - radius, c), (r + radius, c), (r, c - radius), (r, c + radius),
                    (r - radius + 1, c - radius + 1), (r - radius + 1, c + radius - 1),
                    (r + radius - 1, c - radius + 1), (r + radius - 1, c + radius - 1)], color)
    return g


def frame_decor_lunar_lanterns(i):
    """Lunar New Year: two red lanterns on a string over the meadow rock, swaying."""
    g = blank()
    put(g, [(2, c) for c in range(16)], "D")
    for c in (4, 11):
        put(g, [(3, c)], "m")
        put(g, [(4, c - 1), (4, c), (4, c + 1), (5, c - 1), (5, c + 1), (6, c - 1), (6, c), (6, c + 1)], "M")
        put(g, [(5, c)], "m")
        put(g, [(7, c + (i % 2) - (1 if c == 11 and i % 2 else 0))], "m")  # tassels swing
    return g


# Over the flower's cell. A key "holiday@night" replaces the holiday's decor at night.
DECOR = {
    "halloween": (frame_decor_halloween, 4, 3),
    "christmas": (frame_decor_christmas_pot, 4, 2),
    "newYear@night": (frame_decor_newyear_fireworks, 8, 4),
}

# Over the meadow's cell (the long rock), same keys.
MEADOW_DECOR = {
    "christmas": (frame_decor_christmas_tree, 2, 2),
    "newYear": (frame_decor_newyear_bunting, 2, 2),
    "newYear@night": (frame_decor_newyear_bunting, 2, 2),
    "lunarNewYear": (frame_decor_lunar_lanterns, 2, 2),
}
DECOR_ROWS = len(DECOR) + len(MEADOW_DECOR)


# ---------------------------------------------------------------- radio props
# While the built-in radio plays, the theme's prop stands in the gap between
# the flower and Pibbo (columns 11-15 of the flower's cell; the left side is
# kept for holiday decor). A theme names its prop in theme.json ("prop").

def pebble(g):
    """A little stone for a prop to stand on, at the water line."""
    stamp(g, 11, 11, [".rrr.", "rrrrr", "RRRRR"])


def frame_prop_streetlamp(i):
    """Pibbo in the City: a tiny street lamp, its light flickering softly."""
    g = blank()
    pebble(g)
    stamp(g, 1, 12, ["qqq", "qyq", ".q."])
    put(g, [(r, 13) for r in range(4, 11)], "q")
    put(g, [(10, 12), (10, 14)], "q")
    if i % 2 == 0:
        put(g, [(2, 11), (2, 15), (4, 12), (4, 14)], "Y")  # glow
    else:
        put(g, [(2, 11), (2, 15)], "Y")
    return g


def frame_prop_teacup(i):
    """Solo Float: a cup of tea for one, steaming."""
    g = blank()
    pebble(g)
    stamp(g, 7, 11, ["oggo.", "oXXoo", "oXXoo", ".oo.."])
    put(g, [[(6, 12), (5, 13), (4, 12)], [(6, 13), (5, 12), (4, 13)]][i % 2], "W")
    return g


def frame_prop_paperboat(i):
    """Pibbo's Raft Days: a paper boat bobbing on the water."""
    g = blank()
    top = [8, 8, 9, 9][i]
    stamp(g, top, 11, ["..o..", ".oXo.", "oXXXo", "oXXXo", ".ooo."])
    pool = water(blank(), 0)
    for r in range(14, 16):  # it floats: the water covers its keel
        for c in range(11, 16):
            if g[r][c] != ".":
                g[r][c] = pool[r][c]
    return g


def frame_prop_handheld(i):
    """Pixel Tide: a little handheld game on a pebble, a dot hopping on its screen."""
    g = blank()
    pebble(g)
    stamp(g, 4, 11, ["ooooo", "orrro", "okkko", "okkko", "orrro", "oRrMo", "ooooo"])
    put(g, [[(6, 12)], [(7, 13)], [(6, 14)], [(7, 13)]][i], "m")  # the little game
    return g


PROPS = {
    "streetlamp": (frame_prop_streetlamp, 2, 2),
    "teacup": (frame_prop_teacup, 2, 2),
    "paperboat": (frame_prop_paperboat, 4, 2),
    "handheld": (frame_prop_handheld, 4, 3),
}


def wear(grid, hat):
    """Puts `hat` on the head: the topmost run of 4+ outline pixels (a raised
    paw or a heart above the head is never that wide)."""
    for r, row in enumerate(grid):
        line = "".join(row)
        start = line.find("oooo")
        if start >= 0:
            end = start
            while end < len(line) and line[end] == "o":
                end += 1
            middle = (start + end) // 2
            stamp(grid, r + 1 - (len(hat) - 1), middle - len(hat[0]) // 2, hat)
            return grid
    return grid

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
    "unplug": (frame_unplug, 4, 3),        # plays once when music stops
    "backfloat": (frame_backfloat, 4, 3),  # petted (rub)
    "holdpaw": (frame_holdpaw, 4, 2),      # cursor resting on him
    "look": (frame_look, 2, 2),            # a splash nearby
    "friendpaw": (frame_friendpaw, 4, 2),  # holding paws with the friend otter
    "admire": (frame_admire, 4, 2),        # looking up at a rainbow
    "game": (frame_game, 4, 3),            # playing the handheld while Pixel Tide plays
    "flip": (frame_flip, 6, 8),            # the secret: tap the water three times
    "ripple": (frame_ripple, 4, 7),        # splash effect, drawn over the water
    "note": (frame_note, 4, 2),            # reading a message in a bottle
    "wish": (frame_wish, 4, 3),            # wishing on a shooting star
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


# Clips that play once and hold their last frame.
ONE_SHOT = {"unplug", "ripple", "flip"}
# Beats one loop spans: with built-in music, the app plays these in time with
# the track (one nod per beat) instead of at their fps.
CLIP_BEATS = {"music": 2}


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
    "_": ["...", "...", "...", "...", "...", "...", "...", "###"],
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
    "♪": ["...hh.", "...hhh", "...h.h", "...h..", "...h..", ".hhh..", "hhhh..", ".hh...", "......"],
    "🐚": [".........", "....o....", "...oso...", "..osSso..", ".osSsSso.",
           "osSsSsSso", "oSsSsSsSo", ".ooooooo.", "........."],
    "🫧": [".....xx..", "....xuux.", "....xuux.", ".....xx..", ".xx......",
           "xuux..x..", "xuux.xux.", ".xx...x..", "........."],
    "✨": ["....m....", "....m....", "..mmmmm..", "....m....", "....m..m.", ".m.....mm",
          "mmm.....m", ".m.......", "........."],
    "💭": [".........", "..ooooo..", ".oXXXXXo.", "oXXXXXXXo", ".oXXXXXo.", "..ooooo..",
           "...oo....", "....o....", "........."],
    "🦀": [".........", "C.......C", "CC.....CC", ".C.e.e.C.", "..CCCCC..", ".CCCCCCC.",
           "..CCCCC..", ".Q.Q.Q.Q.", "........."],
    "🐦": [".........", "....RR...", "...RXXR..", "...RXeRm.", ".RRXXXR..", "RXXXXXR..",
           ".RXXXR...", "...m.m...", "........."],
    "🐟": [".........", ".........", "...LLL..L", "..LLLLLLL", ".LeLLLLL.", "..LLLLLLL",
           "...LLL..L", ".........", "........."],
    "🦦": [".........", "..ooooo..", ".obbbbbo.", ".oebbbeo.", ".obllllo.", ".oblnlbo.",
           "..obbbo..", "...ooo...", "........."],
    "🍾": ["....D....", "....G....", "...GuG...", "...GXG...", "...GXG...", "...GuG...",
           "...GGG...", ".........", "........."],
    "🌷": [".........", "...f.f...", "..fFfFf..", "..fFFFf..", "...fFf...", "....K....",
           "..k.K.k..", "...kKk...", "....K...."],
    "🌊": [".........", "...oooo..", "..oxxxxo.", ".oxxoooxo", ".oxo...o.",
           "oxxxo....", "xxxxxxxxx", "xuxxuxxux", "xxxxxxxxx"],
    "🎮": [".........", ".........", ".ooooooo.", "oHHHHHHHo", "oHuHHHmHo", "ouuuHmHMo",
           "oHuHHHMHo", "oHHoooHHo", ".oo...oo."],
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


# ---------------------------------------------------------------- water light
# The app recolours the bottom 3 (water) rows of every frame for the time of
# day; daytime keeps the colours above. Palette keys -> new RGB.
WATER_LIGHT = {
    "dawn": {"w": (160, 204, 214), "W": (255, 206, 198), "x": (124, 168, 192)},   # pale misty blue, pink sunrise glints
    "dusk": {"w": (238, 182, 100), "W": (255, 236, 166), "x": (204, 132, 84)},    # golden hour
    "night": {"w": (50, 86, 160), "W": (222, 212, 160), "x": (30, 52, 120)},      # deep blue, moon glints
}


def hex_rgb(rgb):
    return "%02x%02x%02x" % rgb


def light_water(img, time):
    """Python twin of the app's WaterTint, for previews."""
    swap = {PALETTE[k]: v for k, v in WATER_LIGHT[time].items()}
    img = img.copy()
    px = img.load()
    for y in range(img.height):
        if y % SIZE < SIZE - 3:
            continue
        for x in range(img.width):
            r, g_, b, a = px[x, y]
            if a == 255 and (r, g_, b) in swap:
                px[x, y] = swap[(r, g_, b)] + (255,)
    return img


# ---------------------------------------------------------------- app icon

ICON_TILE = 20  # pixel-art tile: Pibbo (16x16) with a little sky around him
ICON_SKY = (255, 236, 205)
ICON_SKY_LOW = (255, 216, 178)


def icon_tile():
    """Pibbo chilling in his pool, on a rounded tile."""
    n = ICON_TILE
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    px = img.load()
    for r in range(n):
        for c in range(n):
            px[c, r] = (ICON_SKY if r < 9 else ICON_SKY_LOW) + (255,)
    pool = water([["."] * n for _ in range(16)], 1)  # water rows 13-15 of a 16-row strip
    for r in range(13, 16):
        for c in range(n):
            px[c, r + 2] = PALETTE[pool[r][c % SIZE]] + (255,)
    for c in range(n):
        px[c, n - 2] = PALETTE["x"] + (255,)
        px[c, n - 1] = PALETTE["x"] + (255,)
    img.alpha_composite(to_image(frame_chill(0)), (2, 2))
    sun = [(2, 15), (2, 16), (3, 15), (3, 16), (1, 14), (1, 17), (4, 14), (4, 17)]  # 2x2 sun, 4 sparkles
    for r, c in sun:
        px[c, r] = PALETTE["m"] + (255,)
    # rounded corners: clear a 2-pixel staircase at each corner
    for r, c in [(0, 0), (0, 1), (1, 0)]:
        for rr, cc in [(r, c), (r, n - 1 - c), (n - 1 - r, c), (n - 1 - r, n - 1 - c)]:
            px[cc, rr] = (0, 0, 0, 0)
    return img


def build_icon():
    """AppIcon.icns: the tile on Apple's icon grid (824 of 1024 px), crisp."""
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    tile = icon_tile()

    def render(size):
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        cell = max(1, round(size * 824 / 1024 / ICON_TILE))
        art = tile.resize((ICON_TILE * cell, ICON_TILE * cell), Image.NEAREST)
        if art.width > size:  # tiny sizes: fit the whole tile
            art = tile.resize((size, size), Image.NEAREST)
        canvas.alpha_composite(art, ((size - art.width) // 2, (size - art.height) // 2))
        return canvas

    render(1024).save(ICON_DIR / "AppIcon.png")
    if not shutil.which("iconutil"):
        return
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for base_size in (16, 32, 128, 256, 512):
            render(base_size).save(iconset / f"icon_{base_size}x{base_size}.png")
            render(base_size * 2).save(iconset / f"icon_{base_size}x{base_size}@2x.png")
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ICON_DIR / "AppIcon.icns")], check=True)


# ---------------------------------------------------------------- skin

def build_skin():
    SKIN_DIR.mkdir(parents=True, exist_ok=True)
    entries = list(STATES.items()) + list(ACTIONS.items()) + list(TRANSITIONS.items())
    visits = {name: fn() for name, fn in VISITORS.items()}
    max_frames = max(max(n for _, (_, n, _) in entries), GARDEN_STAGES, MEADOW_STAGES, VISIT_WRAP)
    visit_rows = {name: -(-len(fn()[0]) // VISIT_WRAP) for name, fn in VISITORS.items()}
    rows = len(entries) + 1 + len(OUTFITS) * len(entries) + DECOR_ROWS + len(PROPS) + 6 + len(WEATHER_EFFECTS) + sum(visit_rows.values()) + len(DRIFT_SEASONS)
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

    # Every clip again per outfit; a clip's outfit row = its row + offset.
    outfit_offsets = {}
    for k, (outfit, hat) in enumerate(OUTFITS.items()):
        offset = garden_row + 1 + k * len(entries)
        outfit_offsets[outfit] = offset
        for row, (name, (fn, n, _)) in enumerate(entries):
            for i in range(n):
                grid = fn(i) if name in NO_OUTFIT else wear(fn(i), hat)
                sheet.paste(to_image(grid), (i * SIZE, (row + offset) * SIZE))

    decor_rows, meadow_decor_rows = {}, {}
    row = garden_row + 1 + len(OUTFITS) * len(entries)
    for table, rows_out, prefix in ((DECOR, decor_rows, "decor"), (MEADOW_DECOR, meadow_decor_rows, "meadowDecor")):
        for key, (fn, n, _) in table.items():
            rows_out[key] = row
            row += 1
            frames[f"{prefix}:{key}"] = [to_image(fn(i)) for i in range(n)]
            for i, f in enumerate(frames[f"{prefix}:{key}"]):
                sheet.paste(f, (i * SIZE, rows_out[key] * SIZE))

    prop_rows = {}
    for k, (name, (fn, n, _)) in enumerate(PROPS.items()):
        prop_rows[name] = garden_row + 1 + len(OUTFITS) * len(entries) + DECOR_ROWS + k
        frames[f"prop:{name}"] = [to_image(fn(i)) for i in range(n)]
        for i, f in enumerate(frames[f"prop:{name}"]):
            sheet.paste(f, (i * SIZE, prop_rows[name] * SIZE))
    meadow_row = garden_row + 1 + len(OUTFITS) * len(entries) + DECOR_ROWS + len(PROPS)
    meadow = [to_image(meadow_stage(s)) for s in range(MEADOW_STAGES)]
    for s, f in enumerate(meadow):
        sheet.paste(f, (s * SIZE, meadow_row * SIZE))
    bottle_row = meadow_row + 1
    frames["bottle"] = [to_image(frame_bottle(i)) for i in range(4)]
    for i, f in enumerate(frames["bottle"]):
        sheet.paste(f, (i * SIZE, bottle_row * SIZE))
    frames["meadow"] = meadow
    star_row = bottle_row + 1
    frames["shootingStar"] = [to_image(frame_shooting_star(i)) for i in range(SHOOTING_STAR_FRAMES)]
    for i, f in enumerate(frames["shootingStar"]):
        sheet.paste(f, (i * SIZE, star_row * SIZE))
    snow_row = star_row + 1
    for cell in range(2):
        sheet.paste(to_image(snow_cover(cell)), (cell * SIZE, snow_row * SIZE))
    weather_rows = {}
    for k, (name, (fn, n, _)) in enumerate(WEATHER_EFFECTS.items()):
        weather_rows[name] = snow_row + 1 + k
        frames[f"weather:{name}"] = [to_image(fn(i)) for i in range(n)]
        for i, f in enumerate(frames[f"weather:{name}"]):
            sheet.paste(f, (i * SIZE, weather_rows[name] * SIZE))
    visitor_rows = {}
    next_row = weather_rows[list(WEATHER_EFFECTS)[-1]] + 1
    for name, (grids, _, _) in visits.items():
        visitor_rows[name] = next_row
        next_row += visit_rows[name]
        frames[f"visitor:{name}"] = [to_image(grid) for grid in grids]
        for i, f in enumerate(frames[f"visitor:{name}"]):
            sheet.paste(f, ((i % VISIT_WRAP) * SIZE, (visitor_rows[name] + i // VISIT_WRAP) * SIZE))
    gift_row = next_row
    sheet.paste(to_image(gift_frame()), (0, gift_row * SIZE))
    frames["gift"] = [to_image(gift_frame())]
    rainbow_row = gift_row + 1
    frames["rainbow"] = rainbow_cells()
    for k, cell in enumerate(frames["rainbow"]):
        sheet.paste(cell, (k * SIZE, rainbow_row * SIZE))
    drift_rows = {}
    for k, season in enumerate(DRIFT_SEASONS):
        drift_rows[season] = rainbow_row + 1 + k
        for i in range(2):
            sheet.paste(to_image(frame_drift(season, i)), (i * SIZE, drift_rows[season] * SIZE))
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
        "meadow": {"row": meadow_row, "stages": MEADOW_STAGES},
        "bottle": {"row": bottle_row, "frames": 4, "fps": 2},
        "shootingStar": {"row": star_row, "frames": SHOOTING_STAR_FRAMES, "fps": 10, "loop": False},
        "moonGlint": {"glint": hex_rgb(PALETTE["W"]), "water": hex_rgb(PALETTE["w"])},
        "snowCover": {"row": snow_row, "stages": 2},
        "gift": {"row": gift_row, "stages": 1},
        "rainbow": {"row": rainbow_row, "stages": 3},
        "drift": {season: {"row": drift_rows[season], "frames": 2, "fps": 2} for season in DRIFT_SEASONS},
        "visitors": {name: {"row": visitor_rows[name], "frames": len(grids), "fps": fps, "wrap": VISIT_WRAP, "path": path}
                     for name, (grids, path, fps) in visits.items()},
        "weatherEffects": {name: {"row": weather_rows[name], "frames": n, "fps": fps}
                           for name, (_, n, fps) in WEATHER_EFFECTS.items()},
        "outfits": {name: {"offset": offset} for name, offset in outfit_offsets.items()},
        "poses": {name: pose_of(name) for name in list(STATES) + list(ACTIONS) if name not in NO_POSE},
        "transitions": {},
        "water": {time: {hex_rgb(PALETTE[k]): hex_rgb(v) for k, v in colors.items()}
                  for time, colors in WATER_LIGHT.items()},
        "props": {name: {"row": prop_rows[name], "frames": n, "fps": fps}
                  for name, (_, n, fps) in PROPS.items()},
        "decor": {key: {"row": decor_rows[key], "frames": n, "fps": fps} for key, (_, n, fps) in DECOR.items()},
        "meadowDecor": {key: {"row": meadow_decor_rows[key], "frames": n, "fps": fps}
                        for key, (_, n, fps) in MEADOW_DECOR.items()},
    }
    for row, (name, (_, n, fps)) in enumerate(entries):
        key = "states" if name in STATES else "actions" if name in ACTIONS else "transitions"
        manifest[key][name] = {"row": row, "frames": n, "fps": fps}
        if name in ONE_SHOT or key == "transitions":
            manifest[key][name]["loop"] = False
        if name in CLIP_BEATS:
            manifest[key][name]["beats"] = CLIP_BEATS[name]
    (SKIN_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    write_previews(entries, frames, garden, sheet)


def write_previews(entries, frames, garden, sheet):
    """Animated previews at 6x: every clip plus the garden stages, and every
    transition between two sample clips."""
    items = [(name, frames[name], fps) for name, (_, _, fps) in entries if name not in TRANSITIONS]
    items += [(f"flower {s}", [garden[s]], 1) for s in range(GARDEN_STAGES)]
    for name in PROPS:
        items.append((name, [Image.alpha_composite(garden[-1], f) for f in frames[f"prop:{name}"]], PROPS[name][2]))
    write_gif(items, SKIN_DIR / "preview.gif", 24)

    # The meadow filling up over the months (with the bloomed flower and Pibbo).
    strip = Image.new("RGBA", (MEADOW_STAGES * (SIZE * 3 * 4 + 8) + 8, SIZE * 4 + 16), (247, 242, 232, 255))
    for s in range(MEADOW_STAGES):
        scene = Image.new("RGBA", (SIZE * 3, SIZE))
        scene.alpha_composite(frames["meadow"][s], (0, 0))
        if s == 0:  # a bottle drifting in the channel (drawn under the garden, like the app)
            scene.alpha_composite(frames["bottle"][0], (SIZE, 0))
        scene.alpha_composite(garden[-1], (SIZE, 0))
        scene.alpha_composite(frames["chill"][0], (SIZE * 2, 0))
        strip.alpha_composite(scene.resize((SIZE * 3 * 4, SIZE * 4), Image.NEAREST), (8 + s * (SIZE * 3 * 4 + 8), 8))
    strip.save(SKIN_DIR / "preview-meadow.png")

    # Every visit across the whole pool, as the app plays it.
    visitor_gif(frames, garden)
    holiday_gif(frames, garden)

    # The tide pool through the day: flower + Pibbo, water coloured per time.
    scene = Image.new("RGBA", (SIZE * 2, SIZE))
    scene.alpha_composite(garden[-1], (0, 0))
    scene.alpha_composite(frames["chill"][0], (SIZE, 0))
    scale, pad = 6, 12
    strip = Image.new("RGBA", (4 * (SIZE * 2 * scale + pad) + pad, SIZE * scale + 2 * pad), (247, 242, 232, 255))
    for k, time in enumerate(["dawn", "day", "dusk", "night"]):
        lit = scene if time not in WATER_LIGHT else light_water(scene, time)
        strip.alpha_composite(lit.resize((SIZE * 2 * scale, SIZE * scale), Image.NEAREST), (pad + k * (SIZE * 2 * scale + pad), pad))
    strip.save(SKIN_DIR / "preview-water.png")

    # Each transition as "from, in-between, to", held a beat on both ends.
    sample = {"@up": "chill", "@low": "hidden", "@peek": "peek", "@under": "submerged", "@back": "backfloat"}
    sequences = []
    for key in TRANSITIONS:
        a, b = (sample.get(side, side) for side in key.split(">"))
        clip = [frames[a][0]] * 4 + frames[key] + [frames[b][0]] * (9 - len(frames[key]))
        sequences.append((key.replace("@", ""), clip, TRANSITION_FPS))
    write_gif(sequences, SKIN_DIR / "preview-transitions.gif", 13, tick=1 / TRANSITION_FPS)
    sheet.resize((sheet.width * 8, sheet.height * 8), Image.NEAREST).save(SKIN_DIR / "sprites@8x.png")


def holiday_gif(frames, garden):
    """preview-holidays.gif: each holiday's decor over the whole pool, Pibbo in his hat."""
    scale, ticks = 5, 16
    keys = list(dict.fromkeys(list(DECOR) + list(MEADOW_DECOR)))
    hats = {name: wear(frame_chill(0), hat) for name, hat in OUTFITS.items()}
    night = (40, 44, 66, 255)
    gif = []
    for t in range(ticks):
        row = Image.new("RGBA", (SIZE * 3 * len(keys) + 4 * (len(keys) - 1), SIZE), (247, 242, 232, 255))
        for k, key in enumerate(keys):
            holiday = key.split("@")[0]
            scene = Image.new("RGBA", (SIZE * 3, SIZE), night if key.endswith("@night") else (247, 242, 232, 255))
            scene.alpha_composite(frames["meadow"][-1], (0, 0))
            scene.alpha_composite(garden[-1], (SIZE, 0))
            for prefix, table, x in (("meadowDecor", MEADOW_DECOR, 0), ("decor", DECOR, SIZE)):
                if key in table:
                    clip = frames[f"{prefix}:{key}"]
                    scene.alpha_composite(clip[(t * table[key][2] // 4) % len(clip)], (x, 0))
            scene.alpha_composite(to_image(hats[holiday]), (SIZE * 2, 0))
            row.alpha_composite(scene, (k * (SIZE * 3 + 4), 0))
        gif.append(row.resize((row.width * scale, SIZE * scale), Image.NEAREST).convert("RGB"))
    gif[0].save(SKIN_DIR / "preview-holidays.gif", save_all=True, append_images=gif[1:], duration=250, loop=0)


def visitor_gif(frames, garden):
    """preview-visitors.gif: each visit in turn over the full pool (meadow, flower, Pibbo)."""
    scale = 5
    reaction = {"friend": "friendpaw"}
    gif = []
    durations = []
    for name, fn in VISITORS.items():
        _, path, fps = fn()
        pet = frames[reaction.get(name, "look")]
        for i, sprite in enumerate(frames[f"visitor:{name}"]):
            scene = Image.new("RGBA", (SIZE * 3, SIZE), (247, 242, 232, 255))
            scene.alpha_composite(frames["meadow"][-1], (0, 0))
            if name == "seagullGift" and i == len(frames[f"visitor:{name}"]) - 1:
                scene.alpha_composite(frames["gift"][0], (0, 0))  # and there it stays
            scene.alpha_composite(garden[-1], (SIZE, 0))
            scene.alpha_composite(pet[i % len(pet)], (SIZE * 2, 0))
            layer = Image.new("RGBA", scene.size)
            x = path[i]
            if x < 0:
                sprite = sprite.crop((-x, 0, SIZE, SIZE))
                x = 0
            layer.paste(sprite, (x, 0))
            scene.alpha_composite(layer)
            gif.append(scene.resize((SIZE * 3 * scale, SIZE * scale), Image.NEAREST).convert("RGB"))
            durations.append(int(1000 / fps))
        durations[-1] += 600  # a pause between visitors
    gif[0].save(SKIN_DIR / "preview-visitors.gif", save_all=True, append_images=gif[1:], duration=durations, loop=0)


def write_gif(items, path, ticks, tick=1 / 12):
    scale, pad, label_h, per_row = 6, 12, 22, 7
    cell = SIZE * scale
    n_rows = (len(items) + per_row - 1) // per_row
    width = per_row * (cell + pad) + pad
    height = n_rows * (cell + label_h + pad) + pad
    try:
        font = ImageFont.load_default(size=13)
    except TypeError:
        font = ImageFont.load_default()
    gif_frames = []
    for t in range(ticks):
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
    gif_frames[0].save(path, save_all=True, append_images=gif_frames[1:], duration=int(tick * 1000), loop=0)


# ---------------------------------------------------------------- games (Game time 🎮)
# One sheet for every game: the window frame around the 160x120 playfield,
# the close button, and each game's art keyed "<game id>.<name>" in games.json.

GAME_W, GAME_H = 160, 120          # playfield, art pixels (Games.Playfield)
CHROME_W = GAME_W + 8              # 1 outline + 2 wood + 1 inner outline, each side
TITLE_H = 13                       # outline row + 12 rows of title bar
CHROME_H = TITLE_H + 1 + GAME_H + 4
PLAYFIELD_X, PLAYFIELD_Y = 4, TITLE_H + 1
WOOD = (214, 176, 126)
WOOD_LIGHT = (234, 204, 158)
WOOD_DARK = (176, 136, 94)
HOVER = (207, 234, 247)  # the menu's hover highlight
GAME_WATER_Y = 101       # top of the water in the Shell Catch background


def game_chrome():
    """The frame: a cream title bar like the speech bubbles, driftwood sides,
    a transparent hole for the playfield, rounded outer corners."""
    img = Image.new("RGBA", (CHROME_W, CHROME_H), (0, 0, 0, 0))
    px = img.load()
    for y in range(CHROME_H):
        for x in range(CHROME_W):
            edge = x in (0, CHROME_W - 1) or y in (0, CHROME_H - 1)
            if edge:
                px[x, y] = TEXT + (255,)
            elif y < TITLE_H:
                px[x, y] = BUBBLE_FILL + (255,)
            else:
                shade = WOOD_LIGHT if (x + y) % 7 == 0 else WOOD_DARK if (x * 3 + y) % 11 == 0 else WOOD
                px[x, y] = shade + (255,)
    # inner outline around the playfield, and the hole itself
    for x in range(PLAYFIELD_X - 1, PLAYFIELD_X + GAME_W + 1):
        px[x, PLAYFIELD_Y - 1] = TEXT + (255,)
        px[x, PLAYFIELD_Y + GAME_H] = TEXT + (255,)
    for y in range(PLAYFIELD_Y - 1, PLAYFIELD_Y + GAME_H + 1):
        px[PLAYFIELD_X - 1, y] = TEXT + (255,)
        px[PLAYFIELD_X + GAME_W, y] = TEXT + (255,)
    for y in range(PLAYFIELD_Y, PLAYFIELD_Y + GAME_H):
        for x in range(PLAYFIELD_X, PLAYFIELD_X + GAME_W):
            px[x, y] = (0, 0, 0, 0)
    # rounded outer corners
    w, h = CHROME_W - 1, CHROME_H - 1
    for cx, cy, dx, dy in ((0, 0, 1, 1), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1)):
        px[cx, cy] = (0, 0, 0, 0)
        px[cx + dx, cy] = (0, 0, 0, 0)
        px[cx, cy + dy] = (0, 0, 0, 0)
        px[cx + dx, cy + dy] = TEXT + (255,)
    return img


CLOSE = [".........", ".o.....o.", "..o...o..", "...o.o...", "....o....",
         "...o.o...", "..o...o..", ".o.....o.", "........."]


def game_close():
    """Close button: normal, then under the pointer."""
    img = Image.new("RGBA", (18, 9), (0, 0, 0, 0))
    img.alpha_composite(to_image(CLOSE, {"o": TEXT, ".": BUBBLE_FILL}), (0, 0))
    img.alpha_composite(to_image(CLOSE, {"o": TEXT, ".": HOVER}), (9, 0))
    return img


def shellcatch_background():
    """A calm afternoon sea: warm sky, two clouds, the water along the bottom."""
    img = Image.new("RGBA", (GAME_W, GAME_H), (0, 0, 0, 255))
    px = img.load()
    sky = [(255, 240, 214), (255, 232, 200), (255, 222, 186), (252, 212, 176)]
    for y in range(GAME_H):
        for x in range(GAME_W):
            if y < GAME_WATER_Y:
                band = min(y * len(sky) // GAME_WATER_Y, len(sky) - 1)
                # dither the band edges a little
                if band + 1 < len(sky) and (y * len(sky)) % GAME_WATER_Y > GAME_WATER_Y - 6 and (x + y) % 2 == 0:
                    band += 1
                px[x, y] = sky[band] + (255,)
            elif y == GAME_WATER_Y:
                px[x, y] = PALETTE["W"] + (255,) if (x // 3) % 4 != 3 else PALETTE["w"] + (255,)
            elif y < GAME_WATER_Y + 7:
                glint = (x * 7 + y * 13) % 23 == 0
                px[x, y] = (PALETTE["W"] if glint else PALETTE["w"]) + (255,)
            else:
                glint = (x * 5 + y * 11) % 29 == 0
                px[x, y] = (PALETTE["w"] if glint else PALETTE["x"]) + (255,)
    cloud = ["....XXX.....", "..XXXXXXX...", ".XXXXXXXXXX.", "XXXXXXXXXXXX"]
    for left, top in ((22, 18), (112, 30)):
        img.alpha_composite(to_image(cloud, {"X": (255, 250, 240)}), (left, top))
    sun = ["..mmm..", ".mmmmm.", "mmmmmmm", "mmmmmmm", "mmmmmmm", ".mmmmm.", "..mmm.."]
    img.alpha_composite(to_image(sun, {"m": (255, 214, 120)}), (126, 20))
    return img


def shellcatch_pibbo(i):
    """Pibbo on his back, bobbing a pixel (16x8; no water: the background has it)."""
    g = [["."] * SIZE for _ in range(8)]
    stamp(g, 1 + [0, 0, 1, 1][i], 0, BACK_BODY)
    return g


def build_games():
    """games.png + games.json: the game window frame and every game's art."""
    GAMES_DIR.mkdir(parents=True, exist_ok=True)
    chrome = game_chrome()
    close = game_close()
    background = shellcatch_background()
    pibbo = [to_image(shellcatch_pibbo(i)) for i in range(4)]

    width = max(CHROME_W, GAME_W)
    y_close = CHROME_H
    y_bg = y_close + close.height
    y_pibbo = y_bg + GAME_H
    sheet = Image.new("RGBA", (width, y_pibbo + 8), (0, 0, 0, 0))
    sheet.alpha_composite(chrome, (0, 0))
    sheet.alpha_composite(close, (0, y_close))
    sheet.alpha_composite(background, (0, y_bg))
    for i, frame in enumerate(pibbo):
        sheet.alpha_composite(frame, (i * SIZE, y_pibbo))
    sheet.save(GAMES_DIR / "games.png")

    meta = {
        "chrome": {
            "frame": {"x": 0, "y": 0, "w": CHROME_W, "h": CHROME_H, "frames": 1},
            "playfieldX": PLAYFIELD_X, "playfieldY": PLAYFIELD_Y,
            "titleX": 6, "titleY": 3,
            "close": {"x": 0, "y": y_close, "w": 9, "h": 9, "frames": 2},
            "closeX": CHROME_W - 12, "closeY": 2,
        },
        "items": {
            "shellCatch.background": {"x": 0, "y": y_bg, "w": GAME_W, "h": GAME_H, "frames": 1},
            "shellCatch.pibbo": {"x": 0, "y": y_pibbo, "w": SIZE, "h": 8, "frames": 4},
        },
    }
    (GAMES_DIR / "games.json").write_text(json.dumps(meta, indent=1) + "\n")

    # preview: the window as it looks before a round
    preview = chrome.copy()
    preview.alpha_composite(background, (PLAYFIELD_X, PLAYFIELD_Y))
    preview.alpha_composite(pibbo[0], (PLAYFIELD_X + (GAME_W - SIZE) // 2, PLAYFIELD_Y + 96))
    preview.alpha_composite(close.crop((0, 0, 9, 9)), (CHROME_W - 12, 2))
    preview.resize((CHROME_W * 4, CHROME_H * 4), Image.NEAREST).save(GAMES_DIR / "preview-games.png")


def main():
    build_skin()
    build_ui()
    build_games()
    build_icon()
    print(f"wrote {SKIN_DIR.relative_to(ROOT)}, {UI_DIR.relative_to(ROOT)}, {GAMES_DIR.relative_to(ROOT)} and {ICON_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
