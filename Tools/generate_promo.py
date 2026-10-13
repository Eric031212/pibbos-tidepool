#!/usr/bin/env python3
"""Render social-media promo images from Tidepool's own pixel art.

Every poster is composed at 270x338 "art pixels" with the real sprites,
pixel font and bubble frame, then scaled 4x with nearest-neighbour to
1080x1350 (4:5, fits Instagram / Xiaohongshu / X), so it stays crisp and
on-brand. Run Tools/generate_sprites.py first if the art changed.

Outputs: Marketing/promo/01-*.png ... 09-*.png

Usage:
    python3 Tools/generate_promo.py

Requires: Python 3.10+, Pillow
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Marketing/promo"
W, H, SCALE = 270, 338, 4

CREAM = (247, 242, 232)
BROWN = (62, 42, 31)
SOFT = (140, 110, 90)
WATER = (111, 183, 217)
FOAM = (191, 230, 245)
DEEP = (76, 147, 189)
WHITE = (255, 250, 238)

UI = json.loads((ROOT / "Assets/UI/ui.json").read_text())
ATLAS = Image.open(ROOT / "Assets/UI/ui.png").convert("RGBA")
MANIFEST = json.loads((ROOT / "Assets/Skins/pibbo/manifest.json").read_text())
SHEET = Image.open(ROOT / "Assets/Skins/pibbo/sprites.png").convert("RGBA")
FS = MANIFEST["frameSize"]
LH = UI["lineHeight"]


# ---------------------------------------------------------------- building blocks

def sprite(name, frame=0, scale=1):
    clip = MANIFEST["states"].get(name) or MANIFEST["actions"][name]
    img = SHEET.crop((frame * FS, clip["row"] * FS, (frame + 1) * FS, (clip["row"] + 1) * FS))
    return img.resize((FS * scale, FS * scale), Image.NEAREST)


def flower(stage, scale=1):
    row = MANIFEST["garden"]["row"]
    img = SHEET.crop((stage * FS, row * FS, (stage + 1) * FS, (row + 1) * FS))
    return img.resize((FS * scale, FS * scale), Image.NEAREST)


def text(s, color=BROWN, scale=1):
    """Pixel-font text; plain glyphs are recoloured, emoji icons keep their colours."""
    pieces = []
    for ch in s:
        key = ch.replace("️", "")
        g = UI["glyphs"].get(key) or UI["glyphs"]["?"]
        glyph = ATLAS.crop((g["x"], g["y"], g["x"] + g["w"], g["y"] + LH))
        if len(key.encode("utf-8")) == 1:  # ASCII: recolour
            solid = Image.new("RGBA", glyph.size, color + (255,))
            solid.putalpha(glyph.getchannel("A"))
            glyph = solid
        pieces.append(glyph)
    width = sum(p.width for p in pieces) + UI["letterSpacing"] * max(0, len(pieces) - 1)
    img = Image.new("RGBA", (max(width, 1), LH), (0, 0, 0, 0))
    x = 0
    for p in pieces:
        img.alpha_composite(p, (x, 0))
        x += p.width + UI["letterSpacing"]
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


def bubble(lines):
    """Speech bubble from the 9-slice frame and tail in the UI atlas."""
    texts = [text(l) for l in lines]
    pad = UI["padding"]
    gap = 3
    bw = max(t.width for t in texts) + 2 * pad["x"]
    bh = len(texts) * LH + (len(texts) - 1) * gap + pad["top"] + pad["bottom"]
    tail = UI["tail"]
    img = Image.new("RGBA", (bw, bh + tail["h"] - 1), (0, 0, 0, 0))
    b, c = UI["bubble"], UI["bubble"]["corner"]
    size = b["size"]

    def part(sx, sy, sw, sh, dx, dy, dw, dh):
        if dw > 0 and dh > 0:
            piece = ATLAS.crop((b["x"] + sx, b["y"] + sy, b["x"] + sx + sw, b["y"] + sy + sh))
            img.alpha_composite(piece.resize((dw, dh), Image.NEAREST), (dx, dy))

    mw, mh = bw - 2 * c, bh - 2 * c
    part(0, 0, c, c, 0, 0, c, c)
    part(size - c, 0, c, c, bw - c, 0, c, c)
    part(0, size - c, c, c, 0, bh - c, c, c)
    part(size - c, size - c, c, c, bw - c, bh - c, c, c)
    part(c, 0, 1, c, c, 0, mw, c)
    part(c, size - c, 1, c, c, bh - c, mw, c)
    part(0, c, c, 1, 0, c, c, mh)
    part(size - c, c, c, 1, bw - c, c, c, mh)
    part(c, c, 1, 1, c, c, mw, mh)
    t = ATLAS.crop((tail["x"], tail["y"], tail["x"] + tail["w"], tail["y"] + tail["h"]))
    img.alpha_composite(t, (bw - 4 - tail["w"], bh - 1))
    for i, t in enumerate(texts):
        img.alpha_composite(t, (pad["x"], pad["top"] + i * (LH + gap)))
    return img


def water_band(canvas, top, height=8, phase=0):
    d = ImageDraw.Draw(canvas)
    d.rectangle((0, top, W, top + height), fill=WATER)
    for x in range(W):
        if (x + phase) % 5 == 0:
            canvas.putpixel((x, top), FOAM)
        if (x + phase) % 3:
            for y in range(top + height - 2, top + height + 1):
                canvas.putpixel((x, y), DEEP)


def poster(title, lines, footer=True):
    canvas = Image.new("RGBA", (W, H), CREAM + (255,))
    t = text(title, scale=2)
    canvas.alpha_composite(t, ((W - t.width) // 2, 18))
    # Captions at 2x when they fit, so they read on a phone.
    rendered = [text(line, color=SOFT, scale=2) for line in lines]
    rendered = [r if r.width <= W - 16 else text(line, color=SOFT) for r, line in zip(rendered, lines)]
    y = H - 30 - sum(r.height + 4 for r in rendered)
    for img in rendered:
        canvas.alpha_composite(img, ((W - img.width) // 2, y))
        y += img.height + 4
    water_band(canvas, H - 22, 14)
    if footer:
        tag = text("pibbo's tidepool", color=WHITE)
        canvas.alpha_composite(tag, ((W - tag.width) // 2, H - 15))
    return canvas


def center(canvas, img, y):
    canvas.alpha_composite(img, ((W - img.width) // 2, y))


def save(canvas, name):
    OUT.mkdir(parents=True, exist_ok=True)
    big = canvas.resize((W * SCALE, H * SCALE), Image.NEAREST).crop((0, 0, 1080, 1350))
    big.convert("RGB").save(OUT / name)
    print(f"wrote {(OUT / name).relative_to(ROOT)}")


def labelled(canvas, img, label, x, y):
    canvas.alpha_composite(img, (x, y))
    t = text(label, color=SOFT)
    canvas.alpha_composite(t, (x + (img.width - t.width) // 2, y + img.height + 4))


def desktop(canvas, top, height, pibbo="chill", with_flower=True):
    """A tiny pixel Mac desktop with Pibbo in the corner above the Dock."""
    left, right = 16, W - 16
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((left - 3, top - 3, right + 3, top + height + 3), radius=6, fill=BROWN)
    bands = [(170, 205, 222), (178, 212, 226), (188, 219, 230), (199, 226, 234), (212, 233, 238)]
    for i, color in enumerate(bands):
        y0 = top + i * height // len(bands)
        d.rectangle((left, y0, right, top + (i + 1) * height // len(bands)), fill=color)
    d.rectangle((left, top, right, top + 5), fill=(236, 236, 240))                 # menu bar
    d.rectangle((left + 22, top + 20, left + 150, top + 100), fill=WHITE)          # a window
    d.rectangle((left + 22, top + 20, left + 150, top + 27), fill=(222, 216, 206))
    for k, color in enumerate([(232, 110, 100), (240, 190, 90), (120, 190, 110)]):
        d.rectangle((left + 26 + k * 5, top + 22, left + 28 + k * 5, top + 24), fill=color)
    for row in range(5):
        d.rectangle((left + 30, top + 34 + row * 10, left + 30 + [100, 80, 110, 60, 90][row], top + 36 + row * 10), fill=(214, 206, 194))
    dock_top = top + height - 16
    d.rounded_rectangle((left + 50, dock_top, right - 50, top + height - 4), radius=4, fill=(226, 232, 238))
    colors = [(108, 123, 168), (232, 110, 100), (120, 190, 110), (240, 190, 90), (96, 168, 160), (200, 140, 200)]
    for k, color in enumerate(colors):
        x = left + 58 + k * 16
        d.rounded_rectangle((x, dock_top + 2, x + 9, dock_top + 10), radius=2, fill=color)
    pet = sprite(pibbo, 0, 2)
    canvas.alpha_composite(pet, (right - pet.width, dock_top - pet.height - 1))
    if with_flower:
        canvas.alpha_composite(flower(5, 2), (right - 2 * pet.width, dock_top - pet.height - 1))
    return right - pet.width, dock_top - pet.height - 1


# ---------------------------------------------------------------- posters

def p01_cover():
    c = poster("Pibbo's Tidepool", ["a tiny pixel otter", "for your Mac"])
    sub = text("no to-dos. no timers. just company.", color=SOFT)
    center(c, sub, 46)
    c.alpha_composite(flower(5, 6), (W // 2 - 100, 112))
    c.alpha_composite(sprite("chill", 0, 6), (W // 2 - 4, 112))
    note = bubble(["hi :)"])
    note = note.resize((note.width * 2, note.height * 2), Image.NEAREST)
    c.alpha_composite(note, (W // 2 + 52 - note.width + 30, 74))
    save(c, "01-cover.png")


def p02_corner():
    c = poster("He lives in the corner", ["hidden most of the time.", "peeks out when you say hi."])
    x, y = desktop(c, 60, 170, pibbo="peek")
    save(c, "02-corner.png")


def p03_hover():
    c = poster("Hover to say hi", ["he floats for a bit,", "then sinks back down."])
    states = ["hidden", "peek", "chill"]
    for k, name in enumerate(states):
        x = 20 + k * 84
        labelled(c, sprite(name, 0, 4), name, x, 110)
        if k < 2:
            arrow = text(">", scale=2)
            c.alpha_composite(arrow, (x + 68, 136))
    save(c, "03-hover.png")


def p04_busy():
    c = poster("He keeps busy", ["little moments while he's out."])
    items = [("water", 2, "watering"), ("crack", 1, "shell snack"), ("groom", 0, "grooming"), ("stretch", 1, "big stretch")]
    for k, (name, frame, label) in enumerate(items):
        labelled(c, sprite(name, frame, 4), label, 40 + (k % 2) * 126, 60 + (k // 2) * 100)
    save(c, "04-busy.png")


def p05_weather():
    c = poster("Your weather, his mood", ["sun, rain, snow, stars:", "he notices."])
    items = [("sunbathe", 1, "sunny", (196, 228, 244)), ("raindrops", 1, "rainy", (150, 168, 186)),
             ("cocoa", 0, "snowy", (176, 188, 204)), ("stargaze", 3, "starry night", (40, 52, 88))]
    d = ImageDraw.Draw(c)
    for k, (name, frame, label, sky) in enumerate(items):
        x, y = 34 + (k % 2) * 126, 58 + (k // 2) * 100
        d.rounded_rectangle((x - 6, y - 6, x + 70, y + 64), radius=6, fill=sky)  # a bit of sky behind him
        labelled(c, sprite(name, frame, 4), label, x + 3, y)
    save(c, "05-weather.png")


def p06_flower():
    c = poster("His flower grows", ["a little every day.", "no chores. it never wilts."])
    days = [1, 2, 4, 7, 11, 14]
    for k, day in enumerate(days):
        x = 8 + (k % 3) * 88
        y = 62 + (k // 3) * 92
        labelled(c, flower(k, 4), f"day {day}", x + 12, y)
    save(c, "06-flower.png")


def p07_music():
    c = poster("Music Time?", ["his own lofi track.", "vibes with Apple Music too."])
    pet = sprite("music", 0, 6)
    center(c, pet, 96)
    b = bubble(["Music Time? 🎧"]).resize((0, 0)) if False else bubble(["Music Time? 🎧"])
    b2 = b.resize((b.width * 2, b.height * 2), Image.NEAREST)
    c.alpha_composite(b2, (W // 2 + 30 - b2.width + 20, 58))
    save(c, "07-music.png")


def p08_dive():
    c = poster("Dive time", ["need to focus?", "he dives and leaves you be."])
    b = bubble(["Dive time 🫧"])
    b2 = b.resize((b.width * 2, b.height * 2), Image.NEAREST)
    center(c, b2, 58)
    labelled(c, sprite("chill", 0, 4), "click", 50, 120)
    c.alpha_composite(text(">", scale=2), (W // 2 - 4, 146))
    labelled(c, sprite("submerged", 1, 4), "splash", 156, 120)
    save(c, "08-dive.png")


def p09_light():
    c = poster("Light as a bubble", ["free & open source", "github.com/Eric031212/pibbos-tidepool"])
    facts = ["0 permission prompts", "~0% CPU when idle", "~13 MB of memory", "hides in fullscreen + lock"]
    y = 58
    for fact in facts:
        c.alpha_composite(text("🫧", scale=2), (14, y))
        c.alpha_composite(text(fact, scale=2), (38, y))
        y += 26
    c.alpha_composite(sprite("sleep", 0, 4), (W // 2 - 32, 170))
    save(c, "09-light.png")


def main():
    for make in [p01_cover, p02_corner, p03_hover, p04_busy, p05_weather, p06_flower, p07_music, p08_dive, p09_light]:
        make()


if __name__ == "__main__":
    main()
