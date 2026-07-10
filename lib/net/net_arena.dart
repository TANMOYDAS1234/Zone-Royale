import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../game/char_art.dart';
import '../game/config.dart';
import '../game/profile.dart';
import '../game/royale_game.dart';
import '../ui/game_ui.dart' show Joystick;
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

  /// Auto-join the shared PUBLIC room with the current rules.
  Future<void> _quickMatch() async {
    _room.text = 'PUBLIC';
    await _connect();
  }

  String get _mapName =>
      _mapSel == 0 ? 'RANDOM' : kMapThemes[_mapSel - 1].name.toUpperCase();
  String get _weaponName => _weaponSel < 0
      ? 'ALL_ARMS'
      : kWeapons[kWeaponOrder[_weaponSel]]!.name.toUpperCase();

  Map<String, dynamic> _buildConfig() {
    final mode = kMatchModes[_sizeSel];
    final w = _weaponSel < 0 ? null : kWeapons[kWeaponOrder[_weaponSel]];
    final startId = _weaponSel < 0 ? WeaponId.smg : kWeaponOrder[_weaponSel];
    return {
      'world': mode.world,
      'maxPlayers': mode.players,
      'map': _mapName,
      'weapon': _weaponName,
      if (w != null) 'dmg': w.damage,
      if (w != null) 'bulletSpeed': w.bulletSpeed,
      if (w != null) 'bulletRange': w.range,
      'rounds': (_bo / 2).ceil(), // wins needed: BO1=1, BO3=2, BO5=3
      'startWi': startId.index,
      // full gun table so the server can drop real weapon loot
      'weapons': [
        for (final id in kWeaponOrder)
          {
            'i': id.index,
            'dmg': kWeapons[id]!.damage,
            'speed': kWeapons[id]!.bulletSpeed,
            'range': kWeapons[id]!.range,
          }
      ],
      'medkit': _medkit,
      'grenades': _grenades,
      'skills': _skills,
    };
  }

  String _normalizeUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('ws://') && !s.startsWith('wss://')) s = 'ws://$s';
    if (s.startsWith('ws://') && !s.substring(5).contains(':')) s = '$s:8080';
    return s;
  }

  Future<void> _connect({bool keepDeployed = false}) async {
    final url = _normalizeUrl(_server.text);
    if (url.isEmpty) return;
    final name = Profile.instance.name.trim().isEmpty
        ? 'Player'
        : Profile.instance.name.trim();
    final room = _room.text.trim().isEmpty ? 'PUBLIC' : _room.text.trim();
    // Close any existing socket first — otherwise RECONNECT leaves the old one
    // open and the server sees a second (idle) copy of you in the room.
    _client?.close();
    final c = NetClient();
    setState(() {
      _client = c;
      if (!keepDeployed) _deployed = false;
    });
    await c.connect(url, name, room,
        config: _buildConfig(),
        hero: Profile.instance.hero,
        startWi: Profile.instance.startWeapon.index);
  }

  void _startMission() => setState(() => _deployed = true);

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
      body: SafeArea(
        child: c == null
            ? _configView()
            : AnimatedBuilder(
                animation: c.rev,
                builder: (_, _) => c.status != 'live'
                    ? _statusView(c)
                    : (_deployed
                        ? _ArenaView(client: c, onLeave: _leave)
                        : _lobbyView(c)),
              ),
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
        children: [
          Text(sub,
              style: TextStyle(
                  fontFamily: _mono,
                  color: kAccent,
                  fontSize: 13,
                  letterSpacing: 3)),
          const SizedBox(height: 6),
          Text(main,
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
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                        child: _titles(
                            'ACTIVE_SESSION_CONFIG', 'CUSTOM_ROOM_COMMAND')),
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
          _fieldLabel('MAP & SECTOR'),
          _dropField(Icons.map_rounded, '$_mapName [SECTOR_${_mapSel + 1}]',
              () => setState(() =>
                  _mapSel = (_mapSel + 1) % (kMapThemes.length + 1))),
          const SizedBox(height: 6),
          _sectionLine('MATCH_RULES'),
          _fieldLabel('WEAPON TYPE'),
          _dropField(Icons.gps_fixed, _weaponName, () {
            setState(() => _weaponSel = _weaponSel >= kWeaponOrder.length - 1
                ? -1
                : _weaponSel + 1);
          }),
          const SizedBox(height: 14),
          _fieldLabel('ROUNDS'),
          _pillGroup(const ['BO1', 'BO3', 'BO5'], const [1, 3, 5], _bo,
              (v) => setState(() => _bo = v)),
          const SizedBox(height: 14),
          _fieldLabel('PLAYER LIMIT'),
          _pillGroup([
            for (final m in kMatchModes) '${m.players}'
          ], [
            for (var i = 0; i < kMatchModes.length; i++) i
          ], _sizeSel, (v) => setState(() => _sizeSel = v)),
          const SizedBox(height: 6),
          _sectionLine('EQUIPMENT_RESTRICTIONS'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _toggleChip('MEDKITS', _medkit,
                  () => setState(() => _medkit = !_medkit)),
              _toggleChip('GRENADES', _grenades,
                  () => setState(() => _grenades = !_grenades)),
              _toggleChip('HERO_SKILLS', _skills,
                  () => setState(() => _skills = !_skills)),
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
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: _titles('ROOM_${_room.text}', 'BRIEFING_ROOM')),
                    const SizedBox(height: 18),
                    _summaryCard(c),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text('CONNECTED_PLAYERS',
                            style: TextStyle(
                                fontFamily: _mono,
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 13,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('${c.players.length} / ${c.maxPlayers}',
                            style: TextStyle(
                                fontFamily: _mono,
                                color: kAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final p in c.players) _rosterTile(c, p),
                    if (c.players.length <= 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                            'Share room code “${_room.text}” so friends can join.',
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
          row('MAP', c.map),
          row('WEAPON', c.weapon),
          row('ROUNDS', 'BEST OF ${c.rounds * 2 - 1}'),
          row('PLAYER LIMIT', '${c.maxPlayers}'),
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
                    style: const TextStyle(
                        fontFamily: _mono,
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('READY   ·   WINS ${p.wins}',
                    style: TextStyle(
                        fontFamily: _mono,
                        color: const Color(0xFF57E389).withValues(alpha: 0.9),
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
        _fieldLabel('ROOM CODE  (share to squad up)'),
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
              Text('ADVANCED · SERVER',
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
            item(Icons.track_changes, 'OPERATIONS', true, null),
            // ARMORY = the Shop (guns / skins / gear)
            item(Icons.military_tech, 'ARMORY', false,
                () => _goto(Screen.shop)),
            // FACTION = your operator identity / loadout
            item(Icons.groups, 'FACTION', false,
                () => _goto(Screen.profile)),
            // INTEL = daily missions / objectives
            item(Icons.storage_rounded, 'INTEL', false,
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
  bool _skillQ = false; // one-shot: activate the hero skill next input
  Timer? _pump;

  // ---- client-side prediction (your own operator moves instantly) ----
  double _selfX = 0, _selfY = 0;
  bool _hasSelf = false;

  // ---- per-frame ticker: drives prediction + interpolation at display rate ----
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  Duration _last = Duration.zero;

  // ---- spectate / kill-cam ----
  int _specIdx = 0;

  static const double _speed = 250; // must match the server's playerSpeed

  @override
  void initState() {
    super.initState();
    // stream input to the server at a steady rate, independent of frame timing
    _pump = Timer.periodic(const Duration(milliseconds: 33), (_) {
      widget.client
          .sendInput(_move.dx, _move.dy, _aim, _fire, nade: _nadeQ, skill: _skillQ);
      _nadeQ = false;
      _skillQ = false;
    });
    _ticker = createTicker(_onFrame)..start();
  }

  @override
  void dispose() {
    _pump?.cancel();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  bool _blocked(double x, double y) {
    for (final o in widget.client.obstacles) {
      if ((x - o.x).abs() < o.w / 2 + 20 && (y - o.y).abs() < o.h / 2 + 20) {
        return true;
      }
    }
    return false;
  }

  void _onFrame(Duration now) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
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
        // reconcile with the authoritative position
        final ex = me.x - _selfX, ey = me.y - _selfY;
        final err = math.sqrt(ex * ex + ey * ey);
        if (err > 70) {
          _selfX = me.x; // teleport / respawn / big desync
          _selfY = me.y;
        } else if (err > 1.5) {
          final k = (2.0 * dt).clamp(0.0, 1.0); // gentle pull, no lag
          _selfX += ex * k;
          _selfY += ey * k;
        }
      }
    }
    _frame.value++;
  }

  /// Who the camera follows: you while alive, otherwise a spectated player.
  NetPlayer? _camTarget(NetClient c) {
    final me = c.me;
    if (me != null && me.alive) return me;
    final alive = c.players.where((p) => p.alive).toList();
    if (alive.isEmpty) return me;
    return alive[_specIdx % alive.length];
  }

  void _cycleSpectate() => setState(() => _specIdx++);

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

  Future<void> _shareResult(NetClient c) async {
    final me = c.me;
    final won = c.matchWinner != null && me != null && me.name == c.matchWinner;
    final txt = won
        ? '🏆 WINNER WINNER! I took the Zone Royale custom room — ${me.kills} kills. Beat that!'
        : '🔫 Zone Royale custom room — ${c.matchWinner} took it. ${me?.kills ?? 0} kills. Rematch?';
    try {
      await WidgetsBinding.instance.endOfFrame;
      final ctx = _shotKey.currentContext;
      if (ctx == null) throw StateError('no boundary');
      // ignore: use_build_context_synchronously  (context re-read after the await)
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      if (boundary.debugNeedsPaint) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      final image = await boundary.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('capture failed');
      final dir = await getTemporaryDirectory();
      final file = await File('${dir.path}/zone_royale_room.png')
          .writeAsBytes(data.buffer.asUint8List());
      await SharePlus.instance
          .share(ShareParams(files: [XFile(file.path)], text: txt));
    } catch (_) {
      await SharePlus.instance.share(ShareParams(text: txt)); // text fallback
    }
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
                              () => _shareResult(c))),
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

  Widget _actionButton(
      String icon, String label, Color color, bool ready, VoidCallback onTap) {
    return GestureDetector(
      onTap: ready ? onTap : null,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: ready ? color : Colors.white24, width: 3),
          boxShadow: ready
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(
                opacity: ready ? 1 : 0.4,
                child: Text(icon, style: const TextStyle(fontSize: 20))),
            Text(label,
                style: TextStyle(
                    color: ready ? color : Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    // repaint every display frame (60/120 Hz) so prediction + interpolation
    // render smoothly between the server's 30 Hz snapshots
    return AnimatedBuilder(
      animation: _frame,
      builder: (context, _) => _stack(c),
    );
  }

  Widget _stack(NetClient c) {
    final me = c.me;
    final spectating = me != null && !me.alive && c.matchWinner == null;
    final cam = _camTarget(c);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: spectating ? _cycleSpectate : null,
            child: CustomPaint(
              painter: _ArenaPainter(
                c,
                selfPos: _hasSelf && (me?.alive ?? false)
                    ? Offset(_selfX, _selfY)
                    : null,
                selfAim: _aim,
                camId: cam?.id ?? c.myId,
              ),
            ),
          ),
        ),
        // spectate banner
        if (spectating)
          Positioned(
            top: 60,
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
          top: 10,
          left: 14,
          right: 14,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _pill('ALIVE  ${c.aliveCount}'),
              if (c.rounds > 1)
                _pill('ROUND  ${c.round}/${c.rounds * 2 - 1}', color: kAccent),
              _pill('WINS  ${me?.wins ?? 0}'),
              GestureDetector(
                onTap: widget.onLeave,
                child: _pill('LEAVE', color: kAccent2),
              ),
            ],
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
        // controls (respect the player's stick size / opacity settings)
        Positioned(
          left: 22,
          bottom: 28,
          child: Joystick(
            onChange: (d) => _move = d,
            onRelease: () => _move = Offset.zero,
            accent: kSafeEdge,
            size: 132 * Profile.instance.stickScale,
            opacity: Profile.instance.stickOpacity,
          ),
        ),
        Positioned(
          right: 22,
          bottom: 28,
          child: Joystick(
            onChange: _aimStick,
            onRelease: () => _fire = false,
            accent: kAccent2,
            size: 132 * Profile.instance.stickScale,
            opacity: Profile.instance.stickOpacity,
          ),
        ),
        // grenade + skill action buttons (above the aim stick)
        Positioned(
          right: 30,
          bottom: 200,
          child: _actionButton('💣', '${me?.nades ?? 0}',
              const Color(0xFF6ABF5A), (me?.nades ?? 0) > 0, () {
            _nadeQ = true;
          }),
        ),
        Positioned(
          right: 108,
          bottom: 200,
          child: _actionButton(
              '⚡',
              (me?.cd ?? 0) > 0 ? '${me?.cd}' : 'SKILL',
              const Color(0xFFB06BFF),
              (me?.cd ?? 0) <= 0, () {
            _skillQ = true;
          }),
        ),
      ],
    );
  }

  Widget _pill(String text, {Color color = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      child: Text(text,
          style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1)),
    );
  }
}

class _ArenaPainter extends CustomPainter {
  final NetClient c;
  final Offset? selfPos; // client-predicted position of your own operator
  final double selfAim;
  final int camId; // who the camera follows (you, or a spectated player)
  _ArenaPainter(this.c, {this.selfPos, this.selfAim = 0, required this.camId});

  /// Smoothed world position: predicted for you, interpolated for everyone else.
  Offset _posOf(NetPlayer p) {
    if (p.id == c.myId && selfPos != null) return selfPos!;
    final l = c.lerpOf(p.id);
    return l == null ? Offset(p.x, p.y) : Offset(l[0], l[1]);
  }

  double _aimOf(NetPlayer p) {
    if (p.id == c.myId && selfPos != null) return selfAim;
    final l = c.lerpOf(p.id);
    return l == null ? p.aim : l[2];
  }

  // Ground tint per selected room map — so the host's map choice is visible.
  static Color _groundFor(String map) {
    switch (map.toUpperCase()) {
      case 'URBAN BUILDINGS':
      case 'URBAN':
        return const Color(0xFF15171C);
      case 'FOREST':
        return const Color(0xFF10190F);
      case 'COMPOUND':
        return const Color(0xFF17140F);
      case 'BADLANDS':
        return const Color(0xFF1B140E);
      default:
        return const Color(0xFF10141B);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // background (tinted by the room's chosen map)
    canvas.drawRect(Offset.zero & size, Paint()..color = _groundFor(c.map));

    // camera follows the (predicted/interpolated) target — you, or a spectatee
    NetPlayer? camP;
    for (final p in c.players) {
      if (p.id == camId) camP = p;
    }
    final camPos = camP == null ? Offset(c.world / 2, c.world / 2) : _posOf(camP);
    final camX = camPos.dx, camY = camPos.dy;
    final scale = size.height / kViewHeight;

    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-camX, -camY);

    // world border + grid
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = kSafeEdge.withValues(alpha: 0.5);
    canvas.drawRect(Rect.fromLTWH(0, 0, c.world, c.world), border);
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double g = 0; g <= c.world; g += 400) {
      canvas.drawLine(Offset(g, 0), Offset(g, c.world), grid);
      canvas.drawLine(Offset(0, g), Offset(c.world, g), grid);
    }

    // obstacles / cover (buildings)
    final obFill = Paint()..color = const Color(0xFF2B303B);
    final obTop = Paint()..color = const Color(0xFF3A414F);
    final obEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black.withValues(alpha: 0.5);
    for (final o in c.obstacles) {
      final rect = Rect.fromCenter(
          center: Offset(o.x, o.y), width: o.w, height: o.h);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(5));
      canvas.drawRRect(rr.shift(const Offset(0, 6)),
          Paint()..color = Colors.black.withValues(alpha: 0.35)); // drop shadow
      canvas.drawRRect(rr, obFill);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(o.w * 0.16), const Radius.circular(4)),
          obTop);
      canvas.drawRRect(rr, obEdge);
    }

    // loot pickups: weapon crates (gun-coloured box + icon) and medkits (green +)
    for (final l in c.loot) {
      final o = Offset(l.x, l.y);
      // soft glow so pickups are easy to spot
      canvas.drawCircle(o, 22,
          Paint()..color = (l.kind == 'm' ? const Color(0xFF57E389) : kAccent)
              .withValues(alpha: 0.16));
      if (l.kind == 'm') {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: o, width: 26, height: 26),
                const Radius.circular(5)),
            Paint()..color = Colors.white);
        final cross = Paint()..color = const Color(0xFFE23B3B);
        canvas.drawRect(
            Rect.fromCenter(center: o, width: 16, height: 5), cross);
        canvas.drawRect(
            Rect.fromCenter(center: o, width: 5, height: 16), cross);
      } else {
        final wid = l.wi.clamp(0, WeaponId.values.length - 1);
        final col = kWeapons[WeaponId.values[wid]]?.color ?? kAccent;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: o, width: 30, height: 24),
                const Radius.circular(5)),
            Paint()..color = const Color(0xFF20242D));
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: o, width: 30, height: 24),
                const Radius.circular(5)),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = col);
        canvas.drawRect(Rect.fromCenter(center: o, width: 16, height: 4),
            Paint()..color = col);
      }
    }

    // bullets
    final bp = Paint()..color = kAccent;
    final bg = Paint()..color = kAccent.withValues(alpha: 0.35);
    for (final b in c.bullets) {
      canvas.drawCircle(Offset(b.x, b.y), 10, bg);
      canvas.drawCircle(Offset(b.x, b.y), 4.5, bp);
    }

    // flying grenades
    for (final g in c.nades) {
      canvas.drawCircle(Offset(g.x, g.y), 14,
          Paint()..color = const Color(0xFF6ABF5A).withValues(alpha: 0.25));
      canvas.drawCircle(Offset(g.x, g.y), 7, Paint()..color = const Color(0xFF2E7D32));
      canvas.drawCircle(
          Offset(g.x, g.y),
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xFF8FE07A));
    }

    // players
    for (final p in c.players) {
      final mine = p.id == c.myId;
      final outfit = mine
          ? Profile.instance.outfitColor
          : Color(kOutfitColors[p.id % kOutfitColors.length]);
      final skin = mine
          ? Profile.instance.skinColor
          : Color(kSkinTones[p.id % kSkinTones.length]);
      final accessory =
          mine ? Profile.instance.accessory : p.id % kAccessoryNames.length;
      // weapon reflects what the player currently holds (loot can swap it)
      final weapon = WeaponId.values[p.wi.clamp(0, WeaponId.values.length - 1)];
      final hero = mine ? Profile.instance.hero : p.id % kHeroes.length;

      final pos = _posOf(p);
      final aim = _aimOf(p);

      if (!p.alive) {
        // faint fallen marker
        canvas.drawCircle(pos, kPlayerRadius * 0.9,
            Paint()..color = Colors.black.withValues(alpha: 0.35));
        continue;
      }
      drawOperator(canvas, pos, kPlayerRadius, aim, aim, outfit, skin,
          accessory, weapon,
          fill: fill, stroke: stroke, walk: 0, hero: hero);

      if (p.shield) {
        canvas.drawCircle(pos, kPlayerRadius * 1.5,
            Paint()..color = kSafeEdge.withValues(alpha: 0.18));
        canvas.drawCircle(
            pos,
            kPlayerRadius * 1.5,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = kSafeEdge);
      }
      if (mine) {
        canvas.drawCircle(
            pos,
            kPlayerRadius * 1.7,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = kSafeEdge.withValues(alpha: 0.7));
      }
    }

    // shrinking gas zone: gas fills everything outside the safe circle
    final gas = Path()
      ..addRect(Rect.fromLTWH(-2000, -2000, c.world + 4000, c.world + 4000))
      ..addOval(Rect.fromCircle(
          center: Offset(c.zoneX, c.zoneY), radius: c.zoneR))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(gas, Paint()..color = kGasFill);
    canvas.drawCircle(
        Offset(c.zoneX, c.zoneY),
        c.zoneR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = kGasEdge);
    canvas.restore();

    // screen-space overlays: names + hp bars
    for (final p in c.players) {
      if (!p.alive) continue;
      final wp = _posOf(p);
      final sx = (wp.dx - camX) * scale + size.width / 2;
      final sy = (wp.dy - camY) * scale + size.height / 2;
      final top = sy - kPlayerRadius * scale - 18;
      // hp bar
      const w = 46.0;
      final hpFrac = (p.hp / 100).clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(sx - w / 2, top, w, 5), const Radius.circular(3)),
        Paint()..color = Colors.black54,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(sx - w / 2, top, w * hpFrac, 5),
            const Radius.circular(3)),
        Paint()
          ..color = hpFrac > 0.5
              ? const Color(0xFF57E389)
              : hpFrac > 0.25
                  ? kAccent
                  : kAccent2,
      );
      // name
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

  @override
  bool shouldRepaint(covariant _ArenaPainter old) => true;
}
