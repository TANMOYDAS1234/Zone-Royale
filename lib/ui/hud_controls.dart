import 'dart:math' as math;

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
/// Everything a player sees or touches during a match now comes from here, in
/// the tactical style the rest of the app uses: amber for you and your kit,
/// cyan for information, red for danger.

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
  // The 1.08 is deliberate slack. [w]/[h] are declared by the caller, and a
  // panel that grows by a few pixels (a longer weapon name, a reload bar
  // appearing) would otherwise be clamped to a position that leaves its
  // bottom edge off the screen — which is exactly how the weapon panel ended
  // up half-cut along the bottom of a landscape phone.
  final ww = w * sc * 1.08, hh = h * sc * 1.08;
  final f = p.hudPosOf(key);
  // A few pixels of margin so a control never kisses the screen edge — on a
  // phone with 3-button navigation the bar is a real, touchable strip.
  const gap = 6.0;
  final maxL = (s.width - safe.right - ww - gap).clamp(0.0, s.width);
  final maxT = (s.height - safe.bottom - hh - gap).clamp(0.0, s.height);
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

/// The twin sticks: a ringed circle with the control's icon stencilled behind
/// the knob. Move is cyan, aim/fire is red — the same pairing the mockups use,
/// so a glance tells you which thumb is which.
class HudStick extends StatelessWidget {
  final String label;
  final Color accent;
  final IconData icon;
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
    this.icon = Icons.open_with,
    this.size = 132,
    this.stickKey,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // the glyph sits under the stick so the control reads instantly
            IgnorePointer(
              child: Icon(icon,
                  size: size * 0.30, color: accent.withValues(alpha: 0.16)),
            ),
            Joystick(
              key: stickKey,
              onChange: onChange,
              onRelease: onRelease,
              size: size,
              accent: accent,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Text(label,
              style: ZR.display(13,
                  color: accent.withValues(alpha: 0.95), spacing: 1.4)),
        ),
      ],
    );
  }
}

/// Circular action button with a cooldown ring — skill, grenade, shield wall.
/// The ring drains as the ability recharges and the button says READY the
/// moment it can be used again.
class HudActionButton extends StatelessWidget {
  final Widget glyph;
  final String label;
  final Color color;
  final bool ready;
  final VoidCallback? onTap;
  final double size;
  /// 0 = just used, 1 = fully charged. Drives the ring.
  final double charge;
  /// Optional count badge (grenades left, walls left).
  final String? count;
  /// What to say while it can't be used. "WAIT" is right for a cooldown;
  /// "EMPTY" is right when you've simply run out.
  final String busyLabel;
  const HudActionButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.color,
    required this.ready,
    this.onTap,
    this.size = 64,
    this.charge = 1,
    this.count,
    this.busyLabel = 'WAIT',
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: ready ? onTap : null,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // charge ring
            Positioned.fill(
              child: CustomPaint(
                painter: _ChargeRingPainter(
                    color: color, charge: charge, ready: ready),
              ),
            ),
            Container(
              margin: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ready
                    ? RadialGradient(colors: [
                        color.withValues(alpha: 0.30),
                        Colors.black.withValues(alpha: 0.62),
                      ])
                    : null,
                color: ready ? null : Colors.black.withValues(alpha: 0.5),
                boxShadow: ready
                    ? [
                        BoxShadow(
                            color: color.withValues(alpha: 0.45),
                            blurRadius: 16,
                            spreadRadius: -2)
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Opacity(opacity: ready ? 1 : 0.4, child: glyph),
                  Text(ready ? label : busyLabel,
                      style: ZR.display(size * 0.19,
                          color: ready ? color : Colors.white38, spacing: 0.5)),
                ],
              ),
            ),
            if (count != null)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: color.withValues(alpha: 0.8)),
                  ),
                  child: Text(count!,
                      style: ZR.display(size * 0.2, color: color)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChargeRingPainter extends CustomPainter {
  final Color color;
  final double charge;
  final bool ready;
  const _ChargeRingPainter(
      {required this.color, required this.charge, required this.ready});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 2;
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white.withValues(alpha: 0.14));
    final sweep = charge.clamp(0.0, 1.0) * math.pi * 2;
    if (sweep > 0.01) {
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          -math.pi / 2,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.4
            ..strokeCap = StrokeCap.round
            ..color = ready ? color : color.withValues(alpha: 0.55));
    }
    if (ready) {
      // a soft outer halo so a charged ability catches the eye mid-fight
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
            ..color = color.withValues(alpha: 0.45));
    }
  }

  @override
  bool shouldRepaint(covariant _ChargeRingPainter old) =>
      old.charge != charge || old.ready != ready || old.color != color;
}

