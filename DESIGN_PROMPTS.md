# 🎨 ZONE ROYALE — Design Prompts

Copy-paste prompts for generating the game's look. The full game specification
(screens, systems, tokens, codebase map) lives separately in
**[GAME_WORKFLOW.md](GAME_WORKFLOW.md)** — feed that to a designer or an AI as
*context*, and use the prompts below to actually generate.

| Prompt | Use it for |
| --- | --- |
| 1. Stitch.ai UI kit | Every screen, in landscape, Free Fire / BGMI quality |
| 2. In-game art | Sprites, only if you ever move off the code-drawn art |

> Tip: paste sections 3, 4 and 7 of GAME_WORKFLOW.md above the prompt so the
> generator knows the exact screens, HUD controls and colour tokens.

---

## 1. 🎨 Stitch.ai — premium LANDSCAPE UI kit

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

## 2. In-game art (only if you ever replace the code-drawn art)

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
