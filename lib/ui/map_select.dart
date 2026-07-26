import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/config.dart';
import '../game/profile.dart';
import '../game/sfx.dart';
import '../game/royale_game.dart';
import 'shell.dart';
import 'theme.dart';

/// Draws a miniature of a map theme — the real thing, generated with the same
/// cover mix the match uses (buildings / trees / walls / boulders, the theme's
/// ground palette). A photo would be prettier but a lie; this preview is
/// exactly what you drop into.
///
/// [choice] follows Profile.mapChoice: 0 = RANDOM, else kMapThemes[choice-1].
class MapThumbPainter extends CustomPainter {
  final int choice;
  final double detail;
  const MapThumbPainter(this.choice, {this.detail = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = choice <= 0;
    final theme = kMapThemes[
        rnd ? 0 : (choice - 1).clamp(0, kMapThemes.length - 1)];
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()..style = PaintingStyle.stroke;

    // ---- ground ----
    canvas.drawRect(
        Offset.zero & size,
        fill
          ..shader = RadialGradient(colors: [
            Color(theme.ground),
            Color(theme.groundEdge),
          ]).createShader(Offset.zero & size));
    fill.shader = null;

    if (rnd) {
      // RANDOM: show a quartered board with a slice of every theme
      for (var i = 0; i < kMapThemes.length; i++) {
        final t = kMapThemes[i];
        final r = Rect.fromLTWH(
            (i % 2) * size.width / 2,
            (i ~/ 2) * size.height / 2,
            size.width / 2,
            size.height / 2);
        canvas.drawRect(r, fill..color = Color(t.ground));
        _scatter(canvas, r, t, seed: i * 31, fill: fill, stroke: stroke);
      }
      canvas.drawLine(Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height), stroke
            ..color = Colors.black.withValues(alpha: 0.5)
            ..strokeWidth = 1.5);
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), stroke);
    } else {
      _scatter(canvas, Offset.zero & size, theme,
          seed: choice * 17, fill: fill, stroke: stroke);
    }

    // ---- gas ring hint ----
    canvas.drawCircle(
        size.center(Offset.zero),
        math.min(size.width, size.height) * 0.42,
        stroke
          ..color = ZR.secondary.withValues(alpha: 0.35)
          ..strokeWidth = 1.4);

    // vignette so text on top stays readable
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.55),
            ],
            stops: const [0.45, 1.0],
          ).createShader(Offset.zero & size));
  }

  /// Builds a REAL arena, not decoration: the same rules `_buildObstacles`
  /// uses in a match — long walls, crate clusters and bushes, in the counts
  /// this theme actually spawns — scaled into the preview box. What you see
  /// here is the kind of layout you drop into.
  void _scatter(Canvas canvas, Rect area, MapTheme theme,
      {required int seed, required Paint fill, required Paint stroke}) {
    // deterministic RNG so a map always previews the same way
    var st = seed * 9781 + 12345;
    double rnd() {
      st = (st * 1103515245 + 12345) & 0x7FFFFFFF;
      return st / 0x7FFFFFFF;
    }

    double rr(double lo, double hi) => lo + rnd() * (hi - lo);
    // work in world units (a 3200-unit arena) then map into the box
    const world = 3200.0;
    final k = area.width / world;
    final ky = area.height / world;
    Rect toBox(double x, double y, double w, double h) => Rect.fromLTWH(
        area.left + x * k, area.top + y * ky, w * k, h * ky);

    final density = (area.width / 260).clamp(0.5, 2.2);
    final walls = (14 * theme.wallMul * density).round();
    final crates = (16 * theme.crateMul * density).round();
    final bushes = (20 * theme.bushMul * density).round();

    // ---- roads / open lanes so the map reads as a place, not noise ----
    fill.color = Colors.white.withValues(alpha: 0.028);
    canvas.drawRect(
        toBox(0, world * 0.46, world, world * 0.08), fill);
    canvas.drawRect(
        toBox(world * 0.44, 0, world * 0.08, world), fill);

    // ---- buildings / long walls ----
    for (var i = 0; i < walls; i++) {
      final horizontal = rnd() < 0.5;
      final w = horizontal ? rr(160, 420) : rr(34, 52);
      final h = horizontal ? rr(34, 52) : rr(160, 420);
      final x = rr(120, world - 120 - w);
      final y = rr(120, world - 120 - h);
      final r = toBox(x, y, w, h);
      canvas.drawRect(r.translate(1.5, 2),
          fill..color = Colors.black.withValues(alpha: 0.5));
      canvas.drawRect(r, fill..color = Color(theme.border));
      canvas.drawRect(Rect.fromLTWH(r.left, r.top, r.width, 1.4),
          fill..color = Colors.white.withValues(alpha: 0.18));
    }

    // ---- crate clusters ----
    for (var i = 0; i < crates; i++) {
      final cx = rr(160, world - 160), cy = rr(160, world - 160);
      final n = 1 + (rnd() * 3).floor();
      for (var j = 0; j < n; j++) {
        final s = rr(30, 44);
        final r = toBox(cx + rr(-46, 46), cy + rr(-46, 46), s, s);
        canvas.drawRect(r.translate(1, 1.4),
            fill..color = Colors.black.withValues(alpha: 0.45));
        canvas.drawRect(r, fill..color = const Color(0xFF7C5C36));
      }
    }

    // ---- trees / undergrowth ----
    for (var i = 0; i < bushes; i++) {
      final s = rr(70, 120);
      final r = toBox(rr(120, world - 120 - s), rr(120, world - 120 - s), s, s);
      final c = r.center;
      final rad = r.width / 2;
      canvas.drawCircle(c.translate(1.5, 2), rad,
          fill..color = Colors.black.withValues(alpha: 0.4));
      canvas.drawCircle(c, rad, fill..color = const Color(0xFF14431F));
      canvas.drawCircle(c.translate(-rad * 0.16, -rad * 0.18), rad * 0.72,
          fill..color = const Color(0xFF1E6B32));
      canvas.drawCircle(c.translate(-rad * 0.3, -rad * 0.32), rad * 0.34,
          fill..color = const Color(0x882FB85A));
    }

    // ---- arena border ----
    canvas.drawRect(
        area.deflate(1),
        stroke
          ..color = Color(theme.border).withValues(alpha: 0.9)
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant MapThumbPainter old) => old.choice != choice;
}

