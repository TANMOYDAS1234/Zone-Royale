import 'package:flutter/material.dart';

import '../game/char_art.dart';
import '../game/config.dart';
import '../game/profile.dart';
import 'game_ui.dart' show Joystick;
import 'theme.dart';

/// THE in-match control set — one implementation, used by both the offline
/// match and the online arena.
///
/// Before this existed the two modes drew their own joysticks, weapon panel
/// and action buttons, so a custom room felt like a different game than solo.
/// Everything a player touches now comes from here.

/// Places a control at the player's saved position for the current layout,
/// with its own size and opacity, kept clear of the system bars.
Widget hudPlace(
  Size s,
  String key,
  Widget child,
  double w,
  double h, [
  EdgeInsets safe = EdgeInsets.zero,
]) {
  final p = Profile.instance;
  final sc = p.hudScaleOf(key);
  final op = p.hudOpacityOf(key);
  final ww = w * sc, hh = h * sc;
  final f = p.hudPosOf(key);
  final maxL = (s.width - safe.right - ww).clamp(0.0, s.width);
  final maxT = (s.height - safe.bottom - hh).clamp(0.0, s.height);
  final left = (f[0] * s.width - ww / 2).clamp(safe.left.clamp(0.0, maxL), maxL);
  final top = (f[1] * s.height - hh / 2).clamp(safe.top.clamp(0.0, maxT), maxT);
  return Positioned(
    key: ValueKey('ctl-$key'),
    left: left,
    top: top,
    child: Opacity(
      opacity: op,
      child: Transform.scale(scale: sc, child: child),
    ),
  );
}

/// Labelled twin-stick, exactly as the offline game draws it.
class HudStick extends StatelessWidget {
  final String label;
  final Color accent;
  final double size;
  final void Function(Offset) onChange;
  final VoidCallback onRelease;
  final Key? stickKey;
  const HudStick({
    super.key,
    required this.label,
    required this.accent,
    required this.onChange,
    required this.onRelease,
    this.size = 132,
    this.stickKey,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: ZR.display(15,
                color: accent.withValues(alpha: 0.9), spacing: 1.4)),
        const SizedBox(height: 6),
        Joystick(
          key: stickKey,
          onChange: onChange,
          onRelease: onRelease,
          size: size,
          accent: accent,
        ),
      ],
    );
  }
}

