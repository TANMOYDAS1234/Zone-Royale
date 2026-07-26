import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Grabs a `RepaintBoundary` (identified by [key]) as PNG bytes, or null.
///
/// Deliberately does NOT touch `RenderObject.debugNeedsPaint`: that getter is
/// implemented with a `late` field assigned only inside an `assert`, so in a
/// release build (asserts stripped) reading it throws a LateInitializationError.
/// Using it here silently broke image sharing in every release APK.
///
/// Instead we wait for a frame to land and retry a couple of times — if the
/// boundary genuinely isn't painted yet, `toImage` throws and we try again.
Future<Uint8List?> captureBoundary(GlobalKey key,
    {double pixelRatio = 1.6, int attempts = 2}) async {
  for (var i = 0; i < attempts; i++) {
    // let the in-flight frame finish so the boundary has painted
    await WidgetsBinding.instance.endOfFrame;
    final object = key.currentContext?.findRenderObject();
    if (object is RenderRepaintBoundary) {
      try {
        final image = await object.toImage(pixelRatio: pixelRatio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (data != null) return data.buffer.asUint8List();
      } catch (_) {
        // not painted yet (or transiently detached) — fall through and retry
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  return null;
}

/// A card that has already been captured and written to disk, ready to hand
/// straight to the share sheet.
///
/// Encoding a PNG and writing it takes a few hundred milliseconds. Doing that
/// AFTER the tap is why sharing felt broken — you press the button and nothing
/// happens for a beat. So the results screen pre-warms it the moment it
/// appears: by the time anyone reaches for SHARE the file is already there and
/// the sheet opens instantly.
class _PrewarmedCard {
  String? path;
  Object? key; // which card this belongs to
  Future<void>? inFlight;
}

final _PrewarmedCard _prewarm = _PrewarmedCard();

/// Capture [cardKey] in the background and keep the file for [shareCard].
/// Safe to call repeatedly; only the first call for a given [token] works.
void prewarmShareCard(GlobalKey cardKey,
    {required Object token, String fileStem = 'zone_royale'}) {
  if (_prewarm.key == token && (_prewarm.path != null || _prewarm.inFlight != null)) {
    return;
  }
  _prewarm
    ..key = token
    ..path = null;
  _prewarm.inFlight = () async {
    try {
      // give the screen a moment to settle so we capture the finished card
      await Future<void>.delayed(const Duration(milliseconds: 260));
      final png = await captureBoundary(cardKey, attempts: 3);
      if (png == null) return;
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/${fileStem}_$stamp.png');
      await file.writeAsBytes(png, flush: true);
      if (_prewarm.key == token) _prewarm.path = file.path;
    } catch (_) {
      // no pre-warmed file; shareCard falls back to capturing on demand
    } finally {
      _prewarm.inFlight = null;
    }
  }();
}

/// One share path for the whole game (result card, room result, anything else).
///
/// The old code swallowed every failure, so a share that didn't work looked
/// exactly like a button that did nothing. This version:
///  * captures the card, writes it to a uniquely-named cache file (a stale
///    file with the same name could be re-shared by some targets),
///  * shares image + text, and if that fails for any reason falls back to
///    text-only, then to the clipboard,
///  * ALWAYS tells the player what happened.
Future<void> shareCard(
  BuildContext context, {
  required GlobalKey cardKey,
  required String text,
  String subject = 'Zone Royale',
  String fileStem = 'zone_royale',
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String msg, {int seconds = 2}) => messenger?.showSnackBar(SnackBar(
        content: Text(msg),
        duration: Duration(seconds: seconds),
        backgroundColor: const Color(0xFF14181F),
      ));

  // Share sheets need an anchor rect on iPad; harmless (and useful) elsewhere.
  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : const Rect.fromLTWH(0, 0, 1, 1);

  // The fast path: the screen pre-warmed this card, so there is nothing to do
  // but open the sheet.
  var path = _prewarm.path;
  if (path == null && _prewarm.inFlight != null) {
    // capture started but hasn't landed — wait for it rather than starting a
    // second, competing capture
    say('Preparing your result card…', seconds: 1);
    await _prewarm.inFlight;
    path = _prewarm.path;
  }

  if (path == null) {
    say('Preparing your result card…', seconds: 1);
    Uint8List? png;
    try {
      png = await captureBoundary(cardKey);
    } catch (_) {
      png = null;
    }
    if (png != null) {
      try {
        final dir = await getTemporaryDirectory();
        final stamp = DateTime.now().millisecondsSinceEpoch;
        final file = File('${dir.path}/${fileStem}_$stamp.png');
        await file.writeAsBytes(png, flush: true);
        path = file.path;
      } catch (_) {
        path = null;
      }
    }
  }

  if (path != null) {
    try {
      final res = await SharePlus.instance.share(ShareParams(
        files: [XFile(path, mimeType: 'image/png')],
        text: text,
        subject: subject,
        sharePositionOrigin: origin,
      ));
      if (res.status == ShareResultStatus.success) return;
      if (res.status == ShareResultStatus.dismissed) return; // user backed out
    } catch (e) {
      say('Image share failed — sending text instead');
    }
  }

  // ---- text-only fallback ----
  try {
    final res = await SharePlus.instance.share(
        ShareParams(text: text, subject: subject, sharePositionOrigin: origin));
    if (res.status != ShareResultStatus.unavailable) return;
  } catch (_) {
    // no share target at all — fall through to the clipboard
  }

  await Clipboard.setData(ClipboardData(text: text));
  say('No share app found — result copied to clipboard');
}
