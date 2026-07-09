import 'dart:ui';

// ============================ World ============================
const double kWorld = 3200; // square world edge length (world units)
const double kViewHeight = 1320; // world units shown vertically (drives camera zoom) — wider POV so you see enemies coming
const double kMaxHp = 100;
const double kPlayerRadius = 20;
const int kBotCount = 9;

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
