import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/char_art.dart';
import '../game/config.dart';
import '../game/profile.dart';
import '../game/royale_game.dart';
import '../ui/game_ui.dart' show Joystick;
import 'net_client.dart';

/// Full-screen multiplayer flow: a connect form (server address + room code),
/// then the live networked arena once the socket is up. Push this with
/// Navigator.push from the start menu's MULTIPLAYER button.
class MultiplayerScreen extends StatefulWidget {
  final RoyaleGame? game; // lets the bottom nav jump to real app sections
  const MultiplayerScreen({super.key, this.game});

  @override
  State<MultiplayerScreen> createState() => _MultiplayerScreenState();
}

class _MultiplayerScreenState extends State<MultiplayerScreen> {
  // Defaults to the live Render server — friends can just tap Connect.
  final _server =
      TextEditingController(text: 'wss://zone-royale.onrender.com');
  final _room = TextEditingController(text: 'PUBLIC');
  NetClient? _client;

  @override
  void dispose() {
    _client?.close();
    _server.dispose();
    _room.dispose();
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
    final name =
        Profile.instance.name.trim().isEmpty ? 'Player' : Profile.instance.name.trim();
    final room = _room.text.trim() == 'PUBLIC' ? '' : _room.text.trim();
    final c = NetClient();
    setState(() => _client = c);
    await c.connect(url, name, room);
  }

  void _leave() {
    _client?.close();
    setState(() => _client = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = _client;
    return Scaffold(
      backgroundColor: const Color(0xFF05070C),
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

  // Dynamic protocol tag from the entered URL — honest status, not decoration.
  String get _protocol {
    final s = _server.text.trim();
    if (s.startsWith('wss://')) return 'WSS_SECURE';
    if (s.startsWith('ws://')) return 'WS_LOCAL';
    return 'AUTO';
  }

  static const _mono = 'monospace';

  Widget _form() {
    return Stack(
      children: [
        // tactical grid + faint recon icons behind everything
        const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _GridPainter()))),
        Positioned(
          top: 150,
          right: 24,
          child: Icon(Icons.storage_rounded,
              size: 92, color: Colors.white.withValues(alpha: 0.05)),
        ),
        Positioned(
          bottom: 120,
          left: 12,
          child: Icon(Icons.track_changes,
              size: 150, color: Colors.white.withValues(alpha: 0.04)),
        ),
        Column(
          children: [
            // ---- header ----
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 14, 6),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Icon(Icons.grid_view_rounded,
                        color: kAccent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Text('ZONE ROYALE',
                      style: TextStyle(
                          color: kAccent,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1)),
                  const Spacer(),
                  Icon(Icons.settings,
                      color: Colors.white.withValues(alpha: 0.6), size: 22),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 22),
                    Center(
                      child: Text('ESTABLISHING_UPLINK',
                          style: TextStyle(
                              fontFamily: _mono,
                              color: kAccent,
                              fontSize: 14,
                              letterSpacing: 3)),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text('DEPLOYMENT_TERMINAL',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1)),
                    ),
                    const SizedBox(height: 26),
                    // ---- terminal card ----
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _termField('SERVER ADDRESS', _server,
                              icon: Icons.dns_rounded),
                          const SizedBox(height: 20),
                          _termField('ROOM CODE', _room,
                              icon: Icons.vpn_key_rounded),
                          const SizedBox(height: 24),
                          GestureDetector(
                            onTap: _connect,
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 17),
                              decoration: BoxDecoration(
                                color: kAccent,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                      color: kAccent.withValues(alpha: 0.4),
                                      blurRadius: 22,
                                      spreadRadius: -2),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.wifi_tethering,
                                      color: Colors.black, size: 20),
                                  SizedBox(width: 12),
                                  Text('CONNECT TO SERVER',
                                      style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('PROTOCOL: $_protocol',
                                  style: TextStyle(
                                      fontFamily: _mono,
                                      color: Colors.white.withValues(alpha: 0.35),
                                      fontSize: 11,
                                      letterSpacing: 1)),
                              Text('LATENCY: -- MS',
                                  style: TextStyle(
                                      fontFamily: _mono,
                                      color: Colors.white.withValues(alpha: 0.35),
                                      fontSize: 11,
                                      letterSpacing: 1)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Playing as ${Profile.instance.name}  ·  share the room code '
                      'with friends to land in the same match.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11,
                          height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
            _bottomNav(),
          ],
        ),
      ],
    );
  }

  Widget _termField(String label, TextEditingController ctrl,
      {required IconData icon}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontFamily: _mono,
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
                child: Icon(icon,
                    size: 18, color: Colors.white.withValues(alpha: 0.4)),
              ),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  onChanged: (_) => setState(() {}), // refresh protocol tag
                  style: TextStyle(
                      fontFamily: _mono,
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 15),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Jump to a real app section: pop this route, then switch the menu screen.
  void _goto(String screen) {
    Navigator.of(context).maybePop();
    widget.game?.screen.value = screen;
  }

  Widget _bottomNav() {
    Widget item(IconData icon, String label, bool active, VoidCallback? onTap) {
      final col = active ? kAccent : Colors.white.withValues(alpha: 0.4);
      return Expanded(
        child: GestureDetector(
          onTap: active ? null : onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: active
                ? BoxDecoration(
                    color: kAccent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12))
                : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: col, size: 22),
                const SizedBox(height: 5),
                Text(label,
                    style: TextStyle(
                        fontFamily: _mono,
                        color: col,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // OPERATIONS = this live-play terminal (current)
            item(Icons.track_changes, 'OPERATIONS', true, null),
            // ARMORY = the Shop (guns / skins / gear)
            item(Icons.military_tech, 'ARMORY', false,
                () => _goto(Screen.shop)),
            // FACTION = your operator identity / loadout
            item(Icons.groups, 'FACTION', false,
                () => _goto(Screen.profile)),
            // INTEL = daily missions / objectives
            item(Icons.storage_rounded, 'INTEL', false,
                () => _goto(Screen.missions)),
          ],
        ),
      ),
    );
  }
}

/// Faint tactical grid used behind terminal screens.
class _GridPainter extends CustomPainter {
  const _GridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 46) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 46) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
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
