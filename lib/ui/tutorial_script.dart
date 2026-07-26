import 'package:flutter/material.dart';

import '../game/config.dart';
import '../game/profile.dart';
import 'tutorial.dart';

/// The tour itself, in order.
///
/// Three acts: the front end, one real match, and the results screen. It sets
/// the new player up to actually win their first fight — SMG, CASUAL bots, the
/// medic hero — because a first match that ends in ten seconds teaches nothing
/// except that the game is unfair.

/// Rect for an in-match control, computed from the player's own saved layout.
/// The HUD is not a widget tree we can hang anchors off, but the positions are
/// known exactly, so the spotlight lands on the real control wherever the
/// player has dragged it.
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

/// Act 1 — the menus. Ends by dropping into a match.
List<TutorialStep> menuSteps() {
  final p = Profile.instance;
  return [
    TutorialStep(
      title: 'WELCOME TO ZONE ROYALE',
      body: 'Ten players drop in. One walks out. This quick tour shows you '
          'every screen and every button — it takes about a minute, and it '
          'only ever runs once.',
      onShow: () {
        // Set the new player up to survive their first match. Nothing here is
        // locked afterwards; it is a starting point, not a cage.
        p.startWeapon = WeaponId.smg;
        p.difficulty = 0; // CASUAL
        final medic = kHeroes.indexWhere((h) => h.skill == SkillType.medic);
        if (medic >= 0) p.hero = medic;
        p.save();
      },
    ),
    const TutorialStep(
      goto: 'start',
      anchor: 'home.operator',
      title: 'THIS IS YOUR OPERATOR',
      body: 'Everything you equip shows up here exactly as it looks in the '
          'match — your outfit, helmet, vest, hero and the gun in your hands.',
    ),
    const TutorialStep(
      anchor: 'home.difficulty',
      title: 'DIFFICULTY',
      body: 'We have set you to CASUAL so the bots go easy while you learn. '
          'Move it up whenever you want a harder fight.',
    ),
    const TutorialStep(
      anchor: 'home.streak',
      title: 'FREE COINS EVERY DAY',
      body: 'Open the game each day and tap here. The bonus grows for seven '
          'days in a row.',
    ),
    const TutorialStep(
      anchor: 'home.mode',
      title: 'MATCH SIZE',
      body: 'SKIRMISH is 10 players and quick. CLASH is 25. WARZONE is a full '
          '50-player battle royale.',
    ),
    const TutorialStep(
      anchor: 'home.maps',
      title: 'PICK YOUR MAP',
      body: 'Each map is a real arena — the preview shows the actual walls, '
          'cover and safe zone you will be fighting in.',
    ),
    const TutorialStep(
      anchor: 'nav.shop',
      title: 'SHOP',
      body: 'Spend the coins you earn on skins, weapons, helmets and heroes. '
          'Anything you buy is equipped straight away.',
    ),
    const TutorialStep(
      anchor: 'nav.missions',
      title: 'MISSIONS',
      body: 'Daily objectives that pay coins and XP. They reset every 24 '
          'hours, and they count in every mode.',
    ),
    const TutorialStep(
      anchor: 'nav.profile',
      title: 'PROFILE',
      body: 'Your name, your look, your loadout — and the two settings most '
          'worth knowing about, coming up next.',
    ),
    const TutorialStep(
      goto: 'profile',
      anchor: 'profile.graphics',
      title: 'GRAPHICS QUALITY',
      body: 'SMOOTH, BALANCED or ULTRA. If the game ever feels like it is '
          'stuttering, drop this to SMOOTH — the sample below shows exactly '
          'what changes.',
    ),
    const TutorialStep(
      goto: 'profile',
      anchor: 'profile.controls',
      title: 'MOVE YOUR CONTROLS',
      body: 'Every button, stick and bar can be dragged anywhere, resized and '
          'faded. Set them where your thumbs actually sit.',
    ),
    const TutorialStep(
      goto: 'profile',
      anchor: 'profile.language',
      title: 'LANGUAGE',
      body: 'You can switch between English, বাংলা and हिन्दी here at any '
          'time.',
    ),
    const TutorialStep(
      // back to the home console, where DROP IN lives
      goto: 'start',
      anchor: 'home.drop',
      title: 'READY? DROP IN',
      body: 'Tap DROP IN and we will walk you through the controls in a real '
          'match.',
      tapTarget: true,
    ),
  ];
}

/// Act 2 — inside the match. Anchored to the player's own control layout.
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
        body: 'The gun you are holding, with rounds left in the magazine. Tap '
            'it to reload — do it in cover, not mid-fight.',
      ),
      TutorialStep(
        screen: 'playing',
        rect: _hud('swap', 80, 66),
        title: 'SWITCH GUN',
        body: 'You carry two weapons. This shows the other one — tap to bring '
            'it up. Nothing else ever swaps your gun for you.',
      ),
      TutorialStep(
        screen: 'playing',
        rect: _hud('fire', 64, 62),
        title: 'AUTO OR SINGLE',
        body: 'AUTO keeps firing while you hold the stick. SINGLE fires one '
            'shot at a time — better for snipers and long range.',
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
        body: 'Your hero ability. The ring fills as it recharges, and it says '
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
        body: 'Red is your health. The blue and white bars are your armour — '
            'they soak damage first, so pick them up whenever you see them.',
      ),
      TutorialStep(
        screen: 'playing',
        rect: (Size s) => Rect.fromLTWH(s.width * 0.36, 12, s.width * 0.28, 62),
        title: 'THE ZONE',
        body: 'The safe circle shrinks. Outside it you take damage that never '
            'stops — always be moving inside the ring.',
      ),
      TutorialStep(
        screen: 'playing',
        rect: (Size s) => Rect.fromLTWH(s.width - 110, 10, 100, 100),
        title: 'MINIMAP',
        body: 'The blue ring is the safe zone, red dots are nearby enemies, '
            'and the gold dot is you.',
      ),
      const TutorialStep(
        screen: 'playing',
        title: 'NOW GO WIN IT',
        body: 'Loot a better gun, stay inside the circle, and be the last one '
            'standing. We will see you on the results screen.',
      ),
    ];

/// Act 3 — the results screen, then home.
List<TutorialStep> resultSteps() => [
      const TutorialStep(
        screen: 'end',
        title: 'MATCH SUMMARY',
        body: 'How you placed, what you earned, and how far you are through '
            'your level — every match pays out, win or lose.',
      ),
      const TutorialStep(
        screen: 'end',
        anchor: 'end.share',
        title: 'SHARE YOUR RESULT',
        body: 'Turns the card into an image you can send to friends. This is '
            'how people get dragged into the game.',
      ),
      const TutorialStep(
        screen: 'end',
        anchor: 'end.again',
        title: 'PLAY AGAIN',
        body: 'Straight into another match with the same settings.',
      ),
      const TutorialStep(
        screen: 'end',
        anchor: 'end.home',
        title: "THAT'S EVERYTHING",
        body: 'HOME takes you back to spend your coins and pick your next '
            'match. Good luck out there.',
      ),
    ];

/// The whole tour, start to finish.
List<TutorialStep> fullTutorial() =>
    [...menuSteps(), ...matchSteps(), ...resultSteps()];
