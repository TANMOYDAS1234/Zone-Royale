import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../game/char_art.dart';
import '../game/config.dart';
import '../game/profile.dart';
import '../game/royale_game.dart';
import '../net/net_arena.dart';
import 'brand.dart';

// ============================================================
//  Reusable emblem (matches the app icon motif: closing zone)
// ============================================================
class EmblemPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    // outer amber ring with glow
    canvas.drawCircle(
        c,
        r * 0.88,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.11
          ..color = kAccent.withValues(alpha: 0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.06));
    canvas.drawCircle(
        c,
        r * 0.88,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.06
          ..color = kAccent);
    // inner red ring (the closing circle)
    canvas.drawCircle(
        c,
        r * 0.52,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.05
          ..color = kAccent2);
    // crosshair ticks
    final tick = Paint()
      ..color = Colors.white
      ..strokeWidth = r * 0.035
      ..strokeCap = StrokeCap.round;
    for (final a in [0, 1, 2, 3]) {
      final ang = a * math.pi / 2;
      final d = Offset(math.cos(ang), math.sin(ang));
      canvas.drawLine(c + d * (r * 0.88), c + d * (r * 0.6), tick);
    }
    // survivor dot
    canvas.drawCircle(c, r * 0.12, Paint()..color = Colors.white);
    canvas.drawCircle(
        c,
        r * 0.12,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.03
          ..color = kAccent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================
//  In-match HUD (health, ammo, alive, zone, minimap) + sticks
// ============================================================
class HudLayer extends StatelessWidget {
  final RoyaleGame game;
  const HudLayer({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.of(context).size;
    final floating = game.isMobile || game.touchMode;
    return Stack(
      children: [
        // cinematic lighting vignette — darkens the corners for depth
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.15,
                  colors: [Colors.transparent, Color(0xB3000000)],
                  stops: [0.5, 1.0],
                ),
              ),
            ),
          ),
        ),
        // live values repaint every frame
        AnimatedBuilder(
          animation: game.ticker,
          builder: (_, _) => _info(context),
        ),
        // Touch controls float at the player's customised positions (see the
        // Controls editor). On desktop the skill button sits at a fixed spot and
        // grenade/reload live in the info row.
        if (floating) ...[
          ..._sticks(s),
          _place(s, 'skill', _ticked(_skillButton), 64, 64),
          _place(s, 'nade', _ticked(_grenadeButton), 60, 60),
          _place(s, 'reload', _ticked(_reloadButton), 120, 70),
          _place(s, 'fire', _ticked(_fireModeButton), 64, 64),
        ] else
          Positioned(
            right: 28,
            bottom: 200,
            child: _ticked(_skillButton),
          ),
      ],
    );
  }

  // Repaints its child every game frame (ammo, cooldowns, grenade count…).
  Widget _ticked(Widget Function() build) => AnimatedBuilder(
        animation: game.ticker,
        builder: (_, _) => build(),
      );

  // Places [child] centred on its stored [key] fraction of the screen.
  Widget _place(Size s, String key, Widget child, double w, double h) {
    final f = Profile.instance.hudPosOf(key);
    final left = (f[0] * s.width - w / 2).clamp(0.0, (s.width - w).clamp(0.0, s.width));
    final top = (f[1] * s.height - h / 2).clamp(0.0, (s.height - h).clamp(0.0, s.height));
    return Positioned(left: left, top: top, child: child);
  }

  Widget _skillButton() {
    final p = game.player;
    final hero = kHeroes[Profile.instance.hero.clamp(0, kHeroes.length - 1)];
    final ready = p.skillCd <= 0;
    final col = Color(hero.color);
    return GestureDetector(
      onTap: ready ? game.activateSkill : null,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: ready ? col : Colors.white24, width: 3),
          boxShadow: ready
              ? [BoxShadow(color: col.withValues(alpha: 0.5), blurRadius: 14)]
              : null,
        ),
        child: Center(
          child: ready
              ? Icon(_skillIcon(hero.skill), color: col, size: 28)
              : Text('${p.skillCd.ceil()}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 20)),
        ),
      ),
    );
  }

  IconData _skillIcon(SkillType s) {
    switch (s) {
      case SkillType.dash:
        return Icons.bolt;
      case SkillType.shield:
        return Icons.shield;
      case SkillType.frenzy:
        return Icons.local_fire_department;
      case SkillType.medic:
        return Icons.healing;
      case SkillType.grenadier:
        return Icons.workspaces;
    }
  }

  Widget _info(BuildContext context) {
    final p = game.player;
    final hpFrac = (p.hp / kMaxHp).clamp(0.0, 1.0);
    final floating = game.isMobile || game.touchMode;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: game.goHome,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.home_rounded,
                        size: 18, color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 8),
                _pill('${game.aliveCount} ALIVE', kAccent),
                const SizedBox(width: 8),
                _pill('${p.kills} KILLS', Colors.white24),
                const Spacer(),
                _MiniMap(game: game),
              ],
            ),
            const SizedBox(height: 8),
            Center(child: _zoneBanner()),
            const Spacer(),
            if (game.toast != null)
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(game.toast!,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // health
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p.hp.ceil().clamp(0, 100)} HP',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13)),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: hpFrac,
                          minHeight: 12,
                          backgroundColor: Colors.black45,
                          valueColor: AlwaysStoppedAnimation(
                            Color.lerp(const Color(0xFFFF4D4D),
                                const Color(0xFF52E06A), hpFrac)!,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // On touch, fire-mode + grenade + reload float freely
                // (customisable); on desktop they stay here in the info row.
                if (!floating) ...[
                  const SizedBox(width: 10),
                  _fireModeButton(),
                  const SizedBox(width: 8),
                  _grenadeButton(),
                  const SizedBox(width: 10),
                  _reloadButton(),
                ],
              ],
            ),
            // leave room for the sticks on touch
            SizedBox(height: game.touchMode ? 150 : 4),
          ],
        ),
      ),
    );
  }

  Widget _zoneBanner() {
    final closing = game.zoneShrinking;
    final txt = closing
        ? 'ZONE CLOSING — GET INSIDE'
        : (game.zoneTimer > 900
            ? 'FINAL ZONE'
            : 'Zone shrinks in ${game.zoneTimer.ceil()}s');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: (closing ? kGasEdge : kSafeEdge).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: (closing ? kGasEdge : kSafeEdge).withValues(alpha: 0.7)),
      ),
      child: Text(txt,
          style: TextStyle(
              color: closing ? kGasEdge : kSafeEdge,
              fontWeight: FontWeight.w700,
              fontSize: 12)),
    );
  }

  Widget _pill(String txt, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: c.withValues(alpha: 0.7)),
        ),
        child: Text(txt,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
      );

  Widget _fireModeButton() {
    final supportsAuto = game.player.weapon.auto;
    final auto = supportsAuto && game.playerAuto;
    return GestureDetector(
      onTap: supportsAuto ? game.toggleFireMode : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: auto ? kAccent : Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(auto ? Icons.flash_on : Icons.filter_center_focus,
                size: 16, color: auto ? kAccent : Colors.white70),
            const SizedBox(height: 2),
            Text(
              !supportsAuto ? 'SINGLE' : (game.playerAuto ? 'AUTO' : 'SINGLE'),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grenadeButton() {
    final n = game.player.grenades;
    final has = n > 0;
    return GestureDetector(
      onTap: has ? game.throwGrenade : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: has ? const Color(0xFF6ABF5A) : Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
                opacity: has ? 1 : 0.4,
                child: const Text('💣', style: TextStyle(fontSize: 16))),
            Text('$n',
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  // Weapon panel — tap to reload. Shows gun name, ammo, and reload progress.
  Widget _reloadButton() {
    final p = game.player;
    final ammo = p.reloading ? 'RELOADING' : '${p.ammo} / ${p.weapon.mag}';
    final lowAmmo = !p.reloading && p.ammo <= (p.weapon.mag * 0.3).ceil();
    return GestureDetector(
      onTap: game.requestReload,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: lowAmmo
                  ? const Color(0xFFFF5A5F)
                  : p.weapon.color.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.autorenew, size: 12, color: Colors.white38),
                const SizedBox(width: 4),
                Text(p.weapon.name.toUpperCase(),
                    style: TextStyle(
                        color: p.weapon.color,
                        fontWeight: FontWeight.w800,
                        fontSize: 13)),
              ],
            ),
            Text(ammo,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: lowAmmo ? const Color(0xFFFF5A5F) : Colors.white)),
            if (p.reloading) ...[
              const SizedBox(height: 3),
              SizedBox(
                width: 62,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: 1 -
                        (p.reloadT / p.weapon.reloadTime).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: Colors.black45,
                    valueColor: AlwaysStoppedAnimation(p.weapon.color),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _sticks(Size s) {
    final p = Profile.instance;
    final size = 132.0 * p.stickScale;
    final move = _stickWidget(
      label: 'MOVE',
      accent: kSafeEdge,
      size: size,
      opacity: p.stickOpacity,
      onChange: (v) {
        game.enableTouch(true);
        game.setMove(v.dx, v.dy);
      },
      onRelease: () => game.setMove(0, 0),
    );
    final aim = _stickWidget(
      label: 'AIM · FIRE',
      accent: kAccent2,
      size: size,
      opacity: p.stickOpacity,
      onChange: (v) {
        game.enableTouch(true);
        game.setAimStick(v.dx, v.dy);
      },
      onRelease: () => game.setAimStick(0, 0),
    );
    // leftHanded swaps which stored slot each stick occupies.
    final moveKey = p.leftHanded ? 'aim' : 'move';
    final aimKey = p.leftHanded ? 'move' : 'aim';
    final h = size + 26; // joystick + label
    return [
      _place(s, moveKey, move, size, h),
      _place(s, aimKey, aim, size, h),
    ];
  }

  Widget _stickWidget({
    required String label,
    required Color accent,
    required double size,
    required double opacity,
    required void Function(Offset) onChange,
    required VoidCallback onRelease,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: accent.withValues(alpha: 0.9))),
        const SizedBox(height: 6),
        Joystick(
          onChange: onChange,
          onRelease: onRelease,
          size: size,
          accent: accent,
          opacity: opacity,
        ),
      ],
    );
  }
}

// ============================================================
//  Minimap
// ============================================================
class _MiniMap extends StatelessWidget {
  final RoyaleGame game;
  const _MiniMap({required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: CustomPaint(painter: _MiniMapPainter(game)),
    );
  }
}

// ============================================================
//  Controls editor — drag on-screen controls (BGMI/Free-Fire style)
// ============================================================
class ControlsEditor extends StatefulWidget {
  const ControlsEditor({super.key});

  @override
  State<ControlsEditor> createState() => _ControlsEditorState();
}

class _ControlsEditorState extends State<ControlsEditor> {
  // working copy of every control's [xFrac, yFrac] centre
  late Map<String, List<double>> _pos;

  static const _labels = {
    'move': 'MOVE',
    'aim': 'AIM · FIRE',
    'skill': 'SKILL',
    'nade': 'GRENADE',
    'reload': 'RELOAD',
    'fire': 'FIRE MODE',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _pos = {
      for (final k in Profile.kDefaultHud.keys)
        k: List<double>.from(Profile.instance.hudPosOf(k)),
    };
  }

  void _reset() => setState(() {
        _pos = {
          for (final e in Profile.kDefaultHud.entries)
            e.key: List<double>.from(e.value),
        };
      });

  Future<void> _save() async {
    Profile.instance.resetHud();
    _pos.forEach((k, v) => Profile.instance.setHudPos(k, v[0], v[1]));
    await Profile.instance.save();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      body: LayoutBuilder(
        builder: (context, box) {
          final s = Size(box.maxWidth, box.maxHeight);
          return Stack(
            children: [
              // faint arena grid so placement feels in-context
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _EditorGridPainter()),
                ),
              ),
              _token(s, 'move', 120, 120, ring: true, accent: kSafeEdge),
              _token(s, 'aim', 120, 120, ring: true, accent: kAccent2),
              _token(s, 'skill', 64, 64, accent: const Color(0xFFB06BFF)),
              _token(s, 'nade', 60, 60,
                  accent: const Color(0xFF6ABF5A), emoji: '💣'),
              _token(s, 'reload', 120, 66, accent: kAccent, box: true),
              _token(s, 'fire', 64, 64, accent: kAccent, box: true),
              // header
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Text('DRAG TO PLACE YOUR CONTROLS',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                  fontSize: 15)),
                        ),
                        TextButton.icon(
                          onPressed: _reset,
                          icon: const Icon(Icons.restart_alt,
                              size: 18, color: Colors.white70),
                          label: const Text('RESET',
                              style: TextStyle(color: Colors.white70)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // save bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kSafeEdge,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('SAVE LAYOUT',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _token(Size s, String key, double w, double h,
      {required Color accent,
      bool ring = false,
      bool box = false,
      String? emoji}) {
    final f = _pos[key]!;
    final left = f[0] * s.width - w / 2;
    final top = f[1] * s.height - h / 2;
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          f[0] = (f[0] + d.delta.dx / s.width).clamp(0.05, 0.95);
          f[1] = (f[1] + d.delta.dy / s.height).clamp(0.10, 0.92);
        }),
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            shape: ring ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: ring ? null : BorderRadius.circular(14),
            border: Border.all(color: accent, width: 2),
          ),
          child: Center(
            child: emoji != null
                ? Text(emoji, style: const TextStyle(fontSize: 22))
                : Text(
                    _labels[key]!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        fontSize: box ? 13 : 11,
                        letterSpacing: 0.5),
                  ),
          ),
        ),
      ),
    );
  }
}

