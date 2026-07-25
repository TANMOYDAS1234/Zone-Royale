import 'package:flame/components.dart' show Vector2;
import 'dart:ui';
import 'config.dart';
import 'mathx.dart';

// ============================ Obstacles =======================
/// `shield` is a player-deployed wall — it blocks bullets and bodies exactly
/// like real cover, but it has hit points and a timer, so it's cover you have
/// to spend and can be shot away.
enum ObstacleKind { wall, crate, bush, shield }

class Obstacle {
  final ObstacleKind kind;
  final double x, y, w, h;
  double hp; // shield walls only
  double life; // seconds left before a shield wall dissolves
  final int ownerId;
  Obstacle(this.kind, this.x, this.y, this.w, this.h,
      {this.hp = 0, this.life = 0, this.ownerId = -1});

  bool get blocks => kind != ObstacleKind.bush; // bushes never block
  bool get conceals => kind == ObstacleKind.bush;
  bool get isShield => kind == ObstacleKind.shield;
  Rect get rect => Rect.fromLTWH(x, y, w, h);

  bool contains(double px, double py) =>
      px >= x && px <= x + w && py >= y && py <= y + h;
}

// ============================ Loot ============================
enum LootKind { weapon, medkit, grenade, vest, helmet, wall }

class Loot {
  final LootKind kind;
  final Vector2 pos;
  final WeaponId? weapon;
  final double heal;
  double bob = randRange(0, kTau);
  bool taken = false;
  double readyAt = 0; // world time before it can be picked up (freshly dropped)
  bool airdrop = false; // supply-drop crate: rare gun, flagged on the minimap

  Loot(this.kind, this.pos, {this.weapon, this.heal = 0});
}

// ============================ Bullet ==========================
class Bullet {
  final Vector2 pos;
  final Vector2 vel;
  final double damage;
  final double range;
  final Color color;
  final int ownerId;
  final Vector2 prev;
  double traveled = 0;
  bool dead = false;

  final double tracer; // tracer thickness/length multiplier (per weapon)

  Bullet(this.pos, this.vel, this.damage, this.range, this.color, this.ownerId,
      {this.tracer = 1.0})
      : prev = pos.clone();
}

// ============================ Grenade =========================
class Grenade {
  final Vector2 pos;
  final Vector2 vel;
  final int ownerId;
  double fuse;
  bool dead = false;

  Grenade(this.pos, this.vel, this.ownerId, this.fuse);
}

// ============================ Particle ========================
class Particle {
  final Vector2 pos;
  final Vector2 vel;
  double life;
  final double maxLife;
  final double size;
  final Color color;
  final bool glow;

  Particle(this.pos, this.vel, this.life, this.size, this.color,
      {this.glow = false})
      : maxLife = life;
}

// ============================ Character =======================
class Character {
  final int id;
  final bool isBot;
  final String name;
  final Color color;
  final Vector2 pos;
  final Vector2 vel = Vector2.zero();
  final Vector2 knock = Vector2.zero(); // knockback / recoil impulse

  double radius = kPlayerRadius;
  double hp = kMaxHp;
  double aim = 0; // facing angle (radians)
  bool alive = true;
  int kills = 0;
  int placement = 0;
  double hitFlash = 0; // white flash timer when damaged
  double stepT = 0; // time to the next boot print
  bool stepFoot = false; // which foot the next print belongs to

  // appearance (customization) — color above is the outfit/suit colour
  Color skin = const Color(0xFFF4CBA2);
  int accessory = 0; // index into kAccessoryNames
  int hero = 0; // index into kHeroes — drives signature gear (shield, pack…)

  // ---- weapon state: TWO SLOTS, like every proper shooter ----
  //
  // Picking a gun off the ground can only ever fill an EMPTY slot. It never
  // rips the gun out of your hands mid-fight — swapping is a deliberate tap on
  // the switch button (or Q on desktop). `slots[slot]` is what you're holding.
  final List<WeaponId?> slots = [WeaponId.pistol, null];
  int slot = 0; // 0 or 1 — which slot is in your hands
  final List<int> slotAmmo = [kWeapons[WeaponId.pistol]!.mag, 0];
  double reloadT = 0; // remaining reload seconds (>0 = reloading)
  double cooldown = 0; // seconds until next shot allowed
  double muzzle = 0; // muzzle-flash timer
  double swapT = 0; // brief "raising the gun" delay after switching

  // grenades
  int grenades = kGrenadeStart;
  double throwCd = 0; // seconds until next throw allowed

  // ---- armour: soaks a share of incoming damage until it breaks ----
  double vest = 0; // remaining vest durability (0 = none)
  double helmet = 0; // remaining helmet durability
  double armourFlash = 0; // brief spark when armour eats a hit

