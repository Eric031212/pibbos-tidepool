#!/usr/bin/env python3
"""Render the 30-second vertical promo video from Tidepool's own pixel art.

Every frame is composed at 270x480 "art pixels" from the real sprites, pixel
font and bubble frame, scaled 4x (nearest-neighbour) to 1080x1920 at 30 fps,
and piped into ffmpeg with "Floating Pibbo" as the soundtrack. The app scenes
are re-enacted with the real animation clips (not a screen recording).

Output: Marketing/video/pibbos-tidepool-promo.mp4 (+ a cover PNG)

Usage:
    python3 Tools/generate_promo_video.py

Requires: Python 3.10+, Pillow, ffmpeg. Run Tools/generate_sprites.py first
if the art changed.
"""
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_promo as promo  # noqa: E402  (shared pixel helpers)
import generate_sprites as art  # noqa: E402  (palette, for the "code" scene)

ROOT = promo.ROOT
OUT = ROOT / "Marketing/video"
VW, VH, SCALE, FPS = 270, 480, 4, 30

CREAM, BROWN, SOFT, WHITE = promo.CREAM, promo.BROWN, promo.SOFT, promo.WHITE
NIGHT = (24, 30, 48)
TRACK_MASTER = ROOT / "Assets/MusicMasters/Pibbo's Raft Days/Floating Pibbo.wav"
TRACK_BUNDLED = ROOT / "Assets/Music/pibbos-raft-days/floating-pibbo.caf"

CURSOR = [
    "o.........", "oo........", "oWo.......", "oWWo......", "oWWWo.....",
    "oWWWWo....", "oWWWWWo...", "oWWWWWWo..", "oWWWWoooo.", "oWWoWo....",
    "oWo.oWo...", "oo..oWo...", "o....oWo..", ".....oo...",
]


# ---------------------------------------------------------------- helpers

def clip(name, t, scale):
    """Frame of a clip `t` seconds after it started (loops or holds)."""
    spec = promo.MANIFEST["states"].get(name) or promo.MANIFEST["actions"][name]
    index = int(t * spec["fps"])
    index = index % spec["frames"] if spec.get("loop", True) else min(index, spec["frames"] - 1)
    return promo.sprite(name, index, scale)


def canvas(color=CREAM):
    return Image.new("RGBA", (VW, VH), color + (255,))


