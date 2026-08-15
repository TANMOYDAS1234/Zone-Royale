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
  /// Permanent marks on the ground — blood pools, scorch craters, bullet
  /// scars. They never fade, so a firefight leaves the map looking like a
  /// firefight happened there.
  final List<_Decal> _decals = [];
  /// Expanding blast rings (drawn additively over the ground).
  final List<_Shock> _shocks = [];
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
  /// Screen-shake "trauma" in 0..1. The camera offset is trauma² so light hits
  /// barely register and only real explosions kick — and it moves along a
  /// smooth curve instead of teleporting a few pixels every frame. Random
  /// per-frame jitter is what made the old shake impossible to aim through.
  double _trauma = 0;
  double _shakeX = 0, _shakeY = 0;
  double _time = 0;
  double _hudT = 0; // time since the last HUD refresh pulse

  // ---- render scratch (allocated once, reused every frame) ----
  Rect _viewRect = Rect.zero;
  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  /// The graphics-fidelity level, refreshed once per frame. Everything that is
  /// pure lighting — bloom haloes, contact shadows, dust — reads from here, so
  /// SMOOTH / BALANCED / ULTRA is a difference you can actually see.
  Quality _q = kQualities[1];
  /// A blurred paint for glow passes. Blur is the expensive part, so it is
  /// built once and skipped entirely when bloom is off.
  final Paint _glow = Paint()
    ..style = PaintingStyle.fill
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
  final Paint _gasFillPaint = Paint()..color = kGasFill;
  /// Reused every frame — allocating a Path per frame churns the heap.
  final Path _gasPath = Path();
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
  /// Recent eliminations, newest last. Read by the HUD.
  final List<KillFeedLine> killLog = [];

  // ---- killstreaks (the bit people screenshot) ----
  int streakKills = 0; // kills inside the current streak window
  double _streakT = 0; // time left to extend the streak
  int bestStreak = 0; // best multi-kill this match
  String? banner; // DOUBLE KILL / TRIPLE KILL / RAMPAGE…
  double _bannerT = 0;
  double get bannerAlpha => (_bannerT / 0.4).clamp(0.0, 1.0);

  // ---- airdrops: a marked crate with a top-tier gun, worth fighting over ----
  double _nextDrop = kAirdropFirstAt;
  int _dropsMade = 0;
  Loot? airdrop; // live crate (for the minimap marker)
  double airdropT = 0; // seconds since it landed (drives the beacon pulse)

  /// World units shown vertically. Landscape shows fewer (the screen is wide),
  /// so operators keep the same on-screen size instead of shrinking to dots.
  double get viewHeight =>
      size.x > size.y ? kViewHeightLandscape : kViewHeight;

  double get zoom => size.y <= 0 ? 1 : size.y / viewHeight;

  /// System bar / cutout insets, pushed in by the Flutter HUD layer. Canvas
  /// overlays (kill feed, hit arcs) keep clear of them — held sideways the
  /// gesture bar sits right where the kill feed used to run off the edge.
  double safeRight = 0;
  double safeLeft = 0;
  double safeTop = 0;
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
    if (resultWon) return;
    // the death branch stopped the simulation, so watching the rest of the
    // match has to start it again
    playing = true;
    screen.value = Screen.playing;
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
    _decals.clear();
    _shocks.clear();
    _dmgTexts.clear();
    killLog.clear();
    _hitMarks.clear();
    _hitMarkerT = 0;
    toast = null;
    _toastT = 0;
    _nextId = 0;
    _time = 0;
    _trauma = 0;
    _shakeX = 0;
    _shakeY = 0;
    pickupPrompt = null;
    _pickupFx.clear();
    airdrop = null;
    airdropT = 0;
    _dropsMade = 0;
    _nextDrop = kAirdropFirstAt;
    streakKills = 0;
    bestStreak = 0;
    _streakT = 0;
    banner = null;
    _bannerT = 0;

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
    // Armour and shield walls are the gear worth detouring for — plentiful
    // enough to find, scarce enough that grabbing them first matters.
    final vests = (9 * areaScale).round().clamp(6, 60);
    for (var i = 0; i < vests; i++) {
      loot.add(Loot(LootKind.vest, _openSpot(centerBias: 0.98)));
    }
    final helmets = (9 * areaScale).round().clamp(6, 60);
    for (var i = 0; i < helmets; i++) {
      loot.add(Loot(LootKind.helmet, _openSpot(centerBias: 0.98)));
    }
    final walls = (8 * areaScale).round().clamp(5, 50);
    for (var i = 0; i < walls; i++) {
      loot.add(Loot(LootKind.wall, _openSpot(centerBias: 0.98)));
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
    player.equipLoadout(prof.startWeapon); // primary + pistol backup
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
      // climb keeps challenging you but never becomes impossible to win. The
      // CASUAL/NORMAL/HARDCORE choice then scales the whole curve.
      final tier = Profile.instance.diff;
      final diff = (Profile.instance.level / 40.0).clamp(0.0, 1.0);
      final gruntCut = lerpd(0.72, 0.38, diff); // fraction that are grunts
      final regCut = lerpd(0.93, 0.78, diff); // grunts..regCut = regular, rest pro
      final roll = randRange(0, 1);
      double skill;
      if (roll < gruntCut) {
        skill = randRange(0.08, 0.34); // grunt: short vision, sprays, misses
      } else if (roll < regCut) {
        skill = randRange(0.36, 0.56); // regular
      } else {
        skill = randRange(0.60, 0.86); // pro
      }
      b.aiSkill =
          ((skill + lerpd(0.0, 0.10, diff)) * tier.skill).clamp(0.06, 0.92);
      // Bots hit softer than you do — a squad shouldn't melt you in one burst.
      b.aiDamage = (tier.damage * randRange(0.9, 1.1)).clamp(0.4, 1.05);
      b.aim = randRange(0, kTau);
      b.aiScan = randRange(0, 0.3); // stagger first scan
      // some bots land already armed so early fights aren't all pistols
      b.equipLoadout(chance(0.5) ? weighted(kLootTable) : WeaponId.pistol);
      // and some land geared — tougher bots wear more of it
      if (chance(0.25 + 0.35 * b.aiSkill)) b.vest = kVestDurability;
      if (chance(0.18 + 0.30 * b.aiSkill)) b.helmet = kHelmetDurability;
      b.walls = chance(0.5) ? 1 : 0;
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
    _updateShake(dt);

    if (_toastT > 0) {
      _toastT -= dt;
      if (_toastT <= 0) toast = null;
    }

    if (playing) _step(dt);
    _updateCamera(dt);
    // HUD refresh is time-based, not frame-based: on a 120Hz panel "every 3rd
    // frame" meant rebuilding the whole HUD 40x a second for numbers that only
    // need ~20. Half the widget work, no visible difference.
    _hudT += dt;
    if (_hudT >= 0.05) {
      _hudT = 0;
      ticker.value++;
    }
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
      if (c.swapT > 0) c.swapT -= dt;
      if (c.wallCd > 0) c.wallCd -= dt;
      if (c.armourFlash > 0) c.armourFlash -= dt;
      if (c.skillCd > 0) c.skillCd -= dt;
      if (c.shieldT > 0) c.shieldT -= dt;
      if (c.frenzyT > 0) c.frenzyT -= dt;
      if (c.reloadT > 0) {
        c.reloadT -= dt;
        if (c.reloadT <= 0) c.ammo = c.weapon.mag;
      }
      // kick up dust while running, and leave boot prints behind
      if (c.vel.length2 > 12000) {
        if (chance(5 * dt)) {
          _spawnDust(c.pos.x + randRange(-6, 6), c.pos.y + c.radius * 0.55);
        }
        c.stepT -= dt;
        if (c.stepT <= 0) {
          c.stepT = 0.26;
          final side = Vector2(-c.vel.y, c.vel.x).normalized() *
              (c.stepFoot ? 7.0 : -7.0);
          c.stepFoot = !c.stepFoot;
          _decals.add(_Decal(c.pos + side, 11, 6, angleOf(c.vel),
              const Color(0x33000000)));
          if (_decals.length > 150) _decals.removeAt(0);
        }
      }
    }
    _separateCharacters();
    _updateBullets(dt);
    _updateGrenades(dt);
    _updateParticles(dt);
    _updateZone(dt);
    _updateWalls(dt);
    _updateAirdrop(dt);
    _updateStreak(dt);
    _updatePickupFx(dt);
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
    for (final k in killLog) {
      k.life -= dt;
    }
    killLog.removeWhere((k) => k.life <= 0);
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

  /// Queue screen shake. [v] is trauma (see [_trauma]); the player's SCREEN
  /// SHAKE slider scales it, and 0 turns it off completely.
  void addShake(double v) {
    final s = Profile.instance.shake;
    if (s <= 0.001) return;
    _trauma = math.min(1.0, _trauma + v * s);
  }

  /// Smooth, continuous shake: two out-of-phase sine sums per axis. Because the
  /// offset follows a curve rather than a fresh random number each frame, the
  /// picture *sways* instead of vibrating — you can still track a target.
  void _updateShake(double dt) {
    _trauma = math.max(0, _trauma - dt * 1.9); // ~0.5s to settle from full
    if (_trauma <= 0) {
      _shakeX = 0;
      _shakeY = 0;
      return;
    }
    final amp = _trauma * _trauma * kShakeMaxPx;
    double wob(double t) =>
        math.sin(t) * 0.62 + math.sin(t * 2.17 + 1.9) * 0.38;
    _shakeX = amp * wob(_time * 27);
    _shakeY = amp * wob(_time * 23.4 + 11.7);
  }

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
    if (c.reloading || c.cooldown > 0 || c.swapping) return;
    if (c.ammo <= 0) {
      _startReload(c);
      return;
    }
    c.ammo--;
    c.cooldown = w.fireInterval * (c.frenzyT > 0 ? 0.45 : 1.0); // VORTEX frenzy
    c.muzzle = 0.06;

    final dmg = w.damage * (c.isBot ? c.aiDamage : 1.0);
    for (var i = 0; i < w.pellets; i++) {
      final jitter = w.pellets > 1
          ? randRange(-w.spread, w.spread)
          : gaussian() * w.spread;
      final dir = fromAngle(c.aim + jitter);
      final origin = c.pos + dir * (c.radius + 8);
      bullets.add(Bullet(origin.clone(), dir * w.bulletSpeed, dmg, w.range,
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
      // Firing shake is the one that hurts your aim the most, so it's the
      // lightest — a kick you feel, not a picture that jumps.
      addShake(w.id == WeaponId.shotgun
          ? kShakeFireHeavy
          : w.id == WeaponId.sniper
              ? kShakeFireSniper
              : kShakeFireLight);
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
      Obstacle? hitWall;
      for (final o in obstacles) {
        if (!o.blocks) continue;
        final t =
            segRect(b.prev.x, b.prev.y, b.pos.x, b.pos.y, o.x, o.y, o.w, o.h);
        if (t >= 0 && t < hitT) {
          hitT = t;
          hitWall = o.isShield ? o : null; // shield walls take damage
        }
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
          if (chance(0.3)) {
            _addDecal(Vector2(hx, hy), randRange(14, 24), randRange(9, 16),
                const Color(0x66450C0C));
          }
        } else if (hitWall != null) {
          // a deployed wall soaks the round and cracks
          hitWall.hp -= b.damage;
          _spawnSparks(hx, hy, const Color(0xFF9FF0FF));
        } else {
          _spawnSparks(hx, hy, b.color);
          // bullet scar on the cover you just chipped
          if (chance(0.35)) {
            _addDecal(Vector2(hx, hy), randRange(5, 9), randRange(4, 7),
                const Color(0x55000000));
          }
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
    // blasts still hit hard — but they fall off with distance
    final d = g.pos.distanceTo(cam);
    if (d < 720) addShake(kShakeBoom * (1 - d / 720));
  }

  void _spawnExplosion(Vector2 p) {
    // scorched ground that stays for the rest of the match
    _addDecal(p, randRange(90, 120), randRange(70, 95), const Color(0x77120C08));
    _shocks.add(_Shock(p.clone(), kGrenadeRadius * 1.15, 0.42));
    // white-hot core
    for (var i = 0; i < 8; i++) {
      particles.add(Particle(
        p.clone(),
        fromAngle(randRange(0, kTau), randRange(30, 160)),
        randRange(0.1, 0.2),
        randRange(7, 14),
        const Color(0xFFFFF3C4),
        glow: true,
      ));
    }
    for (var i = 0; i < _fxCount(26); i++) {
      particles.add(Particle(
        p.clone(),
        fromAngle(randRange(0, kTau), randRange(80, 380)),
        randRange(0.25, 0.6),
        randRange(3, 8),
        i.isEven ? const Color(0xFFFFB020) : const Color(0xFFFF5A2A),
        glow: true,
      ));
    }
    // rolling smoke that lingers and drifts
    for (var i = 0; i < _fxCount(14); i++) {
      particles.add(Particle(
        p + fromAngle(randRange(0, kTau), randRange(0, 40)),
        fromAngle(randRange(0, kTau), randRange(15, 90)),
        randRange(0.8, 1.6),
        randRange(8, 18),
        const Color(0x77494952),
      ));
    }
    // dirt kicked out sideways
    for (var i = 0; i < 8; i++) {
      particles.add(Particle(
        p.clone(),
        fromAngle(randRange(0, kTau), randRange(120, 300)),
        randRange(0.3, 0.7),
        randRange(2, 4),
        const Color(0xAA6B5A42),
      ));
    }
  }

  void _addDecal(Vector2 p, double rx, double ry, Color color) {
    final cap = Profile.instance.gfx.decals;
    if (cap <= 0) return;
    _decals.add(_Decal(p.clone(), rx, ry, randRange(0, kTau), color));
    // hard cap: old marks drop off so a long match can't bloat the draw list
    while (_decals.length > cap) {
      _decals.removeAt(0);
    }
  }

  /// Particle budget for one effect, scaled by the graphics setting.
  int _fxCount(int n) =>
      (n * Profile.instance.gfx.fx).round().clamp(1, n * 2);

  void _damage(Character c, double dmg, int by, Vector2 dir) {
    if (!c.alive) return;
    if (c.shieldT > 0) dmg *= kShieldCut; // BASTION shield
    final before = dmg;
    dmg = c.soak(dmg); // vest + helmet eat their share and wear down
    if (c == player && dmg < before) Sfx.hit(); // metallic "tink" on armour
    c.hp -= dmg;
    c.hitFlash = 0.12;
    if (dir.length2 > 0.01) c.knock.setFrom(c.knock + dir.normalized() * 90);
    if (c == player) {
      addShake(kShakeHurt);
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
      final tier = Profile.instance.diff;
      final enemy = _nearestEnemy(c, lerpd(340, 520, c.aiSkill) * tier.vision);
      if (enemy != null && c.aiEnemy?.id != enemy.id) {
        // grunts hesitate before opening up — this is your window to react
        c.aiReact = lerpd(0.95, 0.16, c.aiSkill) * tier.react;
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

    // Hurt and being shot at? Throw up cover, like a real player would. Only
    // the better bots think of it, so it reads as skill rather than scripting.
    if (c.aiEnemy != null &&
        c.walls > 0 &&
        c.wallCd <= 0 &&
        c.hp < kMaxHp * 0.55 &&
        c.aiSkill > 0.45 &&
        chance(0.5 * dt)) {
      c.aim = angleOf(c.aiEnemy!.pos - c.pos);
      _deployWall(c);
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
  //  AIRDROPS + KILLSTREAKS
  // =====================================================================
  /// Every so often a flare goes up inside the safe zone and a crate lands with
  /// a top-tier gun in it. It's marked on the minimap for everyone, which turns
  /// a quiet mid-game into a fight people actually want to have.
  void _updateAirdrop(double dt) {
    if (airdrop != null) {
      airdropT += dt;
      if (airdrop!.taken) {
        airdrop = null; // someone claimed it
      }
    }
    if (_dropsMade >= kAirdropMax) return;
    _nextDrop -= dt;
    if (_nextDrop > 0) return;
    _dropsMade++;
    _nextDrop = kAirdropEvery;
    // land it inside the current circle so it's always reachable
    Vector2 spot = zoneCenter.clone();
    for (var i = 0; i < 40; i++) {
      final a = randRange(0, kTau);
      final r = randRange(zoneRadius * 0.15, zoneRadius * 0.75);
      final p = Vector2(zoneCenter.x + math.cos(a) * r,
          zoneCenter.y + math.sin(a) * r);
      if (p.x < 140 || p.x > worldSize - 140) continue;
      if (p.y < 140 || p.y > worldSize - 140) continue;
      if (_inWall(p.x, p.y)) continue;
      spot = p;
      break;
    }
    final crate = Loot(LootKind.weapon, spot, weapon: weighted(kAirdropTable))
      ..airdrop = true;
    loot.add(crate);
    airdrop = crate;
    airdropT = 0;
    for (var i = 0; i < 18; i++) {
      particles.add(Particle(
          spot.clone(),
          fromAngle(randRange(0, kTau), randRange(40, 190)),
          randRange(0.4, 0.9),
          randRange(3, 7),
          const Color(0xFFFFB02E),
          glow: true));
    }
    Sfx.zone();
    _setToast('📦 AIRDROP INCOMING — check your map');
  }

  void _updateStreak(double dt) {
    if (_streakT > 0) {
      _streakT -= dt;
      if (_streakT <= 0) streakKills = 0; // window closed
    }
    if (_bannerT > 0) {
      _bannerT -= dt;
      if (_bannerT <= 0) banner = null;
    }
  }

  static const _streakNames = [
    'DOUBLE KILL',
    'TRIPLE KILL',
    'QUAD KILL',
    'RAMPAGE',
    'UNSTOPPABLE',
    'GODLIKE',
  ];

  void _registerPlayerKill() {
    _streakT = 6.0; // 6s to keep the chain alive
    streakKills++;
    if (streakKills > bestStreak) bestStreak = streakKills;
    if (streakKills >= 2) {
      banner = _streakNames[
          (streakKills - 2).clamp(0, _streakNames.length - 1)];
      _bannerT = 1.8;
      Sfx.win(vol: 0.35);
    }
  }

  // =====================================================================
  //  LOOT
  // =====================================================================
  /// Short-lived pickup flourishes: the item lifts off the ground, spins and
  /// bursts into sparks with a label. Collecting something should FEEL like
  /// collecting something.
  final List<_PickupFx> _pickupFx = [];

  void _pickupPop(Vector2 at, Color color, String label, {bool big = false}) {
    _pickupFx.add(_PickupFx(at.clone(), color, label, big ? 0.9 : 0.65, big));
    if (_pickupFx.length > 12) _pickupFx.removeAt(0);
    final n = _fxCount(big ? 18 : 10);
    for (var i = 0; i < n; i++) {
      final a = randRange(0, kTau);
      particles.add(Particle(
          at + fromAngle(a, randRange(0, 10)),
          fromAngle(a, randRange(50, big ? 220 : 140)),
          randRange(0.25, 0.55),
          randRange(1.8, big ? 4.5 : 3.2),
          color,
          glow: true));
    }
    // a ring that snaps outward
    _shocks.add(_Shock(at.clone(), big ? 90 : 58, 0.32));
  }

  void _updatePickupFx(double dt) {
    for (final f in _pickupFx) {
      f.t += dt;
    }
    _pickupFx.removeWhere((f) => f.t >= f.life);
  }

  /// The weapon crate the player is standing on that needs a deliberate tap.
  /// Set when both slots are full — the HUD turns this into a PICK UP button.
  /// While it's null, nothing on the ground can change what you're holding.
  Loot? pickupPrompt;

  void _pickups() {
    // Dropped weapons are collected here and added AFTER iteration finishes —
    // adding to `loot` while looping over it throws ConcurrentModificationError.
    List<Loot>? dropped;
    Loot? prompt;
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
          _pickupPop(l.pos, const Color(0xFF57E389), '+${l.heal.toInt()} HP');
          if (c == player) {
            Sfx.pickup();
            _setToast('+${l.heal.toInt()} HP');
          }
        } else if (l.kind == LootKind.grenade) {
          if (c.grenades >= kGrenadeMax) continue;
          c.grenades = math.min(kGrenadeMax, c.grenades + 2);
          l.taken = true;
          _pickupPop(l.pos, const Color(0xFF7FCF6A), '+2 NADES');
          if (c == player) {
            Sfx.pickup();
            _setToast('+2 grenades');
          }
        } else if (l.kind == LootKind.vest) {
          if (c.vest >= kVestDurability * 0.9) continue; // already geared
          c.vest = kVestDurability;
          l.taken = true;
          _pickupPop(l.pos, const Color(0xFF7FC4FF), 'VEST');
          if (c == player) {
            Sfx.pickup();
            _setToast('🦺 Vest equipped  ·  -30% damage');
          }
        } else if (l.kind == LootKind.helmet) {
          if (c.helmet >= kHelmetDurability * 0.9) continue;
          c.helmet = kHelmetDurability;
          l.taken = true;
          _pickupPop(l.pos, const Color(0xFFC9D6A8), 'HELMET');
          if (c == player) {
            Sfx.pickup();
            _setToast('⛑ Helmet equipped  ·  -22% damage');
          }
        } else if (l.kind == LootKind.wall) {
          if (c.walls >= kShieldWallMax) continue;
          c.walls = math.min(kShieldWallMax, c.walls + 1);
          l.taken = true;
          _pickupPop(l.pos, const Color(0xFF7FE8FF), '+1 WALL');
          if (c == player) {
            Sfx.pickup();
            _setToast('+1 shield wall');
          }
        } else {
          final w = l.weapon!;
          if (c.slots.contains(w)) continue; // already carrying one
          if (c.addWeapon(w)) {
            // free slot — always safe to take, nothing leaves your hands
            l.taken = true;
            _pickupPop(l.pos, kWeapons[w]!.color,
                kWeapons[w]!.name.toUpperCase(),
                big: l.airdrop);
            if (c.isBot) {
              c.equipBest();
            } else {
              Sfx.pickup();
              _setToast('${kWeapons[w]!.name} stowed  ·  tap SWITCH');
            }
            continue;
          }
          if (c.isBot) {
            // bots trade up on their own, but only for a clearly better gun
            final worst =
                weaponScore(c.slots[0]!) <= weaponScore(c.slots[1]!) ? 0 : 1;
            if (weaponScore(w) > weaponScore(c.slots[worst]!) + 0.05) {
              (dropped ??= []).add(Loot(LootKind.weapon,
                  c.pos - fromAngle(c.aim) * (c.radius + 26),
                  weapon: c.slots[worst])
                ..readyAt = _time + 1.6);
              c.slots[worst] = w;
              c.slotAmmo[worst] = kWeapons[w]!.mag;
              c.equipBest();
              l.taken = true;
            }
            continue;
          }
          // Both slots full, but the spare one is only the backup pistol and
          // this is a real gun: quietly stow it there. Your hands are never
          // touched, so this can't cost you a fight — it just saves a tap.
          final spare = 1 - c.slot;
          if (c.slots[spare] == WeaponId.pistol && w != WeaponId.pistol) {
            c.slots[spare] = w;
            c.slotAmmo[spare] = kWeapons[w]!.mag;
            l.taken = true;
            Sfx.pickup();
            _setToast('${kWeapons[w]!.name} stowed  ·  tap SWITCH');
            continue;
          }
          // BOTH SLOTS FULL + it's you: the game does NOT decide. Either you
          // opted into auto-swap in Profile, or the HUD offers a PICK UP tap.
          if (Profile.instance.autoSwapWeapons) {
            final old = c.replaceWeapon(w);
            if (old != null) {
              (dropped ??= []).add(Loot(LootKind.weapon,
                  c.pos - fromAngle(c.aim) * (c.radius + 26),
                  weapon: old)
                ..readyAt = _time + 1.6);
            }
            l.taken = true;
            Sfx.pickup();
            _setToast('Picked up ${c.weapon.name}');
          } else {
            prompt ??= l;
          }
        }
      }
    }
    pickupPrompt = prompt;
    loot.removeWhere((l) => l.taken);
    if (dropped != null) loot.addAll(dropped);
  }

  /// PICK UP button — swap the crate you're standing on into your hands,
  /// dropping the gun it replaces at your feet.
  void takePickup() {
    final l = pickupPrompt;
    if (l == null || l.taken || !playing || !player.alive) return;
    final w = l.weapon;
    if (w == null) return;
    final old = player.replaceWeapon(w);
    l.taken = true;
    pickupPrompt = null;
    _pickupPop(l.pos, kWeapons[w]!.color, kWeapons[w]!.name.toUpperCase(),
        big: l.airdrop);
    if (old != null) {
      loot.add(Loot(LootKind.weapon,
          player.pos - fromAngle(player.aim) * (player.radius + 26),
          weapon: old)
        ..readyAt = _time + 1.2);
    }
    Sfx.pickup();
    _setToast('Picked up ${player.weapon.name}');
  }

  /// SHIELD WALL — drops a slab of cover a couple of steps in front of you,
  /// square-on to where you're facing. It stops bullets and bodies, takes
  /// damage, and melts after [kShieldWallLife] seconds. This is the "oh no —
  /// wall!" button that turns a lost fight into a reset.
  void deployWall() {
    if (!playing) return;
    _deployWall(player);
  }

  void _deployWall(Character c) {
    if (!c.alive || c.walls <= 0 || c.wallCd > 0) return;
    // stand it up perpendicular to the aim, a short step ahead
    final ahead = c.pos + fromAngle(c.aim) * (c.radius + 46);
    final horizontal =
        math.sin(c.aim).abs() > math.cos(c.aim).abs(); // facing up/down?
    final w = horizontal ? kShieldWallWidth : kShieldWallThickness;
    final h = horizontal ? kShieldWallThickness : kShieldWallWidth;
    final x = clampd(ahead.x - w / 2, 4, worldSize - w - 4);
    final y = clampd(ahead.y - h / 2, 4, worldSize - h - 4);
    // don't let someone wall themselves inside solid cover
    if (_inWall(ahead.x, ahead.y, 4)) {
      if (c == player) _setToast('No room for a wall here');
      return;
    }
    c.walls--;
    c.wallCd = kShieldWallCooldown;
    obstacles.add(Obstacle(ObstacleKind.shield, x, y, w, h,
        hp: kShieldWallHp, life: kShieldWallLife, ownerId: c.id));
    for (var i = 0; i < 14; i++) {
      particles.add(Particle(
          Vector2(x + randRange(0, w), y + randRange(0, h)),
          fromAngle(randRange(0, kTau), randRange(20, 90)),
          randRange(0.2, 0.5),
          randRange(2, 5),
          const Color(0xFF7FE8FF),
          glow: true));
    }
    if (c == player) {
      Sfx.skill();
      _setToast('Shield wall up  ·  ${c.walls} left');
    }
  }

  void _updateWalls(double dt) {
    var dirty = false;
    for (final o in obstacles) {
      if (!o.isShield) continue;
      o.life -= dt;
      if (o.life <= 0 || o.hp <= 0) dirty = true;
    }
    if (!dirty) return;
    for (final o in obstacles) {
      if (!o.isShield || (o.life > 0 && o.hp > 0)) continue;
      // puff of shards as it goes
      for (var i = 0; i < 10; i++) {
        particles.add(Particle(
            Vector2(o.x + randRange(0, o.w), o.y + randRange(0, o.h)),
            fromAngle(randRange(0, kTau), randRange(20, 120)),
            randRange(0.2, 0.5),
            randRange(2, 4),
            const Color(0xFF9FF0FF),
            glow: true));
      }
    }
    obstacles.removeWhere((o) => o.isShield && (o.life <= 0 || o.hp <= 0));
  }

  /// SWITCH button (Q on desktop) — change which of your two guns is in hand.
  void swapWeapon() {
    if (!playing || !player.alive) return;
    if (player.switchSlot()) {
      Sfx.reload();
      _setToast('${player.weapon.name} ready');
    } else {
      _setToast('No second weapon');
    }
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
      if (by == player.id && c != player) {
        _setToast('Eliminated ${c.name}');
        _registerPlayerKill(); // DOUBLE KILL / TRIPLE KILL / RAMPAGE…
      }
    }
    // everything they were carrying spills out (pistols are worthless)
    for (var i = 0; i < c.slots.length; i++) {
      final w = c.slots[i];
      if (w == null || w == WeaponId.pistol) continue;
      loot.add(Loot(LootKind.weapon,
          c.pos + fromAngle(randRange(0, kTau), randRange(0, 22)),
          weapon: w));
    }
    if (chance(0.5)) loot.add(Loot(LootKind.medkit, c.pos.clone(), heal: 45));

    _checkEnd();
  }

  void _addKillLine(Character killer, Character victim) {
    killLog.add(KillFeedLine(killer.name, victim.name, killer == player, 4.0));
    // three lines max — the feed shares the top-left corner with the HP bars
    if (killLog.length > 3) killLog.removeAt(0);
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
      // Stop simulating. The win branch already did this; the death branch did
      // not, so after being eliminated the bots kept fighting underneath the
      // results card and you carried on hearing gunfire over your own summary.
      playing = false;
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
    for (final s in _shocks) {
      s.t += dt;
    }
    _shocks.removeWhere((s) => s.t >= s.life);
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
    for (var i = 0; i < _fxCount(8); i++) {
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
    for (var i = 0; i < _fxCount(22); i++) {
      final a = randRange(0, kTau);
      particles.add(Particle(c.pos.clone(), fromAngle(a, randRange(60, 320)),
          randRange(0.3, 0.8), randRange(2.5, 6), c.color));
    }
    // a blood pool that stays on the ground for the rest of the match
    _addDecal(c.pos, randRange(46, 66), randRange(34, 48),
        const Color(0x99400A0A));
    for (var i = 0; i < 4; i++) {
      _addDecal(c.pos + fromAngle(randRange(0, kTau), randRange(16, 46)),
          randRange(14, 26), randRange(10, 18), const Color(0x77380909));
    }
    // dropped kit puffs
    for (var i = 0; i < 6; i++) {
      particles.add(Particle(
          c.pos + fromAngle(randRange(0, kTau), randRange(0, 14)),
          fromAngle(randRange(0, kTau), randRange(3, 16)),
          randRange(1.4, 2.4),
          randRange(6, 12),
          const Color(0x66603030)));
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
    addShake(kShakeSkill);
  }

  Vector2 screenToWorld(Vector2 s) => cam + (s - size / 2) / zoom;

  // =====================================================================
  //  RENDER
  // =====================================================================
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (size.x <= 0) return;
    // read the fidelity setting once a frame instead of per draw call
    _q = Profile.instance.gfx;
    final z = zoom;
    final sx = _shakeX;
    final sy = _shakeY;

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
    _drawPickupFx(canvas);
    _drawObstacles(canvas, bushes: true);
    _drawGas(canvas);
    _drawDmgTexts(canvas);

    canvas.restore();

    _drawAtmosphere(canvas); // drifting dust between the camera and the world
    _drawHitIndicators(canvas); // screen-space arcs pointing at attackers
    _drawHitMarker(canvas);
    _drawGasVignette(canvas);
    _drawLowHp(canvas);
  }

  /// A thin layer of dust motes drifting between the camera and the world.
  /// Costs almost nothing and does more for "this looks like a real place"
  /// than any amount of extra ground texture.
  void _drawAtmosphere(Canvas canvas) {
    if (!Profile.instance.gfx.weather || size.x <= 0) return;
    final n = (34 * Profile.instance.gfx.detail).round().clamp(8, 60);
    for (var i = 0; i < n; i++) {
      final seed = i * 37.0;
      final speed = 12 + (i % 5) * 7;
      final x = ((seed * 13.7 + _time * speed) % (size.x + 60)) - 30;
      final y = ((seed * 29.3 + _time * (speed * 1.6)) % (size.y + 60)) - 30;
      final s = 0.9 + (i % 3) * 0.7;
      canvas.drawCircle(Offset(x, y), s,
          _fill..color = const Color(0xFFFFFFFF).withValues(alpha: 0.055));
    }
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

  /// Stable pseudo-random value for a world cell. Deterministic, so ground
  /// detail sits still as the camera moves instead of crawling.
  static double _hash(int x, int y) {
    var h = x * 374761393 + y * 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0;
  }

  void _drawGround(Canvas canvas) {
    canvas.drawRect(_viewRect, _groundPaint);
    final vr = _viewRect;
    final theme = mapTheme.name;

    // ---- surface detail: only the cells actually on screen ----
    // Bigger cells = fewer draw calls. The graphics setting scales this, which
    // is the single most effective lever for a smooth frame rate.
    final cell = 150.0 / Profile.instance.gfx.detail.clamp(0.3, 1.4);
    final x0 = (vr.left / cell).floor(), x1 = (vr.right / cell).ceil();
    final y0 = (vr.top / cell).floor(), y1 = (vr.bottom / cell).ceil();
    for (var gx = x0; gx <= x1; gx++) {
      for (var gy = y0; gy <= y1; gy++) {
        final h = _hash(gx, gy);
        final cx = gx * cell + h * cell;
        final cy = gy * cell + _hash(gy, gx) * cell;
        final c = Offset(cx, cy);
        switch (theme) {
          case 'FOREST':
            // grass tufts + leaf litter
            if (h < 0.55) {
              _fill.color = const Color(0x1433682C);
              canvas.drawOval(
                  Rect.fromCenter(
                      center: c, width: 90 + h * 120, height: 60 + h * 60),
                  _fill);
            }
            for (var i = 0; i < 4; i++) {
              final s = _hash(gx * 5 + i, gy * 11 + i);
              final p = Offset(gx * cell + s * cell,
                  gy * cell + _hash(gy * 3 + i, gx) * cell);
              _stroke
                ..color = const Color(0x3358A03C)
                ..strokeWidth = 1.6;
              canvas.drawLine(p, p.translate(-2 + s * 4, -7 - s * 5), _stroke);
            }
            break;
          case 'BADLANDS':
            // wind ripples + cracked earth
            _stroke
              ..color = const Color(0x1AE0C08A)
              ..strokeWidth = 2;
            canvas.drawArc(
                Rect.fromCenter(center: c, width: 150 + h * 90, height: 46),
                0.2,
                2.6,
                false,
                _stroke);
            if (h > 0.7) {
              _stroke
                ..color = const Color(0x33000000)
                ..strokeWidth = 1.4;
              canvas.drawLine(c, c.translate(28 + h * 40, 14 - h * 26), _stroke);
            }
            break;
          case 'URBAN':
            // asphalt patches + faded road paint
            _fill.color = const Color(0x29000000);
            canvas.drawRect(
                Rect.fromCenter(
                    center: c, width: 120 + h * 110, height: 70 + h * 50),
                _fill);
            if (h > 0.66) {
              _fill.color = const Color(0x22FFE08A);
              canvas.drawRect(
                  Rect.fromCenter(center: c, width: 46, height: 5), _fill);
            }
            break;
          default: // COMPOUND — poured concrete slabs
            _stroke
              ..color = const Color(0x2E000000)
              ..strokeWidth = 2;
            canvas.drawRect(
                Rect.fromLTWH(gx * cell, gy * cell, cell, cell), _stroke);
            _fill.color = const Color(0x05FFFFFF);
            canvas.drawRect(
                Rect.fromCenter(center: c, width: 80 + h * 60, height: 50),
                _fill);
        }
        // universal gravel so nothing looks like flat paper
        for (var i = 0; i < 3; i++) {
          final s = _hash(gx * 7 + i, gy * 13 - i);
          canvas.drawCircle(
              Offset(gx * cell + s * cell, gy * cell + _hash(gy + i, gx) * cell),
              1 + s * 1.8,
              _fill..color = const Color(0x0AFFFFFF));
        }
      }
    }

    // ---- permanent battle damage (blood, scorch, bullet scars) ----
    for (final d in _decals) {
      if (!_vis(d.pos.x, d.pos.y, 40)) continue;
      canvas.save();
      canvas.translate(d.pos.x, d.pos.y);
      canvas.rotate(d.rot);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: d.rx, height: d.ry),
          _fill..color = d.color);
      canvas.restore();
    }

    // faint survey grid keeps a sense of scale and speed
    const gap = 120.0;
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
        // Canopy goes see-through the moment anyone is under it.
        //
        // A tree you cannot see into is a tree three people are hiding in, and
        // from outside it looks identical to an empty one. Fading the crown
        // keeps concealment meaningful — you still cannot be shot through it,
        // and you still break line of sight — while letting the fight stay
        // readable instead of turning into guesswork.
        var hiding = false;
        for (final ch in chars) {
          if (ch.alive && o.contains(ch.pos.x, ch.pos.y)) {
            hiding = true;
            break;
          }
        }
        // your own bush stays denser than someone else's, so hiding still
        // feels like hiding
        final k = hiding ? 0.34 : 1.0;
        Color veil(int argb) {
          final base = Color(argb);
          return base.withValues(alpha: base.a * k);
        }

        // long soft shadow, cast the same way as every other object
        canvas.drawOval(
            Rect.fromCenter(
                center: c.translate(7, 11), width: rad * 2.2, height: rad * 1.5),
            _fill..color = veil(0x55000000));
        if (hiding) {
          // a dashed rim so the tree still reads as cover when it is faded
          _stroke
            ..color = const Color(0xFF7FE8FF).withValues(alpha: 0.5)
            ..strokeWidth = 1.6;
          canvas.drawCircle(c.translate(0, -rad * 0.2), rad * 1.05, _stroke);
        }
        if (theme == 'FOREST') {
          // proper tree: trunk, three canopy layers, sun-lit crown
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(
                      center: c.translate(0, rad * 0.25),
                      width: rad * 0.34,
                      height: rad * 0.95),
                  Radius.circular(rad * 0.12)),
              _fill..color = veil(0xFF4A3320));
          canvas.drawCircle(c.translate(0, -rad * 0.2), rad * 1.05,
              _fill..color = veil(0xFF0E3418));
          canvas.drawCircle(c.translate(-rad * 0.08, -rad * 0.3), rad * 0.84,
              _fill..color = veil(0xFF1E6B32));
          canvas.drawCircle(c.translate(-rad * 0.28, -rad * 0.48), rad * 0.46,
              _fill..color = veil(0xAA3ECC66));
          canvas.drawCircle(c.translate(-rad * 0.4, -rad * 0.6), rad * 0.2,
              _fill..color = veil(0x88A8F08A));
        } else {
          canvas.drawCircle(c, rad, _fill..color = veil(0x88102F16));
          canvas.drawCircle(c.translate(-rad * 0.06, -rad * 0.08), rad * 0.78,
              _fill..color = veil(0xE01F6B34));
          canvas.drawCircle(c.translate(-rad * 0.25, -rad * 0.28), rad * 0.42,
              _fill..color = veil(0x772FB85A));
          canvas.drawCircle(c.translate(-rad * 0.36, -rad * 0.4), rad * 0.18,
              _fill..color = veil(0x66A8F08A));
        }
        continue;
      }

      // ---- deployed shield wall: frosted energy slab that cracks ----
      if (o.isShield) {
        final health = (o.hp / kShieldWallHp).clamp(0.0, 1.0);
        final fade = (o.life / 2.0).clamp(0.0, 1.0); // fades out at the end
        final rr = RRect.fromRectAndRadius(r, const Radius.circular(5));
        canvas.drawRRect(
            RRect.fromRectAndRadius(r.translate(6, 9), const Radius.circular(5)),
            _fill..color = const Color(0x44000000));
        canvas.drawRRect(
            rr,
            _fill
              ..color = const Color(0xFF7FE8FF)
                  .withValues(alpha: (0.22 + 0.18 * health) * fade));
        canvas.drawRRect(
            rr,
            _stroke
              ..color = const Color(0xFFBFF4FF)
                  .withValues(alpha: (0.55 + 0.35 * health) * fade)
              ..strokeWidth = 2.5);
        // Hex lattice + a lit energy core seam — reads as tech, not a blue box.
        final long = r.width > r.height;
        final n = ((long ? r.width : r.height) / 22).floor();
        _stroke
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.16 * fade)
          ..strokeWidth = 1.3;
        for (var i = 1; i < n; i++) {
          final t = i / n;
          if (long) {
            final x = r.left + r.width * t;
            canvas.drawLine(Offset(x, r.top + 3), Offset(x, r.bottom - 3), _stroke);
            // chevron bracing between the ribs
            canvas.drawLine(Offset(x - r.width / n * 0.5, r.top + 3),
                Offset(x, r.center.dy), _stroke);
            canvas.drawLine(Offset(x - r.width / n * 0.5, r.bottom - 3),
                Offset(x, r.center.dy), _stroke);
          } else {
            final y = r.top + r.height * t;
            canvas.drawLine(Offset(r.left + 3, y), Offset(r.right - 3, y), _stroke);
            canvas.drawLine(Offset(r.left + 3, y - r.height / n * 0.5),
                Offset(r.center.dx, y), _stroke);
            canvas.drawLine(Offset(r.right - 3, y - r.height / n * 0.5),
                Offset(r.center.dx, y), _stroke);
          }
        }
        // glowing spine down the middle, brighter while the wall is healthy
        final core = long
            ? Rect.fromLTRB(r.left + 2, r.center.dy - 2, r.right - 2, r.center.dy + 2)
            : Rect.fromLTRB(r.center.dx - 2, r.top + 2, r.center.dx + 2, r.bottom - 2);
        canvas.drawRRect(
            RRect.fromRectAndRadius(core, const Radius.circular(2)),
            _fill
              ..color = const Color(0xFFEAFBFF)
                  .withValues(alpha: (0.35 + 0.45 * health) * fade));
        // emitter caps at both ends
        for (final e in long
            ? [Offset(r.left + 5, r.center.dy), Offset(r.right - 5, r.center.dy)]
            : [Offset(r.center.dx, r.top + 5), Offset(r.center.dx, r.bottom - 5)]) {
          canvas.drawCircle(e, 4.5,
              _fill..color = const Color(0xFF2A6B7F).withValues(alpha: fade));
          canvas.drawCircle(e, 2.2,
              _fill..color = const Color(0xFFDFF8FF).withValues(alpha: fade));
        }
        if (health < 0.75) {
          _stroke
            ..color = const Color(0xFF0A2A33).withValues(alpha: 0.7 * fade)
            ..strokeWidth = 2;
          final cracks = ((1 - health) * 6).round();
          for (var i = 0; i < cracks; i++) {
            final s = _hash(o.x.round() + i, o.y.round() - i);
            final p1 = Offset(r.left + r.width * s, r.top + r.height * (1 - s));
            canvas.drawLine(p1, p1.translate(-9 + s * 20, 8 - s * 18), _stroke);
          }
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

      // Contact shadow first, always cast the same way (light sits top-left)
      // so the whole map reads as one lit scene.
      canvas.drawRRect(RRect.fromRectAndRadius(r.translate(8, 11), radius),
          _fill..color = const Color(0x66000000));
      final body = Rect.fromLTRB(r.left, r.top - h, r.right, r.bottom);
      canvas.drawRRect(
          RRect.fromRectAndRadius(body, radius), _fill..color = sideColor);
      // vertical shading on the extruded face
      canvas.drawRect(
          Rect.fromLTRB(r.left, r.bottom - h * 0.5, r.right, r.bottom),
          _fill..color = const Color(0x33000000));
      final top = r.translate(0, -h);
      canvas.drawRRect(
          RRect.fromRectAndRadius(top, radius), _fill..color = topColor);
      // lit north edge + shaded south edge
      canvas.drawRect(Rect.fromLTWH(top.left + 2, top.top + 2, top.width - 4, 3),
          _fill..color = const Color(0x4DFFFFFF));
      canvas.drawRect(
          Rect.fromLTWH(top.left + 2, top.bottom - 5, top.width - 4, 3),
          _fill..color = const Color(0x33000000));

      if (wall && theme == 'URBAN') {
        // rooftop plant: AC vents + lit windows, so a block reads as a building
        _fill.color = const Color(0x44000000);
        for (var wx = top.left + 7; wx < top.right - 12; wx += 26) {
          canvas.drawRect(Rect.fromLTWH(wx, top.top + 7, 11, 7), _fill);
        }
        _fill.color = const Color(0x66FFE9A8);
        for (var wx = top.left + 8; wx < top.right - 8; wx += 14) {
          for (var wy = top.top + 18; wy < top.bottom - 7; wy += 14) {
            if (_hash(wx.round(), wy.round()) < 0.4) continue; // dark flats
            canvas.drawRect(Rect.fromLTWH(wx, wy, 5, 5), _fill);
          }
        }
      } else if (wall) {
        // concrete / timber panel seams
        _stroke
          ..color = const Color(0x33000000)
          ..strokeWidth = 1.6;
        for (var wx = top.left + 18; wx < top.right - 6; wx += 24) {
          canvas.drawLine(
              Offset(wx, top.top + 3), Offset(wx, top.bottom - 3), _stroke);
        }
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(top.deflate(3), const Radius.circular(3)),
            _stroke
              ..color = const Color(0x55FFCF9E)
              ..strokeWidth = 2);
        _stroke
          ..color = const Color(0x44000000)
          ..strokeWidth = 1.4;
        canvas.drawLine(Offset(top.left + 3, top.center.dy),
            Offset(top.right - 3, top.center.dy), _stroke);
      }
      canvas.drawRRect(
          RRect.fromRectAndRadius(top, radius),
          _stroke
            ..color = const Color(0x55000000)
            ..strokeWidth = 1.5);
    }
  }

  /// Pickup flourishes, drawn above the world.
  void _drawPickupFx(Canvas canvas) {
    for (final f in _pickupFx) {
      final t = (f.t / f.life).clamp(0.0, 1.0);
      final lift = _easeOut(t) * (f.big ? 34 : 24);
      final a = (1 - t);
      final o = Offset(f.pos.x, f.pos.y - lift);
      // expanding halo
      canvas.drawCircle(o, (f.big ? 26 : 18) * (0.4 + t),
          _stroke..color = f.color.withValues(alpha: 0.5 * a)..strokeWidth = 2);
      // the item itself, spinning as it rises
      canvas.save();
      canvas.translate(o.dx, o.dy);
      canvas.rotate(t * (f.big ? 2.4 : 1.4));
      canvas.scale(1 + t * 0.5);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: 14, height: 10),
              const Radius.circular(3)),
          _fill..color = f.color.withValues(alpha: a));
      canvas.restore();
      // label
      f.label ??= _makeLabel(f.text, f.color);
      final lp = f.label!;
      canvas.saveLayer(
          Rect.fromCenter(
              center: o.translate(0, -18), width: 160, height: 40),
          Paint()..color = Color.fromRGBO(255, 255, 255, a));
      lp.paint(canvas, Offset(o.dx - lp.width / 2, o.dy - 26));
      canvas.restore();
    }
  }

  tp.TextPainter _makeLabel(String text, Color color) => tp.TextPainter(
        text: tp.TextSpan(
          text: text,
          style: tp.TextStyle(
            fontFamily: 'Display',
            fontSize: 15,
            color: color,
            letterSpacing: 1,
            shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

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
      } else if (l.kind == LootKind.vest) {
        // body armour: plate carrier with shoulder straps
        canvas.drawCircle(c, 15,
            _fill..color = const Color(0xFF4FA3FF).withValues(alpha: 0.2 * pulse));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: c, width: 19, height: 22),
                const Radius.circular(5)),
            _fill..color = const Color(0xFF2E4460));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: c, width: 19, height: 22),
                const Radius.circular(5)),
            _stroke..color = const Color(0xFF7FC4FF)..strokeWidth = 1.6);
        canvas.drawRect(Rect.fromCenter(center: c, width: 7, height: 16),
            _fill..color = const Color(0xFF4B6C93));
      } else if (l.kind == LootKind.helmet) {
        canvas.drawCircle(c, 15,
            _fill..color = const Color(0xFFFFC24B).withValues(alpha: 0.2 * pulse));
        canvas.drawArc(
            Rect.fromCenter(center: c.translate(0, 2), width: 22, height: 22),
            math.pi,
            math.pi,
            true,
            _fill..color = const Color(0xFF5A6250));
        canvas.drawArc(
            Rect.fromCenter(center: c.translate(0, 2), width: 22, height: 22),
            math.pi,
            math.pi,
            false,
            _stroke..color = const Color(0xFFC9D6A8)..strokeWidth = 1.8);
        canvas.drawRect(Rect.fromCenter(center: c.translate(0, 3), width: 22, height: 3),
            _fill..color = const Color(0xFF39402F));
      } else if (l.kind == LootKind.wall) {
        // shield-wall charge: a folded slab of energy
        canvas.drawCircle(c, 15,
            _fill..color = const Color(0xFF7FE8FF).withValues(alpha: 0.2 * pulse));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: c, width: 24, height: 15),
                const Radius.circular(3)),
            _fill..color = const Color(0x667FE8FF));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: c, width: 24, height: 15),
                const Radius.circular(3)),
            _stroke..color = const Color(0xFFBFF4FF)..strokeWidth = 1.6);
        _stroke.strokeWidth = 1.2;
        canvas.drawLine(c.translate(-4, -7), c.translate(-4, 7), _stroke);
        canvas.drawLine(c.translate(4, -7), c.translate(4, 7), _stroke);
      } else {
        final wc = kWeapons[l.weapon]!.color;
        if (l.airdrop) {
          // supply crate: a lit pad + a stencilled box you can spot from range
          final beat = 0.5 + 0.5 * math.sin(_time * 4);
          canvas.drawCircle(c, 34,
              _fill..color = kAccent.withValues(alpha: 0.10 + 0.10 * beat));
          canvas.drawCircle(c, 24 + 4 * beat,
              _stroke..color = kAccent.withValues(alpha: 0.7)..strokeWidth = 2);
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: c, width: 34, height: 28),
                  const Radius.circular(4)),
              _fill..color = const Color(0xFF2A2F1E));
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: c, width: 34, height: 28),
                  const Radius.circular(4)),
              _stroke..color = kAccent..strokeWidth = 2);
          canvas.drawRect(Rect.fromCenter(center: c, width: 34, height: 5),
              _fill..color = kAccent.withValues(alpha: 0.85));
        } else {
          canvas.drawCircle(
              c, 15, _fill..color = wc.withValues(alpha: 0.22 * pulse));
        }
        // the actual gun, so you know what you're standing on
        drawGunIcon(canvas, c.translate(0, l.airdrop ? 1 : 0),
            l.airdrop ? 26 : 26, l.weapon!,
            fill: _fill, stroke: _stroke);
        if (!l.airdrop) {
          canvas.drawRect(Rect.fromCenter(center: c.translate(0, 9), width: 22, height: 2),
              _fill..color = wc.withValues(alpha: 0.75));
        }
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
      if (_q.bloom > 0) {
        // a lit tracer: the round leaves a streak of light, not just a line
        canvas.drawLine(
            a,
            bb,
            Paint()
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
              ..color = b.color.withValues(alpha: 0.5 * _q.bloom)
              ..strokeWidth = 8 * b.tracer * _q.bloom
              ..strokeCap = StrokeCap.round);
      }
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

      // Grounded shadow that reacts to what the operator is doing.
      //
      // The light on this map comes from up-left and does not move, so the
      // shadow always falls down-right — that part is fixed, and changing it
      // would look wrong. What DOES change is its shape: a body in motion
      // leans, so the shadow stretches along the direction of travel and
      // trails slightly behind, and it turns with the operator when they turn
      // on the spot. Standing still, it settles back to a round pool.
      final vel = c.vel;
      final speed = vel.length;
      final run = (speed / kPlayerSpeed).clamp(0.0, 1.0);
      // face the shadow along movement when moving, along aim when standing
      final shadowAngle = speed > 6 ? angleOf(vel) : c.aim;
      // trails behind the direction of travel
      final trail = Offset(-math.cos(shadowAngle), -math.sin(shadowAngle)) *
          (r * 0.16 * run);

      void groundShadow(double w, double h, double dx, double dy, int argb) {
        canvas.save();
        canvas.translate(pos.dx + dx + trail.dx, pos.dy + dy + trail.dy);
        canvas.rotate(shadowAngle);
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset.zero,
                // stretched along travel, pinched across it
                width: w * (1 + 0.42 * run),
                height: h * (1 - 0.16 * run)),
            _fill..color = Color(argb));
        canvas.restore();
      }

      if (_q.shadows) {
        groundShadow(r * 2.25, r * 0.95, 6, r * 0.7, 0x4D000000);
        groundShadow(r * 1.5, r * 0.6, 3, r * 0.5, 0x3D000000);
      } else {
        // SMOOTH still needs the figure to sit on the ground, just without a
        // second pass — one flat ellipse instead of a layered soft shadow.
        groundShadow(r * 1.7, r * 0.7, 2, r * 0.6, 0x33000000);
      }

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
          fill: _fill,
          stroke: _stroke,
          walk: walk,
          hero: c.hero,
          vest: c.vest > 0,
          helmet: c.helmet > 0,
          armourFlash: (c.armourFlash / 0.12).clamp(0.0, 1.0));

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
        // A proper flash: a hot star at the muzzle plus a short cone of light
        // thrown forward, instead of a flat white dot.
        final k = (c.muzzle / 0.06).clamp(0.0, 1.0);
        final tip = c.pos + fromAngle(c.aim) * (r * 2.15);
        final o = Offset(tip.x, tip.y);
        // ULTRA throws real light off the barrel; SMOOTH skips the blur pass
        if (_q.bloom > 0) {
          canvas.drawCircle(
              o,
              26 * k * _q.bloom,
              _glow
                ..color =
                    const Color(0xFFFFB02E).withValues(alpha: 0.45 * k * _q.bloom));
        }
        canvas.drawCircle(o, 20 * k,
            _fill..color = const Color(0xFFFFC24B).withValues(alpha: 0.22 * k));
        final cone = Path()
          ..moveTo(o.dx, o.dy)
          ..lineTo(o.dx + math.cos(c.aim + 0.42) * 34 * k,
              o.dy + math.sin(c.aim + 0.42) * 34 * k)
          ..lineTo(o.dx + math.cos(c.aim) * 46 * k,
              o.dy + math.sin(c.aim) * 46 * k)
          ..lineTo(o.dx + math.cos(c.aim - 0.42) * 34 * k,
              o.dy + math.sin(c.aim - 0.42) * 34 * k)
          ..close();
        canvas.drawPath(cone,
            _fill..color = const Color(0xFFFFE9A8).withValues(alpha: 0.5 * k));
        canvas.drawCircle(o, 7 * k,
            _fill..color = const Color(0xFFFFFDF0).withValues(alpha: 0.95 * k));
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
      if (!_vis(p.pos.x, p.pos.y, 24)) continue;
      final a = (p.life / p.maxLife).clamp(0.0, 1.0);
      final o = Offset(p.pos.x, p.pos.y);
      if (p.glow) {
        // soft bloom under the spark so embers actually look hot
        canvas.drawCircle(o, p.size * a * 2.6,
            _fill..color = p.color.withValues(alpha: a * 0.22));
      }
      canvas.drawCircle(
          o, p.size * a, _fill..color = p.color.withValues(alpha: a));
    }
    // expanding blast rings
    for (final s in _shocks) {
      if (!_vis(s.pos.x, s.pos.y, s.maxR)) continue;
      final t = (s.t / s.life).clamp(0.0, 1.0);
      final r = s.maxR * _easeOut(t);
      canvas.drawCircle(
          Offset(s.pos.x, s.pos.y),
          r,
          _stroke
            ..color = const Color(0xFFFFD9A0).withValues(alpha: (1 - t) * 0.75)
            ..strokeWidth = 7 * (1 - t) + 1);
    }
  }

  void _drawGas(Canvas canvas) {
    final vr = _viewRect;
    final center = Offset(zoneCenter.x, zoneCenter.y);

    // Tint everything outside the safe circle. This used to be a saveLayer +
    // BlendMode.clear — an offscreen render target every single frame, which
    // is one of the most expensive things you can ask a mobile GPU for and was
    // a real source of stutter. An even-odd path does the same job for free.
    _gasPath
      ..reset()
      ..addRect(vr.inflate(60))
      ..addOval(Rect.fromCircle(center: center, radius: zoneRadius))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(_gasPath, _gasFillPaint);

    // Boiling gas right at the wall: a few drifting blobs so the barrier reads
    // as moving vapour rather than a flat purple filter.
    final drift = _time * 0.35;
    for (var i = 0; i < 22; i++) {
      final a = i * (kTau / 22) + drift * (i.isEven ? 1 : -1);
      final rr = zoneRadius + 26 + math.sin(_time * 1.7 + i) * 18;
      final p = Offset(center.dx + math.cos(a) * rr, center.dy + math.sin(a) * rr);
      if (!_vis(p.dx, p.dy, 90)) continue;
      canvas.drawCircle(p, 46 + math.sin(_time * 2 + i * 1.3) * 12,
          _fill..color = kGasEdge.withValues(alpha: 0.10));
    }

    // safe edge: a soft translucent ring + a crisp line (no blur)
    canvas.drawCircle(center, zoneRadius,
        _stroke..color = kSafeEdge.withValues(alpha: 0.3)..strokeWidth = 8);
    canvas.drawCircle(center, zoneRadius,
        _stroke..color = kSafeEdge..strokeWidth = 2.5);
    // pulsing inner lip so the boundary is unmistakable while it closes
    if (zoneShrinking) {
      final pulse = 0.5 + 0.5 * math.sin(_time * 4);
      canvas.drawCircle(
          center,
          zoneRadius - 6,
          _stroke
            ..color = kGasEdge.withValues(alpha: 0.25 + 0.35 * pulse)
            ..strokeWidth = 3);
    }

    final phase = kZonePhases[zonePhase.clamp(0, kZonePhases.length - 1)];
    final targetC =
        zoneShrinking ? Offset(_zoneTargetC.x, _zoneTargetC.y) : center;
    final targetR = zoneShrinking ? _zoneTargetR : zoneRadius * phase.factor;
    canvas.drawCircle(targetC, targetR,
        _stroke..color = const Color(0x88FFFFFF)..strokeWidth = 2);
  }
}

/// Quadratic ease-out — blast rings shoot out fast then settle.
double _easeOut(double t) => 1 - (1 - t) * (1 - t);

/// A pickup flourish: the collected item rising, spinning and fading.
class _PickupFx {
  final Vector2 pos;
  final Color color;
  final String text;
  final double life;
  final bool big;
  double t = 0;
  tp.TextPainter? label;
  _PickupFx(this.pos, this.color, this.text, this.life, this.big);
}

/// A permanent mark painted onto the ground (blood, scorch, bullet scar).
class _Decal {
  final Vector2 pos;
  final double rx, ry, rot;
  final Color color;
  _Decal(this.pos, this.rx, this.ry, this.rot, this.color);
}

/// An expanding blast ring.
class _Shock {
  final Vector2 pos;
  double t = 0;
  final double life;
  final double maxR;
  _Shock(this.pos, this.maxR, this.life);
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
/// One elimination in the kill feed. Held as plain data so the HUD can draw
/// it with the same widget the online arena uses, instead of each mode
/// painting its own text.
class KillFeedLine {
  final String killer;
  final String victim;
  final bool mine;
  double life;
  KillFeedLine(this.killer, this.victim, this.mine, this.life);
}