/// Circular action button (skill / grenade / shield wall).
class HudActionButton extends StatelessWidget {
  final Widget glyph;
  final String label;
  final Color color;
  final bool ready;
  final VoidCallback? onTap;
  final double size;
  const HudActionButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.color,
    required this.ready,
    this.onTap,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: ready ? onTap : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: ready ? color : Colors.white24, width: 3),
          boxShadow: ready
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 14)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(opacity: ready ? 1 : 0.4, child: glyph),
            Text(label,
                style: ZR.display(14,
                    color: ready ? color : Colors.white38, spacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

/// Weapon panel: gun art, name, ammo, reload progress. Tap to reload.
class HudWeaponPanel extends StatelessWidget {
  final WeaponId weapon;
  final int ammo;
  final bool reloading;
  final double reloadFrac; // 0..1 complete
  final VoidCallback onTap;
  const HudWeaponPanel({
    super.key,
    required this.weapon,
    required this.ammo,
    required this.reloading,
    required this.reloadFrac,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final w = kWeapons[weapon]!;
    final low = !reloading && ammo <= (w.mag * 0.3).ceil();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: reloading
                  ? ZR.secondary
                  : (low ? ZR.danger : w.color.withValues(alpha: 0.6))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                width: 100,
                height: 22,
                child: CustomPaint(painter: HudGunPainter(weapon))),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.autorenew, size: 11, color: Colors.white38),
                const SizedBox(width: 4),
                Text(w.name.toUpperCase(),
                    style: ZR.display(15, color: w.color, spacing: 0.8)),
              ],
            ),
            Text(reloading ? 'RELOADING…' : '$ammo / ${w.mag}',
                style: ZR.display(14,
                    color: reloading
                        ? ZR.secondary
                        : (low ? ZR.danger : Colors.white))),
            if (reloading) ...[
              const SizedBox(height: 3),
              SizedBox(
                width: 100,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: reloadFrac.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: Colors.black45,
                    valueColor: AlwaysStoppedAnimation(w.color),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The other weapon slot + a tap to switch to it.
class HudSwapPanel extends StatelessWidget {
  final WeaponId? other;
  final VoidCallback? onTap;
  const HudSwapPanel({super.key, required this.other, this.onTap});

  @override
  Widget build(BuildContext context) {
    final has = other != null;
    final col = has ? kWeapons[other]!.color : Colors.white24;
    return GestureDetector(
      onTap: has ? onTap : null,
      child: Container(
        width: 74,
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: has ? col.withValues(alpha: 0.8) : Colors.white24),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.swap_horiz_rounded,
                    size: 12, color: Colors.white54),
                const SizedBox(width: 3),
                Text('SWITCH',
                    style: ZR.display(12, color: Colors.white54, spacing: 1)),
              ],
            ),
            SizedBox(
              width: 60,
              height: 20,
              child: has
                  ? CustomPaint(painter: HudGunPainter(other!))
                  : Center(
                      child: Text('EMPTY',
                          style: ZR.display(12, color: Colors.white30))),
            ),
            Text(has ? kWeapons[other]!.name.toUpperCase() : '—',
                maxLines: 1,
                style: ZR.display(13,
                    color: has ? col : Colors.white24, spacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

/// AUTO / SINGLE trigger toggle.
class HudFireMode extends StatelessWidget {
  final bool supportsAuto;
  final bool auto;
  final VoidCallback? onTap;
  const HudFireMode(
      {super.key,
      required this.supportsAuto,
      required this.auto,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final on = supportsAuto && auto;
    return GestureDetector(
      onTap: supportsAuto ? onTap : null,
      child: Container(
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? ZR.primary : Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(on ? Icons.flash_on : Icons.filter_center_focus,
                size: 16, color: on ? ZR.primary : Colors.white70),
            Text(!supportsAuto ? 'SINGLE' : (auto ? 'AUTO' : 'SINGLE'),
                style: ZR.display(13, spacing: 0.8)),
          ],
        ),
      ),
    );
  }
}

/// Health + armour readout.
class HudHealth extends StatelessWidget {
  final int hp;
  final double vestFrac; // 0..1
  final double helmetFrac; // 0..1
  const HudHealth(
      {super.key,
      required this.hp,
      this.vestFrac = 0,
      this.helmetFrac = 0});

  @override
  Widget build(BuildContext context) {
    final frac = (hp / kMaxHp).clamp(0.0, 1.0);
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('$hp HP', style: ZR.display(16, spacing: 0.8)),
              const Spacer(),
              if (vestFrac > 0)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.shield, size: 12, color: Color(0xFF7FC4FF)),
                ),
              if (helmetFrac > 0)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.sports_motorsports,
                      size: 12, color: Color(0xFFC9D6A8)),
                ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 12,
              backgroundColor: Colors.black45,
              valueColor: AlwaysStoppedAnimation(
                  Color.lerp(ZR.danger, ZR.success, frac)!),
            ),
          ),
          if (vestFrac > 0 || helmetFrac > 0) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                if (vestFrac > 0)
                  Expanded(
                    flex: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: vestFrac.clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: Colors.black45,
                        valueColor:
                            const AlwaysStoppedAnimation(Color(0xFF7FC4FF)),
                      ),
                    ),
                  ),
                if (vestFrac > 0 && helmetFrac > 0) const SizedBox(width: 4),
                if (helmetFrac > 0)
                  Expanded(
                    flex: 2,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: helmetFrac.clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: Colors.black45,
                        valueColor:
                            const AlwaysStoppedAnimation(Color(0xFFC9D6A8)),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "PICK UP RIFLE — replaces SMG" prompt.
class HudPickupPrompt extends StatelessWidget {
  final WeaponId offered;
  final WeaponId held;
  final VoidCallback onTap;
  const HudPickupPrompt(
      {super.key,
      required this.offered,
      required this.held,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = kWeapons[offered]!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: w.color, width: 2),
          boxShadow: [
            BoxShadow(color: w.color.withValues(alpha: 0.35), blurRadius: 14)
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                width: 42,
                height: 18,
                child: CustomPaint(painter: HudGunPainter(offered))),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PICK UP  ${w.name.toUpperCase()}',
                    style: ZR.display(16, color: w.color, spacing: 0.8)),
                Text('REPLACES ${kWeapons[held]!.name.toUpperCase()}',
                    style: ZR.mono(8, color: Colors.white38)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small status pill used along the top of the HUD.
class HudPill extends StatelessWidget {
  final String text;
  final Color color;
  const HudPill(this.text, {super.key, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(text, style: ZR.display(16, color: color, spacing: 1)),
    );
  }
}

/// Draws a weapon as a HUD icon (the same art as in the world).
class HudGunPainter extends CustomPainter {
  final WeaponId weapon;
  const HudGunPainter(this.weapon);

  @override
  void paint(Canvas canvas, Size size) {
    drawGunIcon(canvas, Offset(size.width / 2, size.height / 2),
        size.width * 0.96, weapon);
  }

  @override
  bool shouldRepaint(covariant HudGunPainter old) => old.weapon != weapon;
}
