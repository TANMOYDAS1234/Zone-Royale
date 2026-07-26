// Zone Royale — authoritative multiplayer arena server.
//
// Pure dart:io WebSocket server. Players connect, send their inputs, and the
// server runs the ONE true simulation (movement + weapons + hits + kills) and
// broadcasts a world snapshot to everyone. This is the piece that lets real
// people fight each other — the Flutter client connects to it from CUSTOM ROOM
// and QUICK MATCH.
//
// Design notes that matter for how it FEELS online:
//
//  * Real guns. The client ships its whole weapon table with the room config,
//    so an online SMG behaves like the offline SMG: its own fire rate, mag,
//    reload, spread, pellets and auto/semi trigger. (The old build fired one
//    bullet per trigger *press*, which is why holding the stick felt broken.)
//  * Two weapon slots, never auto-swapped. Loot fills an empty slot; trading a
//    gun you're holding takes a deliberate PICK UP.
//  * Snapshots are compact arrays, not objects, and carry no player names —
//    those arrive once in a roster message. Bullets aren't streamed at all:
//    the server broadcasts *shot events* and each client flies the tracer
//    locally with the real weapon stats. That's a fraction of the bandwidth
//    and the bullets look perfectly smooth instead of stepping 30x/second.
//
// Run:   dart run server/bin/server.dart          (listens on :8080)

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const double worldSize = 3200;
const int tickHz = 30; // simulation + snapshot rate
const double playerSpeed = 250;
const double hitRadius = 22;
const double nadeSpeed = 560;
const double nadeFuse = 1.3; // seconds of flight before it detonates
const double nadeRadius = 150; // blast radius
const double nadeDamage = 70; // damage at the centre (falls off with distance)
const double skillCooldown = 12;
const double maxStep = 16; // bullet sub-step, so fast rounds can't tunnel

// ---- armour (mirrors the offline game) ----
const double vestReduction = 0.30;
const double helmetReduction = 0.22;
const double vestDurability = 120;
const double helmetDurability = 70;

// ---- deployable shield walls ----
const double wallWidth = 132;
const double wallThickness = 26;
const double wallHp = 260;
const double wallLife = 16;
const int wallStart = 2;
const int wallMax = 4;
const double wallCooldown = 1.2;

int _nextId = 1;
final Random _rng = Random();

/// One gun. Mirrors `Weapon` in the client's config.dart — the client sends the
/// whole table on join so both sides simulate identical ballistics.
class Gun {
  final int i;
  final double dmg, speed, range, rof, reload, spread;
  final int mag, pellets;
  final bool auto;
  const Gun(this.i, this.dmg, this.speed, this.range, this.rof, this.mag,
      this.reload, this.spread, this.pellets, this.auto);

  static Gun from(Map m, int fallbackIndex) => Gun(
        (m['i'] as num?)?.toInt() ?? fallbackIndex,
        (m['dmg'] as num?)?.toDouble() ?? 18,
        (m['speed'] as num?)?.toDouble() ?? 900,
        (m['range'] as num?)?.toDouble() ?? 620,
        (m['rof'] as num?)?.toDouble() ?? 0.25,
        (m['mag'] as num?)?.toInt() ?? 20,
        (m['rl'] as num?)?.toDouble() ?? 1.6,
        (m['sp'] as num?)?.toDouble() ?? 0.05,
        (m['pel'] as num?)?.toInt() ?? 1,
        m['auto'] == true,
      );

  /// Sane defaults so a room still works if a client sends no table at all.
  static const Gun fallback = Gun(5, 18, 900, 620, 0.25, 20, 1.6, 0.05, 1, true);
}

// Rooms keyed by code ("PUBLIC" when none given) — this is what makes BGMI/
// Free-Fire-style custom rooms work: friends who share a code land together.
final Map<String, Room> rooms = {};
Room roomFor(String code) {
  final key = code.trim().isEmpty ? 'PUBLIC' : code.trim().toUpperCase();
  return rooms.putIfAbsent(key, () => Room(key));
}

/// Matchmaking for QUICK MATCH. Preference order:
///   1. a public room that has NOT started yet and has a free slot (so people
///      actually land in the same lobby and start together),
///   2. a running public room with space (drop straight into the action),
///   3. a brand new room.
/// Joining a lobby beats joining a firefight already in progress.
Room pickPublicRoom() {
  Room? running;
  for (final r in rooms.values) {
    if (!r.code.startsWith('PUBLIC')) continue;
    if (r.humans >= r.maxPlayers) continue;
    if (!r.started && !r.matchOver) return r;
    running ??= r;
  }
  if (running != null) return running;
  var i = 1;
  while (rooms.containsKey('PUBLIC$i')) {
    i++;
  }
  return roomFor('PUBLIC$i');
}

void _leave(Player p) {
  final room = p.roomRef;
  if (room == null || p.isBot) return;
  room.remove(p);
  if (room.humans == 0) {
    room.dispose();
    rooms.remove(room.code);
    print('- room "${room.code}" closed (no humans)');
  }
}

class Player {
  final int id;
  final WebSocket? socket; // null for bots
  bool get isBot => socket == null;
  double x, y;
  double aim = 0, hp = 100;
  double mx = 0, my = 0; // movement input (-1..1)
  bool fire = false, alive = true;
  int kills = 0;
  int roundWins = 0;

  /// Humans only join the fight after pressing START MISSION. Until then they
  /// sit in the lobby: not shootable, not targeted, not counted for round end.
  bool ready = false;

  // ---- bot brain + difficulty profile (bots are weaker than a human) ----
  double fireCd = 0; // extra bot trigger discipline on top of the gun's rof
  double wanderT = 0;
  double wx = 0, wy = 0;
  double aimErr = 0.2; // radians of aim jitter
  double burst = 0; // seconds left of the current burst
  double vision = 520; // how far a bot can see you
  double spdMul = 0.85; // fraction of the human run speed
  double dmgMul = 0.5; // fraction of the weapon's damage
  double nadeChance = 0, skillChance = 0;

  // ---- weapons: two slots, exactly like the offline game ----
  final List<int> slots = [5, -1]; // weapon indices; -1 = empty
  int slot = 0;
  final List<int> ammo = [0, 0];
  double shotCd = 0; // time until the next shot is allowed
  double reloadT = 0; // >0 while reloading
  double swapT = 0; // brief raise time after switching guns
  bool firePrev = false; // for semi-auto edge detection

  // ---- armour + deployable cover ----
  double vest = 0;
  double helmet = 0;
  int walls = wallStart;
  double wallCd = 0;

