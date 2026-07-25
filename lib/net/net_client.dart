import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// How far behind the newest snapshot we render other players, in ms. Holding a
/// small buffer and interpolating *between* two known positions is what makes
/// online movement look smooth: without it every dropped or late packet shows
/// up as a stutter. ~90ms costs almost nothing you can feel and absorbs normal
/// mobile jitter.
const int kInterpDelayMs = 90;

/// One player as seen in a server snapshot. The wire format is a flat int
/// array (see the server's `_broadcastState`) — names arrive separately in the
/// roster message, so they aren't repeated 30 times a second.
class NetPlayer {
  final int id;
  final double x, y, aim;
  final int hp, kills, wins, wi, wi2, nades, cd, ammo;
  final int vest, helmet, walls; // armour % and shield-wall charges
  final bool alive, ready, shield, dash, bot, reloading;
  final String name;
  const NetPlayer(
      {required this.id,
      required this.x,
      required this.y,
      required this.aim,
      required this.hp,
      required this.kills,
      required this.wins,
      required this.wi,
      required this.wi2,
      required this.nades,
      required this.cd,
      required this.ammo,
      required this.vest,
      required this.helmet,
      required this.walls,
      required this.alive,
      required this.ready,
      required this.shield,
      required this.dash,
      required this.bot,
      required this.reloading,
      required this.name});

  /// [a] is the packed array:
  /// [id, x, y, aim*100, hp, flags, kills, wins, wi, wi2, nades, cd, ammo,
  ///  vest%, helmet%, walls]
  factory NetPlayer.unpack(List a, String name) {
    int at(int i) => i < a.length ? (a[i] as num).toInt() : 0;
    final flags = at(5);
    return NetPlayer(
      id: at(0),
      x: at(1).toDouble(),
      y: at(2).toDouble(),
      aim: at(3) / 100.0,
      hp: at(4),
      kills: at(6),
      wins: at(7),
      wi: at(8),
      wi2: at(9),
      nades: at(10),
      cd: at(11),
      ammo: at(12),
      vest: at(13),
      helmet: at(14),
      walls: at(15),
      alive: flags & 1 != 0,
      ready: flags & 2 != 0,
      shield: flags & 4 != 0,
      dash: flags & 8 != 0,
      bot: flags & 16 != 0,
      reloading: flags & 32 != 0,
      name: name,
    );
  }
}

/// A rectangular obstacle (building/cover). x,y is the centre.
/// kind: 0 building · 1 crate/rock · 2 bush (see-through, no collision).
class NetObs {
  final double x, y, w, h;
  final int kind;
  const NetObs(this.x, this.y, this.w, this.h, [this.kind = 0]);
  bool get blocks => kind != 2;
}

/// A ground pickup. kind: 0 medkit · 1 weapon crate · 2 airdrop.
class NetLoot {
  final double x, y;
  final int kind;
  final int wi;
  const NetLoot(this.x, this.y, this.kind, this.wi);
}

/// A player-deployed shield wall — real cover, with hit points.
class NetWall {
  final double x, y, w, h, health;
  const NetWall(this.x, this.y, this.w, this.h, this.health);
}

/// A shot fired somewhere in the world this tick. The client turns these into
/// local muzzle flashes and tracers using its own weapon table, so bullets fly
/// perfectly smoothly instead of being streamed position-by-position.
class NetShot {
  final double x, y, aim;
  final int wi;
  /// Who fired it. The renderer starts the tracer at THAT operator's muzzle as
  /// currently drawn — otherwise a round appears to leave the shooter's chest,
  /// because the snapshot position lags what you see on screen.
  final int shooter;
  const NetShot(this.x, this.y, this.aim, this.wi, this.shooter);
}

/// Thin client for the Zone Royale authoritative server. Connects over a plain
/// dart:io WebSocket (works on Android/iOS/desktop — no extra dependency),
/// sends local input, and exposes the latest server snapshot. `rev` bumps on
/// every snapshot or status change so a widget can rebuild.
class NetClient {
  WebSocket? _ws;
  int myId = -1;
  double world = 3200;
  bool connected = false;

  /// connecting | live | error | closed
  String status = 'connecting';
  String? error;

  List<NetPlayer> players = const [];
  List<NetObs> obstacles = const [];
  List<NetLoot> loot = const [];
  List<Offset> nades = const [];
  /// Deployed shield walls: centre x/y, size, and how intact they are (0..1).
  List<NetWall> walls = const [];

  /// Drained by the renderer each frame.
  final List<NetShot> shotQueue = [];
  final List<Offset> boomQueue = [];
  final List<Offset> dropQueue = [];