  // ---- deployable shield walls (gloo-wall style cover) ----
  int walls = kShieldWallStart;
  double wallCd = 0;

  /// Fraction of incoming damage that gets through the armour, and wears it
  /// down in the process. Armour absorbs, it doesn't make you invincible.
  double soak(double dmg) {
    var cut = 0.0;
    if (vest > 0) cut += kVestReduction;
    if (helmet > 0) cut += kHelmetReduction;
    if (cut <= 0) return dmg;
    final absorbed = dmg * cut;
    // split the wear between the pieces that are actually carrying it
    if (vest > 0 && helmet > 0) {
      vest -= absorbed * 0.6;
      helmet -= absorbed * 0.4;
    } else if (vest > 0) {
      vest -= absorbed;
    } else {
      helmet -= absorbed;
    }
    if (vest < 0) vest = 0;
    if (helmet < 0) helmet = 0;
    armourFlash = 0.12;
    return dmg - absorbed;
  }

  // hero skill state (player)
  double skillCd = 0; // cooldown remaining
  double shieldT = 0; // shield protection timer
  double frenzyT = 0; // frenzy (fast fire) timer

  // AI state
  int aiState = 0; // 0 = loot/wander, 1 = fight, 2 = flee zone
  final Vector2 aiTarget = Vector2.zero();
  double aiRepath = 0;
  double aiReact = 0;
  double aiStuck = 0;
  double aiScan = 0; // time until next (expensive) enemy re-scan
  double aiSkill = 0.5; // 0..1 accuracy
  double aiDamage = 1.0; // damage multiplier on shots this bot fires
  double aiPreferred = 240; // preferred engagement distance
  Character? aiEnemy;
  final Vector2 _lastPos = Vector2.zero();

  Character(this.id, this.isBot, this.name, this.color, Vector2 spawn)
      : pos = spawn.clone() {
    _lastPos.setFrom(pos);
  }

  // ---- weapon accessors -------------------------------------------------
  WeaponId get weaponId => slots[slot] ?? WeaponId.pistol;
  set weaponId(WeaponId w) {
    slots[slot] = w;
    slotAmmo[slot] = kWeapons[w]!.mag;
  }

  Weapon get weapon => kWeapons[weaponId]!;
  bool get reloading => reloadT > 0;
  bool get swapping => swapT > 0;

  int get ammo => slotAmmo[slot];
  set ammo(int v) => slotAmmo[slot] = v;

  WeaponId? get otherWeapon => slots[1 - slot];
  bool get hasEmptySlot => slots[0] == null || slots[1] == null;

  /// Puts [w] in the first empty slot. Returns false if both are taken.
  bool addWeapon(WeaponId w) {
    final i = slots.indexWhere((s) => s == null);
    if (i < 0) return false;
    slots[i] = w;
    slotAmmo[i] = kWeapons[w]!.mag;
    return true;
  }

  /// Replaces the gun in your hands with [w] and returns the one dropped.
  WeaponId? replaceWeapon(WeaponId w) {
    final old = slots[slot];
    slots[slot] = w;
    slotAmmo[slot] = kWeapons[w]!.mag;
    reloadT = 0;
    swapT = 0.25;
    return old;
  }

  /// Switch to the other slot. No-op when there's nothing to switch to.
  bool switchSlot() {
    final other = 1 - slot;
    if (slots[other] == null) return false;
    slot = other;
    reloadT = 0; // switching cancels a reload, as it should
    cooldown = 0;
    swapT = 0.22; // small raise time so it isn't a free instant-DPS combo
    return true;
  }

  /// Hold whichever of the two slots is the better gun (bots only — a human
  /// picks for themselves).
  void equipBest() {
    final a = slots[0], b = slots[1];
    if (a != null && b != null) {
      slot = weaponScore(a) >= weaponScore(b) ? 0 : 1;
    } else {
      slot = a != null ? 0 : 1;
    }
  }

  /// Starting loadout: [primary] in hand, pistol as the backup.
  void equipLoadout(WeaponId primary) {
    slots[0] = primary;
    slotAmmo[0] = kWeapons[primary]!.mag;
    if (primary == WeaponId.pistol) {
      slots[1] = null;
      slotAmmo[1] = 0;
    } else {
      slots[1] = WeaponId.pistol;
      slotAmmo[1] = kWeapons[WeaponId.pistol]!.mag;
    }
    slot = 0;
    reloadT = 0;
    swapT = 0;
  }

  /// distance the character has moved since last stuck-check sample
  double sampleProgress() {
    final d = pos.distanceTo(_lastPos);
    _lastPos.setFrom(pos);
    return d;
  }
}
