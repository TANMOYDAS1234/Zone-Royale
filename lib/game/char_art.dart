import 'dart:math' as math;
import 'dart:ui';

import 'config.dart';

const Color _hair = Color(0xFF2A2018);

Color _dark(Color c, double t) => Color.lerp(c, const Color(0xFF000000), t)!;
Color _lite(Color c, double t) => Color.lerp(c, const Color(0xFFFFFFFF), t)!;

/// Draws a top-down "operator": legs facing [moveAim], then torso / arms /
/// head / gun / accessory facing [aim]. [pos] is the body centre, [r] the
/// body radius. The two scratch paints are reused to avoid per-call allocation.
void drawOperator(
  Canvas canvas,
  Offset pos,
  double r,
  double aim,
  double moveAim,
  Color outfit,
  Color skin,
  int accessory,
  WeaponId weapon, {
  required Paint fill,
  required Paint stroke,
  double walk = 0, // leg-stride phase in [-1, 1]; 0 = standing
  int hero = -1, // index into kHeroes — draws signature gear on top
  bool vest = false, // wearing body armour
  bool helmet = false, // wearing a helmet
  double armourFlash = 0, // 0..1, sparks when armour just ate a hit
}) {
  final outfitDark = _dark(outfit, 0.34);
  final outfitLite = _lite(outfit, 0.18);
  const glove = Color(0xFF23262E);
  const boot = Color(0xFF1C2028);

  // ---- legs (face movement, stride with the walk phase) + boots ----
  canvas.save();
  canvas.translate(pos.dx, pos.dy);
  canvas.rotate(moveAim);
  for (final s in const [-1.0, 1.0]) {
    final stride = walk * s * r * 0.3;
    final lx = -r * 0.1 + stride;
    final ly = s * r * 0.4;
    // thigh
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(lx, ly), width: r * 0.95, height: r * 0.4),
          Radius.circular(r * 0.2)),
      fill..color = outfitDark,
    );
    // knee-pad highlight so the leg has a joint instead of being a sausage
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(lx + r * 0.16, ly - r * 0.06),
              width: r * 0.3,
              height: r * 0.26),
          Radius.circular(r * 0.1)),
      fill..color = _dark(outfit, 0.15),
    );
    // boot + sole
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(lx + r * 0.42, ly),
              width: r * 0.34,
              height: r * 0.44),
          Radius.circular(r * 0.12)),
      fill..color = boot,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(lx + r * 0.5, ly),
              width: r * 0.14,
              height: r * 0.4),
          Radius.circular(r * 0.06)),
      fill..color = const Color(0xFF0E1015),
    );
  }
  canvas.restore();

  // ambient occlusion where the body meets the ground — glues the operator to
  // the map instead of letting them float above it
  canvas.drawOval(
      Rect.fromCenter(
          center: pos, width: r * 2.0, height: r * 1.5),
      fill..color = const Color(0x33000000));

  // ---- upper body (faces aim) ----
  canvas.save();
  canvas.translate(pos.dx, pos.dy);
  canvas.rotate(aim);

  // backpack behind the torso
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(-r * 0.68, 0), width: r * 0.7, height: r * 1.3),
          Radius.circular(r * 0.18)),
      fill..color = const Color(0xFF3A4230));
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(-r * 0.72, 0), width: r * 0.36, height: r * 0.85),
          Radius.circular(r * 0.1)),
      fill..color = const Color(0xFF2C321F));

  // arms — sleeve then a darker forearm
  stroke
    ..color = outfit
    ..strokeWidth = r * 0.34
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(Offset(0, -r * 0.5), Offset(r * 0.72, -r * 0.2), stroke);
  canvas.drawLine(Offset(0, r * 0.5), Offset(r * 0.72, r * 0.2), stroke);
  stroke
    ..color = outfitDark
    ..strokeWidth = r * 0.2;
  canvas.drawLine(Offset(r * 0.36, -r * 0.34), Offset(r * 0.72, -r * 0.2), stroke);
  canvas.drawLine(Offset(r * 0.36, r * 0.34), Offset(r * 0.72, r * 0.2), stroke);

  // torso + ambient-occlusion back shade + rim light
  canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 1.7, height: r * 1.98),
      fill..color = outfit);
  canvas.drawOval(
      Rect.fromCenter(
          center: Offset(-r * 0.34, 0), width: r * 0.9, height: r * 1.7),
      fill..color = outfitDark.withValues(alpha: 0.5));
  canvas.drawOval(
      Rect.fromCenter(
          center: Offset(r * 0.3, -r * 0.22), width: r * 0.8, height: r * 1.05),
      fill..color = outfitLite.withValues(alpha: 0.55));

  // tactical vest + shoulder straps + pouches
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(r * 0.12, 0), width: r * 0.92, height: r * 1.28),
          Radius.circular(r * 0.16)),
      fill..color = _dark(outfit, 0.5));
  stroke
    ..color = _dark(outfit, 0.62)
    ..strokeWidth = r * 0.13;
  canvas.drawLine(Offset(r * 0.08, -r * 0.72), Offset(r * 0.32, r * 0.18), stroke);
  canvas.drawLine(Offset(r * 0.08, r * 0.72), Offset(r * 0.32, -r * 0.18), stroke);
  for (final py in const [-0.34, 0.34]) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(r * 0.12, r * py),
                width: r * 0.42,
                height: r * 0.3),
            Radius.circular(r * 0.06)),
        fill..color = _dark(outfit, 0.4));
  }

  // shoulder pads catch the light and give the silhouette some bulk
  for (final s in const [-1.0, 1.0]) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(r * 0.02, s * r * 0.72),
                width: r * 0.62,
                height: r * 0.44),
            Radius.circular(r * 0.16)),
        fill..color = _dark(outfit, 0.24));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(r * 0.1, s * r * 0.74),
                width: r * 0.3,
                height: r * 0.18),
            Radius.circular(r * 0.08)),
        fill..color = outfitLite.withValues(alpha: 0.5));
  }

  // torso outline
  canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 1.7, height: r * 1.98),
      stroke
        ..color = const Color(0x70000000)
        ..strokeWidth = 2);

  // ---- body armour (worn over the vest, under the hero gear) ----
  if (vest) {
    // hard plate carrier: front plate, cummerbund, mag pouches, shoulder rig
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(r * 0.08, 0), width: r * 1.06, height: r * 1.5),
            Radius.circular(r * 0.2)),
        fill..color = const Color(0xFF2C3646));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(r * 0.08, 0), width: r * 1.06, height: r * 1.5),
            Radius.circular(r * 0.2)),
        stroke
          ..color = const Color(0xFF8FB6E0)
          ..strokeWidth = r * 0.07);
    // plate seam + pouches
    canvas.drawRect(
        Rect.fromCenter(
            center: Offset(r * 0.08, 0), width: r * 0.98, height: r * 0.1),
        fill..color = const Color(0x55000000));
    for (final py in const [-0.42, 0.0, 0.42]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(r * 0.42, r * py),
                  width: r * 0.24,
                  height: r * 0.3),
              Radius.circular(r * 0.05)),
          fill..color = const Color(0xFF3E4B5E));
    }
    // top highlight so the plate reads as hard, not cloth
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(r * 0.34, -r * 0.16),
                width: r * 0.36,
                height: r * 0.7),
            Radius.circular(r * 0.12)),
        fill..color = const Color(0x33FFFFFF));
    // shoulder plates — the silhouette cue that says "this one is armoured"
    for (final s in const [-1.0, 1.0]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(r * 0.02, s * r * 0.76),
                  width: r * 0.7,
                  height: r * 0.5),
              Radius.circular(r * 0.18)),
          fill..color = const Color(0xFF394557));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(r * 0.12, s * r * 0.78),
                  width: r * 0.34,
                  height: r * 0.2),
              Radius.circular(r * 0.08)),
          fill..color = const Color(0x55BFD8F0));
    }
    // neck guard + collar ring
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(r * 0.5, 0), width: r * 0.3, height: r * 0.8),
            Radius.circular(r * 0.12)),
        fill..color = const Color(0xFF232B37));
    // carbon weave across the plate
    stroke
      ..color = const Color(0x33000000)
      ..strokeWidth = r * 0.035;
    for (var i = -2; i <= 2; i++) {
      canvas.drawLine(Offset(r * -0.3, i * r * 0.28),
          Offset(r * 0.5, i * r * 0.28), stroke);
    }
  }
  if (armourFlash > 0) {
    canvas.drawCircle(Offset(r * 0.4, 0), r * 0.9,
        fill..color = const Color(0xFF9FD8FF).withValues(alpha: 0.5 * armourFlash));
  }

  // gun + gloved hands
  _drawWeapon(canvas, weapon, r, glove, fill, stroke);

  // neck
  canvas.drawCircle(
      Offset(r * 0.14, 0), r * 0.32, fill..color = _dark(skin, 0.3));

  // ---- head: a person seen from above — hair with a part, ears, brow, nose --
  final head = Offset(r * 0.36, 0);
  final hr = r * 0.6;
  final hair = _heroHair(hero);
  // ears
  for (final s in const [-1.0, 1.0]) {
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(head.dx - hr * 0.08, s * hr * 0.86),
            width: hr * 0.34,
            height: hr * 0.46),
        fill..color = _dark(skin, 0.12));
  }
  // skull / face
  canvas.drawCircle(head, hr, fill..color = skin);
  // brow shadow across the forehead gives the face depth from above
  canvas.drawOval(
      Rect.fromCenter(
          center: Offset(head.dx + hr * 0.34, 0),
          width: hr * 0.7,
          height: hr * 1.5),
      fill..color = _dark(skin, 0.16).withValues(alpha: 0.55));
  // nose tip poking forward — the single cue that sells "this is a face"
  canvas.drawOval(
      Rect.fromCenter(
          center: Offset(head.dx + hr * 0.82, 0),
          width: hr * 0.3,
          height: hr * 0.34),
      fill..color = _lite(skin, 0.08));
  if (!helmet) {
    // hair mass: covers the back and sides, leaving the face clear
    canvas.drawCircle(head.translate(-hr * 0.2, 0), hr * 1.0, fill..color = hair);
    // parting + sheen
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(head.dx - hr * 0.34, -hr * 0.3),
            width: hr * 0.8,
            height: hr * 0.5),
        fill..color = _lite(hair, 0.22));
    stroke
      ..color = _dark(hair, 0.35)
      ..strokeWidth = hr * 0.1;
    canvas.drawLine(Offset(head.dx - hr * 0.9, -hr * 0.1),
        Offset(head.dx + hr * 0.1, -hr * 0.2), stroke);
  }
  canvas.drawCircle(head, hr,
      stroke..color = const Color(0x66000000)..strokeWidth = 1.4);

  if (helmet) {
    // ---- ballistic helmet: shell, camo cover, rails, NVG shroud, goggles ----
    canvas.drawCircle(head.translate(hr * 0.14, hr * 0.18), hr * 1.1,
        fill..color = const Color(0x44000000)); // contact shadow
    canvas.drawCircle(head.translate(-hr * 0.04, 0), hr * 1.14,
        fill..color = const Color(0xFF3E4634));
    // cover blotches
    fill.color = const Color(0xFF525B41);
    canvas.drawCircle(head.translate(-hr * 0.48, -hr * 0.32), hr * 0.38, fill);
    canvas.drawCircle(head.translate(-hr * 0.12, hr * 0.52), hr * 0.3, fill);
    canvas.drawCircle(head.translate(hr * 0.3, -hr * 0.46), hr * 0.22, fill);
    // crown highlight (one light source, top-left)
    canvas.drawCircle(head.translate(-hr * 0.42, -hr * 0.36), hr * 0.52,
        fill..color = const Color(0x30FFFFFF));
    // side accessory rails
    for (final s in const [-1.0, 1.0]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(head.dx - hr * 0.04, s * hr * 0.96),
                  width: hr * 1.15,
                  height: hr * 0.18),
              Radius.circular(hr * 0.06)),
          fill..color = const Color(0xFF1F241A));
      // rail teeth
      for (var i = 0; i < 4; i++) {
        canvas.drawRect(
            Rect.fromCenter(
                center: Offset(head.dx - hr * 0.5 + i * hr * 0.3, s * hr * 0.96),
                width: hr * 0.08,
                height: hr * 0.18),
            fill..color = const Color(0xFF39412C));
      }
    }
    // brow rim
    canvas.drawArc(
        Rect.fromCircle(center: head.translate(-hr * 0.04, 0), radius: hr * 1.1),
        -0.95,
        1.9,
        false,
        stroke
          ..color = const Color(0xFF272D1D)
          ..strokeWidth = hr * 0.26);
    // NVG shroud + folded night-vision tube
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(head.dx + hr * 0.64, 0),
                width: hr * 0.38,
                height: hr * 0.5),
            Radius.circular(hr * 0.09)),
        fill..color = const Color(0xFF191E12));
    canvas.drawCircle(Offset(head.dx + hr * 0.72, 0), hr * 0.14,
        fill..color = const Color(0xFF2A3320));
    canvas.drawCircle(Offset(head.dx + hr * 0.74, -hr * 0.03), hr * 0.07,
        fill..color = const Color(0xCC9FE0FF));
    // chin strap running under the jaw
    stroke
      ..color = const Color(0xFF15180F)
      ..strokeWidth = hr * 0.1;
    canvas.drawArc(
        Rect.fromCircle(center: head, radius: hr * 1.02), 0.75, 1.6, false,
        stroke);
    canvas.drawCircle(head.translate(-hr * 0.04, 0), hr * 1.14,
        stroke..color = const Color(0xFF1B1F14)..strokeWidth = hr * 0.1);
  }

  if (!helmet) _drawHeroFace(canvas, head, hr, hero, skin, fill, stroke);
  _drawAccessory(canvas, head, hr, accessory, outfit, fill, stroke);
  _drawHeroGear(canvas, r, hero, fill, stroke);

  canvas.restore();
}

