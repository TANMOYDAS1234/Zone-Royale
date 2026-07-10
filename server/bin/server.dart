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
const int tickHz = 20;
const double playerSpeed = 230;
const double bulletSpeed = 900;
const double bulletRange = 620;
const double hitRadius = 24;
const double bulletDamage = 18;

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
  String name;
  Room? roomRef;
  Player(this.id, this.socket, this.x, this.y, this.name);
}

class Bullet {
  double x, y, vx, vy, dist = 0;
  final int owner;
  Bullet(this.x, this.y, this.vx, this.vy, this.owner);
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
  }

  void _resetZone() {
    zx = world / 2;
    zy = world / 2;
    zr = world * 0.72;
    _elapsed = 0;
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
    maxPlayers = (cfg['maxPlayers'] as num?)?.toInt() ?? maxPlayers;
    rounds = ((cfg['rounds'] as num?)?.toInt() ?? rounds).clamp(1, 9);
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
        cos(p.aim) * bSpeed,
        sin(p.aim) * bSpeed,
        p.id,
      ));
    }
    p.fire = f;
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
  }

  void _respawnAll() {
    _resetZone();
    for (final p in players) {
      _spawn(p);
    }
    bullets.clear();
  }

  void _tick() {
    const dt = 1 / tickHz;
    if (matchOver) {
      broadcast(_snapshot());
      return;
    }
    // movement (with obstacle sliding collision)
    for (final p in players) {
      if (!p.alive) continue;
      var mx = p.mx, my = p.my;
      final len = sqrt(mx * mx + my * my);
      if (len > 1) {
        mx /= len;
        my /= len;
      }
      final nx = (p.x + mx * playerSpeed * dt).clamp(20.0, world - 20);
      final ny = (p.y + my * playerSpeed * dt).clamp(20.0, world - 20);
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
      b.dist += bSpeed * dt;
      if (_blocksBullet(b.x, b.y)) {
        b.dist = bRange + 1;
        continue;
      }
      for (final p in players) {
        if (!p.alive || p.id == b.owner) continue;
        final dx = p.x - b.x, dy = p.y - b.y;
        if (dx * dx + dy * dy < hitRadius * hitRadius) {
          p.hp -= dmg;
          b.dist = bRange + 1; // consume the bullet
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
        b.dist > bRange || b.x < 0 || b.x > world || b.y < 0 || b.y > world);

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
              'name': p.name,
            }
        ],
        'bullets': [
          for (final b in bullets) {'x': b.x.round(), 'y': b.y.round()}
        ],
        'zone': {'x': zx.round(), 'y': zy.round(), 'r': zr.round()},
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
                  final room = roomFor((m['room'] as String?) ?? '');
                  // The host (first player to create the room) sets the rules.
                  final cfg = m['config'];
                  if (cfg is Map) room.configure(cfg);
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
