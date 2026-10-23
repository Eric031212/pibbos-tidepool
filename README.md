# Pibbo's Tidepool 🦦🌊

A tiny pixel sea otter who lives in the corner of your Mac.
No to-dos, no timers, no chat. Just a little company while you do your thing.

![pibbo](Assets/Skins/pibbo/preview.gif)

## What Pibbo does

- 👀 hides at the bottom of your screen and peeks out when you hover
- 🤏 drag him left or right along the bottom if he's in your way
- 💕 rub him with your mouse and he rolls onto his back, happy
- 🤝 rest your cursor on him and he holds your paw (otters hold hands!)
- 💦 click the water beside him for a little splash
- 🌊 glides between moves: bobs up through the water, sinks back down, rolls over with a splash, slips his headphones on
- 🐚 floats around and keeps busy: cracks shells, grooms, waters his flower
- 🌷 his flower grows a little every day (no chores, it never wilts), and over the next few months moss, mushrooms and more slowly show up on the rock next to it
- 🍾 every few days a message in a bottle drifts in. Click it and Pibbo reads you the note
- 🌅 his pool changes colour through the day: misty blue at dawn, blue by day, golden at dusk, moonlit deep blue at night
- ☀️🌧❄️ reacts to your weather, the season and the time of day: sunglasses in the sun, catching raindrops, hot cocoa in the snow, stargazing at night
- 🎶 nods along to the beat of his own radio
- 🎧 puts on headphones when Apple Music is playing, and takes them off when it stops
- 📻 every now and then asks `Music Time? 🎧` and plays his own lofi radio: a random theme, shuffled, no song picking needed. A little pixel ticker shows what's playing ♪
- 🌙 three themes: *Pibbo's Raft Days*, *Solo Float* and *Pibbo in the City*, 36 cozy tracks, almost 2 hours
- 🏮 each theme brings a little something to his rock: a paper boat, a cup of tea, a city street lamp
- 🎃🎅🎉🧧 dresses up for the holidays: pumpkin hat for Halloween, Santa hat for Christmas, party hat for New Year, a red flower knot for Lunar New Year. On Halloween a jack-o'-lantern bobs beside his flower and a little bat flaps by 🦇
- 🫧 `Dive time 🫧` sends him underwater until you click him again
- 😴 naps when you step away
- 🙈 disappears in fullscreen, when you lock the screen, and while your Mac sleeps
- 🔒 zero permission prompts, ever
- 🪶 ~0% CPU and ~13 MB of memory

Everything you see, from the otter to the little speech bubbles and the font, is pixel art drawn by code in `Tools/`. 🎨

## Status

**v0.7.0, still early!** More lofi themes on the way 🎶

## Download

1. Grab `PibbosTidepool-<version>.dmg` from the [latest release](https://github.com/Eric031212/pibbos-tidepool/releases/latest) 📦 (macOS 13+, Apple silicon and Intel)
2. Open it and drag **Tidepool** into **Applications**
3. Open Tidepool from Applications

🔐 Tidepool isn't signed with an Apple Developer ID yet, so the first time macOS says it can't check it for malware. To let Pibbo in (just once):
**System Settings → Privacy & Security** → scroll down → *"Tidepool was blocked…"* → **Open Anyway** → enter your password.

After that he shows up by himself every time you log in (macOS shows a one-time "Login Item Added" note, that's normal 👍).

## Build it yourself

You'll need macOS 13+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -scheme Tidepool -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Tidepool.app
```

Drop `Tidepool.app` into `/Applications` and Pibbo will show up every time you log in.
Click Pibbo → `Swim away 👋` to quit.

Impatient? `open Tidepool.app --args --demo` speeds everything up so you can see it all in a few minutes. ⏩

Run the tests with `swift test`. Make the download DMG with `python3 Tools/package_dmg.py` → `dist/`.

## Privacy

Tidepool talks to the internet for weather only, and never asks for your location:

- 🌐 your IP goes to [ipwho.is](https://ipwho.is/) once per launch to guess your city
- ⛅ a rounded (~1 km) spot goes to [MET Norway](https://api.met.no/) every 1–3 hours for the forecast

That's it. No accounts, no analytics. 🤐

## Thanks

Weather data from MET Norway (CC BY 4.0). Music made with Suno 🎵. More in [CREDITS.md](CREDITS.md).

## License

[GPL-3.0](LICENSE) 💙
