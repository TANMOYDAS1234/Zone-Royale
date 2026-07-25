# 🎮 ZONE ROYALE — Complete Game Workflow & UI Specification

**Purpose of this document:** everything a designer (or an AI like Stitch) needs
to redesign this game's interface to Free Fire / BGMI quality — every screen,
every state, every button, the exact data each one shows, and the art direction.
Section 12 is a ready-to-paste prompt for Stitch.ai.

The game is **landscape-first**. Every mockup should be **16:9 → 20:9 landscape
(1600×720 up to 2400×1080)**, because that's how it's played.

---

## 1. What the game is

A top-down battle royale for phones. Drop into an arena with 9 / 24 / 49
opponents, loot weapons and armour, survive a closing gas ring, be the last one
standing. Sessions are 3–6 minutes. Solo (offline, vs bots) and online (custom
rooms + quick match) share the same rules, HUD and art.

**One-line pitch:** *10 drop in. 1 walks out.*

---

## 2. The core loop (what makes it addictive)

```
        ┌──────────────────────────────────────────────────────────┐
        │                                                          │
   OPEN APP ─► DAILY STREAK (+coins) ─► HOME                       │
                                         │                         │
                     ┌───────────────────┼────────────────┐        │
                     ▼                   ▼                ▼        │
                 DROP IN            CUSTOM ROOM      SHOP/MISSIONS  │
                (solo vs bots)      (online)         (spend coins)  │
                     │                   │                          │
                     └────────► MATCH ◄──┘                          │
                                 │                                  │
        loot ─► fight ─► killstreak ─► zone closes ─► WIN / DIE     │
                                 │                                  │
                                 ▼                                  │
                    RESULT CARD (XP · coins · streak) ─► SHARE ─────┘
                                 │
                       level up ─► better rank ─► harder bots
```

**The four hooks**

| Hook | Where it lives | Why it works |
| --- | --- | --- |
| Fast restart | PLAY AGAIN on the result card | Never more than one tap from the next match |
| Visible progress | XP bar + rank + coins in every header | You always see the next milestone |
| Daily reason to return | Login streak + 3 daily missions | Habit, not grind |
| Bragging | Result card → SHARE (image + text) | Free user acquisition |

---

## 3. Screen map

```
SPLASH (boot animation, ~1.6s)
  │
  ▼
HOME / OPERATIONS HUB ──────────────────────────────────────────┐
  ├─ header: logo · rank pill · coin balance                    │
  ├─ operator card (name, level, XP bar)                        │
  ├─ daily login streak card  [tap to claim]                    │
  ├─ operator schematic (live 2D character preview)             │
  ├─ deployment picker: SKIRMISH 10 / CLASH 25 / WARZONE 50     │
  ├─ difficulty: CASUAL / NORMAL / HARDCORE                     │
  ├─ map: RANDOM / URBAN / FOREST / COMPOUND / BADLANDS         │
  ├─ [DROP IN]            ─────────────────► MATCH (solo)       │
  ├─ [CUSTOM ROOM · PLAY ONLINE] ──────────► ONLINE FLOW        │
  └─ bottom nav: HOME · SHOP · MISSIONS · PROFILE ──────────────┘

ONLINE FLOW
  ROOM CONFIG ──► LOBBY ──► ARENA ──► MATCH OVER (share) ──► LOBBY
   (host sets      (roster,   (live      (winner card)
    the rules)     ping)      match)

SHOP / ARMORY          MISSIONS / INTEL         PROFILE / OPERATOR
  skins                  3 daily objectives       identity + loadout
  accessories            progress bars            appearance
  weapons                CLAIM buttons            screen & feel settings
  heroes                                          control editor
  hero evolutions                                 lifetime stats
```

---

## 4. Screen-by-screen specification

