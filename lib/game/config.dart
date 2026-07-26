import 'dart:ui';

// ============================ World ============================
const double kWorld = 3200; // square world edge length (world units)
const double kViewHeight = 1320; // world units shown vertically (drives camera zoom) — wider POV so you see enemies coming
/// Vertical world units shown when the phone is held sideways. Landscape is
/// much wider than it is tall, so the *vertical* window has to shrink or the
/// visible area explodes and operators become ants. 720 keeps roughly the same
/// on-screen character size as portrait while showing far more left/right —
/// exactly what you want in a twin-stick shooter.
const double kViewHeightLandscape = 620;
const double kMaxHp = 100;
const double kPlayerRadius = 20;
const int kBotCount = 9;

// ============================ Feel / juice =====================
/// Base screen-shake amounts. These are *trauma* units (0..1-ish): the camera
/// offset is trauma² × [kShakeMaxPx], so small values stay subtle and only big
/// hits really kick. Kept deliberately low — shake that fights your aim is bad
/// shake. The player also scales all of it with the SCREEN SHAKE slider.
const double kShakeMaxPx = 13; // px offset at full trauma (before user scale)
const double kShakeFireLight = 0.10; // SMG / rifle / pistol
const double kShakeFireHeavy = 0.20; // shotgun
const double kShakeFireSniper = 0.26;
const double kShakeHurt = 0.16;
const double kShakeBoom = 0.55;
const double kShakeSkill = 0.14;

// ============================ Solo difficulty ==================
/// How hard the offline match is. This scales bot aim, damage, reaction and
/// vision on top of the level-based ranked curve, so a new player can enjoy the
/// game and a veteran can still get wrecked on HARDCORE.
class Difficulty {
  final String id;
  final String name;
  final String tagline;
  final double skill; // multiplier on bot aim skill
  final double damage; // multiplier on damage bots deal
  final double react; // multiplier on bot reaction delay (higher = slower)
  final double vision; // multiplier on how far bots spot you
  const Difficulty(this.id, this.name, this.tagline, this.skill, this.damage,
      this.react, this.vision);

  /// What this tier actually changes, for the settings screen. Percentages are
  /// relative to a bot at full strength, so the numbers move when you switch.
  List<(String, String)> get spec => [
        ('BOT AIM', '${(skill * 100).round()}%'),
        ('BOT DAMAGE', '${(damage * 100).round()}%'),
        ('REACTION', '${(react * 100).round()}%'),
        ('SPOT RANGE', '${(vision * 100).round()}%'),
      ];
}

const List<Difficulty> kDifficulties = [
  Difficulty('casual', 'CASUAL', 'Learn the ropes · relaxed bots', 0.72, 0.62,
      1.6, 0.82),
  Difficulty('normal', 'NORMAL', 'Fair fight · the default', 0.88, 0.80, 1.25,
      0.93),
  Difficulty('hardcore', 'HARDCORE', 'Sweaty lobbies · pro bots', 1.12, 1.0,
      0.85, 1.08),
];

// ============================ Graphics quality =================
/// Scales the cost of everything that is pure decoration — ground detail,
/// particles, decals, weather. HIGH looks best; BATTERY keeps a cheap phone
/// at a steady frame rate. This is the honest fix for "sometimes it feels
/// laggy": a 120Hz panel plus hundreds of small draw calls is a lot to ask.
class Quality {
  final String id;
  final String name;
  final String tagline;
  final double detail; // ground/scenery detail multiplier
  final double fx; // particle count multiplier
  final int decals; // how many permanent marks stay on the ground
  final bool weather; // drifting dust/rain layer
  /// Glow strength on muzzle flashes, tracers, the zone edge and pickups.
  /// 0 draws the flat shape only — cheap, and the honest difference you can
  /// see the instant you fire a gun.
  final double bloom;
  /// Soft contact shadow under every character, crate and tree.
  final bool shadows;
  const Quality(this.id, this.name, this.tagline, this.detail, this.fx,
      this.decals, this.weather, this.bloom, this.shadows);

