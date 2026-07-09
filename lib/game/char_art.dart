import 'dart:math' as math;
import 'dart:ui';

import 'config.dart';

// Metal palette shared by all weapons.
const Color _metal = Color(0xFF3B404B);
const Color _metalDark = Color(0xFF23262E);
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
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(lx, ly), width: r * 0.95, height: r * 0.4),
          Radius.circular(r * 0.2)),
      fill..color = outfitDark,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(lx + r * 0.42, ly),
              width: r * 0.34,
              height: r * 0.44),
          Radius.circular(r * 0.12)),
      fill..color = boot,
    );
  }
  canvas.restore();

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

  // torso outline
  canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 1.7, height: r * 1.98),
      stroke
        ..color = const Color(0x70000000)
        ..strokeWidth = 2);

  // gun + gloved hands
  _drawWeapon(canvas, weapon, r, glove, fill);

  // neck
  canvas.drawCircle(
      Offset(r * 0.14, 0), r * 0.32, fill..color = _dark(skin, 0.22));

  // head — ears, skin, hair, highlights, outline
  final head = Offset(r * 0.36, 0);
  final hr = r * 0.6;
  canvas.drawCircle(
      Offset(head.dx - hr * 0.1, -hr * 0.82), hr * 0.26, fill..color = skin);
  canvas.drawCircle(
      Offset(head.dx - hr * 0.1, hr * 0.82), hr * 0.26, fill..color = skin);
  canvas.drawCircle(head, hr, fill..color = skin);
  canvas.drawCircle(head.translate(-hr * 0.42, 0), hr * 0.92, fill..color = _hair);
  canvas.drawCircle(head.translate(-hr * 0.52, -hr * 0.15), hr * 0.4,
      fill..color = _lite(_hair, 0.14));
  canvas.drawCircle(head.translate(hr * 0.34, -hr * 0.18), hr * 0.26,
      fill..color = _lite(skin, 0.25).withValues(alpha: 0.6));
  canvas.drawCircle(head, hr,
      stroke..color = const Color(0x60000000)..strokeWidth = 1.4);

  _drawAccessory(canvas, head, hr, accessory, outfit, fill, stroke);
  _drawHeroGear(canvas, r, hero, fill, stroke);

  canvas.restore();
}

/// Signature gear drawn over the torso so each hero reads at a glance.
void _drawHeroGear(Canvas canvas, double r, int hero, Paint fill, Paint stroke) {
  if (hero < 0 || hero >= kHeroes.length) return;
  switch (kHeroes[hero].skill) {
    case SkillType.dash: // STRIKER — scout visor
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(r * 0.66, 0), width: r * 0.26, height: r * 0.95),
              Radius.circular(r * 0.1)),
          fill..color = const Color(0xDD37D0FF));
      break;
    case SkillType.shield: // BASTION — heavy chest plate + emblem
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(r * 0.1, 0), width: r * 1.0, height: r * 1.45),
              Radius.circular(r * 0.22)),
          fill..color = const Color(0xFF39476A));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(r * 0.1, 0), width: r * 1.0, height: r * 1.45),
              Radius.circular(r * 0.22)),
          stroke
            ..color = const Color(0xFF7FA8FF)
            ..strokeWidth = r * 0.08);
      canvas.drawCircle(
          Offset(r * 0.12, 0), r * 0.26, fill..color = const Color(0xFF7FA8FF));
      break;
    case SkillType.frenzy: // VORTEX — red ammo belt with brass rounds
      stroke
        ..color = const Color(0xFFB23A2E)
        ..strokeWidth = r * 0.2;
      canvas.drawLine(
          Offset(-r * 0.45, -r * 0.7), Offset(r * 0.5, r * 0.6), stroke);
      for (var i = 0; i < 5; i++) {
        final t = i / 4;
        canvas.drawCircle(
            Offset(-r * 0.45 + r * 0.95 * t, -r * 0.7 + r * 1.3 * t),
            r * 0.1,
            fill..color = const Color(0xFFE8C15A));
      }
      break;
    case SkillType.medic: // MERCY — white plate + red cross
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(r * 0.1, 0), width: r * 0.95, height: r * 1.3),
              Radius.circular(r * 0.18)),
          fill..color = const Color(0xFFF2F5F8));
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(r * 0.1, 0), width: r * 0.55, height: r * 0.18),
          fill..color = const Color(0xFFE0333F));
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(r * 0.1, 0), width: r * 0.18, height: r * 0.55),
          fill..color = const Color(0xFFE0333F));
      break;
    case SkillType.grenadier: // BOOMER — grenade bandolier
      stroke
        ..color = const Color(0xFF4A3A22)
        ..strokeWidth = r * 0.18;
      canvas.drawLine(
          Offset(-r * 0.45, r * 0.7), Offset(r * 0.5, -r * 0.6), stroke);
      for (var i = 0; i < 4; i++) {
        final t = i / 3;
        canvas.drawCircle(
            Offset(-r * 0.45 + r * 0.95 * t, r * 0.7 - r * 1.3 * t),
            r * 0.12,
            fill..color = const Color(0xFF3A5A32));
      }
      break;
  }
}