### 4.1 SPLASH
- Closing tactical ring + crosshair emblem, scale 0.7→1.0, fade in ~700 ms.
- Title **ZONE ROYALE**, tagline *10 DROP IN. 1 WALKS OUT.*
- Gold sweep around the ring, hold ~800 ms, cross-fade to HOME.

### 4.2 HOME / OPERATIONS HUB
| Element | Data shown | State |
| --- | --- | --- |
| Header | crosshair logo, "OPERATIONS HUB", rank pill (RECRUIT→LEGEND, rank-coloured), coin balance | always |
| Operator card | `HERO · NAME`, `LVL n`, XP progress, `x / y XP → NEXT LEVEL` | always |
| Streak card | `DAY n LOGIN STREAK`, reward text, 7 pips | claimable (gold, glowing) / claimed (dim) |
| Schematic card | live 2D operator with current outfit/skin/accessory/weapon, `UNIT: SPEC-OPS // HERO`, `LOADOUT // WEAPON`, `STATUS: READY` | always |
| Deployment | 3 cards: name, icon, player count | one selected (amber glow) |
| Difficulty | 3 pills + one-line description | one selected (cyan) |
| Map | 5 chips | one selected (cyan) |
| DROP IN | primary CTA, full width, gold gradient + outer glow | pressed state |
| CUSTOM ROOM | secondary CTA, cyan outline | — |
| Bottom nav | 4 tabs | active tab highlighted |

### 4.3 IN-MATCH HUD (landscape — the most important screen)

```
┌──────────────────────────────────────────────────────────────────────┐
│ ⌂  [8 ALIVE] [3 KILLS]        ZONE CLOSING — GET INSIDE      ▢MINIMAP│
│                                     (toast line)                     │
│  100 HP                                                       ⚡SKILL│
│  ▓▓▓▓▓▓▓▓▓▓  🛡▓▓▓  ⛑▓▓                                       💣 2   │
│  Frost ▸ Reaper        (kill feed, landscape = top-left)     🧱 2   │
│                                                                      │
│                        ⟨ PICK UP  RIFLE ⟩                            │
│                     (only while standing on one)                     │
│                                                                      │
│   ◎ MOVE                 [AUTO] [WEAPON 30/30] [SWITCH]      ◎ AIM   │
└──────────────────────────────────────────────────────────────────────┘
```

Every control is **drag-positionable and resizable** (Profile → Customise
Control Placement), and **portrait and landscape store separate layouts**.

| Control | Key | Default (landscape, fractions of screen) | Behaviour |
| --- | --- | --- | --- |
| Move stick | `move` | 0.11, 0.74 | 8-way analog |
| Aim/fire stick | `aim` | 0.89, 0.74 | aim + auto-fire while held |
| Hero skill | `skill` | 0.94, 0.47 | cooldown sweep + seconds |
| Grenade | `nade` | 0.83, 0.45 | count badge |
| Shield wall | `wall` | 0.70, 0.45 | charges badge |
| Switch gun | `swap` | 0.66, 0.87 | shows the OTHER slot's gun art |
| Weapon panel | `reload` | 0.52, 0.88 | gun art, name, ammo, reload bar; tap = reload |
| Fire mode | `fire` | 0.38, 0.88 | AUTO / SINGLE |
| HP + armour | `hp` | 0.13, 0.40 | health bar + vest/helmet strips |
| Pick-up prompt | `pick` | 0.50, 0.62 | appears only when a swap is possible |

**Feedback layers:** hit marker (white ✕ flash), floating damage numbers,
directional red damage arcs, kill feed, killstreak banner (DOUBLE KILL →
GODLIKE), low-HP red vignette, gas purple vignette, screen shake (player-tunable).

### 4.4 RESULT CARD
`#1 WINNER WINNER` or `#n ELIMINATED` · operator portrait · KILLS / BEST STREAK /
PLAYERS / RANK · XP + coins earned (with LEVEL UP banner) · **PLAY AGAIN** ·
HOME · **SHARE** (captures the card as a PNG and opens the system share sheet).