class _EditorGridPainter extends CustomPainter {
  const _EditorGridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MiniMapPainter extends CustomPainter {
  final RoyaleGame game;
  _MiniMapPainter(this.game);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / game.worldSize;
    Offset m(double x, double y) => Offset(x * s, y * s);

    // safe circle
    canvas.drawCircle(
        m(game.zoneCenter.x, game.zoneCenter.y),
        game.zoneRadius * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = kSafeEdge);
    final p = game.player;
    // nearby enemies within detection range as red blips (radar)
    const detect = 780.0;
    final red = Paint()..color = const Color(0xFFFF3B30);
    for (final c in game.chars) {
      if (!c.alive || c == p) continue;
      if (p.pos.distanceTo(c.pos) > detect) continue;
      canvas.drawCircle(m(c.pos.x, c.pos.y), 2.4, red);
    }
    // player on top
    canvas.drawCircle(m(p.pos.x, p.pos.y), 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) => true;
}

// ============================================================
//  Twin-stick joystick (immediate Listener-based, multitouch)
// ============================================================
class Joystick extends StatefulWidget {
  final void Function(Offset dir) onChange; // dir components in [-1, 1]
  final VoidCallback onRelease;
  final double size;
  final Color accent;
  final double opacity;
  const Joystick({
    super.key,
    required this.onChange,
    required this.onRelease,
    this.size = 132,
    this.accent = kSafeEdge,
    this.opacity = 1.0,
  });

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  Offset _knob = Offset.zero;
  int? _pointer;

