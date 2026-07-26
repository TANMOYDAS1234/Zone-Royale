import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/char_art.dart';
import '../game/config.dart';
import '../game/profile.dart';
import '../game/royale_game.dart';
import '../net/net_arena.dart';
import 'brand.dart';
import 'capture.dart';
// The offline match and the online arena draw the SAME controls, from here.
import 'hud_controls.dart';
import 'result_screen.dart';
import 'theme.dart';
import 'tutorial.dart';
import '../i18n/strings.dart';

/// Page padding that keeps menu content in a readable centred column instead
/// of stretching one thin list across a 20:9 landscape screen.
EdgeInsets menuPad(BuildContext context,
    {double top = 8, double bottom = 16, double side = 16, double max = 640}) {
  final mq = MediaQuery.of(context);
  final w = mq.size.width;
  var gutter = w > max + side * 2 ? (w - max) / 2 : side;
  // Held sideways, Android puts its navigation bar down one edge — keep the
  // content clear of it (and of any camera cutout).
  final inset = math.max(mq.padding.left, mq.padding.right);
  if (gutter < side + inset) gutter = side + inset;
  return EdgeInsets.fromLTRB(gutter, top, gutter, bottom);
}

/// Horizontal page padding for header rows, clear of system bars/cutouts.
EdgeInsets headerPad(BuildContext context,
    {double top = 4, double bottom = 6, double side = 18}) {
  final mq = MediaQuery.of(context);
  return EdgeInsets.fromLTRB(
      side + mq.padding.left, top, side + mq.padding.right, bottom);
}

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
    final mq = MediaQuery.of(context);
    final s = mq.size;
    // portrait and landscape have their own saved control layouts
    Profile.instance.hudLandscape = s.width > s.height;
    // keep controls clear of the status/gesture bars
    final safe = mq.padding;
    game.safeRight = safe.right; // canvas overlays honour them too
    game.safeLeft = safe.left;
    game.safeTop = safe.top;
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
        // Zone status sits dead-centre at the top in BOTH orientations —
        // parking it under the minimap pushed it into the middle of the
        // battlefield on a sideways screen.
        Positioned(
          top: MediaQuery.of(context).padding.top + 14,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(child: _ticked(_zoneBanner)),
          ),
        ),
        // Touch controls float at the player's customised positions (see the
        // Controls editor). On desktop the skill button sits at a fixed spot and
        // grenade/reload live in the info row.
        if (floating) ...[
          // The width/height passed here MUST match what the widget actually
          // measures — hudPlace clamps against it to keep controls inside the
          // safe area, and an under-reported height lets a panel hang off the
          // bottom of the screen.
          ..._sticks(s, safe),
          _place(s, 'skill', _ticked(_skillButton), 64, 64, safe),
          _place(s, 'nade', _ticked(_grenadeButton), 60, 60, safe),
          _place(s, 'swap', _ticked(_swapButton), 80, 66, safe),
          _place(s, 'wall', _ticked(_wallButton), 60, 60, safe),
          _place(s, 'reload', _ticked(_reloadButton), 140, 84, safe),
          _place(s, 'fire', _ticked(_fireModeButton), 64, 62, safe),
          _place(s, 'hp',
              _ticked(() => SizedBox(width: 158, child: _hpBar())), 158, 56, safe),
          _place(s, 'pick', _ticked(_pickupButton), 168, 52, safe),
        ] else ...[
          Positioned(
            right: 28,
            bottom: 200,
            child: _ticked(_skillButton),
          ),
          _place(s, 'pick', _ticked(_pickupButton), 168, 52, safe),
        ],
        // kill feed — the same widget the online arena uses
        Positioned(
          left: safe.left + 14,
          top: safe.top + 52,
          child: IgnorePointer(
            child: _ticked(() => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final k in game.killLog.reversed)
                      HudKillFeedLine(
                          killer: k.killer.toUpperCase(),
                          victim: k.victim.toUpperCase(),
                          mine: k.mine,
                          alpha: (k.life / 1.2).clamp(0.0, 1.0)),
                  ],
                )),
          ),
        ),
        // killstreak shout — the thing people screenshot
        IgnorePointer(child: _ticked(() => _streakBanner(s))),
      ],
    );
  }

  /// DOUBLE KILL / TRIPLE KILL / RAMPAGE, centred and fading out.
  Widget _streakBanner(Size s) {
    final txt = game.banner;
    if (txt == null) return const SizedBox.shrink();
    return Positioned(
      top: s.height * (Profile.instance.hudLandscape ? 0.16 : 0.24),
      left: 0,
      right: 0,
      child: Center(
        child: HudStreakBanner(
          title: txt,
          kills: game.streakKills,
          alpha: game.bannerAlpha,
        ),
      ),
    );
  }

  // Repaints its child every game frame (ammo, cooldowns, grenade count…).
  Widget _ticked(Widget Function() build) => AnimatedBuilder(
        animation: game.ticker,
        builder: (_, _) => build(),
      );

  // Places [child] centred on its stored [key] fraction of the screen, scaled
  // and faded to that control's own settings. Held sideways, Android's gesture
  // bar sits down one edge and swallows touches, so controls are kept inside
  // the safe area rather than the raw screen rect.
  Widget _place(Size s, String key, Widget child, double w, double h,
          [EdgeInsets safe = EdgeInsets.zero]) =>
      hudPlace(s, key, child, w, h, safe);

  Widget _skillButton() {
    final p = game.player;
    final hero = kHeroes[Profile.instance.hero.clamp(0, kHeroes.length - 1)];
    final ready = p.skillCd <= 0;
    final col = Color(hero.color);
    return HudActionButton(
      glyph: ready
          ? Icon(_skillIcon(hero.skill), color: col, size: 24)
          : Text('${p.skillCd.ceil()}', style: ZR.display(22)),
      label: 'READY',
      color: col,
      ready: ready,
      charge: ready ? 1 : 1 - (p.skillCd / hero.cooldown).clamp(0.0, 1.0),
      onTap: game.activateSkill,
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

  Widget _hpBar() {
    final p = game.player;
    return HudHealth(
      hp: p.hp.ceil().clamp(0, 100),
      vestFrac: (p.vest / kVestDurability).clamp(0.0, 1.0),
      helmetFrac: (p.helmet / kHelmetDurability).clamp(0.0, 1.0),
    );
  }

  /// SHIELD WALL button — instant cover, the panic button that makes close
  /// fights survivable.
  Widget _wallButton() {
    final p = game.player;
    final ready = p.walls > 0 && p.wallCd <= 0;
    return HudActionButton(
      glyph: SizedBox(
        width: 22,
        height: 15,
        child: CustomPaint(painter: ShieldWallGlyph(lit: ready)),
      ),
      label: 'WALL',
      color: ZR.tertiary,
      ready: ready,
      size: 60,
      count: '${p.walls}',
      busyLabel: p.walls <= 0 ? 'EMPTY' : 'WAIT',
      charge: p.walls <= 0
          ? 0
          : (p.wallCd <= 0
              ? 1
              : 1 - (p.wallCd / kShieldWallCooldown).clamp(0.0, 1.0)),
      onTap: game.deployWall,
    );
  }

  Widget _info(BuildContext context) {
    final p = game.player;
    final floating = game.isMobile || game.touchMode;
    final landscape = Profile.instance.hudLandscape;
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
                HudPill('${game.aliveCount}',
                    color: ZR.primary, icon: Icons.person),
                const SizedBox(width: 8),
                HudPill('${p.kills}',
                    color: ZR.danger, icon: Icons.gps_fixed),
                const Spacer(),
                // Landscape screens are short — a full-size minimap would eat
                // a third of the height, so it shrinks when held sideways.
                _MiniMap(game: game, size: landscape ? 82 : 104),
              ],
            ),
            // Pickup/status messages sit just under the zone banner. They used
            // to float in the middle of the screen, right on top of your own
            // operator — the worst possible place for a message.
            const SizedBox(height: 44),
            if (game.toast != null)
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(game.toast!,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ),
            const Spacer(),
            // On touch, HP + fire-mode + grenade + reload float freely
            // (customisable); on desktop they stay here in the info row.
            if (!floating)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: _hpBar()),
                  const SizedBox(width: 10),
                  _fireModeButton(),
                  const SizedBox(width: 8),
                  _grenadeButton(),
                  const SizedBox(width: 10),
                  _reloadButton(),
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
    final t = game.zoneTimer;
    return HudZoneStrip(
      closing: closing,
      time: t > 900 ? 'FINAL' : '${t.ceil()}s',
      // the bar drains through the phase either way, so the strip always
      // reads as "something is about to happen"
      progress: 1 - (t / (closing ? 30 : 60)).clamp(0.0, 1.0),
    );
  }

  Widget _fireModeButton() => HudFireMode(
        supportsAuto: game.player.weapon.auto,
        auto: game.playerAuto,
        onTap: game.toggleFireMode,
      );

  /// WEAPON SWITCH — the fix for "the game swapped my gun for me". Shows the
  /// gun waiting in your other slot; tap to bring it up. Nothing else in the
  /// game can change what you're holding.
  Widget _swapButton() => HudSwapPanel(
        other: game.player.otherWeapon,
        onTap: game.swapWeapon,
      );

  /// Appears only while you're standing on a gun you'd have to trade for.
  /// No tap = no swap, so loot can never cost you a fight.
  Widget _pickupButton() {
    final l = game.pickupPrompt;
    if (l == null || l.weapon == null || !game.player.alive) {
      return const SizedBox.shrink();
    }
    return HudPickupPrompt(
      offered: l.weapon!,
      held: game.player.weaponId,
      onTap: game.takePickup,
    );
  }

  Widget _grenadeButton() {
    final n = game.player.grenades;
    return HudActionButton(
      glyph: const Text('💣', style: TextStyle(fontSize: 17)),
      label: 'NADE',
      color: const Color(0xFF6ABF5A),
      ready: n > 0 && game.player.throwCd <= 0,
      size: 60,
      count: '$n',
      busyLabel: n <= 0 ? 'EMPTY' : 'WAIT',
      charge: n <= 0
          ? 0
          : (game.player.throwCd <= 0
              ? 1
              : 1 - (game.player.throwCd / kThrowCooldown).clamp(0.0, 1.0)),
      onTap: game.throwGrenade,
    );
  }

  // Weapon panel — tap to reload. Shows the gun, its ammo and reload progress.
  Widget _reloadButton() {
    final p = game.player;
    return HudWeaponPanel(
      weapon: p.weaponId,
      ammo: p.ammo,
      reloading: p.reloading,
      reloadFrac: 1 - (p.reloadT / p.weapon.reloadTime).clamp(0.0, 1.0),
      onTap: game.requestReload,
    );
  }

  List<Widget> _sticks(Size s, EdgeInsets safe) {
    final p = Profile.instance;
    // base size — _place() applies each control's own scale + opacity
    const size = 132.0;
    final move = HudStick(
      label: 'MOVE',
      accent: ZR.secondary,
      icon: Icons.open_with,
      size: size,
      onChange: (v) {
        game.enableTouch(true);
        game.setMove(v.dx, v.dy);
      },
      onRelease: () => game.setMove(0, 0),
    );
    final aim = HudStick(
      label: 'AIM · FIRE',
      accent: ZR.danger,
      icon: Icons.gps_fixed,
      size: size,
      onChange: (v) {
        game.enableTouch(true);
        game.setAimStick(v.dx, v.dy);
      },
      onRelease: () => game.setAimStick(0, 0),
    );
    // leftHanded swaps which stored slot each stick occupies.
    final moveKey = p.leftHanded ? 'aim' : 'move';
    final aimKey = p.leftHanded ? 'move' : 'aim';
    const h = size + 26; // joystick + label
    return [
      _place(s, moveKey, move, size, h, safe),
      _place(s, aimKey, aim, size, h, safe),
    ];
  }
}

