import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// Player profile: appearance, loadout, fire preference, and lifetime stats.
/// A single shared instance persisted to the device via shared_preferences.
class Profile {
  static final Profile instance = Profile._();
  Profile._();

  // ---- identity / appearance ----
  String name = 'You';
  int outfit = 0; // index into kOutfitColors
  int skin = 0; // index into kSkinTones
  int accessory = 0; // index into kAccessoryNames

  // ---- loadout / combat ----
  WeaponId startWeapon = WeaponId.smg; // SMG by default
  bool fireAuto = true; // prefer auto fire when the weapon supports it
  int matchMode = 0; // index into kMatchModes
  int hero = 0; // index into kHeroes
  int mapChoice = 0; // 0 = random each match; otherwise kMapThemes[mapChoice - 1]
  int difficulty = 1; // index into kDifficulties (1 = NORMAL)

  /// When ON, walking over a gun with both slots full swaps it in like the old
  /// build did. OFF (the default) means loot NEVER takes the gun out of your
  /// hands — you tap PICK UP if you want it. This is the fix for "I crossed a
  /// shotgun and lost my machine gun mid-fight".
  bool autoSwapWeapons = false;

  // ---- display ----
  /// 0 = LANDSCAPE (default — the game is built for it), 1 = PORTRAIT, 2 = AUTO.
  int orientation = 0;
  /// Screen-shake strength, 0 (off) .. 1 (full). Default is deliberately mild:
  /// enough punch to feel the gun, not enough to throw your aim off.
  double shake = 0.5;
  /// Index into kQualities. Scales scenery detail, particle counts and how
  /// many permanent marks stay on the ground — the dial to turn if the game
  /// ever feels like it is stuttering on your phone.
  int quality = 1;
  /// Index into L.codes — 0 English, 1 Bengali, 2 Hindi.
  int language = 0;
  /// False until the guided tour has run (or been skipped, or arrived with a
  /// restored profile — a returning player should never be taught again).
  bool tutorialDone = false;
  /// True once the first-run language picker has been answered.
  bool languagePicked = false;
  /// Menu/background music level, 0 = off.
  double musicVolume = 0.5;
  /// Everything else — gunfire, UI clicks, explosions.
  double sfxVolume = 0.9;

  // ---- on-screen controller ----
  double stickScale = 1.0; // 0.8 .. 1.35
  double stickOpacity = 1.0; // 0.5 .. 1.4
  bool leftHanded = false; // swap move/aim sides

  // Drag-customizable HUD layout: control key -> [xFrac, yFrac] centre on screen.
  // Empty => use the default. Keys: move, aim, nade, skill, swap, pick, reload,
  // fire, hp.
  //
  // Portrait and landscape get SEPARATE layouts — a thumb reaches very
  // different places when the phone is sideways, so one shared layout would
  // put the sticks in the wrong spot in one of the two. Landscape entries are
  // stored under "<key>@l"; [hudLandscape] selects which set is live.
  final Map<String, List<double>> hudPos = {};
  bool hudLandscape = false;

  static const Map<String, List<double>> kDefaultHud = {
    'move': [0.14, 0.82],
    'aim': [0.86, 0.82],
    'skill': [0.90, 0.55],
    'nade': [0.74, 0.68],
    'swap': [0.28, 0.74],
    'wall': [0.74, 0.54],
    'pick': [0.50, 0.66],
    'reload': [0.58, 0.87],
    'fire': [0.44, 0.87],
    'hp': [0.30, 0.62],
  };

  /// Sideways layout: sticks hug the bottom corners, actions stack up the right
  /// edge within thumb reach, readouts sit low-left where nothing is happening.
  static const Map<String, List<double>> kDefaultHudLandscape = {
    'move': [0.11, 0.74],
    'aim': [0.89, 0.74],
    // sideways screens are short: the minimap owns the top-right corner, the
    // sticks own the bottom, so the action buttons sit in the band between
    'skill': [0.94, 0.47],
    'nade': [0.83, 0.45],
    'swap': [0.66, 0.87],
    'wall': [0.70, 0.45],
    'pick': [0.50, 0.62],
    'reload': [0.52, 0.88],
    'fire': [0.38, 0.88],
    'hp': [0.13, 0.40],
  };

  static Map<String, List<double>> defaultHudFor(bool landscape) =>
      landscape ? kDefaultHudLandscape : kDefaultHud;