  /// One line per thing this level actually changes — used by the settings
  /// screen so the choice is legible instead of three mystery words.
  List<(String, String)> get spec => [
        ('BLOOM & GLOW', bloom <= 0 ? 'OFF' : '${(bloom * 100).round()}%'),
        ('PARTICLES', '${(fx * 100).round()}%'),
        ('GROUND DETAIL', '${(detail * 100).round()}%'),
        ('BULLET MARKS', '$decals'),
        ('CONTACT SHADOWS', shadows ? 'ON' : 'OFF'),
        ('DUST & WEATHER', weather ? 'ON' : 'OFF'),
      ];
}

const List<Quality> kQualities = [
  Quality('battery', 'SMOOTH', 'Flat lighting · fewest effects · best frame rate',
      0.35, 0.45, 30, false, 0.0, false),
  Quality('balanced', 'BALANCED', 'Glow, shadows and dust · the default mix',
      0.75, 0.85, 90, true, 0.75, true),
  Quality('high', 'ULTRA', 'Full bloom, heavy particles · newer phones', 1.25,
      1.3, 170, true, 1.4, true),
];

// ============================ Armour ==========================
/// Helmet + vest, BGMI/Free-Fire style: they soak a share of incoming damage
/// and break down as they take hits, so a geared-up player wins a straight
/// fight but can still be worn down.
const double kVestReduction = 0.30; // -30% body damage at full durability
const double kHelmetReduction = 0.22; // -22% on top, while the helmet holds
const double kVestDurability = 120; // damage the vest can absorb
const double kHelmetDurability = 70;

// ============================ Shield wall =====================
/// A deployable cover slab (think Free Fire's gloo wall). Blocks bullets,
/// blocks movement, and melts away after a while — the single best tool for
/// resetting a losing fight, and the thing that makes close-range play tense.
const double kShieldWallWidth = 132;
const double kShieldWallThickness = 26;
const double kShieldWallHp = 260;
const double kShieldWallLife = 16; // seconds before it dissolves
const int kShieldWallStart = 2; // carried at spawn
const int kShieldWallMax = 4;
const double kShieldWallCooldown = 1.2;

// ============================ Airdrop =========================
const double kAirdropFirstAt = 42; // seconds into the match for the first crate
const double kAirdropEvery = 55; // seconds between later crates
const int kAirdropMax = 3; // crates per match

// ============================ Grenades ========================
const int kGrenadeStart = 2; // carried at spawn
const int kGrenadeMax = 5;
const double kGrenadeDamage = 85; // at the centre; linear falloff to the edge
const double kGrenadeRadius = 155; // blast radius
const double kGrenadeFuse = 1.4; // seconds before it blows
const double kGrenadeSpeed = 560; // initial throw speed
const double kThrowCooldown = 0.6; // seconds between throws

// ============================ Heroes / skills =================
enum SkillType { dash, shield, frenzy, medic, grenadier }

class Hero {
  final String id;
  final String name;
  final String desc;
  final SkillType skill;
  final double cooldown; // seconds
  final int color; // signature accent
  final int cost; // coins to unlock (0 = free / default)
  const Hero(this.id, this.name, this.desc, this.skill, this.cooldown, this.color,
      this.cost);
}

const List<Hero> kHeroes = [
  Hero('striker', 'STRIKER', 'Dash — a burst of speed to rush or escape',
      SkillType.dash, 8, 0xFF4F6BFF, 0),
  Hero('bastion', 'BASTION', 'Shield — soak heavy damage for a few seconds',
      SkillType.shield, 15, 0xFF37D0FF, 900),
  Hero('vortex', 'VORTEX', 'Frenzy — fire and reload much faster',
      SkillType.frenzy, 15, 0xFFFF5A5F, 900),
  Hero('mercy', 'MERCY', 'Field Kit — instantly patch yourself up',
      SkillType.medic, 16, 0xFF52E06A, 750),
  Hero('boomer', 'BOOMER', 'Resupply — restock a full set of grenades',
      SkillType.grenadier, 16, 0xFFFFB02E, 750),
];

// hero skill effect tuning
const double kDashPower = 900; // dash impulse
const double kShieldTime = 4.5; // seconds of protection
const double kShieldCut = 0.35; // damage multiplier while shielded
const double kFrenzyTime = 6.0; // seconds of faster fire/reload
const double kMedicHeal = 55; // hp restored (evolved: full)
const double kEvoCost = 1500; // coins to evolve a hero (top form)

// ============================ Weapons =========================
// NOTE: append new weapons at the end so saved startWeapon indices stay valid.
enum WeaponId { pistol, smg, shotgun, rifle, sniper, magnum, dmr, lmg, minigun }