  /// Damage that gets through the armour, wearing it down on the way.
  double soak(double dmg) {
    var cut = 0.0;
    if (vest > 0) cut += vestReduction;
    if (helmet > 0) cut += helmetReduction;
    if (cut <= 0) return dmg;
    final absorbed = dmg * cut;
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
    return dmg - absorbed;
  }

  // grenades + hero skill
  int grenades = 2;
  int hero = 0; // index into the client's hero list
  int baseWi = 5; // the player's own loadout weapon (used in ALL_ARMS rooms)
  double skillCd = 0;
  double dashT = 0;
  double shieldT = 0;
  double boostT = 0;
  String name;
  Room? roomRef;
  Player(this.id, this.socket, this.x, this.y, this.name);

  int get wi => slots[slot];
  int get otherWi => slots[1 - slot];
}

class Bullet {
  double x, y, vx, vy, dist = 0;
  final int owner;
  final double dmg, range;
  Bullet(this.x, this.y, this.vx, this.vy, this.owner, this.dmg, this.range);
}

class Grenade {
  double x, y, vx, vy, fuse;
  final int owner;
  Grenade(this.x, this.y, this.vx, this.vy, this.fuse, this.owner);
}

// A ground pickup.
// kind: 0 medkit · 1 weapon · 2 airdrop · 3 vest · 4 helmet · 5 shield wall
//       6 grenade
int _lootId = 1;

class Loot {
  final int id;
  final double x, y;
  final int kind;
  final int wi; // weapon index (weapon crates)
  Loot(this.id, this.x, this.y, this.kind, this.wi);
  List<int> get packed => [x.round(), y.round(), kind, wi];
}

/// A deployed shield wall: real cover with hit points and a timer.
class Wall {
  double x, y, w, h, hp, life;
  final int owner;
  Wall(this.x, this.y, this.w, this.h, this.hp, this.life, this.owner);
  List<int> get packed => [
        x.round(),
        y.round(),
        w.round(),
        h.round(),
        ((hp / wallHp) * 100).round().clamp(0, 100),
      ];
}

// A rectangular obstacle (building/cover). x,y is the centre.
class Obs {
  final double x, y, hw, hh;
  final int kind; // 0 building · 1 crate · 2 bush (see-through, no collision)
  Obs(this.x, this.y, this.hw, this.hh, this.kind);
  Map<String, int> get json => {
        'x': x.round(),
        'y': y.round(),
        'w': (hw * 2).round(),
        'h': (hh * 2).round(),
        'k': kind,
      };
  bool get blocks => kind != 2;
}

class Room {
  final String code;
  final List<Player> players = [];
  final List<Bullet> bullets = [];
  Timer? _loop;
  Room(this.code);

  // ---- host-configurable match settings (BGMI-style custom room) ----
  bool configured = false;
  int hostId = 0; // whoever configured the room owns the rules
  double world = worldSize;
  String map = 'RANDOM';
  String weapon = 'ALL_ARMS';
  int maxPlayers = 10;
  int rounds = 1; // round wins needed to win the match
  int roundNo = 1;
  bool _roundEnding = false;
  bool matchOver = false;

  // ---- weapons + loot + grenades ----
  final Map<int, Gun> guns = {}; // index -> stats (from the host's table)
  int startWi = 5;
  bool allArms = true; // when true each player keeps their own loadout weapon
  bool allowMedkits = true;
  bool allowGrenades = true;
  bool allowSkills = true;
  bool fillBots = true; // top the room up with bots so it's always playable
  int botTarget = 8; // total bodies (humans + bots) to aim for
  int botDifficulty = 1; // 0 easy · 1 normal · 2 hard — all weaker than a human

  // ---- per-tick event queues (flushed with the snapshot) ----
  final List<List<int>> _shots = []; // [x, y, aim*100, wi, shooterId]
  final List<List<int>> _booms = []; // [x, y]
  bool _rosterDirty = true;

  Gun gunFor(int wi) => guns[wi] ?? Gun.fallback;
  Gun held(Player p) => gunFor(p.wi);

  /// Humans who have pressed START MISSION. Combat doesn't run until >= 1.
  int get readyHumans {
    var n = 0;
    for (final p in players) {
      if (!p.isBot && p.ready) n++;
    }
    return n;
  }

  bool get started => readyHumans > 0;

  /// Players actually in the fight (ready humans + bots).
  bool _inPlay(Player p) => p.isBot || p.ready;

  /// Only real players count toward the room's PLAYER LIMIT.
  int get humans {
    var n = 0;
    for (final p in players) {
      if (!p.isBot) n++;
    }
    return n;
  }

  int get botCount {
    var n = 0;
    for (final p in players) {
      if (p.isBot) n++;
    }
    return n;
  }

  final List<Loot> loot = [];
  final List<Grenade> grenades = [];
  final List<Wall> walls = [];

  // ---- map cover + shrinking gas zone (parity with a normal match) ----
  final List<Obs> obstacles = [];
  double zx = worldSize / 2, zy = worldSize / 2;
  double zr = worldSize * 0.72; // current safe radius
  double _elapsed = 0; // seconds into the round
  double _nextDrop = 45; // seconds until the next airdrop
  int _drops = 0;
  static const double _zoneWait = 16; // grace before the zone shrinks
  static const double _zoneShrink = 100; // seconds to reach the final ring
  static const double _zoneDps = 6; // damage/second outside the safe circle

  /// The host's MAP choice actually reshapes the arena: how much cover there
  /// is, how big it gets, and what kind (buildings / trees / walls / boulders).
  void _genMap() {
    obstacles.clear();
    final base = (world * world / 300000).round();
    double density, minHalf, maxHalf;
    int kind; // 0 building · 1 crate · 2 bush
    double bushRatio;
    switch (map.toUpperCase()) {
      case 'URBAN BUILDINGS':
      case 'URBAN':
        density = 1.2;
        minHalf = 40;
        maxHalf = 105;
        kind = 0;
        bushRatio = 0.05;
        break;
      case 'FOREST':
        density = 1.9;
        minHalf = 20;
        maxHalf = 38;
        kind = 1;
        bushRatio = 0.45; // lots of see-through undergrowth
        break;
      case 'COMPOUND':
        density = 1.4;
        minHalf = 26;
        maxHalf = 125;
        kind = 0;
        bushRatio = 0.1;
        break;
      case 'BADLANDS':
        density = 0.7;
        minHalf = 55;
        maxHalf = 120;
        kind = 1;
        bushRatio = 0.12;
        break;
      default: // RANDOM
        density = 1.0;
        minHalf = 30;
        maxHalf = 90;
        kind = 0;
        bushRatio = 0.2;
    }
    final n = (base * density).round().clamp(8, 80);
    var tries = 0;
    while (obstacles.length < n && tries < n * 6) {
      tries++;
      final hw = minHalf + _rng.nextDouble() * (maxHalf - minHalf);
      final hh = minHalf + _rng.nextDouble() * (maxHalf - minHalf);
      final x = 60 + _rng.nextDouble() * (world - 120);
      final y = 60 + _rng.nextDouble() * (world - 120);
      // keep the exact centre a bit clearer
      if ((x - world / 2).abs() < 120 && (y - world / 2).abs() < 120) continue;
      final k = _rng.nextDouble() < bushRatio ? 2 : kind;
      obstacles.add(Obs(x, y, hw, hh, k));
    }
    _resetZone();
    _spawnLoot();
  }

