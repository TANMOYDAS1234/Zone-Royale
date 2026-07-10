// Zone Royale — authoritative multiplayer arena server (prototype).
//
// Pure dart:io WebSocket server. Players connect, send their inputs, and the
// server runs the ONE true simulation (movement + bullets + hits + kills) and
// broadcasts a world snapshot to everyone at 20 Hz. This is the piece that lets
// real people fight each other — the Flutter client connects to it in a
// "networked" match mode (see README.md for the integration plan).
//
// Run:   dart run server/bin/server.dart          (listens on :8080)
// Then point the phone at ws://<your-PC-LAN-IP>:8080 on the same Wi-Fi,
// or deploy to a cloud VM for internet play.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const double worldSize = 3200;
const int tickHz = 30; // higher tick = smoother motion for clients
const double playerSpeed = 250;
const double bulletSpeed = 900;
const double bulletRange = 620;
const double hitRadius = 24;
const double bulletDamage = 18;
const double nadeSpeed = 560;
const double nadeFuse = 1.1; // seconds of flight before it detonates
const double nadeRadius = 150; // blast radius
const double nadeDamage = 65; // damage at the centre (falls off with distance)
const double skillCooldown = 12;

int _nextId = 1;
final Random _rng = Random();

// Rooms keyed by code ("PUBLIC" when none given) — this is what makes BGMI/
// Free-Fire-style custom rooms work: friends who share a code land together.
final Map<String, Room> rooms = {};
Room roomFor(String code) {
  final key = code.trim().isEmpty ? 'PUBLIC' : code.trim().toUpperCase();
  return rooms.putIfAbsent(key, () => Room(key));
}