class Weapon {
  final WeaponId id;
  final String name;
  final double damage;
  final double fireInterval; // seconds between shots
  final double bulletSpeed; // units / second
  final double spread; // radians, max half-angle jitter
  final int pellets; // projectiles per trigger pull
  final int mag; // magazine size
  final double reloadTime; // seconds
  final double range; // travel distance before a bullet dies
  final bool auto; // hold to keep firing
  final Color color; // tracer + loot marker colour

  const Weapon({
    required this.id,
    required this.name,
    required this.damage,
    required this.fireInterval,
    required this.bulletSpeed,
    required this.spread,
    required this.pellets,
    required this.mag,
    required this.reloadTime,
    required this.range,
    required this.auto,
    required this.color,
  });
}

const Map<WeaponId, Weapon> kWeapons = {
  WeaponId.pistol: Weapon(
    id: WeaponId.pistol,
    name: 'Pistol',
    damage: 15,
    fireInterval: 0.32,
    bulletSpeed: 820,
    spread: 0.04,
    pellets: 1,
    mag: 12,
    reloadTime: 1.0,
    range: 600,
    auto: false,
    color: Color(0xFFFFE08A),
  ),
  WeaponId.smg: Weapon(
    id: WeaponId.smg,
    name: 'SMG',
    damage: 10,
    fireInterval: 0.085,
    bulletSpeed: 980,
    spread: 0.10,
    pellets: 1,
    mag: 30,
    reloadTime: 1.5,
    range: 560,
    auto: true,
    color: Color(0xFF8AFFC1),
  ),
  WeaponId.shotgun: Weapon(
    id: WeaponId.shotgun,
    name: 'Shotgun',
    damage: 9,
    fireInterval: 0.72,
    bulletSpeed: 840,
    spread: 0.22,
    pellets: 8,
    mag: 6,
    reloadTime: 1.9,
    range: 360,
    auto: false,
    color: Color(0xFFFF9D5C),
  ),
  WeaponId.rifle: Weapon(
    id: WeaponId.rifle,
    name: 'Rifle',
    damage: 17,
    fireInterval: 0.125,
    bulletSpeed: 1250,
    spread: 0.045,
    pellets: 1,
    mag: 25,
    reloadTime: 1.8,
    range: 820,
    auto: true,
    color: Color(0xFF7EC8FF),
  ),
  WeaponId.sniper: Weapon(
    id: WeaponId.sniper,
    name: 'Sniper',
    damage: 70,
    fireInterval: 1.25,
    bulletSpeed: 1900,
    spread: 0.006,
    pellets: 1,
    mag: 5,
    reloadTime: 2.2,
    range: 1300,
    auto: false,
    color: Color(0xFFFF6BD6),
  ),
  WeaponId.magnum: Weapon(
    id: WeaponId.magnum,
    name: 'Magnum',
    damage: 46,
    fireInterval: 0.5,
    bulletSpeed: 1050,
    spread: 0.02,
    pellets: 1,
    mag: 6,
    reloadTime: 1.5,
    range: 720,
    auto: false,
    color: Color(0xFFFFC24B),
  ),
  WeaponId.dmr: Weapon(
    id: WeaponId.dmr,
    name: 'Marksman',
    damage: 34,
    fireInterval: 0.28,
    bulletSpeed: 1500,
    spread: 0.02,
    pellets: 1,
    mag: 12,
    reloadTime: 1.7,
    range: 1050,
    auto: false,
    color: Color(0xFFB0FF6B),
  ),
  WeaponId.lmg: Weapon(
    id: WeaponId.lmg,
    name: 'LMG',
    damage: 13,
    fireInterval: 0.1,
    bulletSpeed: 1120,
    spread: 0.10,
    pellets: 1,
    mag: 60,
    reloadTime: 3.0,
    range: 720,
    auto: true,
    color: Color(0xFFFF8A5C),
  ),
  WeaponId.minigun: Weapon(
    id: WeaponId.minigun,
    name: 'Minigun',
    damage: 9,
    fireInterval: 0.05,
    bulletSpeed: 1000,
    spread: 0.14,
    pellets: 1,
    mag: 120,
    reloadTime: 3.6,
    range: 620,
    auto: true,
    color: Color(0xFFC0C6D0),
  ),
};

