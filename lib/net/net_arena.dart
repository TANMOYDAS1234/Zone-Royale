// The pre-2.0 room/lobby builders below are superseded by RoomConfigView /
// RoomLobbyView in lib/ui/room_screens.dart. They are kept until the whole
// multiplayer flow has been re-verified on device, then deleted.
// ignore_for_file: unused_element

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
import '../ui/room_screens.dart';
import '../ui/theme.dart';
import '../ui/hud_controls.dart';
import '../ui/result_screen.dart';
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
    return RoomConfigView(
      game: widget.game ?? RoyaleGame(),
      mapSel: _mapSel,
      sizeSel: _sizeSel,
      weaponSel: _weaponSel,
      bo: _bo,
      botDiff: _botDiff,
      medkit: _medkit,
      grenades: _grenades,
      skills: _skills,
      bots: _bots,
      roomCode: _room.text,
      serverLabel: _server.text,
      pingMs: _client?.pingMs ?? 0,
      roomController: _room,
      advanced: _advancedServer(),
      onCycleMap: () =>
          _apply(() => _mapSel = (_mapSel + 1) % (kMapThemes.length + 1)),
      onCycleWeapon: () => _apply(() => _weaponSel =
          _weaponSel >= kWeaponOrder.length - 1 ? -1 : _weaponSel + 1),
      onBo: (v) => _apply(() => _bo = v),
      onSize: (v) => _apply(() => _sizeSel = v),
      onBotDiff: (v) => _apply(() => _botDiff = v),
      onToggle: (k) => _apply(() {
        switch (k) {
          case 'medkit':
            _medkit = !_medkit;
            break;
          case 'grenades':
            _grenades = !_grenades;
            break;
          case 'skills':
            _skills = !_skills;
            break;
          case 'bots':
            _bots = !_bots;
            break;
        }
      }),
      onRandomCode: () => _apply(() => _room.text = _randomCode()),
      onCreate: _connect,
      onQuick: _quickMatch,
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
    return _configView();
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
    return RoomLobbyView(
      game: widget.game ?? RoyaleGame(),
      client: c,
      roomLabel: c.roomCode.isEmpty ? _room.text : c.roomCode,
      quick: _wasQuick,
      onStart: _startMission,
      onReconnect: _connect,
      onLeave: _leave,
      onChangeSettings: (c.isHost && !c.started)
          ? () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                        backgroundColor: ZR.bg,
                        body: StatefulBuilder(
                          builder: (_, setInner) => Stack(
                            children: [
                              _configCardLive(setInner),
                              Positioned(
                                right: 18,
                                bottom: 14,
                                child: SizedBox(
                                  width: 220,
                                  child: ZrButton(
                                    label: 'APPLY TO ROOM',
                                    icon: Icons.check,
                                    height: 46,
                                    fontSize: 20,
                                    onTap: () {
                                      _client?.sendConfig(_buildConfig());
                                      Navigator.of(context).maybePop();
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )));
              if (mounted) setState(() {});
            }
          : null,
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
/// The circular tactical minimap from the mockups — the safe ring, the walls,
/// nearby contacts and you. The solo match draws the same thing from its own
/// world, so both modes show the same picture.
class _NetMiniMap extends StatelessWidget {
  final NetClient c;
  final Offset? self;
  final double size;
  const _NetMiniMap({required this.c, required this.self, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
        border: Border.all(color: ZR.primary.withValues(alpha: 0.55), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: ZR.primary.withValues(alpha: 0.18),
              blurRadius: 14,
              spreadRadius: -4)
        ],
      ),
      child: ClipOval(child: CustomPaint(painter: _NetMiniMapPainter(c, self))),
    );
  }
}

class _NetMiniMapPainter extends CustomPainter {
  final NetClient c;
  final Offset? self;
  _NetMiniMapPainter(this.c, this.self);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / c.world;
    Offset m(double x, double y) => Offset(x * s, y * s);
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()..style = PaintingStyle.stroke;

    // safe ring
    canvas.drawCircle(
        m(c.zoneX, c.zoneY),
        c.zoneR * s,
        stroke
          ..color = ZR.secondary
          ..strokeWidth = 1.5);
    canvas.drawCircle(m(c.zoneX, c.zoneY), c.zoneR * s,
        fill..color = ZR.secondary.withValues(alpha: 0.06));

    // hard cover, so the map reads as a place rather than dots on a disc
    for (final o in c.obstacles) {
      if (!o.blocks) continue;
      canvas.drawRect(
          Rect.fromLTWH(o.x * s, o.y * s, math.max(1, o.w * s),
              math.max(1, o.h * s)),
          fill..color = Colors.white.withValues(alpha: 0.16));
    }
    for (final w in c.walls) {
      canvas.drawRect(
          Rect.fromLTWH(w.x * s, w.y * s, math.max(1, w.w * s),
              math.max(1, w.h * s)),
          fill..color = ZR.tertiary.withValues(alpha: 0.7));
    }

    // contacts within detection range, exactly as the solo radar works
    final me = self;
    const detect = 780.0;
    for (final p in c.players) {
      if (!p.alive || p.id == c.myId) continue;
      if (me != null && (Offset(p.x, p.y) - me).distance > detect) continue;
      canvas.drawCircle(m(p.x, p.y), 2.4, fill..color = ZR.danger);
    }

    // you, as an amber pip with a ring
    if (me != null) {
      canvas.drawCircle(m(me.dx, me.dy), 5,
          fill..color = ZR.primary.withValues(alpha: 0.28));
      canvas.drawCircle(m(me.dx, me.dy), 2.8, fill..color = ZR.primary);
    }
  }

  @override
  bool shouldRepaint(covariant _NetMiniMapPainter old) => true;
}

/// One line of the client-derived kill feed.
class _FeedLine {
  final String killer;
  final String victim;
  final bool mine;
  double life = 5.0;
  _FeedLine(this.killer, this.victim, this.mine);
}

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
  double _worldT = 0;

  // Kill feed, killstreak banner and zone state — derived from snapshots so
  // the online HUD carries the same information the solo one does.
  final Map<int, int> _lastKills = {};
  final Map<int, bool> _lastAlive = {};
  final List<_FeedLine> _feed = [];
  String? _streakTitle;
  int _streakKills = 0;
  double _streakT = 0; // window in which further kills extend the streak
  double _bannerT = 0; // how long the banner stays up
  double _lastZoneR = 1e9;
  bool _zoneClosing = false;
  double _zoneStillT = 0; // time since the ring last moved
  double _reloadT = 0; // local reload clock, so the bar animates online too
  bool _wasReloading = false;
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
    _worldT += dt; // drives the drifting dust layer

    // HUD timers
    if (_streakT > 0) _streakT -= dt;
    if (_bannerT > 0) _bannerT -= dt;
    for (final f in _feed) {
      f.life -= dt;
    }
    _feed.removeWhere((f) => f.life <= 0);
    if (_zoneClosing) {
      _zoneStillT -= dt;
      if (_zoneStillT <= 0) _zoneClosing = false;
    }
    final meNow = c.me;
    if (meNow != null) {
      final r = meNow.reloading;
      if (r && !_wasReloading) {
        _reloadT = kWeapons[WeaponId.values[
                    meNow.wi.clamp(0, WeaponId.values.length - 1)]]!
                .reloadTime;
      } else if (r && _reloadT > 0) {
        _reloadT -= dt;
      }
      _wasReloading = r;
    }

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

    // Kill feed and killstreaks, derived on the client.
    //
    // The server sends kill *counts*, not kill events, so a death is matched
    // to whoever's tally went up on the same tick. That is exactly right in
    // every normal case and, at worst, credits a simultaneous double-kill to
    // one of two candidates — a far better trade than shipping no feed at all.
    final risers = <NetPlayer>[];
    for (final p in c.players) {
      final prev = _lastKills[p.id];
      if (prev != null && p.kills > prev) risers.add(p);
      _lastKills[p.id] = p.kills;
    }
    for (final p in c.players) {
      final was = _lastAlive[p.id];
      _lastAlive[p.id] = p.alive;
      if (was != true || p.alive) continue;
      final killer = risers.isEmpty
          ? null
          : risers.reduce((a, b) => a.id == c.myId ? a : b);
      _feed.insert(
          0,
          _FeedLine(killer?.name ?? 'THE ZONE', p.name,
              killer != null && killer.id == c.myId));
      // three lines max: the feed shares the top-left corner with the health
      // bars, and a five-deep feed grows right into them
      if (_feed.length > 3) _feed.removeLast();
    }
    // my own streak — same thresholds the solo match uses
    final mine = risers.where((p) => p.id == c.myId).length;
    if (mine > 0) {
      if (_streakT <= 0) _streakKills = 0;
      _streakKills += mine;
      _streakT = 4.0;
      if (_streakKills >= 2) {
        _streakTitle = switch (_streakKills) {
          2 => 'DOUBLE KILL',
          3 => 'TRIPLE KILL',
          4 => 'RAMPAGE',
          _ => 'UNSTOPPABLE',
        };
        _bannerT = 2.2;
      }
    }

    // the ring is "closing" whenever it is actually shrinking
    if (c.zoneR < _lastZoneR - 0.05) {
      _zoneClosing = true;
      _zoneStillT = 1.2;
    }
    _lastZoneR = c.zoneR;
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
      final gfx = Profile.instance.gfx;
      for (var i = 0; i < (3 * gfx.fx).round().clamp(1, 6); i++) {
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
      final gfx = Profile.instance.gfx;
      for (var i = 0; i < (22 * gfx.fx).round().clamp(6, 44); i++) {
        final a = _rng.nextDouble() * math.pi * 2;
        final sp = 90 + _rng.nextDouble() * 300;
        _fx.add(_Fx(b, Offset(math.cos(a) * sp, math.sin(a) * sp),
            0.28 + _rng.nextDouble() * 0.35, 6,
            i.isEven ? const Color(0xFFFFB020) : const Color(0xFFFF5A2A)));
      }
      for (var i = 0; i < (8 * gfx.fx).round().clamp(2, 16); i++) {
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
  // (kHeroes' element type is named Hero, which collides with the Flutter
  // widget of that name, so these read it without naming the type.)
  Color _heroColor() =>
      Color(kHeroes[Profile.instance.hero.clamp(0, kHeroes.length - 1)].color);
  double _heroCooldown() =>
      kHeroes[Profile.instance.hero.clamp(0, kHeroes.length - 1)].cooldown;

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
    // top of the lobby on kills — the same rule the solo screen uses
    final best = c.players.fold<int>(0, (m, p) => p.kills > m ? p.kills : m);
    return Positioned.fill(
      child: MatchResultView(
        cardKey: _shotKey,
        onBack: widget.onLeave,
        result: MatchResult(
          won: won,
          mode: c.rounds > 1 ? 'CUSTOM ROOM' : 'QUICK MATCH',
          placement: won ? '#1' : null,
          headline: won ? 'WINNER WINNER' : 'MATCH OVER',
          subtitle: '${c.matchWinner ?? '—'} WINS'.toUpperCase(),
          mvp: me != null && me.kills > 0 && me.kills >= best,
          stats: [
            ('KILLS', '${me?.kills ?? 0}'),
            ('ROUNDS WON', '${me?.wins ?? 0}'),
            ('OPERATORS', '${c.players.length}'),
            ('PING', c.pingMs == 0 ? '—' : '${c.pingMs} MS'),
          ],
        ),
        actions: [
          Expanded(
            child: ZrGhostButton(
                label: 'SHARE',
                icon: Icons.ios_share,
                height: 46,
                color: ZR.secondary,
                onTap: () => _shareResult(context, c)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ZrGhostButton(
                label: 'LEAVE ROOM',
                icon: Icons.logout,
                height: 46,
                color: Colors.white54,
                onTap: widget.onLeave),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Text('NEXT MATCH STARTS AUTOMATICALLY…',
                  style: ZR.mono(9, color: Colors.white38, spacing: 1.4)),
            ),
          ),
        ],
      ),
    );
  }


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
                      time: _worldT,
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
    // in the fight: alive, and the match is still running
    final live = c.matchWinner == null && (me?.alive ?? false);
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
        // Top HUD — the same pills, zone strip and minimap the solo match
        // shows, in the same places, so both modes read identically.
        Positioned(
          top: 8,
          left: 12,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: widget.onLeave,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.home_rounded,
                        size: 18, color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 8),
                HudPill('${c.aliveCount}',
                    color: ZR.primary, icon: Icons.person),
                const SizedBox(width: 8),
                HudPill('${me?.kills ?? 0}',
                    color: ZR.danger, icon: Icons.gps_fixed),
                if (c.rounds > 1) ...[
                  const SizedBox(width: 8),
                  HudPill('R${c.round}/${c.rounds * 2 - 1}',
                      color: ZR.secondary, icon: Icons.flag),
                ],
                const SizedBox(width: 8),
                // measurable smoothness + network health
                HudPill('$_fps',
                    icon: Icons.speed,
                    color: _fps >= 80
                        ? ZR.success
                        : (_fps >= 50 ? ZR.primary : ZR.danger)),
                const SizedBox(width: 8),
                HudPill(c.pingMs == 0 ? '—' : '${c.pingMs}',
                    icon: Icons.wifi,
                    color: c.pingMs == 0
                        ? Colors.white54
                        : (c.pingMs < 100
                            ? ZR.success
                            : (c.pingMs < 200 ? ZR.primary : ZR.danger))),
                const Spacer(),
                _NetMiniMap(
                    c: c,
                    self: _hasSelf ? Offset(_selfX, _selfY) : null,
                    size: size.width > size.height ? 82 : 104),
              ],
            ),
          ),
        ),
        // zone strip, centred under the top row
        Positioned(
          top: safe.top + 44,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: HudZoneStrip(
                closing: _zoneClosing,
                time: _zoneClosing
                    ? 'NOW'
                    : '${(c.zoneR / 100).clamp(0, 99).round()}',
                progress: 1 - (c.zoneR / (c.world * 0.94)).clamp(0.0, 1.0),
              ),
            ),
          ),
        ),
        // kill feed down the left, under the top row
        if (_feed.isNotEmpty)
          Positioned(
            left: safe.left + 14,
            top: safe.top + 52,
            child: IgnorePointer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final f in _feed)
                    HudKillFeedLine(
                        killer: f.killer.toUpperCase(),
                        victim: f.victim.toUpperCase(),
                        mine: f.mine,
                        alpha: (f.life / 1.2).clamp(0.0, 1.0)),
                ],
              ),
            ),
          ),
        // killstreak banner — the thing people screenshot
        if (_bannerT > 0 && _streakTitle != null)
          Positioned(
            top: size.height * (size.width > size.height ? 0.16 : 0.24),
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: HudStreakBanner(
                  title: _streakTitle!,
                  kills: _streakKills,
                  alpha: (_bannerT / 0.7).clamp(0.0, 1.0),
                ),
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
        // Once the match is decided nothing you press does anything, and
        // leaving the sticks and panels floating over the result card is the
        // fastest way to make a win look like a bug. Controls exist only while
        // you are actually in the fight.
        if (live) ...[
          // Controls come from the SHARED set (lib/ui/hud_controls.dart), so a
          // custom room and a solo match hand you exactly the same sticks,
          // buttons and panels in exactly the same places.
          hudPlace(
            size,
            Profile.instance.leftHanded ? 'aim' : 'move',
            HudStick(
              stickKey: const ValueKey('js-move'),
              label: 'MOVE',
              accent: ZR.secondary,
              icon: Icons.open_with,
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
              accent: ZR.danger,
              icon: Icons.gps_fixed,
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
              glyph: (me?.cd ?? 0) > 0
                  ? Text('${me?.cd}', style: ZR.display(22))
                  : Icon(_skillIcon(), size: 24, color: _heroColor()),
              label: 'READY',
              color: _heroColor(),
              ready: (me?.cd ?? 0) <= 0,
              charge: (me?.cd ?? 0) <= 0
                  ? 1
                  : 1 - ((me!.cd) / _heroCooldown()).clamp(0.0, 1.0),
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
              glyph: const Text('💣', style: TextStyle(fontSize: 17)),
              label: 'NADE',
              color: const Color(0xFF6ABF5A),
              ready: (me?.nades ?? 0) > 0,
              count: '${me?.nades ?? 0}',
              charge: (me?.nades ?? 0) > 0 ? 1 : 0,
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
                width: 22,
                height: 15,
                child: CustomPaint(
                    painter: ShieldWallGlyph(lit: (me?.walls ?? 0) > 0)),
              ),
              label: 'WALL',
              color: ZR.tertiary,
              ready: (me?.walls ?? 0) > 0,
              count: '${me?.walls ?? 0}',
              charge: (me?.walls ?? 0) > 0 ? 1 : 0,
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
              // clocked locally off the weapon's own reload time, so the bar
              // fills at the real rate instead of sitting frozen at half
              reloadFrac: 1 -
                  (_reloadT /
                          kWeapons[WeaponId.values[
                                  (me?.wi ?? 5)
                                      .clamp(0, WeaponId.values.length - 1)]]!
                              .reloadTime)
                      .clamp(0.0, 1.0),
              onTap: () => _reloadQ = true,
            ),
            140,
            84,
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
            80,
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
              // this used to be a dead control online — it now flips the same
              // setting the solo match reads
              onTap: () {
                setState(() {
                  Profile.instance.fireAuto = !Profile.instance.fireAuto;
                });
                Profile.instance.save();
              },
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
            158,
            56,
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
  final double time;
  _ArenaPainter(this.c,
      {this.selfPos,
      this.selfAim = 0,
      required this.camId,
      required this.tracers,
      required this.fx,
      this.time = 0});

  // Smoothed world transforms, computed once per frame: predicted for you,
  // interpolated for everyone else.
  final Map<int, Offset> _pos = {};
  final Map<int, double> _aims = {};

  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  /// Same fidelity setting the solo match honours — read once per frame so
  /// SMOOTH / BALANCED / ULTRA look identical in both modes.
  Quality _q = kQualities[1];
  final Paint _glow = Paint()
    ..style = PaintingStyle.fill
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);

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
    _q = Profile.instance.gfx;

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

    _drawAtmosphere(canvas, size);
    _drawLabels(canvas, size, camX, camY, scale, onScreen);
    _drawVignette(canvas, size);
  }

  /// The same drifting dust the solo match has, in screen space between the
  /// camera and the world. Off at SMOOTH, which is most of what makes that
  /// level feel lighter.
  void _drawAtmosphere(Canvas canvas, Size size) {
    if (!_q.weather) return;
    final n = (34 * _q.detail).round().clamp(8, 60);
    for (var i = 0; i < n; i++) {
      final seed = i * 37.0;
      final speed = 12 + (i % 5) * 7;
      final x = ((seed * 13.7 + time * speed) % (size.width + 60)) - 30;
      final y = (seed * 29.3 + math.sin(time * 0.5 + i) * 14) % size.height;
      final r = 0.8 + (i % 4) * 0.55;
      canvas.drawCircle(Offset(x, y), r,
          _fill..color = Colors.white.withValues(alpha: 0.05 + (i % 3) * 0.018));
    }
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
    // is what stops the floor reading as flat coloured paper. A bigger cell at
    // SMOOTH means fewer patches per screen — the same knob the solo map uses.
    final cell = 160.0 / _q.detail.clamp(0.35, 1.4);
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
      // Same rule as the solo match: a canopy with someone under it turns
      // see-through, so a bush fight stays readable. Concealment still works —
      // you cannot be shot through it — it just stops being invisible.
      var hiding = false;
      for (final p in c.players) {
        if (!p.alive) continue;
        final pos = _pos[p.id] ?? Offset(p.x, p.y);
        if (pos.dx >= o.x - rad &&
            pos.dx <= o.x + rad &&
            pos.dy >= o.y - rad &&
            pos.dy <= o.y + rad) {
          hiding = true;
          break;
        }
      }
      final k = hiding ? 0.34 : 1.0;
      Color veil(int argb) {
        final base = Color(argb);
        return base.withValues(alpha: base.a * k);
      }

      canvas.drawOval(
          Rect.fromCenter(
              center: centre.translate(6, 9),
              width: rad * 2.1,
              height: rad * 1.4),
          _fill..color = Colors.black.withValues(alpha: 0.3 * k));
      if (hiding) {
        canvas.drawCircle(
            centre,
            rad,
            _stroke
              ..color = ZR.tertiary.withValues(alpha: 0.5)
              ..strokeWidth = 1.6);
      }
      canvas.drawCircle(centre, rad, _fill..color = veil(0xCC123F1E));
      canvas.drawCircle(centre.translate(-rad * 0.2, -rad * 0.2), rad * 0.75,
          _fill..color = veil(0xCC1F6B34));
      canvas.drawCircle(centre.translate(-rad * 0.34, -rad * 0.36), rad * 0.36,
          _fill..color = veil(0x662FB85A));
    }
  }

  // ------------------------------------------------------------------ loot
  void _drawLoot(Canvas canvas, bool Function(double, double, [double]) vis) {
    // Ground loot is drawn with the SAME art the solo match uses — a plate
    // carrier, a helmet dome, a folded shield slab, the real gun silhouette —
    // instead of the coloured boxes this used to draw. Loot you can identify
    // at a glance is the whole point of walking over to it.
    for (final l in c.loot) {
      if (!vis(l.x, l.y, 40)) continue;
      // bob + pulse, keyed off the world position so each piece is out of
      // phase with its neighbours and the whole field doesn't breathe as one
      final bob = (l.x * 0.013 + l.y * 0.021) % 6.28;
      final o = Offset(l.x, l.y + math.sin(time * 3 + bob) * 3);
      final pulse = 0.55 + 0.45 * math.sin(time * 4 + bob);
      canvas.drawOval(
          Rect.fromCenter(center: o.translate(3, 9), width: 26, height: 10),
          _fill..color = Colors.black.withValues(alpha: 0.28));

      switch (l.kind) {
        case 0: // medkit
          canvas.drawCircle(
              o,
              15,
              _fill
                ..color =
                    const Color(0xFFFF4D5A).withValues(alpha: 0.22 * pulse));
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: o, width: 20, height: 20),
                  const Radius.circular(4)),
              _fill..color = const Color(0xFFFFFFFF));
          canvas.drawRect(Rect.fromCenter(center: o, width: 12, height: 4),
              _fill..color = const Color(0xFFE03A46));
          canvas.drawRect(Rect.fromCenter(center: o, width: 4, height: 12),
              _fill..color = const Color(0xFFE03A46));
          continue;
        case 3: // vest — plate carrier with shoulder straps
          canvas.drawCircle(
              o,
              15,
              _fill
                ..color =
                    const Color(0xFF4FA3FF).withValues(alpha: 0.2 * pulse));
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: o, width: 19, height: 22),
                  const Radius.circular(5)),
              _fill..color = const Color(0xFF2E4460));
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: o, width: 19, height: 22),
                  const Radius.circular(5)),
              _stroke
                ..color = const Color(0xFF7FC4FF)
                ..strokeWidth = 1.6);
          canvas.drawRect(Rect.fromCenter(center: o, width: 7, height: 16),
              _fill..color = const Color(0xFF4B6C93));
          continue;
        case 4: // helmet — a dome with a brow band
          canvas.drawCircle(
              o,
              15,
              _fill
                ..color =
                    const Color(0xFFFFC24B).withValues(alpha: 0.2 * pulse));
          canvas.drawArc(
              Rect.fromCenter(
                  center: o.translate(0, 2), width: 22, height: 22),
              math.pi,
              math.pi,
              true,
              _fill..color = const Color(0xFF5A6250));
          canvas.drawArc(
              Rect.fromCenter(
                  center: o.translate(0, 2), width: 22, height: 22),
              math.pi,
              math.pi,
              false,
              _stroke
                ..color = const Color(0xFFC9D6A8)
                ..strokeWidth = 1.8);
          canvas.drawRect(
              Rect.fromCenter(center: o.translate(0, 3), width: 22, height: 3),
              _fill..color = const Color(0xFF39402F));
          continue;
        case 5: // shield-wall charge — a folded slab of energy
          canvas.drawCircle(
              o,
              15,
              _fill
                ..color =
                    const Color(0xFF7FE8FF).withValues(alpha: 0.2 * pulse));
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: o, width: 24, height: 15),
                  const Radius.circular(3)),
              _fill..color = const Color(0x667FE8FF));
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: o, width: 24, height: 15),
                  const Radius.circular(3)),
              _stroke
                ..color = const Color(0xFFBFF4FF)
                ..strokeWidth = 1.6);
          _stroke.strokeWidth = 1.2;
          canvas.drawLine(o.translate(-4, -7), o.translate(-4, 7), _stroke);
          canvas.drawLine(o.translate(4, -7), o.translate(4, 7), _stroke);
          continue;
        case 6: // grenade
          canvas.drawCircle(
              o,
              13,
              _fill
                ..color =
                    const Color(0xFF6ABF5A).withValues(alpha: 0.22 * pulse));
          canvas.drawCircle(o, 8, _fill..color = const Color(0xFF3A5A32));
          canvas.drawCircle(
              o,
              8,
              _stroke
                ..color = const Color(0xFF7FCF6A)
                ..strokeWidth = 1.5);
          canvas.drawRect(
              Rect.fromCenter(center: o.translate(0, -8), width: 5, height: 4),
              _fill..color = const Color(0xFF9AA6B2));
          continue;
      }

      // weapon (kind 1) and airdrop (kind 2)
      final id = WeaponId.values[l.wi.clamp(0, WeaponId.values.length - 1)];
      final wc = kWeapons[id]!.color;
      if (l.kind == 2) {
        final beat = 0.5 + 0.5 * math.sin(time * 4);
        canvas.drawCircle(
            o, 34, _fill..color = kAccent.withValues(alpha: 0.10 + 0.10 * beat));
        canvas.drawCircle(
            o,
            24 + 4 * beat,
            _stroke
              ..color = kAccent.withValues(alpha: 0.7)
              ..strokeWidth = 2);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: o, width: 34, height: 28),
                const Radius.circular(4)),
            _fill..color = const Color(0xFF2A2F1E));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: o, width: 34, height: 28),
                const Radius.circular(4)),
            _stroke
              ..color = kAccent
              ..strokeWidth = 2);
        canvas.drawRect(Rect.fromCenter(center: o, width: 34, height: 5),
            _fill..color = kAccent.withValues(alpha: 0.85));
      } else {
        canvas.drawCircle(
            o, 15, _fill..color = wc.withValues(alpha: 0.22 * pulse));
      }
      drawGunIcon(canvas, o.translate(0, l.kind == 2 ? 1 : 0), 26, id,
          fill: _fill, stroke: _stroke);
      if (l.kind != 2) {
        canvas.drawRect(
            Rect.fromCenter(center: o.translate(0, 9), width: 22, height: 2),
            _fill..color = wc.withValues(alpha: 0.75));
      }
    }
  }

  // --------------------------------------------------------------- tracers
  void _drawTracers(
      Canvas canvas, bool Function(double, double, [double]) vis) {
    for (final t in tracers) {
      if (!vis(t.pos.dx, t.pos.dy, 30)) continue;
      final back = t.pos - t.vel * (0.022 * (0.6 + t.width));
      if (_q.bloom > 0) {
        canvas.drawLine(
            back,
            t.pos,
            Paint()
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
              ..color = t.color.withValues(alpha: 0.5 * _q.bloom)
              ..strokeWidth = 8 * t.width * _q.bloom
              ..strokeCap = StrokeCap.round);
      }
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
      if (_q.bloom > 0) {
        canvas.drawCircle(
            f.pos,
            f.size * a * 2.1 * _q.bloom,
            _glow..color = f.color.withValues(alpha: a * 0.4 * _q.bloom));
      }
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

      // Grounded shadow that reacts to movement, exactly as the solo match
      // does: the light does not move, so the shadow still falls down-right,
      // but it stretches along the direction of travel and trails behind.
      // Travel comes from the difference between the last two snapshots.
      final prev = c.prevPosOf(p.id);
      final travel = prev == null ? Offset.zero : pos - prev;
      final run = (travel.distance / 6.0).clamp(0.0, 1.0);
      final shadowAngle =
          travel.distance > 0.6 ? math.atan2(travel.dy, travel.dx) : aim;
      final trail = Offset(-math.cos(shadowAngle), -math.sin(shadowAngle)) *
          (kPlayerRadius * 0.16 * run);

      void groundShadow(double w, double h, double dx, double dy, double a) {
        canvas.save();
        canvas.translate(pos.dx + dx + trail.dx, pos.dy + dy + trail.dy);
        canvas.rotate(shadowAngle);
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset.zero,
                width: w * (1 + 0.42 * run),
                height: h * (1 - 0.16 * run)),
            _fill..color = Colors.black.withValues(alpha: a));
        canvas.restore();
      }

      if (_q.shadows) {
        groundShadow(kPlayerRadius * 2.1, kPlayerRadius * 0.9, 4,
            kPlayerRadius * 0.62, 0.4);
        groundShadow(kPlayerRadius * 1.4, kPlayerRadius * 0.58, 2,
            kPlayerRadius * 0.45, 0.24);
      } else {
        groundShadow(kPlayerRadius * 1.7, kPlayerRadius * 0.7, 2,
            kPlayerRadius * 0.62, 0.22);
      }

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
