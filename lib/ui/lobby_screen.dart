import 'package:flutter/material.dart';

import '../game/char_art.dart';
import '../game/config.dart';
import '../game/profile.dart';
import '../game/royale_game.dart';
import '../game/sfx.dart';
import '../game/titles.dart';
import '../net/net_arena.dart';
import 'map_select.dart';
import 'shell.dart';
import 'theme.dart';

/// THE LOBBY — the first thing anyone sees.
///
/// Laid out the way every battle royale lays it out, because that layout is
/// what players already know how to read:
///
///   top      player card · currency · mail · events · settings
///   left     a rail of destinations — store, collection, events, missions
///   centre   your operator, big, on a lit stage
///   bottom   mode chips, the map card, and START
///
/// The single rule this screen exists to obey: **START is always on screen.**
/// The old console put DROP IN below the fold, so a new player — a kid — had
/// to scroll to find the only button they came for. Nothing here scrolls.
class LobbyScreen extends StatefulWidget {
  final RoyaleGame game;
  const LobbyScreen({super.key, required this.game});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late int _mode = Profile.instance.matchMode.clamp(0, kMatchModes.length - 1);

  /// How far the operator has been spun by dragging, in radians. Purely for
  /// show — you turn them to look at the kit you just bought.
  double _turn = 0;

  String _look() {
    final p = Profile.instance;
    return '${p.outfit}-${p.skin}-${p.accessory}-${p.hero}-${p.startWeapon.index}';
  }

  void _drop() {
    Profile.instance.matchMode = _mode;
    Profile.instance.save();
    widget.game.startMatch(kMatchModes[_mode]);
  }

  void _go(String screen) {
    Sfx.select();
    widget.game.screen.value = screen;
  }

  @override
  Widget build(BuildContext context) {
    return TacticalBackdrop(
      child: SafeArea(
        top: false,
        bottom: false,
        child: ZrCanvas(
          designHeight: 400,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Column(
              children: [
                _topBar(),
                const SizedBox(height: 6),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 88, child: _leftRail()),
                      const SizedBox(width: 10),
                      Expanded(child: _stage()),
                      const SizedBox(width: 10),
                      SizedBox(width: 210, child: _deployPanel()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- top bar
  Widget _topBar() {
    final p = Profile.instance;
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          // Player card: your actual operator as the avatar, your worn title
          // beside your name, and the level bar underneath. Tapping it opens
          // the profile — a card showing who you are should take you to where
          // you change who you are.
          GestureDetector(
            onTap: () => _go(Screen.profile),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 268,
              padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
              decoration: ZR.panel(
                  radius: 12, border: ZR.primary.withValues(alpha: 0.32)),
              child: Row(
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                              color: p.rankColor.withValues(alpha: 0.7)),
                        ),
                        child: CustomPaint(
                            painter: _AvatarPainter(look: _look())),
                      ),
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.85),
                            borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(6),
                                bottomLeft: Radius.circular(8)),
                          ),
                          child: Text('${p.level}',
                              style: ZR.display(13, color: p.rankColor)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(p.name.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ZR.display(18, spacing: 0.8)),
                            ),
                            const SizedBox(width: 6),
                            _titleChip(),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: p.xpFraction,
                                  minHeight: 5,
                                  backgroundColor: Colors.white10,
                                  valueColor:
                                      AlwaysStoppedAnimation(p.rankColor),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('${p.xp}/${p.xpForNext}',
                                style: ZR.mono(7, color: Colors.white38)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _currency(Icons.monetization_on, '${p.coins}', ZR.primary),
          const Spacer(),
          // the icon rail everyone expects along the top right
          _topIcon(Icons.mail_outline, 'MAIL', _inbox,
              badge: Profile.instance.streakReady),
          const SizedBox(width: 7),
          _topIcon(Icons.local_activity_outlined, 'EVENTS',
              () => _go(Screen.missions)),
          const SizedBox(width: 7),
          // PROFILE and SETTINGS went to the same place, so there is one.
          _topIcon(Icons.person_outline, 'PROFILE', () => _go(Screen.profile)),
        ],
      ),
    );
  }