  void _update(Offset local) {
    final r = widget.size / 2;
    var v = local - Offset(r, r);
    if (v.distance > r) v = v / v.distance * r;
    setState(() => _knob = v);
    widget.onChange(Offset(v.dx / r, v.dy / r));
  }

  void _end() {
    setState(() => _knob = Offset.zero);
    _pointer = null;
    widget.onRelease();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.size / 2;
    final knob = widget.size * 0.4;
    final o = widget.opacity.clamp(0.3, 1.6);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _pointer = e.pointer;
        _update(e.localPosition);
      },
      onPointerMove: (e) {
        if (e.pointer == _pointer) _update(e.localPosition);
      },
      onPointerUp: (e) {
        if (e.pointer == _pointer) _end();
      },
      onPointerCancel: (e) {
        if (e.pointer == _pointer) _end();
      },
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: (0.30 * o).clamp(0.0, 1.0)),
                border: Border.all(
                    color: widget.accent
                        .withValues(alpha: (0.55 * o).clamp(0.0, 1.0)),
                    width: 2.5),
              ),
            ),
            Positioned(
              left: r - knob / 2 + _knob.dx,
              top: r - knob / 2 + _knob.dy,
              child: Container(
                width: knob,
                height: knob,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      widget.accent.withValues(alpha: (0.9 * o).clamp(0.0, 1.0)),
                  boxShadow: [
                    BoxShadow(
                        color: widget.accent.withValues(alpha: 0.5),
                        blurRadius: 12)
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
//  Start screen
// ============================================================
// ============================================================
//  Shared premium chrome: tactical header + bottom nav bar
// ============================================================
Widget metaHeader(BuildContext context, {String subtitle = 'OPERATIONS HUB'}) {
  final p = Profile.instance;
  return SafeArea(
    bottom: false,
    minimum: const EdgeInsets.only(top: 8),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
      children: [
        const ZoneLogo(size: 42, tile: false),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ZONE ROYALE',
                style: TextStyle(
                    color: kAccent,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    height: 1)),
            Text(subtitle,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: p.rankColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: p.rankColor.withValues(alpha: 0.7)),
              ),
              child: Text('RANK: ${p.rank.toUpperCase()}',
                  style: TextStyle(
                      color: p.rankColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5)),
            ),
            const SizedBox(height: 5),
            Text('🪙  ${p.coins}',
                style: const TextStyle(
                    color: Color(0xFFFFD36B),
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ],
      ),
    ),
  );
}

