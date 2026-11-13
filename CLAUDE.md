# CLAUDE.md — Pibbo's Tidepool

> Foundational plan for the project. Claude Code follows this document when implementing.
> Anything marked **[UNVERIFIED]** must be confirmed with a minimal prototype before it is used in production code.

---

## 1. What Tidepool is

Pibbo's Tidepool (display name since v1.0; the app file stays `Tidepool.app` so updates replace it in place) is a standalone, pixel-art desktop companion for macOS. Its mascot is **Pibbo**, a sea otter who lives in a tiny tide pool in the corner of your screen. The mood is close to Stardew Valley: chill, quiet, charming.

- **Not a productivity tool.** No Pomodoro, no to-do lists, no chat. People use other tools to work; Tidepool only provides a sense of company.
- **Hidden by default.** Most of the time Pibbo is barely visible at the edge of the screen.
- **Zero setup.** After the first launch, Tidepool starts automatically at login and needs no configuration. It should never trigger a system permission prompt.
- **Extremely lightweight.** Near-zero CPU while idle, small memory footprint.
- **Few things, done well.** Like Apple: focus on a small number of experiences. When in doubt, leave it out.

## Repository layout (current)

```
CLAUDE.md                          this plan
README.md, LICENSE                 public page (generated, see Tools/generate_github_page.py) and GPL-3.0
docs/design-notes.md               background: market research and why decisions were made
docs/games-plan.md                 brief for the planned games menu (not built yet)
CREDITS.md                         third-party data and attribution (MET Norway, tzdb), bundled into the app
Package.swift                      TidepoolCore: Brain, Content, Games, Strings, World (Foundation only) + tests
project.yml                        XcodeGen spec for the macOS app (Tidepool.xcodeproj is generated, not committed)
Sources/                           modules from Section 7 (App, PetWindow, Renderer, Signals, Music, GameWindow = macOS; Brain, Content, Games, Strings, World = core)
Tests/                             BrainTests, ContentTests, GamesTests, WorldTests
Spikes/                            research prototypes from Section 14 (never part of the app)
Assets/Skins/pibbo/                Pibbo's skin pack (manifest.json, sprites.png, previews)
Assets/UI/                         pixel font, emoji icons, bubble frame (ui.png + ui.json)
Assets/Games/                      game window frame and game art (games.png + games.json, drawn by Tools/generate_sprites.py)
Assets/Music/<theme>/              built-in lofi by theme: theme.json, tracks (AAC in CAF), beat maps (Tools/import_track.py)
Assets/MusicMasters/<Theme Name>/  WAV masters of the tracks (local only: git-ignored, never bundled)
Assets/Data/zone.tab               tzdb time-zone coordinates (offline location fallback)
Tools/generate_sprites.py          draws all pixel art from text grids (requires Pillow)
Tools/import_track.py              WAV master → app-ready CAF + beat map with estimated bpm (numpy + afconvert)
Tools/generate_promo.py            social-media posters (1080×1350, 11 of them since v1.0) from the real sprites and pixel font → Marketing/promo/
Tools/generate_promo_video.py      30 s vertical promo video (1080×1920, 30 fps, BGM "Floating Pibbo") → Marketing/video/ (needs ffmpeg)
Tools/generate_placeholder_lofi.py synthesizes a placeholder lofi loop (stdlib + afconvert), for testing without tracks
Tools/generate_github_page.py      the GitHub page: README.md + pixel signs, reveals and buttons → Marketing/github/page/ (a "field guide": hints that open to show Pibbo doing the thing). Edit this script, never README.md by hand
Tools/package_dmg.py               universal Release build → dist/PibbosTidepool-<version>.dmg (drag-to-install; Developer ID signing + notarization when SIGN_IDENTITY / NOTARY_PROFILE are set)
Assets/AppIcon/                    AppIcon.icns + AppIcon.png, drawn by Tools/generate_sprites.py
```

### Building

```sh
swift test                                   # core unit tests (Brain, Content, World)
xcodegen generate                            # after changing project.yml or adding files
xcodebuild -scheme Tidepool -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Tidepool.app
open build/Build/Products/Debug/Tidepool.app --args --demo   # everything sped up, for trying things out
open build/Build/Products/Debug/Tidepool.app --args --holiday halloween   # preview a holiday outfit
open build/Build/Products/Debug/Tidepool.app --args --time night          # force dawn / day / dusk / night
open build/Build/Products/Debug/Tidepool.app --args --bottle              # a message in a bottle drifts in after 3 s
open build/Build/Products/Debug/Tidepool.app --args --garden-days 91      # flower + meadow as on day 91
open build/Build/Products/Debug/Tidepool.app --args --demo --time night --stars --moon 1   # clear full-moon night, a shooting star every 15–25 s
open build/Build/Products/Debug/Tidepool.app --args --weather rain        # or snow: rain / snow over the pool
open build/Build/Products/Debug/Tidepool.app --args --visitor friend      # crab / seagull / fish / friend, every few seconds
open build/Build/Products/Debug/Tidepool.app --args --rainbow             # a rainbow right away
open build/Build/Products/Debug/Tidepool.app --args --dreams              # asleep after ~30 s idle, a dream every few seconds
open build/Build/Products/Debug/Tidepool.app --args --demo --theme "Pixel Tide" --season autumn   # radio starts with that theme; force the season
open build/Build/Products/Debug/Tidepool.app --args --game shellCatch    # opens that game 2 s after launch
```

Builds are ad-hoc signed until a Developer ID certificate exists. Login-item registration only happens when the app runs from `/Applications` or `~/Applications`, so development builds never register themselves.

## 2. Design principles (use these to make decisions)

1. New features are excluded by default. Anything outside the scope in Section 4 must be discussed first. Do not add it on your own.
2. Not disturbing the user beats being cute. When unsure, choose the quieter option.
3. Do not use any API that triggers a system permission prompt unless it has been explicitly discussed and approved.
4. Prefer events over polling. When polling is unavoidable, use low frequency and timer tolerance.
5. Keep platform-independent logic (state machine, rules, content format) strictly separate from macOS-specific code, so a Windows port later only replaces the platform layer.

## 3. Pibbo

- **Species:** sea otter
- **Sprite size:** 16×16 pixels, rendered at integer scale with image smoothing disabled
- **Personality:** slow, half-closed eyes, unbothered, content
- **Art (decided 2026-10-12):** all pixel art is drawn by Claude Code as text pixel grids in `Tools/generate_sprites.py`, and that is the real art (Pibbo, actions, flower, UI font, icons, bubble). Hand-drawn replacements stay possible if they keep the sheet layout and manifest keys.
- **Setting:** a small strip of water along the bottom edge of the screen. Pibbo floats in it.

### Required states (every skin must provide these)

| State | What it looks like |
|---|---|
| `hidden` | Only the eyes and top of the head above the water line |
| `peek` | Head out of the water, eyes visible |
| `chill` | Floating, half-closed eyes, holding a shell |
| `music` | Floating with headphones, bobbing gently |
| `sleep` | Eyes closed, wrapped in kelp, small "zzz" |

### Optional actions (skins may omit these; missing ones fall back to `chill`)

System actions are never picked at random: `unplug` (headphones off, plays once) when music stops; `backfloat` (on his back with a rising heart), `holdpaw` (raised paw, swaying) and `look` (glances at a splash) for play; `ripple` is a one-shot splash effect drawn over the water. Provided by the bundled skin (v0.2.0): `water` (waters his flower), `crack` (cracks a shell with a rock), `groom`, `stretch`, `yawn`, `sunbathe` (sunglasses), `raindrops` (rain), `cocoa` (snow), `huddle` (storm), `leaf` (autumn), `petal` (spring), `stargaze` (clear night). Which ones fit the moment is decided by `World.ActionRules`.

### Smooth transitions

Switching clips plays a short in-between first (Section 11): he rises and sinks through the water line, rolls onto his back with a splash, and puts props on or takes them off (headphones, kelp, sunglasses, cocoa mug, watering can, raised paw). They're drawn in `Tools/generate_sprites.py` (`TRANSITIONS`). The flower follows him: it hides only once he has sunk and comes back halfway through his rise.

### Holiday outfits (v0.3.2)

Every clip exists once more per outfit, wearing a small 3-row hat that sits *on* the head (a 16×16 frame has only one free row above it): pumpkin hat (`halloween`), Santa hat (`christmas`), party hat (`newYear`), red flower knot (`lunarNewYear`). `Tools/generate_sprites.py` stamps the hat on the topmost run of 4+ outline pixels, so it follows the head in every pose (peek, hidden, back-float, …); `submerged` and `ripple` have no otter and stay plain. The manifest's `outfits` key maps each holiday to a row offset (Section 11).

