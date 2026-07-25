import 'package:flutter/material.dart';

import '../game/config.dart';
import '../game/royale_game.dart';
import '../net/net_client.dart';
import 'map_select.dart';
import 'shell.dart';
import 'theme.dart';

/// CUSTOM ROOM COMMAND — the online setup console.
///
/// Left: a live preview of the chosen arena plus the connection read-outs.
/// Right: every rule the host controls. Nothing was dropped from the old
/// screen; it's the same settings in the new design.
class RoomConfigView extends StatelessWidget {
  final RoyaleGame game;
  final int mapSel; // 0 = RANDOM, else kMapThemes[i-1]
  final int sizeSel; // index into kMatchModes
  final int weaponSel; // -1 = ALL_ARMS
  final int bo; // 1 / 3 / 5
  final int botDiff;
  final bool medkit, grenades, skills, bots;
  final String roomCode;
  final String serverLabel;
  final int pingMs;
  final TextEditingController roomController;
  final Widget advanced;
  final VoidCallback onCycleMap;
  final VoidCallback onCycleWeapon;
  final ValueChanged<int> onBo;
  final ValueChanged<int> onSize;
  final ValueChanged<int> onBotDiff;
  final ValueChanged<String> onToggle;
  final VoidCallback onRandomCode;
  final VoidCallback onCreate;
  final VoidCallback onQuick;

  const RoomConfigView({
    super.key,
    required this.game,
    required this.mapSel,
    required this.sizeSel,
    required this.weaponSel,
    required this.bo,
    required this.botDiff,
    required this.medkit,
    required this.grenades,
    required this.skills,
    required this.bots,
    required this.roomCode,
    required this.serverLabel,
    required this.pingMs,
    required this.roomController,
    required this.advanced,
    required this.onCycleMap,
    required this.onCycleWeapon,
    required this.onBo,
    required this.onSize,
    required this.onBotDiff,
    required this.onToggle,
    required this.onRandomCode,
    required this.onCreate,
    required this.onQuick,
  });

  String get _mapName =>
      mapSel == 0 ? 'RANDOM' : kMapThemes[mapSel - 1].name.toUpperCase();
  String get _weaponName => weaponSel < 0
      ? 'ALL ARMS'
      : kWeapons[kWeaponOrder[weaponSel]]!.name.toUpperCase();

  @override
  Widget build(BuildContext context) {
    return TacticalBackdrop(
      child: SafeArea(
        top: false,
        bottom: false,
        child: ZrCanvas(
          designHeight: 400,
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth > 760;
            return Column(
              children: [
                ZrTopBar(
                  game: game,
                  active: Screen.start,
                  subtitle: 'COMMAND CONSOLE',
                  trailing: _backButton(context),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 250, child: _preview()),
                              const SizedBox(width: 14),
                              Expanded(child: _console(context)),
                            ],
                          )
                        : SingleChildScrollView(
                            child: Column(children: [
                              SizedBox(height: 190, child: _preview()),
                              const SizedBox(height: 12),
                              _console(context, scroll: false),
                            ]),
                          ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _backButton(BuildContext context) => GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ZR.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.arrow_back, size: 15, color: Colors.white70),
            const SizedBox(width: 6),
            Text('BACK', style: ZR.display(14, color: Colors.white70)),
          ]),
        ),
      );