### 4.5 ONLINE — ROOM CONFIG
Map & sector · weapon type (ALL_ARMS or one forced gun) · rounds (BO1/BO3/BO5) ·
player limit (10/25/50) · bot difficulty · equipment toggles (medkits, grenades,
hero skills, fill-with-bots) · room code (+ dice re-roll) · advanced server
field · **CREATE / JOIN ROOM** · **QUICK MATCH**.

### 4.6 ONLINE — LOBBY
Room code title · rules summary card (map, weapon, rounds, limit, bots,
equipment, **ping**) · connected-players roster (host ★, YOU highlight, bots
labelled) · **START MISSION** · host-only **CHANGE / APPLY SETTINGS** ·
RECONNECT · LEAVE ROOM.

### 4.7 SHOP / MISSIONS / PROFILE
- **SHOP:** sections (SKINS, ACCESSORIES, WEAPONS, HEROES, EVOLUTIONS); each row
  = art tile + name + price button or OWNED.
- **MISSIONS:** 3 cards with progress bars, reward (coins + XP), CLAIM.
- **PROFILE:** name field, outfit swatches, skin tones, accessory chips,
  starting weapon, hero, fire mode, **Screen & Feel** (orientation, graphics
  quality, screen shake, auto-swap), controls (left-handed + editor), stats.

---

## 5. Combat systems (what the UI has to express)

| System | Rule | UI surface |
| --- | --- | --- |
| **Two weapon slots** | Loot only fills an EMPTY slot. Both full → PICK UP prompt. Never auto-swaps. | SWITCH button, PICK UP prompt |
| **9 weapons** | Own damage, fire rate, magazine, reload, spread, pellets, range, auto/semi | weapon panel art + ammo |
| **Armour** | Vest −30%, helmet −22%, both wear down and break | armour strips under HP; worn on the character |
| **Shield wall** | Deployable cover, 260 HP, 16 s, blocks bullets and bodies | wall button + charges |
| **Grenades** | Arc throw, radial falloff damage | grenade button + count |
| **Hero skills** | Dash / Shield / Frenzy / Field Kit / Resupply, 8–16 s cooldown | skill button with cooldown |
| **Gas zone** | Shrinks in phases, damages outside | banner, minimap ring, purple vignette |
| **Airdrop** | Marked crate with a top-tier gun, up to 3 per match | minimap beacon + toast |
| **Killstreaks** | 2+ kills within 6 s | centre banner, BEST STREAK on the result card |

---

## 6. Progression & economy

- **XP:** 40 base + 15/kill + 150 win + placement bonus. Level = `80 + level×30` XP.
- **Ranks:** RECRUIT → BRONZE → SILVER → GOLD → PLATINUM → DIAMOND → MASTER → LEGEND.
- **Coins:** 12 base + 6/kill + 70 win + placement; daily missions and login streak.
- **Spend:** outfits 300 · accessories 250 · weapons 450 · heroes 750–900 · evolutions 1500.
- **Ranked difficulty:** bots get better with your level, plateauing ~level 40,
  scaled again by the CASUAL/NORMAL/HARDCORE choice.

---

## 7. Design system

| Token | Value | Use |
| --- | --- | --- |
| `bg` | `#05070C` | app background |
| `surface` | `#12161E` / white @4% | cards, tiles |
| `accent` | `#FFB02E` | primary CTA, XP, coins, selection |
| `danger` | `#FF5A5F` | defeat, low HP, enemies, leave |
| `info` | `#37D0FF` | zone-safe, cyan actions, secondary CTA |
| `success` | `#52E06A` | health, claimed, ready |
| `wall` | `#7FE8FF` | shield walls |
| `vest` / `helmet` | `#7FC4FF` / `#C9D6A8` | armour bars |

- **Type:** condensed uppercase for headings (w900, letter-spacing 1–3),
  clean sans for body, **monospace** for tactical labels/readouts.
