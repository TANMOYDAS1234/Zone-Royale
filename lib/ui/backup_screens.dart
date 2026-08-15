import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../game/cloud_code.dart';
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

/// Shows the player a short code and its QR.
Future<void> showBackupCode(BuildContext context) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => const _BackupCodeScreen(),
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
class _BackupCodeScreen extends StatefulWidget {
  const _BackupCodeScreen();

  @override
  State<_BackupCodeScreen> createState() => _BackupCodeScreenState();
}

class _BackupCodeScreenState extends State<_BackupCodeScreen> {
  final _qrKey = GlobalKey();
  String? _code;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _make();
  }

  Future<void> _make() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final code = await CloudCode.upload();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _code = code;
      _error = code == null
          ? 'Could not reach the server. Check your connection and try again.'
          : null;
    });
  }

  /// Renders the QR card to a PNG the player can keep or send.
  Future<File?> _cardFile() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      final obj = _qrKey.currentContext?.findRenderObject();
      if (obj is! RenderRepaintBoundary) return null;
      final img = await obj.toImage(pixelRatio: 3.0);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (data == null) return null;
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/zone_royale_transfer_$_code.png');
      await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return f;
    } catch (_) {
      return null;
    }
  }

  /// Sends the QR card as an image, with the code in the text as a fallback
  /// for anyone whose app strips attachments.
  Future<void> _shareCard(BuildContext context, {bool withImage = true}) async {
    final f = withImage ? await _cardFile() : null;
    if (!context.mounted) return;
    try {
      await SharePlus.instance.share(ShareParams(
        files: f == null ? null : [XFile(f.path, mimeType: 'image/png')],
        text: 'Zone Royale transfer code: $_code\n'
            'Open Zone Royale > Profile > Restore, and scan or type it.',
        subject: 'Zone Royale transfer code',
      ));
    } catch (_) {
      if (context.mounted) _toast(context, 'COULD NOT SHARE', color: ZR.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _page(
      context,
      title: 'YOUR TRANSFER CODE',
      subtitle: 'SCAN THIS ON THE NEW PHONE, OR TYPE THE SIX CHARACTERS',
      accent: ZR.secondary,
      children: [
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(color: ZR.primary)),
          )
        else if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: ZR.panel(border: ZR.danger.withValues(alpha: 0.5)),
            child: Row(children: [
              const Icon(Icons.cloud_off, size: 16, color: ZR.danger),
              const SizedBox(width: 9),
              Expanded(
                child: Text(_error!,
                    style: ZR.body(12, color: Colors.white70, height: 1.4)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          ZrButton(
              label: 'TRY AGAIN',
              icon: Icons.refresh,
              height: 46,
              fontSize: 20,
              onTap: _make),
        ] else ...[
          Center(
            child: RepaintBoundary(
              key: _qrKey,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('ZONE ROYALE',
                        style: ZR.display(17,
                            color: const Color(0xFF10131A), spacing: 3)),
                    const SizedBox(height: 6),
                    // white background on purpose: scanners want maximum
                    // contrast, and a dark QR on a dark card fails often
                    QrImageView(
                      data: CloudCode.payload(_code!),
                      version: QrVersions.auto,
                      size: 104,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF10131A)),
                      dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF10131A)),
                    ),
                    const SizedBox(height: 8),
                    Text(_code!,
                        style: TextStyle(
                          fontFamily: 'Mono',
                          fontSize: 22,
                          letterSpacing: 5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF10131A),
                        )),
                    Text('VALID FOR 48 HOURS',
                        style: ZR.mono(7,
                            color: const Color(0xFF6B7280), spacing: 1.4)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Three actions on one row: the page is 360dp tall in landscape and
          // stacked full-height buttons pushed the last one off the bottom.
          SizedBox(
            height: 42,
            child: Row(
              children: [
                Expanded(
                  child: ZrButton(
                    label: 'SHARE QR',
                    icon: Icons.ios_share,
                    height: 42,
                    fontSize: 16,
                    onTap: () => _shareCard(context, withImage: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ZrGhostButton(
                    label: 'SAVE IMAGE',
                    icon: Icons.download,
                    height: 42,
                    onTap: () => _shareCard(context, withImage: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ZrGhostButton(
                    label: 'COPY CODE',
                    icon: Icons.copy_all,
                    height: 42,
                    color: Colors.white54,
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: _code!));
                      if (context.mounted) _toast(context, 'COPIED');
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
              'You do not need this for a normal reinstall — that restores by '
              'itself. Use it to move to a phone on a different Google '
              'account.',
              style: ZR.mono(8.5, color: Colors.white38, spacing: 0.3)),
        ],
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
    setState(() => _controller.text = CloudCode.parse(text) ?? text);
    Sfx.tap();
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(builder: (_) => const _ScanScreen()));
    if (code == null || !mounted) return;
    setState(() => _controller.text = code);
    _restore();
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    // A six-character code goes to the server; anything longer is a raw
    // backup blob from the old flow, which still works.
    final raw = _controller.text.trim();
    final String? err;
    if (raw.length <= 12) {
      err = await CloudCode.restore(raw);
    } else {
      err = await Profile.instance.importCode(raw)
          ? null
          : "That code didn't look right.";
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) {
      Sfx.buy();
      Navigator.of(context).pop(true);
    } else {
      Sfx.deny();
      _toast(context, err.toUpperCase(), color: ZR.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final has = _controller.text.trim().isNotEmpty;
    return _page(
      context,
      title: 'RESTORE PROGRESS',
      subtitle: 'SCAN THE QR ON YOUR OLD PHONE, OR TYPE ITS SIX CHARACTERS',
      accent: ZR.primary,
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: ZrButton(
                label: 'SCAN QR CODE',
                icon: Icons.qr_code_scanner,
                height: 46,
                fontSize: 19,
                onTap: _scan,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: ZrGhostButton(
                label: 'PASTE',
                icon: Icons.content_paste,
                height: 46,
                onTap: _paste,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('OR TYPE THE CODE', style: ZR.mono(8, color: Colors.white38)),
        const SizedBox(height: 5),
        TextField(
          controller: _controller,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
          style: TextStyle(
            fontFamily: 'Mono',
            fontSize: 24,
            letterSpacing: 8,
            color: Colors.white,
          ),
          decoration: InputDecoration(
            hintText: 'A1B2C3',
            hintStyle: TextStyle(
                fontFamily: 'Mono',
                fontSize: 24,
                letterSpacing: 8,
                color: Colors.white24),
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
            'behind the code.',
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

/// Camera scanner, with a gallery fallback for a screenshot of the QR.
class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  final MobileScannerController _c = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _found(String raw) {
    if (_done) return;
    final code = CloudCode.parse(raw);
    if (code == null) return;
    _done = true;
    Sfx.buy();
    Navigator.of(context).pop(code);
  }

  Future<void> _fromGallery() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final result = await _c.analyzeImage(file.path);
      final codes = result?.barcodes ?? const [];
      if (codes.isEmpty) {
        if (mounted) {
          _toast(context, 'NO QR CODE IN THAT IMAGE', color: ZR.danger);
        }
        return;
      }
      _found(codes.first.rawValue ?? '');
    } catch (_) {
      if (mounted) _toast(context, 'COULD NOT READ THAT IMAGE', color: ZR.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _c,
            onDetect: (capture) {
              for (final b in capture.barcodes) {
                final v = b.rawValue;
                if (v != null && v.isNotEmpty) {
                  _found(v);
                  return;
                }
              }
            },
          ),
          // a reticle, so it is obvious where to point the phone
          IgnorePointer(
            child: Center(
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  border: Border.all(color: ZR.primary, width: 2),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Sfx.back();
                        Navigator.of(context).maybePop();
                      },
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox(
                          width: 52,
                          height: 46,
                          child: Icon(Icons.arrow_back,
                              color: Colors.white, size: 22)),
                    ),
                    Text('POINT AT THE QR CODE',
                        style: ZR.display(20, spacing: 1.4)),
                  ],
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: ZrGhostButton(
                          label: 'PICK FROM GALLERY',
                          icon: Icons.photo_library_outlined,
                          height: 44,
                          onTap: _fromGallery,
                        ),
                      ),
                      const SizedBox(width: 9),
                      SizedBox(
                        width: 56,
                        child: ZrGhostButton(
                          label: '',
                          icon: Icons.flashlight_on,
                          height: 44,
                          onTap: () => _c.toggleTorch(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