  final Map<int, String> _names = {};
  final Map<int, int> _heroes = {};
  final Map<int, bool> _bots = {};

  int heroOf(int id) => _heroes[id] ?? 0;

  // shrinking gas zone
  double zoneX = 1600, zoneY = 1600, zoneR = 3000;

  // room match settings (from the host's config)
  String map = 'RANDOM';
  String weapon = 'ALL_ARMS';
  int rounds = 1;
  int round = 1;
  int maxPlayers = 10;
  int hostId = 0;
  String? roundBanner; // e.g. "ROUND 1 — AVA WINS"
  String? matchWinner; // set when the match is decided

  // room rules (host-controlled)
  bool allowMedkits = true, allowGrenades = true, allowSkills = true;
  bool fillBots = true;
  int botTarget = 8;
  int botDifficulty = 1;
  bool started = false; // has anyone deployed yet?

  /// True when the host we connected to is running an older build than this
  /// app (it streams the pre-2.0 snapshot format). Online play needs the
  /// matching server — redeploy `server/` and it clears itself.
  bool serverOutdated = false;

  bool get isHost => myId == hostId;

  /// Real players only — bots don't occupy the room's player limit.
  int get humanCount {
    var n = 0;
    for (final p in players) {
      if (!p.bot) n++;
    }
    return n;
  }

  // ---- snapshot interpolation (renders smoothly between server ticks) ----
  final Map<int, List<double>> _prevP = {}; // id -> [x, y, aim]
  final Map<int, List<double>> _currP = {};
  int _prevAt = 0, _currAt = 0;

  /// Interpolated [x, y, aim] for a player, or null if unknown. Renders
  /// [kInterpDelayMs] in the past so a late packet doesn't cause a hitch.
  List<double>? lerpOf(int id) {
    final cur = _currP[id];
    if (cur == null) return null;
    final pv = _prevP[id] ?? cur;
    final span = (_currAt - _prevAt).clamp(1, 400);
    final renderAt = DateTime.now().millisecondsSinceEpoch - kInterpDelayMs;
    final t = ((renderAt - _prevAt) / span).clamp(0.0, 1.35);
    double a = pv[2], b = cur[2];
    var d = b - a;
    while (d > math.pi) {
      d -= 2 * math.pi;
    }
    while (d < -math.pi) {
      d += 2 * math.pi;
    }
    return [
      pv[0] + (cur[0] - pv[0]) * t,
      pv[1] + (cur[1] - pv[1]) * t,
      a + d * t,
    ];
  }

