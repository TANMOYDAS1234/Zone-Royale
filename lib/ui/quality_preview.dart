import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/char_art.dart';
import '../game/config.dart';
import '../game/profile.dart';
import 'theme.dart';

/// A live, running sample of the graphics-fidelity setting.
///
/// It renders with exactly the same code paths the match does — the same
/// operator art, the same muzzle flash, the same tracer, the same contact
/// shadow, the same drifting dust — so switching SMOOTH / BALANCED / ULTRA in
/// the settings shows you the real difference instead of asking you to start a
/// match and guess.
class QualityPreview extends StatefulWidget {
  final int quality;
  final double height;
  const QualityPreview({super.key, required this.quality, this.height = 96});

  @override
  State<QualityPreview> createState() => _QualityPreviewState();
}

class _QualityPreviewState extends State<QualityPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = kQualities[widget.quality.clamp(0, kQualities.length - 1)];
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (_, _) => CustomPaint(
                painter: _QualityPreviewPainter(q, _c.value),
              ),
            ),
            Positioned(
              left: 8,
              top: 6,
              child: Text('LIVE SAMPLE  ·  ${q.name}',
                  style: ZR.mono(8, color: Colors.white38, spacing: 1)),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityPreviewPainter extends CustomPainter {
  final Quality q;
  /// 0→1 loop: a burst of fire, then a pause, then repeat.
  final double t;
  _QualityPreviewPainter(this.q, this.t);

  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  static double _hash(int x, int y) {
    var h = x * 374761393 + y * 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = Profile.instance;
    final time = t * 4; // seconds

    // ---- ground, at this level's detail --------------------------------
    canvas.drawRect(
        Offset.zero & size,
        _fill
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF161C28), Color(0xFF070A10)],
          ).createShader(Offset.zero & size));
    _fill.shader = null;

    final cell = 34.0 / q.detail.clamp(0.35, 1.4);
    for (var gx = 0; gx * cell < size.width + cell; gx++) {
      for (var gy = 0; gy * cell < size.height + cell; gy++) {
        final h = _hash(gx, gy);
        if (h < 0.45) {
          canvas.drawOval(
              Rect.fromCenter(
                  center: Offset(gx * cell + h * cell, gy * cell + h * cell),
                  width: 14 + h * 26,
                  height: 9 + h * 14),
              _fill..color = Colors.white.withValues(alpha: 0.022));
        }
        canvas.drawCircle(
            Offset(gx * cell + _hash(gy, gx) * cell,
                gy * cell + _hash(gx + 3, gy) * cell),
            0.9 + h * 1.1,
            _fill..color = Colors.white.withValues(alpha: 0.04));
      }
    }

    // ---- the operator, firing ------------------------------------------
    final me = Offset(size.width * 0.30, size.height * 0.62);
    final target = Offset(size.width * 0.82, size.height * 0.44);
    final aim = math.atan2(target.dy - me.dy, target.dx - me.dx);
    const r = 15.0;

    // contact shadow — the flat single pass at SMOOTH, layered above it
    if (q.shadows) {
      canvas.drawOval(
          Rect.fromCenter(
              center: me.translate(5, r * 0.7), width: r * 2.25, height: r * 0.95),
          _fill..color = const Color(0x4D000000));
      canvas.drawOval(
          Rect.fromCenter(
              center: me.translate(3, r * 0.5), width: r * 1.5, height: r * 0.6),
          _fill..color = const Color(0x3D000000));
    } else {
      canvas.drawOval(
          Rect.fromCenter(
              center: me.translate(2, r * 0.6), width: r * 1.7, height: r * 0.7),
          _fill..color = const Color(0x33000000));
    }

    drawOperator(canvas, me, r, aim, aim, p.outfitColor, p.skinColor,
        p.accessory, p.startWeapon,
        fill: _fill,
        stroke: _stroke,
        walk: 0,
        hero: p.hero,
        vest: true,
        helmet: true);

    // ---- the shot: three rounds down range every loop -------------------
    final w = kWeapons[p.startWeapon]!;
    for (var i = 0; i < 3; i++) {
      final phase = (t * 3 - i * 0.22) % 1.0;
      if (phase > 0.55) continue; // in the gap between bursts
      final k = phase / 0.55;
      final muzzle = me + Offset(math.cos(aim), math.sin(aim)) * (r * 2.15);
      final head = Offset.lerp(muzzle, target, k)!;
      final tail = Offset.lerp(muzzle, target, (k - 0.16).clamp(0.0, 1.0))!;

      if (q.bloom > 0) {
        canvas.drawLine(
            tail,
            head,
            Paint()
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
              ..color = w.color.withValues(alpha: 0.5 * q.bloom)
              ..strokeWidth = 7 * q.bloom
              ..strokeCap = StrokeCap.round);
      }
      canvas.drawLine(
          tail,
          head,
          _stroke
            ..color = w.color.withValues(alpha: 0.35)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round);
      canvas.drawLine(tail, head,
          _stroke..color = w.color..strokeWidth = 1.9);
      canvas.drawCircle(head, 1.9, _fill..color = Colors.white);

      // muzzle flash only while the round is leaving the barrel
      if (k < 0.16) {
        final f = 1 - k / 0.16;
        if (q.bloom > 0) {
          canvas.drawCircle(
              muzzle,
              22 * f * q.bloom,
              Paint()
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9)
                ..color =
                    const Color(0xFFFFB02E).withValues(alpha: 0.5 * f * q.bloom));
        }
        canvas.drawCircle(muzzle, 13 * f,
            _fill..color = const Color(0xFFFFC24B).withValues(alpha: 0.22 * f));
        canvas.drawCircle(muzzle, 5 * f,
            _fill..color = const Color(0xFFFFFDF0).withValues(alpha: 0.95 * f));
      }
    }

    // ---- impact sparks, scaled by the particle multiplier ----------------
    final sparks = (10 * q.fx).round().clamp(2, 18);
    final burst = (t * 3) % 1.0;
    if (burst < 0.4) {
      final f = 1 - burst / 0.4;
      for (var i = 0; i < sparks; i++) {
        final a = i * (math.pi * 2 / sparks) + t * 6;
        final d = (1 - f) * 22;
        final o = target + Offset(math.cos(a) * d, math.sin(a) * d * 0.7);
        if (q.bloom > 0) {
          canvas.drawCircle(
              o,
              4 * f * q.bloom,
              Paint()
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
                ..color =
                    const Color(0xFFFFB020).withValues(alpha: 0.5 * f * q.bloom));
        }
        canvas.drawCircle(
            o,
            1.8 * f,
            _fill
              ..color = (i.isEven
                      ? const Color(0xFFFFB020)
                      : const Color(0xFFFF5A2A))
                  .withValues(alpha: f));
      }
    }

    // ---- drifting dust ----------------------------------------------------
    if (q.weather) {
      final n = (18 * q.detail).round().clamp(5, 34);
      for (var i = 0; i < n; i++) {
        final seed = i * 37.0;
        final speed = 8 + (i % 5) * 5;
        final x = ((seed * 13.7 + time * speed) % (size.width + 40)) - 20;
        final y = (seed * 29.3 + math.sin(time * 0.5 + i) * 10) % size.height;
        canvas.drawCircle(Offset(x, y), 0.7 + (i % 4) * 0.4,
            _fill..color = Colors.white.withValues(alpha: 0.06 + (i % 3) * 0.02));
      }
    }

    // frame
    canvas.drawRect(
        Offset.zero & size,
        _stroke
          ..color = Colors.white12
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _QualityPreviewPainter old) =>
      old.t != t || old.q != q;
}
