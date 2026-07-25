import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Gradient;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../game/char_art.dart';
import '../game/config.dart';
import '../game/profile.dart';
import '../game/royale_game.dart';
import '../game/sfx.dart';
import '../ui/capture.dart';
import '../ui/game_ui.dart' show menuPad;
import '../ui/hud_controls.dart';
import 'net_client.dart';

/// Full-screen multiplayer flow: a connect form (server address + room code),
/// then the live networked arena once the socket is up. Push this with
/// Navigator.push from the start menu's MULTIPLAYER button.
class MultiplayerScreen extends StatefulWidget {
  final RoyaleGame? game; // lets the bottom nav jump to real app sections
  const MultiplayerScreen({super.key, this.game});

  @override
  State<MultiplayerScreen> createState() => _MultiplayerScreenState();
}

class _MultiplayerScreenState extends State<MultiplayerScreen>
    with WidgetsBindingObserver {
  // Defaults to the live Render server — friends can just tap Connect.
  final _server =
      TextEditingController(text: 'wss://zone-royale.onrender.com');
  late final _room = TextEditingController(text: _randomCode());
  NetClient? _client;
  bool _deployed = false; // false = lobby, true = in the arena
  bool _advanced = false; // reveal the server-address field

  // ---- host-configurable room rules (all dynamic from game data) ----
  int _mapSel = 0; // 0 = RANDOM, else kMapThemes[i-1]
  int _sizeSel = 0; // index into kMatchModes (10 / 25 / 50)
  int _weaponSel = -1; // -1 = ALL_ARMS, else index into kWeaponOrder
  int _bo = 1; // best-of: 1 / 3 / 5
  bool _medkit = true, _grenades = true, _skills = true;
  bool _bots = true; // fill empty slots with bots so a match is always playable
  int _botDiff = 1; // 0 easy · 1 normal · 2 hard (all weaker than a human)

  static String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = math.Random();
    return List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _client?.close();
    _server.dispose();
    _room.dispose();
    super.dispose();
  }

  /// Android suspends the app (and can drop the socket) when the screen turns
  /// off. On resume, silently rejoin the same room instead of dumping the
  /// player back to the menu.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final c = _client;
    if (c != null && (c.status == 'closed' || c.status == 'error')) {
      _connect(keepDeployed: _deployed);
    }
  }

  /// QUICK MATCH: the server drops you into a public room that has a free slot,
  /// opening a new one if they're all full. If you're the one who opens it, YOUR
  /// rules apply (same as a custom room). If you join someone else's room in
  /// progress, you inherit theirs — the lobby always shows the rules in force.
  Future<void> _quickMatch() async => _connect(quick: true);

  String get _mapName =>
      _mapSel == 0 ? 'RANDOM' : kMapThemes[_mapSel - 1].name.toUpperCase();
  String get _weaponName => _weaponSel < 0
      ? 'ALL_ARMS'
      : kWeapons[kWeaponOrder[_weaponSel]]!.name.toUpperCase();

  Map<String, dynamic> _buildConfig() {
    final mode = kMatchModes[_sizeSel];
    // Forced-weapon rooms: everyone starts with (and keeps) that exact gun.
    // ALL_ARMS: you keep your own loadout and loot can add a second.
    final startId = _weaponSel < 0
        ? Profile.instance.startWeapon
        : kWeaponOrder[_weaponSel];
    return {
      'world': mode.world,
      'maxPlayers': mode.players,
      'map': _mapName,
      'weapon': _weaponName,
      'rounds': (_bo / 2).ceil(), // wins needed: BO1=1, BO3=2, BO5=3
      'startWi': startId.index,
      // The FULL weapon table — fire rate, magazine, reload, spread, pellets
      // and auto/semi included — so an online gun behaves exactly like the
      // offline one instead of "one bullet per tap".
      'weapons': weaponNetTable(),
      'medkit': _medkit,
      'grenades': _grenades,
      'skills': _skills,
      // bots fill the empty slots so the room is playable before the game has
      // a real player base; they step aside as friends join
      'bots': _bots,
      'botTarget': mode.players.clamp(2, 12),
      'botDifficulty': _botDiff,
    };
  }

  String _normalizeUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('ws://') && !s.startsWith('wss://')) s = 'ws://$s';
    if (s.startsWith('ws://') && !s.substring(5).contains(':')) s = '$s:8080';
    return s;
  }

  bool _wasQuick = false;

  Future<void> _connect({bool keepDeployed = false, bool quick = false}) async {
    final url = _normalizeUrl(_server.text);
    if (url.isEmpty) return;
    _wasQuick = quick || (keepDeployed && _wasQuick); // survive auto-reconnect
    final name = Profile.instance.name.trim().isEmpty
        ? 'Player'
        : Profile.instance.name.trim();
    final room = _room.text.trim().isEmpty ? 'PUBLIC' : _room.text.trim();
    // Close the old socket AND wait for it — otherwise the server still counts
    // us in the old room, reuses it, and silently ignores our new settings.
    await _client?.close();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final c = NetClient();
    setState(() {
      _client = c;
      if (!keepDeployed) _deployed = false;
    });
    // Your rules travel with you. The server only applies them if you're the
    // first human into the room, so you can never override an in-progress match.
    await c.connect(url, name, room,
        config: _buildConfig(),
        hero: Profile.instance.hero,
        startWi: Profile.instance.startWeapon.index,
        quick: _wasQuick);
  }

  void _startMission() {
    _client?.sendReady(); // server drops us in and starts the match
    setState(() => _deployed = true);
  }

  void _leave() {
    _client?.close();
    setState(() {
      _client = null;
      _deployed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _client;
    return Scaffold(
      backgroundColor: const Color(0xFF05070C),
      // Menus sit inside the safe area; the ARENA does not. Wrapping the arena
      // in a SafeArea shrank the canvas and — because a Stack clips — cut the
      // joysticks and action buttons off at the inset. The arena is full-bleed
      // and insets its own controls instead.
      body: c == null
          ? SafeArea(child: _configView())
          : AnimatedBuilder(
              animation: c.rev,
              builder: (_, _) => c.status != 'live'
                  ? SafeArea(child: _statusView(c))
                  : (_deployed
                      ? _ArenaView(client: c, onLeave: _leave)
                      : SafeArea(child: _lobbyView(c))),
            ),
    );
  }

  Widget _statusView(NetClient c) {
    final busy = c.status == 'connecting' || c.status == 'waking';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const CircularProgressIndicator(color: kSafeEdge)
          else
            const Icon(Icons.wifi_off, color: kAccent2, size: 54),
          const SizedBox(height: 18),
          Text(
            c.status == 'waking'
                ? 'Waking the server…'
                : c.status == 'connecting'
                    ? 'Connecting…'
                    : c.status == 'closed'
                        ? 'Disconnected'
                        : 'Could not connect',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          if (c.status == 'waking') ...[
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Free hosting sleeps when idle — first connect can take up to a '
                'minute. Hang tight…',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
          if (c.error != null && !busy) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(c.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          ],
          const SizedBox(height: 22),
          TextButton(onPressed: _leave, child: const Text('BACK')),
        ],
      ),
    );
  }

  // Dynamic protocol tag from the entered URL — honest status, not decoration.
  String get _protocol {
    final s = _server.text.trim();
    if (s.startsWith('wss://')) return 'WSS_SECURE';
    if (s.startsWith('ws://')) return 'WS_LOCAL';
    return 'AUTO';
  }

  static const _mono = 'monospace';

  // ---- shared chrome ----
  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 14, 6),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: const Icon(Icons.grid_view_rounded, color: kAccent, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('ZONE ROYALE',
                style: TextStyle(
                    color: kAccent,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1)),
            const Spacer(),
            GestureDetector(
              onTap: () {
                _client?.close();
                Navigator.of(context).maybePop();
              },
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.home_rounded,
                    size: 20, color: Colors.white70),
              ),
            ),
          ],
        ),
      );

  Widget _titles(String sub, String main) => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(sub,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: _mono,
                  color: kAccent,
                  fontSize: 13,
                  letterSpacing: 2)),
          const SizedBox(height: 6),
          Text(main,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1)),
        ],
      );

  // ============ SETUP: configure the room ============
  Widget _configView() {
    return Stack(
      children: [
        const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _GridPainter()))),
        Column(
          children: [
            _header(),
            Expanded(
              child: SingleChildScrollView(
                padding: menuPad(context, top: 14, bottom: 18, side: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                        child: _titles(
                            'Active Session Config', 'Custom Room Command')),
                    const SizedBox(height: 22),
                    _configCard(),
                    const SizedBox(height: 16),
                    _roomCodeField(),
                    const SizedBox(height: 12),
                    _advancedServer(),
                    const SizedBox(height: 18),
                    _bigButton(
                        Icons.rocket_launch, 'CREATE / JOIN ROOM', _connect),
                    const SizedBox(height: 10),
                    _ghostButton(Icons.public, 'QUICK MATCH  ·  JOIN PUBLIC',
                        _quickMatch),
                    const SizedBox(height: 10),
                    Center(
                      child: Text('PROTOCOL: $_protocol   ·   HOST SETS THE RULES',
                          style: TextStyle(
                              fontFamily: _mono,
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 10,
                              letterSpacing: 1)),
                    ),
                  ],
                ),
              ),
            ),
            _bottomNav(),
          ],
        ),
      ],
    );
  }

  /// When the settings card is shown inside a pushed route (the host's
  /// CHANGE SETTINGS sheet), taps have to rebuild THAT subtree as well as this
  /// screen — otherwise the chips look frozen even though the value changed.
  StateSetter? _innerSet;
  void _apply(VoidCallback fn) {
    setState(fn);
    _innerSet?.call(() {});
  }

  Widget _configCardLive(StateSetter s) {
    _innerSet = s;
    return _configCard();
  }

  Widget _configCard() {
    final mode = kMatchModes[_sizeSel];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fieldLabel('Map & Sector'),
          _dropField(Icons.map_rounded, _mapName,
              () => _apply(() =>
                  _mapSel = (_mapSel + 1) % (kMapThemes.length + 1))),
          const SizedBox(height: 6),
          _sectionLine('Match Rules'),
          _fieldLabel('Weapon Type'),
          _dropField(Icons.gps_fixed, _weaponName, () {
            _apply(() => _weaponSel = _weaponSel >= kWeaponOrder.length - 1
                ? -1
                : _weaponSel + 1);
          }),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                _weaponSel < 0
                    ? 'ALL_ARMS — everyone brings their own loadout, crates drop guns.'
                    : 'Everyone fights with the $_weaponName only. No weapon crates.',
                style: TextStyle(
                    fontFamily: _mono,
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 10)),
          ),
          const SizedBox(height: 14),
          _fieldLabel('Rounds'),
          _pillGroup(const ['BO1', 'BO3', 'BO5'], const [1, 3, 5], _bo,
              (v) => _apply(() => _bo = v)),
          const SizedBox(height: 14),
          _fieldLabel('Player Limit'),
          _pillGroup([
            for (final m in kMatchModes) '${m.players}'
          ], [
            for (var i = 0; i < kMatchModes.length; i++) i
          ], _sizeSel, (v) => _apply(() => _sizeSel = v)),
          const SizedBox(height: 14),
          _fieldLabel('Bot Difficulty'),
          _pillGroup(const ['Easy', 'Normal', 'Hard'], const [0, 1, 2], _botDiff,
              (v) => _apply(() => _botDiff = v)),
          const SizedBox(height: 6),
          _sectionLine('Equipment Restrictions'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _toggleChip('Medkits', _medkit,
                  () => _apply(() => _medkit = !_medkit)),
              _toggleChip('Grenades', _grenades,
                  () => _apply(() => _grenades = !_grenades)),
              _toggleChip('Hero Skills', _skills,
                  () => _apply(() => _skills = !_skills)),
              _toggleChip('Fill With Bots', _bots,
                  () => _apply(() => _bots = !_bots)),
            ],
          ),
          const SizedBox(height: 6),
          Text('Arena: ${mode.name} · world ${mode.world.round()}u',
              style: TextStyle(
                  fontFamily: _mono,
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 10)),
        ],
      ),
    );
  }

  // ============ LOBBY: connected, waiting to deploy ============
  Widget _lobbyView(NetClient c) {
    return Stack(
      children: [
        const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _GridPainter()))),
        Column(
          children: [
            _header(),
            Expanded(
              child: SingleChildScrollView(
                padding: menuPad(context, top: 10, bottom: 12, side: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                        child: _titles(
                            'Room ${c.roomCode.isEmpty ? _room.text : c.roomCode}',
                            _wasQuick ? 'Quick Match' : 'Briefing Room')),
                    if (c.serverOutdated) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: kAccent2.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kAccent2),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.sync_problem,
                                color: kAccent2, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                  'This server is running an older build. Redeploy '
                                  'the server (push to GitHub → Render rebuilds) '
                                  'to play online with this version.',
                                  style: TextStyle(
                                      fontFamily: _mono,
                                      color: Colors.white
                                          .withValues(alpha: 0.75),
                                      fontSize: 11,
                                      height: 1.4)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    _summaryCard(c),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text('Connected Players',
                            style: TextStyle(
                                fontFamily: _mono,
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 13,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text(
                            '${c.humanCount} / ${c.maxPlayers}'
                            '${c.fillBots ? '  +${c.players.length - c.humanCount} BOTS' : ''}',
                            style: TextStyle(
                                fontFamily: _mono,
                                color: kAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final p in c.players) _rosterTile(c, p),
                    if (c.players.length <= 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                            _wasQuick
                                ? 'Waiting for other players to drop in…'
                                : 'Share room code “${c.roomCode.isEmpty ? _room.text : c.roomCode}” so friends can join.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 11)),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
              child: Column(
                children: [
                  _bigButton(Icons.rocket_launch, 'START MISSION', _startMission),
                  const SizedBox(height: 10),
                  // The host owns the rules, so they can retune the room right
                  // here and have it take effect — no leave-and-rejoin dance.
                  if (c.isHost && !c.started) ...[
                    _ghostButton(Icons.tune, 'CHANGE / APPLY SETTINGS', () {
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                    backgroundColor: const Color(0xFF05070C),
                                    body: SafeArea(
                                      child: Column(
                                        children: [
                                          _header(),
                                          Expanded(
                                            child: SingleChildScrollView(
                                              padding:
                                                  const EdgeInsets.all(18),
                                              child: StatefulBuilder(
                                                builder: (_, setInner) =>
                                                    _configCardLive(setInner),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding:
                                                const EdgeInsets.all(16),
                                            child: _bigButton(Icons.check,
                                                'APPLY TO ROOM', () {
                                              _client
                                                  ?.sendConfig(_buildConfig());
                                              Navigator.of(context).maybePop();
                                            }),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )))
                          .then((_) => setState(() {}));
                    }),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                          child: _ghostButton(
                              Icons.wifi_tethering, 'RECONNECT', _connect)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _ghostButton(
                              Icons.logout, 'LEAVE ROOM', _leave)),
                    ],
                  ),
                ],
              ),
            ),
            _bottomNav(),
          ],
        ),
      ],
    );
  }

  static const _diffNames = ['Easy', 'Normal', 'Hard'];

  String _botsSummary(NetClient c) => c.fillBots
      ? '${_diffNames[c.botDifficulty.clamp(0, 2)]} × ${c.botTarget}'
      : 'Off';

  String _equipSummary(NetClient c) {
    final on = [
      if (c.allowMedkits) 'Medkits',
      if (c.allowGrenades) 'Grenades',
      if (c.allowSkills) 'Skills',
    ];
    return on.isEmpty ? 'None' : on.join(', ');
  }

  Widget _summaryCard(NetClient c) {
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(k,
                  style: TextStyle(
                      fontFamily: _mono,
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                      letterSpacing: 1)),
              Text(v,
                  style: const TextStyle(
                      fontFamily: _mono,
                      color: kAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          row('Map', c.map),
          row('Weapon', c.weapon),
          row('Rounds', 'Best of ${c.rounds * 2 - 1}'),
          row('Player Limit', '${c.maxPlayers}'),
          row('Bots', _botsSummary(c)),
          row('Equipment', _equipSummary(c)),
          row('Ping', c.pingMs == 0 ? 'measuring…' : '${c.pingMs} ms'),
        ],
      ),
    );
  }

  Widget _rosterTile(NetClient c, NetPlayer p) {
    final host = p.id == c.hostId;
    final me = p.id == c.myId;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: me ? kSafeEdge.withValues(alpha: 0.5) : Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Color(kOutfitColors[p.id % kOutfitColors.length])
                  .withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.person, color: Colors.white70, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(me ? '${p.name}  (YOU)' : p.name.toUpperCase(),
                    style: TextStyle(
                        fontFamily: _mono,
                        color: p.bot ? Colors.white60 : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                    p.bot
                        ? 'AI Opponent'
                        : (p.ready
                            ? 'Deployed   ·   Wins ${p.wins}'
                            : 'In lobby'),
                    style: TextStyle(
                        fontFamily: _mono,
                        color: p.bot
                            ? Colors.white38
                            : (p.ready
                                ? const Color(0xFF57E389).withValues(alpha: 0.9)
                                : Colors.white38),
                        fontSize: 11)),
              ],
            ),
          ),
          Icon(host ? Icons.star : Icons.star_border,
              color: host ? kAccent : Colors.white24, size: 20),
        ],
      ),
    );
  }

  // ---- small building blocks ----
  Widget _fieldLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 2),
        child: Text(t,
            style: TextStyle(
                fontFamily: _mono,
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.w600)),
      );

  Widget _sectionLine(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Text(t,
                style: TextStyle(
                    fontFamily: _mono,
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                    letterSpacing: 2)),
            const SizedBox(width: 10),
            Expanded(
                child: Container(
                    height: 1, color: Colors.white.withValues(alpha: 0.08))),
          ],
        ),
      );

  Widget _dropField(IconData icon, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.5)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontFamily: _mono,
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
            Icon(Icons.expand_more,
                color: Colors.white.withValues(alpha: 0.5), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _pillGroup(
      List<String> labels, List<int> values, int sel, ValueChanged<int> onSel) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => onSel(values[i]),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel == values[i]
                      ? kAccent.withValues(alpha: 0.16)
                      : Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: sel == values[i]
                          ? kAccent
                          : Colors.white.withValues(alpha: 0.1)),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                        fontFamily: _mono,
                        color: sel == values[i] ? kAccent : Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _toggleChip(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: on ? kAccent.withValues(alpha: 0.12) : Colors.black26,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: on ? kAccent.withValues(alpha: 0.7) : Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? kAccent : Colors.white24),
            ),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontFamily: _mono,
                    color: on ? Colors.white : Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _roomCodeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Room Code  ·  share to squad up'),
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 0, 8, 0),
                      child: Icon(Icons.vpn_key_rounded,
                          size: 18, color: Colors.white38),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _room,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(
                            fontFamily: _mono,
                            color: Colors.white,
                            fontSize: 16,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w800),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => setState(() => _room.text = _randomCode()),
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kAccent.withValues(alpha: 0.6)),
                ),
                child: const Icon(Icons.casino, color: kAccent, size: 20),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _advancedServer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _advanced = !_advanced),
          child: Row(
            children: [
              Icon(_advanced ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: Colors.white38),
              const SizedBox(width: 4),
              Text('Advanced · Server',
                  style: TextStyle(
                      fontFamily: _mono,
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                      letterSpacing: 1)),
            ],
          ),
        ),
        if (_advanced) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 0, 8, 0),
                  child: Icon(Icons.dns_rounded,
                      size: 18, color: Colors.white38),
                ),
                Expanded(
                  child: TextField(
                    controller: _server,
                    style: const TextStyle(
                        fontFamily: _mono, color: Colors.white70, fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _bigButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: kAccent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: kAccent.withValues(alpha: 0.4),
                blurRadius: 22,
                spreadRadius: -2),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.black, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1)),
          ],
        ),
      ),
    );
  }

  Widget _ghostButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    fontFamily: _mono,
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
          ],
        ),
      ),
    );
  }



  // Jump to a real app section: pop this route, then switch the menu screen.
  void _goto(String screen) {
    Navigator.of(context).maybePop();
    widget.game?.screen.value = screen;
  }

  Widget _bottomNav() {
    Widget item(IconData icon, String label, bool active, VoidCallback? onTap) {
      final col = active ? kAccent : Colors.white.withValues(alpha: 0.4);
      return Expanded(
        child: GestureDetector(
          onTap: active ? null : onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: active
                ? BoxDecoration(
                    color: kAccent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12))
                : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: col, size: 22),
                const SizedBox(height: 5),
                Text(label,
                    style: TextStyle(
                        fontFamily: _mono,
                        color: col,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // OPERATIONS = this live-play terminal (current)
            item(Icons.public, 'ONLINE', true, null),
            // ARMORY = the Shop (guns / skins / gear)
            item(Icons.shopping_cart, 'SHOP', false,
                () => _goto(Screen.shop)),
            // FACTION = your operator identity / loadout
            item(Icons.person, 'PROFILE', false,
                () => _goto(Screen.profile)),
            // INTEL = daily missions / objectives
            item(Icons.assignment, 'MISSIONS', false,
                () => _goto(Screen.missions)),
          ],
        ),
      ),
    );
  }
}