/// Head-level detail that makes each hero a recognisable person rather than a
/// recoloured clone: a bandana, a beard, a ponytail, a headset.
void _drawHeroFace(Canvas canvas, Offset head, double hr, int hero, Color skin,
    Paint fill, Paint stroke) {
  switch (hero) {
    case 0: // STRIKER — cropped hair, stubble jaw
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(head.dx + hr * 0.5, 0),
              width: hr * 0.5,
              height: hr * 1.05),
          fill..color = _dark(skin, 0.3).withValues(alpha: 0.35));
      break;
    case 1: // BASTION — full beard, heavy build
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(head.dx + hr * 0.45, 0),
              width: hr * 0.72,
              height: hr * 1.35),
          fill..color = const Color(0xFF1B1712));
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(head.dx + hr * 0.78, 0),
              width: hr * 0.3,
              height: hr * 0.36),
          fill..color = _lite(skin, 0.05)); // nose stays clear of the beard
      break;
    case 2: // VORTEX — red bandana wrapped across the head
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(head.dx - hr * 0.05, 0),
                  width: hr * 0.62,
                  height: hr * 2.0),
              Radius.circular(hr * 0.16)),
          fill..color = const Color(0xFFB4262B));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(head.dx - hr * 0.12, 0),
                  width: hr * 0.2,
                  height: hr * 2.0),
              Radius.circular(hr * 0.1)),
          fill..color = const Color(0x55000000));
      // trailing knot
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(head.dx - hr * 1.05, hr * 0.5),
              width: hr * 0.5,
              height: hr * 0.26),
          fill..color = const Color(0xFF8E1D22));
      break;
    case 3: // MERCY — ponytail + comms headset
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(head.dx - hr * 1.15, 0),
              width: hr * 0.9,
              height: hr * 0.46),
          fill..color = const Color(0xFFB9853F));
      canvas.drawCircle(Offset(head.dx - hr * 0.1, -hr * 0.9), hr * 0.24,
          fill..color = const Color(0xFF1E2430));
      stroke
        ..color = const Color(0xFF1E2430)
        ..strokeWidth = hr * 0.12;
      canvas.drawArc(
          Rect.fromCircle(center: head, radius: hr * 0.9), -2.5, 1.2, false,
          stroke);
      // boom mic
      canvas.drawLine(Offset(head.dx - hr * 0.1, -hr * 0.9),
          Offset(head.dx + hr * 0.6, -hr * 0.45), stroke..strokeWidth = hr * 0.07);
      break;
    case 4: // BOOMER — grey beard, weathered
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(head.dx + hr * 0.42, 0),
              width: hr * 0.66,
              height: hr * 1.25),
          fill..color = const Color(0xFF6F6C68));
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(head.dx + hr * 0.8, 0),
              width: hr * 0.28,
              height: hr * 0.32),
          fill..color = _lite(skin, 0.05));
      break;
  }
}

/// Each hero gets their own hair so a squad reads as five different people
/// rather than five recolours of one body.
Color _heroHair(int hero) {
  switch (hero) {
    case 0:
      return const Color(0xFF2A2018); // STRIKER — dark brown
    case 1:
      return const Color(0xFF141821); // BASTION — black
    case 2:
      return const Color(0xFF6B1F1F); // VORTEX — deep red
    case 3:
      return const Color(0xFFB9853F); // MERCY — blonde
    case 4:
      return const Color(0xFF3B3A38); // BOOMER — greying
    default:
      return _hair;
  }
}

