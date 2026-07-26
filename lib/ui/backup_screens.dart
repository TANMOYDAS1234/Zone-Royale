import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../game/profile.dart';
import '../game/sfx.dart';
import 'theme.dart';

/// Backup / restore / reset, as full screens rather than dialogs.
///
/// A dialog with a text field is the wrong tool on a landscape phone: the
/// keyboard eats two thirds of a 720px-tall screen, the dialog shrinks to fit
/// what's left, and the field you were meant to type into disappears. These
/// are pages that put the input at the TOP, above where the keyboard opens,
/// and scroll if they still run out of room.

/// Shows the player their transfer code — the thing RESTORE on another phone
/// consumes. Copy it, or send it to yourself.
Future<void> showBackupCode(BuildContext context) async {
  final code = Profile.instance.exportCode();
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => _BackupCodeScreen(code: code),
  ));
}

/// Paste a code from another device.
Future<bool> showRestoreCode(BuildContext context) async {
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
    builder: (_) => const _RestoreScreen(),
  ));
  return ok ?? false;
}

/// Two separate, deliberate confirmations before anything is erased.
Future<bool> showResetFlow(BuildContext context) async {
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
    builder: (_) => const _ResetScreen(),
  ));
  return ok ?? false;
}

// ---------------------------------------------------------------- shared
Widget _page(BuildContext context,
    {required String title,
    required String subtitle,
    required Color accent,
    required List<Widget> children}) {
  return Scaffold(
    backgroundColor: ZR.bg,
    // the keyboard resizes the page instead of covering it
    resizeToAvoidBottomInset: true,
    body: TacticalBackdrop(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 2),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Sfx.back();
                      Navigator.of(context).maybePop();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox(
                        width: 42,
                        height: 38,
                        child: Icon(Icons.arrow_back,
                            color: Colors.white70, size: 20)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: ZR.display(24, spacing: 1.4)),
                        Text(subtitle,
                            style: ZR.mono(8.5,
                                color: Colors.white38, spacing: 0.6)),
                      ],
                    ),
                  ),
                  Icon(Icons.cloud_sync, size: 18, color: accent),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _toast(BuildContext context, String msg, {Color color = ZR.primary}) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    backgroundColor: ZR.surface,
    duration: const Duration(seconds: 3),
    content: Text(msg, style: ZR.display(16, color: color)),
  ));
}

// ------------------------------------------------------------ show code
class _BackupCodeScreen extends StatelessWidget {
  final String code;
  const _BackupCodeScreen({required this.code});

