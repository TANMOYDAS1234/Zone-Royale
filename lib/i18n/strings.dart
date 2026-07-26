import 'package:flutter/widgets.dart';

import 'bn.dart';
import 'hi.dart';

/// Localisation for Zone Royale — English, Bengali, Hindi.
///
/// The English string IS the key. `tr('DROP IN')` looks the phrase up in the
/// active language's table and returns the English unchanged when there is no
/// entry. Two consequences that matter:
///
///  * the code still reads as English, so nothing is harder to work on, and
///  * a missing translation shows the English word, never a raw key like
///    `home.dropIn` — the worst thing a half-translated app can do.
class L {
  static const codes = ['en', 'bn', 'hi'];
  static const names = ['ENGLISH', 'বাংলা', 'हिन्दी'];
  /// Written in the language itself, so you can find yours without reading English.
  static const nativeNames = ['English', 'বাংলা', 'हिन्दी'];

  /// Index into [codes]. Set from Profile at startup and whenever it changes.
  static int current = 0;

  static bool get isLatin => current == 0;

  static Map<String, String> get _table => switch (current) {
        1 => kBn,
        2 => kHi,
        _ => const {},
      };

  /// The font family stack for the active language. Bebas Neue and Hanken
  /// Grotesk have no Bengali or Devanagari glyphs at all, so a translated
  /// build in those languages would render as empty boxes without this.
  static List<String>? get fallback => switch (current) {
        1 => const ['NotoBn'],
        2 => const ['NotoDv'],
        _ => null,
      };

  /// Bengali and Devanagari have taller ascenders and descenders than the
  /// condensed Latin display face, so they need a little more line room.
  static double get heightBoost => current == 0 ? 1.0 : 1.18;

  /// Bebas Neue is caps-only by design and the UI leans on that. Indic scripts
  /// have no case, and forcing `toUpperCase()` on them is a no-op — but the
  /// letter-spacing tuned for caps looks wrong, so it is relaxed.
  static double spacingScale = 1.0;
}

/// Translate [s]. Returns [s] itself when untranslated.
String tr(String s) {
  if (L.current == 0) return s;
  return L._table[s] ?? L._table[s.toUpperCase()] ?? s;
}

/// Translate with a single `{}` placeholder filled in — for strings that carry
/// a number or a name, which every language orders differently.
String trf(String s, Object a) => tr(s).replaceFirst('{}', '$a');

/// Convenience for the many places the UI shouts a label in caps. Indic text
/// is returned unchanged because it has no upper case.
String trUp(String s) {
  final t = tr(s);
  return L.current == 0 ? t.toUpperCase() : t;
}

/// Rebuilds its subtree when the language changes.
class LanguageScope extends InheritedWidget {
  final int language;
  const LanguageScope(
      {super.key, required this.language, required super.child});

  @override
  bool updateShouldNotify(LanguageScope old) => old.language != language;
}