/// Faint tactical grid used behind terminal screens.
class _GridPainter extends CustomPainter {
  const _GridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 46) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 46) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// A bullet the CLIENT flies itself. The server only tells us "a shot was
/// fired here, with this gun" — every client then simulates the tracer with
/// the real weapon stats. That's a fraction of the bandwidth of streaming
/// bullet positions and, because nothing is being interpolated, the rounds
/// look perfectly smooth even on a 200ms connection.
class _Tracer {
  Offset pos;
  final Offset vel;
  final double range;
  final Color color;
  final double width;
  double travelled = 0;
  _Tracer(this.pos, this.vel, this.range, this.color, this.width);
}

/// A short-lived visual: muzzle flash, impact spark, explosion ember, smoke.
class _Fx {
  Offset pos;
  Offset vel;
  double life;
  final double maxLife;
  final double size;
  final Color color;
  _Fx(this.pos, this.vel, this.life, this.size, this.color) : maxLife = life;
}

/// The live arena: renders the server snapshot and streams input at ~30 Hz.
class _ArenaView extends StatefulWidget {
  final NetClient client;
  final VoidCallback onLeave;
  const _ArenaView({required this.client, required this.onLeave});

  @override
  State<_ArenaView> createState() => _ArenaViewState();
}

class _ArenaViewState extends State<_ArenaView>
    with SingleTickerProviderStateMixin {
  Offset _move = Offset.zero; // left stick (-1..1)
  double _aim = 0; // last aim angle
  bool _fire = false;
  bool _nadeQ = false; // one-shot: throw a grenade next input
  bool _skillQ = false; // one-shot: activate the hero skill
  bool _reloadQ = false; // one-shot: reload
  bool _swapQ = false; // one-shot: switch weapon slots
  bool _takeQ = false; // one-shot: pick up the crate under our feet
  bool _wallQ = false; // one-shot: deploy a shield wall
  Timer? _pump;

  // ---- client-side prediction (your own operator moves instantly) ----
  double _selfX = 0, _selfY = 0;
  bool _hasSelf = false;
  /// Where the camera is this frame — used to mix positional audio.
  Offset _camPos = Offset.zero;
  int _lastHp = 100;
  bool _wasAlive = true;
  String? _lastBanner;

  // ---- locally simulated effects ----
  final List<_Tracer> _tracers = [];
  final List<_Fx> _fx = [];

  // ---- per-frame ticker: drives prediction + interpolation at display rate --
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  Duration _last = Duration.zero;

  // ---- spectate / kill-cam ----
  int _specIdx = 0;

  // ---- live perf readout (so "smooth" is measurable, not a feeling) ----
  int _fps = 0;
  int _frames = 0;
  Duration _fpsWindow = Duration.zero;

  /// World repaint cap. Prediction + interpolation are already continuous, so
  /// painting faster than this just burns GPU time and heats the phone.
  static const double _maxRenderHz = 90;
  double _sinceRender = 0;
  /// HUD refresh is time-based too: ammo and cooldowns don't need 30Hz.
  final ValueNotifier<int> _hud = ValueNotifier(0);
  double _sinceHud = 0;

  static const double _speed = 250; // must match the server's playerSpeed
  static final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    // stream input to the server at a steady rate, independent of frame timing
    _pump = Timer.periodic(const Duration(milliseconds: 33), (_) {
      widget.client.sendInput(_move.dx, _move.dy, _aim, _fire,
          nade: _nadeQ,
          skill: _skillQ,
          reload: _reloadQ,
          swap: _swapQ,
          take: _takeQ,
          wall: _wallQ);
      _nadeQ = false;
      _skillQ = false;
      _reloadQ = false;
      _swapQ = false;
      _takeQ = false;
      _wallQ = false;
    });
    _ticker = createTicker(_onFrame)..start();
  }

  @override
  void dispose() {
    _pump?.cancel();
    _ticker.dispose();
    _frame.dispose();
    _hud.dispose();
    super.dispose();
  }

  bool _blocked(double x, double y) {
    for (final o in widget.client.obstacles) {
      if (!o.blocks) continue;
      if ((x - o.x).abs() < o.w / 2 + 18 && (y - o.y).abs() < o.h / 2 + 18) {
        return true;
      }
    }
    for (final w in widget.client.walls) {
      if ((x - w.x).abs() < w.w / 2 + 16 && (y - w.y).abs() < w.h / 2 + 16) {
        return true;
      }
    }
    return false;
  }

  bool _blocksBullet(double x, double y) {
    for (final o in widget.client.obstacles) {
      if (!o.blocks) continue;
      if ((x - o.x).abs() < o.w / 2 && (y - o.y).abs() < o.h / 2) return true;
    }
    for (final w in widget.client.walls) {
      if ((x - w.x).abs() < w.w / 2 && (y - w.y).abs() < w.h / 2) return true;
    }
    return false;
  }

  void _onFrame(Duration now) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;

    // rolling FPS over a 500ms window
    _frames++;
    if (now - _fpsWindow >= const Duration(milliseconds: 500)) {
      final secs = (now - _fpsWindow).inMicroseconds / 1e6;
      if (_fpsWindow != Duration.zero) _fps = (_frames / secs).round();
      _fpsWindow = now;
      _frames = 0;
    }
    final c = widget.client;
    final me = c.me;

    if (me != null) {
      if (!_hasSelf || !me.alive) {
        _selfX = me.x;
        _selfY = me.y;
        _hasSelf = true;
      } else {
        // integrate our own input immediately (mirrors the server's sim)
        var mx = _move.dx, my = _move.dy;
        final len = math.sqrt(mx * mx + my * my);
        if (len > 1) {
          mx /= len;
          my /= len;
        }
        final spd = _speed * (me.dash ? 1.8 : 1.0);
        final nx = (_selfX + mx * spd * dt).clamp(20.0, c.world - 20);
        final ny = (_selfY + my * spd * dt).clamp(20.0, c.world - 20);
        if (!_blocked(nx, ny)) {
          _selfX = nx;
          _selfY = ny;
        } else if (!_blocked(nx, _selfY)) {
          _selfX = nx;
        } else if (!_blocked(_selfX, ny)) {
          _selfY = ny;
        }
        // Reconcile with the authoritative position. Converge faster when the
        // stick is released, otherwise the server's in-flight inputs keep
        // dragging us forward and the operator visibly slides after let-go.
        final ex = me.x - _selfX, ey = me.y - _selfY;
        final err = math.sqrt(ex * ex + ey * ey);
        if (err > 70) {
          _selfX = me.x; // teleport / respawn / big desync
          _selfY = me.y;
        } else if (err > 0.5) {
          final idle = _move.distance < 0.01;
          final k = ((idle ? 12.0 : 6.0) * dt).clamp(0.0, 1.0);
          _selfX += ex * k;
          _selfY += ey * k;
        }
      }
    }

    final cam = _camTarget(c);
    if (cam != null) {
      _camPos = _pos(c, cam.id) ?? Offset(cam.x, cam.y);
    }
    _reactToState(c);
    _spawnEvents(c);
    _stepTracers(dt);
    _stepFx(dt);

    _sinceRender += dt;
    if (_sinceRender >= 1 / _maxRenderHz) {
      _sinceRender = 0;
      _frame.value++;
    }
    _sinceHud += dt;
    if (_sinceHud >= 0.05) {
      _sinceHud = 0;
      _hud.value++;
    }
  }

  /// Rendered position of a player, or null if we have never seen them.
  Offset? _pos(NetClient c, int id) {
    if (id == c.myId && _hasSelf) return Offset(_selfX, _selfY);
    final l = c.lerpOf(id);
    return l == null ? null : Offset(l[0], l[1]);
  }

  /// Audio + haptics driven by state changes: taking damage, dying, winning.
  void _reactToState(NetClient c) {
    final me = c.me;
    if (me != null) {
      if (me.hp < _lastHp && me.alive) Sfx.hurt();
      if (_wasAlive && !me.alive) Sfx.death();
      _lastHp = me.hp;
      _wasAlive = me.alive;
    }
    final banner = c.matchWinner ?? c.roundBanner;
    if (banner != null && banner != _lastBanner) Sfx.win();
    _lastBanner = banner;
  }

  /// Where a shooter is being DRAWN right now — the predicted position for
  /// you, the interpolated one for everybody else. Tracers must start here,
  /// not at the snapshot position, or they visibly leave the wrong spot.
  Offset _renderedPos(NetClient c, int shooter, double fallbackX,
      double fallbackY) {
    if (shooter == c.myId && _hasSelf) return Offset(_selfX, _selfY);
    final l = c.lerpOf(shooter);
    if (l != null) return Offset(l[0], l[1]);
    return Offset(fallbackX, fallbackY);
  }

  /// Turns server events (shots / explosions / airdrops) into local visuals.
  void _spawnEvents(NetClient c) {
    for (final s in c.shotQueue) {
      final id = WeaponId.values[s.wi.clamp(0, WeaponId.values.length - 1)];
      final w = kWeapons[id]!;
      // The muzzle, not the chest: the gun barrel sits ~2.15 body radii
      // forward, exactly where the offline game spawns its rounds.
      const muzzle = kPlayerRadius * 2.15;
      final from = _renderedPos(c, s.shooter, s.x, s.y);
      // your own aim is live; everyone else's comes with the event
      final aim = s.shooter == c.myId ? _aim : s.aim;
      for (var i = 0; i < w.pellets; i++) {
        final jitter = (_rng.nextDouble() * 2 - 1) * w.spread;
        final a = aim + jitter;
        _tracers.add(_Tracer(
          from + Offset(math.cos(a) * muzzle, math.sin(a) * muzzle),
          Offset(math.cos(a) * w.bulletSpeed, math.sin(a) * w.bulletSpeed),
          w.range,
          w.color,
          _tracerWidth(id),
        ));
      }
      // muzzle flash + smoke + brass, at the barrel
      final tip = from + Offset(math.cos(aim) * muzzle, math.sin(aim) * muzzle);
      for (var i = 0; i < 3; i++) {
        final a = aim + (_rng.nextDouble() - 0.5) * 0.6;
        _fx.add(_Fx(tip, Offset(math.cos(a) * 130, math.sin(a) * 130), 0.09, 4,
            const Color(0xFFFFE9A8)));
      }
      _fx.add(_Fx(tip, Offset(math.cos(aim) * 30, math.sin(aim) * 30), 0.5, 5,
          const Color(0x55909090)));
      // brass casing flicking out to the side, like the offline game
      final side = aim + 1.4;
      _fx.add(_Fx(from + Offset(math.cos(aim) * 14, math.sin(aim) * 14),
          Offset(math.cos(side) * 160, math.sin(side) * 160), 0.35, 2.2,
          const Color(0xFFE8C15A)));
      // AUDIO. The online arena used to be completely silent — every shot,
      // blast and hit now sounds exactly like it does offline, mixed by how
      // far away it happened.
      if (s.shooter == c.myId) {
        Sfx.shoot();
      } else {
        final d = (from - _camPos).distance;
        if (d < 620) Sfx.shoot(vol: (0.18 * (1 - d / 620)).clamp(0.04, 0.18));
      }
    }
    c.shotQueue.clear();

    for (final b in c.boomQueue) {
      final d = (b - _camPos).distance;
      if (d < 900) Sfx.boom();
      for (var i = 0; i < 22; i++) {
        final a = _rng.nextDouble() * math.pi * 2;
        final sp = 90 + _rng.nextDouble() * 300;
        _fx.add(_Fx(b, Offset(math.cos(a) * sp, math.sin(a) * sp),
            0.28 + _rng.nextDouble() * 0.35, 6,
            i.isEven ? const Color(0xFFFFB020) : const Color(0xFFFF5A2A)));
      }
      for (var i = 0; i < 8; i++) {
        final a = _rng.nextDouble() * math.pi * 2;
        _fx.add(_Fx(b, Offset(math.cos(a) * 50, math.sin(a) * 50), 0.9, 12,
            const Color(0x77555560)));
      }
    }
    c.boomQueue.clear();
    c.dropQueue.clear();
  }

  static double _tracerWidth(WeaponId w) {
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

  void _stepTracers(double dt) {
    for (final t in _tracers) {
      final step = t.vel * dt;
      t.pos = t.pos + step;
      t.travelled += step.distance;
      if (t.travelled > t.range) continue;
      if (_blocksBullet(t.pos.dx, t.pos.dy)) {
        t.travelled = t.range + 1;
        for (var i = 0; i < 4; i++) {
          final a = _rng.nextDouble() * math.pi * 2;
          _fx.add(_Fx(t.pos, Offset(math.cos(a) * 70, math.sin(a) * 70), 0.22,
              2.4, t.color));
        }
      }
    }
    _tracers.removeWhere((t) => t.travelled > t.range);
    if (_tracers.length > 400) _tracers.removeRange(0, _tracers.length - 400);
  }

  void _stepFx(double dt) {
    for (final f in _fx) {
      f.life -= dt;
      f.pos = f.pos + f.vel * dt;
      f.vel = f.vel * (1 - (3.2 * dt).clamp(0.0, 1.0));
    }
    _fx.removeWhere((f) => f.life <= 0);
    if (_fx.length > 320) _fx.removeRange(0, _fx.length - 320);
  }

  /// Who the camera follows: you while alive, otherwise a spectated player.
  NetPlayer? _camTarget(NetClient c) {
    final me = c.me;
    if (me != null && me.alive) return me;
    final alive = c.players.where((p) => p.alive && p.ready).toList();
    if (alive.isEmpty) return me;
    return alive[_specIdx % alive.length];
  }

  void _cycleSpectate() => setState(() => _specIdx++);

  /// The equipped hero's skill icon, so the button reads the same as solo.
  IconData _skillIcon() {
    final hero = kHeroes[Profile.instance.hero.clamp(0, kHeroes.length - 1)];
    switch (hero.skill) {
      case SkillType.dash:
        return Icons.bolt;
      case SkillType.shield:
        return Icons.shield;
      case SkillType.frenzy:
        return Icons.local_fire_department;
      case SkillType.medic:
        return Icons.healing;
      case SkillType.grenadier:
        return Icons.workspaces;
    }
  }

  /// The crate under your feet that would cost you the gun in your hands.
  /// (An empty slot is filled automatically by the server — no prompt needed.)
  NetLoot? _pickupTarget(NetClient c, NetPlayer me) {
    if (me.wi2 < 0) return null; // there's a free slot; walking over it works
    for (final l in c.loot) {
      if (l.kind == 0) continue;
      if ((l.x - _selfX).abs() > 44 || (l.y - _selfY).abs() > 44) continue;
      if (l.wi == me.wi || l.wi == me.wi2) continue;
      return l;
    }
    return null;
  }

  void _aimStick(Offset dir) {
    if (dir.distance > 0.2) {
      _aim = math.atan2(dir.dy, dir.dx);
      _fire = true;
    } else {
      _fire = false;
    }
  }

  // ---- match over screen (shareable) ----
  static final GlobalKey _shotKey = GlobalKey();

  Future<void> _shareResult(BuildContext context, NetClient c) {
    final me = c.me;
    final won = c.matchWinner != null && me != null && me.name == c.matchWinner;
    final txt = won
        ? '🏆 WINNER WINNER! I took the Zone Royale custom room — ${me.kills} kills. Beat that!'
        : '🔫 Zone Royale custom room — ${c.matchWinner} took it. ${me?.kills ?? 0} kills. Rematch?';
    return shareCard(
      context,
      cardKey: _shotKey,
      text: txt,
      subject: 'Zone Royale custom room',
      fileStem: 'zone_royale_room',
    );
  }

  Widget _matchOver(NetClient c, NetPlayer? me) {
    final won = me != null && me.name == c.matchWinner;
    final accent = won ? kAccent : kAccent2;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.82),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RepaintBoundary(
                    key: _shotKey,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            accent.withValues(alpha: 0.18),
                            const Color(0xFF05070C)
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: accent.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('ZONE ROYALE  //  CUSTOM ROOM',
                              style: TextStyle(
                                  fontFamily: _mono,
                                  color: accent,
                                  fontSize: 11,
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w900)),
                          const SizedBox(height: 14),
                          Text(won ? 'WINNER WINNER' : 'MATCH OVER',
                              style: TextStyle(
                                  color: won ? Colors.white : accent,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2)),
                          const SizedBox(height: 6),
                          Text('${c.matchWinner} WINS'.toUpperCase(),
                              style: TextStyle(
                                  color: accent,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1)),
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _stat('KILLS', '${me?.kills ?? 0}'),
                              _stat('ROUNDS WON', '${me?.wins ?? 0}'),
                              _stat('PLAYERS', '${c.players.length}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                          child: _ghostBtn(Icons.ios_share, 'SHARE',
                              () => _shareResult(context, c))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _ghostBtn(
                              Icons.logout, 'LEAVE ROOM', widget.onLeave)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('Next match starts automatically…',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _mono = 'monospace';

  Widget _stat(String k, String v) => Column(
        children: [
          Text(v,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(k,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700)),
        ],
      );

  Widget _ghostBtn(IconData icon, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: Colors.white70),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      fontSize: 13)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    return LayoutBuilder(builder: (context, box) {
      // Fractional control positions have to be measured against the box the
      // Stack actually gets, not the whole window — otherwise every control
      // lands low and right of where the editor put it.
      final size = Size(box.maxWidth, box.maxHeight);
      Profile.instance.hudLandscape = size.width > size.height;
      return _stack(c, size);
    });
  }

  Widget _stack(NetClient c, Size size) {
    return Stack(
      children: [
        // The world repaints every display frame (90 Hz) so prediction +
        // interpolation look continuous between the server's 30 Hz snapshots.
        // It sits in its own RepaintBoundary so it never drags the HUD along.
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _frame,
              builder: (_, _) {
                final me = c.me;
                final spectating =
                    me != null && !me.alive && c.matchWinner == null;
                final cam = _camTarget(c);
                return GestureDetector(
                  onTap: spectating ? _cycleSpectate : null,
                  child: CustomPaint(
                    painter: _ArenaPainter(
                      c,
                      selfPos: _hasSelf && (me?.alive ?? false)
                          ? Offset(_selfX, _selfY)
                          : null,
                      selfAim: _aim,
                      camId: cam?.id ?? c.myId,
                      tracers: _tracers,
                      fx: _fx,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // HUD/overlays refresh on a timer, not on every packet — rebuilding
        // the whole control tree 30x a second was real, measurable jank.
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _hud,
            builder: (_, _) =>
                _overlays(c, size, MediaQuery.of(context).padding),
          ),
        ),
      ],
    );
  }

  Widget _overlays(NetClient c, Size size, EdgeInsets safe) {
    final me = c.me;
    final spectating = me != null && !me.alive && c.matchWinner == null;
    final cam = _camTarget(c);
    final pickup = me == null ? null : _pickupTarget(c, me);
    return Stack(
      children: [
        // No snapshot for us yet: say so instead of showing an empty arena
        // that looks like the game broke.
        if (me == null)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: kSafeEdge),
                      const SizedBox(height: 16),
                      Text(
                          c.serverOutdated
                              ? 'SERVER NEEDS UPDATING'
                              : 'WAITING FOR THE SERVER…',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2)),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                            c.serverOutdated
                                ? 'This host is running an older build, so it '
                                    'speaks a different language than this app. '
                                    'Redeploy the server and rejoin.'
                                : 'Holding for the first world snapshot.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                                height: 1.4)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // spectate banner
        if (spectating)
          Positioned(
            top: 58,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kSafeEdge.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                      'SPECTATING  ${(cam?.name ?? '—').toUpperCase()}   ·   TAP TO SWITCH',
                      style: const TextStyle(
                          color: kSafeEdge,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                ),
              ),
            ),
          ),
        // top HUD
        Positioned(
          top: 8,
          left: 12,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pill('ALIVE  ${c.aliveCount}'),
                if (c.rounds > 1)
                  _pill('ROUND  ${c.round}/${c.rounds * 2 - 1}', color: kAccent),
                _pill('${me?.kills ?? 0} KILLS'),
                // measurable smoothness + network health
                _pill('$_fps FPS',
                    color: _fps >= 80
                        ? const Color(0xFF57E389)
                        : (_fps >= 50 ? kAccent : kAccent2)),
                _pill(c.pingMs == 0 ? '— MS' : '${c.pingMs} MS',
                    color: c.pingMs == 0
                        ? Colors.white54
                        : (c.pingMs < 100
                            ? const Color(0xFF57E389)
                            : (c.pingMs < 200 ? kAccent : kAccent2))),
                GestureDetector(
                  onTap: widget.onLeave,
                  child: _pill('LEAVE', color: kAccent2),
                ),
              ],
            ),
          ),
        ),
        // match over screen (takes priority) — shareable, like the solo end card
        if (c.matchWinner != null) _matchOver(c, me)
        // round result banner
        else if (c.roundBanner != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Text(c.roundBanner!,
                    style: const TextStyle(
                        color: kSafeEdge,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2)),
              ),
            ),
          )
        // death banner
        else if (me != null && !me.alive)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Text('ELIMINATED',
                    style: TextStyle(
                        color: kAccent2,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3)),
              ),
            ),
          ),
        // Controls come from the SHARED set (lib/ui/hud_controls.dart), so a
        // custom room and a solo match hand you exactly the same sticks,
        // buttons and panels in exactly the same places.
        hudPlace(
          size,
          Profile.instance.leftHanded ? 'aim' : 'move',
          HudStick(
            stickKey: const ValueKey('js-move'),
            label: 'MOVE',
            accent: kSafeEdge,
            onChange: (d) => _move = d,
            onRelease: () => _move = Offset.zero,
          ),
          132,
          158,
          safe,
        ),
        hudPlace(
          size,
          Profile.instance.leftHanded ? 'move' : 'aim',
          HudStick(
            stickKey: const ValueKey('js-aim'),
            label: 'AIM · FIRE',
            accent: kAccent2,
            onChange: _aimStick,
            onRelease: () => _fire = false,
          ),
          132,
          158,
          safe,
        ),
        hudPlace(
          size,
          'skill',
          HudActionButton(
            glyph: Icon(_skillIcon(), size: 26, color: const Color(0xFFB06BFF)),
            label: (me?.cd ?? 0) > 0 ? '${me?.cd}' : 'SKILL',
            color: const Color(0xFFB06BFF),
            ready: (me?.cd ?? 0) <= 0,
            onTap: () => _skillQ = true,
          ),
          64,
          64,
          safe,
        ),
        hudPlace(
          size,
          'nade',
          HudActionButton(
            glyph: const Text('💣', style: TextStyle(fontSize: 19)),
            label: '${me?.nades ?? 0}',
            color: const Color(0xFF6ABF5A),
            ready: (me?.nades ?? 0) > 0,
            onTap: () => _nadeQ = true,
            size: 60,
          ),
          60,
          60,
          safe,
        ),
        hudPlace(
          size,
          'wall',
          HudActionButton(
            glyph: SizedBox(
              width: 24,
              height: 16,
              child: CustomPaint(
                  painter: ShieldWallGlyph(lit: (me?.walls ?? 0) > 0)),
            ),
            label: '${me?.walls ?? 0}',
            color: const Color(0xFF7FE8FF),
            ready: (me?.walls ?? 0) > 0,
            onTap: () => _wallQ = true,
            size: 60,
          ),
          60,
          60,
          safe,
        ),
        hudPlace(
          size,
          'reload',
          HudWeaponPanel(
            weapon: WeaponId.values[
                (me?.wi ?? 5).clamp(0, WeaponId.values.length - 1)],
            ammo: me?.ammo ?? 0,
            reloading: me?.reloading ?? false,
            reloadFrac: 0.5,
            onTap: () => _reloadQ = true,
          ),
          130,
          80,
          safe,
        ),
        hudPlace(
          size,
          'swap',
          HudSwapPanel(
            other: (me == null || me.wi2 < 0)
                ? null
                : WeaponId.values[me.wi2.clamp(0, WeaponId.values.length - 1)],
            onTap: () => _swapQ = true,
          ),
          74,
          66,
          safe,
        ),
        hudPlace(
          size,
          'fire',
          HudFireMode(
            supportsAuto: kWeapons[WeaponId.values[
                    (me?.wi ?? 5).clamp(0, WeaponId.values.length - 1)]]!
                .auto,
            auto: Profile.instance.fireAuto,
            onTap: () {},
          ),
          64,
          64,
          safe,
        ),
        hudPlace(
          size,
          'hp',
          HudHealth(
            hp: me?.hp ?? 0,
            vestFrac: (me?.vest ?? 0) / 100,
            helmetFrac: (me?.helmet ?? 0) / 100,
          ),
          150,
          52,
          safe,
        ),
        if (pickup != null)
          hudPlace(
            size,
            'pick',
            HudPickupPrompt(
              offered: WeaponId.values[
                  pickup.wi.clamp(0, WeaponId.values.length - 1)],
              held: WeaponId.values[
                  (me?.wi ?? 5).clamp(0, WeaponId.values.length - 1)],
              onTap: () => _takeQ = true,
            ),
            168,
            52,
            safe,
          ),
      ],
    );
  }

  Widget _pill(String text, {Color color = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      child: Text(text,
          style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1)),
    );
  }
}

