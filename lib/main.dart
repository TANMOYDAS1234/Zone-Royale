import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

import 'game/profile.dart';
import 'game/royale_game.dart';
import 'game/sfx.dart';
import 'ui/brand.dart';
import 'ui/game_ui.dart';

/// Refresh rate we aim for. 90 Hz is the sweet spot: clearly smoother than 60
/// without the battery/thermal cost of 120 on a mid-range phone. Set to 60 for
/// maximum battery life, or 120 to use the panel's full rate.
const double kTargetRefreshHz = 90;

/// Ask Android for the best refresh mode at or below [kTargetRefreshHz] — Flutter
/// otherwise runs at the system default (often 60 Hz). Only considers modes at
/// the *current* resolution so the screen size never changes. Android resets the
/// preferred mode when the app is backgrounded, so this is re-applied on resume.
Future<void> _useHighRefreshRate() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final supported = await FlutterDisplayMode.supported;
    final active = await FlutterDisplayMode.active;
    final sameRes = supported
        .where((m) => m.width == active.width && m.height == active.height)
        .toList();
    if (sameRes.isEmpty) return;
    // fastest mode that doesn't exceed the target; else the slowest available
    DisplayMode? best;
    for (final m in sameRes) {
      if (m.refreshRate > kTargetRefreshHz + 0.5) continue;
      if (best == null || m.refreshRate > best.refreshRate) best = m;
    }
    best ??= sameRes.reduce((a, b) => a.refreshRate < b.refreshRate ? a : b);
    await FlutterDisplayMode.setPreferredMode(best);
  } catch (_) {
    // device doesn't support mode switching — stay at the default
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _useHighRefreshRate();
  await Profile.instance.load();
  Sfx.init(); // fire-and-forget: generates + loads sounds in the background
  // Edge-to-edge with transparent bars: the game fills the screen and stays
  // rock-steady (immersive/sticky mode flickers when you touch the bottom edge
  // where the joysticks live), and the soft keyboard works for the name field.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));
  runApp(const ZoneRoyaleApp());
}

class ZoneRoyaleApp extends StatelessWidget {
  const ZoneRoyaleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zone Royale',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05070C),
        useMaterial3: true,
      ),
      home: const GamePage(),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  late final RoyaleGame game;
  final FocusNode _focus = FocusNode();
  final Set<LogicalKeyboardKey> _keys = {};
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    game = RoyaleGame();
    WidgetsBinding.instance.addObserver(this);
    // re-request after the window exists (the pre-runApp call can be too early)
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _useHighRefreshRate());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android reverts to the system refresh rate when we're backgrounded
    if (state == AppLifecycleState.resumed) _useHighRefreshRate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    // Don't intercept keys on menus (lets the name field & others type freely).
    if (game.screen.value != Screen.playing) return KeyEventResult.ignored;
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      _keys.add(e.logicalKey);
    } else if (e is KeyUpEvent) {
      _keys.remove(e.logicalKey);
    }
    bool held(LogicalKeyboardKey k) => _keys.contains(k);
    double x = 0, y = 0;
    if (held(LogicalKeyboardKey.keyA) || held(LogicalKeyboardKey.arrowLeft)) {
      x -= 1;
    }
    if (held(LogicalKeyboardKey.keyD) || held(LogicalKeyboardKey.arrowRight)) {
      x += 1;
    }
    if (held(LogicalKeyboardKey.keyW) || held(LogicalKeyboardKey.arrowUp)) {
      y -= 1;
    }
    if (held(LogicalKeyboardKey.keyS) || held(LogicalKeyboardKey.arrowDown)) {
      y += 1;
    }
    game.enableTouch(false);
    game.setMove(x, y);
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.keyR) {
      game.requestReload();
    }
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.keyB) {
      game.toggleFireMode();
    }
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.keyG) {
      game.throwGrenade();
    }
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.keyF) {
      game.activateSkill();
    }
    return KeyEventResult.handled;
  }

  void _aimFromMouse(PointerEvent e) {
    if (e.kind == PointerDeviceKind.mouse) {
      game.enableTouch(false);
      game.setMouse(Vector2(e.localPosition.dx, e.localPosition.dy));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerHover: _aimFromMouse,
          onPointerMove: _aimFromMouse,
          onPointerDown: (e) {
            _aimFromMouse(e);
            if (e.kind == PointerDeviceKind.mouse) game.setFire(true);
          },
          onPointerUp: (e) {
            if (e.kind == PointerDeviceKind.mouse) game.setFire(false);
          },
          child: Stack(
            children: [
              Positioned.fill(child: GameWidget(game: game)),
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: game.screen,
                  builder: (_, _) {
                    switch (game.screen.value) {
                      case Screen.start:
                        return StartOverlay(game: game);
                      case Screen.end:
                        return EndOverlay(game: game);
                      case Screen.profile:
                        return ProfileOverlay(game: game);
                      case Screen.missions:
                        return MissionsOverlay(game: game);
                      case Screen.shop:
                        return ShopOverlay(game: game);
                      default:
                        return HudLayer(game: game);
                    }
                  },
                ),
              ),
              if (_showSplash)
                Positioned.fill(
                  child: SplashScreen(
                    onDone: () => setState(() => _showSplash = false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
