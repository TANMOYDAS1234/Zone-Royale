import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// One player as seen in a server snapshot.
class NetPlayer {
  final int id;
  final double x, y, aim;
  final int hp, kills, wins, wi, nades, cd;
  final bool alive, shield, dash, bot, ready;
  final String name;
  const NetPlayer(this.id, this.x, this.y, this.aim, this.hp, this.kills,
      this.wins, this.wi, this.nades, this.cd, this.alive, this.shield,
      this.dash, this.bot, this.ready, this.name);

  factory NetPlayer.from(Map m) => NetPlayer(
        (m['id'] as num).toInt(),
        (m['x'] as num).toDouble(),
        (m['y'] as num).toDouble(),
        (m['aim'] as num).toDouble(),
        (m['hp'] as num).toInt(),
        (m['kills'] as num?)?.toInt() ?? 0,
        (m['wins'] as num?)?.toInt() ?? 0,
        (m['wi'] as num?)?.toInt() ?? 5,
        (m['nades'] as num?)?.toInt() ?? 0,
        (m['cd'] as num?)?.toInt() ?? 0,
        m['alive'] == true,
        m['sh'] == true,
        m['dsh'] == true,
        m['bot'] == true,
        m['rdy'] == true,
        (m['name'] as String?) ?? '',
      );
}

class NetBullet {
  final double x, y, vx, vy;
  const NetBullet(this.x, this.y, [this.vx = 0, this.vy = 0]);

  /// Position [age] seconds after the snapshot it came from.
  Offset at(double age) => Offset(x + vx * age, y + vy * age);
}

/// A rectangular obstacle (building/cover). x,y is the centre.
class NetObs {
  final double x, y, w, h;
  const NetObs(this.x, this.y, this.w, this.h);
}

/// A ground pickup: weapon crate ('w', with weapon index wi) or medkit ('m').
class NetLoot {
  final double x, y;
  final String kind;
  final int wi;
  const NetLoot(this.x, this.y, this.kind, this.wi);
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
  List<NetBullet> bullets = const [];
  List<NetObs> obstacles = const [];
  List<NetLoot> loot = const [];
  List<NetBullet> nades = const []; // flying grenade positions

  // shrinking gas zone
  double zoneX = 1600, zoneY = 1600, zoneR = 3000;

  // room match settings (from the host's config)
  String map = 'RANDOM';
  String weapon = 'RIFLE';
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
  int _snapAt = 0;
  double _snapDt = 33;

  /// Interpolated [x, y, aim] for a player, or null if unknown.
  List<double>? lerpOf(int id) {
    final cur = _currP[id];
    if (cur == null) return null;
    final pv = _prevP[id] ?? cur;
    final t = ((DateTime.now().millisecondsSinceEpoch - _snapAt) / _snapDt)
        .clamp(0.0, 1.0);
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

  /// Seconds since the last snapshot — used to extrapolate projectiles.
  double get snapAge => _snapAt == 0
      ? 0
      : ((DateTime.now().millisecondsSinceEpoch - _snapAt) / 1000.0)
          .clamp(0.0, 0.15);

  void _recordSnapshot() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_snapAt != 0) {
      // exponential moving average: network jitter shouldn't wobble the lerp
      final measured = (now - _snapAt).clamp(16, 250).toDouble();
      _snapDt = _snapDt * 0.8 + measured * 0.2;
    }
    _snapAt = now;
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
                )
            ];
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
          players = [
            for (final p in (m['players'] as List)) NetPlayer.from(p as Map)
          ];
          _recordSnapshot();
          round = (m['round'] as num?)?.toInt() ?? round;
          rounds = (m['rounds'] as num?)?.toInt() ?? rounds;
          bullets = [
            for (final b in (m['bullets'] as List))
              NetBullet(
                (b['x'] as num).toDouble(),
                (b['y'] as num).toDouble(),
                (b['vx'] as num?)?.toDouble() ?? 0,
                (b['vy'] as num?)?.toDouble() ?? 0,
              )
          ];
          final nd = m['nades'];
          if (nd is List) {
            nades = [
              for (final g in nd)
                NetBullet(
                  (g['x'] as num).toDouble(),
                  (g['y'] as num).toDouble(),
                  (g['vx'] as num?)?.toDouble() ?? 0,
                  (g['vy'] as num?)?.toDouble() ?? 0,
                )
            ];
          }
          final lt = m['loot'];
          if (lt is List) {
            loot = [
              for (final l in lt)
                NetLoot(
                  (l['x'] as num).toDouble(),
                  (l['y'] as num).toDouble(),
                  (l['k'] as String?) ?? 'm',
                  (l['wi'] as num?)?.toInt() ?? -1,
                )
            ];
          }
          final z = m['zone'];
          if (z is Map) {
            zoneX = (z['x'] as num).toDouble();
            zoneY = (z['y'] as num).toDouble();
            zoneR = (z['r'] as num).toDouble();
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

  void sendInput(double mx, double my, double aim, bool fire,
      {bool nade = false, bool skill = false}) {
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
