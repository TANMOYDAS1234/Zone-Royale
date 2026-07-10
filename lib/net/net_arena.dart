import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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

class _MultiplayerScreenState extends State<MultiplayerScreen> {
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
  bool _medkit = true, _grenades = true, _drone = false;

  static String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = math.Random();
    return List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
  }

  @override
  void dispose() {
    _client?.close();
    _server.dispose();
    _room.dispose();
    super.dispose();
  }

  String get _mapName =>
      _mapSel == 0 ? 'RANDOM' : kMapThemes[_mapSel - 1].name.toUpperCase();
  String get _weaponName => _weaponSel < 0
      ? 'ALL_ARMS'
      : kWeapons[kWeaponOrder[_weaponSel]]!.name.toUpperCase();

  Map<String, dynamic> _buildConfig() {
    final mode = kMatchModes[_sizeSel];
    final w = _weaponSel < 0 ? null : kWeapons[kWeaponOrder[_weaponSel]];
    return {
      'world': mode.world,
      'maxPlayers': mode.players,
      'map': _mapName,
      'weapon': _weaponName,
      if (w != null) 'dmg': w.damage,
      if (w != null) 'bulletSpeed': w.bulletSpeed,
      if (w != null) 'bulletRange': w.range,
      'rounds': (_bo / 2).ceil(), // wins needed: BO1=1, BO3=2, BO5=3
      'medkit': _medkit,
      'grenades': _grenades,
      'drone': _drone,
    };
  }

  String _normalizeUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('ws://') && !s.startsWith('wss://')) s = 'ws://$s';
    if (s.startsWith('ws://') && !s.substring(5).contains(':')) s = '$s:8080';
    return s;
  }

  Future<void> _connect() async {
    final url = _normalizeUrl(_server.text);
    if (url.isEmpty) return;
    final name = Profile.instance.name.trim().isEmpty
        ? 'Player'
        : Profile.instance.name.trim();
    final room = _room.text.trim().isEmpty ? 'PUBLIC' : _room.text.trim();
    final c = NetClient();
    setState(() {
      _client = c;
      _deployed = false;
    });
    await c.connect(url, name, room, config: _buildConfig());
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
            Icon(Icons.settings,
                color: Colors.white.withValues(alpha: 0.6), size: 22),
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
              _toggleChip('MEDKIT_V1', _medkit,
                  () => setState(() => _medkit = !_medkit)),
              _toggleChip('GRENADES', _grenades,
                  () => setState(() => _grenades = !_grenades)),
              _toggleChip('DRONE_INTEL', _drone,
                  () => setState(() => _drone = !_drone)),
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

class _ArenaViewState extends State<_ArenaView> {
  Offset _move = Offset.zero; // left stick (-1..1)
  double _aim = 0; // last aim angle
  bool _fire = false;
  Timer? _pump;

  @override
  void initState() {
    super.initState();
    // stream input to the server at a steady rate, independent of frame timing
    _pump = Timer.periodic(const Duration(milliseconds: 33), (_) {
      widget.client.sendInput(_move.dx, _move.dy, _aim, _fire);
    });
  }

  @override
  void dispose() {
    _pump?.cancel();
    super.dispose();
  }

  void _aimStick(Offset dir) {
    if (dir.distance > 0.2) {
      _aim = math.atan2(dir.dy, dir.dx);
      _fire = true;
    } else {
      _fire = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    final me = c.me;
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: c.rev,
            builder: (_, _) => CustomPaint(painter: _ArenaPainter(c)),
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
        // match over banner (takes priority)
        if (c.matchWinner != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('MATCH OVER',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text('${c.matchWinner} WINS'.toUpperCase(),
                        style: const TextStyle(
                            color: kAccent,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2)),
                  ],
                ),
              ),
            ),
          )
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
        // controls
        Positioned(
          left: 22,
          bottom: 28,
          child: Joystick(
            onChange: (d) => _move = d,
            onRelease: () => _move = Offset.zero,
            accent: kSafeEdge,
          ),
        ),
        Positioned(
          right: 22,
          bottom: 28,
          child: Joystick(
            onChange: _aimStick,
            onRelease: () => _fire = false,
            accent: kAccent2,
          ),
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
  _ArenaPainter(this.c);

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

    final me = c.me;
    final camX = me?.x ?? c.world / 2;
    final camY = me?.y ?? c.world / 2;
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

    // bullets
    final bp = Paint()..color = kAccent;
    final bg = Paint()..color = kAccent.withValues(alpha: 0.35);
    for (final b in c.bullets) {
      canvas.drawCircle(Offset(b.x, b.y), 10, bg);
      canvas.drawCircle(Offset(b.x, b.y), 4.5, bp);
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
      final weapon =
          mine ? Profile.instance.startWeapon : WeaponId.values[p.id % 5 + 1];
      final hero = mine ? Profile.instance.hero : p.id % kHeroes.length;

      if (!p.alive) {
        // faint fallen marker
        canvas.drawCircle(Offset(p.x, p.y), kPlayerRadius * 0.9,
            Paint()..color = Colors.black.withValues(alpha: 0.35));
        continue;
      }
      drawOperator(canvas, Offset(p.x, p.y), kPlayerRadius, p.aim, p.aim,
          outfit, skin, accessory, weapon,
          fill: fill, stroke: stroke, walk: 0, hero: hero);

      if (mine) {
        canvas.drawCircle(
            Offset(p.x, p.y),
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
      final sx = (p.x - camX) * scale + size.width / 2;
      final sy = (p.y - camY) * scale + size.height / 2;
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
