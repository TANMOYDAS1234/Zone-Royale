import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/rendering.dart' show CustomPainter;

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

  // ---- body armour: a real plate carrier, worn over the fatigues ----
  if (vest) {
    const plate = Color(0xFF2C3646);
    const plateLo = Color(0xFF1E2733);
    const plateHi = Color(0xFF56657C);
    const webbing = Color(0xFF3E4B5E);
    const trim = Color(0xFF8FB6E0);

    // cummerbund wrapping the sides (drawn first, sits under the front plate)
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(-r * 0.06, 0), width: r * 0.9, height: r * 1.62),
            Radius.circular(r * 0.22)),
        fill..color = plateLo);
    // shoulder plates — the silhouette cue that says "this one is armoured"
    for (final sgn in const [-1.0, 1.0]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(r * 0.02, sgn * r * 0.78),
                  width: r * 0.74,
                  height: r * 0.52),
              Radius.circular(r * 0.2)),
          fill..color = webbing);
      // lit top edge of each pauldron
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(r * 0.14, sgn * r * 0.8),
                  width: r * 0.36,
                  height: r * 0.2),
              Radius.circular(r * 0.08)),
          fill..color = trim.withValues(alpha: 0.35));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(r * 0.02, sgn * r * 0.78),
                  width: r * 0.74,
                  height: r * 0.52),
              Radius.circular(r * 0.2)),
          stroke
            ..color = const Color(0x66000000)
            ..strokeWidth = r * 0.04);
    }

    // front plate
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(r * 0.08, 0), width: r * 1.06, height: r * 1.5),
            Radius.circular(r * 0.2)),
        fill..color = plate);
    // ballistic panel seam + carbon weave
    canvas.drawRect(
        Rect.fromCenter(
            center: Offset(r * 0.08, 0), width: r * 0.98, height: r * 0.09),
        fill..color = const Color(0x55000000));
    stroke
      ..color = const Color(0x2E000000)
      ..strokeWidth = r * 0.03;
    for (var i = -2; i <= 2; i++) {
      canvas.drawLine(Offset(-r * 0.34, i * r * 0.26),
          Offset(r * 0.52, i * r * 0.26), stroke);
    }
    // sculpted highlight: light comes from the front-left
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(r * 0.36, -r * 0.2),
                width: r * 0.34,
                height: r * 0.78),
            Radius.circular(r * 0.14)),
        fill..color = plateHi.withValues(alpha: 0.5));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(-r * 0.24, r * 0.28),
                width: r * 0.3,
                height: r * 0.8),
            Radius.circular(r * 0.14)),
        fill..color = const Color(0x33000000));

    // MOLLE webbing rows + mag pouches with flaps
    for (final py in const [-0.44, 0.0, 0.44]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(r * 0.42, r * py),
                  width: r * 0.26,
                  height: r * 0.32),
              Radius.circular(r * 0.05)),
          fill..color = webbing);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(r * 0.42, r * (py - 0.1)),
                  width: r * 0.26,
                  height: r * 0.12),
              Radius.circular(r * 0.04)),
          fill..color = plateHi.withValues(alpha: 0.45)); // flap
      canvas.drawCircle(Offset(r * 0.42, r * (py + 0.06)), r * 0.03,
          fill..color = const Color(0xFF12161D)); // press stud
    }

    // throat / neck guard
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(r * 0.58, 0), width: r * 0.26, height: r * 0.74),
            Radius.circular(r * 0.12)),
        fill..color = plateLo);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(r * 0.6, 0), width: r * 0.1, height: r * 0.6),
            Radius.circular(r * 0.05)),
        fill..color = plateHi.withValues(alpha: 0.4));

    // rivets at the plate corners — small, but they read as hardware
    for (final sgn in const [-1.0, 1.0]) {
      for (final x in const [-0.3, 0.42]) {
        canvas.drawCircle(Offset(r * x, sgn * r * 0.62), r * 0.045,
            fill..color = const Color(0xFF9FB4CC));
      }
    }
    // blood-type tag
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(-r * 0.16, -r * 0.56),
                width: r * 0.2,
                height: r * 0.12),
            Radius.circular(r * 0.03)),
        fill..color = const Color(0xFFB63A3A));
    // crisp outline so the armour separates from the body
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(r * 0.08, 0), width: r * 1.06, height: r * 1.5),
            Radius.circular(r * 0.2)),
        stroke
          ..color = trim.withValues(alpha: 0.75)
          ..strokeWidth = r * 0.06);
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
    // goggles pushed up on the crown — the detail every real operator has
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(head.dx - hr * 0.34, 0),
                width: hr * 0.3,
                height: hr * 1.35),
            Radius.circular(hr * 0.14)),
        fill..color = const Color(0xFF171B12));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(head.dx - hr * 0.34, 0),
                width: hr * 0.14,
                height: hr * 1.15),
            Radius.circular(hr * 0.07)),
        fill..color = const Color(0x99A8D8FF));
    // IR strobe tab
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(head.dx - hr * 0.72, hr * 0.34),
                width: hr * 0.22,
                height: hr * 0.18),
            Radius.circular(hr * 0.05)),
        fill..color = const Color(0xFF2B3320));
    canvas.drawCircle(head.translate(-hr * 0.72, hr * 0.34), hr * 0.06,
        fill..color = const Color(0xCC7FE08A));
    // cover seam over the crown
    stroke
      ..color = const Color(0x55000000)
      ..strokeWidth = hr * 0.07;
    canvas.drawArc(
        Rect.fromCircle(center: head.translate(-hr * 0.04, 0), radius: hr * 0.72),
        2.0, 2.3, false, stroke);
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

