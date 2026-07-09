import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Sound effects. The waveforms were synthesised once (see tool/gen_sfx.dart)
/// and shipped as real .wav assets under assets/sfx/. We play them through
/// audioplayers with AssetSource + the default media player — the most reliable
/// audio path on Android. Every call is wrapped so audio can never crash the
/// game; worst case it falls back to haptics only.
class Sfx {
  static bool _ready = false;

  static _Voice? _shoot, _hit, _hurt, _pickup, _reload, _boom, _death, _win,
      _skill, _zone;

  static Future<void> init() async {
    if (_ready) return;
    try {
      _shoot = await _Voice.make('sfx/shoot.wav', 4);
      _hit = await _Voice.make('sfx/hit.wav', 2);
      _hurt = await _Voice.make('sfx/hurt.wav', 1);
      _pickup = await _Voice.make('sfx/pickup.wav', 2);
      _reload = await _Voice.make('sfx/reload.wav', 1);
      _boom = await _Voice.make('sfx/boom.wav', 2);
      _death = await _Voice.make('sfx/death.wav', 1);
      _win = await _Voice.make('sfx/win.wav', 1);
      _skill = await _Voice.make('sfx/skill.wav', 1);
      _zone = await _Voice.make('sfx/zone.wav', 1);
      _ready = true;
    } catch (_) {
      _ready = false; // stay silent (haptics still fire), keep playing
    }
  }

  static void _haptic(void Function() f) {
    if (kIsWeb) return;
    try {
      f();
    } catch (_) {}
  }

  // ---- public API (audio + haptics) ----
  static void shoot({double vol = 0.55}) {
    if (_ready) _shoot?.play(vol);
  }

  static void hit() {
    if (_ready) _hit?.play(0.6);
    _haptic(HapticFeedback.selectionClick);
  }

  static void hurt() {
    if (_ready) _hurt?.play(0.8);
    _haptic(HapticFeedback.mediumImpact);
  }

  static void pickup() {
    if (_ready) _pickup?.play(0.6);
    _haptic(HapticFeedback.lightImpact);
  }

  static void reload() {
    if (_ready) _reload?.play(0.7);
  }

  static void boom() {
    if (_ready) _boom?.play(1.0);
    _haptic(HapticFeedback.heavyImpact);
  }

  static void death() {
    if (_ready) _death?.play(0.7);
    _haptic(HapticFeedback.mediumImpact);
  }

  static void win() {
    if (_ready) _win?.play(0.9);
    _haptic(HapticFeedback.heavyImpact);
  }

  static void skill() {
    if (_ready) _skill?.play(0.8);
    _haptic(HapticFeedback.mediumImpact);
  }

  static void zone() {
    if (_ready) _zone?.play(0.6);
  }
}

/// A small round-robin pool of players preloaded with one sound, so the same
/// effect (e.g. rapid gunfire) can overlap itself instead of cutting off.
class _Voice {
  final List<AudioPlayer> _players;
  int _next = 0;
  _Voice(this._players);

  static Future<_Voice> make(String asset, int voices) async {
    final source = AssetSource(asset);
    final players = <AudioPlayer>[];
    for (var i = 0; i < voices; i++) {
      final p = AudioPlayer();
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setSource(source); // preload so first play has no hitch
      players.add(p);
    }
    return _Voice(players);
  }

  void play(double volume) {
    if (_players.isEmpty) return;
    final p = _players[_next];
    _next = (_next + 1) % _players.length;
    _fire(p, volume);
  }

  Future<void> _fire(AudioPlayer p, double volume) async {
    try {
      await p.setVolume(volume.clamp(0.0, 1.0));
      await p.seek(Duration.zero); // rewind so the sound actually replays
      await p.resume();
    } catch (_) {}
  }
}