void _drawWeapon(Canvas canvas, WeaponId w, double r, Color skin, Paint fill) {
  // thick is a fraction of r (body radius)
  void barrel(double x0, double x1, double thick, Color col) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(r * x0, -r * thick / 2, r * x1, r * thick / 2),
          Radius.circular(r * thick * 0.3)),
      fill..color = col,
    );
  }

  void box(double x, double y, double bw, double bh, Color col) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(r * x, r * y, r * bw, r * bh), Radius.circular(r * 0.06)),
      fill..color = col,
    );
  }

  void hand(double x, double y) =>
      canvas.drawCircle(Offset(r * x, r * y), r * 0.21, fill..color = skin);

  switch (w) {
    case WeaponId.pistol:
      barrel(0.5, 1.05, 0.28, _metal);
      box(0.5, -0.02, 0.22, 0.32, _metalDark);
      hand(0.62, 0.16);
      break;
    case WeaponId.smg:
      barrel(0.45, 1.35, 0.3, _metal);
      box(0.6, 0.15, 0.22, 0.55, _metalDark);
      hand(0.62, 0.16);
      hand(1.05, 0.0);
      break;
    case WeaponId.shotgun:
      barrel(0.45, 1.5, 0.34, _metal);
      barrel(0.45, 1.5, 0.14, _metalDark);
      box(0.95, -0.22, 0.3, 0.44, const Color(0xFF5A4632));
      hand(0.62, 0.16);
      hand(1.1, 0.0);
      break;
    case WeaponId.rifle:
      barrel(0.45, 1.85, 0.26, _metal);
      box(0.2, -0.2, 0.35, 0.4, _metalDark); // stock
      box(0.72, 0.12, 0.2, 0.5, _metalDark); // magazine
      hand(0.66, 0.16);
      hand(1.3, 0.0);
      break;
    case WeaponId.sniper:
      barrel(0.4, 2.2, 0.2, _metal);
      box(0.85, -0.16, 0.4, 0.16, _metalDark); // scope
      box(0.2, -0.16, 0.3, 0.32, _metalDark); // stock
      hand(0.64, 0.16);
      hand(1.5, 0.0);
      break;
    case WeaponId.magnum:
      barrel(0.5, 1.2, 0.3, _metal);
      box(0.46, -0.04, 0.26, 0.4, _metalDark);
      canvas.drawCircle(
          Offset(r * 0.66, 0), r * 0.26, fill..color = _metalDark); // cylinder
      hand(0.6, 0.16);
      break;
    case WeaponId.dmr:
      barrel(0.45, 1.95, 0.22, _metal);
      box(0.2, -0.17, 0.32, 0.34, _metalDark); // stock
      box(0.88, -0.15, 0.36, 0.16, _metalDark); // scope
      box(0.72, 0.12, 0.18, 0.44, _metalDark); // mag
      hand(0.66, 0.16);
      hand(1.35, 0.0);
      break;
    case WeaponId.lmg:
      barrel(0.45, 1.85, 0.3, _metal);
      box(0.2, -0.2, 0.32, 0.4, _metalDark); // stock
      canvas.drawCircle(
          Offset(r * 0.86, r * 0.5), r * 0.34, fill..color = _metalDark); // drum
      hand(0.64, 0.16);
      hand(1.35, 0.0);
      break;
    case WeaponId.minigun:
      box(0.32, -0.3, 0.5, 0.6, _metalDark); // body
      for (final dy in const [-0.16, 0.0, 0.16]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(
                  r * 0.5, r * (dy - 0.06), r * 1.75, r * (dy + 0.06)),
              Radius.circular(r * 0.04)),
          fill..color = _metal,
        );
      }
      hand(0.5, 0.24);
      break;
  }
}

