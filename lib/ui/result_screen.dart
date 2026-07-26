import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/config.dart';
import '../game/profile.dart';
import 'shell.dart';
import 'theme.dart';

/// Everything the end screen needs, from either mode.
class MatchResult {
  final bool won;
  /// 'SOLO MATCH', 'CUSTOM ROOM', 'QUICK MATCH' — stencilled on the card.
  final String mode;
  /// '#1' / '#9' — the big number. Null hides it (round-based rooms).
  final String? placement;
  final String headline; // WINNER WINNER / ELIMINATED / MATCH OVER
  final String subtitle; // CHICKEN DINNER / ZONE SECTOR CLEARED / <name> WINS
  final List<(String, String)> stats; // label → value, up to 4
  final int xp;
  final int coins;
  final int levels;
  /// Show the MVP flourish — top of the lobby on kills.
  final bool mvp;
  const MatchResult({
    required this.won,
    required this.mode,
    required this.headline,
    required this.subtitle,
    required this.stats,
    this.placement,
    this.xp = 0,
    this.coins = 0,
    this.levels = 0,
    this.mvp = false,
  });
}

/// THE end screen — one landscape layout, used by the solo match and by custom
/// room / quick match.
///
/// It deliberately does not scroll. A results screen you have to drag to read
/// is a results screen nobody reads: two columns, everything on one page, at
/// any screen size. The left column is the shareable card; the right column is
/// the debrief and the rewards.
class MatchResultView extends StatefulWidget {
  final MatchResult result;
  /// Wrap the shareable card, so the screenshot is just the card.
  final GlobalKey cardKey;
  final VoidCallback? onBack;
  final List<Widget> actions;
  const MatchResultView({
    super.key,
    required this.result,
    required this.cardKey,
    required this.actions,
    this.onBack,
  });

  @override
  State<MatchResultView> createState() => _MatchResultViewState();
}

