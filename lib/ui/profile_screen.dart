import 'package:flutter/material.dart';

import '../game/config.dart';
import '../game/profile.dart';
import '../game/sfx.dart';
import '../game/royale_game.dart';
import 'backup_screens.dart';
import 'game_ui.dart' show ControlsEditor;
import 'quality_preview.dart';
import 'shell.dart';
import 'theme.dart';

/// PROFILE / OPERATOR CONFIG.
///
/// Two columns: the live operator on the left with their loadout, every
/// setting on the right — identity, visual signature, loadout, screen & feel,
/// controls, and a lifetime stats strip pinned to the bottom.
///
/// Everything the old profile screen could do is still here.
class ProfileScreen extends StatefulWidget {
  final RoyaleGame game;
  const ProfileScreen({super.key, required this.game});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _name =
      TextEditingController(text: Profile.instance.name);

  @override
  void dispose() {
    _saveName();
    _name.dispose();
    super.dispose();
  }

  void _saveName() {
    final n = _name.text.trim();
    Profile.instance.name = n.isEmpty ? 'You' : n;
    Profile.instance.save();
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
                    active: Screen.profile,
                  onBack: () => widget.game.screen.value = Screen.start,
                    subtitle: 'OPERATOR CONFIG'),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 5, child: _left()),
                              const SizedBox(width: 14),
                              Expanded(flex: 6, child: _settings()),
                            ],
                          )
                        : ZrScroll(child: SingleChildScrollView(
                            child: Column(children: [
                              SizedBox(height: 230, child: _left()),
                              const SizedBox(height: 12),
                              _settings(scroll: false),
                            ]),
                          )),
                  ),
                ),
                _statsStrip(),
              ],
            );
          }),
        ),
      ),
    );
  }

  /// A fingerprint of everything the preview shows, so the stage rebuilds the
  /// moment any of it changes.
  String _look() {
    final p = Profile.instance;
    return '${p.outfit}-${p.skin}-${p.accessory}-${p.hero}-${p.startWeapon.index}';
  }

  // ---------------------------------------------------------------- left
  Widget _left() {
    final p = Profile.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // NOT const: this has to rebuild every time you change a swatch,
        // chip or hero, so the preview always shows your live loadout.
        Expanded(child: ZrOperatorStage(height: 999, key: ValueKey(_look()))),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _miniStat(Icons.shield_outlined, 'ARMOUR',
                  'VEST + HELMET', ZR.secondary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _miniStat(Icons.inventory_2_outlined, 'LOADOUT',
                  '2 WEAPON SLOTS', ZR.primary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _miniStat(Icons.bolt, 'SKILL',
                  kHeroes[p.hero.clamp(0, kHeroes.length - 1)].name,
                  const Color(0xFFB06BFF)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _miniStat(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: ZR.panel(radius: 10),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: ZR.mono(8, color: Colors.white38)),
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
  }

  // ------------------------------------------------------------ settings
  Widget _settings({bool scroll = true}) {
    final p = Profile.instance;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card('IDENTITY CORE', Icons.fingerprint, [
          Text('OPERATOR ALIAS', style: ZR.mono(8, color: Colors.white38)),
          const SizedBox(height: 5),
          TextField(
            controller: _name,
            maxLength: 14,
            onChanged: (_) => _saveName(),
            style: ZR.display(20, spacing: 1),
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.35),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: BorderSide(color: ZR.line)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: BorderSide(color: ZR.line)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: ZR.primary)),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        _card('VISUAL SIGNATURE', Icons.palette_outlined, [
          Text('TACTICAL CAMOUFLAGE', style: ZR.mono(8, color: Colors.white38)),
          const SizedBox(height: 6),
          _swatches(kOutfitColors.length, (i) => Color(kOutfitColors[i]),
              p.outfit, (i) => setState(() => p.outfit = i), 'o'),
          const SizedBox(height: 10),
          Text('SKIN TONE', style: ZR.mono(8, color: Colors.white38)),
          const SizedBox(height: 6),
          _swatches(kSkinTones.length, (i) => Color(kSkinTones[i]), p.skin,
              (i) => setState(() => p.skin = i), null),
          const SizedBox(height: 10),
          Text('HEAD GEAR', style: ZR.mono(8, color: Colors.white38)),
          const SizedBox(height: 6),
          _chips(kAccessoryNames, p.accessory,
              (i) => setState(() => p.accessory = i), 'a'),
        ]),
        const SizedBox(height: 10),
        _card('COMBAT LOADOUT', Icons.gps_fixed, [
          Text('STARTING WEAPON', style: ZR.mono(8, color: Colors.white38)),
          const SizedBox(height: 6),
          _chips([for (final w in kWeaponOrder) kWeapons[w]!.name],
              kWeaponOrder.indexOf(p.startWeapon), (i) {
            setState(() => p.startWeapon = kWeaponOrder[i]);
          }, 'W'),
          const SizedBox(height: 10),
          Text('HERO', style: ZR.mono(8, color: Colors.white38)),
          const SizedBox(height: 6),
          _chips([for (final h in kHeroes) h.name], p.hero,
              (i) => setState(() => p.hero = i), 'h'),
          const SizedBox(height: 10),
          Text('FIRE MODE', style: ZR.mono(8, color: Colors.white38)),
          const SizedBox(height: 6),
          _segment(const ['AUTO', 'SINGLE'], p.fireAuto ? 0 : 1,
              (i) => setState(() => p.fireAuto = i == 0)),
        ]),
        const SizedBox(height: 10),
        // Solo difficulty lives here as well as on the home console — this is
        // where players look for it. Both write the same setting, and the bot
        // numbers below move as you switch so you can see it take effect.
        // (Custom rooms set their own difficulty in the room rules.)
        _card('SOLO DIFFICULTY', Icons.speed, [
          _segment([for (final d in kDifficulties) d.name], p.difficulty, (i) {
            setState(() => p.difficulty = i);
            p.save();
          }),
          const SizedBox(height: 4),
          Text(p.diff.tagline.toUpperCase(),
              style: ZR.mono(8, color: Colors.white30)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              for (final (k, v) in p.diff.spec)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(5),
                    border:
                        Border.all(color: ZR.primary.withValues(alpha: 0.35)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('$k ',
                        style:
                            ZR.mono(7.5, color: Colors.white38, spacing: 0.4)),
                    Text(v, style: ZR.display(13, color: ZR.primary)),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
              'Applies to solo matches. Your level also raises the bot mix, so '
              'the climb stays challenging without becoming unwinnable.',
              style: ZR.mono(8, color: Colors.white24, spacing: 0.3)),
        ]),
        const SizedBox(height: 10),
        _card('SCREEN & FEEL', Icons.tune, [
          Text('GRAPHICS FIDELITY', style: ZR.mono(8, color: Colors.white38)),
          const SizedBox(height: 6),
          _segment([for (final q in kQualities) q.name], p.quality, (i) {
            setState(() => p.quality = i);
            p.save();
          }),
          const SizedBox(height: 4),
          Text(p.gfx.tagline.toUpperCase(),
              style: ZR.mono(8, color: Colors.white30)),
          const SizedBox(height: 8),
          // A live sample of the setting: the same muzzle flash, tracers,
          // shadows and dust the match renders, so the choice is something you
          // can see rather than three words.
          QualityPreview(quality: p.quality),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              for (final (k, v) in p.gfx.spec)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color: v == 'OFF'
                            ? Colors.white12
                            : ZR.secondary.withValues(alpha: 0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('$k ',
                        style: ZR.mono(7.5, color: Colors.white38, spacing: 0.4)),
                    Text(v,
                        style: ZR.display(13,
                            color:
                                v == 'OFF' ? Colors.white30 : ZR.secondary)),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('TACTICAL SCREEN SHAKE',
                  style: ZR.mono(8, color: Colors.white38)),
              const Spacer(),
              Text(p.shake <= 0.01 ? 'OFF' : '${(p.shake * 100).round()}%',
                  style: ZR.display(15, color: ZR.primary)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3),
            child: Slider(
              value: p.shake.clamp(0.0, 1.0),
              activeColor: ZR.primary,
              onChanged: (v) => setState(() => p.shake = v),
              onChangeEnd: (_) => p.save(),
            ),
          ),
          _toggle(
              'AUTO-SWAP GUN ON PICKUP',
              p.autoSwapWeapons,
              (v) => setState(() {
                    p.autoSwapWeapons = v;
                    p.save();
                  }),
              p.autoSwapWeapons
                  ? 'ON — ground weapons replace what you hold'
                  : 'OFF — loot only fills an empty slot'),
          _toggle(
              'LEFT-HANDED CONTROLS',
              p.leftHanded,
              (v) => setState(() {
                    p.leftHanded = v;
                    p.save();
                  }),
              'Swaps the move and aim sticks'),
          const SizedBox(height: 10),
          // Music and effects are separate on purpose: plenty of players want
          // the gunfire and none of the soundtrack, or the other way round.
          _volume(
            'MENU MUSIC',
            Icons.music_note,
            p.musicVolume,
            (v) {
              setState(() => p.musicVolume = v);
              Sfx.applyMusicVolume();
            },
            () => p.save(),
          ),
          _volume(
            'GAME & UI SOUND',
            Icons.volume_up,
            p.sfxVolume,
            (v) => setState(() => p.sfxVolume = v),
            () {
              p.save();
              Sfx.tap(); // hear the level you just picked
            },
          ),
          const SizedBox(height: 8),
          ZrGhostButton(
            label: 'CUSTOMISE CONTROL PLACEMENT',
            icon: Icons.open_with,
            onTap: () {
              Sfx.select();
              Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ControlsEditor()));
            },
          ),
        ]),
        const SizedBox(height: 10),
        _card('PROGRESS & CLOUD SAVE', Icons.cloud_done, [
          Row(
            children: [
              const Icon(Icons.cloud_done, size: 14, color: ZR.success),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                    'AUTO-BACKUP IS ON — YOUR LEVEL, COINS, PURCHASES, '
                    'LOADOUT, CONTROL LAYOUT AND EVERY SETTING RESTORE '
                    'AUTOMATICALLY WHEN YOU REINSTALL OR SET UP A NEW PHONE.',
                    style: ZR.mono(8, color: Colors.white54, spacing: 0.3)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('MOVING TO ANOTHER PHONE',
              style: ZR.mono(8, color: Colors.white38)),
          const SizedBox(height: 2),
          // Spelled out, because the two buttons are a pair and neither makes
          // sense alone: one produces the code, the other consumes it.
          Text(
              'On the OLD phone tap SHOW MY CODE, then on the NEW phone tap '
              'RESTORE and paste it. Only needed across different Google '
              'accounts — a normal reinstall restores by itself.',
              style: ZR.mono(8, color: Colors.white24, spacing: 0.3)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ZrGhostButton(
                  label: '1 · SHOW MY CODE',
                  icon: Icons.qr_code_2,
                  height: 40,
                  onTap: _showBackupCode,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ZrGhostButton(
                  label: '2 · RESTORE',
                  icon: Icons.download,
                  height: 40,
                  color: ZR.primary,
                  onTap: _restoreFromCode,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Deliberately at the bottom, behind two taps. Never offered on
          // launch — that is where people tap without reading.
          GestureDetector(
            onTap: _confirmReset,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: ZR.danger.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.restart_alt, size: 14, color: ZR.danger),
                const SizedBox(width: 7),
                Text('START OVER FROM SCRATCH',
                    style: ZR.display(15, color: ZR.danger, spacing: 1)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        ZrButton(
            label: 'SAVE PROFILE',
            height: 44,
            fontSize: 20,
            onTap: () {
              _saveName();
              widget.game.screen.value = Screen.start;
            }),
      ],
    );
    return scroll ? ZrScroll(child: SingleChildScrollView(child: body)) : body;
  }

  /// A labelled volume slider that reads OFF at zero, so "no music" is an
  /// obvious state rather than a slider you assume is broken.
  Widget _volume(String label, IconData icon, double value,
      ValueChanged<double> onChanged, VoidCallback onDone) {
    final off = value <= 0.001;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(off ? Icons.volume_off : icon,
                  size: 13, color: off ? Colors.white30 : ZR.secondary),
              const SizedBox(width: 7),
              Text(label, style: ZR.mono(8, color: Colors.white38)),
              const Spacer(),
              Text(off ? 'OFF' : '${(value * 100).round()}%',
                  style: ZR.display(15,
                      color: off ? Colors.white30 : ZR.primary)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              activeColor: ZR.primary,
              inactiveColor: Colors.white12,
              onChanged: onChanged,
              onChangeEnd: (_) => onDone(),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------- cloud save
  void _toast(String msg, {Color color = ZR.primary}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      backgroundColor: ZR.surface,
      duration: const Duration(seconds: 3),
      content: Text(msg, style: ZR.display(16, color: color)),
    ));
  }

  Future<void> _showBackupCode() async {
    await showBackupCode(context);
  }

  Future<void> _restoreFromCode() async {
    final ok = await showRestoreCode(context);
    if (!mounted || !ok) return;
    setState(() {});
    _toast('PROGRESS RESTORED', color: ZR.success);
  }

  Future<void> _confirmReset() async {
    final done = await showResetFlow(context);
    if (!mounted || !done) return;
    setState(() {});
    _toast('PROGRESS RESET', color: ZR.danger);
  }

  Widget _card(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ZR.panel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: ZR.primary),
              const SizedBox(width: 8),
              Text(title, style: ZR.display(19, spacing: 1.2)),
            ],
          ),
          const SizedBox(height: 9),
          ...children,
        ],
      ),
    );
  }

  Widget _swatches(int count, Color Function(int) colorOf, int selected,
      void Function(int) onPick, String? lockPrefix) {
    final p = Profile.instance;
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (var i = 0; i < count; i++)
          Builder(builder: (_) {
            final locked =
                lockPrefix != null && !p.owns('$lockPrefix$i');
            return GestureDetector(
              onTap: locked
                  ? () => widget.game.screen.value = Screen.shop
                  : () {
                      onPick(i);
                      p.save();
                    },
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colorOf(i),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                      color: selected == i ? Colors.white : Colors.transparent,
                      width: 2),
                ),
                child: locked
                    ? Container(
                        color: Colors.black.withValues(alpha: 0.55),
                        child: const Icon(Icons.lock,
                            size: 13, color: Colors.white70),
                      )
                    : null,
              ),
            );
          }),
      ],
    );
  }

  Widget _chips(List<String> names, int selected, void Function(int) onPick,
      String? lockPrefix) {
    final p = Profile.instance;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < names.length; i++)
          Builder(builder: (_) {
            final id = lockPrefix == 'W'
                ? 'w${kWeaponOrder[i].index}'
                : '${lockPrefix ?? ''}$i';
            final locked = lockPrefix != null && !p.owns(id);
            final sel = selected == i;
            return GestureDetector(
              onTap: locked
                  ? () => widget.game.screen.value = Screen.shop
                  : () {
                      onPick(i);
                      p.save();
                    },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: sel
                      ? ZR.primary.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: sel ? ZR.primary : ZR.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (locked) ...[
                      const Icon(Icons.lock, size: 11, color: Colors.white38),
                      const SizedBox(width: 5),
                    ],
                    Text(names[i].toUpperCase(),
                        style: ZR.display(14,
                            color: locked
                                ? Colors.white38
                                : (sel ? ZR.primary : Colors.white70),
                            spacing: 0.6)),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _segment(List<String> labels, int sel, void Function(int) onSel) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () {
                Sfx.tap();
                onSel(i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel == i
                      ? ZR.primary
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sel == i ? ZR.primary : ZR.line),
                ),
                child: Text(labels[i],
                    style: ZR.display(15,
                        color: sel == i
                            ? const Color(0xFF10131A)
                            : Colors.white70,
                        spacing: 0.8)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _toggle(
      String label, bool value, ValueChanged<bool> onChanged, String hint) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: ZR.mono(8.5, color: Colors.white54, spacing: 0.8)),
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: value,
                  activeThumbColor: ZR.primary,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
          Text(hint, style: ZR.mono(8, color: Colors.white24)),
        ],
      ),
    );
  }

  Widget _statsStrip() {
    final p = Profile.instance;
    Widget stat(String label, String value, Color color) => Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: ZR.display(24, color: color, spacing: 1)),
              Text(label, style: ZR.mono(8, color: Colors.white38, spacing: 1)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        border: Border(top: BorderSide(color: ZR.line)),
      ),
      child: Row(
        children: [
          stat('TOTAL MATCHES', '${p.matches}', Colors.white),
          stat('WINS', '${p.wins}', ZR.primary),
          stat('WIN RATE', '${(p.winRate * 100).toStringAsFixed(1)}%',
              ZR.secondary),
          stat('CONFIRMED KILLS', '${p.kills}', ZR.danger),
          stat('BEST PLACING',
              p.bestPlacement == 0 ? '—' : '#${p.bestPlacement}', ZR.success),
        ],
      ),
    );
  }
}