- **Radius:** 10–20 px. **Borders:** 1 px accent @35–70%.
- **Glassmorphism:** translucent panel + 1 px accent border + soft outer glow.
- **Buttons:** gradient fill + outer glow for primary; outlined for secondary.
- **Touch targets:** ≥48 dp. Controls must never sit under the gesture bar.

---

## 8. Codebase map (where each screen lives)

| Screen / system | File |
| --- | --- |
| App entry, orientation, keyboard | `lib/main.dart` |
| Splash, emblem, brand | `lib/ui/brand.dart` |
| HUD, all overlays, shop, missions, profile, control editor | `lib/ui/game_ui.dart` |
| Match simulation + world rendering | `lib/game/royale_game.dart` |
| Character / weapon / accessory art | `lib/game/char_art.dart` |
| Tunables (weapons, heroes, armour, walls, quality, difficulty) | `lib/game/config.dart` |
| Entities (character, bullet, loot, obstacle) | `lib/game/entities.dart` |
| Save data, progression, missions, streak | `lib/game/profile.dart` |
| Online client (protocol, interpolation) | `lib/net/net_client.dart` |
| Online screens (config, lobby, arena) | `lib/net/net_arena.dart` |
| Authoritative server | `server/bin/server.dart` |
| Screenshot + share | `lib/ui/capture.dart` |

---

## 9. Turning a Stitch design into the app

1. Generate the screens (section 12 prompt) in **landscape**.
2. Export the **style guide** (colours, type scale, spacing, radii) → update the
   tokens in `lib/ui/game_ui.dart` and `lib/game/config.dart`.
3. Rebuild screens **widget by widget** — this app draws everything with Flutter
   widgets and `CustomPainter`, so there are no image assets to slice. Match
   layout, spacing and states; keep the existing data bindings.
4. Keep every control **inside the safe area** and honour the per-orientation
   saved layouts.
5. Test at 1600×720 (short landscape) **and** 720×1600 (portrait) before shipping.

---

## 10. Build, run, deploy

```bash
flutter pub get
flutter run -d <device>                                   # dev
flutter build apk --release --target-platform android-arm64
flutter install -d <device>
cd server && dart run bin/server.dart                      # local server :8080
```
The app and `server/` ship together — push to GitHub and Render rebuilds the
server automatically. An out-of-date server shows a warning in the room lobby.

---

## 11. Quality checklist before a release

- [ ] Landscape and portrait both laid out correctly, nothing under the gesture bar
- [ ] Controls reachable one-handed; editor saves per orientation
- [ ] Solo match: 60 fps on a mid-range phone at BALANCED graphics
- [ ] Online: ping shown, no rubber-banding, auto-fire works
- [ ] Share produces an image on WhatsApp/Instagram
- [ ] Weapon never swaps without a tap
- [ ] Every screen readable in sunlight (contrast ≥ 4.5:1 for body text)

---

## 12. 🎨 STITCH.AI PROMPT — premium landscape UI kit

> Paste everything inside the block into Stitch (or another UI generator).