// ground-loot rarity (pistol excluded: everyone spawns with it)
const List<MapEntry<WeaponId, int>> kLootTable = [
  MapEntry(WeaponId.smg, 5),
  MapEntry(WeaponId.magnum, 3),
  MapEntry(WeaponId.shotgun, 4),
  MapEntry(WeaponId.dmr, 3),
  MapEntry(WeaponId.rifle, 4),
  MapEntry(WeaponId.lmg, 2),
  MapEntry(WeaponId.minigun, 1),
  MapEntry(WeaponId.sniper, 2),
];

/// Only the heavy hitters drop from an airdrop — that's what makes the crate
/// worth fighting over.
const List<MapEntry<WeaponId, int>> kAirdropTable = [
  MapEntry(WeaponId.sniper, 4),
  MapEntry(WeaponId.minigun, 3),
  MapEntry(WeaponId.lmg, 3),
  MapEntry(WeaponId.dmr, 2),
];

/// Rough "how good is this gun" score (0..1). Used by bots to decide whether a
/// ground weapon beats what they're carrying, and to rank your two slots.
double weaponScore(WeaponId id) {
  final w = kWeapons[id]!;
  final dps = w.damage * w.pellets / w.fireInterval;
  final sustained = dps * (w.mag / (w.mag + w.reloadTime / w.fireInterval));
  return (sustained / 260 * 0.7 + w.range / 1300 * 0.3).clamp(0.0, 1.0);
}

/// Everything the server needs to simulate a gun exactly like the client does.
/// Sent with the room config so online matches use the *real* weapon table
/// instead of one hardcoded bullet.
List<Map<String, dynamic>> weaponNetTable() => [
      for (final id in kWeaponOrder)
        {
          'i': id.index,
          'dmg': kWeapons[id]!.damage,
          'speed': kWeapons[id]!.bulletSpeed,
          'range': kWeapons[id]!.range,
          'rof': kWeapons[id]!.fireInterval,
          'mag': kWeapons[id]!.mag,
          'rl': kWeapons[id]!.reloadTime,
          'sp': kWeapons[id]!.spread,
          'pel': kWeapons[id]!.pellets,
          'auto': kWeapons[id]!.auto,
        }
    ];

// ============================ Safe zone =======================
class ZonePhase {
  final double wait; // seconds held before this shrink begins
  final double shrink; // seconds spent shrinking
  final double factor; // targetRadius = radius * factor
  final double dps; // damage / second taken outside the circle
  const ZonePhase(this.wait, this.shrink, this.factor, this.dps);
}

const double kZoneStartRadius = 2050;
const List<ZonePhase> kZonePhases = [
  ZonePhase(12, 14, 0.62, 1),
  ZonePhase(10, 12, 0.58, 2),
  ZonePhase(9, 11, 0.55, 4),
  ZonePhase(8, 9, 0.5, 6),
  ZonePhase(8, 8, 0.45, 9),
  ZonePhase(6, 8, 0.4, 14),
];

// ============================ Palette =========================
const Color kBgTop = Color(0xFF0B1220);
const Color kBgBottom = Color(0xFF05070C);
const Color kGroundColor = Color(0xFF121A2B);
const Color kGridColor = Color(0x22294066);
const Color kSafeEdge = Color(0xFF37D0FF);
const Color kGasFill = Color(0x552A0A4A);
const Color kGasEdge = Color(0xFFB14BFF);
const Color kPlayerColor = Color(0xFFFFFFFF);
const Color kAccent = Color(0xFFFFB02E);
const Color kAccent2 = Color(0xFFFF5A5F);

const List<String> kBotNames = [
  'Reaper', 'Ghost', 'Viper', 'Nova', 'Blaze', 'Havoc', 'Frost',
  'Rogue', 'Echo', 'Fang', 'Talon', 'Zero', 'Storm', 'Onyx',
];
const List<int> kBotColors = [
  0xFFFF5A5F, 0xFF7EC8FF, 0xFF8AFFC1, 0xFFFFD36B, 0xFFC58BFF,
  0xFFFF9D5C, 0xFF5AFFEA, 0xFFFF6BD6, 0xFFA0E85B,
];

