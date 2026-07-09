import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/char_art.dart';
import '../game/config.dart';
import '../game/profile.dart';
import '../ui/game_ui.dart' show Joystick;
import 'net_client.dart';

/// Full-screen multiplayer flow: a connect form (server address + room code),
/// then the live networked arena once the socket is up. Push this with
/// Navigator.push from the start menu's MULTIPLAYER button.
class MultiplayerScreen extends StatefulWidget {
  const MultiplayerScreen({super.key});

  @override
  State<MultiplayerScreen> createState() => _MultiplayerScreenState();
}

class _MultiplayerScreenState extends State<MultiplayerScreen> {
  final _server = TextEditingController(text: 'ws://192.168.1.5:8080');
  final _room = TextEditingController();
  late final _name = TextEditingController(text: Profile.instance.name);
  NetClient? _client;

  @override
  void dispose() {
    _client?.close();
    _server.dispose();
    _room.dispose();
    _name.dispose();
    super.dispose();
  }

  String _normalizeUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('ws://') && !s.startsWith('wss://')) s = 'ws://$s';
    // add default port for a plain ws host with no port
    if (s.startsWith('ws://') && !s.substring(5).contains(':')) s = '$s:8080';
    return s;
  }

  Future<void> _connect() async {
    final url = _normalizeUrl(_server.text);
    if (url.isEmpty) return;
    final name = _name.text.trim().isEmpty ? 'Player' : _name.text.trim();
    final c = NetClient();
    setState(() => _client = c);
    await c.connect(url, name, _room.text.trim());
  }

  void _leave() {
    _client?.close();
    setState(() => _client = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = _client;
    return Scaffold(
      backgroundColor: const Color(0xFF0E1116),
      body: SafeArea(
        child: c == null
            ? _form()
            : AnimatedBuilder(
                animation: c.rev,
                builder: (_, _) => c.status == 'live'
                    ? _ArenaView(client: c, onLeave: _leave)
                    : _statusView(c),
              ),
      ),
    );
  }

  Widget _statusView(NetClient c) {
    final busy = c.status == 'connecting' || c.status == 'waking';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const CircularProgressIndicator(color: kSafeEdge)
          else
            const Icon(Icons.wifi_off, color: kAccent2, size: 54),
          const SizedBox(height: 18),
          Text(
            c.status == 'waking'
                ? 'Waking the server…'
                : c.status == 'connecting'
                    ? 'Connecting…'
                    : c.status == 'closed'
                        ? 'Disconnected'
                        : 'Could not connect',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          if (c.status == 'waking') ...[
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Free hosting sleeps when idle — first connect can take up to a '
                'minute. Hang tight…',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
          if (c.error != null && !busy) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(c.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          ],
          const SizedBox(height: 22),
          TextButton(onPressed: _leave, child: const Text('BACK')),
        ],
      ),
    );
  }

  Widget _form() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              const SizedBox(width: 4),
              const Text('MULTIPLAYER',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2)),
            ],
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text('Play live against real players on the same server.',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          const SizedBox(height: 24),
          _field('Server address', _server,
              hint: 'ws://<PC-LAN-IP>:8080  or  wss://your-app.onrender.com'),
          const SizedBox(height: 16),
          _field('Room code (optional)', _room,
              hint: 'Share a code with friends to land together'),
          const SizedBox(height: 16),
          _field('Your name', _name),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _connect,
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('CONNECT & PLAY',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Free LAN test: on your PC run  dart run bin/server.dart  in the '
              'server/ folder, then enter  ws://<your-PC-IP>:8080  here (phone '
              'and PC on the same Wi‑Fi). To play over the internet, deploy the '
              'server to Render (free) and use its wss:// URL.',
              style: TextStyle(
                  color: Colors.white38, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }
}

/// The live arena: renders the server snapshot and streams input at ~30 Hz.
class _ArenaView extends StatefulWidget {
  final NetClient client;
  final VoidCallback onLeave;
  const _ArenaView({required this.client, required this.onLeave});

  @override
  State<_ArenaView> createState() => _ArenaViewState();
}

class _ArenaViewState extends State<_ArenaView> {
  Offset _move = Offset.zero; // left stick (-1..1)
  double _aim = 0; // last aim angle
  bool _fire = false;
  Timer? _pump;

  @override
  void initState() {
    super.initState();
    // stream input to the server at a steady rate, independent of frame timing
    _pump = Timer.periodic(const Duration(milliseconds: 33), (_) {
      widget.client.sendInput(_move.dx, _move.dy, _aim, _fire);
    });
  }

  @override
  void dispose() {
    _pump?.cancel();
    super.dispose();
  }

  void _aimStick(Offset dir) {
    if (dir.distance > 0.2) {
      _aim = math.atan2(dir.dy, dir.dx);
      _fire = true;
    } else {
      _fire = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    final me = c.me;
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: c.rev,
            builder: (_, _) => CustomPaint(painter: _ArenaPainter(c)),
          ),
        ),
        // top HUD
        Positioned(
          top: 10,
          left: 14,
          right: 14,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _pill('ALIVE  ${c.aliveCount}'),
              _pill('KILLS  ${me?.kills ?? 0}'),
              GestureDetector(
                onTap: widget.onLeave,
                child: _pill('LEAVE', color: kAccent2),
              ),
            ],
          ),
        ),
        // death banner
        if (me != null && !me.alive)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Text('ELIMINATED',
                    style: TextStyle(
                        color: kAccent2,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3)),
              ),
            ),
          ),
        // controls
        Positioned(
          left: 22,
          bottom: 28,
          child: Joystick(
            onChange: (d) => _move = d,
            onRelease: () => _move = Offset.zero,
            accent: kSafeEdge,
          ),
        ),
        Positioned(
          right: 22,
          bottom: 28,
          child: Joystick(
            onChange: _aimStick,
            onRelease: () => _fire = false,
            accent: kAccent2,
          ),
        ),
      ],
    );
  }

  Widget _pill(String text, {Color color = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      child: Text(text,
          style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1)),
    );
  }
}

