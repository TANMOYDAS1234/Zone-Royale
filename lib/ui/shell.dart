import 'package:flutter/material.dart';

import '../game/char_art.dart';
import '../game/config.dart';
import '../game/profile.dart';
import '../game/sfx.dart';
import '../game/royale_game.dart';
import 'logo.dart';
import 'theme.dart';

/// Shared app chrome: the tactical top bar and the bottom tab rail that every
/// meta screen sits between. Keeping them here means HOME / SHOP / MISSIONS /
/// PROFILE can never drift apart visually.

/// Top bar: logo, section tabs (wide screens), currency + level chips, gear.
class ZrTopBar extends StatelessWidget {
  final RoyaleGame game;
  final String active; // Screen.*
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onSettings;
  /// Shows a back arrow at the far left. The lobby is the hub now, so every
  /// screen you reach from it needs an obvious way home — hunting for the
  /// right tab in the bottom rail is not that.
  final VoidCallback? onBack;
  const ZrTopBar({
    super.key,
    required this.game,
    required this.active,
    this.subtitle,
    this.trailing,
    this.onSettings,
    this.onBack,
  });

  static const _tabs = [
    [Screen.start, 'HOME'],
    [Screen.shop, 'SHOP'],
    [Screen.missions, 'MISSIONS'],
    [Screen.profile, 'PROFILE'],
  ];

  @override
  Widget build(BuildContext context) {
    final p = Profile.instance;
    return LayoutBuilder(builder: (context, box) {
      // The bottom rail already carries navigation, so the top tabs are a
      // bonus for wide screens only — never something that can clip.
      final wide = box.maxWidth > 900;
      return SafeArea(
      bottom: false,
      minimum: const EdgeInsets.only(top: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 6),
        child: Row(
          children: [
            if (onBack != null) ...[
              GestureDetector(
                onTap: () {
                  Sfx.back();
                  onBack!();
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ZR.line)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.arrow_back,
                        size: 15, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text('BACK',
                        style: ZR.display(14, color: Colors.white70)),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
            ],
            const ZrLogo(height: 30),
            if (subtitle != null && box.maxWidth > 620) ...[
              const SizedBox(width: 12),
              Container(
                  width: 1,
                  height: 26,
                  color: Colors.white.withValues(alpha: 0.14)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(subtitle!.toUpperCase(),
                      style: ZR.mono(11, color: Colors.white70, spacing: 1.6)),
                  Text('SYSTEMS ONLINE',
                      style: ZR.mono(9, color: ZR.success, spacing: 1.2)),
                ],
              ),
            ],
            const Spacer(),
            if (wide) ...[
              for (final t in _tabs)
                _NavTab(
                  label: t[1],
                  active: active == t[0],
                  onTap: () {
                    Sfx.select();
                    game.screen.value = t[0];
                  },
                ),
              const SizedBox(width: 14),
            ],
            if (trailing != null) ...[trailing!, const SizedBox(width: 10)],
            _Chip(
                icon: Icons.military_tech,
                label: 'LVL ${p.level}',
                color: p.rankColor),
            const SizedBox(width: 8),
            _Chip(
                icon: Icons.monetization_on,
                label: '${p.coins}',
                color: ZR.primary),
            const SizedBox(width: 8),
            // Only offered where it is the only way through. Every hub screen
            // has a BACK button now, so a gear that just opens PROFILE is one
            // more thing to read and nothing to do.
            if (onSettings != null)
            GestureDetector(
              onTap: onSettings ??
                  () {
                    Sfx.select();
                    game.screen.value = Screen.profile;
                  },
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ZR.line)),
                child: const Icon(Icons.settings,
                    size: 17, color: Colors.white60),
              ),
            ),
          ],
        ),
      ),
      );
    });
  }
}

class _NavTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavTab(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: active ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: ZR.display(17,
                    color: active ? ZR.primary : Colors.white60, spacing: 1.4)),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 2,
              width: active ? 24 : 0,
              decoration: BoxDecoration(
                  color: ZR.primary, borderRadius: BorderRadius.circular(2)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: ZR.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 7),
          Text(label,
              style: ZR.display(15, color: Colors.white, spacing: 1)),
        ],
      ),
    );
  }
}

/// Bottom tab rail — the primary navigation on a phone.
class ZrBottomNav extends StatelessWidget {
  final RoyaleGame game;
  final String active;
  const ZrBottomNav({super.key, required this.game, required this.active});

  static const _items = [
    [Screen.start, 'HOME'],
    [Screen.shop, 'SHOP'],
    [Screen.missions, 'MISSIONS'],
    [Screen.profile, 'PROFILE'],
  ];

