#!/usr/bin/env python3
"""Build the GitHub page: README.md plus every pixel image it shows.

The README is a short "things to find" list: a few words per hint, each
opening to a picture of Pibbo doing the thing, so the page invites exploring
instead of listing features. Keep it short.
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
    """A section title: a little Pibbo and the words, same size as the hints."""
    content = row([icon, text(title)], gap=4)
    return save(padded(content, px=5, py=3), name).replace("{alt}", title)


def pill(name, s):
    return save(padded(text(s), px=5, py=3), name).replace("{alt}", s)


def reveal(name, picture, said=None, note=None):
    """What a hint opens to: Pibbo doing the thing, maybe saying something."""
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
        parts.append(text(note, color=SOFT))
    alt = " ".join((said or []) + ([note] if note else []))
    return save(padded(column(parts, gap=5), px=6, py=5), name).replace("{alt}", alt)


# ---------------------------------------------------------------- the field guide

def holiday(name, frame=0):
    extras = []
    for table, x in (("meadowDecor", 0), ("decor", FS)):
        clip = M.get(table, {}).get(name)
        if clip:
            extras.append((cell(clip["row"], frame), x))
    return scene(pet("chill", 0, outfit=name), extras=extras)


def hints():
    """(emoji, hint, picture, speech bubble, short note): a few words each."""
    rainbow = [(cell(M["rainbow"]["row"], k), FS * k) for k in range(3)]
    return [
        ("👀", "Hover over the corner.", big(solo(pet("peek"))), None, "he peeks out to say hi"),
        ("🤏", "Rub him.", big(solo(pet("backfloat", 2))), None, None),
        ("🤝", "Rest your cursor on him.", big(solo(pet("holdpaw", 1))), None, "otters hold paws"),
        ("👆", "Click him.", big(solo(pet("chill"))), ["Music Time? 🎧", "Dive time 🫧", "Swim away 👋"], None),
        ("💦", "Splash, splash, splash.", big(row([solo(pet("flip", k)) for k in (1, 2, 3)], gap=1)), None, "a little secret"),
        ("🎮", "Put on some music. Wait for the retro one.", big(solo(pet("game", 0))), ["GG! ✨"], None),
        ("🌧️", "Wait for the rain to stop.", big(scene(pet("admire", 2), extras=rainbow)), None, None),
        ("😴", "Step away for a while.", big(solo(pet("sleep"))), ["💭 🦀"], None),
        ("🌠", "Look up on a clear night.", big(scene(pet("wish", 0), sky=NIGHT_SKY, light="night")), ["Made a wish ✨"], None),
        ("🍾", "Come back in a few days.", big(solo(pet("note", 0))), ["The sea says hi 🌊"], None),
        ("🌱", "Come back in a few months.",
         big(scene(pet("look"), extras=[(promo.visit_frame("crab", 9), 4)])), None, "things grow. neighbours visit."),
        ("🎄", "Come back in December.", big(holiday("christmas")), None, None),
    ]


def guide():
    out = [f'<p>{sign("sign-find", "things to find", pet("peek"))}</p>\n']
    for k, (emoji, question, picture, said, note) in enumerate(hints()):
        body = reveal(f"reveal-{k:02d}", picture, said, note)
        out.append(f"<details><summary>{emoji} {question}</summary>\n<br>{body}\n</details>\n")
    return "\n".join(out)


# ---------------------------------------------------------------- the page

def header():
    download = pill("download", "Download for macOS 🌊")
    return f"""<p align="center">
  <img src="Marketing/github/banner.png" alt="Pibbo's Tidepool: a tiny pixel otter for the corner of your Mac" width="100%">
</p>

<p align="center"><a href="{REPO}/releases/latest">{download}</a></p>

<p align="center">No to-dos, no timers, no chat. Just a little company.<br>
Some things are nicer to find yourself. Peek below if you can't wait 👇</p>
"""


def get_it():
    return f"""<p>{sign("sign-get", "get pibbo", pet("water", 2))}</p>

Download the `.dmg` from the [latest release]({REPO}/releases/latest), drag **Tidepool** into **Applications**, open it. macOS 13+, free and open source.

<details><summary>🔐 macOS blocks the first launch?</summary><br>

It isn't signed with an Apple Developer ID. Once: **System Settings → Privacy & Security** → *"…was blocked"* → **Open Anyway**.
</details>

<details><summary>🔒 Privacy</summary><br>

Weather only: your IP goes to [ipwho.is](https://ipwho.is/) to guess your city, and a rounded (~1 km) spot to [MET Norway](https://api.met.no/). For calls it only checks whether your camera or mic is on; it never sees or hears anything. No accounts, no analytics.
</details>

<details><summary>🛠️ Build it yourself</summary><br>

Needs macOS 13+, Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -scheme Tidepool -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Tidepool.app --args --demo
```

`--demo` speeds everything up. More flags, the plan and how it all works: [CLAUDE.md](CLAUDE.md). This page is made by `Tools/generate_github_page.py`.
</details>
"""


def footer():
    return f"""<p align="center">{strip("divider")}</p>

<p align="center"><sub>Weather by MET Norway (CC BY 4.0) · music made with Suno · <a href="CREDITS.md">credits</a> · <a href="LICENSE">GPL-3.0</a> · made with 🐚 and little pixels</sub></p>
"""


def strip(name):
    """A thin strip of pool water: the divider."""
    img = Image.new("RGBA", (120, 3), (0, 0, 0, 0))
    for x in range(120):
        img.putpixel((x, 0), art.PALETTE["W" if x % 5 == 0 else "w"] + (255,))
        img.putpixel((x, 1), art.PALETTE["w"] + (255,))
        img.putpixel((x, 2), art.PALETTE["x" if x % 3 else "w"] + (255,))
    return save(img, name).replace("{alt}", "")


def main():
    for old in OUT.glob("*.png"):
        old.unlink()
    page = "\n".join([
        "<!-- Generated by Tools/generate_github_page.py: edit the script, not this file. -->",
        header(), guide(), get_it(), footer(),
    ])
    (ROOT / "README.md").write_text(page)
    print(f"wrote README.md and {len(list(OUT.glob('*.png')))} images in {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