/// Full-screen map browser: see every arena before you drop, with the
/// difficulty selector alongside it. This is the "let me look at the maps"
/// screen — it makes the choice feel real instead of picking a word off a chip.
class MapSelectScreen extends StatefulWidget {
  final RoyaleGame game;
  const MapSelectScreen({super.key, required this.game});

  @override
  State<MapSelectScreen> createState() => _MapSelectScreenState();
}

class _MapSelectScreenState extends State<MapSelectScreen> {
  /// One line of flavour per theme, plus what it actually plays like.
  static const _blurb = {
    'URBAN': ['DENSE BLOCKS · CQC FOCUS', 'Tight lanes and rooftops. Corners everywhere.'],
    'FOREST': ['CANOPY · CONCEALMENT', 'Bushes break line of sight. Flank and vanish.'],
    'COMPOUND': ['WALLED ROOMS · HOLD ANGLES', 'Long walls, hard cover, brutal doorways.'],
    'BADLANDS': ['OPEN GROUND · LONG RANGE', 'Sparse boulders. Bring something with reach.'],
  };

  @override
  Widget build(BuildContext context) {
    final p = Profile.instance;
    return Scaffold(
      backgroundColor: ZR.bg,
      body: TacticalBackdrop(
        child: SafeArea(
          top: false,
          bottom: false,
          child: ZrCanvas(
          designHeight: 400,
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth > 760;
            return Column(
          children: [
            ZrTopBar(
              game: widget.game,
              active: Screen.start,
              subtitle: 'MAP INTEL',
              trailing: GestureDetector(
                onTap: () {
                  Sfx.back();
                  Navigator.of(context).maybePop();
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ZR.line)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.arrow_back, size: 15, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text('BACK', style: ZR.display(14, color: Colors.white70)),
                  ]),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 230, child: _sidebar(p)),
                          const SizedBox(width: 16),
                          Expanded(child: _grid()),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Column(children: [
                          _sidebar(p),
                          const SizedBox(height: 14),
                          _grid(scroll: false),
                        ]),
                      ),
              ),
            ),
              ],
            );
          }),
          ),
        ),
      ),
    );
  }

  Widget _sidebar(Profile p) {
    return SingleChildScrollView(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: ZR.panel(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('DIFFICULTY SELECT', style: ZR.display(17, spacing: 1)),
              const SizedBox(height: 10),
              for (var i = 0; i < kDifficulties.length; i++) ...[
                if (i > 0) const SizedBox(height: 7),
                GestureDetector(
                  onTap: () => setState(() {
        Sfx.select();
                  Sfx.tap();
                    Sfx.tap();
                    p.difficulty = i;
                    p.save();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    decoration: p.difficulty == i
                        ? ZR.panelActive(radius: 10)
                        : ZR.panel(radius: 10, fill: Colors.white10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(kDifficulties[i].name,
                              style: ZR.display(18,
                                  color: p.difficulty == i
                                      ? Colors.white
                                      : Colors.white60,
                                  spacing: 1)),
                        ),
                        if (p.difficulty == i)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                color: ZR.primary, shape: BoxShape.circle),
                          )
                        else if (i == kDifficulties.length - 1)
                          const Icon(Icons.warning_amber_rounded,
                              size: 15, color: ZR.danger),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(p.diff.tagline.toUpperCase(),
                  style: ZR.mono(9, color: Colors.white30, spacing: 0.6)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: ZR.panel(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('TACTICAL OPS', style: ZR.display(17, spacing: 1)),
              Text('DEPLOYMENT SIZE & DROP RULES',
                  style: ZR.mono(9, color: Colors.white30, spacing: 0.6)),
              const SizedBox(height: 10),
              // --- squad size / match mode ---
              Row(
                children: [
                  for (var i = 0; i < kMatchModes.length; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
        Sfx.select();
                  Sfx.tap();
                          Sfx.tap();
                    Sfx.tap();
                          p.matchMode = i;
                          p.save();
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          decoration: p.matchMode == i
                              ? ZR.panelActive(radius: 8, color: ZR.secondary)
                              : ZR.panel(radius: 8, fill: Colors.white10),
                          child: Text('${kMatchModes[i].players}',
                              style: ZR.display(18,
                                  color: p.matchMode == i
                                      ? ZR.secondary
                                      : Colors.white60)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                  '${kMatchModes[p.matchMode.clamp(0, kMatchModes.length - 1)].name}'
                  '  ·  ARENA ${kMatchModes[p.matchMode.clamp(0, kMatchModes.length - 1)].world.round()}u',
                  style: ZR.mono(9, color: Colors.white30, spacing: 0.6)),
              const SizedBox(height: 12),
              // --- random drop ---
              GestureDetector(
                onTap: () => setState(() {
        Sfx.select();
                  Sfx.tap();
                  p.mapChoice = 0;
                  p.save();
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: p.mapChoice == 0 ? ZR.primary : Colors.white24,
                        width: p.mapChoice == 0 ? 1.6 : 1),
                    color: p.mapChoice == 0
                        ? ZR.primary.withValues(alpha: 0.08)
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shuffle,
                          size: 20,
                          color:
                              p.mapChoice == 0 ? ZR.primary : Colors.white54),
                      const SizedBox(height: 4),
                      Text('RANDOM DROP',
                          style: ZR.display(16,
                              color: p.mapChoice == 0
                                  ? ZR.primary
                                  : Colors.white70,
                              spacing: 1)),
                      Text('A DIFFERENT ARENA EVERY MATCH',
                          style: ZR.mono(8, color: Colors.white24)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // --- bot difficulty readout, so the sidebar tells the whole story ---
        Container(
          padding: const EdgeInsets.all(14),
          decoration: ZR.panel(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('OPPOSITION', style: ZR.display(16, spacing: 1)),
                  const Spacer(),
                  Text(p.diff.name,
                      style: ZR.display(15, color: ZR.secondary)),
                ],
              ),
              const SizedBox(height: 8),
              _statBar('AIM', p.diff.skill / 1.2),
              _statBar('DAMAGE', p.diff.damage),
              _statBar('EYESIGHT', p.diff.vision / 1.1),
            ],
          ),
        ),
      ],
      ),
    );
  }

  /// A labelled 0..1 bar — used to show at a glance how hard the bots hit.
  Widget _statBar(String label, double v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
              width: 62,
              child: Text(label,
                  style: ZR.mono(9, color: Colors.white38, spacing: 0.6))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: v.clamp(0.05, 1.0),
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.07),
                valueColor: AlwaysStoppedAnimation(
                    v > 0.85 ? ZR.danger : ZR.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid({bool scroll = true}) {
    final p = Profile.instance;
    final cards = [
      for (var i = 0; i < kMapThemes.length; i++) _card(i + 1, p.mapChoice == i + 1),
    ];
    final body = LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth > 620 ? 2 : 1;
      final rows = <Widget>[];
      for (var i = 0; i < cards.length; i += cols) {
        rows.add(IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var c = 0; c < cols; c++) ...[
              if (c > 0) const SizedBox(width: 12),
              Expanded(
                  child: i + c < cards.length
                      ? cards[i + c]
                      : const SizedBox.shrink()),
            ],
          ],
        )));
        rows.add(const SizedBox(height: 12));
      }
      return Column(children: rows);
    });
    return scroll ? SingleChildScrollView(child: body) : body;
  }

  Widget _card(int choice, bool sel) {
    final theme = kMapThemes[choice - 1];
    final info = _blurb[theme.name] ?? const ['ARENA', ''];
    final mode = kMatchModes[
        Profile.instance.matchMode.clamp(0, kMatchModes.length - 1)];
    return GestureDetector(
      onTap: () => setState(() {
        Sfx.select();
        Profile.instance.mapChoice = choice;
        Profile.instance.save();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 210,
        clipBehavior: Clip.antiAlias,
        decoration: sel
            ? ZR.panelActive(radius: 14)
            : ZR.panel(radius: 14, border: Colors.white12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: MapThumbPainter(choice, detail: 1.4)),
            // player-count badge
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ZR.line),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.groups, size: 13, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text('${mode.players} PLAYERS',
                      style: ZR.display(13, color: Colors.white)),
                ]),
              ),
            ),
            // name + blurb + action
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
                color: Colors.black.withValues(alpha: 0.5),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(theme.name,
                              style: ZR.display(26, spacing: 1.4)),
                          Text(info[0],
                              style: ZR.mono(9,
                                  color: Colors.white54, spacing: 0.8)),
                          const SizedBox(height: 3),
                          Text(info[1],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ZR.body(11, color: Colors.white38)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 9),
                      decoration: sel
                          ? ZR.cta(radius: 8)
                          : BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white38),
                            ),
                      child: Text(sel ? 'SELECTED' : 'SELECT',
                          style: ZR.display(15,
                              color: sel
                                  ? const Color(0xFF10131A)
                                  : Colors.white,
                              spacing: 1)),
                    ),
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