  static IconData _icon(String s) {
    switch (s) {
      case Screen.shop:
        return Icons.shopping_cart;
      case Screen.missions:
        return Icons.assignment;
      case Screen.profile:
        return Icons.person;
      default:
        return Icons.home;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZR.bgAlt,
        border: Border(top: BorderSide(color: ZR.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            children: [
              for (final it in _items)
                Expanded(
                  child: _NavButton(
                    icon: _icon(it[0]),
                    label: it[1],
                    active: active == it[0],
                    onTap: () {
                      Sfx.select();
                      game.screen.value = it[0];
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavButton(
      {required this.icon,
      required this.label,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final col = active ? const Color(0xFF10131A) : Colors.white54;
    return GestureDetector(
      onTap: active ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: active
            ? ZR.cta(radius: 12)
            : BoxDecoration(borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21, color: col),
            const SizedBox(height: 3),
            Text(label, style: ZR.display(14, color: col, spacing: 1.2)),
          ],
        ),
      ),
    );
  }
}

/// The framed operator card used on HOME and PROFILE: the live in-game
/// operator on a lit stage, with tactical read-outs stencilled over it.
class ZrOperatorStage extends StatelessWidget {
  final double height;
  final bool showReadouts;
  /// Radians the operator has been spun by dragging, in the lobby.
  final double turn;
  const ZrOperatorStage(
      {super.key,
      this.height = 260,
      this.showReadouts = true,
      this.turn = 0});

  @override
  Widget build(BuildContext context) {
    final p = Profile.instance;
    final hero = kHeroes[p.hero.clamp(0, kHeroes.length - 1)];
    return Container(
      height: height,
      decoration: ZR.panel(border: ZR.primary.withValues(alpha: 0.3), radius: 16),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(
              child: CustomPaint(painter: _StagePainter())),
          // the real in-game operator, lit and framed
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 34),
            child: CustomPaint(
              painter: OperatorStagePainter(
                outfit: p.outfitColor,
                skin: p.skinColor,
                accessory: p.accessory,
                weapon: p.startWeapon,
                hero: p.hero,
                accent: Color(hero.color),
                turn: turn,
              ),
            ),
          ),
          if (showReadouts) ...[
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: ZR.danger.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: ZR.danger.withValues(alpha: 0.7)),
                ),
                child: Text('UNIT: SPEC-OPS // ${hero.name}',
                    style: ZR.mono(10, color: ZR.danger, spacing: 0.5)),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              right: 12,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('WEAPON',
                            style: ZR.mono(9, color: Colors.white38)),
                        Text(kWeapons[p.startWeapon]!.name.toUpperCase(),
                            style: ZR.display(15, spacing: 1)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LOADOUT',
                            style: ZR.mono(9, color: Colors.white38)),
                        Text('ASSAULT-01', style: ZR.display(15, spacing: 1)),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                            color: ZR.success, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text('STATUS: READY',
                          style: ZR.mono(10, color: ZR.success)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Blueprint grid + corner brackets behind the operator.
class _StagePainter extends CustomPainter {
  const _StagePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // floor glow
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(size.width / 2, size.height * 0.86),
            width: size.width * 0.7,
            height: size.height * 0.22),
        Paint()..color = ZR.primary.withValues(alpha: 0.10));
    // corner brackets
    final b = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ZR.primary.withValues(alpha: 0.55);
    const len = 18.0, pad = 8.0;
    for (final c in [
      [pad, pad, 1.0, 1.0],
      [size.width - pad, pad, -1.0, 1.0],
      [pad, size.height - pad, 1.0, -1.0],
      [size.width - pad, size.height - pad, -1.0, -1.0],
    ]) {
      canvas.drawLine(Offset(c[0], c[1]),
          Offset(c[0] + len * c[2], c[1]), b);
      canvas.drawLine(Offset(c[0], c[1]),
          Offset(c[0], c[1] + len * c[3]), b);
    }
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) => false;
}

/// Draws the in-game operator big and centred on the stage.
class OperatorStagePainter extends CustomPainter {
  final Color outfit, skin, accent;
  final int accessory, hero;
  final WeaponId weapon;
  /// Spin applied by dragging the stage.
  final double turn;
  OperatorStagePainter({
    required this.outfit,
    required this.skin,
    required this.accessory,
    required this.weapon,
    required this.hero,
    required this.accent,
    this.turn = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    drawOperatorTile(canvas, Offset.zero & size,
        outfit: outfit,
        skin: skin,
        accessory: accessory,
        hero: hero,
        weapon: weapon,
        glow: accent,
        // the drag spin: the operator turns in place
        turn: turn,
        zoom: 0.9);
  }

  @override
  bool shouldRepaint(covariant OperatorStagePainter old) =>
      old.turn != turn ||
      old.outfit != outfit ||
      old.skin != skin ||
      old.accessory != accessory ||
      old.hero != hero ||
      old.weapon != weapon;
}
