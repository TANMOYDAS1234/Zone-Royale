import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'logo.dart';
import 'theme.dart';

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
/// Boot sequence: the emblem draws itself inside a closing dashed orbit, the
/// wordmark ignites, then a comm-link progress bar runs while telemetry ticks
/// underneath. Matches the launch screen in the UI kit.
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  static const _steps = [
    'INITIALISING TACTICAL CORE...',
    'LOADING OPERATOR PROFILE...',
    'ESTABLISHING SECURE COMM-LINK...',
    'SYNCING ARMOURY MANIFEST...',
    'DEPLOYMENT READY',
  ];

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2800))
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
        final emblemIn = Curves.easeOutBack.transform(_seg(0.04, 0.42));
        final orbit = Curves.easeInOut.transform(_seg(0.10, 0.62));
        final textIn = Curves.easeOut.transform(_seg(0.30, 0.62));
        final load = Curves.easeInOut.transform(_seg(0.34, 0.97));
        final fadeOut = _seg(0.92, 1.0);
        final step = _steps[(load * (_steps.length - 1)).round()];
        final ms = (0.30 + (1 - load) * 2.4).toStringAsFixed(2);

        return Opacity(
          opacity: 1 - fadeOut,
          child: TacticalBackdrop(
            cell: 92,
            child: LayoutBuilder(builder: (context, box) {
              // everything is a fraction of the available height, so the boot
              // screen fits a short landscape phone and a tall tablet alike
              final h = box.maxHeight;
              final w = box.maxWidth;
              final emblem = (h * 0.36).clamp(84.0, 190.0);
              final word = (h * 0.13).clamp(26.0, 58.0);
              final barW = (w * 0.62).clamp(240.0, 560.0);
              return Stack(
              fit: StackFit.expand,
              children: [
                const _CornerBrackets(),
                Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ---- emblem inside the closing orbit ----
                        Transform.scale(
                          scale: 0.72 + 0.28 * emblemIn,
                          child: Opacity(
                            opacity: emblemIn.clamp(0.0, 1.0),
                            child: SizedBox(
                              width: emblem,
                              height: emblem,
                              child: CustomPaint(
                                painter: ZrEmblemPainter(
                                    sweep: orbit, showOrbit: true),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: h * 0.035),
                        // ---- wordmark ----
                        Opacity(
                          opacity: textIn,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..scaleByDouble(0.94 + 0.06 * textIn,
                                  0.94 + 0.06 * textIn, 1, 1),
                            child: ZrLogo(height: word, showEmblem: false),
                          ),
                        ),
                        SizedBox(height: h * 0.02),
                        Opacity(
                          opacity: textIn,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                  width: 46,
                                  height: 1,
                                  color: Colors.white.withValues(alpha: 0.25)),
                              const SizedBox(width: 14),
                              Text('10 DROP IN. 1 WALKS OUT.',
                                  style: ZR.mono(12,
                                      color: Colors.white70, spacing: 3)),
                              const SizedBox(width: 14),
                              Container(
                                  width: 46,
                                  height: 1,
                                  color: Colors.white.withValues(alpha: 0.25)),
                            ],
                          ),
                        ),
                        SizedBox(height: h * 0.055),
                        // ---- comm-link progress ----
                        Opacity(
                          opacity: _seg(0.32, 0.5),
                          child: SizedBox(
                            width: barW,
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                        width: 7,
                                        height: 7,
                                        color: ZR.primary),
                                    const SizedBox(width: 10),
                                    Text(step,
                                        style: ZR.mono(12,
                                            color: Colors.white70,
                                            spacing: 1.5)),
                                    const Spacer(),
                                    Text('${ms}ms',
                                        style: ZR.mono(12,
                                            color: Colors.white38)),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Stack(
                                  children: [
                                    Container(
                                        height: 3,
                                        decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.10),
                                            borderRadius:
                                                BorderRadius.circular(2))),
                                    FractionallySizedBox(
                                      widthFactor: load,
                                      child: Container(
                                        height: 3,
                                        decoration: BoxDecoration(
                                          color: ZR.primary,
                                          borderRadius:
                                              BorderRadius.circular(2),
                                          boxShadow: [
                                            BoxShadow(
                                                color: ZR.primary.withValues(
                                                    alpha: 0.7),
                                                blurRadius: 10),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                // telemetry row
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('LAT: 34.0522° N',
                                        style: ZR.mono(10,
                                            color: Colors.white24)),
                                    Text('LNG: 118.2437° W',
                                        style: ZR.mono(10,
                                            color: Colors.white24)),
                                    Text('ENC_MODE: RSA_4096',
                                        style: ZR.mono(10,
                                            color: Colors.white24)),
                                    Text('VER: 2.1.0_PROD',
                                        style: ZR.mono(10,
                                            color: Colors.white24)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // ---- server status chip ----
                Positioned(
                  left: 20,
                  bottom: 18,
                  child: Opacity(
                    opacity: _seg(0.5, 0.75),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
                      decoration: BoxDecoration(
                        color: ZR.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ZR.line),
                      ),
                      // The amber edge is a foreground strip: a border with
                      // different colours per side cannot coexist with a
                      // corner radius, and Flutter abandons painting the rest
                      // of the surrounding stack when it hits one.
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [ZR.primary, ZR.primary, Color(0x00000000)],
                          stops: [0.0, 0.012, 0.012],
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.shield_outlined,
                                size: 16, color: Colors.white70),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('SERVER STATUS',
                                  style:
                                      ZR.mono(9, color: Colors.white38)),
                              Text('OPTIMAL_OPERATIONAL',
                                  style: ZR.mono(12,
                                      color: ZR.success,
                                      weight: FontWeight.w700)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 20,
                  bottom: 22,
                  child: Opacity(
                    opacity: _seg(0.5, 0.75),
                    child: Text('© ZONE ROYALE',
                        style: ZR.mono(11, color: Colors.white24, spacing: 2)),
                  ),
                ),
              ],
            );
            }),
          ),
        );
      },
    );
  }
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
