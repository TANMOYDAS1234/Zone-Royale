import 'package:flutter/material.dart';

import '../game/config.dart';
import '../game/profile.dart';
import 'tutorial.dart';

/// The tour, written for the lobby as it actually is.
///
/// Three acts: the front end, one real match, and the results card. It sets a
/// new player up to actually win their first fight — SMG, CASUAL bots, the
/// medic hero — because a first match that ends in ten seconds teaches
/// nothing except that the game is unfair.

/// Rect for an in-match control, computed from the player's own saved layout.
/// The HUD is not a widget tree we can hang anchors off, but its positions are
/// known exactly, so the spotlight lands on the real control wherever it has
/// been dragged to.
Rect Function(Size) _hud(String key, double w, double h) => (Size s) {
      final p = Profile.instance;
      final sc = p.hudScaleOf(key);
      final f = p.hudPosOf(key);
      final ww = w * sc, hh = h * sc;
      return Rect.fromLTWH(
        (f[0] * s.width - ww / 2).clamp(0.0, s.width - ww),
        (f[1] * s.height - hh / 2).clamp(0.0, s.height - hh),
        ww,
        hh,
      );
    };

/// Act 1 — the lobby. Ends by dropping into a match.
List<TutorialStep> menuSteps() {
  final p = Profile.instance;
  return [
    TutorialStep(
      goto: 'start',
      title: 'WELCOME TO ZONE ROYALE',
      body: 'Ten players drop in. One walks out. This takes about a minute '
          'and shows you every button — it only ever runs once.',
      onShow: () {
        // Set a new player up to survive their first match. None of this is
        // locked afterwards; it is a starting point, not a cage.
        p.startWeapon = WeaponId.smg;
        p.difficulty = 0; // CASUAL
        final medic = kHeroes.indexWhere((h) => h.skill == SkillType.medic);
        if (medic >= 0) p.hero = medic;
        p.save();
      },
    ),
    const TutorialStep(
      anchor: 'lobby.stage',
      title: 'THIS IS YOUR OPERATOR',
      body: 'Everything you equip shows up here exactly as it looks in the '
          'match. Drag left or right to turn them around.',
    ),
    const TutorialStep(
      anchor: 'lobby.player',
      title: 'YOU',
      body: 'Your name, your level and the title you have earned. Tap it any '
          'time to change how you look and how the game plays.',
    ),
    const TutorialStep(
      anchor: 'lobby.coins',
      title: 'COINS',
      body: 'Earned by playing — every match pays out, win or lose. Spend '
          'them in the store on skins, weapons and heroes.',
    ),
    const TutorialStep(
      anchor: 'lobby.mail',
      title: 'MAIL',
      body: 'Your daily login reward lands here. A red dot means something '
          'is waiting. The bonus grows for seven days in a row.',
    ),
    const TutorialStep(
      anchor: 'lobby.rail',
      title: 'STORE, COLLECTION, MISSIONS',
      body: 'STORE is everything you can buy. COLLECTION is what you already '
          'own. MISSIONS are daily objectives that pay coins and XP.',
    ),
    const TutorialStep(
      anchor: 'lobby.mode',
      title: 'MATCH SIZE',
      body: 'SKIRMISH is 10 players and quick. CLASH is 25. WARZONE is a '
          'full 50-player battle royale.',
    ),
    const TutorialStep(
      anchor: 'lobby.map',
      title: 'YOUR MAP',
      body: 'The preview is the real arena — those are the actual walls, '
          'trees and safe zone. Tap CHANGE to pick a different one.',
    ),
    const TutorialStep(
      anchor: 'lobby.start',
      title: 'READY? TAP START',
      body: 'We will walk you through the controls in a real match.',
      tapTarget: true,
    ),
  ];
}