  /// Storage key for [k] in the layout currently on screen.
  String _hk(String k) => hudLandscape ? '$k@l' : k;

  List<double> hudPosOf(String k) =>
      hudPos[_hk(k)] ??
      defaultHudFor(hudLandscape)[k] ??
      kDefaultHud[k] ??
      const [0.5, 0.5];

  void setHudPos(String k, double x, double y) =>
      hudPos[_hk(k)] = [x.clamp(0.05, 0.95), y.clamp(0.08, 0.93)];

  /// Wipes only the layout for the orientation being edited.
  void resetHudPositions() =>
      hudPos.removeWhere((k, _) => k.endsWith('@l') == hudLandscape);

  // Per-control size + opacity (BGMI-style). 1.0 = default size / fully opaque.
  //
  // The range is per control, not global, because the limits differ:
  //  · floor  — Android's minimum touch target is 48dp, so a 64px button can
  //             only shrink to ~0.75 before it stops being reliably tappable.
  //             The 132px sticks can go much smaller. The HP bar isn't
  //             interactive at all, so it can shrink freely.
  //  · ceiling — two 132px sticks + padding already fill a 360dp-wide screen,
  //             so sticks cap ~1.15; the small buttons have room to grow more.
  static const Map<String, List<double>> kScaleRange = {
    'move': [0.60, 1.15],
    'aim': [0.60, 1.15],
    'skill': [0.75, 1.40],
    'nade': [0.80, 1.40],
    'swap': [0.75, 1.40],
    'wall': [0.80, 1.40],
    'pick': [0.75, 1.40],
    'reload': [0.75, 1.40],
    'fire': [0.75, 1.40],
    'hp': [0.50, 1.50],
  };
  static const List<double> kDefaultScaleRange = [0.70, 1.25];
  static const double kMinOpacity = 0.35, kMaxOpacity = 1.0;
  final Map<String, double> hudScale = {};
  final Map<String, double> hudOpacity = {};

  static List<double> scaleRangeOf(String k) =>
      kScaleRange[k] ?? kDefaultScaleRange;

  double hudScaleOf(String k) {
    final r = scaleRangeOf(k);
    return (hudScale[k] ?? 1.0).clamp(r[0], r[1]);
  }
  double hudOpacityOf(String k) =>
      (hudOpacity[k] ?? 1.0).clamp(kMinOpacity, kMaxOpacity);
  void setHudScale(String k, double v) {
    final r = scaleRangeOf(k);
    hudScale[k] = v.clamp(r[0], r[1]);
  }
  void setHudOpacity(String k, double v) =>
      hudOpacity[k] = v.clamp(kMinOpacity, kMaxOpacity);

  void resetHud() {
    hudPos.clear();
    hudScale.clear();
    hudOpacity.clear();
  }

  // ---- lifetime stats ----
  int matches = 0;
  int wins = 0;
  int kills = 0;
  int bestPlacement = 0; // 0 = none yet; 1 = best possible

  // ---- progression ----
  int level = 1;
  int xp = 0; // XP earned into the current level
  int coins = 0;

  // ---- daily missions ----
  List<Mission> missions = [];
  int missionDay = 0;

  // ---- daily login streak (a reason to come back tomorrow) ----
  int streak = 0; // consecutive days played
  int streakDay = 0; // day index the streak was last advanced
  int streakClaimedDay = -1; // day index the bonus was last collected

  /// Coins for today's login. Grows with the streak and caps at day 7 so it
  /// stays a habit, not a payday.
  int get streakReward => 40 + 30 * (streak.clamp(1, 7) - 1);
  bool get streakReady => streakClaimedDay != _today;

  /// Advances (or resets) the streak for today. Call on app start.
  void touchStreak() {
    final t = _today;
    if (streakDay == t) return;
    streak = (streakDay == t - 1) ? streak + 1 : 1;
    streakDay = t;
    save();
  }

  /// Collect today's login bonus. Returns null if already claimed.
  MatchRewards? claimStreak() {
    if (!streakReady) return null;
    streakClaimedDay = _today;
    final c = streakReward;
    coins += c;
    save();
    return MatchRewards(xp: 0, coins: c, levels: 0);
  }

  // ---- shop / ownership ----
  // Item ids: 'o<i>' outfit colour, 'a<i>' accessory, 'w<index>' start weapon.
  final Set<String> owned = {};

