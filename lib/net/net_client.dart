import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One player as seen in a server snapshot.
class NetPlayer {
  final int id;
  final double x, y, aim;
  final int hp, kills;
  final bool alive;
  final String name;
  const NetPlayer(this.id, this.x, this.y, this.aim, this.hp, this.kills,
      this.alive, this.name);

  factory NetPlayer.from(Map m) => NetPlayer(
        (m['id'] as num).toInt(),
        (m['x'] as num).toDouble(),
        (m['y'] as num).toDouble(),
        (m['aim'] as num).toDouble(),
        (m['hp'] as num).toInt(),
        (m['kills'] as num?)?.toInt() ?? 0,
        m['alive'] == true,
        (m['name'] as String?) ?? '',
      );
}

class NetBullet {
  final double x, y;
  const NetBullet(this.x, this.y);
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

  final ValueNotifier<int> rev = ValueNotifier(0);

  Future<void> connect(String url, String name, String room) async {
    error = null;
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
        ws.add(jsonEncode({'type': 'join', 'name': name, 'room': room}));
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
          _bump();
          break;
        case 'state':
          players = [
            for (final p in (m['players'] as List)) NetPlayer.from(p as Map)
          ];
          bullets = [
            for (final b in (m['bullets'] as List))
              NetBullet((b['x'] as num).toDouble(), (b['y'] as num).toDouble())
          ];
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

  int get aliveCount {
    var n = 0;
    for (final p in players) {
      if (p.alive) n++;
    }
    return n;
  }

  void sendInput(double mx, double my, double aim, bool fire) {
    final ws = _ws;
    if (ws == null) return;
    try {
      ws.add(jsonEncode({
        'type': 'input',
        'mx': double.parse(mx.toStringAsFixed(3)),
        'my': double.parse(my.toStringAsFixed(3)),
        'aim': double.parse(aim.toStringAsFixed(3)),
        'fire': fire,
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

  void close() {
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    connected = false;
  }
}