/// The shield-wall glyph, drawn the same way the deployed wall is drawn in the
/// world: a frosted slab with vertical ribs and a lit core seam. Used on the
/// HUD button so the control and the object it places look like one thing.
class ShieldWallGlyph extends CustomPainter {
  final bool lit;
  const ShieldWallGlyph({this.lit = true});

  @override
  void paint(Canvas canvas, Size size) {
    final col = lit ? const Color(0xFF7FE8FF) : const Color(0x66FFFFFF);
    final r = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(size.height * 0.22));
    canvas.drawRRect(
        r, Paint()..color = col.withValues(alpha: lit ? 0.28 : 0.12));
    canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = col.withValues(alpha: lit ? 0.95 : 0.4));
    final rib = Paint()
      ..strokeWidth = 1.2
      ..color = col.withValues(alpha: lit ? 0.55 : 0.25);
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 2.5), Offset(x, size.height - 2.5), rib);
    }
    // lit core seam
    canvas.drawRect(
        Rect.fromCenter(
            center: Offset(size.width / 2, size.height / 2),
            width: size.width - 4,
            height: 1.8),
        Paint()..color = col.withValues(alpha: lit ? 0.9 : 0.3));
  }

  @override
  bool shouldRepaint(covariant ShieldWallGlyph old) => old.lit != lit;
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


/// Draws the operator EXACTLY as they appear in a match (top-down), framed for
/// a menu tile: a soft accent spotlight, a grounded shadow, and the operator
/// facing "up" so the whole body plan and the gun read clearly.
///
/// Menus deliberately use the in-game art — what you see in the shop is what
/// you get on the battlefield, not a stylised portrait that promises something
/// the game never shows you.
void drawOperatorTile(
  Canvas canvas,
  Rect box, {
  required Color outfit,
  required Color skin,
  int accessory = 0,
  int hero = -1,
  WeaponId weapon = WeaponId.smg,
  Color? glow,
  double zoom = 1.0, // >1 crops in (used by accessory tiles to show the head)
  double headBias = 0.0, // shifts the framing toward the head
  bool vest = false,
  bool helmet = false,
  /// Spin, in radians, added to the facing. The lobby drives this from a drag
  /// so the player can turn their operator and look at the gear.
  double turn = 0,
  /// Draw the hero's evolved form: a gold aura and a rim of light. An
  /// evolution you cannot see is an evolution nobody buys twice.
  bool evolved = false,
}) {
  final fill = Paint()..style = PaintingStyle.fill;
  final stroke = Paint()..style = PaintingStyle.stroke;
  final accent = glow ?? const Color(0xFF9AA6B2);
  final c = box.center;
  final r = math.min(box.width, box.height) * 0.30 * zoom;

  // spotlight so the operator sits in a lit pool instead of a flat void
  canvas.drawRect(
      box,
      fill
        ..shader = Gradient.radial(
            c.translate(0, -box.height * 0.05), box.shortestSide * 0.62, [
          accent.withValues(alpha: 0.26),
          accent.withValues(alpha: 0.06),
          const Color(0x00000000),
        ], [
          0.0,
          0.55,
          1.0
        ]));
  fill.shader = null;

  canvas.save();
  canvas.clipRect(box);
  // frame: shift down a touch so the upward-pointing gun stays in the tile
  final centre = c.translate(0, box.height * (0.10 + headBias));

  // Grounded shadow, matching the map's light direction — and turning with
  // the operator, so spinning them in the lobby swings the shadow round with
  // the body instead of leaving it stuck facing one way.
  canvas.save();
  canvas.translate(centre.dx + r * 0.28, centre.dy + r * 0.85);
  canvas.rotate(turn);
  canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 2.3, height: r * 0.9),
      fill..color = const Color(0x55000000));
  canvas.restore();

  // evolved: a warm ground aura under the operator, before they are drawn
  if (evolved) {
    canvas.drawCircle(
        centre,
        r * 1.5,
        fill
          ..shader = Gradient.radial(centre, r * 1.5, [
            const Color(0x66FFD36B),
            const Color(0x22FFB02E),
            const Color(0x00000000),
          ], [
            0.0,
            0.55,
            1.0
          ]));
    fill.shader = null;
  }

  // -pi/2 = facing the top of the tile, plus whatever spin the player applied
  final face = -math.pi / 2 + turn;
  drawOperator(canvas, centre, r, face, face, outfit, skin,
      accessory, weapon,
      fill: fill,
      stroke: stroke,
      hero: hero,
      vest: vest,
      helmet: helmet);

  // evolved: a bright rim around the silhouette and a pair of crest marks
  if (evolved) {
    canvas.drawCircle(
        centre,
        r * 1.06,
        stroke
          ..color = const Color(0xFFFFD36B).withValues(alpha: 0.85)
          ..strokeWidth = r * 0.055);
    for (final sgn in const [-1.0, 1.0]) {
      final a = face + sgn * 0.85;
      canvas.drawCircle(
          centre + Offset(math.cos(a), math.sin(a)) * (r * 1.06),
          r * 0.11,
          fill..color = const Color(0xFFFFD36B));
    }
  }
  canvas.restore();
}