  void _resetZone() {
    zx = world / 2;
    zy = world / 2;
    zr = world * 0.72;
    _elapsed = 0;
    _nextDrop = 45;
    _drops = 0;
  }

  // ---- bots: keep the room populated so a match is always playable ----
  static const _botNames = [
    'VIPER', 'GHOST', 'RAVEN', 'HAWK', 'WOLF', 'ONYX', 'ECHO', 'NOVA',
    'BLAZE', 'FROST', 'DELTA', 'ZERO', 'TITAN', 'ROGUE', 'STORM', 'ATLAS',
  ];

  /// Bots are tuned to be clearly *weaker* than a human: less damage, shakier
  /// aim, shorter sight, slower legs, and they never hold the trigger forever.
  void _applyBotTier(Player b) {
    switch (botDifficulty) {
      case 0: // easy
        b.aimErr = 0.32;
        b.vision = 440;
        b.spdMul = 0.76;
        b.dmgMul = 0.42;
        b.nadeChance = 0;
        b.skillChance = 0;
        break;
      case 2: // hard
        b.aimErr = 0.13;
        b.vision = 660;
        b.spdMul = 0.94;
        b.dmgMul = 0.78;
        b.nadeChance = 0.25;
        b.skillChance = 0.3;
        break;
      default: // normal
        b.aimErr = 0.21;
        b.vision = 540;
        b.spdMul = 0.85;
        b.dmgMul = 0.58;
        b.nadeChance = 0.1;
        b.skillChance = 0.12;
    }
    // per-bot variance (±10%) so a squad isn't a hive mind
    final v = 0.9 + _rng.nextDouble() * 0.2;
    b.dmgMul *= v;
    b.spdMul = (b.spdMul * v).clamp(0.6, 0.97); // never outrun a human
    b.aimErr /= v;
  }

  void _addBot() {
    final id = _nextId++;
    final b = Player(id, null, 0, 0, 'BOT ${_botNames[id % _botNames.length]}');
    b.ready = true; // bots are always in the fight
    b.hero = _rng.nextInt(5);
    b.baseWi = guns.isEmpty
        ? startWi
        : guns.keys.elementAt(_rng.nextInt(guns.length));
    _applyBotTier(b);
    b.roomRef = this;
    players.add(b);
    _spawn(b);
    _rosterDirty = true;
  }

  /// Bots fill the gap between the human count and [botTarget]; they step aside
  /// as real players arrive.
  void _syncBots() {
    if (!fillBots || !started || humans == 0) {
      if (botCount > 0) _rosterDirty = true;
      players.removeWhere((p) => p.isBot);
      return;
    }
    // bots never push the room over its own limit
    final cap = botTarget.clamp(2, maxPlayers);
    final want = (cap - humans).clamp(0, cap);
    var have = botCount;
    while (have < want) {
      _addBot();
      have++;
    }
    while (have > want) {
      final idx = players.indexWhere((p) => p.isBot && !p.alive);
      players.removeAt(idx >= 0 ? idx : players.indexWhere((p) => p.isBot));
      have--;
      _rosterDirty = true;
    }
  }

  void _botThink(double dt) {
    for (final b in players) {
      if (!b.isBot || !b.alive) continue;
      b.fireCd -= dt;

      // 1) stay inside the safe circle — it always wins over fighting
      final zdx = zx - b.x, zdy = zy - b.y;
      final zd = sqrt(zdx * zdx + zdy * zdy);
      if (zd > zr * 0.82) {
        b.mx = zdx / (zd == 0 ? 1 : zd);
        b.my = zdy / (zd == 0 ? 1 : zd);
        b.aim = atan2(b.my, b.mx);
        b.fire = false;
        continue;
      }

      // 2) hunt the nearest living opponent that's actually in the fight
      Player? target;
      var best = 1e9;
      for (final p in players) {
        if (p.id == b.id || !p.alive || !_inPlay(p)) continue;
        final dx = p.x - b.x, dy = p.y - b.y;
        final d = dx * dx + dy * dy;
        if (d < best) {
          best = d;
          target = p;
        }
      }
      final dist = sqrt(best);
      final gun = held(b);
      if (target != null && dist < b.vision) {
        final dx = target.x - b.x, dy = target.y - b.y;
        // shaky aim — the main reason bots lose fights to a human
        b.aim = atan2(dy, dx) + (_rng.nextDouble() - 0.5) * b.aimErr * 2;
        // keep a fighting distance
        final move = dist > 300 ? 1.0 : (dist < 130 ? -1.0 : 0.0);
        b.mx = (dx / dist) * move;
        b.my = (dy / dist) * move;

        if (b.fireCd <= 0 && !matchOver) {
          final roll = _rng.nextDouble();
          if (allowGrenades &&
              b.grenades > 0 &&
              dist > 220 &&
              dist < 520 &&
              roll < b.nadeChance) {
            b.grenades--;
            b.fireCd = 1.2;
            _throwNade(b);
          } else if (b.walls > 0 &&
              b.wallCd <= 0 &&
              b.hp < 55 &&
              roll < 0.35) {
            b.fireCd = 0.8;
            _deployWall(b); // throw up cover like a real player would
          } else if (allowSkills && b.skillCd <= 0 && roll < b.skillChance) {
            b.fireCd = 1.0;
            _activateSkill(b);
          } else if (dist < gun.range * 0.9) {
            // fire in bursts, then breathe — a constant laser is what made
            // bots feel unfair
            if (b.burst <= 0) {
              b.burst = 0.25 + _rng.nextDouble() * 0.5;
              b.fireCd = b.burst + 0.35 + _rng.nextDouble() * 0.6;
            }
          }
        }
        b.burst -= dt;
        b.fire = b.burst > 0 && dist < gun.range * 0.9;
        continue;
      }

      b.fire = false;
      b.burst = 0;
      // 3) nobody near — wander toward a point inside the zone
      b.wanderT -= dt;
      if (b.wanderT <= 0) {
        b.wanderT = 2 + _rng.nextDouble() * 3;
        final a = _rng.nextDouble() * 2 * pi;
        final r = _rng.nextDouble() * zr * 0.7;
        b.wx = zx + cos(a) * r;
        b.wy = zy + sin(a) * r;
      }
      final wdx = b.wx - b.x, wdy = b.wy - b.y;
      final wd = sqrt(wdx * wdx + wdy * wdy);
      if (wd > 12) {
        b.mx = wdx / wd;
        b.my = wdy / wd;
        b.aim = atan2(wdy, wdx);
      } else {
        b.mx = 0;
        b.my = 0;
      }
    }
  }