class MetaNav extends StatelessWidget {
  final RoyaleGame game;
  final String active;
  const MetaNav({super.key, required this.game, required this.active});

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, String s) {
      final on = s == active;
      final col = on ? kAccent : Colors.white.withValues(alpha: 0.42);
      return Expanded(
        child: GestureDetector(
          onTap: on ? null : () => game.screen.value = s,
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: on
                ? BoxDecoration(
                    color: kAccent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12))
                : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: col, size: 22),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                        color: col,
                        fontSize: 10,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D13),
        border:
            Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            item(Icons.home_rounded, 'HOME', Screen.start),
            item(Icons.shopping_cart_rounded, 'SHOP', Screen.shop),
            item(Icons.assignment_rounded, 'MISSIONS', Screen.missions),
            item(Icons.person_rounded, 'PROFILE', Screen.profile),
          ],
        ),
      ),
    );
  }
}

class StartOverlay extends StatefulWidget {
  final RoyaleGame game;
  const StartOverlay({super.key, required this.game});

  @override
  State<StartOverlay> createState() => _StartOverlayState();
}

class _StartOverlayState extends State<StartOverlay> {
  late int _mode = Profile.instance.matchMode.clamp(0, kMatchModes.length - 1);

  void _drop() {
    Profile.instance.matchMode = _mode;
    Profile.instance.save();
    widget.game.startMatch(kMatchModes[_mode]);
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return Container(
      color: const Color(0xFF07090E),
      child: Column(
        children: [
          metaHeader(context, subtitle: 'OPERATIONS HUB'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _operatorUnitCard(),
                  const SizedBox(height: 14),
                  _schematicCard(),
                  const SizedBox(height: 18),
                  _sectionLabel('SELECT DEPLOYMENT'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (var i = 0; i < kMatchModes.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(child: _modeCard(i)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  _mapPicker(),
                  const SizedBox(height: 18),
                  _DropButton(label: 'DROP IN', onTap: _drop),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => MultiplayerScreen(game: game)),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: kSafeEdge.withValues(alpha: 0.10),
                        border:
                            Border.all(color: kSafeEdge.withValues(alpha: 0.7)),
                      ),
                      child: const Text('🌐  MULTIPLAYER  ·  LIVE',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: kSafeEdge)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          MetaNav(game: game, active: Screen.start),
        ],
      ),
    );
  }

  Widget _sectionLabel(String t) => Row(
        children: [
          Container(width: 4, height: 15, color: kAccent),
          const SizedBox(width: 8),
          Text(t,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
        ],
      );

  Widget _operatorUnitCard() {
    final p = Profile.instance;
    final unit = kHeroes[p.hero.clamp(0, kHeroes.length - 1)].name.toUpperCase();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: kAccent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('OPERATOR UNIT',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('$unit · ${p.name}'.toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900)),
              const Spacer(),
              Text('LVL ${p.level}',
                  style: const TextStyle(
                      color: kAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: p.xpFraction,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation(kAccent),
            ),
          ),
          const SizedBox(height: 5),
          Text('${p.xp} / ${p.xpForNext} XP  →  NEXT LEVEL',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 10,
                  letterSpacing: 1)),
        ],
      ),
    );
  }

  // The real, honest 2D operator inside a tactical HUD schematic frame.
  Widget _schematicCard() {
    final p = Profile.instance;
    final unit = kHeroes[p.hero.clamp(0, kHeroes.length - 1)].name.toUpperCase();
    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kAccent.withValues(alpha: 0.35)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            const Positioned.fill(
                child: IgnorePointer(
                    child: CustomPaint(painter: _EditorGridPainter()))),
            Center(
              child: SizedBox(
                width: 168,
                height: 168,
                child: CustomPaint(
                  painter: OperatorPreviewPainter(
                    outfit: p.outfitColor,
                    skin: p.skinColor,
                    accessory: p.accessory,
                    weapon: p.startWeapon,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: kAccent2.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: kAccent2.withValues(alpha: 0.7)),
                ),
                child: Text('UNIT: SPEC-OPS // $unit',
                    style: const TextStyle(
                        color: kAccent2,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              child: Text('LOADOUT // ${p.startWeapon.name.toUpperCase()}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700)),
            ),
            Positioned(
              bottom: 12,
              right: 12,
              child: Row(
                children: [
                  Text('STATUS: READY',
                      style: TextStyle(
                          color: kSafeEdge.withValues(alpha: 0.9),
                          fontSize: 10,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(width: 6),
                  Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          color: kSafeEdge, shape: BoxShape.circle)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapPicker() {
    final sel = Profile.instance.mapChoice;
    Widget chip(int val, String label) {
      final on = sel == val;
      return GestureDetector(
        onTap: () => setState(() {
          Profile.instance.mapChoice = val;
          Profile.instance.save();
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? kSafeEdge.withValues(alpha: 0.2) : Colors.white10,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? kSafeEdge : Colors.white12),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: on ? kSafeEdge : Colors.white70)),
        ),
      );
    }

    return Column(
      children: [
        const Text('MAP',
            style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                color: Colors.white38,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            chip(0, 'RANDOM'),
            for (var i = 0; i < kMapThemes.length; i++)
              chip(i + 1, kMapThemes[i].name),
          ],
        ),
      ],
    );
  }

  Widget _modeCard(int i) {
    final m = kMatchModes[i];
    final sel = _mode == i;
    const icons = [Icons.groups, Icons.shield, Icons.military_tech];
    return GestureDetector(
      onTap: () => setState(() => _mode = i),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: sel
              ? kAccent.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: sel ? kAccent : Colors.white12, width: sel ? 2 : 1),
          boxShadow: sel
              ? [
                  BoxShadow(
                      color: kAccent.withValues(alpha: 0.3),
                      blurRadius: 16,
                      spreadRadius: -4)
                ]
              : null,
        ),
        child: Column(
          children: [
            Text(m.name.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.5,
                    color: sel ? kAccent : Colors.white)),
            const SizedBox(height: 10),
            Icon(icons[i % icons.length],
                color: sel ? kAccent : Colors.white54, size: 26),
            const SizedBox(height: 10),
            Text('${m.players} PLAYERS',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.5,
                    color: sel
                        ? kAccent.withValues(alpha: 0.9)
                        : Colors.white38)),
          ],
        ),
      ),
    );
  }
}

