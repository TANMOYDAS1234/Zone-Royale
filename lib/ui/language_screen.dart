import 'package:flutter/material.dart';

import '../game/profile.dart';
import '../game/sfx.dart';
import '../i18n/strings.dart';
import 'theme.dart';

/// First-run language choice.
///
/// This has to come before anything else, and it cannot be buried in settings:
/// someone who reads only Bengali cannot navigate an English menu to find the
/// language switch. So each option is written in its own script, large, with
/// no English required to understand the screen.
///
/// Deliberately built from the simplest primitives — a ColoredBox, a Center
/// and a min-height Column. It is the first thing a brand-new player ever
/// sees, so it cannot depend on anything that might not lay out.
class LanguageScreen extends StatefulWidget {
  final void Function(int language) onPicked;
  /// True when reached from the profile, which adds a back arrow.
  final bool canGoBack;
  const LanguageScreen(
      {super.key, required this.onPicked, this.canGoBack = false});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  int _sel = Profile.instance.language;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZR.bg,
      child: SafeArea(
        child: Stack(
          children: [
            if (widget.canGoBack)
              Positioned(
                left: 4,
                top: 4,
                child: GestureDetector(
                  onTap: () {
                    Sfx.back();
                    Navigator.of(context).maybePop();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                      width: 46,
                      height: 40,
                      child: Icon(Icons.arrow_back,
                          color: Colors.white70, size: 20)),
                ),
              ),
            Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('ZONE ROYALE',
                        style: ZR.display(34, color: ZR.primary, spacing: 4)),
                    const SizedBox(height: 6),
                    // shown in all three scripts at once, because at this
                    // point we do not yet know which one they read
                    const Text(
                        'CHOOSE YOUR LANGUAGE  ·  ভাষা বেছে নিন  ·  भाषा चुनें',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Mono',
                          fontFamilyFallback: ['NotoBn', 'NotoDv'],
                          fontSize: 11,
                          height: 1.6,
                          letterSpacing: 0.5,
                          color: Colors.white54,
                        )),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < L.codes.length; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          _option(i),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: 280,
                      child: ZrButton(
                        label: 'CONTINUE',
                        icon: Icons.arrow_forward,
                        height: 48,
                        fontSize: 22,
                        onTap: () {
                          final p = Profile.instance;
                          p.language = _sel;
                          p.languagePicked = true;
                          p.save();
                          L.current = _sel;
                          widget.onPicked(_sel);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(int i) {
    final on = _sel == i;
    return GestureDetector(
      onTap: () {
        Sfx.select();
        setState(() {
          _sel = i;
          // apply immediately so the CONTINUE button below is already in the
          // language you just picked — the choice proves itself
          L.current = i;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 150,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: on ? ZR.panelActive(radius: 14) : ZR.panel(radius: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L.nativeNames[i],
                style: TextStyle(
                  fontFamily: 'Display',
                  fontFamilyFallback: const ['NotoBn', 'NotoDv'],
                  fontSize: 24,
                  height: 1.3,
                  color: on ? ZR.primary : Colors.white,
                )),
            const SizedBox(height: 2),
            Text(L.codes[i].toUpperCase(),
                style: ZR.mono(9,
                    color: on ? ZR.primary : Colors.white30, spacing: 2)),
            const SizedBox(height: 4),
            Icon(on ? Icons.check_circle : Icons.circle_outlined,
                size: 16, color: on ? ZR.primary : Colors.white24),
          ],
        ),
      ),
    );
  }
}