  void _spawnLoot() {
    loot.clear();
    // If the host forced a single WEAPON TYPE, weapon crates would break that
    // rule (you'd pick up a different gun), so only medkits drop.
    final canDropGuns = allArms && guns.isNotEmpty;
    if (!canDropGuns && !allowMedkits) return; // nothing legal to drop
    final k = (obstacles.length * 0.8).round().clamp(8, 34);
    for (var i = 0; i < k; i++) {
      final spot = _openSpot();
      final wantMed =
          allowMedkits && (!canDropGuns || _rng.nextDouble() < 0.38);
      if (wantMed) {
        loot.add(Loot(_lootId++, spot[0], spot[1], 0, -1));
      } else if (canDropGuns) {
        loot.add(Loot(_lootId++, spot[0], spot[1], 1, _randomWi()));
      }
    }
    // Gear: armour and shield-wall charges. Worth breaking cover for, which
    // is exactly what keeps a match moving.
    final gear = (k * 0.75).round().clamp(4, 24);
    for (var i = 0; i < gear; i++) {
      final spot = _openSpot();
      final roll = _rng.nextDouble();
      // grenades are in the mix now, the way they are offline — without them
      // you fought a whole online match on the two you spawned with
      final kind = roll < 0.30
          ? 3
          : roll < 0.55
              ? 4
              : roll < 0.78
                  ? 5
                  : 6;
      loot.add(Loot(_lootId++, spot[0], spot[1], kind, -1));
    }
  }

  int _randomWi() => guns.keys.elementAt(_rng.nextInt(guns.length));

  List<double> _openSpot() {
    double x = 0, y = 0;
    for (var t = 0; t < 24; t++) {
      x = 70 + _rng.nextDouble() * (world - 140);
      y = 70 + _rng.nextDouble() * (world - 140);
      if (!_blocksPlayer(x, y)) break;
    }
    return [x, y];
  }

  bool _blocksPlayer(double x, double y) {
    for (final o in obstacles) {
      if (!o.blocks) continue;
      if ((x - o.x).abs() < o.hw + 18 && (y - o.y).abs() < o.hh + 18) {
        return true;
      }
    }
    for (final w in walls) {
      if ((x - w.x).abs() < w.w / 2 + 16 && (y - w.y).abs() < w.h / 2 + 16) {
        return true;
      }
    }
    return false;
  }

  bool _blocksBullet(double x, double y) {
    for (final o in obstacles) {
      if (!o.blocks) continue;
      if ((x - o.x).abs() < o.hw && (y - o.y).abs() < o.hh) return true;
    }
    return false;
  }

  /// The shield wall a bullet at (x,y) just hit, if any.
  Wall? _wallAt(double x, double y) {
    for (final w in walls) {
      if ((x - w.x).abs() < w.w / 2 && (y - w.y).abs() < w.h / 2) return w;
    }
    return null;
  }

  void _deployWall(Player p) {
    if (!p.alive || p.walls <= 0 || p.wallCd > 0) return;
    final ax = p.x + cos(p.aim) * (hitRadius + 46);
    final ay = p.y + sin(p.aim) * (hitRadius + 46);
    if (_blocksPlayer(ax, ay)) return;
    final horizontal = sin(p.aim).abs() > cos(p.aim).abs();
    final w = horizontal ? wallWidth : wallThickness;
    final h = horizontal ? wallThickness : wallWidth;
    p.walls--;
    p.wallCd = wallCooldown;
    walls.add(Wall(
      ax.clamp(w / 2, world - w / 2),
      ay.clamp(h / 2, world - h / 2),
      w,
      h,
      wallHp,
      wallLife,
      p.id,
    ));
  }

  /// Applies the host's rules. Called when the first human enters an empty
  /// room, and whenever the host re-sends them from the lobby — so changing a
  /// setting and pressing CREATE/JOIN actually takes effect instead of being
  /// silently ignored.
  void configure(Map cfg) {
    world = (cfg['world'] as num?)?.toDouble() ?? world;
    map = (cfg['map'] as String?) ?? map;
    weapon = (cfg['weapon'] as String?) ?? weapon;
    allArms = weapon.toUpperCase() == 'ALL_ARMS';
    maxPlayers = ((cfg['maxPlayers'] as num?)?.toInt() ?? maxPlayers).clamp(2, 64);
    rounds = ((cfg['rounds'] as num?)?.toInt() ?? rounds).clamp(1, 9);
    startWi = (cfg['startWi'] as num?)?.toInt() ?? startWi;
    allowMedkits = cfg['medkit'] != false;
    allowGrenades = cfg['grenades'] != false;
    allowSkills = cfg['skills'] != false;
    fillBots = cfg['bots'] != false;
    botTarget = ((cfg['botTarget'] as num?)?.toInt() ?? botTarget).clamp(2, 30);
    botDifficulty =
        ((cfg['botDifficulty'] as num?)?.toInt() ?? botDifficulty).clamp(0, 2);
    final wl = cfg['weapons'];
    if (wl is List && wl.isNotEmpty) {
      guns.clear();
      for (final w in wl) {
        if (w is Map) {
          final g = Gun.from(w, startWi);
          guns[g.i] = g;
        }
      }
    }
    // the arena depends on `map` and `world`, so rebuild it with the new rules
    obstacles.clear();
    loot.clear();
    _genMap();
    for (final p in players) {
      _spawn(p);
    }
    _syncBots();
    configured = true;
  }

  Map<String, dynamic> get cfgMsg => {
        'type': 'roomcfg',
        'code': code,
        'world': world,
        'map': map,
        'weapon': weapon,
        'rounds': rounds,
        'round': roundNo,
        'maxPlayers': maxPlayers,
        'host': hostId,
        'medkit': allowMedkits,
        'grenades': allowGrenades,
        'skills': allowSkills,
        'bots': fillBots,
        'botTarget': botTarget,
        'botDifficulty': botDifficulty,
        'started': started,
        'obstacles': [for (final o in obstacles) o.json],
      };