/// Renders the online arena. Same visual language as the offline match:
/// one consistent light direction (top-left), extruded cover with real roofs,
/// textured ground, glowing tracers and a gas wall you can read at a glance.
class _ArenaPainter extends CustomPainter {
  final NetClient c;
  final Offset? selfPos; // client-predicted position of your own operator
  final double selfAim;
  final int camId; // who the camera follows (you, or a spectated player)
  final List<_Tracer> tracers;
  final List<_Fx> fx;
  _ArenaPainter(this.c,
      {this.selfPos,
      this.selfAim = 0,
      required this.camId,
      required this.tracers,
      required this.fx});

  // Smoothed world transforms, computed once per frame: predicted for you,
  // interpolated for everyone else.
  final Map<int, Offset> _pos = {};
  final Map<int, double> _aims = {};

  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  void _resolveTransforms() {
    _pos.clear();
    _aims.clear();
    for (final p in c.players) {
      if (p.id == c.myId && selfPos != null) {
        _pos[p.id] = selfPos!;
        _aims[p.id] = selfAim;
        continue;
      }
      final l = c.lerpOf(p.id);
      _pos[p.id] = l == null ? Offset(p.x, p.y) : Offset(l[0], l[1]);
      _aims[p.id] = l == null ? p.aim : l[2];
    }
  }