/// Matchmaking for QUICK MATCH: reuse the first public room with a free slot,
/// otherwise open a fresh one. Nobody "hosts" — quick rooms run the standard
/// ruleset the client sends, which is identical for every player.
Room pickPublicRoom() {
  for (final r in rooms.values) {
    if (!r.code.startsWith('PUBLIC')) continue;
    if (r.humans < r.maxPlayers) return r;
  }
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
  // bot brain + difficulty profile (bots are deliberately weaker than a human)
  double fireCd = 0;
  double wanderT = 0;
  double wx = 0, wy = 0;
  double aimErr = 0.2; // radians of aim jitter
  double fireMin = 0.8, fireMax = 1.4; // seconds between shots
  double vision = 520; // how far a bot can see you
  double spdMul = 0.85; // fraction of the human run speed
  double dmgMul = 0.5; // fraction of the weapon's damage
  double nadeChance = 0, skillChance = 0;
  // current weapon (loot can swap it)
  int wi = 5;
  double dmg = bulletDamage;
  double bSpeed = bulletSpeed;
  double bRange = bulletRange;
  // grenades + hero skill
  int grenades = 2;
  int hero = 0; // index into the client's hero list
  int baseWi = 5; // the player's own loadout weapon (used in ALL_ARMS rooms)
  double skillCd = 0; // seconds until the skill is ready again
  double dashT = 0; // speed-burst timer
  double shieldT = 0; // damage-immunity timer
  double boostT = 0; // damage-boost timer
  String name;
  Room? roomRef;
  Player(this.id, this.socket, this.x, this.y, this.name);
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

// A ground pickup: weapon crate ('w') or medkit ('m').
int _lootId = 1;

class Loot {
  final int id;
  final double x, y;
  final String kind; // 'w' | 'm'
  final int wi; // weapon index (weapon crates)
  final double dmg, speed, range;
  Loot(this.id, this.x, this.y, this.kind, this.wi, this.dmg, this.speed,
      this.range);
  Map<String, dynamic> get json =>
      {'x': x.round(), 'y': y.round(), 'k': kind, 'wi': wi};
}

// A rectangular obstacle (building/cover). x,y is the centre.
class Obs {
  final double x, y, hw, hh;
  Obs(this.x, this.y, this.hw, this.hh);
  Map<String, int> get json =>
      {'x': x.round(), 'y': y.round(), 'w': (hw * 2).round(), 'h': (hh * 2).round()};
}

class Room {
  final String code;
  final List<Player> players = [];
  final List<Bullet> bullets = [];
  Timer? _loop;
  Room(this.code);

  // ---- host-configurable match settings (BGMI-style custom room) ----
  bool configured = false;
  double world = worldSize;
  double dmg = bulletDamage;
  double bSpeed = bulletSpeed;
  double bRange = bulletRange;
  String map = 'RANDOM';
  String weapon = 'RIFLE';
  int maxPlayers = 10;
  int rounds = 1; // round wins needed to win the match
  int roundNo = 1;
  bool _roundEnding = false;
  bool matchOver = false;

  // ---- weapons + loot + grenades ----
  List<Map<String, dynamic>> weaponTable = []; // host sends the full gun table
  int startWi = 5;
  bool allArms = true; // when true each player keeps their own loadout weapon
  // host-controlled rules
  bool allowMedkits = true;
  bool allowGrenades = true;
  bool allowSkills = true;
  bool fillBots = true; // top the room up with bots so it's always playable
  int botTarget = 8; // total bodies (humans + bots) to aim for
  int botDifficulty = 1; // 0 easy · 1 normal · 2 hard — all weaker than a human

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

  // ---- map cover + shrinking gas zone (parity with a normal match) ----
  final List<Obs> obstacles = [];
  double zx = worldSize / 2, zy = worldSize / 2;
  double zr = worldSize * 0.72; // current safe radius
  double _elapsed = 0; // seconds into the round
  static const double _zoneWait = 14; // grace before the zone shrinks
  static const double _zoneShrink = 95; // seconds to reach the final ring
  static const double _zoneDps = 7; // damage/second outside the safe circle

  /// The host's MAP choice actually reshapes the arena: how many pieces of
  /// cover there are and how big they get.
  void _genMap() {
    obstacles.clear();
    final base = (world * world / 340000).round();
    double density, minHalf, maxHalf;
    switch (map.toUpperCase()) {
      case 'URBAN BUILDINGS':
      case 'URBAN':
        density = 1.15; // dense blocks
        minHalf = 40;
        maxHalf = 100;
        break;
      case 'FOREST':
        density = 1.8; // lots of small trees
        minHalf = 16;
        maxHalf = 34;
        break;
      case 'COMPOUND':
        density = 1.35; // long walls / rooms
        minHalf = 26;
        maxHalf = 120;
        break;
      case 'BADLANDS':
        density = 0.65; // sparse, chunky boulders
        minHalf = 55;
        maxHalf = 120;
        break;
      default: // RANDOM
        density = 1.0;
        minHalf = 30;
        maxHalf = 85;
    }
    final n = (base * density).round().clamp(6, 60);
    var tries = 0;
    while (obstacles.length < n && tries < n * 6) {
      tries++;
      final hw = minHalf + _rng.nextDouble() * (maxHalf - minHalf);
      final hh = minHalf + _rng.nextDouble() * (maxHalf - minHalf);
      final x = 60 + _rng.nextDouble() * (world - 120);
      final y = 60 + _rng.nextDouble() * (world - 120);
      // keep the exact centre a bit clearer
      if ((x - world / 2).abs() < 120 && (y - world / 2).abs() < 120) continue;
      obstacles.add(Obs(x, y, hw, hh));
    }
    _resetZone();
    _spawnLoot();
  }

  void _resetZone() {
    zx = world / 2;
    zy = world / 2;
    zr = world * 0.72;
    _elapsed = 0;
  }

  // ---- bots: keep the room populated so a match is always playable ----
  static const _botNames = [
    'VIPER', 'GHOST', 'RAVEN', 'HAWK', 'WOLF', 'ONYX', 'ECHO', 'NOVA',
    'BLAZE', 'FROST', 'DELTA', 'ZERO', 'TITAN', 'ROGUE', 'STORM', 'ATLAS',
  ];

  /// Bots are tuned to be clearly *weaker* than a human: less damage, slower
  /// fire, shakier aim, shorter sight, slower legs. Difficulty scales those,
  /// and each bot gets a little variance so they don't feel cloned.
  void _applyBotTier(Player b) {
    switch (botDifficulty) {
      case 0: // easy
        b.aimErr = 0.30;
        b.fireMin = 1.0;
        b.fireMax = 1.8;
        b.vision = 460;
        b.spdMul = 0.78;
        b.dmgMul = 0.40;
        b.nadeChance = 0;
        b.skillChance = 0;
        break;
      case 2: // hard
        b.aimErr = 0.12;
        b.fireMin = 0.55;
        b.fireMax = 1.0;
        b.vision = 680;
        b.spdMul = 0.95;
        b.dmgMul = 0.75;
        b.nadeChance = 0.30;
        b.skillChance = 0.35;
        break;
      default: // normal
        b.aimErr = 0.20;
        b.fireMin = 0.75;
        b.fireMax = 1.35;
        b.vision = 560;
        b.spdMul = 0.86;
        b.dmgMul = 0.55;
        b.nadeChance = 0.12;
        b.skillChance = 0.15;
    }
    // per-bot variance (±10%) so a squad isn't a hive mind
    final v = 0.9 + _rng.nextDouble() * 0.2;
    b.dmgMul *= v;
    b.spdMul = (b.spdMul * v).clamp(0.6, 0.98); // never outrun a human
    b.aimErr /= v;
  }

  void _addBot() {
    final id = _nextId++;
    final b = Player(id, null, 0, 0, 'BOT ${_botNames[id % _botNames.length]}');
    b.ready = true; // bots are always in the fight
    b.hero = _rng.nextInt(5);
    b.baseWi = weaponTable.isEmpty
        ? startWi
        : weaponTable[_rng.nextInt(weaponTable.length)]['i'] as int;
    _applyBotTier(b);
    b.roomRef = this;
    players.add(b);
    _spawn(b);
  }

  /// Bots fill the gap between the human count and [botTarget]; they step aside
  /// as real players arrive.
  void _syncBots() {
    // no bots while the room is still warming up in the lobby
    if (!fillBots || !started) {
      players.removeWhere((p) => p.isBot);
      return;
    }
    if (humans == 0) {
      players.removeWhere((p) => p.isBot); // nobody to play against
      return;
    }
    final want = (botTarget - humans).clamp(0, botTarget);
    var have = botCount;
    while (have < want) {
      _addBot();
      have++;
    }
    while (have > want) {
      final idx = players.indexWhere((p) => p.isBot && !p.alive);
      players.removeAt(idx >= 0 ? idx : players.indexWhere((p) => p.isBot));
      have--;
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
      if (target != null && dist < b.vision) {
        final dx = target.x - b.x, dy = target.y - b.y;
        // shaky aim — the main reason bots lose fights to a human
        b.aim = atan2(dy, dx) + (_rng.nextDouble() - 0.5) * b.aimErr * 2;
        // keep a fighting distance
        final move = dist > 300 ? 1.0 : (dist < 130 ? -1.0 : 0.0);
        b.mx = (dx / dist) * move;
        b.my = (dy / dist) * move;

        if (b.fireCd <= 0 && !matchOver) {
          b.fireCd = b.fireMin + _rng.nextDouble() * (b.fireMax - b.fireMin);
          final roll = _rng.nextDouble();
          if (allowGrenades && b.grenades > 0 && dist > 220 && dist < 520 &&
              roll < b.nadeChance) {
            b.grenades--;
            grenades.add(Grenade(
              b.x + cos(b.aim) * hitRadius,
              b.y + sin(b.aim) * hitRadius,
              cos(b.aim) * nadeSpeed,
              sin(b.aim) * nadeSpeed,
              nadeFuse,
              b.id,
            ));
          } else if (allowSkills && b.skillCd <= 0 && roll < b.skillChance) {
            _activateSkill(b); // dash in, shield up, etc.
          } else if (dist < b.bRange) {
            bullets.add(Bullet(
              b.x + cos(b.aim) * hitRadius,
              b.y + sin(b.aim) * hitRadius,
              cos(b.aim) * b.bSpeed,
              sin(b.aim) * b.bSpeed,
              b.id,
              b.dmg * b.dmgMul, // bots hit softer than a human
              b.bRange,
            ));
          }
        }
        continue;
      }

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
    final canDropGuns = allArms && weaponTable.isNotEmpty;
    if (!canDropGuns && !allowMedkits) return; // nothing legal to drop
    final k = (obstacles.length * 0.7).round().clamp(6, 24);
    for (var i = 0; i < k; i++) {
      double x = 0, y = 0;
      for (var t = 0; t < 20; t++) {
        x = 60 + _rng.nextDouble() * (world - 120);
        y = 60 + _rng.nextDouble() * (world - 120);
        if (!_blocksPlayer(x, y)) break;
      }
      final wantMed =
          allowMedkits && (!canDropGuns || _rng.nextDouble() < 0.35);
      if (wantMed) {
        loot.add(Loot(_lootId++, x, y, 'm', -1, 0, 0, 0)); // medkit
      } else if (canDropGuns) {
        final w = weaponTable[_rng.nextInt(weaponTable.length)];
        loot.add(Loot(_lootId++, x, y, 'w', w['i'] as int, w['dmg'] as double,
            w['speed'] as double, w['range'] as double));
      }
    }
  }

  bool _blocksPlayer(double x, double y) {
    for (final o in obstacles) {
      if ((x - o.x).abs() < o.hw + 20 && (y - o.y).abs() < o.hh + 20) return true;
    }
    return false;
  }

  bool _blocksBullet(double x, double y) {
    for (final o in obstacles) {
      if ((x - o.x).abs() < o.hw && (y - o.y).abs() < o.hh) return true;
    }
    return false;
  }

  /// Applies the host's rules. Called only when the first human enters an
  /// empty room, so a late joiner can never overwrite the host's settings —
  /// but a host who leaves and comes back with new settings gets them applied.
  void configure(Map cfg) {
    world = (cfg['world'] as num?)?.toDouble() ?? world;
    dmg = (cfg['dmg'] as num?)?.toDouble() ?? dmg;
    bSpeed = (cfg['bulletSpeed'] as num?)?.toDouble() ?? bSpeed;
    bRange = (cfg['bulletRange'] as num?)?.toDouble() ?? bRange;
    map = (cfg['map'] as String?) ?? map;
    weapon = (cfg['weapon'] as String?) ?? weapon;
    allArms = weapon.toUpperCase() == 'ALL_ARMS';
    maxPlayers = (cfg['maxPlayers'] as num?)?.toInt() ?? maxPlayers;
    rounds = ((cfg['rounds'] as num?)?.toInt() ?? rounds).clamp(1, 9);
    startWi = (cfg['startWi'] as num?)?.toInt() ?? startWi;
    allowMedkits = cfg['medkit'] != false;
    allowGrenades = cfg['grenades'] != false;
    allowSkills = cfg['skills'] != false;
    fillBots = cfg['bots'] != false;
    botTarget = ((cfg['botTarget'] as num?)?.toInt() ?? botTarget).clamp(2, 30);
    botDifficulty =
        ((cfg['botDifficulty'] as num?)?.toInt() ?? botDifficulty).clamp(0, 2);
    // the arena depends on `map` and `world`, so rebuild it with the new rules
    obstacles.clear();
    loot.clear();
    final wl = cfg['weapons'];
    if (wl is List) {
      weaponTable = [
        for (final w in wl)
          {
            'i': (w['i'] as num).toInt(),
            'dmg': (w['dmg'] as num).toDouble(),
            'speed': (w['speed'] as num).toDouble(),
            'range': (w['range'] as num).toDouble(),
          }
      ];
    }
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
        'host': players.isNotEmpty ? players.first.id : 0,
        'medkit': allowMedkits,
        'grenades': allowGrenades,
        'skills': allowSkills,
        'bots': fillBots,
        'botTarget': botTarget,
        'botDifficulty': botDifficulty,
        'started': started,
        'obstacles': [for (final o in obstacles) o.json],
      };

  void add(Player p) {
    players.add(p);
    if (obstacles.isEmpty) _genMap(); // build the arena once, on first join
    _send(p, {'type': 'welcome', 'id': p.id, 'world': world});
    _syncBots(); // top up (or free up) bot slots for the new human
    broadcast(cfgMsg); // everyone learns the room rules + map
    _loop ??= Timer.periodic(
        Duration(milliseconds: 1000 ~/ tickHz), (_) => _tick());
    print('+ player ${p.id} -> room "$code" '
        '($humans human/$botCount bot, map=$map, gun=$weapon, rounds=$rounds)');
  }

  void remove(Player p) {
    players.remove(p);
    print('- player ${p.id} ($humans human online)');
    if (humans == 0) {
      // nobody real left — stop the sim and drop the bots
      _loop?.cancel();
      _loop = null;
      players.removeWhere((q) => q.isBot);
      bullets.clear();
      grenades.clear();
    } else {
      _syncBots();
    }
  }

  void dispose() {
    _loop?.cancel();
    _loop = null;
    bullets.clear();
  }

  void onInput(Player p, Map<dynamic, dynamic> m) {
    p.mx = (m['mx'] as num?)?.toDouble() ?? 0;
    p.my = (m['my'] as num?)?.toDouble() ?? 0;
    p.aim = (m['aim'] as num?)?.toDouble() ?? p.aim;
    final f = m['fire'] == true;
    if (f && !p.fire && p.alive && !matchOver) {
      bullets.add(Bullet(
        p.x + cos(p.aim) * hitRadius,
        p.y + sin(p.aim) * hitRadius,
        cos(p.aim) * p.bSpeed,
        sin(p.aim) * p.bSpeed,
        p.id,
        p.dmg * (p.boostT > 0 ? 1.6 : 1.0), // frenzy damage boost
        p.bRange,
      ));
    }
    p.fire = f;

    // throw a grenade (only if the room allows them)
    if (allowGrenades && m['nade'] == true && p.alive && !matchOver && p.grenades > 0) {
      p.grenades--;
      grenades.add(Grenade(
        p.x + cos(p.aim) * hitRadius,
        p.y + sin(p.aim) * hitRadius,
        cos(p.aim) * nadeSpeed,
        sin(p.aim) * nadeSpeed,
        nadeFuse,
        p.id,
      ));
    }
    // activate the hero skill (only if the room allows skills)
    if (allowSkills && m['skill'] == true && p.alive && !matchOver && p.skillCd <= 0) {
      _activateSkill(p);
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
    for (var i = 0; i < 30; i++) {
      p.x = 40 + _rng.nextDouble() * (world - 80);
      p.y = 40 + _rng.nextDouble() * (world - 80);
      if (!_blocksPlayer(p.x, p.y)) break;
    }
    p.hp = 100;
    p.alive = true;
    // ALL_ARMS: each player keeps their own loadout gun (defaults to SMG);
    // otherwise everyone uses the host's forced weapon. Loot can swap it.
    if (allArms) {
      p.wi = p.baseWi;
      final s = _statsFor(p.baseWi);
      p.dmg = s[0];
      p.bSpeed = s[1];
      p.bRange = s[2];
    } else {
      p.wi = startWi;
      p.dmg = dmg;
      p.bSpeed = bSpeed;
      p.bRange = bRange;
    }
    p.grenades = allowGrenades ? 2 : 0;
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
  }

  // weapon stats for an index from the host's table (fallback = room default)
  List<double> _statsFor(int wi) {
    for (final w in weaponTable) {
      if (w['i'] == wi) {
        return [w['dmg'] as double, w['speed'] as double, w['range'] as double];
      }
    }
    return [dmg, bSpeed, bRange];
  }

  void _tick() {
    const dt = 1 / tickHz;
    if (matchOver) {
      broadcast(_snapshot());
      return;
    }
    // WARM-UP: nobody has deployed yet. Hold the world still so a player still
    // sitting in the lobby can't be gunned down before pressing START MISSION.
    if (!started) {
      broadcast(_snapshot());
      return;
    }
    _botThink(dt); // bots choose their movement/aim, then share the sim below

    // tick down skill timers
    for (final p in players) {
      if (p.skillCd > 0) p.skillCd -= dt;
      if (p.dashT > 0) p.dashT -= dt;
      if (p.shieldT > 0) p.shieldT -= dt;
      if (p.boostT > 0) p.boostT -= dt;
    }
    // movement (with obstacle sliding collision; dash gives a speed burst)
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
    // bullets + hit detection (bullets stop at cover)
    for (final b in bullets) {
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.dist += sqrt(b.vx * b.vx + b.vy * b.vy) * dt;
      if (_blocksBullet(b.x, b.y)) {
        b.dist = b.range + 1;
        continue;
      }
      for (final p in players) {
        if (!p.alive || !_inPlay(p) || p.id == b.owner) continue;
        final dx = p.x - b.x, dy = p.y - b.y;
        if (dx * dx + dy * dy < hitRadius * hitRadius) {
          b.dist = b.range + 1; // consume the bullet
          if (p.shieldT > 0) break; // shield absorbs the hit
          p.hp -= b.dmg;
          if (p.hp <= 0) {
            p.alive = false;
            final killer =
                players.firstWhere((k) => k.id == b.owner, orElse: () => p);
            if (killer.id != p.id) killer.kills++;
          }
          break;
        }
      }
    }
    bullets.removeWhere((b) =>
        b.dist > b.range || b.x < 0 || b.x > world || b.y < 0 || b.y > world);

    // loot pickups: walk over a crate to swap weapon, or a medkit to heal
    loot.removeWhere((l) {
      for (final p in players) {
        if (!p.alive || !_inPlay(p)) continue;
        final dx = p.x - l.x, dy = p.y - l.y;
        if (dx * dx + dy * dy < 34 * 34) {
          if (l.kind == 'm') {
            p.hp = (p.hp + 40).clamp(0.0, 100.0);
          } else {
            p.wi = l.wi;
            p.dmg = l.dmg;
            p.bSpeed = l.speed;
            p.bRange = l.range;
          }
          return true;
        }
      }
      return false;
    });

    // grenades: fly, then detonate with radial (falloff) damage
    for (final g in grenades) {
      g.x += g.vx * dt;
      g.y += g.vy * dt;
      g.vx *= 0.965; // drag so it lands
      g.vy *= 0.965;
      g.fuse -= dt;
      if (_blocksBullet(g.x, g.y)) g.fuse = min(g.fuse, 0.02); // bump = detonate
      if (g.fuse <= 0) {
        for (final p in players) {
          if (!p.alive || !_inPlay(p) || p.shieldT > 0) continue;
          final dx = p.x - g.x, dy = p.y - g.y;
          final d = sqrt(dx * dx + dy * dy);
          if (d < nadeRadius) {
            p.hp -= nadeDamage * (1 - d / nadeRadius);
            if (p.hp <= 0) {
              p.alive = false;
              final killer =
                  players.firstWhere((k) => k.id == g.owner, orElse: () => p);
              if (killer.id != p.id) killer.kills++;
            }
          }
        }
        broadcast({'type': 'boom', 'x': g.x.round(), 'y': g.y.round()});
      }
    }
    grenades.removeWhere((g) => g.fuse <= 0);

    // shrinking gas zone: after a grace period the safe circle closes; anyone
    // caught outside it takes damage until they get back in.
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

    _checkRoundEnd();
    broadcast(_snapshot());
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

  String _snapshot() => jsonEncode({
        'type': 'state',
        'players': [
          for (final p in players)
            {
              'id': p.id,
              'x': p.x.round(),
              'y': p.y.round(),
              'aim': double.parse(p.aim.toStringAsFixed(2)),
              'hp': p.hp.round(),
              'alive': p.alive,
              'kills': p.kills,
              'wins': p.roundWins,
              'wi': p.wi,
              'nades': p.grenades,
              'sh': p.shieldT > 0,
              'dsh': p.dashT > 0,
              'cd': p.skillCd.clamp(0, 99).round(),
              'bot': p.isBot,
              'rdy': p.ready,
              'name': p.name,
            }
        ],
        // velocity travels with projectiles so the client can extrapolate them
        // smoothly between ticks instead of stepping 30x/second
        'bullets': [
          for (final b in bullets)
            {
              'x': b.x.round(),
              'y': b.y.round(),
              'vx': b.vx.round(),
              'vy': b.vy.round()
            }
        ],
        'nades': [
          for (final g in grenades)
            {
              'x': g.x.round(),
              'y': g.y.round(),
              'vx': g.vx.round(),
              'vy': g.vy.round()
            }
        ],
        'loot': [for (final l in loot) l.json],
        'zone': {'x': zx.round(), 'y': zy.round(), 'r': zr.round()},
        'round': roundNo,
        'rounds': rounds,
      });

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
                  // The host is whoever enters an empty room; only they set the
                  // rules, so a late joiner can't overwrite them. Reconnecting
                  // into an empty room re-applies your latest settings.
                  final cfg = m['config'];
                  if (cfg is Map && room.humans == 0) {
                    room.configure(cfg);
                    print('  room "${room.code}" configured: map=${room.map} '
                        'gun=${room.weapon} rounds=${room.rounds} '
                        'limit=${room.maxPlayers} bots=${room.fillBots}'
                        '/${room.botTarget}/d${room.botDifficulty} '
                        'med=${room.allowMedkits} nade=${room.allowGrenades} '
                        'skill=${room.allowSkills}');
                  }
                  // enforce the host's PLAYER LIMIT (bots don't take slots)
                  if (room.humans >= room.maxPlayers) {
                    try {
                      ws.add(jsonEncode(
                          {'type': 'full', 'max': room.maxPlayers}));
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