  /// Names/heroes change rarely, so they ride their own message instead of
  /// being repeated in every single snapshot.
  Map<String, dynamic> get rosterMsg => {
        'type': 'roster',
        'players': [
          for (final p in players)
            {
              'id': p.id,
              'name': p.name,
              'bot': p.isBot,
              'hero': p.hero,
            }
        ],
      };

  void add(Player p) {
    players.add(p);
    if (obstacles.isEmpty) _genMap(); // build the arena once, on first join
    if (hostId == 0 || humans == 1) hostId = p.id;
    _send(p, {'type': 'welcome', 'id': p.id, 'world': world});
    _syncBots(); // top up (or free up) bot slots for the new human
    _rosterDirty = true;
    broadcast(cfgMsg); // everyone learns the room rules + map
    broadcast(rosterMsg);
    _loop ??=
        Timer.periodic(Duration(milliseconds: 1000 ~/ tickHz), (_) => _tick());
    print('+ player ${p.id} -> room "$code" '
        '($humans human/$botCount bot, map=$map, gun=$weapon, rounds=$rounds)');
  }

  void remove(Player p) {
    players.remove(p);
    _rosterDirty = true;
    print('- player ${p.id} ($humans human online)');
    if (humans == 0) {
      // nobody real left — stop the sim and drop the bots
      _loop?.cancel();
      _loop = null;
      players.removeWhere((q) => q.isBot);
      bullets.clear();
      grenades.clear();
    } else {
      if (p.id == hostId) {
        hostId = players.firstWhere((q) => !q.isBot, orElse: () => p).id;
      }
      _syncBots();
      broadcast(rosterMsg);
    }
  }

  void dispose() {
    _loop?.cancel();
    _loop = null;
    bullets.clear();
  }

  // =====================================================================
  //  INPUT
  // =====================================================================
  void onInput(Player p, Map<dynamic, dynamic> m) {
    p.mx = (m['mx'] as num?)?.toDouble() ?? 0;
    p.my = (m['my'] as num?)?.toDouble() ?? 0;
    p.aim = (m['aim'] as num?)?.toDouble() ?? p.aim;
    p.fire = m['fire'] == true;

    if (!p.alive || matchOver) return;

    if (m['reload'] == true) _startReload(p);
    if (m['swap'] == true) _swap(p);
    if (m['take'] == true) _takeNearest(p);
    if (m['wall'] == true) _deployWall(p);

    // throw a grenade (only if the room allows them)
    if (allowGrenades && m['nade'] == true && p.grenades > 0) {
      p.grenades--;
      _throwNade(p);
    }
    // activate the hero skill (only if the room allows skills)
    if (allowSkills && m['skill'] == true && p.skillCd <= 0) {
      _activateSkill(p);
    }
  }

  void _throwNade(Player p) {
    grenades.add(Grenade(
      p.x + cos(p.aim) * hitRadius,
      p.y + sin(p.aim) * hitRadius,
      cos(p.aim) * nadeSpeed,
      sin(p.aim) * nadeSpeed,
      nadeFuse,
      p.id,
    ));
  }

  void _startReload(Player p) {
    final g = held(p);
    if (p.reloadT > 0 || p.ammo[p.slot] >= g.mag) return;
    p.reloadT = g.reload * (p.boostT > 0 ? 0.55 : 1.0);
  }

  void _swap(Player p) {
    final other = 1 - p.slot;
    if (p.slots[other] < 0) return;
    p.slot = other;
    p.reloadT = 0;
    p.swapT = 0.22;
    p.shotCd = 0;
  }

  /// PICK UP: trade the gun in your hands for the crate you're standing on.
  /// Only ever runs when the player asks for it.
  void _takeNearest(Player p) {
    for (final l in loot) {
      if (l.kind == 0) continue;
      final dx = p.x - l.x, dy = p.y - l.y;
      if (dx * dx + dy * dy > 44 * 44) continue;
      if (p.slots.contains(l.wi)) continue;
      final dropped = p.slots[p.slot];
      p.slots[p.slot] = l.wi;
      p.ammo[p.slot] = gunFor(l.wi).mag;
      p.reloadT = 0;
      p.swapT = 0.25;
      loot.remove(l);
      if (dropped >= 0) {
        loot.add(Loot(_lootId++, p.x - cos(p.aim) * 34, p.y - sin(p.aim) * 34,
            1, dropped));
      }
      return;
    }
  }

  // Hero skill by index: 0 dash, 1 shield, 2 frenzy(dmg boost), 3 medic, 4 grenadier.
  void _activateSkill(Player p) {
    p.skillCd = skillCooldown;
    switch (p.hero % 5) {
      case 0:
        p.dashT = 2.2;
        break;
      case 1:
        p.shieldT = 3.5;
        break;
      case 2:
        p.boostT = 5;
        break;
      case 3:
        p.hp = (p.hp + 55).clamp(0.0, 100.0);
        break;
      case 4:
        p.grenades += 2;
        break;
    }
    broadcast({'type': 'skill', 'id': p.id, 'hero': p.hero % 5});
  }

  void _spawn(Player p) {
    // spawn on open ground (not inside a building)
    final spot = _openSpot();
    p.x = spot[0];
    p.y = spot[1];
    p.hp = 100;
    p.alive = true;
    // ALL_ARMS: each player keeps their own loadout gun (plus a pistol backup);
    // otherwise everyone uses the host's forced weapon — no second slot, so the
    // rule can't be dodged by picking something else up.
    if (allArms) {
      p.slots[0] = p.baseWi;
      p.slots[1] = p.baseWi == 0 ? -1 : 0; // pistol is index 0
      p.ammo[0] = gunFor(p.slots[0]).mag;
      p.ammo[1] = p.slots[1] < 0 ? 0 : gunFor(p.slots[1]).mag;
    } else {
      p.slots[0] = startWi;
      p.slots[1] = -1;
      p.ammo[0] = gunFor(startWi).mag;
      p.ammo[1] = 0;
    }
    p.slot = 0;
    p.reloadT = 0;
    p.shotCd = 0;
    p.swapT = 0;
    p.fire = false;
    p.firePrev = false;
    p.grenades = allowGrenades ? 2 : 0;
    p.vest = 0;
    p.helmet = 0;
    p.walls = wallStart;
    p.wallCd = 0;
    p.skillCd = 0;
    p.dashT = 0;
    p.shieldT = 0;
    p.boostT = 0;
  }

