import 'dart:convert';
import 'dart:io';

import 'profile.dart';

/// Short transfer codes, backed by the game server.
///
/// The raw backup is ~1.4KB of base64. That is too dense for a phone camera to
/// scan reliably and far too long for anyone to type, which is why the first
/// version handed people a wall of characters. Instead the profile is uploaded
/// once and the other device fetches it with six characters — small enough for
/// a crisp QR, short enough to read down the phone.
///
/// The code is a claim ticket, not a password: it expires, and it only ever
/// points at cosmetic progress. Nothing sensitive travels through it.
class CloudCode {
  /// Same host the multiplayer client talks to.
  static String host = 'https://zone-royale.onrender.com';

  static Uri _uri(String path) {
    var h = host.trim();
    if (h.startsWith('wss://')) h = h.replaceFirst('wss://', 'https://');
    if (h.startsWith('ws://')) h = h.replaceFirst('ws://', 'http://');
    if (!h.startsWith('http')) h = 'https://$h';
    if (h.endsWith('/')) h = h.substring(0, h.length - 1);
    return Uri.parse('$h$path');
  }

  /// Uploads this device's profile and returns the six-character code, or
  /// null if the server could not be reached.
  static Future<String?> upload() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.postUrl(_uri('/save'));
      req.headers.contentType = ContentType.text;
      req.write(Profile.instance.exportCode());
      final res = await req.close().timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return null;
      final body = await utf8.decoder.bind(res).join();
      final map = jsonDecode(body);
      if (map is Map && map['code'] is String) return map['code'] as String;
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Fetches and applies the profile behind [code].
  ///
  /// Returns null on success, or a short human-readable reason on failure —
  /// "that code has expired" is a far more useful thing to show than a
  /// silent no-op.
  static Future<String?> restore(String code) async {
    final clean = code.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.length < 4) return 'That code looks too short.';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(_uri('/save/$clean'));
      final res = await req.close().timeout(const Duration(seconds: 25));
      if (res.statusCode == 404) {
        return 'That code has expired or does not exist.';
      }
      if (res.statusCode != 200) return 'The server could not be reached.';
      final blob = await utf8.decoder.bind(res).join();
      final ok = await Profile.instance.importCode(blob);
      return ok ? null : 'That code did not contain a valid profile.';
    } catch (_) {
      return 'The server could not be reached. Check your connection.';
    } finally {
      client.close(force: true);
    }
  }

  /// Pulls a transfer code out of whatever a QR scan produced. Accepts a bare
  /// code, or a `zoneroyale://transfer/CODE` link.
  static String? parse(String raw) {
    final t = raw.trim();
    final m = RegExp(r'([A-Za-z0-9]{6})$').firstMatch(t);
    if (m != null) return m.group(1)!.toUpperCase();
    return null;
  }

  /// What the QR encodes. A bare code scans in any reader and reads back as
  /// something a person can retype.
  static String payload(String code) => code;
}
