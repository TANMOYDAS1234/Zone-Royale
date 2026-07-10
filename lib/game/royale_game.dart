import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/painting.dart' as tp;

import 'char_art.dart';
import 'config.dart';
import 'entities.dart';
import 'mathx.dart';
import 'profile.dart';
import 'sfx.dart';

const double kPlayerSpeed = 250;
const double kBotSpeed = 226;
const double kPickupRange = 28;

/// Screens the surrounding Flutter UI switches between.
class Screen {
  static const start = 'start';
  static const playing = 'playing';
  static const end = 'end';
  static const profile = 'profile';
  static const missions = 'missions';
  static const shop = 'shop';
}

class RoyaleGame extends FlameGame {
  // ---- world state ----
  final List<Character> chars = [];
  final List<Bullet> bullets = [];
  final List<Grenade> grenades = [];
  final List<Loot> loot = [];
  final List<Obstacle> obstacles = [];
  final List<Particle> particles = [];
  late Character player;

  // ---- zone (gas) ----
  final Vector2 zoneCenter = Vector2.zero();
  double zoneRadius = 0;
  final Vector2 _zoneStartC = Vector2.zero();
  final Vector2 _zoneTargetC = Vector2.zero();
  double _zoneStartR = 0;
  double _zoneTargetR = 0;
  int zonePhase = 0;
  bool zoneShrinking = false;
  double zoneTimer = 0;

  // ---- match / map (set per match from the chosen MatchMode) ----
  double worldSize = 3200;
  int botCount = kBotCount;
  double zoneStart = kZoneStartRadius;
  MatchMode mode = kMatchModes[0];
  MapTheme mapTheme = kMapThemes[0];

  // ---- camera / feel ----
  final Vector2 cam = Vector2.zero();
  double _shake = 0;
  double _time = 0;
  int _frame = 0;

  // ---- render scratch (allocated once, reused every frame) ----
  Rect _viewRect = Rect.zero;
  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;
  final Paint _layerPaint = Paint();
  final Paint _gasFillPaint = Paint()..color = kGasFill;
  final Paint _clearPaint = Paint()..blendMode = BlendMode.clear;
  Paint _gridPaint = Paint()
    ..color = kGridColor
    ..strokeWidth = 1;
  Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6
    ..color = const Color(0xFF2A3550);
  Paint _groundPaint = Paint()..color = kGroundColor;

  bool _vis(double x, double y, [double pad = 60]) =>
      x > _viewRect.left - pad &&
      x < _viewRect.right + pad &&
      y > _viewRect.top - pad &&
      y < _viewRect.bottom + pad;

  // ---- input (written by the Flutter layer) ----
  final Vector2 moveInput = Vector2.zero(); // left stick / WASD
  final Vector2 aimStick = Vector2.zero(); // right stick (touch)
  Vector2? mouseScreen; // desktop aim
  bool fireHeld = false;
  bool _firePrev = false;
  bool touchMode = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  // On a phone/tablet the on-screen sticks must ALWAYS be available, even if a
  // stray mouse-kind event briefly flips touchMode off.
  bool get isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  bool _reloadRequested = false;

  // ---- match / ui ----
  bool playing = false;
  bool endShown = false;
  bool resultWon = false;
  int resultPlacement = 0;
  int _nextId = 0;
  final ValueNotifier<int> ticker = ValueNotifier(0); // HUD refresh pulse
  final ValueNotifier<String> screen = ValueNotifier(Screen.start);
  String? toast;
  double _toastT = 0;

  final Map<int, tp.TextPainter> _nameLabels = {};
  bool playerAuto = true; // player's single/auto fire preference
  bool _recorded = false; // stats recorded for the current match?
  MatchRewards? lastRewards; // XP/coins/level-ups from the last finished match
  int grenadesThrown = 0; // by the player this match (for missions)
  double skillMaxCd = 1; // cooldown length of the last-used hero skill
  final List<_DirMark> _hitMarks = []; // directional damage indicators
  double _hitMarkerT = 0; // white hit-marker flash when you tag an enemy
  final List<_DmgText> _dmgTexts = []; // floating damage numbers
  final List<_KillLine> _killLog = []; // recent-eliminations kill feed

  double get zoom => size.y <= 0 ? 1 : size.y / kViewHeight;
  int get aliveCount => chars.where((c) => c.alive).length;
  Hero get currentHero =>
      kHeroes[Profile.instance.hero.clamp(0, kHeroes.length - 1)];
  double get skillCdFrac =>
      skillMaxCd <= 0 ? 0.0 : (player.skillCd / skillMaxCd).clamp(0.0, 1.0);

  @override
  Color backgroundColor() => kBgBottom;

  @override
  Future<void> onLoad() async {
    _applyMode(
        kMatchModes[Profile.instance.matchMode.clamp(0, kMatchModes.length - 1)]);
    _buildWorld(); // world visible behind the start menu
  }

  // =====================================================================
  //  SETUP
  // =====================================================================
  void _applyMode(MatchMode m) {
    mode = m;
    worldSize = m.world;
    botCount = m.bots;
    zoneStart = m.zoneStart;
    final mc = Profile.instance.mapChoice;
    mapTheme = (mc <= 0 || mc > kMapThemes.length)
        ? kMapThemes[randIntRange(0, kMapThemes.length - 1)] // 0 = random
        : kMapThemes[mc - 1];
  }

  void startMatch([MatchMode? m]) {
    _applyMode(m ?? mode);
    _buildWorld();
    // clear any stale input so the player doesn't drift on spawn
    moveInput.setValues(0, 0);
    aimStick.setValues(0, 0);
    fireHeld = false;
    _firePrev = false;
    _reloadRequested = false;
    playing = true;
    endShown = false;
    resultWon = false;
    resultPlacement = 0;
    _recorded = false;
    grenadesThrown = 0;
    playerAuto = Profile.instance.fireAuto;
    screen.value = Screen.playing;
  }

  void spectate() {
    if (!resultWon) screen.value = Screen.playing;
  }

  /// Quit the current match and return to the home / start menu.
  void goHome() {
    playing = false;
    endShown = false;
    _hitMarks.clear();
    screen.value = Screen.start;
  }

  void _buildWorld() {
    // Map paints depend on theme + size, and both change per match.
    _groundPaint = Paint()
      ..shader = Gradient.radial(Offset(worldSize / 2, worldSize / 2),
          worldSize * 0.7, [Color(mapTheme.ground), Color(mapTheme.groundEdge)]);
    _gridPaint = Paint()
      ..color = Color(mapTheme.grid)
      ..strokeWidth = 1;
    _borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = Color(mapTheme.border);

    chars.clear();
    bullets.clear();
    grenades.clear();
    loot.clear();
    obstacles.clear();
    particles.clear();
    _dmgTexts.clear();
    _killLog.clear();
    _hitMarks.clear();
    _hitMarkerT = 0;
    toast = null;
    _toastT = 0;
    _nextId = 0;
    _time = 0;
    _shake = 0;

    _buildObstacles();
    _buildLoot();
    _buildCharacters();
    _buildNameLabels();

    zoneCenter.setValues(worldSize / 2, worldSize / 2);
    zoneRadius = zoneStart;
    zonePhase = 0;
    zoneShrinking = false;
    zoneTimer = kZonePhases[0].wait * mode.timeScale;

    cam.setFrom(player.pos);
  }

  void _buildObstacles() {
    // Counts scale with map area and the map theme's cover mix.
    final areaScale = (worldSize * worldSize) / (3200 * 3200);
    final walls = (16 * areaScale * mapTheme.wallMul).round().clamp(6, 110);
    final crateGroups = (22 * areaScale * mapTheme.crateMul).round().clamp(8, 120);
    final bushes = (26 * areaScale * mapTheme.bushMul).round().clamp(6, 160);

    for (var i = 0; i < walls; i++) {
      final horizontal = chance(0.5);
      final w = horizontal ? randRange(160, 420) : randRange(30, 46);
      final h = horizontal ? randRange(30, 46) : randRange(160, 420);
      obstacles.add(Obstacle(
        ObstacleKind.wall,
        randRange(120, worldSize - 120 - w),
        randRange(120, worldSize - 120 - h),
        w,
        h,
      ));
    }
    for (var i = 0; i < crateGroups; i++) {
      final cx = randRange(160, worldSize - 160);
      final cy = randRange(160, worldSize - 160);
      final n = randIntRange(1, 4);
      for (var j = 0; j < n; j++) {
        final s = randRange(30, 42);
        obstacles.add(Obstacle(
          ObstacleKind.crate,
          cx + randRange(-46, 46),
          cy + randRange(-46, 46),
          s,
          s,
        ));
      }
    }
    for (var i = 0; i < bushes; i++) {
      final s = randRange(70, 120);
      obstacles.add(Obstacle(
        ObstacleKind.bush,
        randRange(120, worldSize - 120 - s),
        randRange(120, worldSize - 120 - s),
        s,
        s,
      ));
    }
  }