  void _respawnAll() {
    _resetZone();
    _spawnLoot();
    _syncBots(); // refill any bots that were culled mid-round
    for (final p in players) {
      _spawn(p);
    }
    bullets.clear();
    grenades.clear();
    walls.clear();
  }

  // =====================================================================
  //  SIMULATION
  // =====================================================================
  void _tick() {
    const dt = 1 / tickHz;
    if (matchOver || !started) {
      // WARM-UP / post-match: hold the world still so someone still sitting in
      // the lobby can't be gunned down before pressing START MISSION.
      _broadcastState();
      return;
    }
    _botThink(dt); // bots choose their movement/aim, then share the sim below

    for (final p in players) {
      if (p.skillCd > 0) p.skillCd -= dt;
      if (p.dashT > 0) p.dashT -= dt;
      if (p.shieldT > 0) p.shieldT -= dt;
      if (p.boostT > 0) p.boostT -= dt;
      if (p.swapT > 0) p.swapT -= dt;
      if (p.wallCd > 0) p.wallCd -= dt;
      if (p.reloadT > 0) {
        p.reloadT -= dt;
        if (p.reloadT <= 0) p.ammo[p.slot] = held(p).mag;
      }
      if (p.shotCd > 0) p.shotCd -= dt;
    }

    _moveAll(dt);
    _shooting(dt);
    _stepBullets(dt);
    _pickups();
    _stepGrenades(dt);
    for (final w in walls) {
      w.life -= dt;
    }
    walls.removeWhere((w) => w.life <= 0 || w.hp <= 0);
    _zone(dt);
    _airdrops(dt);
    _checkRoundEnd();
    _broadcastState();
  }

  void _moveAll(double dt) {
    for (final p in players) {
      if (!p.alive || !_inPlay(p)) continue;
      var mx = p.mx, my = p.my;
      final len = sqrt(mx * mx + my * my);
      if (len > 1) {
        mx /= len;
        my /= len;
      }
      final spd = playerSpeed *
          (p.dashT > 0 ? 1.8 : 1.0) *
          (p.isBot ? p.spdMul : 1.0); // bots never outrun a human
      final nx = (p.x + mx * spd * dt).clamp(20.0, world - 20);
      final ny = (p.y + my * spd * dt).clamp(20.0, world - 20);
      if (!_blocksPlayer(nx, ny)) {
        p.x = nx;
        p.y = ny;
      } else if (!_blocksPlayer(nx, p.y)) {
        p.x = nx;
      } else if (!_blocksPlayer(p.x, ny)) {
        p.y = ny;
      }
    }
  }

  /// Trigger handling with REAL guns: auto weapons keep firing while the stick
  /// is held, semi-autos fire once per pull, and running dry starts a reload.
  void _shooting(double dt) {
    for (final p in players) {
      if (!p.alive || !_inPlay(p)) continue;
      final g = held(p);
      final wantFire = p.fire && !matchOver;
      final trigger = g.auto ? wantFire : (wantFire && !p.firePrev);
      p.firePrev = wantFire;
      if (!trigger || p.shotCd > 0 || p.reloadT > 0 || p.swapT > 0) continue;
      if (p.ammo[p.slot] <= 0) {
        _startReload(p);
        continue;
      }
      p.ammo[p.slot]--;
      p.shotCd = g.rof * (p.boostT > 0 ? 0.45 : 1.0);
      final dmg = g.dmg * (p.isBot ? p.dmgMul : 1.0) * (p.boostT > 0 ? 1.4 : 1.0);
      for (var i = 0; i < g.pellets; i++) {
        final jitter = (_rng.nextDouble() * 2 - 1) * g.spread;
        final a = p.aim + jitter;
        bullets.add(Bullet(
          p.x + cos(a) * hitRadius,
          p.y + sin(a) * hitRadius,
          cos(a) * g.speed,
          sin(a) * g.speed,
          p.id,
          dmg,
          g.range,
        ));
      }
      // one event per trigger pull — clients draw the muzzle flash and fly
      // their own tracers with the same weapon stats
      _shots.add(
          [p.x.round(), p.y.round(), (p.aim * 100).round(), p.wi, p.id]);
      if (p.ammo[p.slot] <= 0) _startReload(p);
    }
  }

  /// Bullets move in sub-steps so a 1900 u/s sniper round can't skip straight
  /// through a body between two ticks.
  void _stepBullets(double dt) {
    for (final b in bullets) {
      final speed = sqrt(b.vx * b.vx + b.vy * b.vy);
      final total = speed * dt;
      final steps = (total / maxStep).ceil().clamp(1, 12);
      final sdt = dt / steps;
      var done = false;
      for (var s = 0; s < steps && !done; s++) {
        b.x += b.vx * sdt;
        b.y += b.vy * sdt;
        b.dist += speed * sdt;
        if (b.dist > b.range) {
          done = true;
          break;
        }
        final hitWall = _wallAt(b.x, b.y);
        if (hitWall != null) {
          hitWall.hp -= b.dmg; // deployed cover soaks the round
          b.dist = b.range + 1;
          done = true;
          break;
        }
        if (_blocksBullet(b.x, b.y)) {
          b.dist = b.range + 1;
          done = true;
          break;
        }
        for (final p in players) {
          if (!p.alive || !_inPlay(p) || p.id == b.owner) continue;
          final dx = p.x - b.x, dy = p.y - b.y;
          if (dx * dx + dy * dy < hitRadius * hitRadius) {
            b.dist = b.range + 1;
            done = true;
            if (p.shieldT > 0) break; // shield absorbs the hit
            _hurt(p, b.dmg, b.owner);
            break;
          }
        }
      }
    }
    bullets.removeWhere((b) =>
        b.dist > b.range || b.x < 0 || b.x > world || b.y < 0 || b.y > world);
  }

  void _hurt(Player p, double dmg, int by) {
    p.hp -= p.soak(dmg); // vest + helmet take their cut and wear down
    if (p.hp > 0) return;
    p.alive = false;
    final killer = players.firstWhere((k) => k.id == by, orElse: () => p);
    if (killer.id != p.id) killer.kills++;
    // spill what they were carrying
    for (final wi in p.slots) {
      if (wi > 0) {
        loot.add(Loot(_lootId++, p.x + _rng.nextDouble() * 30 - 15,
            p.y + _rng.nextDouble() * 30 - 15, 1, wi));
      }
    }
  }