// ============================================================
//  End screen (win / lose) + share
// ============================================================
class EndOverlay extends StatelessWidget {
  final RoyaleGame game;
  final GlobalKey _shotKey = GlobalKey();
  EndOverlay({super.key, required this.game});

  // Capture the result card as a PNG and share it (BGMI/Free-Fire style),
  // falling back to a copied text result if the capture fails.
  Future<void> _shareShot(BuildContext context) async {
    final ctx = _shotKey.currentContext;
    if (ctx == null) {
      _share(context);
      return;
    }
    try {
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('capture failed');
      final dir = await getTemporaryDirectory();
      final file = await File('${dir.path}/zone_royale_result.png')
          .writeAsBytes(data.buffer.asUint8List());
      final won = game.resultWon;
      final txt = won
          ? '🏆 WINNER WINNER! #1 in Zone Royale — ${game.player.kills} kills. Beat that!'
          : '🔫 Zone Royale — #${game.resultPlacement}, ${game.player.kills} kills. My turn next.';
      await SharePlus.instance
          .share(ShareParams(files: [XFile(file.path)], text: txt));
    } catch (_) {
      if (context.mounted) _share(context);
    }
  }

  void _share(BuildContext context) {
    final won = game.resultWon;
    final place = game.resultPlacement;
    final kills = game.player.kills;
    final txt = won
        ? '🏆 WINNER WINNER! #1 / ${game.chars.length} in Zone Royale — $kills kills. Can you beat me?'
        : '🔫 Zone Royale — #$place / ${game.chars.length}, $kills kills. My turn to win next.';
    Clipboard.setData(ClipboardData(text: txt));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Result copied — paste it anywhere!'),
          duration: Duration(seconds: 2)),
    );
  }

  Widget _rewardsCard(RoyaleGame game) {
    final r = game.lastRewards;
    if (r == null) return const SizedBox.shrink();
    final p = Profile.instance;
    return Container(
      width: 300,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          if (r.levels > 0) ...[
            Text('LEVEL UP!  ×${r.levels}',
                style: TextStyle(
                    color: kAccent,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1)),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text('+${r.xp} XP',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Color(0xFF8FE07A))),
              Text('+${r.coins} 🪙',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Color(0xFFFFD36B))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Lv ${p.level}',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: p.rankColor)),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: p.xpFraction,
                    minHeight: 8,
                    backgroundColor: Colors.black38,
                    valueColor: AlwaysStoppedAnimation(p.rankColor),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(p.rank,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: p.rankColor)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final won = game.resultWon;
    final canSpectate = !won && game.aliveCount > 1;
    final accent = won ? kAccent : kAccent2;
    return Container(
      color: const Color(0xFF07090E),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                14, 10 + MediaQuery.of(context).padding.top, 14, 4),
            child: Row(
              children: [
                GestureDetector(
                    onTap: game.goHome,
                    child: const Icon(Icons.arrow_back, color: Colors.white)),
                const SizedBox(width: 10),
                const Text('MATCH SUMMARY',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Column(
                children: [
                  RepaintBoundary(
                    key: _shotKey,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            accent.withValues(alpha: 0.16),
                            const Color(0xFF05070C)
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: accent.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        children: [
                          Text('ZONE ROYALE  //  ${won ? 'VICTORY' : 'DEFEAT'}',
                              style: TextStyle(
                                  fontSize: 12,
                                  letterSpacing: 3,
                                  fontWeight: FontWeight.w900,
                                  color: accent)),
                          const SizedBox(height: 10),
                          Text(won ? '#1' : '#${game.resultPlacement}',
                              style: TextStyle(
                                  fontSize: 76,
                                  fontWeight: FontWeight.w900,
                                  color: accent,
                                  height: 1)),
                          Text(won ? 'WINNER WINNER' : 'ELIMINATED',
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                  color: won ? Colors.white : accent)),
                          Text(won ? 'CHICKEN DINNER' : 'ZONE SECTOR CLEARED',
                              style: TextStyle(
                                  fontSize: 12,
                                  letterSpacing: 5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.5))),
                          const SizedBox(height: 16),
                          // the real 2D operator (honest — matches gameplay)
                          Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: accent.withValues(alpha: 0.4)),
                            ),
                            child: CustomPaint(
                              painter: OperatorPreviewPainter(
                                outfit: Profile.instance.outfitColor,
                                skin: Profile.instance.skinColor,
                                accessory: Profile.instance.accessory,
                                weapon: Profile.instance.startWeapon,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _statsCard(),
                          const SizedBox(height: 12),
                          _rewardsCard(game),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DropButton(label: 'PLAY AGAIN', onTap: game.startMatch),
                  if (canSpectate)
                    TextButton(
                      onPressed: game.spectate,
                      child: const Text('SPECTATE',
                          style: TextStyle(
                              color: Colors.white38, letterSpacing: 1)),
                    ),
                ],
              ),
            ),
          ),
          // bottom action bar (HOME / SHARE)
          Container(
            decoration: const BoxDecoration(color: Color(0xFF0A0D13)),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                        child: _endAction(
                            Icons.home_rounded, 'HOME', game.goHome)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _endAction(Icons.ios_share, 'SHARE',
                            () => _shareShot(context))),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _endAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: Colors.white70),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _statsCard() {
    Widget stat(String k, String v) => Column(
          children: [
            Text(v,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
            const SizedBox(height: 2),
            Text(k,
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.5))),
          ],
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          stat('KILLS', '${game.player.kills}'),
          stat('PLAYERS', '${game.chars.length}'),
          stat('RANK', Profile.instance.rank.toUpperCase()),
        ],
      ),
    );
  }
}

