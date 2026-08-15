import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Geometry of the ZONE ROYALE mark, in a -0.5..0.5 unit square.
///
/// It is shared between the Flutter painter and `tool/gen_icon.dart`, so the
/// launcher icon and the in-app logo are literally the same shape — they can
/// never drift apart.
class ZrMark {
  /// Outline of the shield, as a closed polyline (curves approximated with
  /// segments so the icon generator can test distance to it cheaply).
  static const List<Offset> shield = [
    Offset(-0.35, -0.40),
    Offset(0.35, -0.40),
    Offset(0.35, 0.02),
    Offset(0.31, 0.16),
    Offset(0.23, 0.28),
    Offset(0.12, 0.37),
    Offset(0.0, 0.43),
    Offset(-0.12, 0.37),
    Offset(-0.23, 0.28),
    Offset(-0.31, 0.16),
    Offset(-0.35, 0.02),
  ];

  /// The Z, as three thick strokes — Z for Zone. A letterform is the most
  /// recognisable thing you can put in a small icon, and it survives being
  /// shrunk to a launcher tile in a way a fine crosshair never does.
  static const double zHalf = 0.046;
  static const List<List<Offset>> zStrokes = [
    [Offset(-0.165, -0.185), Offset(0.165, -0.185)],
    [Offset(0.165, -0.185), Offset(-0.165, 0.165)],
    [Offset(-0.165, 0.165), Offset(0.165, 0.165)],
  ];

  /// Scope ticks either side of the shield.
  static const double tickHalf = 0.020;
  static const double tickNear = 0.385;
  static const double tickFar = 0.455;

  static const double stroke = 0.055; // outline thickness
  static const Offset ringC = Offset(0, -0.03);
  static const double ringR = 0.185;
  static const double ringStroke = 0.05;
  static const double tickIn = 0.10; // ticks start here…
  static const double tickOut = 0.30; // …and end here
  static const double starLong = 0.10;
  static const double starShort = 0.032;

  /// The two ribbon notches that break the top edge (the "medal" cue).
  static const double notchW = 0.075;
  static const double notchH = 0.10;
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

    final fill = Paint()..color = color;

    // ---- solid shield with the Z knocked out of it ----
    //
    // The old mark was an outlined shield holding a crosshair ring and a
    // four-point star: four thin shapes that turn to mush at launcher size.
    // A filled silhouette with one bold letter cut through it reads at any
    // scale, and it is the same geometry tool/gen_icon.dart bakes into the
    // launcher icon — so the app and the home screen can never drift apart.
    final mark = Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(ZrMark.shieldPath(), Offset.zero);

    // ribbon notches punched through the top edge
    for (final sgn in const [-1.0, 1.0]) {
      mark.addRect(Rect.fromLTWH(
          sgn > 0 ? ZrMark.notchX : -ZrMark.notchX - ZrMark.notchW,
          -0.41,
          ZrMark.notchW,
          ZrMark.notchH + 0.01));
    }

    // The Z as real capsule geometry — a quad plus round ends per stroke,
    // unioned. That is exactly the shape tool/gen_icon.dart tests for
    // (distance-to-segment <= half thickness), so the drawn emblem and the
    // baked launcher icon are the same mark to the pixel.
    Path capsule(Offset a, Offset b, double t) {
      var out = Path()..addOval(Rect.fromCircle(center: a, radius: t));
      out = Path.combine(PathOperation.union, out,
          Path()..addOval(Rect.fromCircle(center: b, radius: t)));
      final d = b - a;
      final len = d.distance;
      final n = Offset(-d.dy, d.dx) / len * t;
      final quad = Path()
        ..moveTo(a.dx + n.dx, a.dy + n.dy)
        ..lineTo(b.dx + n.dx, b.dy + n.dy)
        ..lineTo(b.dx - n.dx, b.dy - n.dy)
        ..lineTo(a.dx - n.dx, a.dy - n.dy)
        ..close();
      return Path.combine(PathOperation.union, out, quad);
    }

    var z = Path();
    for (final st in ZrMark.zStrokes) {
      z = Path.combine(
          PathOperation.union, z, capsule(st[0], st[1], ZrMark.zHalf));
    }
    canvas.drawPath(
        Path.combine(PathOperation.difference, mark, z), fill);

    // scope ticks flanking the shield, so it still reads as a sight
    for (final sgn in const [-1.0, 1.0]) {
      canvas.drawRect(
          Rect.fromLTRB(
              sgn > 0 ? ZrMark.tickNear : -ZrMark.tickFar,
              -ZrMark.tickHalf,
              sgn > 0 ? ZrMark.tickFar : -ZrMark.tickNear,
              ZrMark.tickHalf),
          fill);
    }

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
            child: Text('ZONE ROYALE',
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
          Text('ZONE ROYALE',
              style: ZR.display(size * 0.125, color: ZR.primary, spacing: 0.5)),
          SizedBox(height: size * 0.05),
        ],
      ),
    );
  }
}