/// Signature gear drawn over the torso so each hero reads at a glance.
void _drawHeroGear(Canvas canvas, double r, int hero, Paint fill, Paint stroke) {
  if (hero < 0 || hero >= kHeroes.length) return;

  /// A patch on one shoulder — the way real kit is worn, instead of a slab
  /// bolted across the chest. Gear that follows the body is what stops these
  /// operators reading as machines.
  void shoulderPatch(double side, Color base, Color mark) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(r * 0.04, side * r * 0.74),
                width: r * 0.4,
                height: r * 0.3),
            Radius.circular(r * 0.08)),
        fill..color = base);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(r * 0.04, side * r * 0.74),
                width: r * 0.4,
                height: r * 0.3),
            Radius.circular(r * 0.08)),
        stroke
          ..color = const Color(0x66000000)
          ..strokeWidth = r * 0.03);
    canvas.drawCircle(
        Offset(r * 0.04, side * r * 0.74), r * 0.09, fill..color = mark);
  }

  /// Small unit badge low on the chest, under the vest line.
  void chestBadge(Color base, Color mark) {
    canvas.drawCircle(Offset(r * 0.16, 0), r * 0.19, fill..color = base);
    canvas.drawCircle(
        Offset(r * 0.16, 0),
        r * 0.19,
        stroke
          ..color = const Color(0x77000000)
          ..strokeWidth = r * 0.03);
    canvas.drawCircle(Offset(r * 0.16, 0), r * 0.09, fill..color = mark);
  }

  switch (kHeroes[hero].skill) {
    case SkillType.dash: // ---- STRIKER: scout ----
      // A slim monocle over ONE eye, sitting on the head — not a cyan bar
      // across the whole face like a visor-bot.
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(r * 0.62, -r * 0.16),
                  width: r * 0.2,
                  height: r * 0.26),
              Radius.circular(r * 0.08)),
          fill..color = const Color(0xE6121A24));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(r * 0.62, -r * 0.16),
                  width: r * 0.12,
                  height: r * 0.18),
              Radius.circular(r * 0.05)),
          fill..color = const Color(0xCC37D0FF));
      stroke
        ..color = const Color(0xAA121A24)
        ..strokeWidth = r * 0.07;
      canvas.drawLine(
          Offset(r * 0.56, -r * 0.24), Offset(r * 0.16, -r * 0.4), stroke);
      shoulderPatch(-1, const Color(0xFF2B3C7A), const Color(0xFF7FA0FF));
      break;

    case SkillType.shield: // ---- BASTION: heavy ----
      // real pauldrons + a breastplate that follows the torso oval
      for (final side in const [-1.0, 1.0]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: Offset(0, side * r * 0.76),
                    width: r * 0.66,
                    height: r * 0.46),
                Radius.circular(r * 0.2)),
            fill..color = const Color(0xFF3A4356));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: Offset(r * 0.1, side * r * 0.78),
                    width: r * 0.3,
                    height: r * 0.16),
                Radius.circular(r * 0.06)),
            fill..color = const Color(0x88AFC8E8));
      }
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(r * 0.18, 0), width: r * 0.62, height: r * 1.05),
          fill..color = const Color(0xFF44506A));
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(r * 0.18, 0), width: r * 0.62, height: r * 1.05),
          stroke
            ..color = const Color(0xFF8FB6E0)
            ..strokeWidth = r * 0.05);
      chestBadge(const Color(0xFF2C3A55), const Color(0xFF7FA8FF));
      break;

    case SkillType.frenzy: // ---- VORTEX: brawler ----
      stroke
        ..color = const Color(0xFF8E2A22)
        ..strokeWidth = r * 0.15;
      canvas.drawLine(
          Offset(-r * 0.3, -r * 0.62), Offset(r * 0.42, r * 0.55), stroke);
      for (var i = 0; i < 5; i++) {
        final t = i / 4;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: Offset(
                        -r * 0.3 + r * 0.72 * t, -r * 0.62 + r * 1.17 * t),
                    width: r * 0.1,
                    height: r * 0.16),
                Radius.circular(r * 0.03)),
            fill..color = const Color(0xFFE8C15A));
      }
      shoulderPatch(1, const Color(0xFF7A1F1B), const Color(0xFFFF8A80));
      break;

    case SkillType.medic: // ---- MERCY: field medic ----
      // A white ARMBAND with a red cross, the way a medic is really marked.
      // The old build stuck a big white medkit slab over the whole torso —
      // that is exactly what made this hero look like a machine.
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(r * 0.42, -r * 0.4),
                  width: r * 0.26,
                  height: r * 0.3),
              Radius.circular(r * 0.06)),
          fill..color = const Color(0xFFF2F5F8));
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(r * 0.42, -r * 0.4),
              width: r * 0.16,
              height: r * 0.06),
          fill..color = const Color(0xFFE0333F));
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(r * 0.42, -r * 0.4),
              width: r * 0.06,
              height: r * 0.16),
          fill..color = const Color(0xFFE0333F));
      // trauma pouch on the belt
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(-r * 0.12, r * 0.5),
                  width: r * 0.3,
                  height: r * 0.24),
              Radius.circular(r * 0.06)),
          fill..color = const Color(0xFFD8DEE6));
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(-r * 0.12, r * 0.5),
              width: r * 0.14,
              height: r * 0.05),
          fill..color = const Color(0xFFE0333F));
      chestBadge(const Color(0xFFE8EDF2), const Color(0xFFE0333F));
      break;

    case SkillType.grenadier: // ---- BOOMER: demolitions ----
      stroke
        ..color = const Color(0xFF4A3A22)
        ..strokeWidth = r * 0.14;
      canvas.drawLine(
          Offset(-r * 0.3, r * 0.6), Offset(r * 0.42, -r * 0.55), stroke);
      for (var i = 0; i < 4; i++) {
        final t = i / 3;
        final c = Offset(-r * 0.3 + r * 0.72 * t, r * 0.6 - r * 1.15 * t);
        canvas.drawCircle(c, r * 0.11, fill..color = const Color(0xFF3A5A32));
        canvas.drawCircle(c.translate(-r * 0.03, -r * 0.03), r * 0.05,
            fill..color = const Color(0xFF6E9A5E));
      }
      shoulderPatch(-1, const Color(0xFF6A5220), const Color(0xFFFFC24B));
      break;
  }
}

// ============================================================
//  WEAPONS
//  Every gun is built from the same small kit of parts — receiver, handguard,
//  barrel, muzzle device, magazine, optic, stock — so they read as members of
//  one armoury instead of nine different doodles. Each part gets a top
//  highlight and a bottom shade, which is what sells "machined metal" from a
//  top-down camera.
// ============================================================
const Color _gunBody = Color(0xFF343945); // receiver / polymer
const Color _gunBodyLo = Color(0xFF1D2027);
const Color _gunSteel = Color(0xFF4C5566); // barrels, bolts
const Color _gunSteelHi = Color(0xFF79839A);
const Color _gunWood = Color(0xFF6B4A2B);
const Color _gunWoodHi = Color(0xFF8C6437);
const Color _glass = Color(0xFF7FD8FF);