  Widget _preview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 120,
          clipBehavior: Clip.antiAlias,
          decoration: ZR.panel(border: ZR.secondary.withValues(alpha: 0.5)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: MapThumbPainter(mapSel, detail: 1.2)),
              Positioned(
                left: 10,
                bottom: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_mapName,
                        style: ZR.display(22, color: ZR.secondary, spacing: 1)),
                    Text('ARENA ${kMatchModes[sizeSel].world.round()}u',
                        style: ZR.mono(8, color: Colors.white54)),
                  ],
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Text('CAM_PREVIEW_01',
                    style: ZR.mono(8, color: Colors.white30)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(11),
          decoration: ZR.panel(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _row('LOBBY STATUS', 'READY', ZR.success),
              _row('SERVER LATENCY',
                  pingMs == 0 ? 'MEASURING…' : '$pingMs MS', ZR.secondary),
              _row('DEPLOYMENT', kMatchModes[sizeSel].name, Colors.white),
              _row('HOST', 'YOU SET THE RULES', ZR.primary),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: ZR.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ZR.danger.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 14, color: ZR.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'ROOM RULES ARE SET BY WHOEVER OPENS THE ROOM. JOINING AN '
                    'ACTIVE ROOM INHERITS ITS RULES.',
                    style: ZR.mono(7.5, color: Colors.white54, spacing: 0.4)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String k, String v, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(k, style: ZR.mono(8.5, color: Colors.white38, spacing: 0.8)),
            const Spacer(),
            Text(v, style: ZR.display(14, color: c, spacing: 0.5)),
          ],
        ),
      );

  Widget _console(BuildContext context, {bool scroll = true}) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('CUSTOM ROOM COMMAND',
                      style: ZR.display(26, color: ZR.primary, spacing: 1.2)),
                  Text('ID: ZR-$roomCode', style: ZR.mono(9, color: Colors.white38)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('PROTOCOL', style: ZR.mono(8, color: Colors.white30)),
                Text('LOCKED SESSION', style: ZR.display(15, spacing: 0.8)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _dropField(Icons.map_rounded, 'MAP SELECTION', _mapName,
                  onCycleMap, ZR.secondary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dropField(Icons.gps_fixed, 'WEAPON PROTOCOL',
                  _weaponName, onCycleWeapon, ZR.primary),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _pillGroup('ROUNDS (MATCH LENGTH)',
                  const ['BO1', 'BO3', 'BO5'], const [1, 3, 5], bo, onBo,
                  ZR.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _pillGroup(
                  'OPERATOR CAPACITY',
                  [for (final m in kMatchModes) '${m.players}'],
                  [for (var i = 0; i < kMatchModes.length; i++) i],
                  sizeSel,
                  onSize,
                  ZR.secondary),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _pillGroup('BOT DIFFICULTY', const ['EASY', 'NORMAL', 'HARD'],
            const [0, 1, 2], botDiff, onBotDiff, ZR.primary),
        const SizedBox(height: 10),
        Text('RESTRICTED EQUIPMENT',
            style: ZR.mono(9, color: ZR.secondary, spacing: 1.2)),
        const SizedBox(height: 7),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _equipChip('MEDKITS', medkit, 'medkit'),
            _equipChip('GRENADES', grenades, 'grenades'),
            _equipChip('HERO SKILLS', skills, 'skills'),
            _equipChip('FILL WITH BOTS', bots, 'bots'),
          ],
        ),
        const SizedBox(height: 12),
        _roomCodeField(),
        const SizedBox(height: 8),
        advanced,
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ZrButton(
                  label: 'CREATE / JOIN ROOM',
                  icon: Icons.add_circle_outline,
                  height: 48,
                  fontSize: 20,
                  onTap: onCreate),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ZrGhostButton(
                  label: 'QUICK MATCH',
                  icon: Icons.rocket_launch,
                  height: 48,
                  onTap: onQuick),
            ),
          ],
        ),
      ],
    );
    return scroll ? SingleChildScrollView(child: body) : body;
  }

  Widget _dropField(IconData icon, String label, String value,
      VoidCallback onTap, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Icon(icon, size: 12, color: accent),
          const SizedBox(width: 6),
          Text(label, style: ZR.mono(9, color: accent, spacing: 1)),
        ]),
        const SizedBox(height: 5),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ZR.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZR.display(19, spacing: 0.8)),
                ),
                const Icon(Icons.expand_more, size: 18, color: Colors.white38),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _pillGroup(String label, List<String> labels, List<int> values,
      int sel, ValueChanged<int> onSel, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: ZR.mono(9, color: accent, spacing: 1)),
        const SizedBox(height: 5),
        Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 7),
              Expanded(
                child: GestureDetector(
                  onTap: () => onSel(values[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sel == values[i]
                          ? accent
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                          color: sel == values[i] ? accent : ZR.line),
                    ),
                    child: Text(labels[i],
                        style: ZR.display(17,
                            color: sel == values[i]
                                ? const Color(0xFF10131A)
                                : Colors.white70,
                            spacing: 0.8)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _equipChip(String label, bool on, String key) {
    return GestureDetector(
      onTap: () => onToggle(key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: (on ? ZR.success : ZR.danger).withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(9),
          border:
              Border.all(color: (on ? ZR.success : ZR.danger).withValues(alpha: 0.75)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(on ? Icons.check_circle : Icons.block,
                size: 13, color: on ? ZR.success : ZR.danger),
            const SizedBox(width: 7),
            Text('$label [${on ? 'ENABLED' : 'DISABLED'}]',
                style: ZR.mono(9,
                    color: on ? ZR.success : ZR.danger, spacing: 0.6)),
          ],
        ),
      ),
    );
  }

  Widget _roomCodeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('ROOM CODE  ·  SHARE TO SQUAD UP',
            style: ZR.mono(9, color: ZR.secondary, spacing: 1)),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ZR.line),
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 8, 0),
                      child: Icon(Icons.vpn_key_rounded,
                          size: 16, color: Colors.white38),
                    ),
                    Expanded(
                      child: TextField(
                        controller: roomController,
                        textCapitalization: TextCapitalization.characters,
                        style: ZR.display(20, spacing: 3),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 9),
            GestureDetector(
              onTap: onRandomCode,
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: ZR.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ZR.primary.withValues(alpha: 0.6)),
                ),
                child: const Icon(Icons.casino, color: ZR.primary, size: 19),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// MISSION CONTROL — the lobby you sit in before deploying.
