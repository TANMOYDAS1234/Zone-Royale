import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';
import '../i18n/strings.dart';

/// Geometry of the ZONE ROYALE mark, in a -0.5..0.5 unit square.
///
/// It is shared between the Flutter painter and `tool/gen_icon.dart`, so the
/// launcher icon and the in-app logo are literally the same shape — they can
/// never drift apart.
class ZrMark {
  /// Outline of the shield, as a closed polyline (curves approximated with
  /// segments so the icon generator can test distance to it cheaply).
  static const List<Offset> shield = [
    Offset(-0.34, -0.40),
    Offset(0.34, -0.40),
    Offset(0.34, -0.02),
    Offset(0.31, 0.12),
    Offset(0.24, 0.25),
    Offset(0.13, 0.37),
    Offset(0.0, 0.46),
    Offset(-0.13, 0.37),
    Offset(-0.24, 0.25),
    Offset(-0.31, 0.12),
    Offset(-0.34, -0.02),
  ];

  static const double stroke = 0.055; // outline thickness
  static const Offset ringC = Offset(0, -0.03);
  static const double ringR = 0.185;
  static const double ringStroke = 0.05;
  static const double tickIn = 0.10; // ticks start here…
  static const double tickOut = 0.30; // …and end here
  static const double starLong = 0.10;
  static const double starShort = 0.032;

  /// The two ribbon notches that break the top edge (the "medal" cue).
  static const double notchW = 0.085;
  static const double notchH = 0.13;
  static const double notchX = 0.115; // distance from centre to inner edge

  static Path shieldPath() {
    final p = Path()..moveTo(shield.first.dx, shield.first.dy);
    for (final o in shield.skip(1)) {
      p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }
}

/// Paints the ZONE ROYALE emblem: an outlined shield holding a crosshair ring
/// with a four-point star, and two ribbon notches across the top edge.
class ZrEmblemPainter extends CustomPainter {
  final Color color;
  /// 0..1 — how far the dashed orbit ring has closed (splash animation).
  final double sweep;
  final bool showOrbit;

  const ZrEmblemPainter({
    this.color = ZR.primary,
    this.sweep = 1.0,
    this.showOrbit = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ZrMark.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = color;
    final fill = Paint()..color = color;

    // ---- shield outline ----
    canvas.drawPath(ZrMark.shieldPath(), line);

    // ---- ribbon notches across the top edge ----
    final clear = Paint()..blendMode = BlendMode.clear;
    canvas.saveLayer(const Rect.fromLTRB(-0.6, -0.6, 0.6, 0.6), Paint());
    canvas.drawPath(ZrMark.shieldPath(), line);
    for (final sgn in const [-1.0, 1.0]) {
      canvas.drawRect(
          Rect.fromLTWH(
              sgn > 0 ? ZrMark.notchX : -ZrMark.notchX - ZrMark.notchW,
              -0.40 - ZrMark.stroke,
              ZrMark.notchW,
              ZrMark.notchH),
          clear);
    }
    canvas.restore();
    // the notch uprights
    for (final sgn in const [-1.0, 1.0]) {
      canvas.drawLine(
          Offset(sgn * ZrMark.notchX, -0.40),
          Offset(sgn * ZrMark.notchX, -0.40 + ZrMark.notchH),
          Paint()
            ..strokeWidth = ZrMark.stroke * 0.9
            ..strokeCap = StrokeCap.round
            ..color = color);
    }

    // ---- crosshair ring ----
    canvas.drawCircle(
        ZrMark.ringC,
        ZrMark.ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ZrMark.ringStroke
          ..color = color);
    // cardinal ticks
    final tick = Paint()
      ..strokeWidth = ZrMark.ringStroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(ZrMark.ringC + d * ZrMark.tickIn,
          ZrMark.ringC + d * ZrMark.tickOut, tick);
    }

    // ---- four-point star ----
    final star = Path();
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final r = i.isEven ? ZrMark.starLong : ZrMark.starShort;
      final p = ZrMark.ringC + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    canvas.drawPath(star, fill);

    // ---- optional dashed orbit (splash) ----
    if (showOrbit) {
      final orbit = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.016
        ..color = color.withValues(alpha: 0.55);
      const dashes = 46;
      final lit = (dashes * sweep.clamp(0.0, 1.0)).floor();
      for (var i = 0; i <= lit && i < dashes; i++) {
        final a0 = -math.pi / 2 + i * (math.pi * 2 / dashes);
        canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: 0.60), a0,
            math.pi * 2 / dashes * 0.55, false, orbit);
      }
      canvas.drawCircle(
          Offset.zero,
          0.53,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.006
            ..color = color.withValues(alpha: 0.22));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ZrEmblemPainter old) =>
      old.color != color || old.sweep != sweep || old.showOrbit != showOrbit;
}

/// Emblem + wordmark, the way the logo is locked up in the app bar.
class ZrLogo extends StatelessWidget {
  final double height;
  final bool showEmblem;
  final bool showWord;
  const ZrLogo(
      {super.key,
      this.height = 34,
      this.showEmblem = true,
      this.showWord = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showEmblem)
          SizedBox(
            width: height,
            height: height,
            child: const CustomPaint(painter: ZrEmblemPainter()),
          ),
        if (showEmblem && showWord) SizedBox(width: height * 0.28),
        if (showWord)
          // Italic condensed caps with a warm glow — the wordmark from the kit.
          Transform(
            transform: Matrix4.skewX(-0.16),
            child: Text(trUp('ZONE ROYALE'),
                style: ZR.display(height * 0.9,
                        color: ZR.primaryLite, spacing: 1.5)
                    .copyWith(shadows: [
                  Shadow(
                      color: ZR.primary.withValues(alpha: 0.55),
                      blurRadius: height * 0.5),
                ])),
          ),
      ],
    );
  }
}

/// The boxed app-icon lockup (emblem over the wordmark inside a plate).
class ZrLogoPlate extends StatelessWidget {
  final double size;
  const ZrLogoPlate({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1A212C),
        borderRadius: BorderRadius.circular(size * 0.18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: size * 0.58,
            height: size * 0.58,
            child: const CustomPaint(painter: ZrEmblemPainter()),
          ),
          Text(trUp('ZONE ROYALE'),
              style: ZR.display(size * 0.125, color: ZR.primary, spacing: 0.5)),
          SizedBox(height: size * 0.05),
        ],
      ),
    );
  }
}