/// Draws a weapon pointing along +x, with the grip near the origin. [r] is the
/// operator body radius (the unit everything is measured in). When [hands] is
/// false the gloved hands are skipped — used for inventory/HUD icons.
void _drawWeapon(Canvas canvas, WeaponId w, double r, Color skin, Paint fill,
    Paint stroke, {bool hands = true}) {
  // --- primitives (all coordinates in body-radius units) ---

  /// A lengthwise part with a lit top edge and a shadowed bottom edge.
  void part(double x0, double x1, double yc, double thick, Color col,
      {double round = 0.3, double hi = 0.22, double lo = 0.3}) {
    final t = r * thick;
    final rect = Rect.fromLTRB(r * x0, r * yc - t / 2, r * x1, r * yc + t / 2);
    final rad = Radius.circular(t * round);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, rad), fill..color = col);
    // bottom shade
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(rect.left, rect.bottom - t * 0.34, rect.right,
                rect.bottom),
            rad),
        fill..color = _dark(col, lo).withValues(alpha: 0.85));
    // top highlight
    canvas.drawRect(
        Rect.fromLTRB(rect.left + t * 0.25, rect.top + t * 0.12,
            rect.right - t * 0.25, rect.top + t * 0.32),
        fill..color = _lite(col, hi).withValues(alpha: 0.75));
  }

  /// A block hanging off the gun (magazine, grip, drum housing).
  void block(double x, double y, double bw, double bh, Color col,
      {double round = 0.08}) {
    final rect = Rect.fromLTWH(r * x, r * y, r * bw, r * bh);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r * round)),
        fill..color = col);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r * round)),
        stroke
          ..color = const Color(0x66000000)
          ..strokeWidth = r * 0.035);
  }

  /// Cooling slots / rail notches across a handguard.
  void vents(double x0, double x1, double yc, int n, double thick) {
    final step = (x1 - x0) / n;
    for (var i = 0; i < n; i++) {
      final x = x0 + step * (i + 0.25);
      canvas.drawRect(
          Rect.fromLTRB(r * x, r * (yc - thick / 2), r * (x + step * 0.4),
              r * (yc + thick / 2)),
          fill..color = const Color(0x55000000));
    }
  }

  /// Muzzle brake / flash hider at the end of the barrel.
  void muzzle(double x, double thick) {
    part(x, x + 0.22, 0, thick, _gunSteel, round: 0.25);
    canvas.drawCircle(Offset(r * (x + 0.2), 0), r * thick * 0.22,
        fill..color = const Color(0xFF0C0E12));
  }

  /// Telescopic sight with a glinting lens.
  void optic(double x0, double x1, {double tube = 0.17}) {
    part(x0, x1, -0.02, tube + 0.1, _gunBodyLo, round: 0.5); // mount ring
    part(x0 + 0.05, x1 - 0.05, -0.02, tube, _gunBody, round: 0.5);
    canvas.drawCircle(Offset(r * (x1 - 0.07), -r * 0.02), r * tube * 0.42,
        fill..color = _glass.withValues(alpha: 0.85));
    canvas.drawCircle(Offset(r * (x1 - 0.09), -r * 0.06), r * tube * 0.16,
        fill..color = const Color(0xCCFFFFFF));
  }

  void hand(double x, double y, {double sz = 0.21}) {
    if (!hands) return;
    canvas.drawCircle(
        Offset(r * x, r * y), r * sz, fill..color = _dark(skin, 0.15));
    canvas.drawCircle(Offset(r * x, r * y - r * 0.04), r * sz * 0.62,
        fill..color = _lite(skin, 0.1));
  }

  /// Pistol grip angled back under the receiver.
  void grip(double x, Color col) {
    canvas.save();
    canvas.translate(r * x, r * 0.16);
    canvas.rotate(-0.42);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: r * 0.2, height: r * 0.44),
            Radius.circular(r * 0.07)),
        fill..color = col);
    canvas.restore();
  }

  switch (w) {
    case WeaponId.pistol:
      // compact slide + squared frame
      part(0.42, 1.12, -0.04, 0.26, _gunSteel); // slide
      vents(0.62, 0.98, -0.04, 3, 0.1); // serrations
      block(0.5, 0.02, 0.2, 0.34, _gunBody); // magazine well
      grip(0.56, _gunBodyLo);
      muzzle(1.06, 0.18);
      hand(0.66, 0.15);
      break;

    case WeaponId.magnum:
      part(0.42, 1.3, -0.03, 0.24, _gunSteel); // frame + barrel
      part(0.9, 1.28, -0.03, 0.15, _gunSteelHi, round: 0.4); // vented rib
      canvas.drawCircle(
          Offset(r * 0.72, -r * 0.02), r * 0.23, fill..color = _gunBodyLo);
      canvas.drawCircle(Offset(r * 0.72, -r * 0.02), r * 0.23,
          stroke
            ..color = _gunSteelHi
            ..strokeWidth = r * 0.05); // cylinder
      for (var i = 0; i < 5; i++) {
        final a = i * 1.257;
        canvas.drawCircle(
            Offset(r * 0.72 + math.cos(a) * r * 0.13,
                -r * 0.02 + math.sin(a) * r * 0.13),
            r * 0.045,
            fill..color = const Color(0xFF12141A));
      }
      grip(0.52, _gunWood);
      hand(0.6, 0.15);
      break;

    case WeaponId.smg:
      part(0.34, 0.98, -0.02, 0.36, _gunBody); // receiver
      part(0.9, 1.42, -0.02, 0.18, _gunSteel); // barrel shroud
      vents(0.95, 1.32, -0.02, 4, 0.14);
      block(0.58, 0.14, 0.19, 0.62, _gunBodyLo); // long magazine
      grip(0.46, _gunBodyLo);
      muzzle(1.4, 0.15);
      hand(0.62, 0.15);
      hand(1.06, -0.01);
      break;

    case WeaponId.shotgun:
      part(0.3, 0.92, -0.02, 0.34, _gunWood); // stock/receiver
      part(0.86, 1.62, -0.06, 0.24, _gunSteel); // barrel
      part(0.9, 1.5, 0.12, 0.16, _gunWoodHi, round: 0.4); // pump / tube
      block(0.62, -0.24, 0.26, 0.16, _gunBodyLo); // ejection port
      grip(0.44, _gunWood);
      muzzle(1.6, 0.22);
      hand(0.6, 0.16);
      hand(1.14, 0.08);
      break;

    case WeaponId.rifle:
      part(0.12, 0.5, -0.02, 0.3, _gunBodyLo); // stock
      part(0.4, 1.06, -0.02, 0.36, _gunBody); // receiver
      part(1.0, 1.78, -0.03, 0.2, _gunSteel); // handguard + barrel
      vents(1.06, 1.6, -0.03, 5, 0.15);
      part(0.62, 0.98, -0.22, 0.08, _gunBodyLo, round: 0.5); // top rail
      block(0.7, 0.14, 0.2, 0.52, _gunBodyLo); // curved magazine
      grip(0.56, _gunBodyLo);
      muzzle(1.76, 0.17);
      hand(0.66, 0.15);
      hand(1.28, -0.02);
      break;

    case WeaponId.dmr:
      part(0.08, 0.48, -0.02, 0.32, _gunBodyLo); // stock + cheek riser
      part(0.4, 1.02, -0.02, 0.34, _gunBody); // receiver
      part(0.98, 1.92, -0.03, 0.17, _gunSteel); // long barrel
      optic(0.66, 1.06, tube: 0.15);
      block(0.7, 0.13, 0.18, 0.44, _gunBodyLo); // magazine
      grip(0.54, _gunBodyLo);
      muzzle(1.9, 0.15);
      hand(0.64, 0.15);
      hand(1.36, -0.02);
      break;

    case WeaponId.sniper:
      part(0.02, 0.46, -0.02, 0.32, _gunWood); // wooden stock
      part(0.38, 1.0, -0.02, 0.3, _gunBody); // action
      part(0.96, 2.16, -0.03, 0.15, _gunSteel); // heavy barrel
      optic(0.6, 1.12, tube: 0.2); // big glass
      block(0.68, 0.11, 0.16, 0.34, _gunBodyLo);
      part(1.5, 1.78, 0.16, 0.07, _gunBodyLo, round: 0.5); // bipod leg
      grip(0.5, _gunWoodHi);
      muzzle(2.12, 0.16);
      hand(0.62, 0.15);
      hand(1.52, -0.02);
      break;

    case WeaponId.lmg:
      part(0.06, 0.46, -0.02, 0.34, _gunBodyLo); // stock
      part(0.38, 1.06, -0.02, 0.42, _gunBody); // big receiver
      part(1.0, 1.9, -0.04, 0.22, _gunSteel); // barrel
      vents(1.06, 1.7, -0.04, 6, 0.17);
      canvas.drawCircle(
          Offset(r * 0.76, r * 0.42), r * 0.32, fill..color = _gunBodyLo); // drum
      canvas.drawCircle(Offset(r * 0.76, r * 0.42), r * 0.32,
          stroke
            ..color = _gunSteelHi.withValues(alpha: 0.7)
            ..strokeWidth = r * 0.05);
      canvas.drawCircle(
          Offset(r * 0.76, r * 0.42), r * 0.12, fill..color = _gunSteel);
      part(1.44, 1.74, 0.2, 0.07, _gunBodyLo, round: 0.5); // bipod
      grip(0.54, _gunBodyLo);
      muzzle(1.88, 0.2);
      hand(0.64, 0.16);
      hand(1.34, -0.03);
      break;

    case WeaponId.minigun:
      part(0.22, 0.94, 0, 0.62, _gunBody, round: 0.18); // housing
      block(0.3, -0.34, 0.26, 0.24, _gunBodyLo); // motor cover
      // six rotating barrels, brightest in the middle for a round look
      for (final dy in const [-0.22, -0.11, 0.0, 0.11, 0.22]) {
        part(0.88, 1.86, dy, 0.1,
            dy.abs() < 0.06 ? _gunSteelHi : _gunSteel, round: 0.5);
      }
      canvas.drawCircle(
          Offset(r * 1.86, 0), r * 0.3, fill..color = const Color(0x33000000));
      block(0.34, 0.3, 0.42, 0.3, _gunBodyLo); // ammo box
      hand(0.52, 0.24);
      hand(0.92, -0.2);
      break;
  }
}

/// Draws [w] as a standalone icon centred in a [width]-wide box — used by the
/// weapon panel, the slot switcher, ground loot and the shop so the gun you see
/// in the UI is exactly the gun in your hands.
void drawGunIcon(Canvas canvas, Offset centre, double width, WeaponId w,
    {Paint? fill, Paint? stroke}) {
  final f = fill ?? (Paint()..style = PaintingStyle.fill);
  final s = stroke ?? (Paint()..style = PaintingStyle.stroke);
  // guns live in x ∈ [0.0, 2.3] body-radii; scale so that span fills the box
  final r = width / 2.3;
  canvas.save();
  canvas.translate(centre.dx - width / 2, centre.dy + r * 0.05);
  _drawWeapon(canvas, w, r, const Color(0xFFF4CBA2), f, s, hands: false);
  canvas.restore();
}