class _DropButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DropButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFFFD36B), kAccent]),
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(color: kAccent.withValues(alpha: 0.5), blurRadius: 24)
          ],
        ),
        child: Text(label,
            style: const TextStyle(
                color: Color(0xFF10131A),
                fontWeight: FontWeight.w900,
                fontSize: 19,
                letterSpacing: 1)),
      ),
    );
  }
}

// ============================================================
//  Profile / customization screen
// ============================================================
class ProfileOverlay extends StatefulWidget {
  final RoyaleGame game;
  const ProfileOverlay({super.key, required this.game});

  @override
  State<ProfileOverlay> createState() => _ProfileOverlayState();
}

class _ProfileOverlayState extends State<ProfileOverlay> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: Profile.instance.name);
  }

  void _saveName() {
    final n = _name.text.trim();
    Profile.instance.name = n.isEmpty ? 'You' : n;
    Profile.instance.save();
  }

  @override
  void dispose() {
    _saveName(); // persist edits when leaving via the bottom nav too
    _name.dispose();
    super.dispose();
  }

  void _close() {
    _saveName();
    widget.game.screen.value = Screen.start;
  }

  @override
  Widget build(BuildContext context) {
    final p = Profile.instance;
    return Container(
      color: const Color(0xFF07090E),
      child: Column(
        children: [
          metaHeader(context, subtitle: 'OPERATOR CONFIG'),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 6),
              child: Row(
                children: [
                  const Text('OPERATOR',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _close,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: kAccent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kAccent),
                      ),
                      child: const Text('✓ SAVE',
                          style: TextStyle(
                              color: kAccent,
                              fontWeight: FontWeight.w900,
                              fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: CustomPaint(
                          painter: OperatorPreviewPainter(
                            outfit: p.outfitColor,
                            skin: p.skinColor,
                            accessory: p.accessory,
                            weapon: p.startWeapon,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _progressBanner(),
                    const SizedBox(height: 16),
                    _label('NAME'),
                    TextField(
                      controller: _name,
                      maxLength: 14,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: Colors.white10,
                        hintText: 'Your name',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('OUTFIT'),
                    _swatches(kOutfitColors.length, (i) => Color(kOutfitColors[i]),
                        p.outfit, (i) => setState(() => p.outfit = i),
                        lockPrefix: 'o'),
                    const SizedBox(height: 14),
                    _label('SKIN'),
                    _swatches(kSkinTones.length, (i) => Color(kSkinTones[i]),
                        p.skin, (i) => setState(() => p.skin = i)),
                    const SizedBox(height: 14),
                    _label('ACCESSORY'),
                    _chips(kAccessoryNames, p.accessory,
                        (i) => setState(() => p.accessory = i), lockPrefix: 'a'),
                    const SizedBox(height: 14),
                    _label('STARTING WEAPON'),
                    _weapons(p),
                    const SizedBox(height: 14),
                    _label('HERO'),
                    _heroes(p),
                    const SizedBox(height: 14),
                    _label('FIRE MODE'),
                    _fireMode(p),
                    const SizedBox(height: 14),
                    _label('CONTROLS'),
                    _controls(p),
                    const SizedBox(height: 18),
                    _stats(p),
                    const SizedBox(height: 18),
                    Center(
                        child: _DropButton(
                            label: 'SAVE PROFILE', onTap: _close)),
                  ],
                ),
              ),
            ),
            MetaNav(game: widget.game, active: Screen.profile),
          ],
        ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w800,
                color: Colors.white54)),
      );

  Widget _progressBanner() {
    final p = Profile.instance;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('Lv ${p.level}',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: p.rankColor)),
              const SizedBox(width: 8),
              Text(p.rank,
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: p.rankColor)),
              const Spacer(),
              Text('${p.coins} 🪙',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Color(0xFFFFD36B))),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: p.xpFraction,
              minHeight: 8,
              backgroundColor: Colors.black38,
              valueColor: AlwaysStoppedAnimation(p.rankColor),
            ),
          ),
          const SizedBox(height: 4),
          Text('${p.xp} / ${p.xpForNext} XP',
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _swatches(int count, Color Function(int) colorOf, int selected,
      void Function(int) onPick,
      {String? lockPrefix}) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < count; i++)
          _swatch(
            colorOf(i),
            selected == i,
            lockPrefix != null && !Profile.instance.owns('$lockPrefix$i'),
            () => onPick(i),
          ),
      ],
    );
  }

  Widget _swatch(Color color, bool sel, bool locked, VoidCallback onPick) {
    return GestureDetector(
      onTap: locked ? null : onPick,
      child: Opacity(
        opacity: locked ? 0.4 : 1,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                    color: sel ? Colors.white : Colors.transparent, width: 3),
              ),
            ),
            if (locked) const Icon(Icons.lock, size: 16, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _chips(List<String> names, int selected, void Function(int) onPick,
      {String? lockPrefix}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < names.length; i++)
          _chip(
            names[i],
            selected == i,
            lockPrefix != null && !Profile.instance.owns('$lockPrefix$i'),
            selected == i ? const Color(0xFF10131A) : Colors.white70,
            selected == i ? kAccent : Colors.white10,
            () => onPick(i),
          ),
      ],
    );
  }

  Widget _weapons(Profile p) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final w in kWeaponOrder)
          _chip(
            kWeapons[w]!.name,
            p.startWeapon == w,
            !p.owns('w${w.index}'),
            p.startWeapon == w ? const Color(0xFF10131A) : Colors.white70,
            p.startWeapon == w ? kWeapons[w]!.color : Colors.white10,
            () => setState(() => p.startWeapon = w),
          ),
      ],
    );
  }

  Widget _heroes(Profile p) {
    final cur = kHeroes[p.hero.clamp(0, kHeroes.length - 1)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < kHeroes.length; i++)
              _chip(
                kHeroes[i].name + (p.heroEvolved(i) ? ' ★' : ''),
                p.hero == i,
                !p.heroOwned(i),
                p.hero == i ? const Color(0xFF10131A) : Colors.white70,
                p.hero == i ? Color(kHeroes[i].color) : Colors.white10,
                () => setState(() => p.hero = i),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(cur.desc,
            style: const TextStyle(fontSize: 12, color: Colors.white54)),
      ],
    );
  }

  Widget _chip(String label, bool sel, bool locked, Color fg, Color bg,
      VoidCallback onPick) {
    return GestureDetector(
      onTap: locked ? null : onPick,
      child: Opacity(
        opacity: locked ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (locked)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.lock, size: 12, color: Colors.white70),
                ),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13, color: fg)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fireMode(Profile p) {
    Widget opt(String label, bool val) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => p.fireAuto = val),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.fireAuto == val ? kAccent : Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: p.fireAuto == val
                          ? const Color(0xFF10131A)
                          : Colors.white70)),
            ),
          ),
        );
    return Row(children: [opt('AUTO', true), opt('SINGLE', false)]);
  }

  Widget _controls(Profile p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('Left-handed (swap sticks)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Switch(
              value: p.leftHanded,
              activeThumbColor: kAccent,
              onChanged: (v) => setState(() => p.leftHanded = v),
            ),
          ],
        ),
        _slider('Stick size', p.stickScale, 0.8, 1.35,
            (v) => setState(() => p.stickScale = v)),
        _slider('Stick opacity', p.stickOpacity, 0.5, 1.4,
            (v) => setState(() => p.stickOpacity = v)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ControlsEditor()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: kSafeEdge.withValues(alpha: 0.12),
              border: Border.all(color: kSafeEdge.withValues(alpha: 0.7)),
            ),
            child: const Text('✥  CUSTOMISE CONTROL PLACEMENT',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: kSafeEdge)),
          ),
        ),
      ],
    );
  }

  Widget _slider(
      String label, double val, double min, double max, ValueChanged<double> onCh) {
    return Row(
      children: [
        SizedBox(
            width: 96,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Colors.white70))),
        Expanded(
          child: Slider(
            value: val.clamp(min, max),
            min: min,
            max: max,
            activeColor: kAccent,
            onChanged: onCh,
          ),
        ),
      ],
    );
  }

  Widget _stats(Profile p) {
    Widget stat(String v, String l) => Column(
          children: [
            Text(v,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, color: kAccent)),
            Text(l, style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        );
    final wr = (p.winRate * 100).toStringAsFixed(0);
    final best = p.bestPlacement == 0 ? '—' : '#${p.bestPlacement}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          stat('${p.matches}', 'MATCHES'),
          stat('${p.wins}', 'WINS'),
          stat('$wr%', 'WIN RATE'),
          stat('${p.kills}', 'KILLS'),
          stat(best, 'BEST'),
        ],
      ),
    );
  }
}