  void _recordSnapshot() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _prevAt = _currAt == 0 ? now - 33 : _currAt;
    _currAt = now;
    _prevP
      ..clear()
      ..addAll(_currP);
    _currP.clear();
    for (final p in players) {
      _currP[p.id] = [p.x, p.y, p.aim];
    }
  }

  Map<String, dynamic>? _joinConfig;
  int _hero = 0;
  int _startWi = 5;
  bool _quick = false;
  Timer? _pinger;

  /// Smoothed round-trip time to the server, in ms. 0 until the first pong.
  int pingMs = 0;

  void _startPinging() {
    _pinger?.cancel();
    _pinger = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      try {
        _ws?.add(jsonEncode(
            {'type': 'ping', 't': DateTime.now().millisecondsSinceEpoch}));
      } catch (_) {}
    });
  }

  /// The room the server actually placed us in (quick match may overflow into
  /// PUBLIC1, PUBLIC2, …). Empty until the first `roomcfg` arrives.
  String roomCode = '';

  final ValueNotifier<int> rev = ValueNotifier(0);

  Future<void> connect(String url, String name, String room,
      {Map<String, dynamic>? config,
      int hero = 0,
      int startWi = 5,
      bool quick = false}) async {
    error = null;
    _joinConfig = config;
    _hero = hero;
    _startWi = startWi;
    _quick = quick;
    // Free hosts (Render free tier) spin the server down when idle. The first
    // request wakes it but can take ~30-60s — far longer than a WebSocket
    // handshake will wait. So we first send a plain HTTP GET to wake it (which
    // Render holds open until the instance is live), then connect the socket,
    // retrying a few times to ride out the cold start.
    status = 'waking';
    _bump();
    await _wake(url);

    for (var attempt = 1; attempt <= 5; attempt++) {
      status = attempt == 1 ? 'connecting' : 'waking';
      _bump();
      try {
        final ws =
            await WebSocket.connect(url).timeout(const Duration(seconds: 15));
        _ws = ws;
        ws.add(jsonEncode({
          'type': 'join',
          'name': name,
          'room': room,
          'hero': _hero,
          'startWi': _startWi,
          if (_quick) 'quick': true,
          if (_joinConfig != null) 'config': _joinConfig,
        }));
        ws.listen(
          _onData,
          onError: (Object e) => _fail('$e'),
          onDone: () {
            if (status != 'error') status = 'closed';
            connected = false;
            _bump();
          },
          cancelOnError: true,
        );
        return; // connected — done
      } catch (e) {
        error = '$e';
        if (attempt == 5) {
          _fail('$e');
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 4));
      }
    }
  }

  /// Sends an HTTP GET to the same host to wake a sleeping free-tier instance.
  /// Best-effort: any failure is ignored (the socket retry loop handles it).
  Future<void> _wake(String wsUrl) async {
    HttpClient? client;
    try {
      final httpUrl = wsUrl
          .replaceFirst('wss://', 'https://')
          .replaceFirst('ws://', 'http://');
      client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      final req = await client
          .getUrl(Uri.parse(httpUrl))
          .timeout(const Duration(seconds: 15));
      final resp = await req.close().timeout(const Duration(seconds: 55));
      await resp.drain<void>();
    } catch (_) {
      // ignore — the instance may already be awake or the retry loop will cope
    } finally {
      client?.close(force: true);
    }
  }

  void _onData(dynamic data) {
    try {
      final m = jsonDecode(data as String) as Map;
      switch (m['type']) {
        case 'welcome':
          myId = (m['id'] as num).toInt();
          world = (m['world'] as num).toDouble();
          connected = true;
          status = 'live';
          _startPinging();
          _bump();
          break;
        case 'roomcfg':
          roomCode = (m['code'] as String?) ?? roomCode;
          world = (m['world'] as num?)?.toDouble() ?? world;
          map = (m['map'] as String?) ?? map;
          weapon = (m['weapon'] as String?) ?? weapon;
          rounds = (m['rounds'] as num?)?.toInt() ?? rounds;
          round = (m['round'] as num?)?.toInt() ?? round;
          maxPlayers = (m['maxPlayers'] as num?)?.toInt() ?? maxPlayers;
          hostId = (m['host'] as num?)?.toInt() ?? hostId;
          allowMedkits = m['medkit'] != false;
          allowGrenades = m['grenades'] != false;
          allowSkills = m['skills'] != false;
          fillBots = m['bots'] != false;
          botTarget = (m['botTarget'] as num?)?.toInt() ?? botTarget;
          botDifficulty = (m['botDifficulty'] as num?)?.toInt() ?? botDifficulty;
          started = m['started'] == true;
          final obs = m['obstacles'];
          if (obs is List) {
            obstacles = [
              for (final o in obs)
                NetObs(
                  (o['x'] as num).toDouble(),
                  (o['y'] as num).toDouble(),
                  (o['w'] as num).toDouble(),
                  (o['h'] as num).toDouble(),
                  (o['k'] as num?)?.toInt() ?? 0,
                )
            ];
          }
          _bump();
          break;
        case 'roster':
          final list = m['players'];
          if (list is List) {
            _names.clear();
            _heroes.clear();
            _bots.clear();
            for (final e in list) {
              final id = (e['id'] as num).toInt();
              _names[id] = (e['name'] as String?) ?? '';
              _heroes[id] = (e['hero'] as num?)?.toInt() ?? 0;
              _bots[id] = e['bot'] == true;
            }
          }
          _bump();
          break;
        case 'round':
          final r = (m['round'] as num?)?.toInt() ?? round;
          final name = (m['name'] as String?) ?? '—';
          roundBanner = 'ROUND $r  —  $name WINS';
          // banner clears itself when the next round starts (see 'state')
          _bump();
          break;
        case 'matchover':
          matchWinner = (m['name'] as String?) ?? '—';
          roundBanner = null;
          _bump();
          break;
        case 'drop':
          dropQueue.add(Offset((m['x'] as num).toDouble(),
              (m['y'] as num).toDouble()));
          _bump();
          break;
        case 'pong':
          final sent = (m['t'] as num?)?.toInt();
          if (sent != null) {
            final rtt = DateTime.now().millisecondsSinceEpoch - sent;
            // smooth it so the readout doesn't flicker on a single spike
            pingMs = pingMs == 0 ? rtt : ((pingMs * 3 + rtt) ~/ 4);
            _bump();
          }
          break;
        case 'full':
          _fail('Room is full (${m['max']} players max).');
          break;
        case 'state':
          final ps = m['p'];
          // An old server still streams `players` objects. Say so plainly
          // instead of showing an empty arena that looks like a bug.
          if (ps is! List && m['players'] is List) {
            serverOutdated = true;
            _bump();
            break;
          }
          if (ps is List) {
            players = [
              for (final a in ps)
                NetPlayer.unpack(
                    a as List, _names[(a[0] as num).toInt()] ?? 'PLAYER')
            ];
          }
          _recordSnapshot();
          round = (m['r'] as num?)?.toInt() ?? round;
          rounds = (m['rs'] as num?)?.toInt() ?? rounds;
          final z = m['z'];
          if (z is List && z.length >= 3) {
            zoneX = (z[0] as num).toDouble();
            zoneY = (z[1] as num).toDouble();
            zoneR = (z[2] as num).toDouble();
          }
          final lt = m['l'];
          if (lt is List) {
            loot = [
              for (final l in lt)
                NetLoot((l[0] as num).toDouble(), (l[1] as num).toDouble(),
                    (l[2] as num).toInt(), (l[3] as num).toInt())
            ];
          }
          final wl = m['w'];
          walls = wl is List
              ? [
                  for (final w in wl)
                    NetWall(
                      (w[0] as num).toDouble(),
                      (w[1] as num).toDouble(),
                      (w[2] as num).toDouble(),
                      (w[3] as num).toDouble(),
                      (w[4] as num).toDouble() / 100.0,
                    )
                ]
              : const [];
          final g = m['g'];
          if (g is List) {
            nades = [
              for (final n in g)
                Offset((n[0] as num).toDouble(), (n[1] as num).toDouble())
            ];
          }
          final e = m['e'];
          if (e is List) {
            for (final s in e) {
              shotQueue.add(NetShot(
                (s[0] as num).toDouble(),
                (s[1] as num).toDouble(),
                (s[2] as num).toDouble() / 100.0,
                (s[3] as num).toInt(),
                s.length > 4 ? (s[4] as num).toInt() : -1,
              ));
            }
            if (shotQueue.length > 120) {
              shotQueue.removeRange(0, shotQueue.length - 120);
            }
          }
          final bx = m['x'];
          if (bx is List) {
            for (final b in bx) {
              boomQueue.add(
                  Offset((b[0] as num).toDouble(), (b[1] as num).toDouble()));
            }
          }
          // everyone respawned => a new round started; clear the banners
          final allAlive = players.isNotEmpty && players.every((p) => p.alive);
          if (allAlive) {
            roundBanner = null;
            if (round == 1 && players.every((p) => p.wins == 0)) {
              matchWinner = null;
            }
          }
          _bump();
          break;
      }
    } catch (_) {}
  }

  NetPlayer? get me {
    for (final p in players) {
      if (p.id == myId) return p;
    }
    return null;
  }

  /// Alive combatants — lobby players aren't in the fight yet.
  int get aliveCount {
    var n = 0;
    for (final p in players) {
      if (p.alive && p.ready) n++;
    }
    return n;
  }

  /// START MISSION — tells the server to drop us into the fight. Until this is
  /// sent we sit in the lobby: not shootable, not counted for round end.
  void sendReady() {
    try {
      _ws?.add(jsonEncode({'type': 'ready'}));
    } catch (_) {}
  }

  /// Host-only: push the room rules again from the lobby so a settings change
  /// applies without leaving and rejoining.
  void sendConfig(Map<String, dynamic> config) {
    try {
      _ws?.add(jsonEncode({'type': 'cfg', 'config': config}));
    } catch (_) {}
  }

  void sendInput(double mx, double my, double aim, bool fire,
      {bool nade = false,
      bool skill = false,
      bool reload = false,
      bool swap = false,
      bool take = false,
      bool wall = false}) {
    final ws = _ws;
    if (ws == null) return;
    try {
      ws.add(jsonEncode({
        'type': 'input',
        'mx': double.parse(mx.toStringAsFixed(3)),
        'my': double.parse(my.toStringAsFixed(3)),
        'aim': double.parse(aim.toStringAsFixed(3)),
        'fire': fire,
        if (nade) 'nade': true,
        if (skill) 'skill': true,
        if (reload) 'reload': true,
        if (swap) 'swap': true,
        if (take) 'take': true,
        if (wall) 'wall': true,
      }));
    } catch (_) {}
  }

  void _fail(String e) {
    error = e;
    status = 'error';
    connected = false;
    _bump();
  }

  void _bump() => rev.value++;

  /// Awaits the close handshake. This matters: if we reconnect before the
  /// server has processed our disconnect, the old room still has us in it, so
  /// it is reused and the new settings are ignored.
  Future<void> close() async {
    _pinger?.cancel();
    _pinger = null;
    pingMs = 0;
    final ws = _ws;
    _ws = null;
    connected = false;
    if (ws == null) return;
    try {
      await ws.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}