// (The gun-icon painter used to live here. Both modes now share HudGunPainter
// from lib/ui/hud_controls.dart, so there is exactly one of them.)

// ============================================================
//  Minimap
// ============================================================
class _MiniMap extends StatelessWidget {
  final RoyaleGame game;
  final double size;
  const _MiniMap({required this.game, this.size = 104});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
        border:
            Border.all(color: ZR.primary.withValues(alpha: 0.55), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: ZR.primary.withValues(alpha: 0.18),
              blurRadius: 14,
              spreadRadius: -4)
        ],
      ),
      child: ClipOval(child: CustomPaint(painter: _MiniMapPainter(game))),
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
    'swap': 'SWITCH GUN',
    'wall': 'SHIELD WALL',
    'pick': 'PICK UP',
    'reload': 'RELOAD',
    'fire': 'FIRE MODE',
    'hp': 'HP BAR',
  };

  /// Short names for the picker strip — you select a control from the bar
  /// itself, so a token parked under the bar (or under your thumb) is still
  /// reachable without moving it first.
  static const _short = {
    'move': 'MOVE',
    'aim': 'AIM',
    'skill': 'SKILL',
    'nade': 'NADE',
    'swap': 'SWAP',
    'wall': 'WALL',
    'pick': 'PICK',
    'reload': 'RELOAD',
    'fire': 'MODE',
    'hp': 'HP',
  };

  static const _tint = {
    'move': kSafeEdge,
    'aim': kAccent2,
    'skill': Color(0xFFB06BFF),
    'nade': Color(0xFF6ABF5A),
    'swap': kSafeEdge,
    'wall': Color(0xFF7FE8FF),
    'pick': kAccent2,
    'reload': kAccent,
    'fire': kAccent,
    'hp': Color(0xFF52E06A),
  };

  late Map<String, double> _scale;
  late Map<String, double> _opacity;
  String _sel = 'move'; // control currently being tuned
  bool? _loadedLandscape; // which orientation's layout is loaded
  /// The header and tuning row sit in one slim bar at the very top — the only
  /// strip of screen no control needs — and fade while you drag, so the whole
  /// layout stays reachable without ever hiding SAVE or the sliders.
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final p = Profile.instance;
    _pos = {
      for (final k in Profile.kDefaultHud.keys)
        k: List<double>.from(p.hudPosOf(k)),
    };
    _scale = {for (final k in Profile.kDefaultHud.keys) k: p.hudScaleOf(k)};
    _opacity = {for (final k in Profile.kDefaultHud.keys) k: p.hudOpacityOf(k)};
  }

  void _reset() => setState(() {
        final def = Profile.defaultHudFor(Profile.instance.hudLandscape);
        _pos = {
          for (final k in Profile.kDefaultHud.keys)
            k: List<double>.from(def[k] ?? Profile.kDefaultHud[k]!),
        };
        _scale = {for (final k in Profile.kDefaultHud.keys) k: 1.0};
        _opacity = {for (final k in Profile.kDefaultHud.keys) k: 1.0};
      });

  Future<void> _save() async {
    final p = Profile.instance;
    // only the layout for the orientation being edited — the other one keeps
    // whatever the player set up for it
    p.resetHudPositions();
    _pos.forEach((k, v) => p.setHudPos(k, v[0], v[1]));
    _scale.forEach(p.setHudScale);
    _opacity.forEach(p.setHudOpacity);
    await p.save();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      body: LayoutBuilder(
        builder: (context, box) {
          final s = Size(box.maxWidth, box.maxHeight);
          // Editing the layout for however the phone is being held right now.
          // If it gets rotated mid-edit, reload the other orientation's saved
          // positions instead of dragging one layout into the other.
          final land = s.width > s.height;
          Profile.instance.hudLandscape = land;
          if (_loadedLandscape != land) {
            _loadedLandscape = land;
            _load();
          }
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
              _token(s, 'swap', 74, 66, accent: kSafeEdge, box: true),
              _token(s, 'wall', 60, 60, accent: const Color(0xFF7FE8FF)),
              _token(s, 'pick', 168, 52, accent: kAccent2, box: true),
              _token(s, 'reload', 130, 66, accent: kAccent, box: true),
              _token(s, 'fire', 64, 64, accent: kAccent, box: true),
              _token(s, 'hp', 150, 46, accent: const Color(0xFF52E06A), box: true),
              // One slim bar pinned to the very top — the strip of screen no
              // control needs. Everything (close, reset, save, size, opacity)
              // stays visible at all times; it only fades while you drag so
              // you can park a control right under it.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: _dragging,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 140),
                    opacity: _dragging ? 0.15 : 1.0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                        child: _tuneBar(),
                      ),
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

  Widget _token(Size s, String key, double baseW, double baseH,
      {required Color accent,
      bool ring = false,
      bool box = false,
      String? emoji}) {
    final f = _pos[key]!;
    final sc = _scale[key]!;
    final op = _opacity[key]!;
    final w = baseW * sc, h = baseH * sc;
    final selected = _sel == key;
    return Positioned(
      left: f[0] * s.width - w / 2,
      top: f[1] * s.height - h / 2,
      child: GestureDetector(
        onTap: () => setState(() => _sel = key),
        onPanStart: (_) => setState(() {
          _sel = key;
          _dragging = true;
        }),
        onPanEnd: (_) => setState(() => _dragging = false),
        onPanCancel: () => setState(() => _dragging = false),
        onPanUpdate: (d) => setState(() {
          f[0] = (f[0] + d.delta.dx / s.width).clamp(0.05, 0.95);
          f[1] = (f[1] + d.delta.dy / s.height).clamp(0.10, 0.92);
        }),
        child: Opacity(
          opacity: op,
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: selected ? 0.30 : 0.16),
              shape: ring ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: ring ? null : BorderRadius.circular(14 * sc),
              border: Border.all(
                  color: selected ? Colors.white : accent,
                  width: selected ? 3 : 2),
            ),
            child: Center(
              child: emoji != null
                  ? Text(emoji, style: TextStyle(fontSize: 22 * sc))
                  : Text(
                      _labels[key]!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          fontSize: (box ? 13 : 11) * sc,
                          letterSpacing: 0.5),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Everything the editor needs in one 70dp bar: exit, SIZE and OPACITY for
  /// the selected control, RESET, SAVE, and a strip that selects any control
  /// directly. The old stacked panel was twice this tall and swallowed the
  /// top third of the layout — where the health bar and pickup prompt live.
  Widget _tuneBar() {
    Widget slider(IconData icon, double val, double min, double max,
        ValueChanged<double> onCh) {
      return Expanded(
        child: Row(
          children: [
            Icon(icon, size: 13, color: Colors.white38),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.5,
                  activeTrackColor: kAccent,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: kAccent,
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                    value: val.clamp(min, max),
                    min: min,
                    max: max,
                    onChanged: onCh),
              ),
            ),
            SizedBox(
              width: 34,
              child: Text('${(val * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 10,
                      color: kAccent,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
    }

    Widget tap(String text, IconData icon, Color fg, Color bg,
        VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Text(text,
                style: TextStyle(
                    color: fg,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8)),
          ]),
        ),
      );
    }

    // one chip per control — tap to tune it without hunting for the token
    Widget chip(String key) {
      final on = _sel == key;
      final col = _tint[key] ?? kAccent;
      return Padding(
        padding: const EdgeInsets.only(right: 5),
        child: GestureDetector(
          onTap: () => setState(() => _sel = key),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: col.withValues(alpha: on ? 0.30 : 0.08),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                  color: on ? col : col.withValues(alpha: 0.35),
                  width: on ? 1.6 : 1),
            ),
            child: Text(_short[key] ?? key,
                style: TextStyle(
                    color: on ? Colors.white : col.withValues(alpha: 0.85),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                      width: 34,
                      height: 32,
                      child: Icon(Icons.close, color: Colors.white70, size: 19)),
                ),
                // each control has its own floor (48dp touch target) and ceiling
                slider(Icons.photo_size_select_small, _scale[_sel]!,
                    Profile.scaleRangeOf(_sel)[0], Profile.scaleRangeOf(_sel)[1],
                    (v) => setState(() => _scale[_sel] = v)),
                slider(Icons.opacity, _opacity[_sel]!, Profile.kMinOpacity,
                    Profile.kMaxOpacity,
                    (v) => setState(() => _opacity[_sel] = v)),
                const SizedBox(width: 6),
                tap('RESET', Icons.restart_alt, Colors.white70,
                    Colors.white.withValues(alpha: 0.07), _reset),
                const SizedBox(width: 6),
                tap('SAVE', Icons.check, const Color(0xFF10131A), kSafeEdge,
                    _save),
              ],
            ),
          ),
          SizedBox(
            height: 26,
            child: Row(
              children: [
                const SizedBox(width: 6),
                const Icon(Icons.tune, size: 13, color: Colors.white38),
                const SizedBox(width: 7),
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [for (final k in _labels.keys) chip(k)],
                  ),
                ),
              ],
            ),
          ),
        ],
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
    canvas.drawCircle(m(game.zoneCenter.x, game.zoneCenter.y),
        game.zoneRadius * s, Paint()..color = ZR.secondary.withValues(alpha: 0.06));
    canvas.drawCircle(
        m(game.zoneCenter.x, game.zoneCenter.y),
        game.zoneRadius * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = kSafeEdge);
    // hard cover, so the map reads as a place rather than dots on a disc —
    // the online minimap draws exactly the same thing
    final cover = Paint()..color = Colors.white.withValues(alpha: 0.16);
    final shield = Paint()..color = ZR.tertiary.withValues(alpha: 0.7);
    for (final o in game.obstacles) {
      if (!o.blocks) continue;
      canvas.drawRect(
          Rect.fromLTWH(o.x * s, o.y * s, math.max(1, o.w * s),
              math.max(1, o.h * s)),
          o.isShield ? shield : cover);
    }
    final p = game.player;
    // nearby enemies within detection range as red blips (radar)
    const detect = 780.0;
    final red = Paint()..color = const Color(0xFFFF3B30);
    for (final c in game.chars) {
      if (!c.alive || c == p) continue;
      if (p.pos.distanceTo(c.pos) > detect) continue;
      canvas.drawCircle(m(c.pos.x, c.pos.y), 2.4, red);
    }
    // live airdrop — a pulsing gold ring everyone can see and race to
    final drop = game.airdrop;
    if (drop != null && !drop.taken) {
      final beat = 0.5 + 0.5 * math.sin(game.airdropT * 4);
      final at = m(drop.pos.x, drop.pos.y);
      canvas.drawCircle(at, 3 + 3 * beat,
          Paint()..color = kAccent.withValues(alpha: 0.35 + 0.3 * beat));
      canvas.drawRect(Rect.fromCenter(center: at, width: 5, height: 5),
          Paint()..color = kAccent);
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
            Text(trUp('ZONE ROYALE'),
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
              padding: menuPad(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _operatorUnitCard(),
                  const SizedBox(height: 10),
                  _streakCard(),
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
                  _difficultyPicker(),
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
                      child: const Text('🌐  CUSTOM ROOM  ·  PLAY ONLINE',
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
      // same rule as everywhere else: a mixed-colour border and a corner
      // radius cannot coexist, so the amber edge is a foreground strip
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [kAccent, kAccent, Color(0x00000000)],
          stops: [0.0, 0.01, 0.01],
        ),
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
    final sz = MediaQuery.of(context).size;
    // A 240px card eats two thirds of a sideways screen — shrink it there.
    final land = sz.width > sz.height;
    return Container(
      height: land ? 168 : 240,
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
                width: land ? 120 : 168,
                height: land ? 120 : 168,
                child: CustomPaint(
                  painter: OperatorPreviewPainter(
                    outfit: p.outfitColor,
                    skin: p.skinColor,
                    accessory: p.accessory,
                    weapon: p.startWeapon,
                    hero: p.hero,
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
                  Text(trUp('STATUS: READY'),
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

  /// Daily login streak — a small, honest reason to open the app tomorrow.
  Widget _streakCard() {
    final p = Profile.instance;
    final ready = p.streakReady;
    return GestureDetector(
      onTap: ready
          ? () => setState(() {
                final r = p.claimStreak();
                if (r != null) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
                    duration: const Duration(seconds: 2),
                    backgroundColor: const Color(0xFF14181F),
                    content: Text('DAY ${p.streak} STREAK  ·  +${r.coins} COINS',
                        style: const TextStyle(
                            color: kAccent, fontWeight: FontWeight.w800)),
                  ));
                }
              })
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: ready
              ? kAccent.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: ready ? kAccent : Colors.white12, width: ready ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(ready ? Icons.card_giftcard : Icons.local_fire_department,
                color: ready ? kAccent : Colors.white38, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DAY ${p.streak} LOGIN STREAK',
                      style: TextStyle(
                          color: ready ? kAccent : Colors.white70,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1)),
                  Text(
                      ready
                          ? 'Tap to collect +${p.streakReward} coins'
                          : 'Collected — come back tomorrow for more',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10.5)),
                ],
              ),
            ),
            // 7-day pip row
            for (var i = 0; i < 7; i++)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < p.streak.clamp(0, 7)
                      ? kAccent
                      : Colors.white.withValues(alpha: 0.15),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// CASUAL / NORMAL / HARDCORE. Bots scale their aim, damage, reaction and
  /// eyesight to match — the match stays a real fight, just at your speed.
  Widget _difficultyPicker() {
    final p = Profile.instance;
    return Column(
      children: [
        Text(trUp('DIFFICULTY'),
            style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                color: Colors.white38,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < kDifficulties.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    p.difficulty = i;
                    p.save();
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: p.difficulty == i
                          ? kSafeEdge.withValues(alpha: 0.18)
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: p.difficulty == i ? kSafeEdge : Colors.white12),
                    ),
                    child: Column(
                      children: [
                        Text(kDifficulties[i].name,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: p.difficulty == i
                                    ? kSafeEdge
                                    : Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(p.diff.tagline,
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
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
        Text(trUp('MAP'),
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
  // static so the key survives the parent's rebuilds — a fresh GlobalKey each
  // build made `currentContext` stale and the share silently fell back to text.
  static final GlobalKey _shotKey = GlobalKey();
  const EndOverlay({super.key, required this.game});

  // Capture the result card as a PNG and share it (BGMI/Free-Fire style).
  // shareCard() handles every fallback and always reports back, so the button
  // can no longer look like it did nothing.
  Future<void> _shareShot(BuildContext context) => shareCard(
        context,
        cardKey: _shotKey,
        text: _resultText(),
        subject: 'Zone Royale result',
        fileStem: 'zone_royale_result',
      );

  /// Dynamic share caption built from the actual match result.
  String _resultText() {
    final won = game.resultWon;
    final kills = game.player.kills;
    final total = game.chars.length;
    final streak = game.bestStreak > 1 ? ' (×${game.bestStreak} streak!)' : '';
    return won
        ? '🏆 WINNER WINNER! #1 / $total in Zone Royale — $kills kills$streak. Can you beat me?'
        : '🔫 Zone Royale — #${game.resultPlacement} / $total, $kills kills$streak. My turn to win next.';
  }

  @override
  Widget build(BuildContext context) {
    final won = game.resultWon;
    final r = game.lastRewards;
    final p = Profile.instance;
    return MatchResultView(
      cardKey: _shotKey,
      onBack: game.goHome,
      result: MatchResult(
        won: won,
        mode: 'SOLO MATCH',
        placement: won ? '#1' : '#${game.resultPlacement}',
        headline: won ? 'WINNER WINNER' : 'ELIMINATED',
        subtitle: won ? 'CHICKEN DINNER' : 'ZONE SECTOR CLEARED',
        // top of the lobby on kills, with at least one, is worth calling out
        mvp: game.player.kills > 0 &&
            game.chars.every((c) => c == game.player || c.kills < game.player.kills),
        stats: [
          ('KILLS', '${game.player.kills}'),
          ('BEST STREAK', game.bestStreak > 1 ? 'x${game.bestStreak}' : '—'),
          ('PLAYERS', '${game.chars.length}'),
          ('RANK', p.rank.toUpperCase()),
        ],
        xp: r?.xp ?? 0,
        coins: r?.coins ?? 0,
        levels: r?.levels ?? 0,
      ),
      actions: [
        Expanded(
          flex: 2,
          child: TutorialAnchor(
            id: 'end.again',
            child: ZrButton(
                label: 'PLAY AGAIN',
                icon: Icons.replay,
                height: 46,
                fontSize: 20,
                onTap: game.startMatch),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TutorialAnchor(
            id: 'end.share',
            child: ZrGhostButton(
                label: 'SHARE',
                icon: Icons.ios_share,
                height: 46,
                color: ZR.secondary,
                onTap: () => _shareShot(context)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TutorialAnchor(
            id: 'end.home',
            child: ZrGhostButton(
                label: 'HOME',
                icon: Icons.home_rounded,
                height: 46,
                color: Colors.white54,
                onTap: game.goHome),
          ),
        ),
        if (!won && game.aliveCount > 1) ...[
          const SizedBox(width: 10),
          Expanded(
            child: ZrGhostButton(
                label: 'SPECTATE',
                icon: Icons.visibility,
                height: 46,
                color: ZR.primary,
                onTap: game.spectate),
          ),
        ],
      ],
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
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFFFD36B), kAccent]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: kAccent.withValues(alpha: 0.45),
                blurRadius: 22,
                spreadRadius: -2)
          ],
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0xFF10131A),
                fontWeight: FontWeight.w900,
                fontSize: 18,
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
              padding: headerPad(context),
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
                padding: menuPad(context, top: 4, bottom: 20),
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
                    _label('SCREEN & FEEL'),
                    _display(p),
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

  /// Screen orientation, shake strength and the weapon-pickup rule — the three
  /// things players asked to be able to control.
  Widget _display(Profile p) {
    Widget seg(List<String> labels, int sel, ValueChanged<int> onSel) => Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => onSel(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sel == i ? kAccent : Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(labels[i],
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: sel == i
                                ? const Color(0xFF10131A)
                                : Colors.white70)),
                  ),
                ),
              ),
            ],
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('GRAPHICS',
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.w800,
                color: Colors.white38)),
        const SizedBox(height: 8),
        seg([for (final q in kQualities) q.name], p.quality, (i) {
          setState(() => p.quality = i);
          p.save();
        }),
        const SizedBox(height: 6),
        Text(
            '${p.gfx.tagline}. Drop this to SMOOTH if the game ever stutters — '
            'it cuts scenery detail, particles and ground marks, not gameplay.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                height: 1.4)),
        const SizedBox(height: 14),
        Row(
          children: [
            const Text('Screen shake',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
                p.shake <= 0.01
                    ? 'OFF'
                    : '${(p.shake * 100).round()}%',
                style: const TextStyle(
                    color: kAccent, fontWeight: FontWeight.w800, fontSize: 12)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(trackHeight: 3),
          child: Slider(
            value: p.shake.clamp(0.0, 1.0),
            activeColor: kAccent,
            onChanged: (v) => setState(() => p.shake = v),
          ),
        ),
        Text(
            'Recoil kick without wrecking your aim. 50% is the default; 0 turns '
            'it off completely.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                height: 1.4)),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(
              child: Text('Auto-swap gun when you walk over one',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Switch(
              value: p.autoSwapWeapons,
              activeThumbColor: kAccent,
              onChanged: (v) => setState(() => p.autoSwapWeapons = v),
            ),
          ],
        ),
        Text(
            p.autoSwapWeapons
                ? 'ON — ground weapons replace what you are holding (old behaviour).'
                : 'OFF — loot only fills an empty slot. A full swap needs a tap on '
                    'PICK UP, so you never lose your gun mid-fight.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                height: 1.4)),
      ],
    );
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
        const SizedBox(height: 6),
        Text(
          'Position, size and opacity are set per control (move, aim, skill, '
          'grenade, shield wall, switch, pick up, reload, fire mode, HP bar) in '
          'the editor below.',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
              height: 1.4),
        ),
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
/// Shop tile art: a tactical frame + the item rendered with the real in-game
/// `drawOperator` routine (hero gear, outfit, accessory, gun all show through).
class _ShopThumbPainter extends CustomPainter {
  final Color accent, outfit, skin;
  final int accessory, hero;
  final WeaponId weapon;
  final bool evolved, gunOnly, headOnly;
  _ShopThumbPainter({
    required this.accent,
    required this.outfit,
    required this.skin,
    required this.accessory,
    required this.weapon,
    required this.hero,
    required this.evolved,
    required this.gunOnly,
    this.headOnly = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final c = size.center(Offset.zero);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(12));

    // frame: dark tile, accent glow, accent border
    canvas.drawRRect(rr, Paint()..color = const Color(0xFF12161E));
    canvas.drawCircle(
      c,
      size.width * 0.52,
      Paint()
        ..shader = RadialGradient(
          colors: [accent.withValues(alpha: 0.30), Colors.transparent],
        ).createShader(Rect.fromCircle(center: c, radius: size.width * 0.52)),
    );
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = accent.withValues(alpha: 0.65));

    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.save();
    canvas.clipRRect(rr);
    if (gunOnly) {
      // weapon tiles: the gun itself, angled so the silhouette reads
      canvas.translate(c.dx, c.dy);
      canvas.rotate(-0.42);
      drawGunIcon(canvas, Offset.zero, size.width * 0.92, weapon,
          fill: fill, stroke: stroke);
    } else if (headOnly) {
      // ACCESSORY tiles: the same in-game operator, cropped in on the head so
      // you can actually see the hat/mask/shades you're buying.
      drawOperatorTile(canvas, rect,
          outfit: outfit,
          skin: skin,
          accessory: accessory,
          hero: hero,
          weapon: weapon,
          glow: accent,
          zoom: 2.1,
          headBias: 0.30);
    } else {
      // character / skin tiles: the operator exactly as they look in a match
      drawOperatorTile(canvas, rect,
          outfit: outfit,
          skin: skin,
          accessory: accessory,
          hero: hero,
          weapon: weapon,
          glow: accent);
    }
    canvas.restore();

    if (evolved) {
      final tp = TextPainter(
        text: const TextSpan(
            text: '★', style: TextStyle(color: Color(0xFFFFD36B), fontSize: 14)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 4, 2));
    }
  }

  @override
  bool shouldRepaint(covariant _ShopThumbPainter old) =>
      old.outfit != outfit ||
      old.hero != hero ||
      old.weapon != weapon ||
      old.accessory != accessory ||
      old.evolved != evolved;
}

class OperatorPreviewPainter extends CustomPainter {
  final Color outfit;
  final Color skin;
  final int accessory;
  final WeaponId weapon;
  final int hero;
  OperatorPreviewPainter({
    required this.outfit,
    required this.skin,
    required this.accessory,
    required this.weapon,
    this.hero = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // The real in-game operator, lit and framed. This is the honest preview:
    // exactly the character you'll be looking at during the match.
    drawOperatorTile(canvas, Offset.zero & size,
        outfit: outfit,
        skin: skin,
        accessory: accessory,
        hero: hero,
        weapon: weapon,
        glow: Color(kHeroes[hero.clamp(0, kHeroes.length - 1)].color),
        zoom: 1.25);
  }

  @override
  bool shouldRepaint(covariant OperatorPreviewPainter old) =>
      old.outfit != outfit ||
      old.skin != skin ||
      old.accessory != accessory ||
      old.hero != hero ||
      old.weapon != weapon;
}

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
            padding: headerPad(context, top: 6, bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(trUp('DAILY MISSIONS'),
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
              padding: menuPad(context, top: 6),
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
    // Every tile renders the real operator art with that item applied, so the
    // preview is exactly what you'll look like in a match.
    final skins = [
      for (var i = 0; i < kOutfitColors.length; i++)
        if (!Profile.isFree('o$i'))
          _item(
            _thumb(
              accent: Color(kOutfitColors[i]),
              outfit: Color(kOutfitColors[i]),
              accessory: p.accessory,
              weapon: p.startWeapon,
              hero: p.hero,
            ),
            i < kOutfitNames.length ? '${kOutfitNames[i]} Kit' : 'Kit ${i + 1}',
            'o$i',
          ),
    ];
    final accs = [
      for (var i = 0; i < kAccessoryNames.length; i++)
        if (!Profile.isFree('a$i'))
          _item(
            _thumb(
              accent: const Color(0xFF7FA6D8),
              accessory: i,
              weapon: p.startWeapon,
              hero: p.hero,
              headOnly: true,
            ),
            kAccessoryNames[i],
            'a$i',
          ),
    ];
    final wpns = [
      for (final w in kWeaponOrder)
        if (!Profile.isFree('w${w.index}'))
          _item(
            _thumb(accent: kWeapons[w]!.color, weapon: w, gunOnly: true),
            kWeapons[w]!.name,
            'w${w.index}',
          ),
    ];
    final heroes = [
      for (var i = 0; i < kHeroes.length; i++)
        if (!Profile.isFree('h$i'))
          _item(
            _thumb(
              accent: Color(kHeroes[i].color),
              outfit: Color(kHeroes[i].color),
              accessory: p.accessory,
              weapon: p.startWeapon,
              hero: i,
            ),
            '${kHeroes[i].name} · ${kHeroes[i].desc.split(' — ').first}',
            'h$i',
          ),
    ];
    final evos = [
      for (var i = 0; i < kHeroes.length; i++)
        if (p.heroOwned(i))
          _item(
            _thumb(
              accent: Color(kHeroes[i].color),
              outfit: Color(kHeroes[i].color),
              accessory: p.accessory,
              weapon: p.startWeapon,
              hero: i,
              evolved: true,
            ),
            '${kHeroes[i].name} — Top Form ★',
            'e$i',
          ),
    ];
    return Container(
      color: const Color(0xFF07090E),
      child: Column(
        children: [
          metaHeader(context, subtitle: 'SUPPLY HUB'),
          Padding(
            padding: headerPad(context, top: 6, bottom: 8),
            child: Row(
              children: [
                Text(trUp('ARMORY'),
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
              padding: menuPad(context, top: 6),
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

  /// A real preview of the item — the same `drawOperator` art you play as,
  /// framed in a tactical tile. Beats a coloured dot, and it's honest: what you
  /// see here is exactly what you'll look like in a match.
  Widget _thumb({
    required Color accent,
    Color? outfit,
    Color? skin,
    int accessory = 0,
    WeaponId weapon = WeaponId.smg,
    int hero = -1,
    bool evolved = false,
    bool gunOnly = false,
    bool headOnly = false,
  }) {
    final p = Profile.instance;
    return SizedBox(
      width: 62,
      height: 62,
      child: CustomPaint(
        painter: _ShopThumbPainter(
          accent: accent,
          outfit: outfit ?? p.outfitColor,
          skin: skin ?? p.skinColor,
          accessory: accessory,
          weapon: weapon,
          hero: hero,
          evolved: evolved,
          gunOnly: gunOnly,
          headOnly: headOnly,
        ),
      ),
    );
  }

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