  /// Ground tint per selected room map — so the host's map choice is visible.
  static List<Color> _groundFor(String map) {
    switch (map.toUpperCase()) {
      case 'URBAN BUILDINGS':
      case 'URBAN':
        return const [Color(0xFF1A1F2B), Color(0xFF090C13)];
      case 'FOREST':
        return const [Color(0xFF12241A), Color(0xFF060E09)];
      case 'COMPOUND':
        return const [Color(0xFF1C1A24), Color(0xFF0A0810)];
      case 'BADLANDS':
        return const [Color(0xFF241D14), Color(0xFF0E0A06)];
      default:
        return const [Color(0xFF141A26), Color(0xFF070A10)];
    }
  }

  /// Cheap deterministic hash → stable "random" per world cell, so ground
  /// detail doesn't crawl as the camera moves.
  static double _hash(int x, int y) {
    var h = x * 374761393 + y * 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _resolveTransforms();

    final cols = _groundFor(c.map);
    final camPos = _pos[camId] ?? Offset(c.world / 2, c.world / 2);
    final camX = camPos.dx, camY = camPos.dy;
    // Landscape shows a shorter vertical slice so operators stay readable.
    final viewH =
        size.width > size.height ? kViewHeightLandscape : kViewHeight;
    final scale = size.height / viewH;

    // Everything outside the camera is culled.
    final halfW = size.width / (2 * scale) + 80;
    final halfH = size.height / (2 * scale) + 80;
    final vL = camX - halfW, vR = camX + halfW;
    final vT = camY - halfH, vB = camY + halfH;
    bool onScreen(double x, double y, [double m = 0]) =>
        x > vL - m && x < vR + m && y > vT - m && y < vB + m;

    canvas.drawRect(Offset.zero & size, _fill..color = cols[1]);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-camX, -camY);

