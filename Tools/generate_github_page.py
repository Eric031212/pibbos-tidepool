#!/usr/bin/env python3
"""Build the GitHub page: README.md plus every pixel image it shows.

The README is a "field guide": short hints that open on click to show Pibbo
doing the thing, so the page invites exploring instead of listing features.
Signs, reveals, buttons, labels and dividers are drawn from Tidepool's own
sprites and pixel font, on cream cards so they read in GitHub's light and dark
themes. The clickable hint lines themselves are plain text with an emoji:
GitHub wraps every README image in a link to itself, so an image inside a
<summary> opens the picture instead of the hint. Technical bits that must stay
copyable (build commands, links) are plain Markdown too.

Images are drawn at 6 device pixels per art pixel and shown at half width, so
each art pixel is 3 CSS px: crisp on Retina, and an exact 2:1 downscale
elsewhere.

Outputs: README.md, Marketing/github/page/*.png
Run Tools/generate_sprites.py and Tools/generate_promo.py first if the art
changed (the banner and hero.gif come from generate_promo.py).

Usage:
    python3 Tools/generate_github_page.py

Requires: Python 3.10+, Pillow
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_promo as promo  # noqa: E402  (sprites, pixel font, bubble frame)
import generate_sprites as art  # noqa: E402  (water light, outfits)

ROOT = promo.ROOT
OUT = ROOT / "Marketing/github/page"
REL = "Marketing/github/page"
FILE_SCALE, SHOW_SCALE = 6, 3
FS = promo.FS
BROWN, SOFT, CREAM, FILL = promo.BROWN, promo.SOFT, promo.CREAM, promo.WHITE
NIGHT_SKY = (52, 58, 84)
REPO = "https://github.com/Eric031212/pibbos-tidepool"

# ---------------------------------------------------------------- pixel pieces


def check_glyphs(s):
    for ch in s:
        key = ch.replace("️", "")
        if key not in promo.UI["glyphs"]:
            raise SystemExit(f"no pixel glyph for {ch!r} in {s!r}")


def text(s, color=BROWN, scale=1):
    check_glyphs(s)
    return promo.text(s, color=color, scale=scale)


def wrap(s, width):
    """Pixel-text lines no wider than `width` art pixels."""
    lines, line = [], ""
    for word in s.split(" "):
        trial = f"{line} {word}".strip()
        if line and text(trial).width > width:
            lines.append(line)
            line = word
        else:
            line = trial
    return lines + [line] if line else lines


def card(w, h, fill=FILL, outline=BROWN):
    """A cream card with a 1-pixel outline and clipped corners."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle((1, 0, w - 2, h - 1), fill=outline)
    d.rectangle((0, 1, w - 1, h - 2), fill=outline)
    d.rectangle((2, 1, w - 3, h - 2), fill=fill)
    d.rectangle((1, 2, w - 2, h - 3), fill=fill)
    return img


def column(parts, gap=4, align="center"):
    w = max(p.width for p in parts)
    h = sum(p.height for p in parts) + gap * (len(parts) - 1)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    y = 0
    for p in parts:
        x = (w - p.width) // 2 if align == "center" else 0
        img.alpha_composite(p, (x, y))
        y += p.height + gap
    return img


def row(parts, gap=4):
    w = sum(p.width for p in parts) + gap * (len(parts) - 1)
    h = max(p.height for p in parts)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    x = 0
    for p in parts:
        img.alpha_composite(p, (x, h - p.height))
        x += p.width + gap
    return img


def padded(content, px=6, py=5, fill=FILL):
    c = card(content.width + 2 * px, content.height + 2 * py, fill=fill)
    c.alpha_composite(content, (px, py))
    return c


def lines_image(lines, color=BROWN, scale=1):
    return column([text(l, color=color, scale=scale) for l in lines], gap=2 * scale, align="left")


# ---------------------------------------------------------------- sprites and scenes