// ============================ Customization ===================
// Outfit / suit colours the player (and bots) can wear.
const List<int> kOutfitColors = [
  0xFF4F6BFF, 0xFFFF5A5F, 0xFF3CC46E, 0xFFFFB02E, 0xFFC58BFF,
  0xFF17C4CE, 0xFFFF7A3D, 0xFFEE4C97, 0xFF9AA6B2, 0xFFF4D03F,
  0xFF223A5E, 0xFFEDEFF3,
  0xFF00E5A0, 0xFF7C4DFF, 0xFF00B0FF, 0xFFFF3D00, 0xFFD500F9, 0xFF8D6E63,
];
/// Real names for the outfit colours — "Skin 7" told the player nothing about
/// what they were buying.
const List<String> kOutfitNames = [
  'Cobalt', 'Crimson', 'Jungle', 'Amber', 'Orchid', 'Teal',
  'Ember', 'Rose', 'Ash', 'Sand', 'Midnight', 'Arctic',
  'Venom', 'Violet', 'Azure', 'Inferno', 'Magenta', 'Umber',
];

// Skin tones (last is a grey "cyborg" tone).
const List<int> kSkinTones = [
  0xFFF4CBA2, 0xFFE0A970, 0xFFB87A4E, 0xFF7A5334, 0xFF9BB0BC,
];
// Head accessories; index 0 = none.
const List<String> kAccessoryNames = [
  'None', 'Cap', 'Beanie', 'Headband', 'Helmet', 'Shades',
  'Mohawk', 'Mask', 'Crown', 'Horns',
];

// Weapon display / selection order.
const List<WeaponId> kWeaponOrder = [
  WeaponId.pistol,
  WeaponId.magnum,
  WeaponId.smg,
  WeaponId.shotgun,
  WeaponId.dmr,
  WeaponId.rifle,
  WeaponId.lmg,
  WeaponId.minigun,
  WeaponId.sniper,
];

// ============================ Match modes =====================
// Player count drives the map size and zone timing so every mode feels right.
class MatchMode {
  final String id;
  final String name;
  final String tagline;
  final int players; // total incl. you
  final double world; // map edge length (world units)
  final double timeScale; // zone wait/shrink multiplier (bigger map = longer)
  const MatchMode(
      this.id, this.name, this.tagline, this.players, this.world, this.timeScale);

  int get bots => players - 1;
  double get zoneStart => world * 0.64;
}

const List<MatchMode> kMatchModes = [
  MatchMode('skirmish', 'SKIRMISH', '10 players · fast & frantic', 10, 2600, 1.0),
  MatchMode('clash', 'CLASH', '25 players · tactical', 25, 4300, 1.4),
  MatchMode('warzone', 'WARZONE', '50 players · total chaos', 50, 6200, 1.9),
];

// ============================ Map themes ======================
// Cover mix + palette per map so matches don't feel the same. A random theme
// is picked each match.
class MapTheme {
  final String name;
  final int ground;
  final int groundEdge;
  final int grid;
  final int border;
  final double wallMul; // obstacle density multipliers vs. the base counts
  final double crateMul;
  final double bushMul;
  const MapTheme(
    this.name, {
    required this.ground,
    required this.groundEdge,
    required this.grid,
    required this.border,
    required this.wallMul,
    required this.crateMul,
    required this.bushMul,
  });
}

const List<MapTheme> kMapThemes = [
  MapTheme('URBAN',
      ground: 0xFF1A1F2B,
      groundEdge: 0xFF090C13,
      grid: 0x22315078,
      border: 0xFF2A3550,
      wallMul: 1.7,
      crateMul: 1.2,
      bushMul: 0.4),
  MapTheme('FOREST',
      ground: 0xFF12241A,
      groundEdge: 0xFF060E09,
      grid: 0x2233603C,
      border: 0xFF244028,
      wallMul: 0.5,
      crateMul: 0.8,
      bushMul: 2.1),
  MapTheme('COMPOUND',
      ground: 0xFF1C1A24,
      groundEdge: 0xFF0A0810,
      grid: 0x22503C78,
      border: 0xFF3A2E50,
      wallMul: 1.3,
      crateMul: 1.7,
      bushMul: 0.7),
  MapTheme('BADLANDS',
      ground: 0xFF241D14,
      groundEdge: 0xFF0E0A06,
      grid: 0x22785C31,
      border: 0xFF4A3A22,
      wallMul: 0.7,
      crateMul: 0.6,
      bushMul: 0.5),
];
