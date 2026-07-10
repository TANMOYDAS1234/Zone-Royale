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

  // ---- on-screen controller ----
  double stickScale = 1.0; // 0.8 .. 1.35
  double stickOpacity = 1.0; // 0.5 .. 1.4
  bool leftHanded = false; // swap move/aim sides

  // Drag-customizable HUD layout: control key -> [xFrac, yFrac] centre on screen.
  // Empty => use the default. Keys: move, aim, nade, skill, reload, fire.
  final Map<String, List<double>> hudPos = {};
  static const Map<String, List<double>> kDefaultHud = {
    'move': [0.14, 0.82],
    'aim': [0.86, 0.82],
    'skill': [0.90, 0.55],
    'nade': [0.74, 0.68],
    'reload': [0.58, 0.87],
    'fire': [0.44, 0.87],
    'hp': [0.30, 0.62],
  };
  List<double> hudPosOf(String k) =>
      hudPos[k] ?? kDefaultHud[k] ?? const [0.5, 0.5];
  void setHudPos(String k, double x, double y) =>
      hudPos[k] = [x.clamp(0.05, 0.95), y.clamp(0.10, 0.92)];
  void resetHud() => hudPos.clear();

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
      fireAuto = p.getBool('fireAuto') ?? true;
      matchMode = p.getInt('matchMode') ?? 0;
      hero = p.getInt('hero') ?? 0;
      mapChoice = p.getInt('mapChoice') ?? 0;
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
      await p.setBool('fireAuto', fireAuto);
      await p.setInt('matchMode', matchMode);
      await p.setInt('hero', hero);
      await p.setInt('mapChoice', mapChoice);
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
    } catch (_) {
      // Ignore write failures — stats are best-effort.
    }
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