M = promo.MANIFEST
SHEET = promo.SHEET


def cell(row_, frame=0):
    return SHEET.crop((frame * FS, row_ * FS, (frame + 1) * FS, (row_ + 1) * FS))


def clip_row(name):
    return (M["states"].get(name) or M["actions"][name])["row"]


def pet(name, frame=0, outfit=None):
    r = clip_row(name) + (M["outfits"][outfit]["offset"] if outfit else 0)
    return cell(r, frame)


def scene(pet_img, meadow_stage=6, flower_stage=5, extras=(), sky=None, light=None):
    """The pool as in the app: meadow, flower, Pibbo; `extras` are (image, x) overlays."""
    img = Image.new("RGBA", (FS * 3, FS), (sky + (255,)) if sky else (0, 0, 0, 0))
    if meadow_stage is not None:
        img.alpha_composite(cell(M["meadow"]["row"], meadow_stage), (0, 0))
    if flower_stage is not None:
        img.alpha_composite(cell(M["garden"]["row"], flower_stage), (FS, 0))
    for overlay, x in extras:
        img.alpha_composite(overlay, (x, 0))
    img.alpha_composite(pet_img, (FS * 2, 0))
    return art.light_water(img, light) if light else img


def solo(pet_img, sky=None, light=None):
    img = Image.new("RGBA", (FS, FS), (sky + (255,)) if sky else (0, 0, 0, 0))
    img.alpha_composite(pet_img)
    return art.light_water(img, light) if light else img


def big(img, k=2):
    return img.resize((img.width * k, img.height * k), Image.NEAREST)


# ---------------------------------------------------------------- page elements

def save(img, name):
    OUT.mkdir(parents=True, exist_ok=True)
    img.resize((img.width * FILE_SCALE, img.height * FILE_SCALE), Image.NEAREST).save(OUT / f"{name}.png")
    return f'<img src="{REL}/{name}.png" width="{img.width * SHOW_SCALE}" alt="{{alt}}">'


def sign(name, title, icon):
    """A section title: a little Pibbo and the words, on a cream card."""
    content = row([icon, text(title, scale=2)], gap=6)
    return save(padded(content, px=6, py=4), name).replace("{alt}", title)


def pill(name, s, scale=1, prefix="> "):
    content = text(prefix + s, scale=scale)
    return save(padded(content, px=5, py=3), name).replace("{alt}", s)