/// Draws just the head gear at [head] with head-radius [hr] — used by the shop
/// so an accessory tile shows the actual accessory instead of a distant body.
void drawAccessoryIcon(Canvas canvas, Offset head, double hr, int accessory,
    Color outfit,
    {Paint? fill, Paint? stroke}) {
  _drawAccessory(
      canvas,
      head,
      hr,
      accessory,
      outfit,
      fill ?? (Paint()..style = PaintingStyle.fill),
      stroke ?? (Paint()..style = PaintingStyle.stroke));
}

/// Head gear, drawn from above. Every piece gets a lit top edge, a shaded
/// underside and one or two "story" details (a cap button, a knit rib, a
/// helmet rail) — that's what separates a real accessory from a coloured blob.
void _drawAccessory(Canvas canvas, Offset head, double hr, int acc, Color outfit,
    Paint fill, Paint stroke) {
  // soft contact shadow under any headwear, so it sits ON the head
  void gearShadow(double rad) {
    canvas.drawCircle(head.translate(hr * 0.12, hr * 0.16), rad,
        fill..color = const Color(0x33000000));
  }

  switch (acc) {
    case 1: // ---- Cap: crown panels, seam, button, curved visor ----
      gearShadow(hr * 1.0);
      // visor first so the crown overlaps it
      final visor = Path()
        ..moveTo(head.dx + hr * 0.35, -hr * 0.78)
        ..quadraticBezierTo(
            head.dx + hr * 1.7, 0, head.dx + hr * 0.35, hr * 0.78)
        ..close();
      canvas.drawPath(visor, fill..color = _dark(outfit, 0.42));
      canvas.drawPath(
          visor,
          stroke
            ..color = const Color(0x55000000)
            ..strokeWidth = hr * 0.06);
      canvas.drawCircle(
          head.translate(-hr * 0.1, 0), hr * 0.98, fill..color = outfit);
      // panel seams
      stroke
        ..color = _dark(outfit, 0.3)
        ..strokeWidth = hr * 0.07;
      for (final a in const [-0.9, 0.0, 0.9]) {
        canvas.drawLine(
            head.translate(-hr * 0.1, 0),
            Offset(head.dx - hr * 0.1 + math.cos(a) * hr * 0.98,
                math.sin(a) * hr * 0.98),
            stroke);
      }
      // crown highlight + button
      canvas.drawCircle(head.translate(-hr * 0.38, -hr * 0.34), hr * 0.34,
          fill..color = _lite(outfit, 0.22));
      canvas.drawCircle(head.translate(-hr * 0.1, 0), hr * 0.13,
          fill..color = _dark(outfit, 0.45));
      break;

    case 2: // ---- Beanie: knit ribs + rolled brim + pom ----
      gearShadow(hr * 1.05);
      canvas.drawCircle(
          head.translate(-hr * 0.05, 0), hr * 1.02, fill..color = outfit);
      // knit ribbing
      stroke
        ..color = _dark(outfit, 0.28)
        ..strokeWidth = hr * 0.09;
      for (var i = -3; i <= 3; i++) {
        final y = i * hr * 0.26;
        canvas.drawLine(Offset(head.dx - hr * 0.95, y),
            Offset(head.dx + hr * 0.55, y), stroke);
      }
      // rolled brim across the forehead
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: head.translate(hr * 0.72, 0),
                  width: hr * 0.42,
                  height: hr * 1.9),
              Radius.circular(hr * 0.2)),
          fill..color = _lite(outfit, 0.16));
      canvas.drawCircle(head.translate(-hr * 0.05, 0), hr * 1.02,
          stroke..color = _dark(outfit, 0.4)..strokeWidth = hr * 0.08);
      // bobble
      canvas.drawCircle(head.translate(-hr * 1.05, 0), hr * 0.3,
          fill..color = _lite(outfit, 0.3));
      break;

    case 3: // ---- Headband: cloth strip, knot and trailing tails ----
      gearShadow(hr * 0.7);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: head.translate(hr * 0.24, 0),
                  width: hr * 0.52,
                  height: hr * 2.05),
              Radius.circular(hr * 0.16)),
          fill..color = const Color(0xFFD8313F));
      canvas.drawRect(
          Rect.fromCenter(
              center: head.translate(hr * 0.12, 0),
              width: hr * 0.14,
              height: hr * 2.05),
          fill..color = const Color(0x44000000));
      // knot on the left temple + two tails
      canvas.drawCircle(head.translate(hr * 0.2, -hr * 0.95), hr * 0.22,
          fill..color = const Color(0xFFB92533));
      for (final s in const [-1.0, 1.0]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: head.translate(-hr * 0.45, s * hr * 1.02),
                    width: hr * 0.9,
                    height: hr * 0.2),
                Radius.circular(hr * 0.08)),
            fill..color = const Color(0xFFC22B39));
      }
      break;

    case 4: // ---- Combat helmet: shell, cover, rails, strap ----
      gearShadow(hr * 1.1);
      canvas.drawCircle(head.translate(-hr * 0.05, 0), hr * 1.08,
          fill..color = const Color(0xFF3F462F));
      // camo cover blotches
      fill.color = const Color(0xFF565E3F);
      canvas.drawCircle(head.translate(-hr * 0.45, -hr * 0.3), hr * 0.36, fill);
      canvas.drawCircle(head.translate(-hr * 0.1, hr * 0.5), hr * 0.28, fill);
      canvas.drawCircle(head.translate(hr * 0.35, -hr * 0.42), hr * 0.22, fill);
      // lit crown
      canvas.drawCircle(head.translate(-hr * 0.4, -hr * 0.35), hr * 0.5,
          fill..color = const Color(0x33FFFFFF));
      // side rails
      for (final s in const [-1.0, 1.0]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: head.translate(-hr * 0.05, s * hr * 0.92),
                    width: hr * 1.1,
                    height: hr * 0.18),
                Radius.circular(hr * 0.06)),
            fill..color = const Color(0xFF23281B));
      }
      // brow rim + NVG shroud
      canvas.drawArc(
          Rect.fromCircle(center: head.translate(-hr * 0.05, 0), radius: hr * 1.05),
          -0.95,
          1.9,
          false,
          stroke
            ..color = const Color(0xFF262C1C)
            ..strokeWidth = hr * 0.26);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: head.translate(hr * 0.72, 0),
                  width: hr * 0.36,
                  height: hr * 0.46),
              Radius.circular(hr * 0.08)),
          fill..color = const Color(0xFF1B1F14));
      canvas.drawCircle(head.translate(hr * 0.78, 0), hr * 0.1,
          fill..color = const Color(0xCC9FE0FF));
      break;

    case 5: // ---- Shades: twin lenses, bridge, temples, glint ----
      // temples running back along the sides
      stroke
        ..color = const Color(0xFF1A1D24)
        ..strokeWidth = hr * 0.12;
      for (final s in const [-1.0, 1.0]) {
        canvas.drawLine(Offset(head.dx + hr * 0.5, s * hr * 0.62),
            Offset(head.dx - hr * 0.55, s * hr * 0.86), stroke);
      }
      for (final s in const [-1.0, 1.0]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: head.translate(hr * 0.58, s * hr * 0.4),
                    width: hr * 0.4,
                    height: hr * 0.62),
                Radius.circular(hr * 0.14)),
            fill..color = const Color(0xFF11141A));
        // lens sheen
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: head.translate(hr * 0.66, s * hr * 0.5),
                    width: hr * 0.14,
                    height: hr * 0.3),
                Radius.circular(hr * 0.06)),
            fill..color = const Color(0x88A8D8FF));
      }
      // bridge
      canvas.drawRect(
          Rect.fromCenter(
              center: head.translate(hr * 0.58, 0),
              width: hr * 0.36,
              height: hr * 0.14),
          fill..color = const Color(0xFF1A1D24));
      break;

    case 6: // ---- Mohawk: spiked crest with root shading ----
      final crest = Path();
      for (var i = 0; i <= 6; i++) {
        final t = i / 6.0;
        final x = head.dx - hr * 0.95 + hr * 1.75 * t;
        final spike = hr * (0.34 + 0.22 * math.sin(t * math.pi));
        if (i == 0) {
          crest.moveTo(x, -hr * 0.06);
        }
        crest.lineTo(x - hr * 0.08, -spike);
        crest.lineTo(x + hr * 0.08, -hr * 0.06);
      }
      for (var i = 6; i >= 0; i--) {
        final t = i / 6.0;
        final x = head.dx - hr * 0.95 + hr * 1.75 * t;
        final spike = hr * (0.34 + 0.22 * math.sin(t * math.pi));
        crest.lineTo(x + hr * 0.08, spike);
        crest.lineTo(x - hr * 0.08, hr * 0.06);
      }
      crest.close();
      canvas.drawPath(crest, fill..color = const Color(0xFFE12F5F));
      canvas.drawPath(
          crest,
          stroke
            ..color = const Color(0xFF7A1330)
            ..strokeWidth = hr * 0.07);
      // shaved sides
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: head.translate(-hr * 0.1, 0),
                  width: hr * 1.8,
                  height: hr * 0.22),
              Radius.circular(hr * 0.1)),
          fill..color = const Color(0xFFFF6A93));
      break;

    case 7: // ---- Mask: respirator with filter + straps ----
      // straps around the head
      stroke
        ..color = const Color(0xFF191D26)
        ..strokeWidth = hr * 0.14;
      canvas.drawArc(Rect.fromCircle(center: head, radius: hr * 0.95), 0.6, 1.4,
          false, stroke);
      canvas.drawArc(Rect.fromCircle(center: head, radius: hr * 0.95), -2.0, 1.4,
          false, stroke);
      // mask body over the mouth/nose
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: head.translate(hr * 0.5, 0),
                  width: hr * 0.78,
                  height: hr * 1.45),
              Radius.circular(hr * 0.26)),
          fill..color = const Color(0xFF262B36));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: head.translate(hr * 0.44, 0),
                  width: hr * 0.5,
                  height: hr * 1.1),
              Radius.circular(hr * 0.2)),
          fill..color = const Color(0xFF323947));
      // filter canister + vents
      canvas.drawCircle(head.translate(hr * 0.86, 0), hr * 0.26,
          fill..color = const Color(0xFF171B22));
      canvas.drawCircle(head.translate(hr * 0.86, 0), hr * 0.13,
          fill..color = const Color(0xFF4C5566));
      break;

    case 8: // ---- Crown: band, points, set gems ----
      gearShadow(hr * 0.95);
      canvas.drawCircle(
          head.translate(-hr * 0.05, 0),
          hr * 0.92,
          stroke
            ..color = const Color(0xFFE8B830)
            ..strokeWidth = hr * 0.26);
      canvas.drawCircle(
          head.translate(-hr * 0.05, 0),
          hr * 0.92,
          stroke
            ..color = const Color(0x66FFF3B0)
            ..strokeWidth = hr * 0.1);
      for (final a in const [-1.25, -0.42, 0.42, 1.25]) {
        final cx = head.dx - hr * 0.05 + math.cos(a - 1.57) * hr * 0.92;
        final cy = head.dy + math.sin(a - 1.57) * hr * 0.92;
        // pointed tine
        final tine = Path()
          ..moveTo(cx - hr * 0.16, cy)
          ..lineTo(cx, cy - hr * 0.34)
          ..lineTo(cx + hr * 0.16, cy)
          ..close();
        canvas.drawPath(tine, fill..color = const Color(0xFFFFD75E));
        canvas.drawCircle(Offset(cx, cy - hr * 0.06), hr * 0.11,
            fill..color = const Color(0xFFFF4D6D));
      }
      break;

    case 9: // ---- Horns: curved, ridged, bone-coloured ----
      for (final s in const [-1.0, 1.0]) {
        final horn = Path()
          ..moveTo(head.dx - hr * 0.15, head.dy + s * hr * 0.55)
          ..quadraticBezierTo(head.dx - hr * 1.15, head.dy + s * hr * 0.75,
              head.dx - hr * 0.95, head.dy + s * hr * 1.5)
          ..quadraticBezierTo(head.dx - hr * 0.4, head.dy + s * hr * 1.0,
              head.dx + hr * 0.12, head.dy + s * hr * 0.95)
          ..close();
        canvas.drawPath(horn, fill..color = const Color(0xFFEDE6D2));
        canvas.drawPath(
            horn,
            stroke
              ..color = const Color(0xFF8C8168)
              ..strokeWidth = hr * 0.07);
        // growth ridges
        stroke
          ..color = const Color(0x668C8168)
          ..strokeWidth = hr * 0.06;
        for (var i = 1; i <= 3; i++) {
          final t = i / 4.0;
          canvas.drawLine(
              Offset(head.dx - hr * 0.15 - hr * 0.8 * t,
                  head.dy + s * (hr * 0.6 + hr * 0.5 * t)),
              Offset(head.dx - hr * 0.05 - hr * 0.75 * t,
                  head.dy + s * (hr * 0.95 + hr * 0.2 * t)),
              stroke);
        }
      }
      break;

    default:
      break; // None
  }
}