  bool _inWall(double x, double y, [double margin = 24]) {
    for (final o in obstacles) {
      if (!o.blocks) continue;
      if (x > o.x - margin &&
          x < o.x + o.w + margin &&
          y > o.y - margin &&
          y < o.y + o.h + margin) {
        return true;
      }
    }
    return false;
  }

  Vector2 _openSpot({double centerBias = 0.9}) {
    for (var i = 0; i < 60; i++) {
      final ang = randRange(0, kTau);
      final r = randRange(0, zoneStart * centerBias);
      final x = worldSize / 2 + math.cos(ang) * r;
      final y = worldSize / 2 + math.sin(ang) * r;
      if (x < 120 || x > worldSize - 120 || y < 120 || y > worldSize - 120) continue;
      if (!_inWall(x, y)) return Vector2(x, y);
    }
    return Vector2(worldSize / 2, worldSize / 2);
  }

  void _buildLoot() {
    final areaScale = (worldSize * worldSize) / (3200 * 3200);
    final weapons = (24 * areaScale).round().clamp(14, 170);
    final medkits = (14 * areaScale).round().clamp(8, 110);
    for (var i = 0; i < weapons; i++) {
      loot.add(Loot(LootKind.weapon, _openSpot(centerBias: 0.98),
          weapon: weighted(kLootTable)));
    }
    for (var i = 0; i < medkits; i++) {
      loot.add(Loot(LootKind.medkit, _openSpot(centerBias: 0.98), heal: 45));
    }
    final nades = (10 * areaScale).round().clamp(6, 70);
    for (var i = 0; i < nades; i++) {
      loot.add(Loot(LootKind.grenade, _openSpot(centerBias: 0.98)));
    }
  }

  void _buildCharacters() {
    final spots = <Vector2>[];
    Vector2 farSpot() {
      for (var i = 0; i < 40; i++) {
        final s = _openSpot(centerBias: 0.85);
        var ok = true;
        for (final o in spots) {
          if (o.distanceTo(s) < 240) {
            ok = false;
            break;
          }
        }
        if (ok) {
          spots.add(s);
          return s;
        }
      }
      final f = Vector2(worldSize / 2, worldSize / 2);
      spots.add(f);
      return f;
    }

    final prof = Profile.instance;
    final myName = prof.name.trim().isEmpty ? 'You' : prof.name.trim();
    player = Character(_nextId++, false, myName, prof.outfitColor, farSpot());
    player.skin = prof.skinColor;
    player.accessory = prof.accessory;
    player.hero = prof.hero.clamp(0, kHeroes.length - 1);
    player.weaponId = prof.startWeapon;
    player.ammo = player.weapon.mag;
    chars.add(player);

    for (var i = 0; i < botCount; i++) {
      final b = Character(
        _nextId++,
        true,
        kBotNames[i % kBotNames.length],
        Color(kBotColors[i % kBotColors.length]),
        farSpot(),
      );
      b.skin = Color(kSkinTones[randIntRange(0, kSkinTones.length - 1)]);
      b.accessory = randIntRange(0, kAccessoryNames.length - 1);
      b.hero = randIntRange(0, kHeroes.length - 1);
      // Ranked-style difficulty (like BGMI / Free Fire): the higher your level
      // and rank, the fewer easy grunts and the more regulars & pros you face,
      // plus a small capped accuracy nudge. It plateaus at ~level 40 so the
      // climb keeps challenging you but never becomes impossible to win.
      final diff = (Profile.instance.level / 40.0).clamp(0.0, 1.0);
      final gruntCut = lerpd(0.66, 0.30, diff); // fraction that are grunts
      final regCut = lerpd(0.90, 0.72, diff); // grunts..regCut = regular, rest pro
      final roll = randRange(0, 1);
      double skill;
      if (roll < gruntCut) {
        skill = randRange(0.10, 0.38); // grunt: short vision, sprays, misses
      } else if (roll < regCut) {
        skill = randRange(0.40, 0.60); // regular
      } else {
        skill = randRange(0.66, 0.92); // pro
      }
      b.aiSkill = (skill + lerpd(0.0, 0.12, diff)).clamp(0.08, 0.95);
      b.aim = randRange(0, kTau);
      b.aiScan = randRange(0, 0.3); // stagger first scan
      chars.add(b);
    }
  }

