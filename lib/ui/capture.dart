import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';

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
    {double pixelRatio = 2.0, int attempts = 3}) async {
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
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
  return null;
}