// =====================================================================
//  HERO PORTRAITS (front view)
//
//  The in-match art is top-down because that's the camera — but a bird's-eye
//  body will never read as a *character*. Menus, the shop and the result card
//  therefore use this: a proper front-facing bust with a face, hair, gear and
//  the hero's weapon held across the chest. It's the difference between "a
//  coloured blob" and "my operator".
// =====================================================================

class _HeroLook {
  final String name;
  final Color hair;
  final Color accent;
  final bool beard;
  final bool longHair; // ponytail
  final bool bandana;
  final bool visor;
  final bool headset;
  final Color eyes;
  const _HeroLook(this.name, this.hair, this.accent,
      {this.beard = false,
      this.longHair = false,
      this.bandana = false,
      this.visor = false,
      this.headset = false,
      this.eyes = const Color(0xFF2B3A4A)});
}

const List<_HeroLook> _looks = [
  _HeroLook('STRIKER', Color(0xFF2A2018), Color(0xFF4F6BFF),
      visor: true, eyes: Color(0xFF35507A)),
  _HeroLook('BASTION', Color(0xFF141821), Color(0xFF37D0FF),
      beard: true, eyes: Color(0xFF2E4A55)),
  _HeroLook('VORTEX', Color(0xFF5E1A1A), Color(0xFFFF5A5F),
      bandana: true, eyes: Color(0xFF6B2C2C)),
  _HeroLook('MERCY', Color(0xFFB9853F), Color(0xFF52E06A),
      longHair: true, headset: true, eyes: Color(0xFF3E6B4A)),
  _HeroLook('BOOMER', Color(0xFF57534E), Color(0xFFFFB02E),
      beard: true, eyes: Color(0xFF5A4A32)),
];