  /// Walking over loot: medkits heal, and a gun is taken ONLY into an empty
  /// slot. Trading the gun in your hands needs an explicit PICK UP.
  void _pickups() {
    loot.removeWhere((l) {
      for (final p in players) {
        if (!p.alive || !_inPlay(p)) continue;
        final dx = p.x - l.x, dy = p.y - l.y;
        if (dx * dx + dy * dy > 34 * 34) continue;
        if (l.kind == 0) {
          if (p.hp >= 100) continue;
          p.hp = (p.hp + 40).clamp(0.0, 100.0);
          return true;
        }
        if (l.kind == 3) { // vest
          if (p.vest >= vestDurability * 0.9) continue;
          p.vest = vestDurability;
          return true;
        }
        if (l.kind == 4) { // helmet
          if (p.helmet >= helmetDurability * 0.9) continue;
          p.helmet = helmetDurability;
          return true;
        }
        if (l.kind == 5) { // shield wall charge
          if (p.walls >= wallMax) continue;
          p.walls++;
          return true;
        }
        if (l.kind == 6) { // grenade
          if (p.grenades >= 5) continue;
          p.grenades++;
          return true;
        }
        if (p.slots.contains(l.wi)) continue;
        final empty = p.slots.indexOf(-1);
        if (empty >= 0) {
          p.slots[empty] = l.wi;
          p.ammo[empty] = gunFor(l.wi).mag;
          if (p.isBot) _botEquipBest(p);
          return true;
        }
        // Spare slot only holds the backup pistol (index 0)? Stow the new gun
        // there. The gun in your hands is never touched without you asking.
        final spare = 1 - p.slot;
        if (p.slots[spare] == 0 && l.wi != 0) {
          p.slots[spare] = l.wi;
          p.ammo[spare] = gunFor(l.wi).mag;
          if (p.isBot) _botEquipBest(p);
          return true;
        }
        if (p.isBot) {
          // bots trade up on their own, humans decide for themselves
          final worst = gunFor(p.slots[0]).dmg / gunFor(p.slots[0]).rof <=
                  gunFor(p.slots[1]).dmg / gunFor(p.slots[1]).rof
              ? 0
              : 1;
          final cur = gunFor(p.slots[worst]);
          final cand = gunFor(l.wi);
          if (cand.dmg / cand.rof > cur.dmg / cur.rof * 1.15) {
            p.slots[worst] = l.wi;
            p.ammo[worst] = cand.mag;
            _botEquipBest(p);
            return true;
          }
        }
      }
      return false;
    });
  }

  void _botEquipBest(Player b) {
    if (b.slots[1] < 0) {
      b.slot = 0;
      return;
    }
    final a = gunFor(b.slots[0]);
    final c = gunFor(b.slots[1]);
    b.slot = (a.dmg / a.rof) >= (c.dmg / c.rof) ? 0 : 1;
  }

  void _stepGrenades(double dt) {
    for (final g in grenades) {
      g.x += g.vx * dt;
      g.y += g.vy * dt;
      g.vx *= 0.965; // drag so it lands
      g.vy *= 0.965;
      g.fuse -= dt;
      if (_blocksBullet(g.x, g.y)) {
        g.vx *= -0.4;
        g.vy *= -0.4;
      }
      if (g.fuse <= 0) {
        for (final p in players) {
          if (!p.alive || !_inPlay(p) || p.shieldT > 0) continue;
          final dx = p.x - g.x, dy = p.y - g.y;
          final d = sqrt(dx * dx + dy * dy);
          if (d < nadeRadius) {
            _hurt(p, nadeDamage * (1 - d / nadeRadius), g.owner);
          }
        }
        _booms.add([g.x.round(), g.y.round()]);
      }
    }
    grenades.removeWhere((g) => g.fuse <= 0);
  }

  void _zone(double dt) {
    _elapsed += dt;
    final t = ((_elapsed - _zoneWait) / _zoneShrink).clamp(0.0, 1.0);
    zr = world * 0.72 - (world * 0.72 - world * 0.14) * t;
    for (final p in players) {
      if (!p.alive || !_inPlay(p)) continue;
      final dx = p.x - zx, dy = p.y - zy;
      if (dx * dx + dy * dy > zr * zr) {
        p.hp -= _zoneDps * dt;
        if (p.hp <= 0) p.alive = false;
      }
    }
  }

  /// A marked crate with a top-tier gun lands mid-match — an excuse for
  /// everyone to stop hiding and have a fight.
  void _airdrops(double dt) {
    if (!allArms || guns.isEmpty || _drops >= 3) return;
    _nextDrop -= dt;
    if (_nextDrop > 0) return;
    _nextDrop = 55;
    _drops++;
    // best gun available, dropped inside the current circle
    var bestWi = guns.keys.first;
    var bestScore = 0.0;
    for (final g in guns.values) {
      final s = g.dmg * g.pellets / g.rof + g.range * 0.15;
      if (s > bestScore) {
        bestScore = s;
        bestWi = g.i;
      }
    }
    double x = zx, y = zy;
    for (var i = 0; i < 30; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final r = _rng.nextDouble() * zr * 0.7;
      final px = zx + cos(a) * r, py = zy + sin(a) * r;
      if (px < 80 || px > world - 80 || py < 80 || py > world - 80) continue;
      if (_blocksPlayer(px, py)) continue;
      x = px;
      y = py;
      break;
    }
    loot.add(Loot(_lootId++, x, y, 2, bestWi));
    broadcast({'type': 'drop', 'x': x.round(), 'y': y.round()});
  }

  // Round / match win logic: last one standing wins the round; first to
  // [rounds] round-wins takes the match.
  void _checkRoundEnd() {
    if (_roundEnding || !started) return;
    final inPlay = players.where(_inPlay).toList();
    if (inPlay.length < 2) return; // need at least two combatants
    final aliveList = inPlay.where((p) => p.alive).toList();
    if (aliveList.length > 1) return;
    _roundEnding = true;
    final winner = aliveList.isNotEmpty ? aliveList.first : null;
    if (winner != null) winner.roundWins++;
    broadcast({
      'type': 'round',
      'winner': winner?.id ?? 0,
      'name': winner?.name ?? '—',
      'round': roundNo,
      'rounds': rounds,
    });
    if (winner != null && winner.roundWins >= rounds) {
      matchOver = true;
      broadcast({'type': 'matchover', 'winner': winner.id, 'name': winner.name});
      Timer(const Duration(seconds: 8), () {
        matchOver = false;
        _roundEnding = false;
        roundNo = 1;
        for (final p in players) {
          p.roundWins = 0;
          p.kills = 0;
        }
        _respawnAll();
      });
    } else {
      Timer(const Duration(seconds: 3), () {
        roundNo++;
        _respawnAll();
        _roundEnding = false;
      });
    }
  }