void _drawAccessory(Canvas canvas, Offset head, double hr, int acc, Color outfit,
    Paint fill, Paint stroke) {
  switch (acc) {
    case 1: // Cap — dome + forward visor
      canvas.drawCircle(
          head.translate(-hr * 0.12, 0), hr * 0.98, fill..color = _dark(outfit, 0.05));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: head.translate(hr * 0.95, 0),
                  width: hr * 1.0,
                  height: hr * 1.5),
              Radius.circular(hr * 0.2)),
          fill..color = _dark(outfit, 0.22));
      break;
    case 2: // Beanie
      canvas.drawCircle(
          head.translate(-hr * 0.05, 0), hr * 1.02, fill..color = outfit);
      canvas.drawCircle(
          head.translate(-hr * 0.05, 0),
          hr * 1.02,
          stroke
            ..color = _dark(outfit, 0.3)
            ..strokeWidth = hr * 0.16);
      break;
    case 3: // Headband
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: head.translate(hr * 0.2, 0),
                  width: hr * 0.5,
                  height: hr * 2.0),
              Radius.circular(hr * 0.2)),
          fill..color = const Color(0xFFE23B4E));
      break;
    case 4: // Helmet
      canvas.drawCircle(head.translate(-hr * 0.05, 0), hr * 1.05,
          fill..color = const Color(0xFF4A5340));
      canvas.drawCircle(
          head.translate(-hr * 0.05, 0),
          hr * 1.05,
          stroke
            ..color = const Color(0xFF2E3327)
            ..strokeWidth = hr * 0.14);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: head.translate(hr * 0.7, 0),
                  width: hr * 0.5,
                  height: hr * 1.2),
              Radius.circular(hr * 0.1)),
          fill..color = const Color(0xFF3A4030));
      break;
    case 5: // Shades
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: head.translate(hr * 0.55, 0),
                  width: hr * 0.4,
                  height: hr * 1.4),
              Radius.circular(hr * 0.18)),
          fill..color = const Color(0xFF15181F));
      break;
    case 6: // Mohawk — a crest running front-to-back over the head
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: head.translate(-hr * 0.1, 0),
                  width: hr * 1.7,
                  height: hr * 0.5),
              Radius.circular(hr * 0.2)),
          fill..color = const Color(0xFFFF3D6E));
      break;
    case 7: // Mask — covers the front of the face
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: head.translate(hr * 0.42, 0),
                  width: hr * 0.7,
                  height: hr * 1.5),
              Radius.circular(hr * 0.25)),
          fill..color = const Color(0xFF262A34));
      break;
    case 8: // Crown
      canvas.drawCircle(
          head.translate(-hr * 0.05, 0),
          hr * 0.9,
          stroke
            ..color = const Color(0xFFF4C430)
            ..strokeWidth = hr * 0.22);
      for (final a in const [-1.1, 0.0, 1.1]) {
        final cx = head.dx + math.cos(a - 1.57) * hr * 0.9;
        final cy = head.dy + math.sin(a - 1.57) * hr * 0.9;
        canvas.drawCircle(Offset(cx, cy), hr * 0.16,
            fill..color = const Color(0xFFFFE082));
      }
      break;
    case 9: // Horns
      for (final s in const [-1.0, 1.0]) {
        final path = Path()
          ..moveTo(head.dx - hr * 0.2, head.dy + s * hr * 0.6)
          ..lineTo(head.dx - hr * 0.95, head.dy + s * hr * 1.15)
          ..lineTo(head.dx + hr * 0.1, head.dy + s * hr * 0.95)
          ..close();
        canvas.drawPath(path, fill..color = const Color(0xFFEDE6D2));
      }
      break;
    default:
      break; // None
  }
}