  static bool isFree(String id) {
    if (id.isEmpty) return true;
    final n = int.tryParse(id.substring(1)) ?? 0;
    switch (id[0]) {
      case 'o':
        return n < 6; // first 6 outfit colours free
      case 'a':
        return n < 4; // None, Cap, Beanie, Headband free
      case 'w':
        final w = WeaponId.values[n];
        return w == WeaponId.pistol ||
            w == WeaponId.smg ||
            w == WeaponId.shotgun;
      case 'h':
        return n == 0; // first hero free
      case 'e':
        return false; // hero evolutions always premium
    }
    return true;
  }

  int costOf(String id) {
    if (id.isEmpty) return 0;
    final n = int.tryParse(id.substring(1)) ?? 0;
    switch (id[0]) {
      case 'o':
        return 300;
      case 'a':
        return 250;
      case 'w':
        return 450;
      case 'h':
        return kHeroes[n % kHeroes.length].cost;
      case 'e':
        return kEvoCost.round();
    }
    return 0;
  }

  bool heroOwned(int i) => owns('h$i');
  bool heroEvolved(int i) => owned.contains('e$i');

  bool owns(String id) => isFree(id) || owned.contains(id);

  bool buy(String id) {
    if (owns(id)) return true;
    final c = costOf(id);
    if (coins < c) return false;
    coins -= c;
    owned.add(id);
    save();
    return true;
  }

  SharedPreferences? _prefs;

  Quality get gfx => kQualities[quality.clamp(0, kQualities.length - 1)];

  Difficulty get diff =>
      kDifficulties[difficulty.clamp(0, kDifficulties.length - 1)];

  Color get outfitColor => Color(kOutfitColors[outfit % kOutfitColors.length]);
  Color get skinColor => Color(kSkinTones[skin % kSkinTones.length]);
  String get accessoryName => kAccessoryNames[accessory % kAccessoryNames.length];
  double get winRate => matches == 0 ? 0 : wins / matches;

  int get xpForNext => 80 + level * 30;
  double get xpFraction => (xp / xpForNext).clamp(0.0, 1.0);

  String get rank {
    final l = level;
    if (l < 3) return 'RECRUIT';
    if (l < 6) return 'BRONZE';
    if (l < 10) return 'SILVER';
    if (l < 15) return 'GOLD';
    if (l < 22) return 'PLATINUM';
    if (l < 30) return 'DIAMOND';
    if (l < 45) return 'MASTER';
    return 'LEGEND';
  }

