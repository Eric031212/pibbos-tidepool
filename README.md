# Pibbo's Tidepool 🦦🌊

A tiny pixel sea otter who lives in the corner of your Mac.
No to-dos, no timers, no chat. Just a little company while you do your thing.

![pibbo](Assets/Placeholder/pibbo/preview.gif)

## What Pibbo does

- 👀 hides at the bottom of your screen and peeks out when you hover
- 🐚 floats around holding a shell, then sinks back down
- 🎧 puts on headphones when Apple Music is playing
- 😴 naps when you step away
- 🫧 `work work, leave me alone :D` sends him underwater until you click him again
- 🙈 disappears in fullscreen, when you lock the screen, and while your Mac sleeps
- 🔒 zero permission prompts, ever
- 🪶 ~0% CPU and ~11 MB of memory

## Status

**v0.1.0, early days!** The art is a placeholder (the real Pibbo is being hand-drawn).
Coming later: a cozy lofi radio 📻, weather and season moods ☔❄️, holiday outfits 🎅

## Build it yourself

You'll need macOS 13+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -scheme Tidepool -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Tidepool.app
```

Drop `Tidepool.app` into `/Applications` and Pibbo will show up every time you log in
(macOS shows a one-time "Login Item Added" note, that's normal 👍).
Click Pibbo → `bye 👋` to quit.

Run the tests with `swift test`.

## Privacy

v0.1.0 doesn't talk to the internet at all. 🤐

## License

[GPL-3.0](LICENSE) 💙