  // =====================================================================
  //  SNAPSHOT
  // =====================================================================
  /// Players are packed as flat int arrays. Compared with the old
  /// object-per-player JSON (which also repeated every name, 30x a second)
  /// this is roughly a fifth of the bytes — which is most of what "the server
  /// lags" actually was on a free instance.
  ///
  /// Layout: [id, x, y, aim*100, hp, flags, kills, wins, wi, otherWi, nades,
  ///          cd, ammo]
  /// flags: 1 alive · 2 ready · 4 shield · 8 dash · 16 bot · 32 reloading
  void _broadcastState() {
    if (_rosterDirty) {
      _rosterDirty = false;
      broadcast(rosterMsg);
    }
    final ps = <List<int>>[];
    for (final p in players) {
      var flags = 0;
      if (p.alive) flags |= 1;
      if (p.ready) flags |= 2;
      if (p.shieldT > 0) flags |= 4;
      if (p.dashT > 0) flags |= 8;
      if (p.isBot) flags |= 16;
      if (p.reloadT > 0) flags |= 32;
      ps.add([
        p.id,
        p.x.round(),
        p.y.round(),
        (p.aim * 100).round(),
        p.hp.round().clamp(0, 100),
        flags,
        p.kills,
        p.roundWins,
        p.wi,
        p.otherWi,
        p.grenades,
        p.skillCd.clamp(0, 99).round(),
        p.ammo[p.slot],
        ((p.vest / vestDurability) * 100).round().clamp(0, 100),
        ((p.helmet / helmetDurability) * 100).round().clamp(0, 100),
        p.walls,
      ]);
    }
    final msg = jsonEncode({
      'type': 'state',
      'p': ps,
      'z': [zx.round(), zy.round(), zr.round()],
      'l': [for (final l in loot) l.packed],
      if (walls.isNotEmpty) 'w': [for (final w in walls) w.packed],
      'g': [for (final g in grenades) [g.x.round(), g.y.round()]],
      if (_shots.isNotEmpty) 'e': _shots,
      if (_booms.isNotEmpty) 'x': _booms,
      'r': roundNo,
      'rs': rounds,
    });
    _shots.clear();
    _booms.clear();
    broadcast(msg);
  }

  void broadcast(Object msg) {
    final s = msg is String ? msg : jsonEncode(msg);
    for (final p in players) {
      try {
        p.socket?.add(s); // bots have no socket
      } catch (_) {}
    }
  }

  void _send(Player p, Map<String, dynamic> m) {
    try {
      p.socket?.add(jsonEncode(m));
    } catch (_) {}
  }
}

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('Zone Royale server listening on port $port');
  print('Connect clients to  ws://<this-machine-ip>:$port');

  await for (final req in server) {
    if (WebSocketTransformer.isUpgradeRequest(req)) {
      final ws = await WebSocketTransformer.upgrade(req);
      // Snapshots are small and frequent — don't let Nagle hold them back.
      final id = _nextId++;
      final p = Player(
        id,
        ws,
        _rng.nextDouble() * worldSize,
        _rng.nextDouble() * worldSize,
        'Player$id',
      );
      ws.listen(
        (data) {
          try {
            final m = jsonDecode(data as String) as Map<dynamic, dynamic>;
            switch (m['type']) {
              case 'join':
                // First join binds the player to a room (by shared code) and
                // starts sending it snapshots. Later joins are ignored.
                if (p.roomRef == null) {
                  p.name = (m['name'] as String?)?.trim().isNotEmpty == true
                      ? (m['name'] as String).trim()
                      : p.name;
                  p.hero = (m['hero'] as num?)?.toInt() ?? 0;
                  p.baseWi = (m['startWi'] as num?)?.toInt() ?? p.baseWi;
                  // QUICK MATCH: server picks a public room with a free slot
                  // (or opens a new one). Custom rooms: join by shared code.
                  final room = m['quick'] == true
                      ? pickPublicRoom()
                      : roomFor((m['room'] as String?) ?? '');
                  // The rules belong to whoever opened the room. An empty room
                  // (or one that hasn't deployed yet, when you ARE the host)
                  // takes your settings, so changing a setting and re-joining
                  // actually does something.
                  final cfg = m['config'];
                  if (cfg is Map && room.humans == 0) {
                    room.hostId = p.id;
                    room.configure(cfg);
                    print('  room "${room.code}" configured: map=${room.map} '
                        'gun=${room.weapon} rounds=${room.rounds} '
                        'limit=${room.maxPlayers} bots=${room.fillBots}'
                        '/${room.botTarget}/d${room.botDifficulty} '
                        'med=${room.allowMedkits} nade=${room.allowGrenades} '
                        'skill=${room.allowSkills} guns=${room.guns.length}');
                  }
                  // enforce the host's PLAYER LIMIT (bots don't take slots)
                  if (room.humans >= room.maxPlayers) {
                    try {
                      ws.add(
                          jsonEncode({'type': 'full', 'max': room.maxPlayers}));
                    } catch (_) {}
                    if (room.humans == 0) rooms.remove(room.code);
                    ws.close();
                    return;
                  }
                  p.roomRef = room;
                  room._spawn(p); // place inside the (possibly resized) arena
                  room.add(p);
                }
                break;
              case 'cfg': // host re-applies the room rules from the lobby
                final room = p.roomRef;
                final cfg = m['config'];
                if (room != null &&
                    cfg is Map &&
                    p.id == room.hostId &&
                    !room.started) {
                  room.configure(cfg);
                  room.broadcast(room.cfgMsg);
                  print('  room "${room.code}" re-configured by host '
                      '(map=${room.map} gun=${room.weapon})');
                }
                break;
              case 'ready': // START MISSION — the player joins the fight
                final room = p.roomRef;
                if (room != null && !p.ready) {
                  final first = !room.started;
                  p.ready = true;
                  if (first) {
                    // first deployment: fresh zone, fresh loot, spawn the bots
                    room._respawnAll();
                  } else {
                    room._spawn(p); // drop into the running match
                  }
                  room.broadcast(room.cfgMsg);
                }
                break;
              case 'ping': // echo straight back so the client can time the RTT
                try {
                  ws.add(jsonEncode({'type': 'pong', 't': m['t']}));
                } catch (_) {}
                break;
              case 'input':
                p.roomRef?.onInput(p, m);
                break;
            }
          } catch (_) {}
        },
        onDone: () => _leave(p),
        onError: (_) => _leave(p),
        cancelOnError: true,
      );
    } else {
      req.response
        ..statusCode = HttpStatus.ok
        ..write('Zone Royale server OK')
        ..close();
    }
  }
}