  Color get rankColor {
    final l = level;
    if (l < 3) return const Color(0xFF9AA6B2);
    if (l < 6) return const Color(0xFFC77B3A);
    if (l < 10) return const Color(0xFFCBD3DA);
    if (l < 15) return const Color(0xFFFFC24B);
    if (l < 22) return const Color(0xFF6FE0D0);
    if (l < 30) return const Color(0xFF6AB8FF);
    if (l < 45) return const Color(0xFFC58BFF);
    return const Color(0xFFFF5A5F);
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = p;
      name = p.getString('name') ?? 'You';
      outfit = p.getInt('outfit') ?? 0;
      skin = p.getInt('skin') ?? 0;
      accessory = p.getInt('accessory') ?? 0;
      final w = p.getInt('startWeapon');
      if (w != null && w >= 0 && w < WeaponId.values.length) {
        startWeapon = WeaponId.values[w];
      }
      // one-time migration: the old default was Pistol — bump profiles that
      // never explicitly changed it up to SMG (the new default).
      if ((p.getInt('wver') ?? 0) < 1) startWeapon = WeaponId.smg;
      fireAuto = p.getBool('fireAuto') ?? true;
      matchMode = p.getInt('matchMode') ?? 0;
      hero = p.getInt('hero') ?? 0;
      mapChoice = p.getInt('mapChoice') ?? 0;
      difficulty = (p.getInt('difficulty') ?? 1).clamp(0, kDifficulties.length - 1);
      autoSwapWeapons = p.getBool('autoSwap') ?? false;
      orientation = (p.getInt('orientation') ?? 0).clamp(0, 2);
      shake = (p.getDouble('shake') ?? 0.5).clamp(0.0, 1.0);
      quality = (p.getInt('quality') ?? 1).clamp(0, kQualities.length - 1);
      language = (p.getInt('language') ?? 0).clamp(0, 2);
      tutorialDone = p.getBool('tutorialDone') ?? false;
      languagePicked = p.getBool('languagePicked') ?? false;
      musicVolume = (p.getDouble('musicVol') ?? 0.5).clamp(0.0, 1.0);
      sfxVolume = (p.getDouble('sfxVol') ?? 0.9).clamp(0.0, 1.0);
      streak = p.getInt('streak') ?? 0;
      streakDay = p.getInt('streakDay') ?? 0;
      streakClaimedDay = p.getInt('streakClaimed') ?? -1;
      stickScale = p.getDouble('stickScale') ?? 1.0;
      stickOpacity = p.getDouble('stickOpacity') ?? 1.0;
      leftHanded = p.getBool('leftHanded') ?? false;
      matches = p.getInt('matches') ?? 0;
      wins = p.getInt('wins') ?? 0;
      kills = p.getInt('kills') ?? 0;
      bestPlacement = p.getInt('best') ?? 0;
      level = p.getInt('level') ?? 1;
      xp = p.getInt('xp') ?? 0;
      coins = p.getInt('coins') ?? 0;
      final ml = p.getStringList('missions');
      if (ml != null) {
        missions = ml.map(Mission.decode).whereType<Mission>().toList();
      }
      missionDay = p.getInt('missionDay') ?? 0;
      final ow = p.getStringList('owned');
      if (ow != null) {
        owned
          ..clear()
          ..addAll(ow);
      }
      final hp = p.getStringList('hudPos');
      if (hp != null) {
        hudPos.clear();
        for (final e in hp) {
          final parts = e.split(':');
          if (parts.length != 3) continue;
          final x = double.tryParse(parts[1]);
          final y = double.tryParse(parts[2]);
          if (x != null && y != null) hudPos[parts[0]] = [x, y];
        }
      }
      void readMap(String key, Map<String, double> into) {
        final list = p.getStringList(key);
        if (list == null) return;
        into.clear();
        for (final e in list) {
          final i = e.lastIndexOf(':');
          if (i <= 0) continue;
          final v = double.tryParse(e.substring(i + 1));
          if (v != null) into[e.substring(0, i)] = v;
        }
      }

      readMap('hudScale', hudScale);
      readMap('hudOpacity', hudOpacity);
      // migrate the old global stick sliders into the per-control model
      if (hudScale.isEmpty && stickScale != 1.0) {
        hudScale['move'] = stickScale;
        hudScale['aim'] = stickScale;
      }
      if (hudOpacity.isEmpty && stickOpacity != 1.0) {
        hudOpacity['move'] = stickOpacity;
        hudOpacity['aim'] = stickOpacity;
      }
    } catch (_) {
      // First run or storage unavailable — defaults are fine.
    }
    ensureMissions();
  }

  Future<void> save() async {
    final p = _prefs;
    if (p == null) return;
    try {
      await p.setString('name', name);
      await p.setInt('outfit', outfit);
      await p.setInt('skin', skin);
      await p.setInt('accessory', accessory);
      await p.setInt('startWeapon', startWeapon.index);
      await p.setInt('wver', 1); // SMG-default migration applied
      await p.setBool('fireAuto', fireAuto);
      await p.setInt('matchMode', matchMode);
      await p.setInt('hero', hero);
      await p.setInt('mapChoice', mapChoice);
      await p.setInt('difficulty', difficulty);
      await p.setBool('autoSwap', autoSwapWeapons);
      await p.setInt('orientation', orientation);
      await p.setDouble('shake', shake);
      await p.setInt('quality', quality);
      await p.setInt('language', language);
      await p.setBool('tutorialDone', tutorialDone);
      await p.setBool('languagePicked', languagePicked);
      await p.setDouble('musicVol', musicVolume);
      await p.setDouble('sfxVol', sfxVolume);
      await p.setInt('streak', streak);
      await p.setInt('streakDay', streakDay);
      await p.setInt('streakClaimed', streakClaimedDay);
      await p.setDouble('stickScale', stickScale);
      await p.setDouble('stickOpacity', stickOpacity);
      await p.setBool('leftHanded', leftHanded);
      await p.setInt('matches', matches);
      await p.setInt('wins', wins);
      await p.setInt('kills', kills);
      await p.setInt('best', bestPlacement);
      await p.setInt('level', level);
      await p.setInt('xp', xp);
      await p.setInt('coins', coins);
      await p.setStringList('missions', missions.map((m) => m.encode()).toList());
      await p.setInt('missionDay', missionDay);
      await p.setStringList('owned', owned.toList());
      await p.setStringList('hudPos',
          hudPos.entries.map((e) => '${e.key}:${e.value[0]}:${e.value[1]}').toList());
      await p.setStringList('hudScale',
          hudScale.entries.map((e) => '${e.key}:${e.value}').toList());
      await p.setStringList('hudOpacity',
          hudOpacity.entries.map((e) => '${e.key}:${e.value}').toList());
    } catch (_) {
      // Ignore write failures — stats are best-effort.
    }
  }

  // ---------------------------------------------------------------- backup
  //
  // Progress lives in SharedPreferences, which Android's Auto Backup copies to
  // the player's Google Drive and restores on a reinstall or a new phone — no
  // account, no server, no cost. See android/app/src/main/res/xml/.
  //
  // Auto Backup only restores on a FRESH install, though, and only if the
  // device has backup switched on. The transfer code below covers everything
  // it can't: copy it, paste it anywhere, get your profile back.

  /// The WHOLE profile — not just the wallet. Coming back on a new phone
  /// should hand you the game exactly as you left it: the same operator, skin,
  /// accessory, hero and starting gun, the same control layout you dragged out
  /// (which both solo and online read), the same graphics fidelity, difficulty,
  /// shake, fire mode and handedness, and the same missions and streak.
  Map<String, dynamic> toBackup() => {
        'v': 2,
        // identity + what you have
        'name': name,
        'level': level,
        'xp': xp,
        'coins': coins,
        'owned': owned.toList(),
        // equipped look and loadout
        'outfit': outfit,
        'skin': skin,
        'accessory': accessory,
        'weapon': startWeapon.index,
        'hero': hero,
        // settings — every one of them, for solo and online alike
        'fireAuto': fireAuto,
        'autoSwap': autoSwapWeapons,
        'leftHanded': leftHanded,
        'quality': quality,
        'difficulty': difficulty,
        'musicVol': musicVolume,
        'sfxVol': sfxVolume,
        'language': language,
        'shake': shake,
        'matchMode': matchMode,
        'mapChoice': mapChoice,
        'orientation': orientation,
        // the control layout, exactly as placed in the editor
        'hudPos': {
          for (final e in hudPos.entries) e.key: [e.value[0], e.value[1]]
        },
        'hudScale': hudScale,
        'hudOpacity': hudOpacity,
        // progression bookkeeping
        'matches': matches,
        'wins': wins,
        'kills': kills,
        'best': bestPlacement,
        'streak': streak,
        'streakDay': streakDay,
        'streakClaimed': streakClaimedDay,
        'missionDay': missionDay,
        'missions': missions.map((m) => m.encode()).toList(),
      };

  void applyBackup(Map<String, dynamic> j) {
    int i(String k, int fallback) {
      final v = j[k];
      return v is int ? v : (v is num ? v.toInt() : fallback);
    }

    double d(String k, double fallback) {
      final v = j[k];
      return v is num ? v.toDouble() : fallback;
    }

    bool b(String k, bool fallback) {
      final v = j[k];
      return v is bool ? v : fallback;
    }

    name = (j['name'] as String?)?.trim().isNotEmpty == true
        ? j['name'] as String
        : name;
    level = i('level', level).clamp(1, 999);
    xp = i('xp', xp).clamp(0, 1 << 30);
    coins = i('coins', coins).clamp(0, 1 << 30);
    final ow = j['owned'];
    if (ow is List) {
      owned
        ..clear()
        ..addAll(ow.whereType<String>());
    }

    outfit = i('outfit', outfit);
    skin = i('skin', skin);
    accessory = i('accessory', accessory);
    final w = i('weapon', startWeapon.index);
    if (w >= 0 && w < WeaponId.values.length) startWeapon = WeaponId.values[w];
    hero = i('hero', hero).clamp(0, kHeroes.length - 1);

    fireAuto = b('fireAuto', fireAuto);
    autoSwapWeapons = b('autoSwap', autoSwapWeapons);
    leftHanded = b('leftHanded', leftHanded);
    quality = i('quality', quality).clamp(0, kQualities.length - 1);
    musicVolume = d('musicVol', musicVolume).clamp(0.0, 1.0);
    language = i('language', language).clamp(0, 2);
    // A restored profile belongs to someone who already knows the game.
    // Teaching them the joystick again would be insulting, so the tour is
    // marked done and the language picker is skipped.
    tutorialDone = true;
    languagePicked = true;
    sfxVolume = d('sfxVol', sfxVolume).clamp(0.0, 1.0);
    difficulty = i('difficulty', difficulty).clamp(0, kDifficulties.length - 1);
    shake = d('shake', shake).clamp(0.0, 1.0);
    matchMode = i('matchMode', matchMode);
    mapChoice = i('mapChoice', mapChoice);
    orientation = i('orientation', orientation).clamp(0, 2);

    final hp = j['hudPos'];
    if (hp is Map) {
      hudPos.clear();
      hp.forEach((k, v) {
        if (k is String && v is List && v.length == 2) {
          final x = v[0], y = v[1];
          if (x is num && y is num) hudPos[k] = [x.toDouble(), y.toDouble()];
        }
      });
    }
    void readMap(String key, Map<String, double> into) {
      final m = j[key];
      if (m is! Map) return;
      into.clear();
      m.forEach((k, v) {
        if (k is String && v is num) into[k] = v.toDouble();
      });
    }

    readMap('hudScale', hudScale);
    readMap('hudOpacity', hudOpacity);

    matches = i('matches', matches);
    wins = i('wins', wins);
    kills = i('kills', kills);
    bestPlacement = i('best', bestPlacement);
    streak = i('streak', streak);
    streakDay = i('streakDay', streakDay);
    streakClaimedDay = i('streakClaimed', streakClaimedDay);
    missionDay = i('missionDay', missionDay);
    final ms = j['missions'];
    if (ms is List) {
      final decoded =
          ms.whereType<String>().map(Mission.decode).whereType<Mission>().toList();
      if (decoded.isNotEmpty) missions = decoded;
    }
  }

  /// A short, copy-pasteable string that carries this profile. Gzipped so it
  /// stays under a couple hundred characters.
  String exportCode() {
    final json = jsonEncode(toBackup());
    try {
      return 'ZR1-${base64Url.encode(gzip.encode(utf8.encode(json)))}';
    } catch (_) {
      // gzip is unavailable on some platforms; plain is still valid
      return 'ZR0-${base64Url.encode(utf8.encode(json))}';
    }
  }

  /// Returns true if the code was understood and applied.
  Future<bool> importCode(String raw) async {
    final code = raw.trim().replaceAll(RegExp(r'\s'), '');
    try {
      final String json;
      if (code.startsWith('ZR1-')) {
        json = utf8.decode(gzip.decode(base64Url.decode(code.substring(4))));
      } else if (code.startsWith('ZR0-')) {
        json = utf8.decode(base64Url.decode(code.substring(4)));
      } else {
        return false;
      }
      final map = jsonDecode(json);
      if (map is! Map<String, dynamic>) return false;
      applyBackup(map);
      await save();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Wipe progress and start over.
  ///
  /// Deliberately NOT offered on launch or after a restore — a "start again?"
  /// prompt in the flow you walk through every day is a trap, and one mistap
  /// costs a player everything. This is reached from settings, behind an
  /// explicit confirmation, and keeps the control layout and screen settings
  /// (nobody wants to re-drag their joysticks to reset a coin balance).
  Future<void> resetProgress() async {
    level = 1;
    xp = 0;
    coins = 0;
    matches = 0;
    wins = 0;
    kills = 0;
    bestPlacement = 0;
    streak = 0;
    streakDay = 0;
    streakClaimedDay = -1;
    owned.clear();
    missions = [];
    missionDay = 0;
    outfit = 0;
    skin = 0;
    accessory = 0;
    hero = 0;
    startWeapon = WeaponId.smg;
    ensureMissions();
    await save();
  }

  MatchRewards recordResult({
    required int placement,
    required int matchKills,
    required bool won,
  }) {
    matches++;
    if (won) wins++;
    kills += matchKills;
    final place = placement <= 0 ? 1 : placement;
    if (bestPlacement == 0 || place < bestPlacement) bestPlacement = place;

    // XP + coin rewards: participation + kills + placement + a win bonus.
    final placeBonus = place <= 10 ? (11 - place) * 12 : 0;
    final xpGain = 40 + matchKills * 15 + (won ? 150 : 0) + placeBonus;
    final coinGain = 12 + matchKills * 6 + (won ? 70 : 0) + placeBonus ~/ 3;
    xp += xpGain;
    coins += coinGain;
    var levelsUp = 0;
    while (xp >= xpForNext) {
      xp -= xpForNext;
      level++;
      levelsUp++;
    }
    save();
    return MatchRewards(xp: xpGain, coins: coinGain, levels: levelsUp);
  }

  // ---- missions ----
  int get _today => DateTime.now().millisecondsSinceEpoch ~/ 86400000;

  void ensureMissions() {
    if (missionDay == _today && missions.isNotEmpty) return;
    missionDay = _today;
    missions = _genMissions(_today);
    save();
  }

  List<Mission> _genMissions(int day) {
    final pool = <Mission>[
      Mission(MissionType.kills, 8, 60, 120),
      Mission(MissionType.kills, 15, 100, 200),
      Mission(MissionType.wins, 1, 120, 240),
      Mission(MissionType.matches, 3, 40, 80),
      Mission(MissionType.top3, 2, 70, 140),
      Mission(MissionType.grenades, 6, 40, 80),
    ];
    final start = day % pool.length;
    return [for (var i = 0; i < 3; i++) pool[(start + i) % pool.length]];
  }

  void updateMissions({
    required int kills,
    required bool won,
    required int placement,
    required int grenades,
  }) {
    ensureMissions();
    for (final m in missions) {
      if (m.claimed) continue;
      switch (m.type) {
        case MissionType.kills:
          m.progress += kills;
          break;
        case MissionType.wins:
          if (won) m.progress += 1;
          break;
        case MissionType.matches:
          m.progress += 1;
          break;
        case MissionType.top3:
          if (placement <= 3) m.progress += 1;
          break;
        case MissionType.grenades:
          m.progress += grenades;
          break;
      }
      if (m.progress > m.target) m.progress = m.target;
    }
    save();
  }

  /// Claim a completed mission's reward. Returns the reward, or null if invalid.
  MatchRewards? claimMission(int i) {
    if (i < 0 || i >= missions.length) return null;
    final m = missions[i];
    if (!m.done || m.claimed) return null;
    m.claimed = true;
    coins += m.rewardCoins;
    xp += m.rewardXp;
    var levelsUp = 0;
    while (xp >= xpForNext) {
      xp -= xpForNext;
      level++;
      levelsUp++;
    }
    save();
    return MatchRewards(xp: m.rewardXp, coins: m.rewardCoins, levels: levelsUp);
  }
}

class MatchRewards {
  final int xp;
  final int coins;
  final int levels; // number of level-ups this match
  const MatchRewards({required this.xp, required this.coins, required this.levels});
}

enum MissionType { kills, wins, matches, top3, grenades }

class Mission {
  final MissionType type;
  final int target;
  final int rewardCoins;
  final int rewardXp;
  int progress;
  bool claimed;

  Mission(this.type, this.target, this.rewardCoins, this.rewardXp,
      {this.progress = 0, this.claimed = false});

  bool get done => progress >= target;

  String get desc {
    switch (type) {
      case MissionType.kills:
        return 'Get $target kills';
      case MissionType.wins:
        return 'Win $target match${target > 1 ? 'es' : ''}';
      case MissionType.matches:
        return 'Play $target matches';
      case MissionType.top3:
        return 'Finish top 3 · ${target}x';
      case MissionType.grenades:
        return 'Throw $target grenades';
    }
  }

  String encode() =>
      '${type.index}|$target|$rewardCoins|$rewardXp|$progress|${claimed ? 1 : 0}';

  static Mission? decode(String s) {
    final a = s.split('|');
    if (a.length < 6) return null;
    final ti = int.tryParse(a[0]);
    final target = int.tryParse(a[1]);
    final coins = int.tryParse(a[2]);
    final xp = int.tryParse(a[3]);
    final prog = int.tryParse(a[4]);
    if (ti == null ||
        ti < 0 ||
        ti >= MissionType.values.length ||
        target == null ||
        coins == null ||
        xp == null ||
        prog == null) {
      return null;
    }
    return Mission(MissionType.values[ti], target, coins, xp,
        progress: prog, claimed: a[5] == '1');
  }
}
