import 'profile.dart';

/// Unlockable player titles.
///
/// A title is the cheapest possible reward — it costs nothing to give and
/// nothing to store — and it is the one people actually chase, because it is
/// the only thing every other player sees next to your name. The conditions
/// are read straight off stats the game already keeps, so nothing new has to
/// be tracked and titles unlock retroactively for anyone already past the bar.
class GameTitle {
  final String id;
  final String name;
  /// What you have to do, in the player's words.
  final String how;
  /// Progress toward the goal, 0..1, and the raw "have / need" numbers.
  final int Function(Profile p) have;
  final int need;
  /// Rank tier, purely cosmetic: 0 common, 1 rare, 2 elite, 3 legendary.
  final int tier;

  const GameTitle(this.id, this.name, this.how, this.have, this.need, this.tier);

  bool unlocked(Profile p) => have(p) >= need;
  double progress(Profile p) => (have(p) / need).clamp(0.0, 1.0);
}

/// Ordered easiest first. Deliberately front-loaded so a new player unlocks
/// something in their first session, then spaced out so the later ones stay
/// worth having.
const List<GameTitle> kTitles = [
  GameTitle('rookie', 'ROOKIE', 'Play your first match', _matches, 1, 0),
  GameTitle('scrapper', 'SCRAPPER', 'Get 10 kills', _kills, 10, 0),
  GameTitle('survivor', 'SURVIVOR', 'Play 25 matches', _matches, 25, 0),
  GameTitle('victor', 'VICTOR', 'Win a match', _wins, 1, 1),
  GameTitle('marksman', 'MARKSMAN', 'Get 100 kills', _kills, 100, 1),
  GameTitle('regular', 'REGULAR', 'Play 100 matches', _matches, 100, 1),
  GameTitle('champion', 'CHAMPION', 'Win 10 matches', _wins, 10, 2),
  GameTitle('veteran', 'VETERAN', 'Reach level 25', _level, 25, 2),
  GameTitle('devoted', 'DEVOTED', 'Log in 7 days in a row', _streak, 7, 2),
  GameTitle('executioner', 'EXECUTIONER', 'Get 500 kills', _kills, 500, 3),
  GameTitle('conqueror', 'CONQUEROR', 'Win 50 matches', _wins, 50, 3),
  GameTitle('legend', 'LEGEND', 'Reach level 50', _level, 50, 3),
];

int _matches(Profile p) => p.matches;
int _kills(Profile p) => p.kills;
int _wins(Profile p) => p.wins;
int _level(Profile p) => p.level;
int _streak(Profile p) => p.streak;

/// The title currently worn, or the best one unlocked if none is chosen.
GameTitle titleFor(Profile p) {
  for (final t in kTitles) {
    if (t.id == p.title && t.unlocked(p)) return t;
  }
  GameTitle best = kTitles.first;
  for (final t in kTitles) {
    if (t.unlocked(p)) best = t;
  }
  return best;
}

/// How many are unlocked right now — the number the profile shows.
int titlesUnlocked(Profile p) =>
    kTitles.where((t) => t.unlocked(p)).length;