/// Draws a front-facing operator bust filling [box] — a premium character
/// card, not a game sprite.
///
/// What makes it read as "premium" rather than clip-art:
///  * portrait proportions (head ≈ a third of the bust, wide shoulders),
///  * a coloured spotlight behind the operator in their hero accent,
///  * one hard key light from the upper left plus a cool rim light on the
///    right edge, which is the trick that gives flat vector art depth,
///  * a sculpted face — brow ridge, cheekbone, jaw and chin shadows — instead
///    of a circle with two dots.
void drawHeroPortrait(
  Canvas canvas,
  Rect box, {
  required Color outfit,
  required Color skin,
  int accessory = 0,
  int hero = 0,
  WeaponId? weapon,
  bool showWeapon = true,
}) {
  final look = _looks[hero.clamp(0, _looks.length - 1)];
  final fill = Paint()..style = PaintingStyle.fill;
  final stroke = Paint()..style = PaintingStyle.stroke;

  // Work in a 100x100 space, then map it onto the box.
  final s = math.min(box.width, box.height) / 100.0;
  canvas.save();
  canvas.translate(box.center.dx, box.center.dy);
  canvas.scale(s);
  canvas.translate(-50, -50);
  canvas.clipRect(const Rect.fromLTWH(-2, -2, 104, 104));

  final skinDark = _dark(skin, 0.3);
  final skinShade = _dark(skin, 0.16);
  final skinLite = _lite(skin, 0.16);
  final coat = _dark(outfit, 0.12);
  final coatDark = _dark(outfit, 0.5);
  final coatLite = _lite(outfit, 0.22);
  const rim = Color(0x8899D8FF); // cool rim light
  final key = look.accent;

  // ---------------- backdrop: hero-coloured spotlight ----------------
  canvas.drawRect(
      const Rect.fromLTWH(-2, -2, 104, 104),
      fill
        ..shader = Gradient.radial(const Offset(50, 34), 62, [
          key.withValues(alpha: 0.30),
          key.withValues(alpha: 0.07),
          const Color(0x00000000),
        ], [
          0.0,
          0.55,
          1.0
        ]));
  fill.shader = null;
  // floor glow so the bust isn't floating in a void
  canvas.drawOval(
      const Rect.fromLTRB(14, 88, 86, 104),
      fill..color = key.withValues(alpha: 0.16));

  // ---------------- shoulders / torso ----------------
  final torso = Path()
    ..moveTo(50, 54)
    ..cubicTo(66, 55, 78, 66, 84, 104)
    ..lineTo(16, 104)
    ..cubicTo(22, 66, 34, 55, 50, 54)
    ..close();
  canvas.drawPath(torso, fill..color = coat);
  // key light from upper-left
  canvas.drawPath(
      Path()
        ..moveTo(50, 54)
        ..cubicTo(38, 56, 28, 68, 24, 104)
        ..lineTo(40, 104)
        ..cubicTo(42, 74, 46, 62, 50, 54)
        ..close(),
      fill..color = coatLite.withValues(alpha: 0.55));
  // shadow side
  canvas.drawPath(
      Path()
        ..moveTo(84, 104)
        ..cubicTo(78, 70, 70, 58, 60, 55)
        ..lineTo(66, 104)
        ..close(),
      fill..color = coatDark.withValues(alpha: 0.75));

  // jacket collar, raised and angled
  canvas.drawPath(
      Path()
        ..moveTo(50, 58)
        ..lineTo(36, 56)
        ..lineTo(40, 74)
        ..close(),
      fill..color = coatDark);
  canvas.drawPath(
      Path()
        ..moveTo(50, 58)
        ..lineTo(64, 56)
        ..lineTo(60, 74)
        ..close(),
      fill..color = _dark(outfit, 0.32));
  // zip line
  stroke
    ..color = coatDark
    ..strokeWidth = 1.4;
  canvas.drawLine(const Offset(50, 60), const Offset(50, 100), stroke);

  // ---------------- chest rig ----------------
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(34, 74, 32, 30), const Radius.circular(4)),
      fill..color = _dark(outfit, 0.62));
  for (final x in const [36.0, 47.0, 58.0]) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, 82, 8, 13), const Radius.circular(2)),
        fill..color = _dark(outfit, 0.45));
    canvas.drawRect(Rect.fromLTWH(x, 82, 8, 2.5),
        fill..color = coatLite.withValues(alpha: 0.4));
  }
  // shoulder straps
  stroke
    ..color = _dark(outfit, 0.7)
    ..strokeWidth = 4.5;
  canvas.drawLine(const Offset(40, 60), const Offset(38, 76), stroke);
  canvas.drawLine(const Offset(60, 60), const Offset(62, 76), stroke);
  // hero indicator light
  canvas.drawCircle(const Offset(50, 79), 3.2, fill..color = key);
  canvas.drawCircle(const Offset(49.2, 78.2), 1.3,
      fill..color = const Color(0xCCFFFFFF));

  // ---------------- neck ----------------
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(44, 40, 12, 18), const Radius.circular(4)),
      fill..color = skinShade);
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(44, 40, 12, 7), const Radius.circular(3)),
      fill..color = skinDark); // shadow under the jaw

  // ---------------- head ----------------
  const cx = 50.0, cy = 27.0;
  const rx = 13.0, ry = 16.0;
  // ears
  for (final side in const [-1.0, 1.0]) {
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx + side * rx, cy + 3), width: 5, height: 8),
        fill..color = side < 0 ? skin : skinShade);
  }
  // skull + jaw + chin
  final face = Path()
    ..moveTo(cx - rx, cy - 2)
    ..cubicTo(cx - rx, cy - ry - 3, cx + rx, cy - ry - 3, cx + rx, cy - 2)
    ..cubicTo(cx + rx, cy + 9, cx + 6, cy + ry, cx, cy + ry)
    ..cubicTo(cx - 6, cy + ry, cx - rx, cy + 9, cx - rx, cy - 2)
    ..close();
  canvas.drawPath(face, fill..color = skin);
  // key light on the left cheek/forehead
  canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 5, cy - 4), width: 14, height: 18),
      fill..color = skinLite.withValues(alpha: 0.55));
  // shadow down the right side + under the cheekbone
  canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 8, cy + 1), width: 11, height: 20),
      fill..color = skinShade.withValues(alpha: 0.6));
  canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 5, cy + 7), width: 9, height: 6),
      fill..color = skinDark.withValues(alpha: 0.3));
  // brow ridge shadow
  canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 5), width: 22, height: 5),
      fill..color = skinShade.withValues(alpha: 0.45));

  // brows — angled, heroic
  stroke
    ..color = _dark(look.hair, 0.25)
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(Offset(cx - 9, cy - 4.4), Offset(cx - 3, cy - 6.2), stroke);
  canvas.drawLine(Offset(cx + 3, cy - 6.2), Offset(cx + 9, cy - 4.4), stroke);

  // eyes
  for (final side in const [-1.0, 1.0]) {
    final ex = cx + side * 5.8;
    canvas.drawOval(
        Rect.fromCenter(center: Offset(ex, cy - 0.6), width: 7.4, height: 4.8),
        fill..color = const Color(0xFFEFF2F6));
    canvas.drawOval(
        Rect.fromCenter(center: Offset(ex, cy + 0.6), width: 7.4, height: 2.4),
        fill..color = const Color(0x22000000)); // lower lid shadow
    canvas.drawCircle(Offset(ex + side * 0.4, cy - 0.6), 2.1,
        fill..color = look.eyes);
    canvas.drawCircle(
        Offset(ex + side * 0.4, cy - 0.6), 0.95, fill..color = const Color(0xFF0B0D12));
    canvas.drawCircle(Offset(ex + side * 0.4 - 0.8, cy - 1.5), 0.75,
        fill..color = const Color(0xF2FFFFFF));
    stroke
      ..color = const Color(0xAA10141C)
      ..strokeWidth = 1.15;
    canvas.drawLine(Offset(ex - 3.8, cy - 2.6), Offset(ex + 3.8, cy - 2.6), stroke);
  }

  // nose (bridge highlight + nostril shadow) and mouth
  canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 0.5, cy + 3), width: 3.4, height: 8),
      fill..color = skinLite.withValues(alpha: 0.5));
  canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 1.8, cy + 6.4), width: 4, height: 3),
      fill..color = skinDark.withValues(alpha: 0.5));
  if (!look.beard) {
    stroke
      ..color = _dark(skin, 0.5)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(cx - 3.4, cy + 10.4), Offset(cx + 3.4, cy + 10.4),
        stroke);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy + 12.6), width: 6, height: 2.4),
        fill..color = skinShade.withValues(alpha: 0.5)); // chin crease
  }

  // ---------------- hair ----------------
  if (look.longHair) {
    canvas.drawPath(
        Path()
          ..moveTo(cx - rx - 3, cy - 4)
          ..cubicTo(cx - rx - 7, cy + 22, cx - 10, cy + 30, cx - 4, cy + 30)
          ..lineTo(cx - 6, cy + 8)
          ..close(),
        fill..color = _dark(look.hair, 0.18));
    canvas.drawPath(
        Path()
          ..moveTo(cx + rx + 3, cy - 4)
          ..cubicTo(cx + rx + 8, cy + 24, cx + 12, cy + 34, cx + 5, cy + 34)
          ..lineTo(cx + 7, cy + 8)
          ..close(),
        fill..color = look.hair);
  }
  if (!look.bandana) {
    // swept fringe with volume
    final hair = Path()
      ..moveTo(cx - rx - 1.5, cy + 1)
      ..cubicTo(cx - rx - 2, cy - ry - 8, cx + rx + 2, cy - ry - 8, cx + rx + 1.5,
          cy + 1)
      ..cubicTo(cx + rx - 1, cy - 8, cx + 6, cy - 6, cx + 1, cy - 7)
      ..cubicTo(cx - 6, cy - 8, cx - rx + 2, cy - 4, cx - rx - 1.5, cy + 1)
      ..close();
    canvas.drawPath(hair, fill..color = look.hair);
    // strand highlights
    stroke
      ..color = _lite(look.hair, 0.34).withValues(alpha: 0.8)
      ..strokeWidth = 1.5;
    for (var i = 0; i < 3; i++) {
      final ox = -7.0 + i * 5.0;
      canvas.drawLine(Offset(cx + ox, cy - ry - 1), Offset(cx + ox + 4, cy - 7),
          stroke);
    }
  }
  if (look.beard) {
    final beard = Path()
      ..moveTo(cx - rx + 0.5, cy + 1)
      ..cubicTo(cx - 12, cy + 20, cx + 12, cy + 20, cx + rx - 0.5, cy + 1)
      ..cubicTo(cx + 9, cy + 13, cx - 9, cy + 13, cx - rx + 0.5, cy + 1)
      ..close();
    canvas.drawPath(beard, fill..color = look.hair);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy + 12), width: 17, height: 11),
        fill..color = look.hair);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy + 8), width: 11, height: 3.6),
        fill..color = _dark(look.hair, 0.2)); // moustache
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx - 4, cy + 11), width: 7, height: 5),
        fill..color = _lite(look.hair, 0.18).withValues(alpha: 0.6));
  }

  // ---------------- hero signature ----------------
  if (look.bandana) {
    canvas.drawPath(
        Path()
          ..moveTo(cx - rx - 1.5, cy - 3)
          ..cubicTo(cx - rx - 2, cy - ry - 6, cx + rx + 2, cy - ry - 6,
              cx + rx + 1.5, cy - 3)
          ..lineTo(cx + rx + 1, cy - 9)
          ..lineTo(cx - rx - 1, cy - 9)
          ..close(),
        fill..color = const Color(0xFFC22B39));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, cy - 9), width: 30, height: 6),
            const Radius.circular(2)),
        fill..color = const Color(0xFFB4262B));
    canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, cy - 9), width: 30, height: 1.6),
        fill..color = const Color(0x55000000));
    canvas.drawPath(
        Path()
          ..moveTo(cx - 15, cy - 8)
          ..lineTo(cx - 22, cy + 8)
          ..lineTo(cx - 16, cy + 9)
          ..close(),
        fill..color = const Color(0xFFB4262B));
  }
  if (look.visor) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, cy - 1), width: 30, height: 9),
            const Radius.circular(4.5)),
        fill..color = const Color(0xE60E1621));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, cy - 1), width: 26, height: 5.5),
            const Radius.circular(3)),
        fill..color = const Color(0xDD37D0FF));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx - 7, cy - 2), width: 9, height: 2),
            const Radius.circular(1)),
        fill..color = const Color(0xAAFFFFFF));
    canvas.drawCircle(Offset(cx + 14, cy - 1), 2, fill..color = const Color(0xFF1B2531));
  }
  if (look.headset) {
    stroke
      ..color = const Color(0xFF1B2230)
      ..strokeWidth = 2.8;
    canvas.drawArc(
        Rect.fromCenter(center: Offset(cx, cy - 1), width: 31, height: 33),
        math.pi + 0.3, math.pi - 0.6, false, stroke);
    for (final side in const [-1.0, 1.0]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(cx + side * 14.5, cy + 1),
                  width: 5.5,
                  height: 9),
              const Radius.circular(2.5)),
          fill..color = const Color(0xFF232B3A));
      canvas.drawCircle(Offset(cx + side * 14.5, cy + 1), 1.4,
          fill..color = key.withValues(alpha: 0.9));
    }
    stroke
      ..color = const Color(0xFF232B3A)
      ..strokeWidth = 1.6;
    canvas.drawLine(Offset(cx - 14, cy + 5), Offset(cx - 5, cy + 11), stroke);
    canvas.drawCircle(Offset(cx - 4.4, cy + 11.4), 1.7, fill..color = key);
  }

  // ---------------- accessory ----------------
  _drawAccessoryFront(canvas, const Offset(cx, cy), rx, ry, accessory, outfit,
      fill, stroke);

  // ---------------- rim light (last, over everything) ----------------
  stroke
    ..color = rim
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round;
  canvas.drawArc(
      Rect.fromCenter(center: const Offset(cx, cy), width: rx * 2, height: ry * 2),
      -0.9, 1.5, false, stroke);
  canvas.drawPath(
      Path()
        ..moveTo(62, 56)
        ..cubicTo(74, 62, 80, 74, 84, 104),
      stroke..color = rim.withValues(alpha: 0.45));

  // ---------------- weapon ----------------
  if (showWeapon && weapon != null) {
    canvas.save();
    canvas.translate(54, 88);
    canvas.rotate(-0.38);
    drawGunIcon(canvas, Offset.zero, 58, weapon, fill: fill, stroke: stroke);
    canvas.restore();
    canvas.drawCircle(const Offset(41, 95), 5.5,
        fill..color = const Color(0xFF23262E));
    canvas.drawCircle(const Offset(40, 93.6), 2.4,
        fill..color = const Color(0xFF343A46));
  }

  canvas.restore();
}

