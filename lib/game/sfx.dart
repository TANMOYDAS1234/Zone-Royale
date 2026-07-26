import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'profile.dart';

/// Sound effects. The waveforms were synthesised once (see tool/gen_sfx.dart)
/// and shipped as real .wav assets under assets/sfx/. We play them through
/// audioplayers with AssetSource + the default media player — the most reliable
/// audio path on Android. Every call is wrapped so audio can never crash the
/// game; worst case it falls back to haptics only.
class Sfx {
  static bool _ready = false;

  static _Voice? _shoot, _hit, _hurt, _pickup, _reload, _boom, _death, _win,
      _skill, _zone;
  // menu/UI voices — the front end used to be completely silent
  static _Voice? _uiTap, _uiSelect, _uiBack, _uiBuy, _uiDeny, _uiWhoosh;

  /// The looping menu bed. Separate player, separate volume: music and effects
  /// are different things and players want different amounts of each.
  static AudioPlayer? _music;
  static bool _musicWanted = false;

  /// Every effect is scaled by the player's SFX slider, so one setting governs
  /// gunfire, explosions and button clicks alike.
  static double get _sfxGain => Profile.instance.sfxVolume.clamp(0.0, 1.0);

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
      _uiTap = await _Voice.make('sfx/ui_tap.wav', 3);
      _uiSelect = await _Voice.make('sfx/ui_select.wav', 2);
      _uiBack = await _Voice.make('sfx/ui_back.wav', 2);
      _uiBuy = await _Voice.make('sfx/ui_buy.wav', 2);
      _uiDeny = await _Voice.make('sfx/ui_deny.wav', 1);
      _uiWhoosh = await _Voice.make('sfx/ui_whoosh.wav', 2);
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

  static void win({double vol = 0.9}) {
    if (_ready) _win?.play(vol);
    _haptic(HapticFeedback.heavyImpact);
  }

  static void skill() {
    if (_ready) _skill?.play(0.8);
    _haptic(HapticFeedback.mediumImpact);
  }

  static void zone() {
    if (_ready) _zone?.play(0.6);
  }

  // ---- menus ----------------------------------------------------------
  /// A button, a chip, a slider handle — anything you tapped that did a thing.
  static void tap() {
    if (_ready) _uiTap?.play(0.55);
    _haptic(HapticFeedback.selectionClick);
  }

  /// Moving forward: a tab, a bottom-nav destination, opening a screen.
  static void select() {
    if (_ready) _uiSelect?.play(0.6);
    _haptic(HapticFeedback.selectionClick);
  }

  /// Going back or closing.
  static void back() {
    if (_ready) _uiBack?.play(0.55);
    _haptic(HapticFeedback.selectionClick);
  }

  /// A purchase, an equip, a claimed reward.
  static void buy() {
    if (_ready) _uiBuy?.play(0.85);
    _haptic(HapticFeedback.mediumImpact);
  }

  /// Refused — not enough coins, bad code.
  static void deny() {
    if (_ready) _uiDeny?.play(0.6);
    _haptic(HapticFeedback.heavyImpact);
  }

  /// Under a screen transition.
  static void whoosh({double vol = 0.5}) {
    if (_ready) _uiWhoosh?.play(vol);
  }

  // ---- music ----------------------------------------------------------
  /// Start the menu bed. Safe to call repeatedly — it will not restart a loop
  /// that is already playing, so moving between menu screens is seamless.
  static Future<void> startMenuMusic() async {
    _musicWanted = true;
    final vol = Profile.instance.musicVolume.clamp(0.0, 1.0);
    if (vol <= 0.001) {
      await stopMenuMusic(keepWanted: true);
      return;
    }
    try {
      if (_music != null) {
        await _music!.setVolume(vol);
        if (_music!.state == PlayerState.playing) return;
        await _music!.resume();
        return;
      }
      final p = AudioPlayer();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setSource(AssetSource('sfx/menu_loop.wav'));
      await p.setVolume(vol);
      await p.resume();
      _music = p;
    } catch (_) {
      // no music is fine; the game is still playable
    }
  }

  /// Silence the bed — during a match, and whenever the slider hits zero.
  static Future<void> stopMenuMusic({bool keepWanted = false}) async {
    if (!keepWanted) _musicWanted = false;
    try {
      await _music?.pause();
    } catch (_) {}
  }

  /// Apply a slider change immediately, without waiting for a screen change.
  static Future<void> applyMusicVolume() async {
    final vol = Profile.instance.musicVolume.clamp(0.0, 1.0);
    if (!_musicWanted) return;
    if (vol <= 0.001) {
      await stopMenuMusic(keepWanted: true);
      return;
    }
    await startMenuMusic();
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
    volume *= Sfx._sfxGain;
    if (volume <= 0.001) return;
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