class _MatchResultViewState extends State<MatchResultView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..forward();

  @override
  void initState() {
    super.initState();
    if (widget.result.won) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final accent = r.won ? ZR.primary : ZR.danger;
    return TacticalBackdrop(
      // top: true here, unlike the menu screens — this layout starts with a
      // headline on the first line, so it has to clear the status bar.
      child: SafeArea(
        bottom: false,
        child: ZrCanvas(
          designHeight: 400,
          child: Stack(
            children: [
              // celebration behind everything, only on a win
              if (r.won)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (_, _) =>
                          CustomPaint(painter: _CelebrationPainter(_c.value)),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Column(
                  children: [
                    _header(accent),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 5, child: _card(accent)),
                          const SizedBox(width: 12),
                          Expanded(flex: 4, child: _debrief(accent)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(height: 46, child: Row(children: widget.actions)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(Color accent) {
    final r = widget.result;
    return Row(
      children: [
        if (widget.onBack != null)
          GestureDetector(
            onTap: widget.onBack,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(
                width: 34,
                height: 30,
                child: Icon(Icons.arrow_back, color: Colors.white70, size: 20)),
          ),
        Text('MATCH SUMMARY', style: ZR.display(24, spacing: 1.6)),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: accent.withValues(alpha: 0.6)),
          ),
          child: Text(r.mode.toUpperCase(),
              style: ZR.mono(9, color: accent, spacing: 1.2)),
        ),
        const Spacer(),
        if (r.mvp)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: ZR.cta(radius: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.workspace_premium,
                  size: 13, color: Color(0xFF10131A)),
              const SizedBox(width: 5),
              Text('MVP',
                  style: ZR.display(15,
                      color: const Color(0xFF10131A), spacing: 1.4)),
            ]),
          ),
      ],
    );
  }

  /// The shareable card. Kept to one column and one glance.
  Widget _card(Color accent) {
    final r = widget.result;
    final p = Profile.instance;
    final hero = kHeroes[p.hero.clamp(0, kHeroes.length - 1)];
    return RepaintBoundary(
      key: widget.cardKey,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [accent.withValues(alpha: 0.18), const Color(0xFF05070C)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          // stretch, so the operator panel gets a real height — a CustomPaint
          // with no child takes constraints.smallest, and a centred Row child
          // is given a loose one, which collapses it to nothing.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('ZONE ROYALE  //  ${r.won ? 'VICTORY' : 'DEFEAT'}',
                      style: ZR.mono(9, color: accent, spacing: 2.4)),
                  if (r.placement != null)
                    Text(r.placement!,
                        style: ZR.display(64,
                            color: accent, spacing: 1, height: 0.95)),
                  Text(r.headline,
                      style: ZR.display(28,
                          color: r.won ? Colors.white : accent, spacing: 1.6)),
                  Text(r.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZR.mono(9, color: Colors.white38, spacing: 2.6)),
                ],
              ),
            ),
            // the operator exactly as they look in the match
            SizedBox(
              width: 118,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                clipBehavior: Clip.antiAlias,
                child: CustomPaint(
                  painter: OperatorStagePainter(
                    outfit: p.outfitColor,
                    skin: p.skinColor,
                    accessory: p.accessory,
                    weapon: p.startWeapon,
                    hero: p.hero,
                    accent: Color(hero.color),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _debrief(Color accent) {
    final r = widget.result;
    final p = Profile.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ZrSectionLabel('DEBRIEF'),
        const SizedBox(height: 6),
        Expanded(
          child: GridView.count(
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 2.5,
            children: [
              for (final (label, value) in r.stats)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  alignment: Alignment.centerLeft,
                  decoration: ZR.panel(radius: 9),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label.toUpperCase(),
                          style: ZR.mono(8, color: Colors.white38)),
                      Text(value, style: ZR.display(22, spacing: 0.5)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (r.xp > 0 || r.coins > 0) ...[
          const SizedBox(height: 8),
          // rewards count up, so getting paid feels like getting paid
          AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final k = Curves.easeOutCubic
                  .transform((_c.value * 2.2).clamp(0.0, 1.0));
              return Row(
                children: [
                  Expanded(
                    child: _reward(Icons.military_tech,
                        '+${(r.xp * k).round()} XP', ZR.secondary),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _reward(Icons.monetization_on,
                        '+${(r.coins * k).round()}', ZR.primary),
                  ),
                  if (r.levels > 0) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: _reward(Icons.arrow_upward,
                          'LVL UP ×${r.levels}', ZR.success),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Text('LV ${p.level}',
                style: ZR.display(16, color: p.rankColor, spacing: 0.6)),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: p.xpFraction,
                  minHeight: 8,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation(p.rankColor),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(p.rank, style: ZR.display(15, color: p.rankColor)),
          ],
        ),
      ],
    );
  }

  Widget _reward(IconData icon, String label, Color color) => Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZR.display(17, color: color)),
          ),
        ]),
      );
}

/// Light rays and rising confetti behind a win. Deterministic, so it costs
/// nothing but a handful of transforms per frame.
class _CelebrationPainter extends CustomPainter {
  final double t;
  const _CelebrationPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.28, size.height * 0.5);
    // slow sweeping rays
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var i = 0; i < 12; i++) {
      final a = i * (math.pi * 2 / 12) + t * 0.5;
      final p = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a - 0.05) * size.width,
            c.dy + math.sin(a - 0.05) * size.width)
        ..lineTo(c.dx + math.cos(a + 0.05) * size.width,
            c.dy + math.sin(a + 0.05) * size.width)
        ..close();
      canvas.drawPath(
          p, Paint()..color = ZR.primary.withValues(alpha: 0.035));
    }
    // confetti drifting upward and fading
    const n = 40;
    for (var i = 0; i < n; i++) {
      final seed = i * 53.0;
      final phase = ((t * 0.5) + i / n) % 1.0;
      final x = (seed * 17.3) % size.width;
      final y = size.height * (1.05 - phase * 1.15) +
          math.sin(phase * 7 + i) * 12;
      final col = switch (i % 3) {
        0 => ZR.primary,
        1 => ZR.secondary,
        _ => Colors.white,
      };
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(phase * 9 + i);
      canvas.drawRect(
          const Rect.fromLTWH(-2.5, -1.4, 5, 2.8),
          Paint()
            ..color = col.withValues(
                alpha: (1 - phase).clamp(0.0, 1.0) * 0.75));
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CelebrationPainter old) => old.t != t;
}
