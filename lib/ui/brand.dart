import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/config.dart';

/// The Zone Royale crosshair mark, drawn entirely in code (no image asset).
/// Two glowing scope rings + four tapered reticle blades + a centre dot on a
/// dark rounded tile — matches the app icon.
class ZoneLogo extends StatelessWidget {
  final double size;
  final bool tile; // draw the dark rounded background tile
  const ZoneLogo({super.key, this.size = 96, this.tile = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter(tile: tile)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final bool tile;
  _LogoPainter({required this.tile});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;

    if (tile) {
      final rect = Offset.zero & size;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.22)),
        Paint()..color = const Color(0xFF0A0A0F),
      );
      // warm radial glow behind the scope
      canvas.drawCircle(
        c,
        r * 0.8,
        Paint()
          ..shader = RadialGradient(
            colors: [const Color(0xFFFF7A1A).withValues(alpha: 0.55), Colors.transparent],
          ).createShader(Rect.fromCircle(center: c, radius: r * 0.8)),
      );
    }

    final gold = const Color(0xFFFFB02E);
    // outer ring (with soft glow underlay)
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16
        ..color = gold.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.11
        ..color = gold,
    );
    // inner ring
    canvas.drawCircle(
      c,
      r * 0.40,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.055
        ..color = gold,
    );

    // four white reticle blades (N/E/S/W): wide near the rings, tapering in
    final blade = Paint()..color = Colors.white;
    for (var i = 0; i < 4; i++) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(i * math.pi / 2);
      final outer = r * 0.74;
      final inner = r * 0.14;
      final wOut = r * 0.10;
      final wIn = r * 0.03;
      final path = Path()
        ..moveTo(-wOut, -outer)
        ..lineTo(wOut, -outer)
        ..lineTo(wIn, -inner)
        ..lineTo(-wIn, -inner)
        ..close();
      canvas.drawPath(path, blade);
      canvas.restore();
    }
    // centre dot
    canvas.drawCircle(c, r * 0.045, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => false;
}

/// Animated boot splash: the crosshair scales/fades in over a tactical grid with
/// corner brackets, the wordmark and tagline rise, and a loading bar fills.
/// Calls [onDone] when the intro finishes.
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600))
      ..forward();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _seg(double start, double end) =>
      ((_c.value - start) / (end - start)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final logoIn = Curves.easeOutBack.transform(_seg(0.05, 0.5));
        final textIn = Curves.easeOut.transform(_seg(0.35, 0.7));
        final load = Curves.easeInOut.transform(_seg(0.45, 0.98));
        final fadeOut = _seg(0.9, 1.0);
        return Opacity(
          opacity: 1 - fadeOut,
          child: Container(
            color: const Color(0xFF05070C),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const IgnorePointer(child: CustomPaint(painter: _GridPainter())),
                const _CornerBrackets(),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: 0.6 + 0.4 * logoIn,
                        child: Opacity(
                          opacity: logoIn.clamp(0.0, 1.0),
                          child: ZoneLogo(size: 128, tile: false),
                        ),
                      ),
                      const SizedBox(height: 26),
                      Opacity(
                        opacity: textIn,
                        child: Transform.translate(
                          offset: Offset(0, 16 * (1 - textIn)),
                          child: Column(
                            children: [
                              const Text('ZONE ROYALE',
                                  style: TextStyle(
                                      color: kAccent,
                                      fontSize: 40,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2,
                                      height: 1.0)),
                              const SizedBox(height: 8),
                              Text('10 DROP IN.  1 WALKS OUT.',
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      fontSize: 12,
                                      letterSpacing: 3,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // loading bar
                Positioned(
                  left: 40,
                  right: 40,
                  bottom: 90,
                  child: Opacity(
                    opacity: textIn,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('SYSTEM CHECK: OPTIMAL',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 10,
                                    letterSpacing: 1)),
                            Text('LOADING… ${(load * 100).round()}%',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 10,
                                    letterSpacing: 1)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: load,
                            minHeight: 6,
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            valueColor: const AlwaysStoppedAnimation(kAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 42) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 42) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _CornerBrackets extends StatelessWidget {
  const _CornerBrackets();
  @override
  Widget build(BuildContext context) {
    Widget bracket(Alignment a) => Align(
          alignment: a,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: CustomPaint(
                size: const Size(34, 34),
                painter: _BracketPainter(a)),
          ),
        );
    return IgnorePointer(
      child: Stack(children: [
        bracket(Alignment.topLeft),
        bracket(Alignment.topRight),
        bracket(Alignment.bottomLeft),
        bracket(Alignment.bottomRight),
      ]),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final Alignment a;
  _BracketPainter(this.a);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = kAccent.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final left = a.x < 0;
    final top = a.y < 0;
    final x0 = left ? 0.0 : size.width;
    final y0 = top ? 0.0 : size.height;
    final xh = left ? size.width : 0.0;
    final yv = top ? size.height : 0.0;
    canvas.drawLine(Offset(x0, y0), Offset(xh, y0), p);
    canvas.drawLine(Offset(x0, y0), Offset(x0, yv), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