// Draws the customized operator into a widget (start screen + profile preview).
class OperatorPreviewPainter extends CustomPainter {
  final Color outfit;
  final Color skin;
  final int accessory;
  final WeaponId weapon;
  OperatorPreviewPainter({
    required this.outfit,
    required this.skin,
    required this.accessory,
    required this.weapon,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()..style = PaintingStyle.stroke;
    final center = Offset(size.width * 0.42, size.height * 0.5);
    final r = size.height * 0.26;
    canvas.drawOval(
        Rect.fromCenter(
            center: center.translate(3, r * 0.7),
            width: r * 2.1,
            height: r * 0.8),
        fill..color = const Color(0x33000000));
    drawOperator(canvas, center, r, 0, 0, outfit, skin, accessory, weapon,
        fill: fill,
        stroke: stroke,
        hero: Profile.instance.hero.clamp(0, kHeroes.length - 1));
  }

  @override
  bool shouldRepaint(covariant OperatorPreviewPainter old) =>
      old.outfit != outfit ||
      old.skin != skin ||
      old.accessory != accessory ||
      old.weapon != weapon;
}

// ============================================================
//  Daily missions screen
// ============================================================
class MissionsOverlay extends StatefulWidget {
  final RoyaleGame game;
  const MissionsOverlay({super.key, required this.game});

  @override
  State<MissionsOverlay> createState() => _MissionsOverlayState();
}

class _MissionsOverlayState extends State<MissionsOverlay> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    Profile.instance.ensureMissions();
    // live countdown to the daily reset (next local midnight)
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _claim(int i) {
    if (Profile.instance.claimMission(i) != null) setState(() {});
  }