/// Weapon panel: gun art on a lit plate, name, ammo, reload progress, and the
/// SWITCH pill for the other slot. Tap the panel to reload.
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
    final edge = reloading ? ZR.secondary : (low ? ZR.danger : ZR.primary);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.fromLTRB(9, 6, 9, 7),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black.withValues(alpha: 0.72),
              edge.withValues(alpha: 0.12),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: edge.withValues(alpha: 0.75), width: 1.4),
          boxShadow: [
            BoxShadow(
                color: edge.withValues(alpha: 0.22),
                blurRadius: 14,
                spreadRadius: -4)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(w.name.toUpperCase(),
                    style: ZR.display(15, color: edge, spacing: 0.8)),
                const Spacer(),
                Text(reloading ? 'RELOAD' : '$ammo',
                    style: ZR.display(18,
                        color: reloading
                            ? ZR.secondary
                            : (low ? ZR.danger : Colors.white))),
                if (!reloading)
                  Text(' / ${w.mag}',
                      style: ZR.display(12, color: Colors.white38)),
              ],
            ),
            const SizedBox(height: 2),
            // lit plate behind the silhouette — gunmetal on black vanishes
            Container(
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(7),
              ),
              child: CustomPaint(painter: HudGunPainter(weapon)),
            ),
            SizedBox(
              height: 4,
              child: reloading
                  ? Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: reloadFrac.clamp(0.0, 1.0),
                          minHeight: 3,
                          backgroundColor: Colors.black45,
                          valueColor:
                              const AlwaysStoppedAnimation(ZR.secondary),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The other weapon slot as a SWITCH pill, matching the mockup: gun art with a
/// gold SWITCH tag, greyed out when the second slot is empty.
class HudSwapPanel extends StatelessWidget {
  final WeaponId? other;
  final VoidCallback? onTap;
  const HudSwapPanel({super.key, required this.other, this.onTap});

  @override
  Widget build(BuildContext context) {
    final has = other != null;
    final col = has ? ZR.primary : Colors.white24;
    return GestureDetector(
      onTap: has ? onTap : null,
      child: Container(
        width: 80,
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: col.withValues(alpha: has ? 0.7 : 1)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              height: 20,
              child: has
                  ? CustomPaint(painter: HudGunPainter(other!))
                  : Center(
                      child: Text('EMPTY',
                          style: ZR.display(12, color: Colors.white30))),
            ),
            Text(has ? kWeapons[other]!.name.toUpperCase() : '—',
                maxLines: 1,
                style: ZR.display(12,
                    color: has ? Colors.white70 : Colors.white24,
                    spacing: 0.4)),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 1),
              decoration: BoxDecoration(
                color: has
                    ? ZR.primary.withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swap_horiz_rounded,
                      size: 11,
                      color:
                          has ? const Color(0xFF10131A) : Colors.white24),
                  const SizedBox(width: 3),
                  Text('SWITCH',
                      style: ZR.display(12,
                          color: has
                              ? const Color(0xFF10131A)
                              : Colors.white24,
                          spacing: 0.8)),
                ],
              ),
            ),
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
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: on ? ZR.primary : Colors.white24, width: on ? 1.4 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(on ? Icons.flash_on : Icons.filter_center_focus,
                size: 16, color: on ? ZR.primary : Colors.white70),
            Text(!supportsAuto ? 'SINGLE' : (auto ? 'AUTO' : 'SINGLE'),
                style: ZR.display(13,
                    color: on ? ZR.primary : Colors.white70, spacing: 0.8)),
          ],
        ),
      ),
    );
  }
}

/// Health, vest and helmet as three thin icon bars, straight out of the
/// mockup: a red heart for HP, a cyan shield for the vest, an ice helmet for
/// the head. Bars you can read in a firefight without looking away.
class HudHealth extends StatelessWidget {
  final int hp;
  final double vestFrac; // 0..1
  final double helmetFrac; // 0..1
  const HudHealth(
      {super.key,
      required this.hp,
      this.vestFrac = 0,
      this.helmetFrac = 0});

