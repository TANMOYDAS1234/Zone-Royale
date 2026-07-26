import 'package:flutter/material.dart';

import '../game/config.dart';
import '../game/profile.dart';
import '../game/sfx.dart';
import '../game/royale_game.dart';
import '../net/net_arena.dart';
import 'map_select.dart';
import 'shell.dart';
import 'theme.dart';
import 'tutorial.dart';
import '../i18n/strings.dart';

/// HOME / OPERATIONS HUB.
///
/// Landscape two-column layout from the UI kit: the operator stage on the
/// left, the whole deployment console on the right. Every option the old home
/// screen had is still here — nothing was dropped in the reskin:
/// streak · difficulty · match mode · map · DROP IN · CUSTOM ROOM.
class HomeScreen extends StatefulWidget {
  final RoyaleGame game;
  const HomeScreen({super.key, required this.game});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _mode = Profile.instance.matchMode.clamp(0, kMatchModes.length - 1);

  /// Rebuild key for the operator stage — changes whenever the loadout does.
  String _look() {
    final p = Profile.instance;
    return '${p.outfit}-${p.skin}-${p.accessory}-${p.hero}-${p.startWeapon.index}';
  }

  void _drop() {
    Profile.instance.matchMode = _mode;
    Profile.instance.save();
    widget.game.startMatch(kMatchModes[_mode]);
  }

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
                  game: widget.game,
                  active: Screen.start,
                  subtitle: 'OPERATIONS HUB'),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                            flex: 5,
                            child: TutorialAnchor(
                              id: 'home.operator',
                              child: ZrOperatorStage(
                                  height: 999, key: ValueKey(_look())),
                            )),
                        const SizedBox(width: 16),
                        Expanded(flex: 6, child: _console()),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          ZrOperatorStage(height: 240, key: ValueKey(_look())),
                          const SizedBox(height: 14),
                          _console(scroll: false),
                        ],
                      ),
                    ),
            ),
          ),
          ZrBottomNav(game: widget.game, active: Screen.start),
            ],
          );
        }),
        ),
      ),
    );
  }

  Widget _console({bool scroll = true}) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _operatorCard(),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  flex: 6,
                  child: TutorialAnchor(
                      id: 'home.streak', child: _streakCard())),
              const SizedBox(width: 10),
              Expanded(
                  flex: 5,
                  child: TutorialAnchor(
                      id: 'home.difficulty', child: _difficultyCard())),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const ZrSectionLabel('MISSION PARAMETERS'),
        const SizedBox(height: 8),
        TutorialAnchor(
          id: 'home.mode',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < kMatchModes.length; i++) ...[
                _modeRow(i),
                if (i < kMatchModes.length - 1) const SizedBox(height: 7),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        TutorialAnchor(id: 'home.maps', child: _mapRow()),
        const SizedBox(height: 12),
        TutorialAnchor(
          id: 'home.drop',
          child: ZrButton(
              label: 'DROP IN', onTap: _drop, height: 48, fontSize: 24),
        ),
        const SizedBox(height: 9),
        ZrGhostButton(
          label: 'CUSTOM ROOM  ·  PLAY ONLINE',
          icon: Icons.public,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (_) => MultiplayerScreen(game: widget.game)),
          ),
        ),
      ],
    );
    return scroll ? SingleChildScrollView(child: body) : body;
  }

  // ---------------------------------------------------------------- cards
  Widget _operatorCard() {
    final p = Profile.instance;
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: ZR.panel(radius: 14),
      child: Row(
        children: [
          // rank plate
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.rankColor.withValues(alpha: 0.7)),
            ),
            child: Center(
              child: Icon(Icons.military_tech, color: p.rankColor, size: 26),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                          (p.name.trim().isEmpty ? 'OPERATOR' : p.name)
                              .toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZR.display(22, spacing: 1)),
                    ),
                    Text('RANK: ${p.rank}',
                        style: ZR.display(15, color: p.rankColor, spacing: 1)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: p.xpFraction,
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation(ZR.primary),
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(Icons.monetization_on,
                        size: 13, color: ZR.primary),
                    const SizedBox(width: 5),
                    Text('${p.coins}',
                        style: ZR.display(15, color: Colors.white)),
                    const Spacer(),
                    Text('${p.xp} / ${p.xpForNext} XP',
                        style: ZR.mono(10, color: Colors.white38)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
                color: ZR.primary, borderRadius: BorderRadius.circular(6)),
            child: Text('${p.level}',
                style: ZR.display(16, color: const Color(0xFF10131A))),
          ),
        ],
      ),
    );
  }

  Widget _streakCard() {
    final p = Profile.instance;
    final ready = p.streakReady;
    return GestureDetector(
      onTap: ready
          ? () => setState(() {
                final r = p.claimStreak();
                if (r != null) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
                    duration: const Duration(seconds: 2),
                    backgroundColor: ZR.surface,
                    content: Text('DAY ${p.streak} STREAK  ·  +${r.coins} COINS',
                        style: ZR.display(16, color: ZR.primary)),
                  ));
                }
              })
          : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration:
            ready ? ZR.panelActive(radius: 14) : ZR.panel(radius: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(ready ? Icons.card_giftcard : Icons.local_fire_department,
                    size: 15, color: ready ? ZR.primary : Colors.white38),
                const SizedBox(width: 7),
                Text(trUp('7-DAY STREAK'), style: ZR.display(16, spacing: 1)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i < p.streak.clamp(0, 7)
                            ? ZR.primaryLite
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: i < p.streak.clamp(0, 7)
                          ? const Icon(Icons.check,
                              size: 13, color: Color(0xFF10131A))
                          : Text('${i + 1}',
                              style: ZR.mono(10, color: Colors.white38)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
                ready
                    ? 'TAP TO COLLECT +${p.streakReward}'
                    : 'COLLECTED · COME BACK TOMORROW',
                style: ZR.mono(9,
                    color: ready ? ZR.primary : Colors.white30, spacing: 0.8)),
          ],
        ),
      ),
    );
  }

  Widget _difficultyCard() {
    final p = Profile.instance;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: ZR.panel(radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(trUp('DIFFICULTY'), style: ZR.display(16, spacing: 1)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < kDifficulties.length; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      Sfx.tap();
                      p.difficulty = i;
                      p.save();
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.difficulty == i
                            ? ZR.secondary.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                            color: p.difficulty == i
                                ? ZR.secondary
                                : Colors.transparent),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(trUp(kDifficulties[i].name),
                            style: ZR.display(14,
                                color: p.difficulty == i
                                    ? ZR.secondary
                                    : Colors.white60,
                                spacing: 0.8)),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(trUp(p.diff.tagline),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZR.mono(9, color: Colors.white30, spacing: 0.6)),
        ],
      ),
    );
  }

  Widget _modeRow(int i) {
    final m = kMatchModes[i];
    final sel = _mode == i;
    const icons = [Icons.groups, Icons.shield, Icons.public];
    const subs = ['FAST-PACED SKIRMISH', 'TACTICAL SQUAD FIGHT', 'FULL BATTLE ROYALE'];
    return GestureDetector(
      onTap: () {
        Sfx.select();
        setState(() => _mode = i);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: sel ? ZR.panelActive(radius: 12) : ZR.panel(radius: 12),
        child: Row(
          children: [
            Icon(icons[i % icons.length],
                size: 19, color: sel ? ZR.primary : Colors.white38),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.name,
                      style: ZR.display(19,
                          color: sel ? Colors.white : Colors.white70,
                          spacing: 1)),
                  Text(subs[i % subs.length],
                      style: ZR.mono(9, color: Colors.white30, spacing: 0.6)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: sel
                    ? ZR.primaryLite
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${m.players} PLAYERS',
                  style: ZR.display(13,
                      color: sel ? const Color(0xFF10131A) : Colors.white54)),
            ),
          ],
        ),
      ),
    );
  }

  /// Map strip: the two most recent picks plus a button into the full
  /// visual map browser.
  Widget _mapRow() {
    final p = Profile.instance;
    final picks = <int>[p.mapChoice, p.mapChoice == 1 ? 2 : 1];
    return Row(
      children: [
        for (final c in picks) ...[
          Expanded(child: _mapChip(c, p.mapChoice == c)),
          const SizedBox(width: 8),
        ],
        GestureDetector(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => MapSelectScreen(game: widget.game)));
            if (mounted) setState(() {});
          },
          child: Container(
            width: 54,
            height: 54,
            decoration: ZR.panel(radius: 12),
            child: const Icon(Icons.map_rounded, color: ZR.primary, size: 22),
          ),
        ),
      ],
    );
  }

  Widget _mapChip(int choice, bool sel) {
    final name = choice <= 0
        ? 'RANDOM'
        : kMapThemes[(choice - 1).clamp(0, kMapThemes.length - 1)].name;
    return GestureDetector(
      onTap: () => setState(() {
        Sfx.tap();
        Profile.instance.mapChoice = choice;
        Profile.instance.save();
      }),
      child: Container(
        height: 54,
        clipBehavior: Clip.antiAlias,
        decoration: sel ? ZR.panelActive(radius: 12) : ZR.panel(radius: 12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: MapThumbPainter(choice)),
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(9, 3, 9, 4),
                color: Colors.black.withValues(alpha: 0.55),
                child: Text(name,
                    style: ZR.display(14,
                        color: sel ? ZR.primary : Colors.white70, spacing: 1)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