```
Design a premium mobile game UI kit for "ZONE ROYALE", a fast top-down battle
royale shooter for Android. Reference the polish of Free Fire and BGMI, but
cleaner and more modern. IMPORTANT: every screen must be designed in LANDSCAPE
(1600x720, also check 2400x1080) — this game is played sideways. Dark theme.

BRAND & MOOD
Elite, tactical, high energy, but clean and readable in sunlight. Deep near-black
background (#05070C) with a subtle radial glow behind content. Primary accent
amber/gold (#FFB02E), danger red (#FF5A5F), info cyan (#37D0FF), success green
(#52E06A), energy cyan (#7FE8FF) for shield tech. Rounded corners 12-20px,
glassmorphism cards (blurred translucent panels, 1px accent border, soft outer
glow), bold condensed uppercase display type for headings, clean sans for body,
monospace for tactical readouts (ping, room codes, stats). Micro-shadows,
gradient buttons with outer glow. Everything should feel tactile and worth
tapping. Minimum touch target 48dp. Keep a 24-48px safe gutter on the left and
right edges for the Android gesture bar.

DESIGN THESE SCREENS (all landscape):

1. SPLASH — animated logo reveal: a closing tactical ring / crosshair emblem over
   a dark battlefield vignette, tagline "10 DROP IN. 1 WALKS OUT.", loading
   shimmer. Show the key animation frames.

2. HOME / OPERATIONS HUB — a two-column landscape layout:
   LEFT COLUMN: large live operator preview card inside a tactical schematic
   frame (grid lines, corner brackets, "UNIT: SPEC-OPS // STRIKER" tag,
   "LOADOUT // RIFLE", "STATUS: READY" with a pulsing dot).
   RIGHT COLUMN: player card (name, LVL 34, XP progress bar, rank pill "MASTER"
   in rank colour, coin balance), a DAILY LOGIN STREAK banner with 7 pips and a
   "Tap to collect +160 coins" state, three deployment cards in a row (SKIRMISH
   10 / CLASH 25 / WARZONE 50 with icons), a DIFFICULTY segmented control
   (CASUAL / NORMAL / HARDCORE), a MAP chip row (RANDOM / URBAN / FOREST /
   COMPOUND / BADLANDS), a huge glowing primary "DROP IN" button and a cyan
   outlined "CUSTOM ROOM · PLAY ONLINE" button.
   BOTTOM: a 4-tab nav bar (HOME / SHOP / MISSIONS / PROFILE).

3. IN-MATCH HUD (landscape, the hero screen) — transparent overlay over
   gameplay:
   - top-left: home button, "8 ALIVE" pill, "3 KILLS" pill
   - top-centre: zone status banner ("ZONE CLOSING — GET INSIDE" in purple when
     closing, "Zone shrinks in 12s" in cyan otherwise) and a slim toast line
     beneath it for pickups ("HELMET EQUIPPED · -22% DAMAGE")
   - top-right: circular minimap with the safe ring, red enemy blips, a gold
     airdrop beacon
   - left: health bar with numeric HP, plus two thin armour bars under it
     (blue vest, olive helmet), and a kill feed below
   - right edge: circular SKILL button with a cooldown sweep, GRENADE button
     with count, SHIELD WALL button with charges
   - bottom-centre: fire-mode toggle (AUTO/SINGLE), weapon panel showing the gun
     illustration + name + "30 / 30" ammo + reload progress, and a SWITCH button
     showing the second weapon
   - bottom corners: two translucent virtual joysticks (MOVE cyan, AIM·FIRE red)
   - centre: an optional "PICK UP  RIFLE — replaces SMG" prompt chip
   - feedback states to show: white hit marker, floating damage numbers,
     directional red damage arcs at the screen edge, a big centred "DOUBLE KILL"
     killstreak banner, low-HP red vignette, purple gas vignette.
   Deliver the HUD in two densities: default and "minimal" (smaller controls).

4. CONTROL CUSTOMISER — a drag-and-drop editor: ghost tokens for every control
   on a faint grid, a selected token with handles, a tuning panel with SIZE and
   OPACITY sliders, a "LANDSCAPE LAYOUT" badge, RESET and SAVE LAYOUT buttons.

5. ONLINE ROOM CONFIG — a tactical terminal: title "CUSTOM ROOM COMMAND",
   dropdown-style fields (MAP & SECTOR, WEAPON TYPE), segmented pills (ROUNDS
   BO1/BO3/BO5, PLAYER LIMIT 10/25/50, BOT DIFFICULTY), equipment toggle chips
   (Medkits, Grenades, Hero Skills, Fill With Bots), a room-code input with a
   dice re-roll button, a collapsed "Advanced · Server" row, primary "CREATE /
   JOIN ROOM" and secondary "QUICK MATCH · JOIN PUBLIC".

6. ONLINE LOBBY — room code header, a rules summary card (Map, Weapon, Rounds,
   Player Limit, Bots, Equipment, Ping in ms with a green/amber/red dot), a
   connected-players roster (avatar, name, "Deployed · Wins 2" or "In lobby",
   host star, YOU highlighted, bots dimmed), big "START MISSION", plus
   "CHANGE / APPLY SETTINGS", RECONNECT and LEAVE ROOM.

7. VICTORY / DEFEAT RESULT CARD — huge "#1 WINNER WINNER" (gold) or
   "#7 ELIMINATED" (red), operator portrait in a framed tile, a stat strip
   (KILLS / BEST STREAK / PLAYERS / RANK), a rewards card (+XP, +coins, LEVEL UP
   banner), then PLAY AGAIN (primary), HOME and SHARE. Design it so the card
   itself is screenshot-worthy — it gets shared to WhatsApp and Instagram.

8. SHOP / ARMORY — section headers (SKINS, ACCESSORIES, WEAPONS, HEROES,
   EVOLUTIONS), rows with a square art tile, item name, and a gold price button
   or a muted "OWNED" state; coin balance pinned in the header. Show a purchase
   confirmation and an insufficient-funds state.

9. DAILY MISSIONS — three mission cards with progress bars ("12 / 15 kills"),
   reward chips (+100 coins, +200 XP), CLAIM buttons in ready and claimed
   states, and a "refreshes daily" note with a countdown.

10. PROFILE / OPERATOR — landscape two-column: left is a large operator preview
    with the current outfit, skin, accessory and weapon; right is a scrollable
    settings column — name field, outfit colour swatch grid, skin tone swatches,
    accessory chips (locked ones show a padlock), starting weapon chips, hero
    cards, fire-mode toggle, SCREEN & FEEL (orientation segmented control
    LANDSCAPE/PORTRAIT/AUTO, graphics SMOOTH/BALANCED/ULTRA, a screen-shake
    slider, an auto-swap switch), a "CUSTOMISE CONTROL PLACEMENT" button, and a
    lifetime stats strip (matches, wins, win %, kills, best rank).

DELIVER
- A style guide: colour tokens, type scale, spacing scale, radii, elevation.
- Reusable components: primary/secondary/ghost buttons, pills, segmented
  controls, chips, cards, sliders, progress bars, joysticks, circular action
  buttons with cooldown sweeps, stat tiles, roster rows, shop rows.
- High-fidelity mockups of every screen above in landscape, each with idle and
  pressed/active states.
- A dark-battlefield illustration style for backgrounds: near-black base, subtle
  tactical grid, soft gold light bloom, heavy vignette.
Keep it consistent, premium, high-contrast and thumb-friendly for two-handed
landscape play.
```

---

## 13. Prompt for in-game art (if you ever replace the code-drawn art)

```
Top-down (bird's eye) 2D game sprites for a premium mobile battle royale, clean
vector style with soft rim lighting and one consistent light direction from the
top-left. Near-black background. Produce: 5 operator characters seen from above
(distinct silhouettes — scout with visor, heavy with chest plate and beard,
red-bandana brawler, blonde medic with headset, grey-bearded grenadier), each
with plate-carrier armour and ballistic-helmet variants; 9 weapons from above
(pistol, magnum revolver, SMG, pump shotgun, assault rifle, marksman rifle,
sniper with bipod, LMG with drum, six-barrel minigun) with visible receivers,
optics, magazines and muzzle brakes; ground loot icons (medkit, grenade, plate
carrier, helmet, shield-wall charge, supply crate with beacon); environment tiles
for urban rooftops, forest canopies, concrete compounds and desert boulders.
Cohesive palette: amber #FFB02E, cyan #37D0FF, red #FF5A5F, energy cyan #7FE8FF.
```