**Holiday decor (v0.4.1):** an animated extra in the flower's cell while a holiday is on, played in a sublayer of the garden layer so it shows and hides with the flower (`decor` key, Section 11; `DECOR` in `Tools/generate_sprites.py`). Halloween: a jack-o'-lantern bobbing in the water in front of the rock, candle flickering, and a bat flapping above the flower. **Winter decor (v1.1):** decor can also sit on the meadow rock (`meadowDecor`, a sublayer of the meadow) and have a night version (`holiday@night`, used at night when present). Christmas: twinkling lights around the flower pot and a little tree with a star on the meadow rock. New Year: bunting across the meadow rock; at night also little fireworks above the flower. Lunar New Year: two red lanterns swaying on a string over the meadow rock. `preview-holidays.gif` shows them all.

### The flower (decided 2026-10-12)

A flower in a pot on a rock to Pibbo's left. It grows with real days since the first launch (seed → full bloom in ~2 weeks, `World.Garden`), needs no care and never wilts, so it is not a pet stat. It only shows while Pibbo shows his face; when he sinks, it hides too. Skins provide it through the optional `garden` key (Section 11); skins without one simply have no flower.

**The meadow (v0.7.0, approved 2026-10-23):** after the flower blooms, the long rock to its left slowly fills up: moss (day 21), mushrooms (35), a succulent (49), a little blue flower (63), a starfish (77), a shell and a butterfly (91), then it stays like that. Nothing resets or wilts, and there is no counter or progress UI, so it is not a collectible. It is drawn by the garden layer one cell to the left (the window is one cell wider), so it shows and hides with the flower. `World.Garden.meadowDays`; skin key `meadow`. In `--demo` the real flower seemed to "start over": that was only the demo clock (30 s = 1 day) restarting at every launch; real users never see a reset. `--garden-days <n>` previews any day.

### Message in a bottle (v0.7.0, approved 2026-10-23)

Every 2–4 days a bottle drifts into the channel between the meadow rock and the flower's rock (it brings its own strip of water, so it shows even while Pibbo hides). Click it and Pibbo comes out, reads the note (`note` action) and a bubble shows one of `Strings.bottleNotes` for ~7 s, even over music. Unopened, it drifts off after 30 min. Never in work mode (a bottle due then waits until work mode ends); arrival is quiet, Pibbo doesn't pop up. `Brain.nextBottle` is saved in UserDefaults so the wait carries over launches. Demo: every 40–70 s, stays 45 s.

### Visitors (v1.0, approved 2026-11-02)

Some of Pibbo's own appearances (35 %, demo 70 %) bring a visitor instead of an idle action, chosen by `World.Visitors` (weighted; crab ×3 on dry days, seagull ×3 by day when it isn't raining, fish ×3 unless stormy or snowing, the friend otter ×1 unless stormy; nobody in a storm). Pibbo looks at the shore folk (`look`) and reaches out to hold paws with his friend (`friendpaw`, the paw-hold mirrored). He stays out for the whole visit plus 1.5 s; no music invitation then. Brain outputs `visitor`; the platform plays it once on its own layer (between the garden and Pibbo) and lets it finish even if Brain moves on. Visits never happen during calls or work mode. Crab: walks along the shore toward Pibbo, waves its claws, walks back (5.5 s). Seagull: glides down onto the meadow rock, hops, looks round, flies off (5.3 s). Fish: jumps between the flower and Pibbo (1.2 s). Friend otter (lighter fur): swims in from the left, holds paws, swims away (14 s). `preview-visitors.gif` shows them all; `--visitor <name>` brings one every few seconds.

### The seagull's gift (v1.0)

Seagull visits are counted (`seagullVisits`, saved except in `--demo`). On the fifth (`World.SeagullGift`) the seagull brings a feather in its beak (`seagullGift` visit), sets it on the meadow rock and flies off; from then on the feather (`gift` frame, a sublayer of the meadow) stays for good (`seagullGiftBrought`). One gift, ever; no counter or hint is shown. Brain only knows "seagull"; the platform picks the gift variant.

### Rainbow after rain (v1.1)