/// Head gear seen from the front (portraits only).
void _drawAccessoryFront(Canvas canvas, Offset head, double hw, double hh,
    int acc, Color outfit, Paint fill, Paint stroke) {
  switch (acc) {
    case 1: // cap
      canvas.drawPath(
          Path()
            ..moveTo(head.dx - hw - 1, head.dy - 6)
            ..cubicTo(head.dx - hw, head.dy - hh - 6, head.dx + hw,
                head.dy - hh - 6, head.dx + hw + 1, head.dy - 6)
            ..close(),
          fill..color = _dark(outfit, 0.05));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(head.dx, head.dy - 6), width: 42, height: 7),
              const Radius.circular(3)),
          fill..color = _dark(outfit, 0.3));
      canvas.drawCircle(Offset(head.dx, head.dy - hh - 2), 2.4,
          fill..color = _dark(outfit, 0.45));
      break;
    case 2: // beanie
      canvas.drawPath(
          Path()
            ..moveTo(head.dx - hw - 1, head.dy - 4)
            ..cubicTo(head.dx - hw - 1, head.dy - hh - 8, head.dx + hw + 1,
                head.dy - hh - 8, head.dx + hw + 1, head.dy - 4)
            ..close(),
          fill..color = outfit);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(head.dx, head.dy - 5), width: 38, height: 8),
              const Radius.circular(4)),
          fill..color = _lite(outfit, 0.18));
      canvas.drawCircle(Offset(head.dx, head.dy - hh - 8), 4,
          fill..color = _lite(outfit, 0.3));
      break;
    case 3: // headband
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(head.dx, head.dy - 10), width: 38, height: 8),
              const Radius.circular(3)),
          fill..color = const Color(0xFFD8313F));
      break;
    case 4: // combat helmet
      canvas.drawPath(
          Path()
            ..moveTo(head.dx - hw - 3, head.dy - 2)
            ..cubicTo(head.dx - hw - 3, head.dy - hh - 10, head.dx + hw + 3,
                head.dy - hh - 10, head.dx + hw + 3, head.dy - 2)
            ..close(),
          fill..color = const Color(0xFF3F462F));
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(head.dx - 6, head.dy - 16), width: 16, height: 10),
          fill..color = const Color(0x33FFFFFF));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(head.dx, head.dy - 3), width: 44, height: 6),
              const Radius.circular(2)),
          fill..color = const Color(0xFF262C1C));
      // chin strap
      stroke
        ..color = const Color(0xFF262C1C)
        ..strokeWidth = 2.4;
      canvas.drawLine(Offset(head.dx - hw - 1, head.dy - 1),
          Offset(head.dx - 5, head.dy + 15), stroke);
      canvas.drawLine(Offset(head.dx + hw + 1, head.dy - 1),
          Offset(head.dx + 5, head.dy + 15), stroke);
      break;
    case 5: // shades
      for (final side in const [-1.0, 1.0]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: Offset(head.dx + side * 8, head.dy - 0.5),
                    width: 14,
                    height: 10),
                const Radius.circular(3)),
            fill..color = const Color(0xFF11141A));
      }
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(head.dx, head.dy - 0.5), width: 6, height: 2.5),
          fill..color = const Color(0xFF11141A));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(head.dx - 10, head.dy - 2),
                  width: 5,
                  height: 3),
              const Radius.circular(1)),
          fill..color = const Color(0x88A8D8FF));
      break;
    case 6: // mohawk
      for (var i = 0; i < 7; i++) {
        final t = i / 6.0;
        final x = head.dx - 2 + (t - 0.5) * 4;
        final h = 8 + 9 * math.sin(t * math.pi);
        canvas.drawPath(
            Path()
              ..moveTo(x - 3, head.dy - hh + 2)
              ..lineTo(x, head.dy - hh + 2 - h)
              ..lineTo(x + 3, head.dy - hh + 2)
              ..close(),
            fill..color = const Color(0xFFE12F5F));
      }
      break;
    case 7: // mask
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(head.dx, head.dy + 9), width: 30, height: 18),
              const Radius.circular(7)),
          fill..color = const Color(0xFF262B36));
      canvas.drawCircle(Offset(head.dx - 9, head.dy + 10), 4,
          fill..color = const Color(0xFF171B22));
      canvas.drawCircle(Offset(head.dx + 9, head.dy + 10), 4,
          fill..color = const Color(0xFF171B22));
      break;
    case 8: // crown
      final crown = Path()..moveTo(head.dx - 16, head.dy - 12);
      for (var i = 0; i < 3; i++) {
        final x = head.dx - 16 + i * 16.0;
        crown
          ..lineTo(x + 4, head.dy - 22)
          ..lineTo(x + 8, head.dy - 12)
          ..lineTo(x + 12, head.dy - 22)
          ..lineTo(x + 16, head.dy - 12);
      }
      crown.close();
      canvas.drawPath(crown, fill..color = const Color(0xFFFFD75E));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(head.dx, head.dy - 11), width: 36, height: 6),
              const Radius.circular(2)),
          fill..color = const Color(0xFFE8B830));
      canvas.drawCircle(Offset(head.dx, head.dy - 11), 2.6,
          fill..color = const Color(0xFFFF4D6D));
      break;
    case 9: // horns
      for (final side in const [-1.0, 1.0]) {
        canvas.drawPath(
            Path()
              ..moveTo(head.dx + side * 12, head.dy - 12)
              ..quadraticBezierTo(head.dx + side * 26, head.dy - 22,
                  head.dx + side * 22, head.dy - 34)
              ..quadraticBezierTo(head.dx + side * 15, head.dy - 22,
                  head.dx + side * 7, head.dy - 15)
              ..close(),
            fill..color = const Color(0xFFEDE6D2));
      }
      break;
  }
}