    _drawGround(canvas, cols, vL, vT, vR, vB);
    _drawObstacles(canvas, onScreen, shadowsOnly: true);
    _drawLoot(canvas, onScreen);
    _drawObstacles(canvas, onScreen);
    _drawWalls(canvas, onScreen);
    _drawTracers(canvas, onScreen);
    _drawGrenades(canvas, onScreen);
    _drawPlayers(canvas, onScreen);
    _drawFx(canvas, onScreen);
    _drawBushes(canvas, onScreen);
    _drawGas(canvas, vL, vT, vR, vB);
    canvas.restore();

    _drawLabels(canvas, size, camX, camY, scale, onScreen);
    _drawVignette(canvas, size);
  }

  // ---------------------------------------------------------------- ground
  void _drawGround(Canvas canvas, List<Color> cols, double vL, double vT,
      double vR, double vB) {
    final rect = Rect.fromLTRB(vL, vT, vR, vB);
    canvas.drawRect(
        rect,
        _fill
          ..shader = ui.Gradient.radial(
              Offset(c.world / 2, c.world / 2), c.world * 0.72, cols));
    _fill.shader = null;

    // Ground detail: stable patches + gravel, only for the cells in view. This
    // is what stops the floor reading as flat coloured paper.
    const cell = 160.0;
    final x0 = (vL / cell).floor(), x1 = (vR / cell).ceil();
    final y0 = (vT / cell).floor(), y1 = (vB / cell).ceil();
    for (var gx = x0; gx <= x1; gx++) {
      for (var gy = y0; gy <= y1; gy++) {
        final h = _hash(gx, gy);
        final cx = gx * cell + h * cell;
        final cy = gy * cell + _hash(gy, gx) * cell;
        if (h < 0.42) {
          canvas.drawOval(
              Rect.fromCenter(
                  center: Offset(cx, cy),
                  width: 70 + h * 150,
                  height: 46 + h * 90),
              _fill..color = Colors.white.withValues(alpha: 0.018));
        } else if (h < 0.62) {
          canvas.drawOval(
              Rect.fromCenter(
                  center: Offset(cx, cy), width: 90 + h * 120, height: 60),
              _fill..color = Colors.black.withValues(alpha: 0.16));
        }
        // scattered gravel specks
        for (var i = 0; i < 3; i++) {
          final s = _hash(gx * 7 + i, gy * 13 - i);
          canvas.drawCircle(
              Offset(gx * cell + s * cell, gy * cell + _hash(gy + i, gx) * cell),
              1.2 + s * 1.6,
              _fill..color = Colors.white.withValues(alpha: 0.035));
        }
      }
    }

    // faint survey grid keeps a sense of scale
    _stroke
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    final g0 = (vL / 400).floor() * 400.0;
    for (var g = g0; g <= vR; g += 400) {
      canvas.drawLine(Offset(g, vT), Offset(g, vB), _stroke);
    }
    final h0 = (vT / 400).floor() * 400.0;
    for (var g = h0; g <= vB; g += 400) {
      canvas.drawLine(Offset(vL, g), Offset(vR, g), _stroke);
    }

    // world border
    canvas.drawRect(
        Rect.fromLTWH(0, 0, c.world, c.world),
        _stroke
          ..color = kSafeEdge.withValues(alpha: 0.35)
          ..strokeWidth = 6);
  }

  // ------------------------------------------------------------- obstacles
  void _drawObstacles(Canvas canvas, bool Function(double, double, [double]) vis,
      {bool shadowsOnly = false}) {
    for (final o in c.obstacles) {
      if (o.kind == 2) continue; // bushes draw on top, later
      if (!vis(o.x, o.y, o.w / 2 + o.h / 2 + 30)) continue;
      final rect =
          Rect.fromCenter(center: Offset(o.x, o.y), width: o.w, height: o.h);
      final tall = o.kind == 0;
      final lift = tall ? 18.0 : 10.0;
      final radius = Radius.circular(tall ? 4 : 5);

      if (shadowsOnly) {
        // one light source, so every shadow falls the same way
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect.translate(lift * 0.6, lift * 0.8),
                radius),
            _fill..color = Colors.black.withValues(alpha: 0.42));
        continue;
      }

      // extruded side wall
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(rect.left, rect.top - lift, rect.right, rect.bottom),
              radius),
          _fill..color = tall ? const Color(0xFF232A38) : const Color(0xFF3A2C1C));
      // roof
      final roof = rect.translate(0, -lift);
      canvas.drawRRect(RRect.fromRectAndRadius(roof, radius),
          _fill..color = tall ? const Color(0xFF4A5468) : const Color(0xFF7C5C36));
      // lit edge (top-left) + shaded edge (bottom-right)
      canvas.drawRect(
          Rect.fromLTWH(roof.left + 2, roof.top + 2, roof.width - 4, 3),
          _fill..color = Colors.white.withValues(alpha: 0.22));
      canvas.drawRect(
          Rect.fromLTWH(roof.left + 2, roof.bottom - 4, roof.width - 4, 3),
          _fill..color = Colors.black.withValues(alpha: 0.28));

      if (tall) {
        // rooftop plant: vents + lit windows, so buildings read as buildings
        _fill.color = Colors.black.withValues(alpha: 0.25);
        for (var wx = roof.left + 8; wx < roof.right - 10; wx += 22) {
          canvas.drawRect(Rect.fromLTWH(wx, roof.top + 7, 9, 6), _fill);
        }
        _fill.color = const Color(0x55FFE9A8);
        for (var wx = roof.left + 9; wx < roof.right - 9; wx += 16) {
          for (var wy = roof.top + 16; wy < roof.bottom - 8; wy += 16) {
            if (_hash(wx.round(), wy.round()) < 0.45) continue;
            canvas.drawRect(Rect.fromLTWH(wx, wy, 6, 6), _fill);
          }
        }
      } else {
        // crate slats
        canvas.drawRRect(
            RRect.fromRectAndRadius(roof.deflate(3), const Radius.circular(3)),
            _stroke
              ..color = const Color(0x66FFCF9E)
              ..strokeWidth = 2);
        canvas.drawLine(Offset(roof.left + 3, roof.center.dy),
            Offset(roof.right - 3, roof.center.dy),
            _stroke..color = const Color(0x33000000));
      }
      canvas.drawRRect(
          RRect.fromRectAndRadius(roof, radius),
          _stroke
            ..color = Colors.black.withValues(alpha: 0.45)
            ..strokeWidth = 1.6);
    }
  }

  /// Player-deployed cover: frosted energy slabs that crack as they take fire.
  void _drawWalls(Canvas canvas, bool Function(double, double, [double]) vis) {
    for (final w in c.walls) {
      if (!vis(w.x, w.y, w.w + w.h)) continue;
      final r = Rect.fromCenter(
          center: Offset(w.x, w.y), width: w.w, height: w.h);
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(5));
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              r.translate(6, 9), const Radius.circular(5)),
          _fill..color = Colors.black.withValues(alpha: 0.3));
      canvas.drawRRect(
          rr,
          _fill
            ..color = const Color(0xFF7FE8FF)
                .withValues(alpha: 0.22 + 0.18 * w.health));
      canvas.drawRRect(
          rr,
          _stroke
            ..color = const Color(0xFFBFF4FF)
                .withValues(alpha: 0.55 + 0.35 * w.health)
            ..strokeWidth = 2.5);
      _stroke
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 1.4;
      final long = r.width > r.height;
      final n = ((long ? r.width : r.height) / 22).floor();
      for (var i = 1; i < n; i++) {
        final t = i / n;
        if (long) {
          final x = r.left + r.width * t;
          canvas.drawLine(
              Offset(x, r.top + 3), Offset(x, r.bottom - 3), _stroke);
        } else {
          final y = r.top + r.height * t;
          canvas.drawLine(
              Offset(r.left + 3, y), Offset(r.right - 3, y), _stroke);
        }
      }
    }
  }

  void _drawBushes(Canvas canvas, bool Function(double, double, [double]) vis) {
    for (final o in c.obstacles) {
      if (o.kind != 2) continue;
      if (!vis(o.x, o.y, o.w)) continue;
      final centre = Offset(o.x, o.y);
      final rad = o.w / 2;
      canvas.drawOval(
          Rect.fromCenter(
              center: centre.translate(6, 9),
              width: rad * 2.1,
              height: rad * 1.4),
          _fill..color = Colors.black.withValues(alpha: 0.3));
      canvas.drawCircle(centre, rad, _fill..color = const Color(0xCC123F1E));
      canvas.drawCircle(centre.translate(-rad * 0.2, -rad * 0.2), rad * 0.75,
          _fill..color = const Color(0xCC1F6B34));
      canvas.drawCircle(centre.translate(-rad * 0.34, -rad * 0.36), rad * 0.36,
          _fill..color = const Color(0x662FB85A));
    }
  }

  // ------------------------------------------------------------------ loot
  void _drawLoot(Canvas canvas, bool Function(double, double, [double]) vis) {
    for (final l in c.loot) {
      if (!vis(l.x, l.y, 40)) continue;
      final o = Offset(l.x, l.y);
      canvas.drawOval(
          Rect.fromCenter(center: o.translate(3, 8), width: 30, height: 12),
          _fill..color = Colors.black.withValues(alpha: 0.3));
      if (l.kind == 0) {
        canvas.drawCircle(o, 20,
            _fill..color = const Color(0xFF57E389).withValues(alpha: 0.16));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: o, width: 24, height: 24),
                const Radius.circular(5)),
            _fill..color = const Color(0xFFF2F5F8));
        canvas.drawRect(Rect.fromCenter(center: o, width: 15, height: 5),
            _fill..color = const Color(0xFFE23B3B));
        canvas.drawRect(Rect.fromCenter(center: o, width: 5, height: 15),
            _fill..color = const Color(0xFFE23B3B));
        continue;
      }
      if (l.kind == 3 || l.kind == 4 || l.kind == 5) {
        final tint = l.kind == 3
            ? const Color(0xFF7FC4FF)
            : l.kind == 4
                ? const Color(0xFFC9D6A8)
                : const Color(0xFF7FE8FF);
        canvas.drawCircle(o, 18, _fill..color = tint.withValues(alpha: 0.18));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: o,
                    width: l.kind == 5 ? 26 : 20,
                    height: l.kind == 5 ? 16 : 22),
                const Radius.circular(4)),
            _fill..color = const Color(0xFF2A3140));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: o,
                    width: l.kind == 5 ? 26 : 20,
                    height: l.kind == 5 ? 16 : 22),
                const Radius.circular(4)),
            _stroke..color = tint..strokeWidth = 2);
        continue;
      }
      final id = WeaponId.values[l.wi.clamp(0, WeaponId.values.length - 1)];
      final col = kWeapons[id]!.color;
      if (l.kind == 2) {
        // airdrop: a lit pad + a stencilled crate, visible from across the map
        canvas.drawCircle(o, 36, _fill..color = kAccent.withValues(alpha: 0.14));
        canvas.drawCircle(o, 26,
            _stroke..color = kAccent.withValues(alpha: 0.8)..strokeWidth = 2);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: o, width: 36, height: 30),
                const Radius.circular(4)),
            _fill..color = const Color(0xFF2A2F1E));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: o, width: 36, height: 30),
                const Radius.circular(4)),
            _stroke..color = kAccent..strokeWidth = 2);
      } else {
        canvas.drawCircle(o, 16, _fill..color = col.withValues(alpha: 0.18));
      }
      drawGunIcon(canvas, o, 28, id, fill: _fill, stroke: _stroke);
    }
  }

  // --------------------------------------------------------------- tracers
  void _drawTracers(
      Canvas canvas, bool Function(double, double, [double]) vis) {
    for (final t in tracers) {
      if (!vis(t.pos.dx, t.pos.dy, 30)) continue;
      final back = t.pos - t.vel * (0.022 * (0.6 + t.width));
      canvas.drawLine(
          back,
          t.pos,
          _stroke
            ..color = t.color.withValues(alpha: 0.3)
            ..strokeWidth = 6 * t.width
            ..strokeCap = StrokeCap.round);
      canvas.drawLine(
          back,
          t.pos,
          _stroke
            ..color = t.color
            ..strokeWidth = 2.4 * t.width);
      canvas.drawCircle(t.pos, 2.4 * t.width, _fill..color = Colors.white);
    }
  }

  void _drawFx(Canvas canvas, bool Function(double, double, [double]) vis) {
    for (final f in fx) {
      if (!vis(f.pos.dx, f.pos.dy, 20)) continue;
      final a = (f.life / f.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(f.pos, f.size * a,
          _fill..color = f.color.withValues(alpha: a * 0.95));
    }
  }

  void _drawGrenades(
      Canvas canvas, bool Function(double, double, [double]) vis) {
    for (final g in c.nades) {
      if (!vis(g.dx, g.dy, 24)) continue;
      canvas.drawOval(
          Rect.fromCenter(center: g.translate(2, 6), width: 16, height: 7),
          _fill..color = Colors.black.withValues(alpha: 0.35));
      canvas.drawCircle(g, 7, _fill..color = const Color(0xFF2E3A2A));
      canvas.drawCircle(g.translate(-2, -2), 3,
          _fill..color = const Color(0xFF6A7A55));
      canvas.drawCircle(
          g, 7, _stroke..color = const Color(0xFF8FE07A)..strokeWidth = 1.5);
    }
  }

  // --------------------------------------------------------------- players
  void _drawPlayers(Canvas canvas, bool Function(double, double, [double]) vis) {
    for (final p in c.players) {
      if (!p.ready) continue; // people still in the lobby aren't in the world
      final pos = _pos[p.id] ?? Offset(p.x, p.y);
      if (!vis(pos.dx, pos.dy, kPlayerRadius * 3)) continue;
      final mine = p.id == c.myId;

      if (!p.alive) {
        canvas.drawOval(
            Rect.fromCenter(
                center: pos, width: kPlayerRadius * 2.2, height: kPlayerRadius),
            _fill..color = Colors.black.withValues(alpha: 0.4));
        continue;
      }

      final outfit = mine
          ? Profile.instance.outfitColor
          : Color(kOutfitColors[p.id % kOutfitColors.length]);
      final skin = mine
          ? Profile.instance.skinColor
          : Color(kSkinTones[p.id % kSkinTones.length]);
      final accessory =
          mine ? Profile.instance.accessory : p.id % kAccessoryNames.length;
      final weapon = WeaponId.values[p.wi.clamp(0, WeaponId.values.length - 1)];
      final hero = mine ? Profile.instance.hero : c.heroOf(p.id) % kHeroes.length;
      final aim = _aims[p.id] ?? p.aim;

      // grounded shadow, matching the map's single light direction
      canvas.drawOval(
          Rect.fromCenter(
              center: pos.translate(4, kPlayerRadius * 0.62),
              width: kPlayerRadius * 2.1,
              height: kPlayerRadius * 0.9),
          _fill..color = Colors.black.withValues(alpha: 0.4));

      if (mine) {
        canvas.drawCircle(
            pos,
            kPlayerRadius + 8,
            _stroke
              ..color = kSafeEdge.withValues(alpha: 0.55)
              ..strokeWidth = 2.5);
      }
      drawOperator(canvas, pos, kPlayerRadius, aim, aim, outfit, skin,
          accessory, weapon,
          fill: _fill,
          stroke: _stroke,
          walk: 0,
          hero: hero,
          vest: p.vest > 0,
          helmet: p.helmet > 0);

      if (p.shield) {
        canvas.drawCircle(pos, kPlayerRadius * 1.5,
            _fill..color = kSafeEdge.withValues(alpha: 0.16));
        canvas.drawCircle(pos, kPlayerRadius * 1.5,
            _stroke..color = kSafeEdge..strokeWidth = 3);
      }
    }
  }

  // ------------------------------------------------------------------- gas
  void _drawGas(Canvas canvas, double vL, double vT, double vR, double vB) {
    final gas = Path()
      ..addRect(Rect.fromLTRB(vL - 60, vT - 60, vR + 60, vB + 60))
      ..addOval(
          Rect.fromCircle(center: Offset(c.zoneX, c.zoneY), radius: c.zoneR))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(gas, _fill..color = kGasFill);
    canvas.drawCircle(
        Offset(c.zoneX, c.zoneY),
        c.zoneR,
        _stroke
          ..color = kGasEdge.withValues(alpha: 0.35)
          ..strokeWidth = 12);
    canvas.drawCircle(Offset(c.zoneX, c.zoneY), c.zoneR,
        _stroke..color = kSafeEdge..strokeWidth = 3);
  }

  // ---------------------------------------------------------------- labels
  void _drawLabels(Canvas canvas, Size size, double camX, double camY,
      double scale, bool Function(double, double, [double]) vis) {
    for (final p in c.players) {
      if (!p.alive || !p.ready) continue;
      final wp = _pos[p.id] ?? Offset(p.x, p.y);
      if (!vis(wp.dx, wp.dy, kPlayerRadius * 2)) continue;
      final sx = (wp.dx - camX) * scale + size.width / 2;
      final sy = (wp.dy - camY) * scale + size.height / 2;
      final top = sy - kPlayerRadius * scale - 18;
      const w = 46.0;
      final hpFrac = (p.hp / 100).clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(sx - w / 2, top, w, 5), const Radius.circular(3)),
        _fill..color = Colors.black54,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(sx - w / 2, top, w * hpFrac, 5),
            const Radius.circular(3)),
        _fill
          ..color = hpFrac > 0.5
              ? const Color(0xFF57E389)
              : hpFrac > 0.25
                  ? kAccent
                  : kAccent2,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: p.id == c.myId ? 'YOU' : p.name,
          style: TextStyle(
            color: p.id == c.myId ? kSafeEdge : Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(sx - tp.width / 2, top - 15));
    }
  }

  void _drawVignette(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.radial(
              Offset(size.width / 2, size.height / 2),
              math.max(size.width, size.height) * 0.75,
              [const Color(0x00000000), const Color(0x99000000)],
              [0.55, 1.0]));
  }

  @override
  bool shouldRepaint(covariant _ArenaPainter old) => true;
}
