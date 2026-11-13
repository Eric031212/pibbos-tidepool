# Games with Pibbo: plan (approved idea, 2026-11-04; built in v1.3, 2026-11-13)

The developer's idea: a fourth menu item next to Music / Dive / Swim away, where you play small pixel games with Pibbo. One game first, a list that can grow. Built in v1.3 (framework + Shell Catch); how it works now is in `CLAUDE.md` Section 3 "Games with Pibbo". The other options below stay as ideas for later games. Read `CLAUDE.md` first (principles, permissions, performance budget, how to work with the developer).

## Decided

- **Entry:** a fourth line in the click menu, `Game time 🎮` (needs a 🎮 icon in `Tools/generate_sprites.py`; all text in `Sources/Strings`). It opens a pixel list of games (the bubble/menu style), even while there is only one game, so more can follow.
- **Lightweight outside games:** the developer accepts more memory and CPU **only while a game is open**. Outside games Tidepool must stay as it is (~0 % CPU, ~16 MB, no continuous wakeups). Closing a game (Esc or a close button) releases its window, layers, sprites, timers and any display link.
- **Input:** simple clicking, typing keys, or swiping on the trackpad. Only inside the game's own window while it is in front (an ordinary key window): never global event monitors, never Input Monitoring or any other permission prompt. The pet panel stays non-activating; the game window is a separate window that may activate the app while it is open, and focus goes back afterwards.
- **Look:** Tidepool's pixel art, drawn in `Tools/generate_sprites.py` (or a sibling tool), integer scale, nearest-neighbour, the pixel font and bubble frame. Roughly a 160×120 art-pixel playfield at 4× (~640×480 pt), in a pixel frame, rising out of the pool.
- **Code:** game rules in a new pure-Swift core module `Games` (Foundation only, unit tested, Windows-portable like Brain and World); window, input and drawing in the macOS layer. A frame loop (e.g. `CADisplayLink`/`CVDisplayLink` or a timer at 60 fps) is allowed only while a game window is open.
- **While playing:** Pibbo in the pool shows that he is playing too (e.g. the v1.2 `game` action), and Brain stays quiet (no appearances, bubbles or visitors) until the game closes.
- **Scores:** each game remembers one "best" number at most. No leaderboards, achievements, streaks or daily goals (Section 4 rules out pet stats and collectibles; keep it pressure-free).
- **Process:** propose, then build in tested steps (framework first, then the game), hand off with a checklist, release only when the developer says so.

## First game: options (developer to pick; Claude's recommendation is A)

- **A. Shell Catch 🐚 (recommended first):** Pibbo floats on his back at the bottom; shells, starfish and little fish fall; move him left/right to catch them and dodge the odd jellyfish. ~60 s rounds, slowly faster. Controls: ← →, a left/right trackpad swipe, or the mouse. Calm, easy, reuses existing art.
- **B. Beat Shells 🎶:** play one of our own lofi tracks; shells arrive on the beat (we have beat maps, `Content.BeatGrid`); click or press space on the beat to crack them. Most on-brand, but needs careful audio-latency calibration.
- **C. Bubble Pop 🫧:** bubbles rise from the water; click them before they reach the top, some carry a fish or a shell. Mouse/trackpad only, the most relaxing.
- **D. Kelp Hop 🌿:** side-scroller; press space to dive under or jump over driftwood and kelp. Most exciting, keyboard only.

## Decided by the developer (2026-11-13)

1. First game: A, Shell Catch.
2. One best score per game.
3. Games ship on their own as v1.3.
