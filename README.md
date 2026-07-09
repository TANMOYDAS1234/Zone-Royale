# 🎯 Zone Royale

A lightweight 2D **battle royale** built with **Flutter + Flame**. 10 players drop in,
loot weapons, fight, and survive the shrinking gas zone — last one standing wins.
Runs on **Android, and the same code also runs on web + desktop**.

> Status: **playable single-player prototype** — you vs 9 AI bots. Real online
> multiplayer is the next milestone (see Roadmap).

---

## ▶️ How to play

**Phone (touch):** left stick = move · right stick = aim & auto-fire.
**PC (keyboard/mouse):** `WASD`/arrows = move · mouse = aim · click = fire · `R` = reload.

- Grab better guns (SMG, Shotgun, Rifle, Sniper) and medkits off the ground.
- Stay inside the blue circle — the purple gas outside drains your health.
- Eliminate everyone or outlast them. `#1` = 🏆 Winner Winner.
- Share your placement from the end screen.

---

## 🛠️ Run & build

```bash
flutter pub get

# run on the connected phone (hot reload)
flutter run -d <device-id>

# build the installable Android app
flutter build apk --release        # -> build/app/outputs/flutter-apk/app-release.apk

# same code, other targets
flutter run -d chrome              # web
flutter run -d windows             # desktop
```

### Regenerate the logo / icon / splash
```bash
dart run tool/gen_icon.dart            # regenerates assets/branding/*.png
dart run flutter_launcher_icons        # launcher icon
dart run flutter_native_splash:create  # boot splash
```

---

## 📁 Structure

```
lib/
  main.dart              app entry, keyboard/mouse input, screen routing
  game/
    config.dart          weapons, zone phases, palette, constants
    mathx.dart           vectors, RNG, collision helpers (circle/rect, ray casts)
    entities.dart        Character, Bullet, Loot, Obstacle, Particle
    royale_game.dart     the engine: movement, shooting, bot AI, gas zone, render
    sfx.dart             haptics (procedural audio = fast-follow)
  ui/
    game_ui.dart         HUD, minimap, twin-stick joysticks, start/end screens
tool/
  gen_icon.dart          generates the app icon + splash logo from code
```

---

## 🗺️ Roadmap

1. **Audio** — procedural gunshots / hits / pickups (haptics already wired).
2. **Real online multiplayer** — authoritative server (Dart `shelf` + WebSockets,
   or Nakama/Colyseus), client-side prediction, matchmaking. This is the big one.
3. **Monetization** — `google_mobile_ads` (rewarded revive, interstitial between
   matches), optional cosmetics.
4. **Play Store** — signing keystore, `flutter build appbundle`, store listing.
5. **Retention/virality** — daily challenge seed, XP/levels, leaderboards.
6. **(Later) AR camera mode** — optional toggle via `ar_flutter_plugin` for buzz.

---

Built as a viral-first prototype: instant to play, tiny to download, one codebase
for every screen.