  void _buildNameLabels() {
    _nameLabels.clear();
    for (final c in chars) {
      final painter = tp.TextPainter(
        text: tp.TextSpan(
          text: c.name,
          style: tp.TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: c == player ? kAccent : const Color(0xCCFFFFFF),
            shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _nameLabels[c.id] = painter;
    }
  }

  // =====================================================================
  //  UPDATE
  // =====================================================================
  @override
  void update(double dt) {
    super.update(dt);
    dt = dt.clamp(0.0, 1 / 30);
    _time += dt;
    _shake = math.max(0, _shake - dt * 40);

    if (_toastT > 0) {
      _toastT -= dt;
      if (_toastT <= 0) toast = null;
    }

    if (playing) _step(dt);
    _updateCamera(dt);
    _frame++;
    if (_frame % 3 == 0) ticker.value++; // ~20 Hz HUD refresh (was every frame)
  }

  void _step(double dt) {
    if (player.alive) _drivePlayer(dt);
    for (final c in chars) {
      if (c.alive && c.isBot) _driveBot(c, dt);
    }
    for (final c in chars) {
      if (!c.alive) continue;
      if (c.cooldown > 0) c.cooldown -= dt;
      if (c.muzzle > 0) c.muzzle -= dt;
      if (c.hitFlash > 0) c.hitFlash -= dt;
      if (c.throwCd > 0) c.throwCd -= dt;
      if (c.skillCd > 0) c.skillCd -= dt;
      if (c.shieldT > 0) c.shieldT -= dt;
      if (c.frenzyT > 0) c.frenzyT -= dt;
      if (c.reloadT > 0) {
        c.reloadT -= dt;
        if (c.reloadT <= 0) c.ammo = c.weapon.mag;
      }
      // kick up dust while running
      if (c.vel.length2 > 12000 && chance(5 * dt)) {
        _spawnDust(c.pos.x + randRange(-6, 6), c.pos.y + c.radius * 0.55);
      }
    }
    _separateCharacters();
    _updateBullets(dt);
    _updateGrenades(dt);
    _updateParticles(dt);
    _updateZone(dt);
    _pickups();
    for (final m in _hitMarks) {
      m.life -= dt;
    }
    _hitMarks.removeWhere((m) => m.life <= 0);
    if (_hitMarkerT > 0) _hitMarkerT -= dt;
    for (final d in _dmgTexts) {
      d.life -= dt;
      d.pos.y -= 32 * dt; // drift up
    }
    _dmgTexts.removeWhere((d) => d.life <= 0);
    for (final k in _killLog) {
      k.life -= dt;
    }
    _killLog.removeWhere((k) => k.life <= 0);
  }

  // ----- player driving -----
  void _drivePlayer(double dt) {
    final p = player;
    bool wantFire;
    if (touchMode) {
      if (aimStick.length > 0.2) {
        p.aim = angleOf(aimStick);
        _aimAssist(p, dt); // gentle sticky aim so thumbstick shots land
        wantFire = true;
      } else {
        wantFire = false;
      }
    } else {
      if (mouseScreen != null) {
        final d = screenToWorld(mouseScreen!) - p.pos;
        if (d.length2 > 1) p.aim = angleOf(d);
      }
      wantFire = fireHeld;
    }

    _moveChar(p, moveInput.clone(), kPlayerSpeed, dt);

    if (_reloadRequested) {
      _startReload(p);
      _reloadRequested = false;
    }

    // Auto only when the weapon supports it AND the player prefers auto.
    final effAuto = p.weapon.auto && playerAuto;
    final trigger = effAuto ? wantFire : (wantFire && !_firePrev);
    if (trigger) _fire(p);
    _firePrev = wantFire;
  }

  /// Gentle sticky aim for touch: nudge the player's aim toward the enemy
  /// closest to where they're already pointing (with lead). Not a full lock —
  /// it just makes thumbstick shots actually connect.
  void _aimAssist(Character c, double dt) {
    Character? best;
    var bestErr = 0.42; // widest cone (radians) to snap within
    for (final e in chars) {
      if (!e.alive || e.id == c.id) continue;
      final to = e.pos - c.pos;
      final d = to.length;
      if (d > 520 || d < 1) continue;
      final err = _angDiff(c.aim, angleOf(to));
      if (err > bestErr) continue;
      if (_concealed(e.pos) && d > 160) continue;
      if (!_lineOfSight(c.pos, e.pos)) continue;
      bestErr = err;
      best = e;
    }
    if (best == null) return;
    final lead = best.pos.distanceTo(c.pos) / c.weapon.bulletSpeed;
    final target = angleOf((best.pos + best.vel * lead) - c.pos);
    c.aim = angleLerp(c.aim, target, (7 * dt).clamp(0.0, 0.4));
  }

  void _updateCamera(double dt) {
    Vector2 target;
    if (player.alive) {
      target = player.pos + player.vel * 0.28; // lead the view toward movement
    } else {
      final others = chars.where((c) => c.alive).toList();
      target = others.isNotEmpty ? others.first.pos : zoneCenter;
    }
    final k = (6 * dt).clamp(0.0, 1.0);
    cam.setFrom(cam + (target - cam) * k);
  }

  void addShake(double v) => _shake = math.min(16, _shake + v);

  void _setToast(String msg) {
    toast = msg;
    _toastT = 1.6;
  }

  // =====================================================================
  //  MOVEMENT + COLLISION
  // =====================================================================
  void _moveChar(Character c, Vector2 dir, double speed, double dt) {
    if (dir.length2 > 1) dir = dir.normalized();
    c.vel.setFrom(dir * speed);
    final step = (c.vel + c.knock) * dt;
    c.pos.setFrom(c.pos + step);
    c.knock.setFrom(c.knock * (1 - (9 * dt).clamp(0.0, 1.0)));

    for (final o in obstacles) {
      if (!o.blocks) continue;
      final push =
          circleRectPush(c.pos.x, c.pos.y, c.radius, o.x, o.y, o.w, o.h);
      if (push != null) c.pos.setFrom(c.pos + push);
    }
    c.pos.x = clampd(c.pos.x, c.radius, worldSize - c.radius);
    c.pos.y = clampd(c.pos.y, c.radius, worldSize - c.radius);
  }

  void _separateCharacters() {
    for (var i = 0; i < chars.length; i++) {
      final a = chars[i];
      if (!a.alive) continue;
      for (var j = i + 1; j < chars.length; j++) {
        final b = chars[j];
        if (!b.alive) continue;
        final d = a.pos.distanceTo(b.pos);
        final minD = a.radius + b.radius;
        if (d > 0 && d < minD) {
          final push = (a.pos - b.pos) * ((minD - d) / d * 0.5);
          a.pos.setFrom(a.pos + push);
          b.pos.setFrom(b.pos - push);
        }
      }
    }
  }

  // =====================================================================
  //  SHOOTING + BULLETS
  // =====================================================================
  void _startReload(Character c) {
    if (c.reloading || c.ammo == c.weapon.mag) return;
    c.reloadT = c.weapon.reloadTime * (c.frenzyT > 0 ? 0.5 : 1.0);
    if (c == player) {
      Sfx.reload();
      _setToast('Reloading…');
    }
  }

  void _fire(Character c) {
    final w = c.weapon;
    if (c.reloading || c.cooldown > 0) return;
    if (c.ammo <= 0) {
      _startReload(c);
      return;
    }
    c.ammo--;
    c.cooldown = w.fireInterval * (c.frenzyT > 0 ? 0.45 : 1.0); // VORTEX frenzy
    c.muzzle = 0.06;

    for (var i = 0; i < w.pellets; i++) {
      final jitter = w.pellets > 1
          ? randRange(-w.spread, w.spread)
          : gaussian() * w.spread;
      final dir = fromAngle(c.aim + jitter);
      final origin = c.pos + dir * (c.radius + 8);
      bullets.add(Bullet(origin.clone(), dir * w.bulletSpeed, w.damage, w.range,
          w.color, c.id, tracer: _tracerW(w.id)));
    }
    c.knock.setFrom(c.knock + fromAngle(c.aim, -w.bulletSpeed * 0.012));
    _spawnMuzzle(c);
    if (c == player) {
      Sfx.shoot();
    } else if (c.pos.distanceTo(cam) < 560) {
      Sfx.shoot(vol: 0.13); // quieter nearby enemy fire
    }

    if (c == player) {
      addShake(w.id == WeaponId.shotgun
          ? 7
          : w.id == WeaponId.sniper
              ? 9
              : 3);
    }
    if (c.ammo <= 0) _startReload(c);
  }

  void _updateBullets(double dt) {
    for (final b in bullets) {
      if (b.dead) continue;
      b.prev.setFrom(b.pos);
      b.pos.setFrom(b.pos + b.vel * dt);
      b.traveled += b.vel.length * dt;
      if (b.traveled > b.range ||
          b.pos.x < 0 ||
          b.pos.x > worldSize ||
          b.pos.y < 0 ||
          b.pos.y > worldSize) {
        b.dead = true;
        continue;
      }

      var hitT = 2.0;
      Character? hitChar;
      for (final o in obstacles) {
        if (!o.blocks) continue;
        final t =
            segRect(b.prev.x, b.prev.y, b.pos.x, b.pos.y, o.x, o.y, o.w, o.h);
        if (t >= 0 && t < hitT) hitT = t;
      }
      for (final c in chars) {
        if (!c.alive || c.id == b.ownerId) continue;
        final t = segCircle(
            b.prev.x, b.prev.y, b.pos.x, b.pos.y, c.pos.x, c.pos.y, c.radius);
        if (t >= 0 && t < hitT) {
          hitT = t;
          hitChar = c;
        }
      }

      if (hitT <= 1) {
        final hx = lerpd(b.prev.x, b.pos.x, hitT);
        final hy = lerpd(b.prev.y, b.pos.y, hitT);
        if (hitChar != null) {
          _damage(hitChar, b.damage, b.ownerId, b.vel);
          _spawnBlood(hx, hy, b.vel, hitChar.color);
        } else {
          _spawnSparks(hx, hy, b.color);
        }
        b.dead = true;
      }
    }
    bullets.removeWhere((b) => b.dead);
  }

  void _updateGrenades(double dt) {
    for (final g in grenades) {
      if (g.dead) continue;
      g.fuse -= dt;
      g.vel.setFrom(g.vel * (1 - (2.2 * dt).clamp(0.0, 1.0))); // friction
      g.pos.setFrom(g.pos + g.vel * dt);
      for (final o in obstacles) {
        if (!o.blocks) continue;
        final push = circleRectPush(g.pos.x, g.pos.y, 8, o.x, o.y, o.w, o.h);
        if (push != null) {
          g.pos.setFrom(g.pos + push);
          g.vel.setFrom(g.vel * -0.4); // bounce + dampen off cover
        }
      }
      g.pos.x = clampd(g.pos.x, 8, worldSize - 8);
      g.pos.y = clampd(g.pos.y, 8, worldSize - 8);
      if (g.fuse <= 0) {
        _explode(g);
        g.dead = true;
      }
    }
    grenades.removeWhere((g) => g.dead);
  }

  void _explode(Grenade g) {
    for (final c in chars) {
      if (!c.alive) continue;
      final d = c.pos.distanceTo(g.pos);
      if (d > kGrenadeRadius) continue;
      final falloff = 1 - (d / kGrenadeRadius); // full at centre, 0 at edge
      final away = d > 1 ? (c.pos - g.pos) / d : Vector2(0, -1);
      _damage(c, kGrenadeDamage * falloff, g.ownerId, away);
      c.knock.setFrom(c.knock + away * (170 * falloff));
    }
    _spawnExplosion(g.pos);
    Sfx.boom();
    if (g.pos.distanceTo(cam) < 720) addShake(13);
  }

  void _spawnExplosion(Vector2 p) {
    for (var i = 0; i < 26; i++) {
      particles.add(Particle(
        p.clone(),
        fromAngle(randRange(0, kTau), randRange(80, 380)),
        randRange(0.25, 0.6),
        randRange(3, 8),
        i.isEven ? const Color(0xFFFFB020) : const Color(0xFFFF5A2A),
        glow: true,
      ));
    }
    for (var i = 0; i < 10; i++) {
      particles.add(Particle(
        p.clone(),
        fromAngle(randRange(0, kTau), randRange(20, 120)),
        randRange(0.5, 1.0),
        randRange(6, 13),
        const Color(0x88555560),
      ));
    }
  }

  void _damage(Character c, double dmg, int by, Vector2 dir) {
    if (!c.alive) return;
    if (c.shieldT > 0) dmg *= kShieldCut; // BASTION shield
    c.hp -= dmg;
    c.hitFlash = 0.12;
    if (dir.length2 > 0.01) c.knock.setFrom(c.knock + dir.normalized() * 90);
    if (c == player) {
      addShake(4);
      Sfx.hurt();
      // BGMI-style: remember which way the shot came from for an on-screen arc.
      if (by >= 0 && dir.length2 > 0.001) {
        _hitMarks.add(_DirMark(angleOf(-dir), 2.2));
        if (_hitMarks.length > 12) _hitMarks.removeAt(0);
      }
    } else if (by == player.id) {
      Sfx.hit();
      _hitMarkerT = 0.14; // confirm the hit
      _dmgTexts.add(_makeDmg(c.pos, dmg.round()));
      if (_dmgTexts.length > 24) _dmgTexts.removeAt(0);
    }
    if (c.hp <= 0) _kill(c, by);
  }

  _DmgText _makeDmg(Vector2 pos, int dmg) {
    final painter = tp.TextPainter(
      text: tp.TextSpan(
        text: '$dmg',
        style: tp.TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w900,
          color: const Color(0xFFFFE08A),
          shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return _DmgText(painter, pos.clone()..y -= 24, 0.7);
  }

  // =====================================================================
  //  BOT AI
  // =====================================================================
  double _preferred(WeaponId w) {
    switch (w) {
      case WeaponId.shotgun:
        return 130;
      case WeaponId.smg:
        return 210;
      case WeaponId.pistol:
        return 230;
      case WeaponId.rifle:
        return 340;
      case WeaponId.sniper:
        return 470;
      case WeaponId.magnum:
        return 230;
      case WeaponId.dmr:
        return 420;
      case WeaponId.lmg:
        return 300;
      case WeaponId.minigun:
        return 240;
    }
  }

  bool _lineOfSight(Vector2 a, Vector2 b) {
    for (final o in obstacles) {
      if (!o.blocks) continue;
      final t = segRect(a.x, a.y, b.x, b.y, o.x, o.y, o.w, o.h);
      if (t >= 0 && t < 0.999) return false;
    }
    return true;
  }

  bool _concealed(Vector2 p) {
    for (final o in obstacles) {
      if (o.conceals && o.contains(p.x, p.y)) return true;
    }
    return false;
  }

  Character? _nearestEnemy(Character self, double viewRange) {
    Character? best;
    var bestD = viewRange;
    for (final c in chars) {
      if (!c.alive || c.id == self.id) continue;
      final d = self.pos.distanceTo(c.pos);
      if (d > bestD) continue;
      if (_concealed(c.pos) && d > 170) continue;
      if (!_lineOfSight(self.pos, c.pos)) continue;
      bestD = d;
      best = c;
    }
    return best;
  }

  void _driveBot(Character c, double dt) {
    if (c.aiReact > 0) c.aiReact -= dt;
    if (c.aiRepath > 0) c.aiRepath -= dt;
    if (c.aiScan > 0) c.aiScan -= dt;
    c.aiPreferred = _preferred(c.weaponId);

    final outside = c.pos.distanceTo(zoneCenter) > zoneRadius - 60;
    // The enemy scan (line-of-sight vs every obstacle) is the expensive part, so
    // each bot only re-scans a few times a second, staggered across bots. This
    // keeps 50-player Warzone matches smooth.
    if (c.aiScan <= 0) {
      c.aiScan = randRange(0.18, 0.34);
      // Vision scales with skill — grunts see barely past your own view,
      // only pros spot you from far. This kills the "shot from nowhere" feel.
      final enemy = _nearestEnemy(c, lerpd(360, 540, c.aiSkill));
      if (enemy != null && c.aiEnemy?.id != enemy.id) {
        c.aiReact = lerpd(0.85, 0.12, c.aiSkill); // grunts hesitate
      }
      c.aiEnemy = enemy;
    }
    if (c.aiEnemy != null && !c.aiEnemy!.alive) c.aiEnemy = null;

    // occasional grenade toss at a mid-range target
    if (c.aiEnemy != null && c.grenades > 0 && c.throwCd <= 0) {
      final gd = c.pos.distanceTo(c.aiEnemy!.pos);
      if (gd > 140 && gd < 430 && chance(0.6 * dt)) {
        c.aim = angleOf(c.aiEnemy!.pos - c.pos);
        _throw(c);
      }
    }

    if (outside) {
      c.aiState = 2;
    } else if (c.aiEnemy != null && c.aiEnemy!.alive) {
      c.aiState = 1;
    } else {
      c.aiState = 0;
    }

    switch (c.aiState) {
      case 2:
        final dir = safeNorm(zoneCenter - c.pos);
        _moveChar(c, dir, kBotSpeed, dt);
        c.aim = angleOf(dir);
        break;

      case 1:
        final e = c.aiEnemy!;
        final toE = e.pos - c.pos;
        final dist = toE.length;
        final lead = dist / c.weapon.bulletSpeed;
        final predicted = e.pos + e.vel * lead;
        // Aim error grows with distance and shrinks with skill, so grunts
        // genuinely miss at range instead of laser-beaming you across the map.
        final err =
            gaussian() * lerpd(0.34, 0.05, c.aiSkill) * (1 + dist / 380);
        final wantAngle = angleOf(predicted - c.pos) + err;
        c.aim = angleLerp(
            c.aim, wantAngle, (lerpd(6, 13, c.aiSkill) * dt).clamp(0.0, 1.0));

        Vector2 dir;
        if (dist > c.aiPreferred + 70) {
          dir = safeNorm(toE);
        } else if (dist < c.aiPreferred - 70) {
          dir = safeNorm(-toE);
        } else {
          final n = safeNorm(toE);
          dir = Vector2(-n.y, n.x) * (c.id.isEven ? 1.0 : -1.0);
        }
        _avoidWalls(c, dir);
        _moveChar(c, dir, kBotSpeed * 0.92, dt);

        // Grunts only engage close with loose aim; pros push the range out.
        final effRange = c.weapon.range * lerpd(0.5, 0.9, c.aiSkill);
        final aimTol = lerpd(0.3, 0.12, c.aiSkill);
        if (dist > 1 &&
            _angDiff(c.aim, angleOf(toE)) < aimTol &&
            dist < effRange &&
            c.aiReact <= 0) {
          _fire(c);
        }
        break;

      default:
        if (c.aiRepath <= 0 || c.pos.distanceTo(c.aiTarget) < 40) {
          _pickWanderTarget(c);
          c.aiRepath = randRange(2.2, 4.5);
        }
        if (c.sampleProgress() < 1.2) {
          c.aiStuck += dt;
          if (c.aiStuck > 0.5) {
            _pickWanderTarget(c);
            c.aiStuck = 0;
          }
        } else {
          c.aiStuck = 0;
        }
        final dir = safeNorm(c.aiTarget - c.pos);
        _avoidWalls(c, dir);
        _moveChar(c, dir, kBotSpeed * 0.8, dt);
        c.aim = angleLerp(c.aim, angleOf(dir), (6 * dt).clamp(0.0, 1.0));
    }
  }

  void _pickWanderTarget(Character c) {
    Loot? best;
    var bestD = 720.0;
    for (final l in loot) {
      if (l.taken) continue;
      final d = c.pos.distanceTo(l.pos);
      if (d < bestD) {
        bestD = d;
        best = l;
      }
    }
    if (best != null && chance(0.7)) {
      c.aiTarget.setFrom(best.pos);
    } else {
      final ang = randRange(0, kTau);
      final r = randRange(0, zoneRadius * 0.6);
      c.aiTarget.setValues(
        clampd(zoneCenter.x + math.cos(ang) * r, 140, worldSize - 140),
        clampd(zoneCenter.y + math.sin(ang) * r, 140, worldSize - 140),
      );
    }
  }

  void _avoidWalls(Character c, Vector2 dir) {
    final ahead = c.pos + dir * (c.radius + 34);
    if (_inWall(ahead.x, ahead.y, 6)) {
      final n = Vector2(-dir.y, dir.x);
      dir.setFrom(safeNorm(dir + n * 0.9));
    }
  }

  double _angDiff(double a, double b) {
    var d = ((b - a + math.pi) % kTau) - math.pi;
    if (d < -math.pi) d += kTau;
    return d.abs();
  }

  // =====================================================================
  //  ZONE
  // =====================================================================
  void _updateZone(double dt) {
    final phase = kZonePhases[zonePhase.clamp(0, kZonePhases.length - 1)];
    zoneTimer -= dt;

    if (!zoneShrinking) {
      if (zoneTimer <= 0) {
        _zoneStartC.setFrom(zoneCenter);
        _zoneStartR = zoneRadius;
        _zoneTargetR = zoneRadius * phase.factor;
        final maxShift = math.max(0.0, zoneRadius - _zoneTargetR);
        final ang = randRange(0, kTau);
        final shift = randRange(0, maxShift);
        _zoneTargetC.setValues(
          zoneCenter.x + math.cos(ang) * shift,
          zoneCenter.y + math.sin(ang) * shift,
        );
        zoneShrinking = true;
        zoneTimer = phase.shrink * mode.timeScale;
        Sfx.zone();
      }
    } else {
      final p =
          1 - (zoneTimer / (phase.shrink * mode.timeScale)).clamp(0.0, 1.0);
      zoneRadius = lerpd(_zoneStartR, _zoneTargetR, p);
      zoneCenter.setFrom(_zoneStartC + (_zoneTargetC - _zoneStartC) * p);
      if (zoneTimer <= 0) {
        zoneRadius = _zoneTargetR;
        zoneCenter.setFrom(_zoneTargetC);
        zoneShrinking = false;
        if (zonePhase < kZonePhases.length - 1) {
          zonePhase++;
          zoneTimer = kZonePhases[zonePhase].wait * mode.timeScale;
        } else {
          zoneTimer = 9999;
        }
      }
    }

    final dps = phase.dps;
    for (final c in chars) {
      if (!c.alive) continue;
      if (c.pos.distanceTo(zoneCenter) > zoneRadius) {
        _damage(c, dps * dt, -1, Vector2.zero());
      }
    }
  }

  // =====================================================================
  //  LOOT
  // =====================================================================
  void _pickups() {
    // Dropped weapons are collected here and added AFTER iteration finishes —
    // adding to `loot` while looping over it throws ConcurrentModificationError.
    List<Loot>? dropped;
    for (final c in chars) {
      if (!c.alive) continue;
      for (final l in loot) {
        if (l.taken) continue;
        if (l.readyAt > _time) continue; // can't instantly re-grab a fresh drop
        if (c.pos.distanceTo(l.pos) > c.radius + kPickupRange) continue;
        if (l.kind == LootKind.medkit) {
          if (c.hp >= kMaxHp) continue;
          c.hp = math.min(kMaxHp, c.hp + l.heal);
          l.taken = true;
          if (c == player) {
            Sfx.pickup();
            _setToast('+${l.heal.toInt()} HP');
          }
        } else if (l.kind == LootKind.grenade) {
          if (c.grenades >= kGrenadeMax) continue;
          c.grenades = math.min(kGrenadeMax, c.grenades + 2);
          l.taken = true;
          if (c == player) {
            Sfx.pickup();
            _setToast('+2 grenades');
          }
        } else {
          if (l.weapon == c.weaponId) continue;
          if (c.weaponId != WeaponId.pistol) {
            // Drop the old gun BEHIND the character with a short pickup delay
            // so it can't be instantly re-grabbed (that caused a swap flicker).
            (dropped ??= []).add(
                Loot(LootKind.weapon,
                    c.pos - fromAngle(c.aim) * (c.radius + 26),
                    weapon: c.weaponId)
                  ..readyAt = _time + 1.6);
          }
          c.weaponId = l.weapon!;
          c.ammo = c.weapon.mag;
          c.reloadT = 0;
          l.taken = true;
          if (c == player) {
            Sfx.pickup();
            _setToast('Picked up ${c.weapon.name}');
          }
        }
      }
    }
    loot.removeWhere((l) => l.taken);
    if (dropped != null) loot.addAll(dropped);
  }

  // =====================================================================
  //  KILLS / END
  // =====================================================================
  void _kill(Character c, int by) {
    if (!c.alive) return;
    c.placement = aliveCount;
    c.alive = false;
    c.hp = 0;
    _spawnDeath(c);
    Sfx.death();

    if (by >= 0) {
      final killer = chars.firstWhere((k) => k.id == by, orElse: () => c);
      if (killer.id != c.id) {
        killer.kills++;
        _addKillLine(killer, c);
      }
      if (by == player.id && c != player) _setToast('Eliminated ${c.name}');
    }
    if (c.weaponId != WeaponId.pistol) {
      loot.add(Loot(LootKind.weapon, c.pos.clone(), weapon: c.weaponId));
    }
    if (chance(0.5)) loot.add(Loot(LootKind.medkit, c.pos.clone(), heal: 45));

    _checkEnd();
  }

  void _addKillLine(Character killer, Character victim) {
    final kColor = killer == player ? kAccent : const Color(0xFFDDE3EC);
    final painter = tp.TextPainter(
      text: tp.TextSpan(
        style: const tp.TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Color(0xCC000000), blurRadius: 2)],
        ),
        children: [
          tp.TextSpan(text: killer.name, style: tp.TextStyle(color: kColor)),
          const tp.TextSpan(
              text: '  ▸  ', style: tp.TextStyle(color: Color(0xFFFF5A5F))),
          tp.TextSpan(
              text: victim.name,
              style: const tp.TextStyle(color: Color(0xFFAAB2BE))),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _killLog.add(_KillLine(painter, 4.0));
    if (_killLog.length > 5) _killLog.removeAt(0);
  }

  void _checkEnd() {
    final alive = chars.where((c) => c.alive).toList();
    if (alive.length <= 1) {
      playing = false;
      // A real win only if the last one standing is actually the player
      // (if everyone died on the same frame, nobody won).
      resultWon = alive.isNotEmpty && alive.first.id == player.id;
      resultPlacement = resultWon ? 1 : player.placement;
      if (resultWon) Sfx.win();
      if (!_recorded) {
        _recorded = true;
        lastRewards = Profile.instance.recordResult(
            placement: resultPlacement,
            matchKills: player.kills,
            won: resultWon);
        Profile.instance.updateMissions(
            kills: player.kills,
            won: resultWon,
            placement: resultPlacement,
            grenades: grenadesThrown);
      }
      endShown = true;
      screen.value = Screen.end;
      return;
    }
    if (!player.alive && !endShown) {
      endShown = true;
      resultWon = false;
      resultPlacement = player.placement;
      if (!_recorded) {
        _recorded = true;
        lastRewards = Profile.instance.recordResult(
            placement: player.placement, matchKills: player.kills, won: false);
        Profile.instance.updateMissions(
            kills: player.kills,
            won: false,
            placement: player.placement,
            grenades: grenadesThrown);
      }
      screen.value = Screen.end;
    }
  }

  // =====================================================================
  //  PARTICLES
  // =====================================================================
  void _updateParticles(double dt) {
    for (final p in particles) {
      p.life -= dt;
      p.pos.setFrom(p.pos + p.vel * dt);
      p.vel.setFrom(p.vel * (1 - (3 * dt).clamp(0.0, 1.0)));
    }
    particles.removeWhere((p) => p.life <= 0);
  }

  void _spawnMuzzle(Character c) {
    final tip = c.pos + fromAngle(c.aim) * (c.radius + 14);
    // flash
    for (var i = 0; i < 4; i++) {
      final a = c.aim + randRange(-0.3, 0.3);
      particles.add(Particle(tip.clone(), fromAngle(a, randRange(60, 200)),
          randRange(0.06, 0.14), randRange(2, 4), const Color(0xFFFFE9A8),
          glow: true));
    }
    // drifting muzzle smoke
    for (var i = 0; i < 2; i++) {
      final a = c.aim + randRange(-0.4, 0.4);
      particles.add(Particle(tip.clone(), fromAngle(a, randRange(18, 66)),
          randRange(0.4, 0.8), randRange(3, 6), const Color(0x66888C94)));
    }
    // ejected brass casing flicking out to the side
    final side = c.aim + (c.id.isEven ? 1.4 : -1.4);
    particles.add(Particle(
        c.pos + fromAngle(c.aim) * (c.radius * 0.4),
        fromAngle(side, randRange(120, 220)),
        randRange(0.25, 0.45),
        randRange(1.6, 2.4),
        const Color(0xFFE8C15A),
        glow: true));
  }

  void _spawnDust(double x, double y) {
    particles.add(Particle(
        Vector2(x, y),
        fromAngle(randRange(0, kTau), randRange(6, 26)),
        randRange(0.25, 0.5),
        randRange(2, 4),
        const Color(0x55B8A98A)));
  }

  void _spawnBlood(double x, double y, Vector2 dir, Color color) {
    final base = dir.length2 > 0.01 ? angleOf(dir) : 0.0;
    for (var i = 0; i < 8; i++) {
      final a = base + randRange(-0.7, 0.7);
      particles.add(Particle(Vector2(x, y), fromAngle(a, randRange(40, 220)),
          randRange(0.2, 0.5), randRange(2, 4.5), color));
    }
    // dark specks that settle and linger
    for (var i = 0; i < 3; i++) {
      particles.add(Particle(
          Vector2(x, y),
          fromAngle(base + randRange(-0.5, 0.5), randRange(10, 60)),
          randRange(0.9, 1.7),
          randRange(2, 4),
          const Color(0x99801515)));
    }
  }

  void _spawnSparks(double x, double y, Color color) {
    for (var i = 0; i < 5; i++) {
      final a = randRange(0, kTau);
      particles.add(Particle(Vector2(x, y), fromAngle(a, randRange(30, 160)),
          randRange(0.1, 0.3), randRange(1.5, 3), color, glow: true));
    }
    // impact dust / debris off the surface
    for (var i = 0; i < 3; i++) {
      particles.add(Particle(
          Vector2(x, y),
          fromAngle(randRange(0, kTau), randRange(10, 60)),
          randRange(0.3, 0.6),
          randRange(1.5, 3),
          const Color(0x66A0A0A8)));
    }
  }

  void _spawnDeath(Character c) {
    for (var i = 0; i < 22; i++) {
      final a = randRange(0, kTau);
      particles.add(Particle(c.pos.clone(), fromAngle(a, randRange(60, 320)),
          randRange(0.3, 0.8), randRange(2.5, 6), c.color));
    }
    // lingering blood pool
    for (var i = 0; i < 6; i++) {
      particles.add(Particle(
          c.pos + fromAngle(randRange(0, kTau), randRange(0, 14)),
          fromAngle(randRange(0, kTau), randRange(3, 16)),
          randRange(2.2, 3.6),
          randRange(6, 12),
          const Color(0xCC5A0E0E)));
    }
  }

  // =====================================================================
  //  UI-facing setters
  // =====================================================================
  void setMove(double x, double y) => moveInput.setValues(x, y);
  void setAimStick(double x, double y) => aimStick.setValues(x, y);
  void setFire(bool v) => fireHeld = v;
  void setMouse(Vector2? s) => mouseScreen = s;
  void enableTouch(bool v) => touchMode = v;
  void requestReload() => _reloadRequested = true;

  /// Toggle single/auto fire preference (only affects auto-capable weapons).
  void toggleFireMode() {
    playerAuto = !playerAuto;
    Profile.instance.fireAuto = playerAuto;
    Profile.instance.save();
    _setToast(playerAuto ? 'AUTO fire' : 'SINGLE fire');
  }

  void throwGrenade() {
    if (playing) _throw(player);
  }

  void _throw(Character c) {
    if (!c.alive || c.grenades <= 0 || c.throwCd > 0) return;
    c.grenades--;
    if (c == player) grenadesThrown++;
    c.throwCd = kThrowCooldown;
    final dir = fromAngle(c.aim);
    grenades.add(Grenade(
      c.pos + dir * (c.radius + 10),
      dir * kGrenadeSpeed,
      c.id,
      kGrenadeFuse,
    ));
    if (c == player) Sfx.pickup();
  }

  void activateSkill() {
    final p = player;
    if (!playing || !p.alive || p.skillCd > 0) return;
    final idx = Profile.instance.hero.clamp(0, kHeroes.length - 1);
    final hero = kHeroes[idx];
    final evo = Profile.instance.heroEvolved(idx);
    switch (hero.skill) {
      case SkillType.dash:
        final dir = p.vel.length2 > 20 ? p.vel.normalized() : fromAngle(p.aim);
        p.knock.setFrom(p.knock + dir * (kDashPower * (evo ? 1.4 : 1.0)));
        break;
      case SkillType.shield:
        p.shieldT = kShieldTime * (evo ? 1.5 : 1.0);
        break;
      case SkillType.frenzy:
        p.frenzyT = kFrenzyTime * (evo ? 1.5 : 1.0);
        break;
      case SkillType.medic:
        p.hp = evo ? kMaxHp : math.min(kMaxHp, p.hp + kMedicHeal);
        break;
      case SkillType.grenadier:
        p.grenades = kGrenadeMax;
        break;
    }
    skillMaxCd = hero.cooldown * (evo ? 0.6 : 1.0);
    p.skillCd = skillMaxCd;
    Sfx.skill();
    _setToast('${hero.name} — ${hero.desc.split(' — ').first}!');
    addShake(5);
  }

  Vector2 screenToWorld(Vector2 s) => cam + (s - size / 2) / zoom;

  // =====================================================================
  //  RENDER
  // =====================================================================
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (size.x <= 0) return;
    final z = zoom;
    final sx = _shake > 0 ? randRange(-_shake, _shake) : 0.0;
    final sy = _shake > 0 ? randRange(-_shake, _shake) : 0.0;

    _viewRect = Rect.fromCenter(
      center: Offset(cam.x, cam.y),
      width: size.x / z + 220,
      height: size.y / z + 220,
    );

    canvas.save();
    canvas.translate(size.x / 2 + sx, size.y / 2 + sy);
    canvas.scale(z);
    canvas.translate(-cam.x, -cam.y);

    _drawGround(canvas);
    _drawObstacles(canvas, bushes: false);
    _drawLoot(canvas);
    _drawBullets(canvas);
    _drawGrenades(canvas);
    _drawCharacters(canvas);
    _drawParticles(canvas);
    _drawObstacles(canvas, bushes: true);
    _drawGas(canvas);
    _drawDmgTexts(canvas);

    canvas.restore();

    _drawHitIndicators(canvas); // screen-space arcs pointing at attackers
    _drawHitMarker(canvas);
    _drawGasVignette(canvas);
    _drawLowHp(canvas);
    _drawKillFeed(canvas);
  }

  void _drawGasVignette(Canvas canvas) {
    if (!player.alive || size.x <= 0) return;
    if (player.pos.distanceTo(zoneCenter) <= zoneRadius) return; // safe inside
    final pulse = 0.5 + 0.5 * math.sin(_time * 5);
    final alpha = (0.4 * pulse).clamp(0.0, 0.5);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, size.y),
        Paint()
          ..shader = Gradient.radial(
              Offset(size.x / 2, size.y / 2),
              math.max(size.x, size.y) * 0.72,
              [
                const Color(0x00B14BFF),
                const Color(0xFFB14BFF).withValues(alpha: alpha),
              ],
              [0.55, 1.0]));
  }

  void _drawKillFeed(Canvas canvas) {
    if (_killLog.isEmpty || size.x <= 0) return;
    var y = 155.0;
    for (var i = _killLog.length - 1; i >= 0; i--) {
      final k = _killLog[i];
      k.painter.paint(canvas, Offset(size.x - 14 - k.painter.width, y));
      y += 20;
    }
  }

  void _drawDmgTexts(Canvas canvas) {
    for (final d in _dmgTexts) {
      d.painter.paint(canvas, Offset(d.pos.x - d.painter.width / 2, d.pos.y));
    }
  }

  void _drawHitMarker(Canvas canvas) {
    if (_hitMarkerT <= 0 || size.x <= 0) return;
    final a = (_hitMarkerT / 0.14).clamp(0.0, 1.0);
    final cx = size.x / 2;
    final cy = size.y / 2;
    _stroke
      ..color = const Color(0xFFFFFFFF).withValues(alpha: a)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const g = 7.0;
    const l = 7.0;
    canvas.drawLine(
        Offset(cx - g, cy - g), Offset(cx - g - l, cy - g - l), _stroke);
    canvas.drawLine(
        Offset(cx + g, cy - g), Offset(cx + g + l, cy - g - l), _stroke);
    canvas.drawLine(
        Offset(cx - g, cy + g), Offset(cx - g - l, cy + g + l), _stroke);
    canvas.drawLine(
        Offset(cx + g, cy + g), Offset(cx + g + l, cy + g + l), _stroke);
  }

  void _drawLowHp(Canvas canvas) {
    if (!player.alive || size.x <= 0) return;
    final frac = (player.hp / kMaxHp).clamp(0.0, 1.0);
    if (frac >= 0.35) return; // only when badly hurt
    final intensity = 1 - frac / 0.35;
    final pulse = 0.55 + 0.45 * math.sin(_time * 6);
    final alpha = (0.55 * intensity * pulse).clamp(0.0, 0.6);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.x, size.y),
        Paint()
          ..shader = Gradient.radial(
              Offset(size.x / 2, size.y / 2),
              math.max(size.x, size.y) * 0.72,
              [
                const Color(0x00CC0000),
                const Color(0xFFCC0000).withValues(alpha: alpha),
              ],
              [0.5, 1.0]));
  }

  void _drawHitIndicators(Canvas canvas) {
    if (_hitMarks.isEmpty || size.x <= 0) return;
    final cx = size.x / 2;
    final cy = size.y / 2;
    final rad = math.min(cx, cy) * 0.6;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: rad);
    for (final m in _hitMarks) {
      final a = (m.life / 2.2).clamp(0.0, 1.0);
      canvas.drawArc(
        rect,
        m.angle - 0.32,
        0.64,
        false,
        _stroke
          ..color = const Color(0xFFFF3B30).withValues(alpha: 0.85 * a)
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawGround(Canvas canvas) {
    canvas.drawRect(Rect.fromLTWH(0, 0, worldSize, worldSize), _groundPaint);
    const gap = 120.0;
    final vr = _viewRect;
    for (var x = (vr.left ~/ gap) * gap; x < vr.right; x += gap) {
      canvas.drawLine(Offset(x, vr.top), Offset(x, vr.bottom), _gridPaint);
    }
    for (var y = (vr.top ~/ gap) * gap; y < vr.bottom; y += gap) {
      canvas.drawLine(Offset(vr.left, y), Offset(vr.right, y), _gridPaint);
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, worldSize, worldSize), _borderPaint);
  }

  void _drawObstacles(Canvas canvas, {required bool bushes}) {
    final theme = mapTheme.name;
    for (final o in obstacles) {
      if ((o.kind == ObstacleKind.bush) != bushes) continue;
      if (!_viewRect.overlaps(o.rect.inflate(30))) continue; // cull off-screen
      final r = o.rect;

      if (bushes) {
        final c = r.center;
        final rad = r.width / 2;
        canvas.drawOval(
            Rect.fromCenter(
                center: c.translate(4, 7), width: rad * 2.1, height: rad * 1.5),
            _fill..color = const Color(0x44000000));
        if (theme == 'FOREST') {
          // proper tree: trunk + layered canopy
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(
                      center: c.translate(0, rad * 0.25),
                      width: rad * 0.34,
                      height: rad * 0.95),
                  Radius.circular(rad * 0.12)),
              _fill..color = const Color(0xFF4A3320));
          canvas.drawCircle(c.translate(0, -rad * 0.2), rad * 1.05,
              _fill..color = const Color(0xFF123E1D));
          canvas.drawCircle(c.translate(0, -rad * 0.2), rad * 0.8,
              _fill..color = const Color(0xFF1E6B32));
          canvas.drawCircle(c.translate(-rad * 0.3, -rad * 0.5), rad * 0.4,
              _fill..color = const Color(0x882FB85A));
        } else {
          canvas.drawCircle(c, rad, _fill..color = const Color(0x77123F1E));
          canvas.drawCircle(c, rad * 0.78, _fill..color = const Color(0xDD1F6B34));
          canvas.drawCircle(c.translate(-rad * 0.25, -rad * 0.28), rad * 0.42,
              _fill..color = const Color(0x552FB85A));
        }
        continue;
      }

      final wall = o.kind == ObstacleKind.wall;

      // Badlands crates are rounded boulders instead of wooden crates.
      if (!wall && theme == 'BADLANDS') {
        final c = r.center;
        final rad = r.width * 0.62;
        canvas.drawOval(
            Rect.fromCenter(
                center: c.translate(5, 7), width: rad * 2.0, height: rad * 1.5),
            _fill..color = const Color(0x55000000));
        canvas.drawCircle(c, rad, _fill..color = const Color(0xFF6B6258));
        canvas.drawCircle(c.translate(-rad * 0.28, -rad * 0.28), rad * 0.5,
            _fill..color = const Color(0xFF8A8074));
        canvas.drawCircle(c, rad,
            _stroke..color = const Color(0x55000000)..strokeWidth = 2);
        continue;
      }

      // Extruded 2.5D block (wall / crate), tinted per theme.
      final h = wall ? 16.0 : 11.0;
      final radius = Radius.circular(wall ? 4 : 5);
      Color topColor, sideColor;
      if (wall) {
        switch (theme) {
          case 'URBAN':
            topColor = const Color(0xFF515C74);
            sideColor = const Color(0xFF2A3245);
            break;
          case 'BADLANDS':
            topColor = const Color(0xFF9C8460);
            sideColor = const Color(0xFF5E4E38);
            break;
          case 'FOREST':
            topColor = const Color(0xFF5A4A34);
            sideColor = const Color(0xFF352A1C);
            break;
          default:
            topColor = const Color(0xFF46536F);
            sideColor = const Color(0xFF232C42);
        }
      } else {
        topColor = theme == 'FOREST'
            ? const Color(0xFF6E6A3A)
            : const Color(0xFF876540);
        sideColor = theme == 'FOREST'
            ? const Color(0xFF3C3A20)
            : const Color(0xFF493420);
      }

      canvas.drawRRect(RRect.fromRectAndRadius(r.translate(7, 9), radius),
          _fill..color = const Color(0x55000000));
      final body = Rect.fromLTRB(r.left, r.top - h, r.right, r.bottom);
      canvas.drawRRect(
          RRect.fromRectAndRadius(body, radius), _fill..color = sideColor);
      final top = r.translate(0, -h);
      canvas.drawRRect(
          RRect.fromRectAndRadius(top, radius), _fill..color = topColor);
      canvas.drawRect(Rect.fromLTWH(top.left + 2, top.top + 2, top.width - 4, 3),
          _fill..color = const Color(0x3AFFFFFF));

      if (wall && theme == 'URBAN') {
        // lit windows on the building rooftops
        _fill.color = const Color(0x66FFE9A8);
        for (var wx = top.left + 6; wx < top.right - 6; wx += 12) {
          for (var wy = top.top + 6; wy < top.bottom - 6; wy += 12) {
            canvas.drawRect(Rect.fromLTWH(wx, wy, 5, 5), _fill);
          }
        }
      } else if (!wall) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(top.deflate(3), const Radius.circular(3)),
            _stroke
              ..color = const Color(0x55FFCF9E)
              ..strokeWidth = 2);
      }
    }
  }

  void _drawLoot(Canvas canvas) {
    for (final l in loot) {
      if (l.taken) continue;
      if (!_vis(l.pos.x, l.pos.y)) continue;
      final bobY = math.sin(_time * 3 + l.bob) * 3;
      final c = Offset(l.pos.x, l.pos.y + bobY);
      final pulse = 0.55 + 0.45 * math.sin(_time * 4 + l.bob);
      if (l.kind == LootKind.medkit) {
        canvas.drawCircle(c, 15,
            _fill..color = const Color(0xFFFF4D5A).withValues(alpha: 0.22 * pulse));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: c, width: 20, height: 20),
                const Radius.circular(4)),
            _fill..color = const Color(0xFFFFFFFF));
        canvas.drawRect(Rect.fromCenter(center: c, width: 12, height: 4),
            _fill..color = const Color(0xFFE03A46));
        canvas.drawRect(Rect.fromCenter(center: c, width: 4, height: 12),
            _fill..color = const Color(0xFFE03A46));
      } else if (l.kind == LootKind.grenade) {
        canvas.drawCircle(c, 13,
            _fill..color = const Color(0xFF6ABF5A).withValues(alpha: 0.22 * pulse));
        canvas.drawCircle(c, 8, _fill..color = const Color(0xFF3A5A32));
        canvas.drawCircle(c, 8,
            _stroke..color = const Color(0xFF7FCF6A)..strokeWidth = 1.5);
        canvas.drawRect(Rect.fromCenter(center: c.translate(0, -8), width: 5, height: 4),
            _fill..color = const Color(0xFF9AA6B2));
      } else {
        final wc = kWeapons[l.weapon]!.color;
        canvas.drawCircle(
            c, 15, _fill..color = wc.withValues(alpha: 0.22 * pulse));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: c.translate(0, -1), width: 20, height: 6),
                const Radius.circular(2)),
            _fill..color = wc);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(c.dx - 4, c.dy + 1, 6, 8),
                const Radius.circular(2)),
            _fill..color = wc);
      }
    }
  }

  // Tracer thickness per weapon so each gun's fire reads differently:
  // fat slow sniper bolts, tiny fast minigun/SMG rounds, punchy magnum, etc.
  double _tracerW(WeaponId w) {
    switch (w) {
      case WeaponId.sniper:
        return 1.9;
      case WeaponId.dmr:
        return 1.4;
      case WeaponId.magnum:
        return 1.3;
      case WeaponId.smg:
      case WeaponId.minigun:
        return 0.72;
      case WeaponId.shotgun:
        return 0.7;
      default:
        return 1.0;
    }
  }

  void _drawBullets(Canvas canvas) {
    for (final b in bullets) {
      if (!_vis(b.pos.x, b.pos.y)) continue;
      // Longer trail for fatter tracers (extend the tail back along velocity).
      final tail = 1.0 + (b.tracer - 1.0) * 0.6;
      final a = Offset(
        b.pos.x - (b.pos.x - b.prev.x) * tail,
        b.pos.y - (b.pos.y - b.prev.y) * tail,
      );
      final bb = Offset(b.pos.x, b.pos.y);
      canvas.drawLine(
          a,
          bb,
          _stroke
            ..color = b.color.withValues(alpha: 0.35)
            ..strokeWidth = 5 * b.tracer
            ..strokeCap = StrokeCap.round);
      canvas.drawLine(
          a,
          bb,
          _stroke
            ..color = b.color
            ..strokeWidth = 2.4 * b.tracer);
      canvas.drawCircle(
          bb, 2.4 * b.tracer, _fill..color = const Color(0xFFFFFFFF));
    }
  }

  void _drawGrenades(Canvas canvas) {
    for (final g in grenades) {
      if (!_vis(g.pos.x, g.pos.y, 30)) continue;
      final o = Offset(g.pos.x, g.pos.y);
      canvas.drawOval(
          Rect.fromCenter(center: o.translate(2, 5), width: 16, height: 7),
          _fill..color = const Color(0x44000000));
      canvas.drawCircle(o, 7, _fill..color = const Color(0xFF2E3A2A));
      canvas.drawCircle(o, 7,
          _stroke..color = const Color(0xFF6A7A55)..strokeWidth = 1.5);
      // fuse light blinks faster the closer it is to detonating
      final rate = 4 + (kGrenadeFuse - g.fuse) * 5;
      final on = (g.fuse * rate).floor().isEven;
      canvas.drawCircle(o.translate(0, -6), 2.6,
          _fill..color = on ? const Color(0xFFFF3B30) : const Color(0x55FF3B30));
    }
  }

  void _drawCharacters(Canvas canvas) {
    for (final c in chars) {
      if (!c.alive) continue;
      if (!_vis(c.pos.x, c.pos.y, 110)) continue;
      final pos = Offset(c.pos.x, c.pos.y);
      final r = c.radius;

      // ground shadow
      canvas.drawOval(
          Rect.fromCenter(
              center: pos.translate(3, r * 0.6),
              width: r * 2.0,
              height: r * 0.85),
          _fill..color = const Color(0x44000000));

      // player ground ring
      if (c == player) {
        canvas.drawCircle(
            pos,
            r + 8,
            _stroke
              ..color = kAccent.withValues(alpha: 0.55)
              ..strokeWidth = 2.5);
      }

      final moving = c.vel.length2 > 40;
      final moveAim = moving ? angleOf(c.vel) : c.aim;
      final walk = moving ? math.sin(_time * 11 + c.id * 1.7) : 0.0;
      drawOperator(canvas, pos, r, c.aim, moveAim, c.color, c.skin, c.accessory,
          c.weaponId,
          fill: _fill, stroke: _stroke, walk: walk, hero: c.hero);

      if (c.shieldT > 0) {
        canvas.drawCircle(
            pos,
            r + 10,
            _stroke
              ..color = kSafeEdge.withValues(alpha: 0.65)
              ..strokeWidth = 3);
      }

      if (c.hitFlash > 0) {
        canvas.drawCircle(
            pos,
            r * 1.05,
            _fill
              ..color = const Color(0xFFFFFFFF)
                  .withValues(alpha: (c.hitFlash / 0.12) * 0.6));
      }

      if (c.muzzle > 0) {
        final tip = c.pos + fromAngle(c.aim) * (r * 2.2);
        canvas.drawCircle(Offset(tip.x, tip.y), 9 * (c.muzzle / 0.06),
            _fill..color = const Color(0xFFFFE9A8).withValues(alpha: 0.85));
      }

      final label = _nameLabels[c.id];
      if (label != null) {
        label.paint(canvas, Offset(pos.dx - label.width / 2, pos.dy - r - 30));
      }

      if (c != player && c.hp < kMaxHp) {
        final w = r * 2;
        final bx = pos.dx - r;
        final by = pos.dy - r - 16;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(bx, by, w, 5), const Radius.circular(2)),
            _fill..color = const Color(0x88000000));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(bx, by, w * (c.hp / kMaxHp).clamp(0.0, 1.0), 5),
                const Radius.circular(2)),
            _fill..color = const Color(0xFF52E06A));
      }
    }
  }

  void _drawParticles(Canvas canvas) {
    for (final p in particles) {
      if (!_vis(p.pos.x, p.pos.y, 20)) continue;
      final a = (p.life / p.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(Offset(p.pos.x, p.pos.y), p.size * a,
          _fill..color = p.color.withValues(alpha: a));
    }
  }

  void _drawGas(Canvas canvas) {
    final vr = _viewRect;
    final center = Offset(zoneCenter.x, zoneCenter.y);

    // tint everything outside the safe circle (single offscreen layer per frame)
    canvas.saveLayer(vr, _layerPaint);
    canvas.drawRect(vr, _gasFillPaint);
    canvas.drawCircle(center, zoneRadius, _clearPaint);
    canvas.restore();

    // safe edge: a soft translucent ring + a crisp line (no blur)
    canvas.drawCircle(center, zoneRadius,
        _stroke..color = kSafeEdge.withValues(alpha: 0.3)..strokeWidth = 8);
    canvas.drawCircle(center, zoneRadius,
        _stroke..color = kSafeEdge..strokeWidth = 2.5);

    final phase = kZonePhases[zonePhase.clamp(0, kZonePhases.length - 1)];
    final targetC =
        zoneShrinking ? Offset(_zoneTargetC.x, _zoneTargetC.y) : center;
    final targetR = zoneShrinking ? _zoneTargetR : zoneRadius * phase.factor;
    canvas.drawCircle(targetC, targetR,
        _stroke..color = const Color(0x88FFFFFF)..strokeWidth = 2);
  }
}

/// A fading on-screen indicator pointing toward where damage came from.
class _DirMark {
  final double angle; // world angle from the player to the attacker
  double life;
  _DirMark(this.angle, this.life);
}

/// A floating damage number that drifts up and fades.
class _DmgText {
  final tp.TextPainter painter;
  final Vector2 pos;
  double life;
  _DmgText(this.painter, this.pos, this.life);
}

/// A "Killer ▸ Victim" line in the kill feed.
class _KillLine {
  final tp.TextPainter painter;
  double life;
  _KillLine(this.painter, this.life);
}