def center_text(c, s, y, scale=1, color=BROWN):
    img = promo.text(s, color=color, scale=scale)
    if img.width > VW - 12 and scale > 1:
        img = promo.text(s, color=color, scale=1)
    c.alpha_composite(img, ((VW - img.width) // 2, y))
    return img.height


def caption(c, s, y=34, color=BROWN):
    """A cream caption plate so text reads over any background."""
    img = promo.text(s, color=color, scale=2)
    if img.width > VW - 24:
        img = promo.text(s, color=color, scale=1)
    d = ImageDraw.Draw(c)
    x = (VW - img.width) // 2
    d.rounded_rectangle((x - 8, y - 6, x + img.width + 8, y + img.height + 5), radius=5, fill=promo.WHITE, outline=BROWN)
    c.alpha_composite(img, (x, y))


def cursor(c, x, y, pressed=False):
    img = art.to_image(CURSOR, {"o": BROWN, "W": WHITE})
    img = img.resize((img.width * 2, img.height * 2), Image.NEAREST)
    if pressed:
        d = ImageDraw.Draw(c)
        for r in (6, 9):
            d.ellipse((x - r, y - r, x + r, y + r), outline=WHITE)
    c.alpha_composite(img, (int(x), int(y)))


def lerp(a, b, t):
    return a + (b - a) * max(0.0, min(1.0, t))


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- the desktop and the pool

POOL_SCALE = 5
CELL = 16 * POOL_SCALE          # 64 art px per sprite cell
DOCK_TOP = VH - 34
POOL_X = VW - 2 * CELL - 8      # flower cell, then Pibbo
POOL_Y = DOCK_TOP - CELL - 2
PIBBO_CENTER = (POOL_X + CELL + CELL // 2, POOL_Y + CELL // 2)
WATER_SPOT = (POOL_X + CELL // 2, POOL_Y + CELL - 6)


def desktop():
    c = canvas()
    d = ImageDraw.Draw(c)
    bands = [(170, 205, 222), (178, 212, 226), (188, 219, 230), (199, 226, 234), (212, 233, 238)]
    for i, color in enumerate(bands):
        d.rectangle((0, i * VH // 5, VW, (i + 1) * VH // 5), fill=color)
    d.rectangle((0, 0, VW, 8), fill=(236, 236, 240))
    d.rectangle((18, 84, 200, 290), fill=WHITE)
    d.rectangle((18, 84, 200, 94), fill=(222, 216, 206))
    for k, color in enumerate([(232, 110, 100), (240, 190, 90), (120, 190, 110)]):
        d.rectangle((23 + k * 7, 87, 26 + k * 7, 90), fill=color)
    for row in range(9):
        d.rectangle((28, 106 + row * 18, 28 + [150, 120, 160, 90, 140, 110, 155, 70, 130][row], 109 + row * 18), fill=(214, 206, 194))
    d.rounded_rectangle((26, DOCK_TOP, VW - 26, VH - 8), radius=6, fill=(226, 232, 238))
    colors = [(108, 123, 168), (232, 110, 100), (120, 190, 110), (240, 190, 90), (96, 168, 160), (200, 140, 200), (90, 160, 220)]
    for k, color in enumerate(colors):
        x = 36 + k * 30
        d.rounded_rectangle((x, DOCK_TOP + 5, x + 20, DOCK_TOP + 24), radius=4, fill=color)
    return c


def pool(c, pibbo, t, flower=True, stage=5, ripple_t=None):
    if flower:
        c.alpha_composite(promo.flower(stage, POOL_SCALE), (POOL_X, POOL_Y))
    if ripple_t is not None and ripple_t >= 0:
        spec = promo.MANIFEST["actions"]["ripple"]
        if ripple_t < spec["frames"] / spec["fps"]:
            c.alpha_composite(clip("ripple", ripple_t, POOL_SCALE), (WATER_SPOT[0] - CELL // 2, POOL_Y))
    c.alpha_composite(clip(pibbo, t, POOL_SCALE), (POOL_X + CELL, POOL_Y))


def highlight_band(img, top, bottom):
    """Paints the bubble fill between two rows light blue (menu hover)."""
    px = img.load()
    for y in range(max(0, top), min(img.height, bottom)):
        for x in range(img.width):
            if px[x, y][:3] == promo.WHITE:
                px[x, y] = (207, 234, 247, 255)
    return img


def marquee(c, text, t):
    """The now-playing ticker spanning the pool, scrolling one pixel at a time."""
    width = 2 * CELL // 2  # pool width in bubble pixels (bubbles are drawn at half size)
    note = promo.text("♪")
    line = promo.text(text)
    pad = promo.UI["padding"]
    body_h = promo.LH + pad["top"] + pad["bottom"]
    bubble = Image.new("RGBA", (width, body_h + promo.UI["tail"]["h"] - 1), (0, 0, 0, 0))
    # Stretch an empty one-line bubble to the exact width: corners + edge column.
    base = promo.bubble([" " * 4])
    corner = promo.UI["bubble"]["corner"]
    bubble.alpha_composite(base.crop((0, 0, corner, body_h)), (0, 0))
    bubble.alpha_composite(base.crop((corner, 0, corner + 1, body_h)).resize((width - 2 * corner, body_h), Image.NEAREST), (corner, 0))
    bubble.alpha_composite(base.crop((base.width - corner, 0, base.width, body_h)), (width - corner, 0))
    tail = promo.ATLAS.crop((promo.UI["tail"]["x"], promo.UI["tail"]["y"],
                             promo.UI["tail"]["x"] + promo.UI["tail"]["w"], promo.UI["tail"]["y"] + promo.UI["tail"]["h"]))
    bubble.alpha_composite(tail, (width * 3 // 4 - 2, body_h - 1))
    bubble.alpha_composite(note, (pad["x"], pad["top"]))
    window_x = pad["x"] + note.width + 3
    window_w = width - window_x - pad["x"]
    period = line.width + 16
    shift = int(t * 14) % period
    strip = Image.new("RGBA", (period + line.width, promo.LH), (0, 0, 0, 0))
    strip.alpha_composite(line, (0, 0))
    strip.alpha_composite(line, (period, 0))
    bubble.alpha_composite(strip.crop((shift, 0, shift + window_w, promo.LH)), (window_x, pad["top"]))
    big = bubble.resize((bubble.width * 2, bubble.height * 2), Image.NEAREST)
    c.alpha_composite(big, (POOL_X, POOL_Y - big.height + 8))


# ---------------------------------------------------------------- scenes

def scene_code(t):
    """Pixel art as code: Pibbo's rows type in, then turn into pixels."""
    c = canvas(NIGHT)
    inverse = {v: k for k, v in art.PALETTE.items()}
    chill = promo.sprite("chill", 0, 1)
    grid = [[inverse.get(chill.getpixel((x, y))[:3], ".") if chill.getpixel((x, y))[3] else "." for x in range(16)]
            for y in range(16)]
    center_text(c, "Tools/generate_sprites.py", 30, 1, (150, 170, 200))
    rows_typed = int(t / 0.09)
    convert_start = 1.7
    big = 6
    sprite_x, sprite_y = (VW - 16 * big) // 2, 120
    for r, row in enumerate(grid):
        converted = t > convert_start + r * 0.05
        if converted:
            for x, ch in enumerate(row):
                if ch != ".":
                    color = art.PALETTE[ch]
                    ImageDraw.Draw(c).rectangle((sprite_x + x * big, sprite_y + r * big,
                                                 sprite_x + x * big + big - 1, sprite_y + r * big + big - 1), fill=color)
        elif r < rows_typed:
            x = 60
            for ch in row:
                color = art.PALETTE.get(ch, (90, 100, 125)) if ch != "." else (90, 100, 125)
                glyph = promo.text(ch, color=color if len(ch.encode()) == 1 else BROWN)
                c.alpha_composite(glyph, (x, 70 + r * 11))
                x += glyph.width + 3
    if t > 2.6:
        c.paste(Image.new("RGBA", (16 * big, 16 * big), NIGHT + (255,)), (sprite_x, sprite_y))
        c.alpha_composite(clip("chill", t - 2.6, big), (sprite_x, sprite_y))
        center_text(c, "Pibbo's Tidepool", 240, 2, WHITE)
        center_text(c, "a tiny pixel otter for your Mac", 268, 1, (190, 205, 230))
    if t > 0.3:
        center_text(c, "every pixel written as code", VH - 60, 2, WHITE)
    return c


ALL_CLIPS = ["hidden", "peek", "chill", "music", "sleep", "submerged", "water", "crack", "groom", "stretch",
             "yawn", "sunbathe", "raindrops", "cocoa", "huddle", "leaf", "petal", "stargaze", "backfloat",
             "holdpaw", "look", "unplug"]


def scene_all(t):
    c = canvas()
    caption(c, "every frame, drawn in code", 24)
    cell, gap, cols = 48, 8, 4
    x0 = (VW - (cols * cell + (cols - 1) * gap)) // 2
    for k, name in enumerate(ALL_CLIPS + ["flower"]):
        x, y = x0 + (k % cols) * (cell + gap), 64 + (k // cols) * (cell + gap)
        if name == "flower":
            img = promo.flower(int(t * 2.5) % 6, 3)
        else:
            img = clip(name, t % 1.6 if name == "unplug" else t, 3)  # loop the one-shot for the grid
        c.alpha_composite(img, (x, y))
    center_text(c, "22 animations + a growing flower", VH - 40, 1, SOFT)
    return c


def scene_hover(t):
    c = desktop()
    caption(c, "he hides in the corner...")
    x = lerp(60, PIBBO_CENTER[0], ease(t / 0.7))
    y = lerp(160, PIBBO_CENTER[1], ease(t / 0.7))
    if t < 0.7:
        pool(c, "hidden", t, flower=False)
    elif t < 1.2:
        pool(c, "peek", t - 0.7)
        caption(c, "...and peeks when you say hi")
    else:
        pool(c, "chill", t - 1.2)
        caption(c, "...and peeks when you say hi")
    cursor(c, x, y)
    return c


def scene_rub(t):
    c = desktop()
    caption(c, "rub him for a belly float")
    wiggle = math.sin(t * 22) * 12 if t < 0.9 else 0
    pool(c, "chill" if t < 0.9 else "backfloat", 0 if t < 0.9 else t - 0.9)
    cursor(c, PIBBO_CENTER[0] + wiggle, PIBBO_CENTER[1])
    return c


def scene_hold(t):
    c = desktop()
    caption(c, "rest your cursor: he holds paws")
    pool(c, "chill" if t < 0.5 else "holdpaw", t if t < 0.5 else t - 0.5)
    cursor(c, PIBBO_CENTER[0] + 6, PIBBO_CENTER[1] - 20)
    return c


def scene_splash(t):
    c = desktop()
    caption(c, "splash!")
    x = lerp(PIBBO_CENTER[0], WATER_SPOT[0], ease(t / 0.4))
    y = lerp(PIBBO_CENTER[1], WATER_SPOT[1], ease(t / 0.4))
    pool(c, "chill" if t < 0.5 else "look", t if t < 0.5 else t - 0.5, ripple_t=t - 0.5)
    cursor(c, x, y, pressed=0.45 < t < 0.6)
    return c


def scene_music(t):
    c = desktop()
    items = ["Music Time? 🎧", "Dive time 🫧", "Swim away 👋"]
    if t < 1.15:
        caption(c, "a click opens his pixel menu")
        pool(c, "chill", t)
        if t > 0.35:
            menu = promo.bubble(items)
            if t > 0.8:
                pad = promo.UI["padding"]
                menu = highlight_band(menu, pad["top"] - 1, pad["top"] + promo.LH + 1)
            big = menu.resize((menu.width * 2, menu.height * 2), Image.NEAREST)
            mx = min(VW - big.width - 4, PIBBO_CENTER[0] + 24 - big.width)
            c.alpha_composite(big, (mx, POOL_Y - big.height + 8))
            tx, ty = mx + 40, POOL_Y - big.height + 8 + 14
        else:
            tx, ty = PIBBO_CENTER
        x = lerp(PIBBO_CENTER[0], tx, ease((t - 0.4) / 0.4))
        y = lerp(PIBBO_CENTER[1], ty, ease((t - 0.4) / 0.4))
        cursor(c, x, y, pressed=(0.3 < t < 0.4) or (1.0 < t < 1.12))
    else:
        caption(c, "his own lofi radio ♪")
        pool(c, "music", t - 1.15)
        marquee(c, "Pibbo's Raft Days - Floating Pibbo", t - 1.15)
    return c


WEATHER = [("sunbathe", "sunny", (196, 228, 244)), ("raindrops", "rainy", (150, 168, 186)),
           ("cocoa", "snowy", (190, 200, 214)), ("stargaze", "starry night", (40, 52, 88))]


def scene_weather(t):
    k = min(int(t / 0.75), 3)
    name, label, sky = WEATHER[k]
    c = canvas(sky)
    caption(c, "your weather, his mood")
    img = clip(name, t - k * 0.75, 7)
    c.alpha_composite(img, ((VW - img.width) // 2, 150))
    center_text(c, label, 290, 2, WHITE if k == 3 else BROWN)
    return c


def scene_flower(t):
    c = canvas()
    caption(c, "his flower grows every day")
    stage = min(int(t / 0.38), 5)
    img = promo.flower(stage, 8)
    c.alpha_composite(img, ((VW - img.width) // 2, 110))
    center_text(c, f"day {[1, 2, 4, 7, 11, 14][stage]}", 260, 2, SOFT)
    center_text(c, "no chores. it never wilts.", 300, 1, SOFT)
    return c


def scene_facts(t):
    c = canvas()
    caption(c, "light as a bubble")
    facts = ["0 permission prompts", "~0% CPU when idle", "free & open source"]
    for k, fact in enumerate(facts):
        if t > 0.3 + k * 0.6:
            y = 100 + k * 40
            c.alpha_composite(promo.text("🫧", scale=2), (20, y))
            c.alpha_composite(promo.text(fact, scale=2), (44, y))
    c.alpha_composite(clip("sleep", t, 5), ((VW - 80) // 2, 260))
    return c


def scene_end(t):
    c = canvas()
    img = promo.flower(5, 5)
    c.alpha_composite(img, (VW // 2 - 80, 110))
    c.alpha_composite(clip("peek" if t < 0.6 else "chill", t if t < 0.6 else t - 0.6, 5), (VW // 2, 110))
    center_text(c, "Pibbo's Tidepool", 210, 2)
    center_text(c, "for macOS", 238, 1, SOFT)
    center_text(c, "free on GitHub", 300, 2, SOFT)
    center_text(c, "github.com/Eric031212/pibbos-tidepool", 330, 1, SOFT)
    hi = promo.bubble(["hi :)"])
    big = hi.resize((hi.width * 2, hi.height * 2), Image.NEAREST)
    if t > 0.8:
        c.alpha_composite(big, (VW // 2 + 50 - big.width + 20, 70))
    return c


SCENES = [(3.5, scene_code), (3.0, scene_all), (2.0, scene_hover), (2.5, scene_rub), (2.0, scene_hold),
          (1.8, scene_splash), (3.7, scene_music), (3.0, scene_weather), (2.5, scene_flower),
          (3.0, scene_facts), (3.0, scene_end)]


def water_strip(c, height=14):
    """The brand's water strip along the bottom of every non-desktop scene."""
    top = VH - height
    d = ImageDraw.Draw(c)
    d.rectangle((0, top, VW, VH), fill=promo.WATER)
    for x in range(VW):
        if x % 5 == 0:
            c.putpixel((x, top), promo.FOAM)
        if x % 3:
            for y in range(VH - 3, VH):
                c.putpixel((x, y), promo.DEEP)


def frames():
    for duration, scene in SCENES:
        for i in range(int(round(duration * FPS))):
            c = scene(i / FPS)
            if scene not in (scene_hover, scene_rub, scene_hold, scene_splash, scene_music, scene_code):
                water_strip(c)
            yield c


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    audio = TRACK_MASTER if TRACK_MASTER.exists() else TRACK_BUNDLED
    total = sum(d for d, _ in SCENES)
    out = OUT / "pibbos-tidepool-promo.mp4"
    cmd = ["ffmpeg", "-y", "-loglevel", "error",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{VW * SCALE}x{VH * SCALE}", "-r", str(FPS), "-i", "-",
           "-i", str(audio),
           "-map", "0:v", "-map", "1:a",
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", "-preset", "slow", "-tune", "animation",
           "-c:a", "aac", "-b:a", "192k",
           "-af", f"afade=t=in:d=0.6,afade=t=out:st={total - 2.0}:d=2.0",
           "-t", str(total), "-movflags", "+faststart", str(out)]
    encoder = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for k, frame in enumerate(frames()):
        big = frame.resize((VW * SCALE, VH * SCALE), Image.NEAREST).convert("RGB")
        if k == int(3.2 * FPS):
            big.save(OUT / "cover.png")
        encoder.stdin.write(big.tobytes())
    encoder.stdin.close()
    if encoder.wait() != 0:
        raise SystemExit("ffmpeg failed")
    print(f"wrote {out.relative_to(ROOT)} ({total:.1f} s) and cover.png, music: {audio.name}")


if __name__ == "__main__":
    main()