When the weather turns from rain or storm to clear or cloudy, outside the night, a rainbow arches over the whole pool for 10 minutes (half see-through, so the flower shows behind it; three static `rainbow` frames, sublayers of the garden so it shows with the flower; Pibbo's own sprite is drawn over his part). Rain coming back takes it away. Brain's `.rainbowAppeared` brings Pibbo up to look (`admire`, eyes up, 8 s) when he could appear on his own anyway (hidden, not quiet, no music, user not away). The 10-minute fade is the only timer, and only after rain. `--rainbow` shows one at launch.

### Dream bubbles (v1.1)

While Pibbo sleeps (user away), every 4–8 min a thought bubble shows for 5 s with what he dreams of: something he saw lately (the controller's `memories`, last 6: visitors, a bottle he read, a star he wished on, music), or shells, his flower or bubbles before he has seen anything. Icons only, no words (`Strings.dreams`, an exception to Section 6's "short phrase + emoji": a dream has no words). Never during work mode or calls, never over music; waking up ends them. Brain's `Bubble.dream(pick:)`; demo every 10–15 s; `--dreams` makes him fall asleep at the next idle check.

### v1.2 little things

- **Playing along (Pixel Tide):** a theme's `theme.json` may name a `toy`, a skin action Pibbo plays while it plays. Pixel Tide's is `game`: every 40–80 s (demo 8–12) he picks up the little handheld (headphones on), plays for 8 s and says `GG! ✨` for the last 3 s, even over music. Brain's `.radioToyChanged`; its prop on the rock is the `handheld`.
- **The secret flip:** three clicks on the water within 1.2 s and he flips out of the water with a big splash (`flip`, one-shot, 1.4 s). Not mentioned in the app; it is a hint on the GitHub page. Brain's `.splashCombo`; never in Dive time or calls.
- **Drifting by:** while Pibbo is out, every ~30 s a spring petal, summer dandelion fluff or autumn leaf drifts across the pool (`World.Drift`, skin key `drift`; nothing in winter, rain, storm or snow). One looping Core Animation keyframe animation on a sublayer of the garden: no timers.

### Quiet during calls (v1.0)

While any camera or microphone is in use by any app (spike 8: a call, most likely, including browser calls and screen sharing from another app), Pibbo stays under water like in work mode: no surfacing, bubbles, bottles or shooting stars; hover and play are ignored. A call starts after 2 s of use and ends after 5 s of quiet (so Siri or a quick dictation don't count); afterwards he goes back to hidden without popping up. `Signals/CallMonitor` reads only the devices' "running somewhere" flags (property listeners, no polling); Brain's `.callChanged`. Unlike work mode a click still opens the menu.

### Work mode look

Pibbo sinks under the water. Only a few small bubbles rise occasionally. Skins provide this as the optional action `submerged`; if missing, fall back to `hidden`.

## 4. Scope of the first version

**In scope:**
- The five required states and transitions between them
- Hover to reveal, click to open a small menu
- Work mode (do not disturb)
- Detect external music playback and switch to `music`
- Built-in lofi playback
- Small actions driven by time of day, weather, and season, plus everyday idle actions while Pibbo is out
- The flower (Section 3), approved 2026-10-12
- Pixel-style speech bubbles and click menu (pixel font drawn by `Tools/generate_sprites.py`)
- Gentle mouse play (approved 2026-10-14): rub to pet, rest the cursor to hold paws, click the water to splash. Mouse only, inside our own window, no permission. (Reacting to what the user types anywhere was considered and dropped: it needs Input Monitoring and would put private text on screen.)
- Holiday outfits
- The meadow and messages in a bottle (approved 2026-10-23)
- Moonlight on the water and shooting stars with wishes (approved 2026-10-24)
- v1.1 (approved 2026-11-03): winter holiday decor, rainbow after rain, dream bubbles
- v1.2 (approved 2026-11-04): fourth theme "Pixel Tide" with a handheld-game prop, Pibbo playing that game while it plays, a hidden triple-splash flip, seasonal things drifting by
- **Planned, not built (approved idea 2026-11-04): games with Pibbo**, a fourth menu item `Game time 🎮` opening a list of small pixel games; heavier only while a game is open. The brief and open questions are in `docs/games-plan.md`
- v1.0 (approved 2026-11-02): weather in the pool (rain ripples, snowfall, snow on the rocks), quiet during calls, visitors (crab, seagull, fish, a friend otter), the seagull's gift
- Launch at login

**Out of scope:**
- Pomodoro, to-do lists, focus statistics
- Hunger, affection, or any other pet stats
- Chat or AI conversation
- Interacting with other windows (e.g. sitting on title bars)
- Multiple displays (main display only)
- Controlling external music playback (read only)
- Collectibles (e.g. cassette tapes)
- Location-specific actions (e.g. city vs. beach)

## 5. Behavior state machine

### Position
On the bottom edge of the main display's visible frame (above a bottom Dock, beside a side Dock, at the edge when it auto-hides). Default: the bottom-right corner. The user can drag Pibbo left and right along that edge (v0.3.0); a press becomes a drag after 4 pt of movement, otherwise it is a click. The spot is saved as a fraction of the edge (`shorePosition`), so it survives resolution and Dock changes. Bubbles and the menu follow him and stay on screen.

### Default flow

```
launch → peek (~5 s) → chill → no interaction for a while → hidden
```

### Transition rules (values are starting points, to be tuned)

| Trigger | Result |
|---|---|
| Mouse hovers over Pibbo | `hidden` → `peek` / `chill` (ignored in work mode) |
| No interaction with Pibbo for 2–3 minutes | Back to `hidden` |
| Random, once every 30–60 minutes | Pibbo appears and performs a small action (5–10 s), then returns to `hidden` |
| External music starts playing | Switch to `music`; return to the previous state when it stops |
| No keyboard/mouse input for ~10 minutes | `sleep` |
| Late night | Stronger tendency toward `sleep` |
| A fullscreen Space is active / screen locked / system asleep | Fully hidden; pause all timers and animations |
| Pibbo is out (`chill`) for 25–50 s | He does a small idle or context action (5–10 s), then keeps chilling |
| Mouse rubs back and forth over Pibbo (4 direction changes of ≥ 4 pt within 1.5 s) | `backfloat` for ~4 s, then back to what he was doing |
| Cursor rests on Pibbo (moves < 3 pt for 2 s) | `holdpaw` until the cursor moves or leaves |
| Click on the water / flower beside Pibbo | A `ripple` where you clicked; Pibbo plays `look` for ~1.5 s |
| A message in a bottle is due (every 2–4 days) | The bottle floats beside Pibbo for 30 min; click it → Pibbo reads the note (~7 s) |
| Clear night, every 20–60 min | A shooting star; a click on Pibbo within 6 s makes a wish (`wish` + `Made a wish ✨`) instead of opening the menu |
| A camera or microphone is in use (2 s) | Pibbo dives and stays down until it has been off for 5 s |
| Click on Pibbo | Open the menu |

Play (rub, hold, splash) wakes Pibbo, restarts the hide timer, shows over `music` for its duration, and is ignored in work mode. Mouse moves are only tracked while the cursor is over Pibbo, so idle cost stays zero.

### Click menu

A pixel menu in the bubble style (not a system menu), above Pibbo. Hover highlights a line. It closes after a pick, a second click on Pibbo, when another app activates, or ~1 s after the mouse leaves it (4 s if the mouse never comes over). No global event monitors.

- `Music Time? 🎧` / `Tunes off 🐚` — play / stop built-in lofi
- `Dive time 🫧` — enter work mode: Pibbo stays submerged, ignores hover, never appears on his own, until the user clicks him again
- `Swim away 👋` — quit

### Occasional music invitation

- Sometimes, when Pibbo appears on his own, a `Music Time? 🎧` bubble pops up. It only plays if clicked; otherwise it disappears after ~6 s. Pibbo stays out while it is up.
- 30 % of random appearances, and at most once per hour: roughly every 2–3 hours. Never while any music is playing. Never in work mode. Never without built-in tracks.
- Bubbles and the menu are drawn at half of Pibbo's pixel size (2× instead of 4×) to stay small.

## 6. Text style

- Short English phrases, a little otter-flavoured (swimming, diving, shells, kelp), each with an emoji (updated 2026-10-12)
- Sentence case is fine; keep it simple and brief
- Examples: `Music Time? 🎧`, `Dive time 🫧`, `Swim away 👋`, `Kelp nap zzz`, `Snow! Cocoa? ❄️`
- All strings live in one string table (`Sources/Strings`). No hard-coded strings in code.
- Every character must exist in the pixel font; a new emoji means drawing a new icon in `Tools/generate_sprites.py`. `ContentTests` checks every string.

## 7. Tech stack

- **Language / frameworks:** Swift + AppKit + Core Animation
- **Do not use** Godot, SpriteKit, or any engine with a continuous render loop. Reason: when Pibbo is still, the process should be fully idle, with animation handled by the system render server.
- **Language split:** everything that ships to users (the app itself, spikes that test system APIs) is **Swift**. **Python** is only for developer tooling that never ships: sprite generation, offline BPM / beat-map analysis (librosa), content pack validation, build helpers. Do not write app code in Python (no PyObjC, py2app, or PyInstaller). Reasons: an embedded interpreter breaks the size and memory budget, bundled Python apps are fragile to sign and notarize, and the Steamworks SDK is best supported from C++/Swift.
- **Python tooling:** lives in `Tools/`, targets Python 3.10+, lists its dependencies at the top of each script, and is run manually by the developer.
- **Minimum macOS:** 13 (needed for `SMAppService` launch-at-login)
- **Project generation:** XcodeGen (`project.yml`). Build everything from the command line with `xcodebuild`; never depend on manual Xcode GUI steps.
- **App type:** `LSUIElement = true`. No Dock icon, no menu bar icon. All interaction happens by clicking Pibbo.
- **Bundle ID:** `io.github.eric031212.pibbostidepool` (final, v1.0; was `com.tidepool.app`). `App/SingleTidepool` copies the old preferences once (first launch date, next bottle, coordinate, shore position; not the login-item flag, so the new ID registers itself once more) and keeps one Pibbo on screen: a second copy quits, a running pre-1.0 copy is force-quit (a signal, not an Apple Event)

### Module layout

```
Sources/
  App/        entry point, lifecycle, launch at login
  PetWindow/  transparent window, position (Dock / screen corner)
  Renderer/   sprite sheet loading, CALayer frame animation
  Brain/      state machine and rules (pure Swift, no AppKit, unit tested)
  World/      time of day, season, weather mapping, action rules, flower growth (pure Swift, unit tested)
  Signals/    providers of external signals (idle, frontmost app, fullscreen, lock, music, time, weather)
  Music/      built-in player, external music watchers, beat maps
  Games/      little games' rules: GameSession (fixed 60 Hz step, pause, best score), GameCatalog, ShellCatch (pure Swift, unit tested)
  GameWindow/ the game's own key window, input (keys, swipe, mouse; only in that window), frame loop, drawing; exists only while a game is open
  Content/    content pack loading and validation
  Strings/    string table
  Steam/      Steamworks integration (Steam build only)
```

`Brain` only consumes events from `Signals` and outputs "which state to enter / which action to play". It never calls system APIs directly.

## 8. System APIs and permission policy

Goal: **the app never triggers a system permission prompt.**

| Need | Approach | Status |
|---|---|---|
| Transparent always-on-top window | `NSPanel`, borderless + nonactivating, clear background, level `.floating`, `[.canJoinAllSpaces, .stationary, .ignoresCycle]`, `hidesOnDeactivate = false`, window only as large as the sprite area | VERIFIED, no prompt; crisp; clicks on transparent pixels pass through; clicking never activates the app or steals focus (spike 3) |
| User idle time | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, kCGAnyInputEventType)` | VERIFIED, no prompt; resets on any input, keeps counting while locked (spike 2) |
| Frontmost app changes | `NSWorkspace.didActivateApplicationNotification` | VERIFIED, no prompt; fires on every switch incl. `loginwindow` on lock (spike 2) |
| Hide during fullscreen | ~~Bounds check~~ FAILED (spike 2). ~~Keep the panel off fullscreen Spaces + occlusion~~ FAILED (spike 3: every `.canJoinAllSpaces` window shows on fullscreen Spaces, with or without `.fullScreenAuxiliary`). **Chosen (spike 3):** 0.5 s after `activeSpaceDidChange`, read `CGWindowListCopyWindowInfo` layer + owner name + bounds only (no titles): fullscreen Space ⇔ **no** full-screen Finder window at `kCGDesktopIconWindowLevel` **and** a full-screen `WindowManager` window at `kCGDesktopWindowLevel + 1`. Undocumented; if it breaks it fails safe (Pibbo stays visible) | Works in spike 3; [UNVERIFIED] follow-up test pending (Section 16) |
| Screen lock / sleep | Distributed `com.apple.screenIsLocked` / `screenIsUnlocked`; `NSWorkspace` `willSleep` / `didWake` / `screensDidSleep` / `screensDidWake`; lock state at launch from `CGSessionCopyCurrentDictionary` | VERIFIED, no prompt (spike 2) |
| Dock position | Compare `NSScreen.frame` with `visibleFrame`; reposition on `NSApplication.didChangeScreenParametersNotification` | VERIFIED: bottom / left / right / auto-hide all handled by placing at `visibleFrame` bottom-right (spike 3) |
| External music | Observe distributed notifications `com.apple.Music.playerInfo` and `com.spotify.client.PlaybackStateChanged` | Apple Music: VERIFIED, no prompt, state + track info but no position, no state at launch (spike 1). Spotify: [UNVERIFIED], not installed on test Mac |
| Built-in music playback | `AVAudioPlayer` | — |
| Approximate location | `https://ipwho.is/` (free, no key, HTTPS, commercial use allowed, 1,000 req/day) when its `timezone.id` matches `TimeZone.current`; otherwise (offline, VPN) the zone's city coordinate from a bundled tzdb `zone.tab` (public domain, 19 KB). **Do not use CoreLocation.** | VERIFIED (spike 5) |
| Weather | MET Norway `locationforecast/2.0/compact` (free, commercial OK, CC BY 4.0), request every 1–3 hours and never before `Expires` (`World.WeatherSchedule`, tested; a later `Expires` wins over the 3-hour cap since v1.2.1); after a time-zone change the zone's city is used at once and the location is looked up again; coordinates rounded to 2 decimals; identifying `User-Agent` required. ~~Open-Meteo~~: free tier is non-commercial only | VERIFIED (spike 5) |
| Region for holidays | `Locale.current.region` (confirmed: the user's region setting, not the physical location) | — |
| Call detection (camera / microphone in use by any app) | CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` per camera, CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere` per input device, property listeners on each plus the device lists. Never opens a device | VERIFIED (spike 8 + developer test 2026-11-02): no prompt; Pibbo dives when the camera turns on and comes back after |
| Launch at login | `SMAppService.mainApp.register()`, registered automatically on first launch | VERIFIED: no prompt, no approval needed, status `enabled` at once; macOS shows a one-time "Login Item Added" notification (cannot be suppressed); app started automatically after reboot (spike 6) |

**Forbidden:** CoreLocation, AppleScript / Apple Events to control other apps, Accessibility permission, Screen Recording permission, Apple private frameworks (e.g. MediaRemote).

## 9. Music

### External music
- Read playback state and track info only. Never control playback.
- Supports Apple Music and Spotify. Other sources (browsers, etc.) are out of scope for v1.
- For external music, Pibbo only does a generic gentle bob, no precise beat sync. The bob is drawn in the `music` clip's frames; the app never moves the sprite layer, because that would move the water strip too (spike 4).

### Built-in lofi
- Tracks generated with Suno, roughly 1–2 hours total, looped. The developer's Suno plan is **Pro** (commercial use allowed); the Steam store page must still disclose AI-generated content.
- **Themes (v0.3.0):** tracks are grouped into themes. Workflow: export WAV from Suno → `Assets/MusicMasters/<Theme Name>/` → `python3 Tools/import_track.py` → `Assets/Music/<theme-slug>/` with `theme.json` (`{"title": …}`), AAC 128 kbps CAF (~1 MB/min) and a beat map per track.
- **No song picking, on purpose:** every start (menu or bubble) is a random theme in shuffled order (`Content.RadioPlan`); when a theme runs out, another theme follows (a different one when there is more than one). Fewer clicks, no choice paralysis.
- **Now playing:** while the radio plays, a fixed-width pixel bubble above the tide pool (same width and edges as the pool, tail over Pibbo, ♪ icon) scrolls "theme - track" inside a fixed window. The scroll is one discrete Core Animation keyframe animation stepping one art pixel at a time: crisp, and no timers in our process. It shows for ~15 s when a track starts and while the mouse is on Pibbo (+3 s after), so it stays quiet the rest of the time.
- **Gentle start and stop:** tracks fade in over 1 s. "Tunes off" fades the volume to silence over 1.6 s while Pibbo plays `unplug` (headphones off), then pauses. When external music (Apple Music) stops, Pibbo also plays `unplug`; its volume can't be faded because external playback is read only.
- Current set: "Pibbo's Raft Days" (12 tracks, ~37 min, 35 MB, 2026-10-13), "Solo Float" (12 tracks, ~37 min, 35 MB, 2026-10-17), "Pibbo in the City" (12 tracks, ~37 min, 35 MB, 2026-10-22) and "Pixel Tide" (12 retro-game tracks, ~32 min, 30 MB, 2026-11-04, prop `handheld`, toy `game`): 48 tracks, ~2 h 20 min. Estimated tempos are mostly 60–83 bpm; "Pibbo's Night", "Holding Paws" and "Lights Off" came out ~120, likely double-time of ~60 (half-time feel). Confirm by ear before writing cues.
- `Tools/generate_placeholder_lofi.py` can still synthesize a 27 s placeholder loop for testing.
- Never plays automatically; the user starts it from the menu or the invitation bubble
- **Theme props (v0.6.0):** while a theme plays, its prop stands in the gap between the flower and Pibbo: a street lamp with flickering light (City), a steaming teacup (Solo Float), a bobbing paper boat (Raft Days). `theme.json` names it (`"prop": "streetlamp"`); the skin draws it (`props`, Section 11). It shows with the flower, changes with the theme and goes away when the radio stops. `Tools/import_track.py` keeps extra `theme.json` keys and drops Suno's " - usesuno.com" file-name suffix from titles.

### Beat maps (built-in tracks only)
Each built-in track has a JSON file describing tempo and action cues:

```json
{
  "track": "sunny-afternoon.m4a",
  "bpm": 78,
  "offset": 0.42,
  "cues": [
    { "time": 32.0, "action": "sunglasses" },
    { "time": 96.5, "action": "yawn" }
  ]
}
```

BPM and offset are computed offline by `Tools/import_track.py` (numpy: spectral-flux onsets + autocorrelation; librosa was not needed) and should be checked by ear. No audio analysis at runtime. `title` holds the display name. Cues are not used by the app yet.

**Nodding along (built-in only):** while the radio plays a track with a beat map, the `music` clip runs in time with it: one nod per beat, head down on the beat. `Content.BeatGrid` folds the bpm into 50–100 (so ~120 estimates nod at ~60) and gives the phase; the renderer sets the clip's duration from the tempo and enters it at that phase with `timeOffset`. It is set once per track, re-synced after a pause, and needs no timers. External music keeps the plain `fps` bob.

### Common interface

```swift
protocol MusicSource {
    var events: AsyncStream<MusicEvent> { get }  // started / paused / trackChanged
}
```

Implementations: `BuiltInLofiSource`, `AppleMusicWatcher`, `SpotifyWatcher`. `Brain` subscribes to events and does not care where they come from.

## 10. Weather, seasons, holidays

- **Season:** from the date and hemisphere (sign of the latitude from Section 8's coordinate)
- **Time of day:** dawn / day / dusk / night, computed locally from the coordinate with the sunrise equation (civil twilight = −6°); no network needed; affects actions and lighting on the water
- **Water light (v0.5.0):** the tide pool takes the colour of the time of day: misty pale blue with pink glints at dawn, blue by day, golden at dusk, deep blue with moon glints at night (tuned with the developer 2026-10-21: purple dawn looked odd). The skin's `water` key (Section 11) maps water colours per time; `Content.WaterTint` recolours only the bottom 3 rows of every frame in a copy of the sheet, once per time-of-day change (4 times a day), so splashes, steam and Pibbo keep their colours and idle cost stays zero. `preview-water.png` shows all four; `--time <dawn|day|dusk|night>` forces one.
- **Moonlight (v0.8.0):** `World.MoonPhase` computes the moon's illumination locally (mean synodic month from the 2000-01-06 new moon; within ~half a day), rounded to eighths in `WorldContext.moonlight`. At night the glints on the water (`moonGlint` in the skin) fade from bright at full moon to none at new moon. `--moon <0…1>` forces it.
- **Shooting stars (v0.8.0, approved 2026-10-24):** on clear nights (`WorldContext.isClearNight`), every 20–60 min a shooting star streaks over the pool (one-shot `shootingStar` clip, drawn on top). For 6 s afterwards a click on Pibbo is a wish instead of opening the menu: he puts his paws together (`wish` action) and says `Made a wish ✨`. Missed stars just go by; none in work mode or while the user is away. `--stars` makes any night count as clear.
- **Weather:** map MET Norway `symbol_code` to `clear / cloudy / rain / snow / storm` (mapping in the spike 5 result)
- **Holidays (v0.3.2):** `World.Holidays`, a bundled table keyed by the region setting; no remote updates. Halloween Oct 25–31, Christmas Dec 20–26, New Year Dec 31–Jan 2 (all regions); Lunar New Year from its eve to the 6th day (CN, TW, HK, MO, SG, MY, KR, VN), computed with the system's Chinese calendar. Checked at launch and at every time-of-day change. `--holiday <halloween|christmas|newYear|lunarNewYear>` forces one for testing.
- Examples: snow → hot cocoa, steam rising; rain → Pibbo happily catches raindrops; Christmas → Santa hat
- **Weather in the pool (v1.0):** rain (and storms) fall over every cell with little rings on the water, also over Pibbo's cell while he hides; snow drifts down and settles on the rocks and the pot rim, staying ~2 h after it stops (`weatherEffects`, `snowCover`). No lightning (too disturbing). `--weather <rain|snow|…>` forces the weather

## 11. Content pack format (shared by skins and music)

```
my-skin/
  manifest.json
  sprites.png      sprite sheet with a fixed layout
  tracks/          optional, local import only
```

Example `manifest.json`:

```json
{
  "id": "com.example.my-skin",
  "name": "my skin",
  "author": "someone",
  "version": "1.0.0",
  "type": "skin",
  "frameSize": 16,
  "states": {
    "hidden": { "row": 0, "frames": 2, "fps": 2 },
    "peek":   { "row": 1, "frames": 4, "fps": 6 },
    "chill":  { "row": 2, "frames": 4, "fps": 4 },
    "music":  { "row": 3, "frames": 4, "fps": 6 },
    "sleep":  { "row": 4, "frames": 2, "fps": 1 }
  },
  "actions": {
    "submerged": { "row": 5, "frames": 4, "fps": 2 }
  },
  "garden": { "row": 6, "stages": 6 }
}
```

- Sheet layout: one row per state/action in manifest order, frames left to right, each `frameSize`×`frameSize`. The sheet is as wide as the longest row; unused cells are transparent. The bottom 3 rows of every frame are water, so frames line up with the tide pool strip.
- Optional `garden`: one row with one frame per flower growth stage (static, not animated), drawn to sit on Pibbo's left.
- Optional `"loop": false` on a clip: play once and hold the last frame (used by `unplug`).
- Optional `"beats": n` on a clip: one loop spans n beats; with built-in music the app plays it in time with the track instead of at `fps` (used by `music`, n = 2).
- Optional `outfits`: `{"halloween": {"offset": 24}, …}`; the outfit version of a clip is at `row + offset`. Skins without an outfit show the plain clip.
- Optional `water`: `{"night": {"6fb7d9": "3a548a", …}, …}`, per time of day (`dawn`, `day`, `dusk`, `night`), hex RGB of a water colour → its replacement, applied to the bottom 3 rows of every frame only. Missing times keep the sheet's colours.
- Optional `meadow`: `{"row": …, "stages": 7}`, like `garden` but for the long rock one cell left of the flower (cumulative stages, `World.Garden.meadowDays`). Needs a `garden`.
- Optional `bottle`: `{"row": …, "frames": 4, "fps": 2}`, the message in a bottle, drawn in the flower's cell under the garden with its own water strip.
- Optional `shootingStar`: a one-shot clip (`"loop": false`) drawn on top over the flower's cell on clear nights.
- Optional `moonGlint`: `{"glint": "bfe6f5", "water": "6fb7d9"}`, which sheet colours are the water's glints and plain surface; at night the glint's replacement is mixed toward the water's by how dark the moon is.
- Optional `visitors`: `{"crab": {"row": …, "frames": 22, "fps": 4, "wrap": 8, "path": [2, 4, …]}}`, one-shot visits: `path[i]` is the visitor layer's left edge during frame i, in art pixels from the window's left edge (meadow 0, flower 16, Pibbo 32). Frames and position step together (discrete keyframes), so the walk stays pixel-crisp.
- Optional `drift`: `{"spring": {"row": …, "frames": 2, "fps": 2}, …}`, a tiny looping item in the top-left of its frame, moved across the pool by the app (v1.2).
- Optional `rainbow`: `{"row": …, "stages": 3}`, the rainbow after rain: frames for the meadow's, the flower's and Pibbo's cells (half see-through), together one arc. Needs a `garden`.
- Optional `gift`: `{"row": …, "stages": 1}`, the seagull's present: one static frame over the meadow's cell, shown once it has been brought. Needs a `meadow`.
- Optional `"wrap": n` on a clip or visit: n frames per sheet row, longer clips continue on the rows below. Keeps the sheet narrow: the renderer keeps the whole sheet decoded (plus a recoloured copy at dusk, dawn and night), so a 42-frame row would cost ~20 MB.
- Optional `weatherEffects`: `{"rain": {…}, "snow": {…}}`, looping clips drawn over every cell of the pool while it rains (or storms) / snows; ripples sit in the water rows so the water light recolours them.
- Optional `snowCover`: `{"row": …, "stages": 2}`, static snow on the rocks: frame 0 over the flower's cell, frame 1 over the meadow's. Shown while it snows and for 2 h after.
- Optional `props`: `{"streetlamp": {"row": …, "frames": 2, "fps": 2}}`, looping clips drawn over the garden frame (in columns 11–15, between the flower and Pibbo; holiday decor keeps the left side) while a radio theme that names the prop plays. Needs a `garden`.
- Optional `decor`: `{"halloween": {"row": …, "frames": 4, "fps": 3}}`, a looping clip drawn over the garden frame (transparent elsewhere) while that holiday is on. Needs a `garden`. A key `"newYear@night"` replaces `"newYear"` at night (and may exist alone: then that holiday has decor only at night).
- Optional `meadowDecor`: same as `decor`, drawn over the meadow's cell. Needs a `meadow`.
- Optional `poses` + `transitions` (smooth switches): `poses` maps each clip to a body pose (`under`, `low`, `peek`, `up`, `back`); `transitions` holds in-between clips (played once, then the new clip takes over, scheduled in Core Animation with no timers) keyed `"from>to"`, each side a clip name or `@pose`. Most specific wins: `a>b`, `@poseA>b`, `a>@poseB`, `@poseA>@poseB`; no key means a straight cut. Keep each under ~0.6 s, because Brain's timings start when the clip is shown. Outfits apply to transitions too. `preview-transitions.gif` shows them all.
- Validate on load: reject skins missing a required state; missing optional actions fall back to `chill`. Every clip (states, actions, transitions, decor, props, weather, drift, visitors, bottle, shooting star) and every strip (garden, meadow, snow cover, gift, rainbow) is checked, and `SkinPack.load` checks that every frame, including outfit copies, fits inside `sprites.png` (read from its PNG header). Outfits keep a clip's `wrap` (v1.2.1)
- Packs live in `~/Library/Application Support/Tidepool/Packs/`
- GitHub build: users drop pack folders into that directory manually
- Steam build: the Workshop is only a channel that downloads packs into the same directory

### Steam Workshop
- v1 supports **skins only** (upload and download)
- Music is **not** shared via the Workshop (copyright risk); local import only

## 12. Performance budget

- Idle (Pibbo still): CPU near 0%, no continuous wakeups
- Memory: target under 40 MB
- Animation: `CAKeyframeAnimation` on layer `contents`, rendered by the system. No timer-driven frame loop while idle.
- Periodic work: idle check about every 30 s, weather every 1–3 h, all timers with tolerance
- Network: every request (ipwho.is, MET Norway) runs in its own `URLSession`, invalidated when it finishes. A shared session kept its HTTP/3 (QUIC) connection open with keepalive wakeups (~1.5/s) after each request; found and fixed in v0.5.0
- Pause everything when fullscreen, locked, or asleep
- Timers run on a clock that stops while the Mac sleeps, so a long timer (time of day, weather) fires late by however long the Mac slept. `WorldMonitor` recomputes the world on wake, screen wake, unlock, clock change and time-zone change (found 2026-10-24: day-coloured water at 8 pm after an evening of sleep). Anything scheduled hours ahead must re-check on wake the same way
- One-shot effects (splash, visitor, shooting star) go through `OneShot` in the renderer: each play has a number, so a hide scheduled for an earlier play never cuts a new one short, and `stopEffects()` ends them the moment Pibbo is under water (Dive time, a call) or suspended. The window must obey the same rules as Brain, not just Brain's tests (found in a review, fixed in v1.2.1)
- The radio says "started" only once a track really plays; tracks that fail to load, start or decode are skipped (one pass over the library), and if none plays it goes back to silence. Never headphones without sound
- Verification: Activity Monitor "Energy Impact" stays low; spot-check with `powermetrics` or Instruments

## 13. Distribution

- **First release (decided 2026-10-12):** open source on GitHub, used by the developer and friends for a while. The Steam build and spike 7 are deferred until then.
- **GitHub build:** a DMG on each GitHub release (since v0.4.0), made by `Tools/package_dmg.py`: universal (arm64 + x86_64), app + `Applications` link + `First launch.txt`. Ad-hoc signed for now, so a downloaded copy is blocked on first launch (`spctl` says rejected) until the user clicks Open Anyway in System Settings → Privacy & Security; README explains it. Once a Developer ID exists, set `SIGN_IDENTITY` and `NOTARY_PROFILE` and the same tool signs, notarizes and staples. Consider Sparkle for updates later
- **Steam / Windows: on hold (decided 2026-11-03).** The developer keeps updating the Mac app for fun; the notes below stay for if it resumes.
- **Steam build:** integrate the Steamworks SDK (C++, bridged into Swift) and use the UGC API for the Workshop. Note: requires the Steam client to be running.
- Both builds share one codebase; a build flag enables the `Steam/` module

## 14. Research plan

Each item is an independent minimal prototype that answers one question. Write the conclusion back into the relevant section of this file.

| Order | Spike | Question to answer |
|---|---|---|
| 1 | External music notifications | Without any permission, can we receive Apple Music / Spotify playback notifications? Which fields do they contain? |
| 2 | User state signals | Can idle time, frontmost app, fullscreen detection, and screen lock all be read without permission? |
| 3 | Transparent window | Always on top, transparent, only the sprite area receives mouse events; behavior with fullscreen apps and multiple Spaces |
| 4 | Pixel animation rendering | Is CALayer frame animation crisp at integer scale? Is CPU truly ~0 when still? |
| 5 | Location and weather | Pick an IP lookup service; weather requests and weather-code mapping |
| 6 | Launch at login | Does the first `SMAppService` registration require any user action? |
| 7 | Steamworks | Viable way to call Steamworks UGC from Swift on macOS (**deferred**: GitHub release first, see Section 13) |
| 8 | Call signal | Can we tell a camera or microphone is in use by any app, without a prompt? |

### Spike 1 result: external music notifications (2026-10-12)

Code: `Spikes/01-music-notifications/` (`DistributedNotificationCenter` only). Tested on macOS 27 with Apple Music. **Spotify was not tested** (not installed on the test Mac), so everything below applies to Apple Music only.

1. **Permission prompt?** None. Subscribing and receiving needed no permission, entitlement, or user action.
2. **Fields.** Name `com.apple.Music.playerInfo`, `object` = `"com.apple.Music.player"`. A full notification has: `Name`, `Artist`, `Album`, `Composer`, `Genre` (String); `Total Time` (Int64, milliseconds); `PersistentID`, `Library PersistentID` (Int64; `PersistentID` identifies the track and can be negative); `Player State` (String). `Composer` is sometimes missing (an 8-key notification was seen). **No playback position field.** `Player State` values seen: `Playing`, `Paused`, `Stopped`. Some notifications carry **only** `Player State` (1 key) with no track info.
3. **Which events notify.** Play, pause, resume: one full notification each. Skip forward/back: a full notification for the new track, sometimes preceded ~80 ms earlier by a 1-key `Stopped`. Scrubbing: no dedicated event; it shows up as rapid `Paused`/`Playing` pairs for the same track. A track ending naturally could not be told apart from a skip in the log (both produce a new-track notification). Quitting Music while playing: one 1-key notification (`Stopped` once, `Paused` another time), then nothing.
4. **Started while music is already playing?** Nothing arrives. The tool started at 19:41:22 with music playing and received nothing until the user's next action at 19:41:38. There is **no permission-free way** to read the current state at launch within Section 8's rules: Apple Events / ScriptingBridge need the Automation permission, MediaRemote is private, and `MPNowPlayingInfoCenter` only reports the calling app's own playback. We do not work around this.
5. **Hidden / minimized / other Space?** Still delivered in all three cases (hide + skip, minimize + pause/play, other Space + skip, all via media keys).

**Keys we rely on:** `Player State` (`== "Playing"` means music is on; anything else means off) and `PersistentID` (detect a track change). `Name` / `Artist` are optional extras for display only. Nothing should depend on `Total Time` (it varied by a few seconds for the same track) or on a position.

**Limitations / implications for Brain:**
- At launch the music state is unknown; Brain must start as "not playing" and switch to `music` only on the first `Playing` notification.
- Debounce stop events (e.g. ~1–2 s) so a transient `Stopped` during a track change does not flicker Pibbo out of `music`.
- A 1-key notification can mean "app quit"; treat it as stopped and keep no stale track info.
- Spotify (`com.spotify.client.PlaybackStateChanged`) remains unverified; re-run this spike with Spotify installed before relying on it.

### Spike 2 result: user state signals (2026-10-12)

Code: `Spikes/02-user-state-signals/`. `run.sh` wraps the binary in a minimal ad-hoc-signed `LSUIElement` .app and starts it with `open`, so permission checks apply to the spike itself, not to the terminal. Tested on macOS 27.0.1, 14" MacBook Pro (notch, 1512×982 points).

- **Permission prompt?** None. After the test the spike did not appear under Screen Recording, Accessibility, or Input Monitoring. `CGWindowListCopyWindowInfo` exposed a window name only for one Window Server window, confirming we ran without Screen Recording.
- **Idle time:** `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: kCGAnyInputEventType)` works. Readable at launch, resets on mouse or keyboard input, keeps counting while locked. Video playback does not reset it (Chrome holds a display-sleep assertion, but HID idle keeps growing), so Pibbo may fall asleep while the user watches a video. Accepted: that is quiet behavior.
- **Frontmost app:** `didActivateApplicationNotification` fires on every switch (click, ⌘Tab, Space switch) with an `NSRunningApplication` (name, bundle ID, PID). On lock, `loginwindow` becomes frontmost. Initial value from `NSWorkspace.shared.frontmostApplication`.
- **Fullscreen: the planned check FAILED.** On a notched Mac a native-fullscreen window sits at `0,33 1512×949`, not `0,0 1512×982`; it matches the full screen only for a moment during the Space transition. A "below the notch" rule would also match a zoomed window when the Dock is hidden. Approved design change: stop detecting other apps' fullscreen; keep Pibbo's panel out of fullscreen Spaces and pause on our own panel's occlusion state. Verify in spike 3, including fullscreen video in a browser (not tested here: the video never entered fullscreen).
- **Lock:** `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` arrive immediately, with empty `userInfo`. Lock state at launch: `CGSessionCopyCurrentDictionary()` contains `CGSSessionScreenIsLocked = true` only while locked. The function is public; this key is **undocumented**, so treat a missing key as "unlocked" and rely on the notifications afterwards.
- **Sleep:** closing the lid produced `willSleep` → `screensDidSleep` → `screenIsLocked` → (sleep) → `screensDidWake` → `didWake` → `screenIsUnlocked`. Our 5 s timer simply stopped during sleep and resumed after wake. `willSleep` can fire **without** the system actually sleeping (first lid close: an app held a sleep assertion, `didWake` came 30 s later with no gap in timer ticks), so treat `willSleep`…`didWake` as "pause", never as proof of real sleep. Apple menu → Sleep did nothing while the Claude desktop app held a keep-awake assertion.
- **Events vs polling:** only idle time needs polling (planned ~30 s with tolerance). Everything else is event-driven, and the spike's timer never caught a lock change that the notifications missed.

**APIs we will use:** `CGEventSource.secondsSinceLastEventType`, `NSWorkspace.didActivateApplicationNotification`, `com.apple.screenIsLocked` / `screenIsUnlocked`, `NSWorkspace` `willSleep` / `didWake` / `screensDidSleep` / `screensDidWake`, `CGSessionCopyCurrentDictionary` (launch only). Drop `CGWindowListCopyWindowInfo`.

### Spike 3 result: transparent window (2026-10-12)

Code: `Spikes/03-transparent-window/` (`run.sh` launches it as its own LSUIElement .app; `run.sh --variants` adds the window-configuration test squares). Tested on macOS 27.0.1, 14" MacBook Pro (Retina, scale 2).

- **Permission prompt?** None.
- **Window:** borderless non-activating `NSPanel`, clear background, level `.floating`, `[.canJoinAllSpaces, .stationary, .ignoresCycle]`, `hidesOnDeactivate = false`, app policy `.accessory`. Always on top of normal windows; the Dock (higher level) covers it when an auto-hidden Dock slides up.
- **Rendering:** one 16×16 frame in a `CALayer` with `magnificationFilter = .nearest` at 4× (64 pt = 128 device px) is crisp. CPU 0.0 % while static.
- **Mouse:** clicks on fully transparent pixels pass through to the window behind; clicks on the sprite arrive (`acceptsFirstMouse`). An `NSTrackingArea` with `.activeAlways` reports hover while another app is frontmost, but it is purely geometric (it fires over the transparent margin too), so in the app the tracking rect must be the sprite rect only.
- **Focus:** clicking Pibbo and opening an `NSMenu` (`popUp(positioning:at:in:)`) leaves the frontmost app unchanged, `NSApp.isActive` stays false, the panel never becomes key, and typing continues in the previous app after the menu closes.
- **Spaces:** Pibbo stays on every normal desktop and in Mission Control.
- **Fullscreen:** Pibbo appears on fullscreen Spaces (apps and browser video). Six window configurations were compared (panel vs window, `.floating` vs `.normal`, with/without `.stationary`): every `.canJoinAllSpaces` window showed on fullscreen Spaces; only a single-Space window hid, and it also hides on other normal desktops. The panel's occlusion state stays "visible" on fullscreen Spaces, so occlusion cannot detect fullscreen. **Contradicted the spike 2 plan;** replaced, with approval, by the desktop-window probe in Section 8:

  | Space | Finder @ desktop-icon level | `WindowManager` @ desktop level + 1 | `Wallpaper` |
  |---|---|---|---|
  | normal desktop 1 | yes | no | yes |
  | normal desktop 2 | yes (appears ~0.5 s after the switch) | no | **no** |
  | fullscreen app / video | **no** | **yes** | no |

  Wallpaper is not a usable marker. Require both conditions, and re-check 0.5 s after `activeSpaceDidChange` because the list is mid-transition at the event. Mission Control triggers no Space change.
- **Occlusion** is still useful for lock and display off: `visible` became false on lock and true after unlock; it flickers false→true for a moment on every Space switch, so debounce it.
- **Dock / position:** `visibleFrame` bottom-right is correct for Dock bottom (above it), left, right (left of it), and auto-hide (bottom edge). Every change, including the Dock growing 2 pt when an app launches, arrives as `didChangeScreenParametersNotification`; the 5 s cross-check never caught a missed change.
- **Memory:** ~48 MB RSS (debug build), above the 40 MB target. Re-measure with a release build in spike 4.

### Spike 4 result: pixel animation rendering (2026-10-12)

Code: `Spikes/04-pixel-animation/` (`run.sh` builds **release** by default). It loads `manifest.json` + `sprites.png`, crops all frames once, and plays each clip as a `CAKeyframeAnimation` on `contents` (`calculationMode = .discrete`, `keyTimes` with one more entry than frames, `repeatCount = .infinity`), with `magnificationFilter = .nearest` and implicit actions disabled. The process has no timers. Test hook: the distributed notification `com.tidepool.spike.anim` (object = command) switches clips so measurements need no clicking.

- **Crisp?** Yes. At 4× (64 pt, 128 device px on Retina) every clip is sharp, with no blur, flicker, or cross-fade between frames. Speeds from the manifest (1–6 fps) look fine.
- **CPU when still or animating:** measured with `top` over ~12 s per case for `still`, all six clips, `music` + layer bob, and paused: **0.0 % CPU and 0 idle wakeups** in every case. Core Animation's render server drives the frames; our process sleeps.
- **WindowServer cost:** not measurable. It stayed at ~38 % with Pibbo still, animating, or quit (the baseline load comes from other apps on the test Mac), so the difference is below noise (< 1 %).
- **Memory:** **11 MB** physical footprint (`top` MEM, what Activity Monitor shows) in a release build. The ~48 MB from spike 3 was RSS, which counts shared system frameworks. Well under the 40 MB target.
- **Pause / resume:** `layer.speed = 0` with `timeOffset`, then restoring `beginTime`, freezes and resumes all animations exactly (for fullscreen / lock / sleep).
- **Layer-level bob: do not use.** Moving the sprite layer also moves the water rows at the bottom of every frame, which breaks the "frames line up with the tide pool strip" rule (Section 11). The placeholder `music` clip already bobs inside its frames, and the extra layer bob was indistinguishable from it. Motion belongs in the skin's frames.

### Spike 5 result: location and weather (2026-10-12)

Code: `Spikes/05-location-weather/` (`swift run`). No permission prompt; outbound HTTPS needs none.

- **Approximate location:** `https://ipwho.is/` returned city, region, country, latitude, longitude and `timezone.id` in ~40 ms (≈950 bytes). Its free tier allows commercial use (1,000 req/day, no key, HTTPS works). Use its coordinate only when `timezone.id == TimeZone.current.identifier`; otherwise, and when offline, fall back to the zone's main-city coordinate from tzdb `zone.tab`. In the test the IP city and the zone's main city were ~300 km apart, which is fine for weather. Zone coordinates alone are too coarse for large zones (e.g. `Asia/Shanghai` covers all of China), so IP lookup stays the primary source.
- **Weather provider: changed, with approval.** Open-Meteo works (533 bytes, ~380 ms), but its free API is for non-commercial use only, and a paid Steam app counts as commercial (paid plans start around $29/month). **Use MET Norway** `https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=…&lon=…` instead: free, commercial use OK under CC BY 4.0, global. ~40 KB per response (~310 ms). Rules: identifying `User-Agent` with a real contact, honour `Expires` / send `If-Modified-Since`, at most 4 decimals of coordinates, ≤ 20 req/s for the whole app (hourly refresh with random jitter covers roughly 70k–200k concurrent users; beyond that needs an agreement or a proxy), attribution required.
- **Weather mapping** (MET `properties.timeseries[0].data.next_1_hours.summary.symbol_code`, drop the `_day` / `_night` / `_polartwilight` suffix): contains `thunder` → `storm`; contains `snow` → `snow`; contains `rain` or `sleet` → `rain`; `clearsky`, `fair` → `clear`; `partlycloudy`, `cloudy`, `fog` → `cloudy`; anything else → keep the previous category. (Open-Meteo WMO mapping, for reference: 0–1 clear, 2–3 / 45 / 48 cloudy, 51–67 / 80–82 rain, 71–77 / 85–86 snow, 95–99 storm.)
- **Season / time of day:** computed locally. The sunrise-equation implementation matched Open-Meteo's sunrise/sunset within 1 minute, so no sun API is needed. Polar day/night returns no events (treat as day / night).
- **Offline:** every request failed within 5 ms ("Internet connection appears to be offline"), the zone coordinate was used, and season and time of day were still computed. Weather should then stay at its last known value or `unknown` (no weather actions).
- **Holidays:** `Locale.current.region` can differ from the physical location (the test Mac's region setting was a different country from its time zone). Confirmed by the developer: holidays follow the region setting.
- **Privacy:** the IP address reaches ipwho.is; a coordinate rounded to 2 decimals (~1 km) reaches MET Norway. The spike never prints the IP.

### Spike 6 result: launch at login (2026-10-12)

Code: `Spikes/06-launch-at-login/`. `run.sh register|unregister|status` installs an ad-hoc-signed LSUIElement app at `~/Applications/Tidepool Login Spike.app` and launches it with one command; every launch appends to `~/Library/Logs/TidepoolLoginSpike.log`. The test app was unregistered and deleted afterwards.

- **Does the first registration need user action?** No. `SMAppService.mainApp.register()` returned without error and the status went from `notFound` to `enabled` immediately (never `requiresApproval`). No permission prompt.
- **But it is not silent:** macOS immediately shows a system notification: *"Login Item Added — "<app name>" will open automatically when you log in. You can manage this in Login Items & Extensions."* It needs no click and disappears by itself, but the app cannot suppress it. The app then appears under System Settings → General → Login Items & Extensions → Open at Login, with its `CFBundleName`.
- **Does it really start at login?** Yes. After a reboot the app launched with no arguments, parent PID 1 (launchd), 44 s after boot, status `enabled`.
- **Unregister:** `unregister()` returned without error, status `notRegistered`.
- **Status before registering** was `notFound` (not `notRegistered`), so don't treat `notFound` as an error on first launch.
- **Limitations:** tested with an ad-hoc signature in `~/Applications`; re-test with the Developer ID-signed, notarized build in `/Applications` before release.
- **Conflict with Section 1 ("zero setup", Principle 2 "quiet"):** the notification is unavoidable on the first launch. **Decided:** accept it (it appears once and is transparent to the user); keep registering automatically on first launch, no menu toggle.

### Spike 8 result: call signal (2026-11-02)

Code: `Spikes/08-call-signal/` (`run.sh [seconds]` wraps it in its own ad-hoc-signed LSUIElement app, like spike 2, and logs to `.build/call.log`). Why: detecting meeting apps by the frontmost app fails exactly when it matters, because presenting means switching to another app while the call app stays in the background.

- Reading `kCMIODevicePropertyDeviceIsRunningSomewhere` (every camera, including Desk View and Continuity cameras) and `kAudioDevicePropertyDeviceIsRunningSomewhere` (every input device, including virtual ones such as a meeting app's audio driver) works from a plain app; all values read `off` with nothing in use, and every listener registered (`noErr`).
- Only flags are read; no device is opened, so no audio or video is ever seen by Tidepool.
- **Verified by the developer (2026-11-02):** with the camera turned on Pibbo dives, and returns after; no permission prompt appeared.
- Device names in the log can contain personal names (e.g. a phone's name); never copy them into this file.

## 15. Working rules for Claude Code

- Prototype before production code. Spikes live in `Spikes/` and are never mixed into the main project.
- After each spike, update the status column in Section 8 and record the conclusion in Section 14.
- Never add anything from the "Out of scope" list in Section 4. Never introduce an API that triggers a permission prompt.
- App code is Swift only. Python is allowed only in `Tools/` (see Section 7).
- The `Brain` module must have unit tests.
- To change any pixel art, edit and rerun `Tools/generate_sprites.py`; never hand-edit the generated PNGs.
- Tasks that need a human (art, music, signing certificates, system permissions) must not be worked around. List them for the developer instead.

### Working with the developer (learned through v0.3.2)

- The developer writes in Chinese; reply in Chinese. User-facing app text stays English (Section 6). README and release notes: short, casual, with emoji. The README is a pixel-styled field guide made by `Tools/generate_github_page.py` (2026-11-03): explore-by-hints, not a feature list; add a hint there when a feature ships. GitHub wraps README images in links, so clickable `<summary>` lines must stay text
- New features are proposed first and built only after a yes (Principle 1). Present options with a recommendation; flag anything that conflicts with this file instead of changing the design silently.
- Hand-off for testing: build, launch the app yourself, then give a short numbered checklist of what to try. `open` on an already-running app ignores `--args`, so relaunch with `pkill -x Tidepool; open … --args …`. `--demo` speeds everything up; `--holiday <name>` previews an outfit; `--time <dawn|day|dusk|night>` forces the time of day; `--bottle` brings a bottle in 3 s; `--garden-days <n>` previews the flower and meadow on day n; `--stars` makes any night clear (shooting stars); `--moon <0…1>` sets the moonlight; `--weather <rain|snow>` forces the weather; `--visitor <crab|seagull|fish|friend>` brings that visitor every few seconds; `--rainbow` shows a rainbow at launch; `--dreams` makes him fall asleep quickly and dream often; `--theme <title>` starts the radio with that theme; `--season <name>` forces the season; `--game <id>` opens a game 2 s after launch. Debug builds also take distributed notifications `io.github.eric031212.pibbostidepool.debug.game` (object `open` / `press` / `right` / `stop` / `close`) to measure an open game without clicking.
- The repo is **public**: never put personal data (city or location, machine host name, email) in files, test fixtures, or commit messages. Commits use the repo-local identity already set in `.git/config`; don't change it.
- Music: new tracks arrive as WAVs in `Assets/MusicMasters/<Theme Name>/` → `python3 Tools/import_track.py`. It re-encodes every theme and the old CAFs come out byte-different (same audio): `git checkout -- Assets/Music/<old-theme>` afterwards so only the new theme is committed. Art: edit `Tools/generate_sprites.py` and rerun; rerun `Tools/generate_promo.py` / `Tools/generate_promo_video.py` when the promo material should follow.

### Working on two machines (decided 2026-11-02)

- The Windows port is built on the developer's own Windows PC; the Mac stays the home of the macOS app. GitHub (`main` of github.com/Eric031212/pibbos-tidepool) is the only link between them.
- **On Windows, always start by cloning the repo or `git pull` on `main`**, before reading or changing anything; push when a piece of work is done.
- On the Mac, push finished work before the developer switches to Windows, so the PC starts from the latest state.

- CI (`.github/workflows/tests.yml`, since v1.2.1) runs `swift test` on every push to `main`; the app itself is still built and checked by hand before each release.

### Release checklist (only when the developer says to release)

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`; rerun `Tools/generate_github_page.py` (add hints for new features) and update this file.
2. `swift test` (all pass) → `xcodegen generate` → Release build → check `CFBundleShortVersionString` in the built Info.plist.
3. Launch the Release build; after Pibbo hides, `top -c d -pid <pid>` should show ~0 % CPU and ~0 idle wakeups.
4. Commit with a summary message → push `main` → annotated tag `vX.Y.Z` → push the tag → `python3 Tools/package_dmg.py` → `gh release create vX.Y.Z dist/PibbosTidepool-X.Y.Z.dmg` with casual emoji notes (point to the README's Open Anyway steps until a notarized build exists; credit Suno / MET Norway).
5. Releases so far: v0.1.0 app shell · v0.2.0 actions, flower, pixel UI · v0.3.0 themed radio, ticker, drag · v0.3.1 mouse play · v0.3.2 holiday outfits · v0.3.3 smooth transitions · v0.4.0 second theme "Solo Float", nodding to the beat · v0.4.1 Halloween decor · v0.5.0 water light by time of day · v0.6.0 third theme "Pibbo in the City", theme props · v0.7.0 the meadow, messages in a bottle · v0.8.0 shooting stars, moonlight, wake fix for time of day · v1.0.0 "Pibbo's Tidepool": visitors, the seagull's gift, weather in the pool, quiet during calls, final bundle ID · v1.1.0 winter holiday decor, rainbow after rain, dream bubbles · v1.2.0 fourth theme "Pixel Tide", playing the handheld, the secret flip, seasonal drifting · v1.2.1 sturdiness: effects obey state, radio never stuck, full skin validation, weather Expires and time zones, CI.

## 16. Open items

- [ ] Trademark / name conflict check for "Tidepool" and "Pibbo" before public release
- [x] Final bundle ID: `io.github.eric031212.pibbostidepool` (v1.0, with data migration)
- [ ] Exact timing values for state transitions (tune after real use)
- [ ] Follow-up test for the fullscreen-Space probe (Section 8): rapid Space switching, switching between two fullscreen apps, split-view fullscreen, Finder desktop icons disabled (`CreateDesktop = false`)
- [x] IP lookup service: ipwho.is (spike 5)
- [x] MET Norway `User-Agent`: `PibbosTidepool/<version> (+https://github.com/Eric031212/pibbos-tidepool)`
- [x] MET Norway attribution (CC BY 4.0): README + `CREDITS.md` (bundled in the app)
- [x] "Login Item Added" notification on first launch: accepted (spike 6)
- [x] Open-source license: GPL-3.0; public repo `pibbos-tidepool` on GitHub, first tag v0.1.0
- [x] Apple Developer account: not planned (decided 2026-11-02). Next: a Windows build, then Steam (Steam-installed Mac apps aren't quarantined, so no notarization needed there). `Tools/package_dmg.py` still supports signing if that changes
- [ ] Test the x86_64 slice on an Intel Mac or with Rosetta (the dev Mac has neither): deferred to the Steam release
- [ ] Re-test launch at login with a Developer ID-signed build in `/Applications` (spike 6 used an ad-hoc-signed app in `~/Applications`)
- [x] Privacy note in README (IP → ipwho.is, ~1 km coordinate → MET Norway); repeat it on a store page later
- [x] Built-in lofi tracks: 36 tracks in 3 themes, ~1 h 50 min (planned 1–2 hours)
- [x] Pibbo sprite art: drawn by code in `Tools/generate_sprites.py` (v0.2.0)
- [x] Display name: "Pibbo's Tidepool" (decided 2026-11-02)