class _ArenaPainter extends CustomPainter {
  final NetClient c;
  _ArenaPainter(this.c);

  @override
  void paint(Canvas canvas, Size size) {
    // background
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF10141B));

    final me = c.me;
    final camX = me?.x ?? c.world / 2;
    final camY = me?.y ?? c.world / 2;
    final scale = size.height / kViewHeight;

    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-camX, -camY);

    // world border + grid
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = kSafeEdge.withValues(alpha: 0.5);
    canvas.drawRect(Rect.fromLTWH(0, 0, c.world, c.world), border);
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double g = 0; g <= c.world; g += 400) {
      canvas.drawLine(Offset(g, 0), Offset(g, c.world), grid);
      canvas.drawLine(Offset(0, g), Offset(c.world, g), grid);
    }

    // bullets
    final bp = Paint()..color = kAccent;
    final bg = Paint()..color = kAccent.withValues(alpha: 0.35);
    for (final b in c.bullets) {
      canvas.drawCircle(Offset(b.x, b.y), 10, bg);
      canvas.drawCircle(Offset(b.x, b.y), 4.5, bp);
    }

    // players
    for (final p in c.players) {
      final mine = p.id == c.myId;
      final outfit = mine
          ? Profile.instance.outfitColor
          : Color(kOutfitColors[p.id % kOutfitColors.length]);
      final skin = mine
          ? Profile.instance.skinColor
          : Color(kSkinTones[p.id % kSkinTones.length]);
      final accessory =
          mine ? Profile.instance.accessory : p.id % kAccessoryNames.length;
      final weapon =
          mine ? Profile.instance.startWeapon : WeaponId.values[p.id % 5 + 1];
      final hero = mine ? Profile.instance.hero : p.id % kHeroes.length;

      if (!p.alive) {
        // faint fallen marker
        canvas.drawCircle(Offset(p.x, p.y), kPlayerRadius * 0.9,
            Paint()..color = Colors.black.withValues(alpha: 0.35));
        continue;
      }
      drawOperator(canvas, Offset(p.x, p.y), kPlayerRadius, p.aim, p.aim,
          outfit, skin, accessory, weapon,
          fill: fill, stroke: stroke, walk: 0, hero: hero);

      if (mine) {
        canvas.drawCircle(
            Offset(p.x, p.y),
            kPlayerRadius * 1.7,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = kSafeEdge.withValues(alpha: 0.7));
      }
    }
    canvas.restore();

    // screen-space overlays: names + hp bars
    for (final p in c.players) {
      if (!p.alive) continue;
      final sx = (p.x - camX) * scale + size.width / 2;
      final sy = (p.y - camY) * scale + size.height / 2;
      final top = sy - kPlayerRadius * scale - 18;
      // hp bar
      const w = 46.0;
      final hpFrac = (p.hp / 100).clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(sx - w / 2, top, w, 5), const Radius.circular(3)),
        Paint()..color = Colors.black54,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(sx - w / 2, top, w * hpFrac, 5),
            const Radius.circular(3)),
        Paint()
          ..color = hpFrac > 0.5
              ? const Color(0xFF57E389)
              : hpFrac > 0.25
                  ? kAccent
                  : kAccent2,
      );
      // name
      final tp = TextPainter(
        text: TextSpan(
          text: p.id == c.myId ? 'YOU' : p.name,
          style: TextStyle(
            color: p.id == c.myId ? kSafeEdge : Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(sx - tp.width / 2, top - 15));
    }
  }

  @override
  bool shouldRepaint(covariant _ArenaPainter old) => true;
}