  Widget _bar(IconData icon, Color color, double frac, String value,
      {double height = 8}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: frac.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        color.withValues(alpha: 0.75),
                        color,
                      ]),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: 26,
            child: Text(value,
                textAlign: TextAlign.right,
                style: ZR.display(13, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final frac = (hp / kMaxHp).clamp(0.0, 1.0);
    return SizedBox(
      width: 158,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _bar(Icons.favorite, Color.lerp(ZR.danger, ZR.success, frac)!, frac,
              '$hp',
              height: 11),
          if (vestFrac > 0)
            _bar(Icons.shield, ZR.secondary, vestFrac,
                '${(vestFrac * 100).round()}'),
          if (helmetFrac > 0)
            _bar(Icons.sports_motorsports, ZR.tertiary, helmetFrac,
                '${(helmetFrac * 100).round()}'),
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
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ZR.primary, width: 1.6),
          boxShadow: [
            BoxShadow(
                color: ZR.primary.withValues(alpha: 0.35),
                blurRadius: 16,
                spreadRadius: -4)
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
                    style: ZR.display(16, color: ZR.primary, spacing: 0.8)),
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

/// Small status pill used along the top of the HUD — ALIVE, KILLS, PING.
class HudPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const HudPill(this.text, {super.key, this.color = Colors.white, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(icon == null ? 12 : 8, 4, 12, 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(text, style: ZR.display(16, color: color, spacing: 1)),
        ],
      ),
    );
  }
}

/// The ZONE CLOSING / ZONE SAFE strip that sits under the top bar, with a
/// countdown bar that drains as the ring moves.
class HudZoneStrip extends StatelessWidget {
  final bool closing;
  final String time;
  final double progress; // 0..1 through the current phase
  const HudZoneStrip(
      {super.key,
      required this.closing,
      required this.time,
      required this.progress});

  @override
  Widget build(BuildContext context) {
    final col = closing ? ZR.danger : ZR.secondary;
    return Container(
      width: 176,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: col.withValues(alpha: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(closing ? Icons.warning_amber_rounded : Icons.shield_moon,
                  size: 12, color: col),
              const SizedBox(width: 5),
              Text(closing ? 'ZONE CLOSING' : 'ZONE SAFE',
                  style: ZR.display(14, color: col, spacing: 1.2)),
              const SizedBox(width: 6),
              Text(time, style: ZR.display(14, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation(col),
            ),
          ),
        ],
      ),
    );
  }
}

/// DOUBLE KILL / TRIPLE KILL / RAMPAGE — the gold banner from the mockup, with
/// the XP and combo line under it. This is the moment people screenshot, so it
/// gets a scale-in and a glow rather than plain text.
class HudStreakBanner extends StatelessWidget {
  final String title;
  final int kills;
  final double alpha; // 1 → fresh, 0 → gone
  const HudStreakBanner(
      {super.key,
      required this.title,
      required this.kills,
      required this.alpha});

  @override
  Widget build(BuildContext context) {
    // pops past full size then settles — reads as an impact, not a fade-in
    final t = (1 - alpha).clamp(0.0, 1.0);
    final scale = 1 + 0.18 * math.exp(-t * 9) * math.sin(t * 22);
    return Opacity(
      opacity: alpha.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [
                  Color(0x00FFB02E),
                  Color(0x33FFB02E),
                  Color(0x00FFB02E),
                ]),
                border: const Border(
                  top: BorderSide(color: ZR.primary, width: 1.5),
                  bottom: BorderSide(color: ZR.primary, width: 1.5),
                ),
                boxShadow: [
                  BoxShadow(
                      color: ZR.primary.withValues(alpha: 0.35),
                      blurRadius: 26,
                      spreadRadius: -6)
                ],
              ),
              child: Text(title,
                  textAlign: TextAlign.center,
                  style: ZR.display(34, color: ZR.primary, spacing: 4)),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('+${kills * 250} XP   |   COMBO X$kills',
                  style: ZR.mono(9, color: Colors.white70, spacing: 1.6)),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the kill feed: KILLER ⌖ VICTIM, your own kills in amber.
class HudKillFeedLine extends StatelessWidget {
  final String killer;
  final String victim;
  final bool mine;
  final double alpha;
  const HudKillFeedLine(
      {super.key,
      required this.killer,
      required this.victim,
      required this.mine,
      this.alpha = 1});

  @override
  Widget build(BuildContext context) {
    final col = mine ? ZR.primary : Colors.white70;
    return Opacity(
      opacity: alpha.clamp(0.0, 1.0),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border(
              left: BorderSide(
                  color: mine ? ZR.primary : Colors.white24, width: 2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(killer, style: ZR.display(13, color: col, spacing: 0.5)),
            const SizedBox(width: 6),
            const Icon(Icons.gps_fixed, size: 10, color: ZR.danger),
            const SizedBox(width: 6),
            Text(victim,
                style: ZR.display(13, color: Colors.white38, spacing: 0.5)),
          ],
        ),
      ),
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
