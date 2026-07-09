import 'package:flame/components.dart' show Vector2;
import 'dart:ui';
import 'config.dart';
import 'mathx.dart';

// ============================ Obstacles =======================
enum ObstacleKind { wall, crate, bush }

class Obstacle {
  final ObstacleKind kind;
  final double x, y, w, h;
  const Obstacle(this.kind, this.x, this.y, this.w, this.h);

  bool get blocks => kind != ObstacleKind.bush; // bushes never block
  bool get conceals => kind == ObstacleKind.bush;
  Rect get rect => Rect.fromLTWH(x, y, w, h);

  bool contains(double px, double py) =>
      px >= x && px <= x + w && py >= y && py <= y + h;
}

// ============================ Loot ============================
enum LootKind { weapon, medkit, grenade }

class Loot {
  final LootKind kind;
  final Vector2 pos;
  final WeaponId? weapon;
  final double heal;
  double bob = randRange(0, kTau);
  bool taken = false;
  double readyAt = 0; // world time before it can be picked up (freshly dropped)

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

  // appearance (customization) — color above is the outfit/suit colour
  Color skin = const Color(0xFFF4CBA2);
  int accessory = 0; // index into kAccessoryNames
  int hero = 0; // index into kHeroes — drives signature gear (shield, pack…)

  // weapon state
  WeaponId weaponId = WeaponId.pistol;
  int ammo = kWeapons[WeaponId.pistol]!.mag;
  double reloadT = 0; // remaining reload seconds (>0 = reloading)
  double cooldown = 0; // seconds until next shot allowed
  double muzzle = 0; // muzzle-flash timer

  // grenades
  int grenades = kGrenadeStart;
  double throwCd = 0; // seconds until next throw allowed

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
  double aiPreferred = 240; // preferred engagement distance
  Character? aiEnemy;
  final Vector2 _lastPos = Vector2.zero();

  Character(this.id, this.isBot, this.name, this.color, Vector2 spawn)
      : pos = spawn.clone() {
    _lastPos.setFrom(pos);
  }

  Weapon get weapon => kWeapons[weaponId]!;
  bool get reloading => reloadT > 0;

  /// distance the character has moved since last stuck-check sample
  double sampleProgress() {
    final d = pos.distanceTo(_lastPos);
    _lastPos.setFrom(pos);
    return d;
  }
}