/// Act 2 — inside the match, anchored to the player's own control layout.
List<TutorialStep> matchSteps() => [
      TutorialStep(
        screen: 'playing',
        rect: _hud(Profile.instance.leftHanded ? 'aim' : 'move', 132, 158),
        title: 'LEFT STICK — MOVE',
        body: 'Drag this to run. You can move and shoot at the same time.',
      ),
      TutorialStep(
        screen: 'playing',
        rect: _hud(Profile.instance.leftHanded ? 'move' : 'aim', 132, 158),
        title: 'RIGHT STICK — AIM AND FIRE',
        body: 'Drag to aim; you fire automatically while you hold it. Let go '
            'to stop shooting.',
      ),
      TutorialStep(
        screen: 'playing',
        rect: _hud('reload', 140, 84),
        title: 'YOUR WEAPON',
        body: 'The gun in your hands and the rounds left in the magazine. Tap '
            'it to reload — do that in cover, not mid-fight.',
      ),
      TutorialStep(
        screen: 'playing',
        rect: _hud('swap', 80, 66),
        title: 'SWITCH GUN',
        body: 'You carry two weapons. This is the other one — tap to bring it '
            'up. Nothing else ever swaps your gun for you.',
      ),
      TutorialStep(
        screen: 'playing',
        rect: _hud('fire', 64, 62),
        title: 'AUTO OR SINGLE',
        body: 'AUTO keeps firing while you hold the stick. SINGLE fires one '
            'shot at a time — better at long range.',
      ),
      TutorialStep(
        screen: 'playing',
        rect: _hud('nade', 60, 60),
        title: 'GRENADE',
        body: 'Throws where you are aiming. The number is how many you have '
            'left; find more on the ground.',
      ),
      TutorialStep(
        screen: 'playing',
        rect: _hud('skill', 64, 64),
        title: 'HERO SKILL',
        body: 'Your hero ability. The ring fills as it recharges and says '
            'READY when you can use it again.',
      ),
      TutorialStep(
        screen: 'playing',
        rect: _hud('wall', 60, 60),
        title: 'SHIELD WALL',
        body: 'Drops instant cover in front of you. The panic button that '
            'wins close fights — bullets cannot pass through it.',
      ),
      TutorialStep(
        screen: 'playing',
        rect: _hud('hp', 158, 56),
        title: 'HEALTH, VEST AND HELMET',
        body: 'Red is your health. The blue and white bars are armour — they '
            'soak damage first, so pick them up whenever you see them.',
      ),
      TutorialStep(
        screen: 'playing',
        rect: (Size s) => Rect.fromLTWH(s.width * 0.36, 10, s.width * 0.28, 64),
        title: 'THE ZONE',
        body: 'The safe circle shrinks. Outside it you take damage that never '
            'stops — always be moving inside the ring.',
      ),
      TutorialStep(
        screen: 'playing',
        rect: (Size s) => Rect.fromLTWH(s.width - 112, 8, 104, 104),
        title: 'MINIMAP',
        body: 'The blue ring is the safe zone, red dots are nearby enemies, '
            'and the gold dot is you.',
      ),
      const TutorialStep(
        screen: 'playing',
        title: 'NOW GO WIN IT',
        body: 'Loot a better gun, stay inside the circle, and be the last one '
            'standing. See you on the results screen.',
      ),
    ];

/// Act 3 — the results card.
List<TutorialStep> resultSteps() => [
      const TutorialStep(
        screen: 'end',
        title: 'MATCH SUMMARY',
        body: 'Where you placed, what you earned, and how far through your '
            'level you are. Every match pays out, win or lose.',
      ),
      const TutorialStep(
        screen: 'end',
        anchor: 'end.share',
        title: 'SHARE YOUR RESULT',
        body: 'Turns the card into an image you can send to friends.',
      ),
      const TutorialStep(
        screen: 'end',
        anchor: 'end.home',
        title: "THAT'S EVERYTHING",
        body: 'HOME takes you back to spend your coins and pick the next '
            'match. Good luck out there.',
      ),
    ];

/// The whole tour, start to finish.
List<TutorialStep> fullTutorial() =>
    [...menuSteps(), ...matchSteps(), ...resultSteps()];