def reveal(name, picture, said=None, note=None):
    """What a hint opens to: a picture of Pibbo, maybe a speech bubble, and a note."""
    parts = []
    if said:
        for line in said:
            check_glyphs(line)
        bub = promo.bubble(said)
        both = Image.new("RGBA", (max(bub.width + picture.width // 2, picture.width), bub.height + picture.height - 4), (0, 0, 0, 0))
        both.alpha_composite(picture, (both.width - picture.width, bub.height - 4))
        both.alpha_composite(bub, (max(0, both.width - picture.width // 2 - bub.width + 6), 0))
        parts.append(both)
    else:
        parts.append(picture)
    if note:
        parts.append(lines_image(wrap(note, 170), color=SOFT))
    alt = " ".join((said or []) + ([note] if note else []))
    return save(padded(column(parts, gap=6), px=8, py=6), name).replace("{alt}", alt)


def strip(name):
    """A thin strip of pool water: the dividers."""
    img = Image.new("RGBA", (180, 3), (0, 0, 0, 0))
    for x in range(180):
        img.putpixel((x, 0), art.PALETTE["W" if x % 5 == 0 else "w"] + (255,))
        img.putpixel((x, 1), art.PALETTE["w"] + (255,))
        img.putpixel((x, 2), art.PALETTE["x" if x % 3 else "w"] + (255,))
    return save(img, name).replace("{alt}", "")


# ---------------------------------------------------------------- the field guide

HINT_EMOJI = {
    "corner": "👀", "rub": "🤏", "paw": "🤝", "splash": "💦", "menu": "👆",
    "light": "🌅", "rain": "🌧️", "nap": "😴", "music": "🎧", "call": "📹",
    "moon": "🌕", "star": "🌠", "flower": "🌱", "rock": "🪨", "bottle": "🍾",
    "visitors": "🦀", "gift": "🐦", "october": "🎃", "december": "🎄", "lunar": "🏮",
}


def hint(key, question, picture, said=None, note=None):
    body = reveal(f"reveal-{key}", picture, said, note)
    return f"<details><summary>{HINT_EMOJI[key]} {question}</summary>\n<br>{body}\n</details>\n"


def water_lights():
    tiles = [scene(pet("chill"), light=t if t != "day" else None, meadow_stage=None) for t in ("dawn", "day", "dusk", "night")]
    return row([t.crop((FS, 0, FS * 3, FS)) for t in tiles], gap=3)


def holiday(name, frame=0):
    extras = []
    for table, x in (("meadowDecor", 0), ("decor", FS)):
        clip = M.get(table, {}).get(name)
        if clip:
            extras.append((cell(clip["row"], frame), x))
    return scene(pet("chill", 0, outfit=name), extras=extras)


def guide():
    v = M["visitors"]
    star = M["shootingStar"]
    rainbow = [(cell(M["rainbow"]["row"], k), FS * k) for k in range(3)]
    sections = [
        ("first", "The first few minutes", pet("peek"), [
            ("corner", "Point at the water in the corner of your screen.", big(solo(pet("peek"))), None,
             "He peeks out to see who's there, then sinks back down. He hides most of the time."),
            ("rub", "Give him a little rub.", big(solo(pet("backfloat", 2))), None,
             "Move the mouse back and forth over him. He rolls onto his back, happy!"),
            ("paw", "Rest your cursor on him for a moment.", big(solo(pet("holdpaw", 1))), None,
             "He holds your paw. Otters hold hands so they don't drift apart."),
            ("splash", "Click the water next to him.", big(scene(pet("look", 1), meadow_stage=None, flower_stage=None,
                                                                 extras=[(cell(M["actions"]["ripple"]["row"], 1), FS)]).crop((FS, 0, FS * 3, FS))), None,
             "A little splash, and he turns to look."),
            ("menu", "Click on him.", big(solo(pet("chill"))), ["Music Time? 🎧", "Dive time 🫧", "Swim away 👋"],
             "His tiny menu. You can also drag him along the bottom of the screen."),
        ]),
        ("day", "Over a day", pet("sunbathe", 1), [
            ("light", "Look at the water at dawn, and again at dusk.", big(water_lights()), None,
             "His pool follows the real sun where you are: misty, blue, golden, deep blue."),
            ("rain", "Check on him when it rains... and when it stops.", big(scene(pet("admire", 2), extras=rainbow)), None,
             "He catches raindrops. When the rain stops in the daytime, a little rainbow comes out."),
            ("nap", "Step away from your desk for a while.", big(solo(pet("sleep"))), ["💭 🦀"],
             "He naps in his kelp, and dreams of what he saw lately."),
            ("music", "Say yes when he asks about music.", big(solo(pet("music"))), ["Music Time? 🎧"],
             "Three lofi themes, almost two hours. He nods along to the beat."),
            ("call", "Join a video call.", big(solo(pet("submerged", 1))), None,
             "Camera or mic on? He dives and stays down, so he never shows up on a shared screen."),
        ]),
        ("night", "After dark", solo(pet("stargaze", 3), sky=NIGHT_SKY), [
            ("moon", "Look at the water on the night of a full moon.", big(scene(pet("stargaze", 3), sky=NIGHT_SKY, light="night")), None,
             "The moonlight on the water follows the real moon: sparkly when it's full, dark at new moon."),
            ("star", "On a clear night, keep an eye on the sky.",
             big(scene(pet("wish", 0), sky=NIGHT_SKY, light="night", extras=[(cell(star["row"], 3), FS)])), ["Made a wish ✨"],
             "Now and then a shooting star streaks by. Click him right away."),
        ]),
        ("months", "Over weeks and months", cell(M["garden"]["row"], 5), [
            ("flower", "Watch the flower in the pot.", big(row([cell(M["garden"]["row"], s) for s in range(6)], gap=1)), None,
             "From a seed to full bloom in about two weeks. No chores, and it never wilts."),
            ("rock", "Then watch the rock next to it.", big(scene(pet("chill"), meadow_stage=2)), None,
             "Over the next three months, little things slowly show up there. Nothing ever resets."),
            ("bottle", "Every few days, something drifts in.", big(solo(pet("note", 0))), ["The sea says hi 🌊"],
             "A message in a bottle. Click it before it floats away."),
            ("visitors", "Someone might drop by.", big(row([solo(promo.visit_frame("crab", 9)), solo(promo.visit_frame("seagull", 4)),
                                                          solo(promo.visit_frame("fish", 2))], gap=2)), None,
             "A crab, a seagull, a fish, depending on the weather. And once in a while, a friend 🦦"),
            ("gift", "Be nice to the seagull.", big(scene(pet("look"), extras=[(cell(M["gift"]["row"]), 0)])), None,
             "After a few visits it brings him a little something. It stays on the rock for good."),
        ]),
        ("holidays", "On special days", pet("chill", 0, outfit="christmas"), [
            ("october", "Late October.", big(holiday("halloween")), None,
             "A pumpkin hat, a jack-o'-lantern in the water, and a little bat."),
            ("december", "Late December.", big(holiday("christmas")), None,
             "A Santa hat, lights and a tiny tree. Then a party hat and fireworks for the New Year."),
            ("lunar", "Lunar New Year.", big(holiday("lunarNewYear")), None,
             "A red flower knot and two lanterns, if your Mac's region celebrates it."),
        ]),
    ]
    out = []
    for key, title, icon, hints in sections:
        out.append(f'<p>{sign(f"sign-{key}", title, icon)}</p>\n')
        for h in hints:
            out.append(hint(*h))
        out.append("")
    return "\n".join(out)


# ---------------------------------------------------------------- the page

def header():
    tagline = text("no to-dos, no timers, no chat. just a little company.")
    tag = save(padded(tagline, px=8, py=5), "tagline").replace("{alt}", "No to-dos, no timers, no chat. Just a little company.")
    download = pill("download", "Download for macOS 🌊", scale=2, prefix="")
    badges = " ".join(pill(f"badge-{k}", s, prefix="") for k, s in
                      (("prompts", "no permission prompts"), ("cpu", "~0% CPU when idle"), ("free", "free & open source")))
    return f"""<p align="center">
  <img src="Marketing/github/banner.png" alt="Pibbo's Tidepool" width="100%">
</p>

<p align="center">{tag}</p>

<p align="center"><a href="{REPO}/releases/latest">{download}</a></p>

<p align="center">{badges}</p>

<p align="center">
  <img src="Marketing/github/hero.gif" alt="Pibbo surfaces, cracks a shell, and sinks back down" width="432">
</p>
"""


def intro():
    words = ["Most of Pibbo's little world is meant to be found, not read about.",
             "If you'd like to discover it yourself, stop here and go say hi 👋",
             "Otherwise, click a hint to peek."]
    img = lines_image(["Most of Pibbo's little world is meant to be found,", "not read about. If you'd like to discover it yourself,",
                       "stop here and go say hi 👋", "", "Otherwise, click a hint to peek."])
    return f'<p align="center">{save(padded(img, px=10, py=8), "intro").replace("{alt}", " ".join(words))}</p>\n'


def get_it():
    steps = lines_image(["1. Download the .dmg from the latest release", "2. Drag Tidepool into Applications",
                         "3. Open it. From then on he shows up when you log in."])
    steps_img = save(padded(steps, px=10, py=8), "steps").replace("{alt}", "Download the dmg, drag Tidepool into Applications, open it.")
    blocked = "🔐 If macOS blocks the first launch"
    upgrade = "🔄 Coming from an older version?"
    privacy = "🔒 Privacy"
    build = "🛠️ Build it yourself"
    return f"""<p>{sign("sign-get", "Get Pibbo", pet("water", 2))}</p>

<p>{steps_img}</p>

<p><a href="{REPO}/releases/latest">{pill("download-small", "Latest release", prefix="")}</a> <a href="{REPO}/releases">{pill("whats-new", "What's new", prefix="")}</a></p>

<details><summary>{blocked}</summary><br>

Pibbo's Tidepool isn't signed with an Apple Developer ID, so macOS blocks the first launch. To let Pibbo in (just once):
**System Settings → Privacy & Security** → scroll down → *"…was blocked"* → **Open Anyway** → enter your password.
macOS also shows a one-time "Login Item Added" note. That's normal 👍
</details>

<details><summary>{upgrade}</summary><br>

Just drag the new one over the old one. His flower, the rock and your other little bits come along.
Coming from 0.x, you may see an old "Tidepool" entry in **System Settings → General → Login Items** next to "Pibbo's Tidepool"; you can remove the old one.
</details>

<details><summary>{privacy}</summary><br>

Pibbo's Tidepool talks to the internet for weather only, and never asks for your location:

- 🌐 your IP goes to [ipwho.is](https://ipwho.is/) once per launch to guess your city
- ⛅ a rounded (~1 km) spot goes to [MET Norway](https://api.met.no/) every 1–3 hours for the forecast

To know when you're on a call, it only checks whether a camera or microphone is switched on, the same on/off you see in the menu bar. It never opens them and never sees or hears anything 🙈 No accounts, no analytics.
</details>

<details><summary>{build}</summary><br>

You'll need macOS 13+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -scheme Tidepool -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Tidepool.app
```

Run the tests with `swift test`. Make the download DMG with `python3 Tools/package_dmg.py`. This page is made by `python3 Tools/generate_github_page.py`.

Impatient? These skip the waiting (spoilers ahead):

| Flag | What it does |
|---|---|
| `--demo` | everything sped up |
| `--visitor crab` | a visitor every few seconds (`seagull`, `fish`, `friend`) |
| `--holiday christmas` | a holiday outfit (`halloween`, `newYear`, `lunarNewYear`) |
| `--time night` | a time of day (`dawn`, `day`, `dusk`) |
| `--weather rain` | the weather (`snow`, `clear`, …) |
| `--rainbow` / `--stars` / `--bottle` | a rainbow, shooting stars, a message in a bottle |
| `--garden-days 91` | the flower and the rock as on day 91 |

Everything you see, from the otter to the speech bubbles and this page, is pixel art drawn by code in `Tools/` 🎨
</details>
"""


def footer():
    made = save(padded(text("made with 🐚 and lots of little pixels", color=SOFT), px=8, py=5), "made").replace(
        "{alt}", "Made with a shell and lots of little pixels")
    return f"""<p align="center">{strip("divider-end")}</p>

<p align="center">{made}</p>

<p align="center"><sub>Weather data from MET Norway (CC BY 4.0) · Music made with Suno · More in <a href="CREDITS.md">CREDITS.md</a> · <a href="LICENSE">GPL-3.0</a></sub></p>
"""


def main():
    for old in OUT.glob("*.png"):
        old.unlink()
    divider = f'<p align="center">{strip("divider")}</p>\n'
    page = "\n".join([
        "<!-- Generated by Tools/generate_github_page.py: edit the script, not this file. -->",
        header(), divider, intro(), guide(), divider, get_it(), footer(),
    ])
    (ROOT / "README.md").write_text(page)
    print(f"wrote README.md and {len(list(OUT.glob('*.png')))} images in {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
