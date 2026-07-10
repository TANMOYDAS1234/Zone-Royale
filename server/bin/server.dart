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

void _leave(Player p) {
  final room = p.roomRef;
  if (room == null) return;
  room.remove(p);
  if (room.players.isEmpty) {
    room.dispose();
    rooms.remove(room.code);
    print('- room "${room.code}" closed (empty)');
  }
}

class Player {
  final int id;
  final WebSocket socket;
  double x, y;
  double aim = 0, hp = 100;
  double mx = 0, my = 0; // movement input (-1..1)
  bool fire = false, alive = true;
  int kills = 0;
  int roundWins = 0;
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

  void _genMap() {
    obstacles.clear();
    final n = (world * world / 340000).round().clamp(6, 40);
    var tries = 0;
    while (obstacles.length < n && tries < n * 6) {
      tries++;
      final hw = 30 + _rng.nextDouble() * 55;
      final hh = 30 + _rng.nextDouble() * 55;
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

  void _spawnLoot() {
    loot.clear();
    final k = (obstacles.length * 0.7).round().clamp(6, 24);
    for (var i = 0; i < k; i++) {
      double x = 0, y = 0;
      for (var t = 0; t < 20; t++) {
        x = 60 + _rng.nextDouble() * (world - 120);
        y = 60 + _rng.nextDouble() * (world - 120);
        if (!_blocksPlayer(x, y)) break;
      }
      final wantMed = allowMedkits && (weaponTable.isEmpty || _rng.nextDouble() < 0.35);
      if (wantMed) {
        loot.add(Loot(_lootId++, x, y, 'm', -1, 0, 0, 0)); // medkit
      } else if (weaponTable.isEmpty) {
        continue; // nothing to drop
      } else {
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

  // First player to create the room is the host and sets the rules.
  void configure(Map cfg) {
    if (configured) return;
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
        'obstacles': [for (final o in obstacles) o.json],
      };

  void add(Player p) {
    players.add(p);
    if (obstacles.isEmpty) _genMap(); // build the arena once, on first join
    _send(p, {'type': 'welcome', 'id': p.id, 'world': world});
    broadcast(cfgMsg); // everyone learns the room rules + map
    _loop ??= Timer.periodic(
        Duration(milliseconds: 1000 ~/ tickHz), (_) => _tick());
    print('+ player ${p.id} -> room "$code" '
        '(${players.length}/$maxPlayers, map=$map, gun=$weapon, rounds=$rounds)');
  }

  void remove(Player p) {
    players.remove(p);
    print('- player ${p.id} (${players.length} online)');
    if (players.isEmpty) {
      _loop?.cancel();
      _loop = null;
      bullets.clear();
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
    // tick down skill timers
    for (final p in players) {
      if (p.skillCd > 0) p.skillCd -= dt;
      if (p.dashT > 0) p.dashT -= dt;
      if (p.shieldT > 0) p.shieldT -= dt;
      if (p.boostT > 0) p.boostT -= dt;
    }
    // movement (with obstacle sliding collision; dash gives a speed burst)
    for (final p in players) {
      if (!p.alive) continue;
      var mx = p.mx, my = p.my;
      final len = sqrt(mx * mx + my * my);
      if (len > 1) {
        mx /= len;
        my /= len;
      }
      final spd = playerSpeed * (p.dashT > 0 ? 1.8 : 1.0);
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
        if (!p.alive || p.id == b.owner) continue;
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
        if (!p.alive) continue;
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
          if (!p.alive || p.shieldT > 0) continue;
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
      if (!p.alive) continue;
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
    if (_roundEnding || players.length < 2) return;
    final aliveList = players.where((p) => p.alive).toList();
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
              'name': p.name,
            }
        ],
        'bullets': [
          for (final b in bullets) {'x': b.x.round(), 'y': b.y.round()}
        ],
        'nades': [
          for (final g in grenades) {'x': g.x.round(), 'y': g.y.round()}
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
        p.socket.add(s);
      } catch (_) {}
    }
  }

  void _send(Player p, Map<String, dynamic> m) {
    try {
      p.socket.add(jsonEncode(m));
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
                  final room = roomFor((m['room'] as String?) ?? '');
                  // The host (first player to create the room) sets the rules.
                  final cfg = m['config'];
                  if (cfg is Map) room.configure(cfg);
                  // enforce the host's PLAYER LIMIT
                  if (room.players.length >= room.maxPlayers) {
                    try {
                      ws.add(jsonEncode(
                          {'type': 'full', 'max': room.maxPlayers}));
                    } catch (_) {}
                    if (room.players.isEmpty) rooms.remove(room.code);
                    ws.close();
                    return;
                  }
                  p.roomRef = room;
                  room._spawn(p); // place inside the (possibly resized) arena
                  room.add(p);
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
