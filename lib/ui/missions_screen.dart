import 'dart:async';

import 'package:flutter/material.dart';

import '../game/profile.dart';
import '../game/royale_game.dart';
import '../game/sfx.dart';
import 'shell.dart';
import 'theme.dart';

/// DAILY MISSIONS / INTEL.
///
/// Objectives with live progress, a countdown to the next rotation, and the
/// three states a mission can be in: claimable, in progress, claimed.
class MissionsScreen extends StatefulWidget {
  final RoyaleGame game;
  const MissionsScreen({super.key, required this.game});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    Profile.instance.ensureMissions();
    // the rotation countdown has to actually count
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _untilRotation {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final d = tomorrow.difference(now);
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '${h}h ${m}m ${s}s';
  }

  void _claim(int i) {
    final r = Profile.instance.claimMission(i);
    if (r == null) return;
    Sfx.buy();
    setState(() {});
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      backgroundColor: ZR.surface,
      duration: const Duration(seconds: 2),
      content: Text('CLAIMED  ·  +${r.coins} COINS  ·  +${r.xp} XP',
          style: ZR.display(16, color: ZR.primary)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = Profile.instance;
    final done = p.missions.where((m) => m.claimed).length;
    return TacticalBackdrop(
      child: SafeArea(
        top: false,
        bottom: false,
        child: ZrCanvas(
          designHeight: 400,
          child: Column(
            children: [
              ZrTopBar(
                  game: widget.game,
                  active: Screen.missions,
                  onBack: () => widget.game.screen.value = Screen.start,
                  subtitle: 'INTEL'),
              Expanded(
                child: ZrScroll(child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(done, p.missions.length),
                      const SizedBox(height: 10),
                      for (var i = 0; i < p.missions.length; i++) ...[
                        _missionRow(i, p),
                        if (i < p.missions.length - 1)
                          const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 10),
                      // IntrinsicHeight matters: _notes is a Row with
                      // crossAxisAlignment.stretch, and inside a scroll view
                      // the cross axis is UNBOUNDED — the row grew to a
                      // ridiculous height and the page scrolled far past the
                      // end of its own content.
                      IntrinsicHeight(child: _notes()),
                      const SizedBox(height: 6),
                    ],
                  ),
                )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(int done, int total) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
              color: ZR.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ZR.primary.withValues(alpha: 0.6))),
          child: const Icon(Icons.assignment, color: ZR.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('DAILY MISSIONS', style: ZR.display(28, spacing: 1.4)),
              Text(
                  'COMPLETE OBJECTIVES TO EARN TACTICAL REWARDS  ·  $done/$total DONE',
                  style: ZR.mono(9, color: Colors.white38, spacing: 0.8)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: ZR.panel(radius: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('NEXT ROTATION',
                  style: ZR.mono(8, color: Colors.white38, spacing: 1)),
              Text(_untilRotation, style: ZR.display(20, spacing: 1)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _missionRow(int i, Profile p) {
    final m = p.missions[i];
    final frac = (m.progress / m.target).clamp(0.0, 1.0);
    final ready = m.done && !m.claimed;
    const icons = [
      Icons.gps_fixed,
      Icons.emoji_events,
      Icons.sports_esports,
      Icons.workspace_premium,
      Icons.local_fire_department,
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: ready
          ? ZR.panelActive(radius: 12)
          : ZR.panel(radius: 12, border: m.claimed ? ZR.success.withValues(alpha: 0.35) : null),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ready
                  ? ZR.primary.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                  color: m.claimed
                      ? ZR.success.withValues(alpha: 0.7)
                      : (ready ? ZR.primary : Colors.white12)),
            ),
            child: Icon(
                m.claimed ? Icons.check_circle : icons[m.type.index % icons.length],
                color: m.claimed
                    ? ZR.success
                    : (ready ? ZR.primary : Colors.white54),
                size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(m.desc.toUpperCase(),
                    style: ZR.display(19,
                        color: m.claimed ? Colors.white38 : Colors.white,
                        spacing: 0.8)),
                const SizedBox(height: 5),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 15,
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        valueColor: AlwaysStoppedAnimation(
                            m.claimed ? ZR.success.withValues(alpha: 0.5) : ZR.primary),
                      ),
                    ),
                    Text('${m.progress} / ${m.target}',
                        style: ZR.display(13,
                            color: frac > 0.5
                                ? const Color(0xFF10131A)
                                : Colors.white70)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _reward(Icons.monetization_on, '+${m.rewardCoins}', ZR.primary),
              const SizedBox(height: 4),
              _reward(Icons.military_tech, '+${m.rewardXp} XP', ZR.secondary),
            ],
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 108,
            child: ready
                ? ZrButton(
                    label: 'CLAIM',
                    height: 40,
                    fontSize: 19,
                    onTap: () => _claim(i))
                : Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: m.claimed
                              ? ZR.success.withValues(alpha: 0.5)
                              : Colors.white12),
                    ),
                    child: Text(m.claimed ? 'CLAIMED' : 'IN PROGRESS',
                        style: ZR.display(15,
                            color: m.claimed ? ZR.success : Colors.white38,
                            spacing: 0.8)),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _reward(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(label, style: ZR.display(13, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _notes() {
    Widget note(IconData i, String text, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              border: Border(left: BorderSide(color: c, width: 2)),
            ),
            child: Row(
              children: [
                Icon(i, size: 13, color: c),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(text,
                      style: ZR.mono(8.5,
                          color: Colors.white54, spacing: 0.4)),
                ),
              ],
            ),
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        note(Icons.info_outline,
            'Missions reset every 24 hours.\nUnclaimed rewards are lost.',
            ZR.secondary),
        const SizedBox(width: 8),
        note(Icons.star_outline,
            'Progress counts in every mode —\nsolo, custom room and quick match.',
            ZR.primary),
        const SizedBox(width: 8),
        note(Icons.local_fire_department,
            'Play daily to keep your login\nstreak and its coin bonus alive.',
            ZR.success),
      ],
    );
  }
}