class RoomLobbyView extends StatelessWidget {
  final RoyaleGame game;
  final NetClient client;
  final String roomLabel;
  final bool quick;
  final VoidCallback onStart;
  final VoidCallback onReconnect;
  final VoidCallback onLeave;
  final VoidCallback? onChangeSettings;
  const RoomLobbyView({
    super.key,
    required this.game,
    required this.client,
    required this.roomLabel,
    required this.quick,
    required this.onStart,
    required this.onReconnect,
    required this.onLeave,
    this.onChangeSettings,
  });

  static const _diffNames = ['EASY', 'NORMAL', 'HARD'];

  @override
  Widget build(BuildContext context) {
    final c = client;
    return TacticalBackdrop(
      child: SafeArea(
        top: false,
        bottom: false,
        child: ZrCanvas(
          designHeight: 400,
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth > 760;
            return Column(
              children: [
                ZrTopBar(
                    game: game,
                    active: Screen.start,
                    subtitle: 'MISSION CONTROL · ROOM $roomLabel'),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 260, child: _briefing(c)),
                              const SizedBox(width: 14),
                              Expanded(child: _roster(c)),
                            ],
                          )
                        : SingleChildScrollView(
                            child: Column(children: [
                              _briefing(c),
                              const SizedBox(height: 12),
                              _roster(c, scroll: false),
                            ]),
                          ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _briefing(NetClient c) {
    final mapSel = _mapIndex(c.map);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: ZR.panel(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text('MISSION BRIEFING', style: ZR.display(18, spacing: 1)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: ZR.secondary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(5)),
                      child: Text(quick ? 'QUICK MATCH' : 'CUSTOM ROOM',
                          style: ZR.mono(8, color: ZR.secondary)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 92,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(painter: MapThumbPainter(mapSel)),
                        Positioned(
                          left: 8,
                          bottom: 6,
                          child: Text(c.map.toUpperCase(),
                              style: ZR.display(18, spacing: 1)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Row(children: [
                  Expanded(
                      child: _stat(Icons.wifi, 'AVG PING',
                          c.pingMs == 0 ? '—' : '${c.pingMs} MS')),
                  const SizedBox(width: 7),
                  Expanded(
                      child: _stat(Icons.groups, 'LIMIT', '${c.maxPlayers}')),
                ]),
                const SizedBox(height: 7),
                Row(children: [
                  Expanded(
                      child: _stat(Icons.gps_fixed, 'WEAPON',
                          c.weapon.replaceAll('_', ' '))),
                  const SizedBox(width: 7),
                  Expanded(
                      child: _stat(Icons.timer, 'ROUNDS',
                          'BEST OF ${c.rounds * 2 - 1}')),
                ]),
                const SizedBox(height: 7),
                Row(children: [
                  Expanded(
                      child: _stat(
                          Icons.smart_toy,
                          'BOTS',
                          c.fillBots
                              ? '${_diffNames[c.botDifficulty.clamp(0, 2)]} ×${c.botTarget}'
                              : 'OFF')),
                  const SizedBox(width: 7),
                  Expanded(
                      child: _stat(Icons.inventory_2, 'EQUIPMENT',
                          _equipSummary(c))),
                ]),
                if (c.serverOutdated) ...[
                  const SizedBox(height: 9),
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: ZR.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: ZR.danger),
                    ),
                    child: Text(
                        'SERVER IS RUNNING AN OLDER BUILD — REDEPLOY IT TO PLAY',
                        style: ZR.mono(8, color: Colors.white70)),
                  ),
                ],
                const SizedBox(height: 10),
                if (onChangeSettings != null) ...[
                  ZrGhostButton(
                      label: 'CHANGE SETTINGS',
                      icon: Icons.tune,
                      height: 40,
                      onTap: onChangeSettings),
                  const SizedBox(height: 7),
                ],
                Row(children: [
                  Expanded(
                      child: ZrGhostButton(
                          label: 'RECONNECT',
                          icon: Icons.wifi_tethering,
                          height: 38,
                          color: Colors.white54,
                          onTap: onReconnect)),
                  const SizedBox(width: 7),
                  Expanded(
                      child: ZrGhostButton(
                          label: 'LEAVE',
                          icon: Icons.logout,
                          height: 38,
                          color: ZR.danger,
                          onTap: onLeave)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static int _mapIndex(String name) {
    for (var i = 0; i < kMapThemes.length; i++) {
      if (kMapThemes[i].name.toUpperCase() == name.toUpperCase()) return i + 1;
    }
    return 0;
  }

  static String _equipSummary(NetClient c) {
    final on = [
      if (c.allowMedkits) 'MED',
      if (c.allowGrenades) 'NADE',
      if (c.allowSkills) 'SKILL',
    ];
    return on.isEmpty ? 'NONE' : on.join(' · ');
  }

  Widget _stat(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: ZR.panel(radius: 9, fill: Colors.white10),
        child: Row(
          children: [
            Icon(icon, size: 13, color: ZR.secondary),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: ZR.mono(7.5, color: Colors.white38)),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZR.display(14, spacing: 0.5)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _roster(NetClient c, {bool scroll = true}) {
    final humans = c.players.where((p) => !p.bot).toList();
    final bots = c.players.where((p) => p.bot).length;
    final slots = c.maxPlayers.clamp(1, 8);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('CONNECTED OPERATORS', style: ZR.display(19, spacing: 1)),
            const Spacer(),
            Text('${humans.length} / ${c.maxPlayers}${bots > 0 ? '  +$bots BOTS' : ''}',
                style: ZR.mono(10, color: ZR.primary, spacing: 1)),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, box) {
          final cols = (box.maxWidth / 150).floor().clamp(2, 6);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: slots,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.15,
            ),
            itemBuilder: (_, i) =>
                i < humans.length ? _playerCard(c, humans[i]) : _emptySlot(),
          );
        }),
        const SizedBox(height: 10),
        ZrButton(
            label: 'START MISSION',
            icon: Icons.rocket_launch,
            height: 50,
            fontSize: 24,
            onTap: onStart),
      ],
    );
    return scroll ? SingleChildScrollView(child: body) : body;
  }

  Widget _playerCard(NetClient c, NetPlayer p) {
    final me = p.id == c.myId;
    final host = p.id == c.hostId;
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: me
          ? ZR.panelActive(radius: 12)
          : ZR.panel(radius: 12, border: Colors.white12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(kOutfitColors[p.id % kOutfitColors.length])
                      .withValues(alpha: 0.85),
                  border: Border.all(
                      color: me ? ZR.primary : Colors.white24, width: 2),
                ),
                child: const Icon(Icons.person, color: Colors.white70, size: 22),
              ),
              if (host)
                const Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(Icons.star, size: 13, color: ZR.primary),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(me ? 'YOU' : p.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZR.display(15, spacing: 0.8)),
          Text(p.ready ? 'DEPLOYED · WINS ${p.wins}' : 'IN LOBBY',
              maxLines: 1,
              style: ZR.mono(7.5,
                  color: p.ready ? ZR.success : Colors.white38)),
        ],
      ),
    );
  }

  Widget _emptySlot() => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
              style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_add_alt, size: 20, color: Colors.white24),
            const SizedBox(height: 5),
            Text('OPEN SLOT', style: ZR.mono(8, color: Colors.white24)),
          ],
        ),
      );
}