  @override
  Widget build(BuildContext context) {
    return _page(
      context,
      title: 'YOUR BACKUP CODE',
      subtitle: 'THIS IS WHAT "RESTORE" ON ANOTHER PHONE ASKS FOR',
      accent: ZR.secondary,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: ZR.panel(border: ZR.secondary.withValues(alpha: 0.4)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.info_outline, size: 13, color: ZR.secondary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                      'You do not need this for a normal reinstall — that '
                      'restores by itself. Keep it for moving to a phone on a '
                      'different Google account.',
                      style: ZR.mono(9, color: Colors.white54, spacing: 0.3)),
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                // selectable, so it can also be picked up by hand
                child: SelectableText(code,
                    style: ZR.mono(10, color: Colors.white70, spacing: 0)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ZrButton(
                label: 'COPY',
                icon: Icons.copy_all,
                height: 46,
                fontSize: 20,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (context.mounted) {
                    _toast(context, 'COPIED TO CLIPBOARD');
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ZrGhostButton(
                label: 'SEND TO MYSELF',
                icon: Icons.ios_share,
                height: 46,
                onTap: () async {
                  try {
                    await SharePlus.instance.share(ShareParams(
                      text: 'Zone Royale backup code:\n$code',
                      subject: 'Zone Royale backup code',
                    ));
                  } catch (_) {
                    if (context.mounted) {
                      _toast(context, 'COULD NOT OPEN SHARE',
                          color: ZR.danger);
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- restore
class _RestoreScreen extends StatefulWidget {
  const _RestoreScreen();

  @override
  State<_RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<_RestoreScreen> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) _toast(context, 'CLIPBOARD IS EMPTY', color: ZR.danger);
      return;
    }
    setState(() => _controller.text = text);
    Sfx.tap();
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await Profile.instance.importCode(_controller.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Sfx.buy();
      Navigator.of(context).pop(true);
    } else {
      Sfx.deny();
      _toast(context, "THAT CODE DIDN'T LOOK RIGHT", color: ZR.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final has = _controller.text.trim().isNotEmpty;
    return _page(
      context,
      title: 'RESTORE PROGRESS',
      subtitle: 'PASTE THE BACKUP CODE FROM YOUR OTHER DEVICE',
      accent: ZR.primary,
      children: [
        // PASTE first, and prominent: almost nobody types one of these by hand
        ZrButton(
          label: 'PASTE FROM CLIPBOARD',
          icon: Icons.content_paste,
          height: 46,
          fontSize: 20,
          onTap: _paste,
        ),
        const SizedBox(height: 10),
        Text('OR TYPE IT IN', style: ZR.mono(8, color: Colors.white38)),
        const SizedBox(height: 5),
        TextField(
          controller: _controller,
          maxLines: 3,
          minLines: 3,
          onChanged: (_) => setState(() {}),
          style: ZR.mono(10, color: Colors.white),
          decoration: InputDecoration(
            hintText: 'ZR1-…',
            hintStyle: ZR.mono(10, color: Colors.white24),
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.4),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: ZR.primary)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
            'Restoring replaces the progress on THIS device with the progress '
            'in the code.',
            style: ZR.mono(8.5, color: Colors.white38, spacing: 0.3)),
        const SizedBox(height: 12),
        ZrButton(
          label: _busy ? 'RESTORING…' : 'RESTORE',
          icon: Icons.download,
          height: 48,
          fontSize: 22,
          onTap: has && !_busy ? _restore : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- reset
class _ResetScreen extends StatefulWidget {
  const _ResetScreen();

  @override
  State<_ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends State<_ResetScreen> {
  /// false = first confirmation, true = the final hold-to-erase step.
  bool _second = false;

  @override
  Widget build(BuildContext context) {
    return _page(
      context,
      title: _second ? 'LAST CHANCE' : 'START OVER?',
      subtitle: _second
          ? 'STEP 2 OF 2 — HOLD THE BUTTON TO ERASE'
          : 'STEP 1 OF 2 — READ THIS FIRST',
      accent: ZR.danger,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: ZR.panel(border: ZR.danger.withValues(alpha: 0.5)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 15, color: ZR.danger),
                const SizedBox(width: 8),
                Text('THIS CANNOT BE UNDONE',
                    style: ZR.display(18, color: ZR.danger, spacing: 1)),
              ]),
              const SizedBox(height: 8),
              Text(
                  'You will lose level ${Profile.instance.level}, '
                  '${Profile.instance.coins} coins, '
                  '${Profile.instance.matches} matches of stats, and every '
                  'skin, weapon, hero and accessory you have unlocked.\n\n'
                  'Your control layout, graphics and sound settings are kept.',
                  style: ZR.body(12, color: Colors.white70, height: 1.5)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: ZR.panel(border: ZR.secondary.withValues(alpha: 0.4)),
          child: Row(children: [
            const Icon(Icons.lightbulb_outline, size: 14, color: ZR.secondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  'Copy your backup code first if there is any chance you '
                  'want this back later.',
                  style: ZR.mono(9, color: Colors.white54, spacing: 0.3)),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        if (!_second) ...[
          ZrGhostButton(
            label: 'YES, CONTINUE',
            icon: Icons.arrow_forward,
            height: 46,
            color: ZR.danger,
            onTap: () => setState(() => _second = true),
          ),
          const SizedBox(height: 10),
          ZrButton(
            label: 'KEEP MY PROGRESS',
            icon: Icons.shield,
            height: 48,
            fontSize: 22,
            onTap: () => Navigator.of(context).pop(false),
          ),
        ] else ...[
          _HoldToErase(
            onComplete: () async {
              await Profile.instance.resetProgress();
              if (context.mounted) Navigator.of(context).pop(true);
            },
          ),
          const SizedBox(height: 10),
          ZrButton(
            label: 'NO, KEEP MY PROGRESS',
            icon: Icons.shield,
            height: 48,
            fontSize: 22,
            onTap: () => Navigator.of(context).pop(false),
          ),
        ],
      ],
    );
  }
}

/// Press and hold for a full two seconds. A second tap-through is easy to do
/// by accident; a sustained hold is not — and no keyboard is involved, which
/// matters on a landscape phone.
class _HoldToErase extends StatefulWidget {
  final Future<void> Function() onComplete;
  const _HoldToErase({required this.onComplete});

  @override
  State<_HoldToErase> createState() => _HoldToEraseState();
}

class _HoldToEraseState extends State<_HoldToErase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        Sfx.deny();
        widget.onComplete();
      }
    });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        Sfx.tap();
        _c.forward();
      },
      onTapUp: (_) => _c.reverse(),
      onTapCancel: () => _c.reverse(),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ZR.danger, width: 1.6),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // the fill IS the countdown — let go and it drains back
              FractionallySizedBox(
                widthFactor: _c.value,
                child: Container(color: ZR.danger.withValues(alpha: 0.45)),
              ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.delete_forever,
                        size: 18, color: ZR.danger),
                    const SizedBox(width: 8),
                    Text(
                        _c.value <= 0.01
                            ? 'HOLD TO ERASE EVERYTHING'
                            : 'KEEP HOLDING…  ${((1 - _c.value) * 2).toStringAsFixed(1)}S',
                        style: ZR.display(19, color: Colors.white, spacing: 1)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