  String _refreshIn() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final d = midnight.difference(now);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = Profile.instance;
    return Container(
      color: const Color(0xFF07090E),
      child: Column(
        children: [
          metaHeader(context, subtitle: 'DAILY OPERATIONS'),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('DAILY MISSIONS',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1)),
                const Spacer(),
                Icon(Icons.schedule,
                    size: 15, color: Colors.white.withValues(alpha: 0.5)),
                const SizedBox(width: 5),
                Text('REFRESHES IN ${_refreshIn()}',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              children: [
                for (var i = 0; i < p.missions.length; i++)
                  _missionCard(i, p.missions[i]),
              ],
            ),
          ),
          MetaNav(game: widget.game, active: Screen.missions),
        ],
      ),
    );
  }

  Widget _missionCard(int i, Mission m) {
    final frac = (m.progress / m.target).clamp(0.0, 1.0);
    final ready = m.done && !m.claimed;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: ready
                ? kAccent
                : (m.claimed ? Colors.white10 : Colors.white12),
            width: ready ? 1.5 : 1),
        boxShadow: ready
            ? [
                BoxShadow(
                    color: kAccent.withValues(alpha: 0.18),
                    blurRadius: 20,
                    spreadRadius: -6)
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.claimed
                        ? 'MISSION COMPLETE'
                        : (m.done ? 'OBJECTIVE CLEARED' : 'ACTIVE OBJECTIVE'),
                        style: TextStyle(
                            color: (m.claimed ? const Color(0xFF57E389) : kAccent)
                                .withValues(alpha: 0.85),
                            fontSize: 10,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 5),
                    Text(m.desc,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            height: 1.25)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFFFFD36B).withValues(alpha: 0.5)),
                ),
                child: Text('🪙 ${m.rewardCoins}',
                    style: const TextStyle(
                        color: Color(0xFFFFD36B),
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  m.claimed
                      ? 'MISSION COMPLETED'
                      : (m.done ? 'READY TO CLAIM' : 'MISSION PROGRESS'),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700)),
              Text('${m.progress} / ${m.target}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 9,
              backgroundColor: Colors.black.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation(
                  m.claimed ? const Color(0xFF57E389) : kAccent),
            ),
          ),
          if (ready) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => _claim(i),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  gradient:
                      const LinearGradient(colors: [Color(0xFFFFD36B), kAccent]),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: kAccent.withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: -3)
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('CLAIM REWARD',
                        style: TextStyle(
                            color: Color(0xFF10131A),
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: 1)),
                    SizedBox(width: 8),
                    Icon(Icons.card_giftcard,
                        color: Color(0xFF10131A), size: 18),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
//  Shop — spend coins on premium skins, accessories, weapons
// ============================================================
class ShopOverlay extends StatefulWidget {
  final RoyaleGame game;
  const ShopOverlay({super.key, required this.game});

  @override
  State<ShopOverlay> createState() => _ShopOverlayState();
}

class _ShopOverlayState extends State<ShopOverlay> {
  void _buy(String id) => setState(() => Profile.instance.buy(id));

  @override
  Widget build(BuildContext context) {
    final p = Profile.instance;
    final skins = [
      for (var i = 0; i < kOutfitColors.length; i++)
        if (!Profile.isFree('o$i'))
          _item(
            _dot(Color(kOutfitColors[i])),
            'Skin ${i + 1}',
            'o$i',
          ),
    ];
    final accs = [
      for (var i = 0; i < kAccessoryNames.length; i++)
        if (!Profile.isFree('a$i'))
          _item(_dot(const Color(0xFF6A7A9A)), kAccessoryNames[i], 'a$i'),
    ];
    final wpns = [
      for (final w in kWeaponOrder)
        if (!Profile.isFree('w${w.index}'))
          _item(_dot(kWeapons[w]!.color), kWeapons[w]!.name, 'w${w.index}'),
    ];
    final heroes = [
      for (var i = 0; i < kHeroes.length; i++)
        if (!Profile.isFree('h$i'))
          _item(_dot(Color(kHeroes[i].color)),
              '${kHeroes[i].name} · ${kHeroes[i].desc.split(' — ').first}', 'h$i'),
    ];
    final evos = [
      for (var i = 0; i < kHeroes.length; i++)
        if (p.heroOwned(i))
          _item(_dot(Color(kHeroes[i].color)),
              '${kHeroes[i].name} — Top Form ★', 'e$i'),
    ];
    return Container(
      color: const Color(0xFF07090E),
      child: Column(
        children: [
          metaHeader(context, subtitle: 'SUPPLY HUB'),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
            child: Row(
              children: [
                const Text('ARMORY',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD36B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFFFFD36B).withValues(alpha: 0.5)),
                  ),
                  child: Text('🪙  ${p.coins}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFFFD36B),
                          fontSize: 14)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              children: [
                _section('HEROES', heroes),
                _section('EVOLUTIONS', evos),
                _section('SKINS', skins),
                _section('ACCESSORIES', accs),
                _section('WEAPONS', wpns),
                Text('Buy once — then equip it in your Profile.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 12)),
              ],
            ),
          ),
          MetaNav(game: widget.game, active: Screen.shop),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 10)
        ],
      ));

  Widget _section(String title, List<Widget> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 6),
          child: Row(
            children: [
              Container(width: 4, height: 15, color: kAccent),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
            ],
          ),
        ),
        ...items,
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _item(Widget lead, String name, String id) {
    final p = Profile.instance;
    final owned = p.owns(id);
    final cost = p.costOf(id);
    final can = p.coins >= cost;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          lead,
          const SizedBox(width: 12),
          Expanded(
              child: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.w800))),
          if (owned)
            const Text('OWNED',
                style: TextStyle(
                    color: Color(0xFF8FE07A),
                    fontWeight: FontWeight.w800,
                    fontSize: 12))
          else
            GestureDetector(
              onTap: can ? () => _buy(id) : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: can ? kAccent : Colors.white12,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$cost 🪙',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color:
                            can ? const Color(0xFF10131A) : Colors.white38)),
              ),
            ),
        ],
      ),
    );
  }
}