  Widget _currency(IconData icon, String value, Color color) =>
      GestureDetector(
        onTap: () {
          Sfx.tap();
          _getCoins();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: ZR.panel(radius: 12, border: color.withValues(alpha: 0.35)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 7),
            Text(value, style: ZR.display(20, spacing: 0.5)),
            const SizedBox(width: 8),
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(Icons.add, size: 12, color: color),
            ),
          ],
        ),
      ));

  /// Where coins come from. Playing is listed first on purpose: the fastest
  /// way to lose a player is to make the shop feel like the only route.
  void _getCoins() {
    final p = Profile.instance;
    Widget row(IconData i, String title, String sub, Color c) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Icon(i, size: 18, color: c),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: ZR.display(17, color: Colors.white)),
                  Text(sub,
                      style: ZR.body(11, color: Colors.white54, height: 1.3)),
                ],
              ),
            ),
          ]),
        );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZR.surface,
        title: Row(children: [
          const Icon(Icons.monetization_on, color: ZR.primary, size: 20),
          const SizedBox(width: 9),
          Text('GET COINS', style: ZR.display(24)),
          const Spacer(),
          Text('${p.coins}', style: ZR.display(22, color: ZR.primary)),
        ]),
        // A landscape phone is 360dp tall before the keyboard; an unbounded
        // dialog puts its buttons on top of its own content.
        content: SizedBox(
          width: 380,
          height: 150,
          child: ZrScroll(
            child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row(Icons.play_circle_outline, 'PLAY A MATCH',
                  'Every match pays out, win or lose. A win pays about five times a loss.',
                  ZR.success),
              row(Icons.assignment_turned_in_outlined, 'DAILY MISSIONS',
                  'Three objectives a day. They reset every 24 hours.',
                  ZR.secondary),
              row(Icons.card_giftcard, 'DAILY LOGIN',
                  'Open the game each day. The bonus grows for seven days running.',
                  ZR.primary),
              const Divider(color: Colors.white12, height: 18),
              row(Icons.shopping_bag_outlined, 'COIN PACKS',
                  'Buying coins with real money is not switched on yet. It will never sell power — cosmetics only.',
                  Colors.white38),
            ],
          ),
        ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _go(Screen.missions);
            },
            child: Text('OPEN MISSIONS',
                style: ZR.display(18, color: ZR.secondary)),
          ),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child:
                  Text('CLOSE', style: ZR.display(18, color: Colors.white38))),
        ],
      ),
    );
  }

  Widget _topIcon(IconData icon, String label, VoidCallback onTap,
      {bool badge = false}) {
    return GestureDetector(
      onTap: () {
        Sfx.tap();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 52,
        height: 54,
        child: Stack(
          children: [
            Container(
              decoration: ZR.panel(radius: 11),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 19, color: Colors.white70),
                  const SizedBox(height: 2),
                  Text(label,
                      style: ZR.mono(7, color: Colors.white38, spacing: 0.4)),
                ],
              ),
            ),
            // an unread dot, so a waiting reward is visible without opening it
            if (badge)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: ZR.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: ZR.bg, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The worn title, next to the name — the only thing other players see.
  Widget _titleChip() {
    final t = titleFor(Profile.instance);
    const tierColour = [
      Color(0xFF8B8B8C),
      ZR.secondary,
      Color(0xFFB06BFF),
      ZR.primary,
    ];
    final c = tierColour[t.tier.clamp(0, 3)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: c.withValues(alpha: 0.7)),
      ),
      child: Text(t.name,
          maxLines: 1, style: ZR.display(11, color: c, spacing: 0.6)),
    );
  }

  void _inbox() {
    final p = Profile.instance;
    final ready = p.streakReady;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZR.surface,
        title: Text('INBOX', style: ZR.display(24)),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.card_giftcard,
                    size: 16, color: ready ? ZR.primary : Colors.white24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      ready
                          ? 'Daily login reward — day ${p.streak}: '
                              '+${p.streakReward} coins'
                          : "Today's login reward has been collected. "
                              'Come back tomorrow for a bigger one.',
                      style: ZR.body(12, color: Colors.white70, height: 1.4)),
                ),
              ]),
            ],
          ),
        ),
        actions: [
          if (ready)
            TextButton(
              onPressed: () {
                final r = p.claimStreak();
                Navigator.of(ctx).pop();
                if (r == null) return;
                Sfx.buy();
                setState(() {});
              },
              child: Text('COLLECT  +${p.streakReward}',
                  style: ZR.display(18, color: ZR.primary)),
            ),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('CLOSE',
                  style: ZR.display(18, color: Colors.white38))),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- left rail
  Widget _leftRail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
            child: _railCard(Icons.storefront, 'STORE', ZR.primary,
                () => _go(Screen.shop))),
        const SizedBox(height: 7),
        Expanded(
            child: _railCard(Icons.inventory_2_outlined, 'COLLECTION',
                ZR.secondary, () => _go(Screen.shop))),
        const SizedBox(height: 7),
        Expanded(
            child: _railCard(Icons.assignment_turned_in_outlined, 'MISSIONS',
                ZR.success, () => _go(Screen.missions))),
      ],
    );
  }

  Widget _railCard(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        Sfx.select();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.20),
              Colors.black.withValues(alpha: 0.55),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    maxLines: 1,
                    style: ZR.display(14, color: Colors.white, spacing: 0.8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- stage
  Widget _stage() {
    final p = Profile.instance;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The operator, large and centred — the point of the whole screen —
        // and draggable: sweep left or right to turn them and look at the
        // gear from another side.
        GestureDetector(
          onHorizontalDragUpdate: (d) =>
              setState(() => _turn += d.delta.dx * 0.012),
          onDoubleTap: () => setState(() => _turn = 0),
          behavior: HitTestBehavior.opaque,
          child: ZrOperatorStage(
              height: 999,
              showReadouts: false,
              turn: _turn,
              key: ValueKey(_look())),
        ),
        // a quiet hint the first time, so the interaction is discoverable
        if (_turn == 0)
          Positioned(
            left: 0,
            right: 0,
            top: 10,
            child: IgnorePointer(
              child: Center(
                child: Text('DRAG TO TURN',
                    style: ZR.mono(8, color: Colors.white24, spacing: 2)),
              ),
            ),
          ),
        // loadout summary along the bottom of the stage
        Positioned(
          left: 10,
          right: 10,
          bottom: 8,
          child: IgnorePointer(
            child: Row(
              children: [
                _tag(Icons.gps_fixed, kWeapons[p.startWeapon]!.name),
                const SizedBox(width: 6),
                _tag(Icons.bolt,
                    kHeroes[p.hero.clamp(0, kHeroes.length - 1)].name),
                const Spacer(),
                _tag(Icons.shield_outlined, 'VEST + HELMET'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tag(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: ZR.primary),
          const SizedBox(width: 5),
          Text(text.toUpperCase(),
              style: ZR.display(13, color: Colors.white70, spacing: 0.5)),
        ]),
      );

  // ------------------------------------------------------- deploy panel
  Widget _deployPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // mode chips
        SizedBox(
          height: 30,
          child: Row(
            children: [
              for (var i = 0; i < kMatchModes.length; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(child: _modeChip(i)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 7),
        // map card — tap to open the full map intel screen
        Expanded(child: _mapCard()),
        const SizedBox(height: 7),
        // the button this whole screen exists for
        _startButton(),
        const SizedBox(height: 6),
        SizedBox(
          height: 34,
          child: ZrGhostButton(
            label: 'PLAY WITH FRIENDS',
            icon: Icons.public,
            height: 34,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => MultiplayerScreen(game: widget.game))),
          ),
        ),
      ],
    );
  }

  Widget _modeChip(int i) {
    final m = kMatchModes[i];
    final sel = _mode == i;
    return GestureDetector(
      onTap: () {
        Sfx.tap();
        setState(() => _mode = i);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel
              ? ZR.primary.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sel ? ZR.primary : ZR.line),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(m.name,
                maxLines: 1,
                style: ZR.display(14,
                    color: sel ? ZR.primary : Colors.white60, spacing: 0.6)),
          ),
        ),
      ),
    );
  }

  Widget _mapCard() {
    final p = Profile.instance;
    final choice = p.mapChoice;
    final name = choice == 0
        ? 'RANDOM'
        : kMapThemes[(choice - 1).clamp(0, kMapThemes.length - 1)].name;
    return GestureDetector(
      onTap: () async {
        Sfx.select();
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => MapSelectScreen(game: widget.game)));
        if (mounted) setState(() {});
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: ZR.panel(radius: 12, border: ZR.secondary.withValues(alpha: 0.4)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: MapThumbPainter(choice, detail: 1.1)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(9, 5, 9, 6),
                color: Colors.black.withValues(alpha: 0.6),
                child: Row(
                  children: [
                    const Icon(Icons.map, size: 13, color: ZR.secondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZR.display(16, spacing: 0.8)),
                    ),
                    Text('CHANGE',
                        style: ZR.mono(8, color: ZR.secondary, spacing: 1)),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${kMatchModes[_mode].players} PLAYERS',
                    style: ZR.mono(8, color: Colors.white70, spacing: 0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Big, gold, bottom-right, impossible to miss — and never below the fold.
  Widget _startButton() {
    return SizedBox(
      height: 58,
      child: ZrButton(
        label: 'START',
        icon: Icons.play_arrow_rounded,
        height: 58,
        fontSize: 30,
        onTap: _drop,
      ),
    );
  }
}


/// The player's own operator, framed head-and-shoulders, for the lobby avatar.
class _AvatarPainter extends CustomPainter {
  final String look;
  const _AvatarPainter({required this.look});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Profile.instance;
    drawOperatorTile(
      canvas,
      Offset.zero & size,
      outfit: p.outfitColor,
      skin: p.skinColor,
      accessory: p.accessory,
      hero: p.hero,
      weapon: p.startWeapon,
      zoom: 1.5,
      headBias: 0.22,
      vest: true,
      helmet: true,
    );
  }

  @override
  bool shouldRepaint(covariant _AvatarPainter old) => old.look != look;
}
