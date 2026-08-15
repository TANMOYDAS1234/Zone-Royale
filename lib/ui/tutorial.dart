import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/profile.dart';
import '../game/sfx.dart';
import 'theme.dart';

/// The first-run guided tour.
///
/// A new player opening a battle royale for the first time sees five screens,
/// nine buttons and two joysticks and has no idea which one starts a game.
/// This walks them through it: a spotlight on one thing at a time, a hand that
/// points at it, and a caption saying what it does — through the menus, into a
/// real match, through every control, and out the other side of the results
/// screen.
///
/// It runs ONCE, on a genuinely fresh install. A profile restored from a
/// backup code is marked as already taught (see Profile.applyBackup), because
/// someone moving phones does not need to be shown the fire button again.

/// Where a step points. Anchors are registered by the widgets themselves.
class TutorialAnchors {
  static final Map<String, Rect> _rects = {};
  static final Map<String, BuildContext> _ctx = {};

  static void put(String id, Rect r, BuildContext c) {
    _rects[id] = r;
    _ctx[id] = c;
  }

  static void drop(String id) {
    _rects.remove(id);
    _ctx.remove(id);
  }

  static Rect? of(String id) => _rects[id];

  /// Scroll the anchor into view. A step that points at something below the
  /// fold is worse than no step at all: the spotlight lands off-screen, the
  /// blockers cover everything that IS on screen, and the player is stuck with
  /// nothing to tap.
  static void reveal(String id) {
    final c = _ctx[id];
    if (c == null || !c.mounted) return;
    try {
      Scrollable.ensureVisible(c,
          alignment: 0.5,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic);
    } catch (_) {
      // not inside a scrollable — nothing to do
    }
  }

  static void clear() {
    _rects.clear();
    _ctx.clear();
  }
}

/// Wrap any widget to make it targetable by the tour.
class TutorialAnchor extends StatefulWidget {
  final String id;
  final Widget child;
  const TutorialAnchor({super.key, required this.id, required this.child});

  @override
  State<TutorialAnchor> createState() => _TutorialAnchorState();
}

class _TutorialAnchorState extends State<TutorialAnchor> {
  final _key = GlobalKey();

  void _report() {
    if (!mounted) return;
    final ctx = _key.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final pos = box.localToGlobal(Offset.zero);
    TutorialAnchors.put(widget.id, pos & box.size, ctx);
  }

  @override
  Widget build(BuildContext context) {
    // report after every layout — screens scroll, and a stale rect would put
    // the spotlight on empty space
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    return KeyedSubtree(key: _key, child: widget.child);
  }

  @override
  void dispose() {
    TutorialAnchors.drop(widget.id);
    super.dispose();
  }
}

/// One beat of the tour.
class TutorialStep {
  /// Anchor id to spotlight. Null = a full-screen message with no target.
  final String? anchor;
  /// Fallback rect resolver for things that aren't widgets — the in-match
  /// controls, which are positioned by the player's own saved layout.
  final Rect Function(Size screen)? rect;
  final String title;
  final String body;
  /// Runs when the step is shown — used to put the profile into a known state.
  final void Function()? onShow;
  /// True when the player must tap the highlighted thing to continue; false
  /// shows a NEXT button instead.
  final bool tapTarget;
  /// Which screen this step belongs to, so the tour can wait for it.
  final String? screen;
  /// Move the player to this screen before showing the step.
  final String? goto;
  const TutorialStep({
    this.anchor,
    this.rect,
    required this.title,
    required this.body,
    this.onShow,
    this.tapTarget = false,
    this.screen,
    this.goto,
  });
}

/// Drives the tour. One instance, owned by the app.
class Tutorial extends ChangeNotifier {
  static final Tutorial instance = Tutorial._();
  Tutorial._();

  List<TutorialStep> _steps = const [];
  int _index = 0;
  bool _running = false;

  /// Set by the app: moves the player to a named screen. Steps that explain
  /// the profile have to put the player ON the profile first, or the
  /// spotlight would point at an anchor that isn't on screen.
  void Function(String screen)? navigator;

  void go(String screen) => navigator?.call(screen);

  bool get running => _running;
  int get index => _index;
  int get total => _steps.length;
  TutorialStep? get step =>
      _running && _index < _steps.length ? _steps[_index] : null;

  /// A skip button only appears after a few steps — long enough for the tour
  /// to have proven it is worth watching, early enough that nobody is trapped.
  bool get canSkip => _index >= 3;

  void start(List<TutorialStep> steps) {
    if (steps.isEmpty) return;
    _steps = steps;
    _index = 0;
    _running = true;
    _enter(steps.first);
    notifyListeners();
  }

  void next() {
    if (!_running) return;
    _index++;
    if (_index >= _steps.length) {
      finish();
      return;
    }
    Sfx.select();
    _enter(_steps[_index]);
    notifyListeners();
  }

  /// Jump to the first step tagged with [screen] — used when the tour follows
  /// the player into a match or onto the results page.
  void jumpToScreen(String screen) {
    if (!_running) return;
    for (var i = _index; i < _steps.length; i++) {
      if (_steps[i].screen == screen) {
        _index = i;
        _steps[i].onShow?.call();
        notifyListeners();
        return;
      }
    }
  }

  void _enter(TutorialStep s) {
    if (s.goto != null) navigator?.call(s.goto!);
    s.onShow?.call();
  }

  void skip() {
    Sfx.back();
    finish();
  }

  void finish() {
    _running = false;
    _steps = const [];
    _index = 0;
    Profile.instance.tutorialDone = true;
    Profile.instance.save();
    notifyListeners();
  }
}

/// The overlay: dim everything, cut a hole around the target, point at it.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({super.key});

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  /// Which step we have already scrolled into view, so the reveal runs once.
  int _revealedFor = -1;

  @override
  void initState() {
    super.initState();
    Tutorial.instance.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Tutorial.instance.removeListener(_onChange);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tutorial.instance;
    final step = t.step;
    // MUST stay a Positioned, even with nothing to show.
    //
    // A Stack sizes itself to its largest NON-positioned child, and every
    // other child of the app's root Stack is a Positioned.fill — which does
    // not contribute to sizing at all. Returning a bare SizedBox.shrink()
    // made this the only non-positioned child, so the Stack collapsed to 0x0
    // and clipped the entire app away.
    //
    // THAT was the blank screen, through every attempt at this feature. Not
    // an exception, not a paint failure, not a flex child — which is why
    // debug, profile and release all reported absolutely nothing wrong. Stay
    // positioned and the Stack keeps sizing off constraints.biggest.
    if (step == null) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }
    final screen = MediaQuery.of(context).size;

    Rect? target;
    // Belt and braces. This overlay once stopped the app presenting a single
    // frame, and a tutorial is never worth taking the game down for: if
    // anything about resolving the target misbehaves, the step simply loses
    // its spotlight and the tour carries on with a plain caption.
    try {
    if (step.rect != null) {
      target = step.rect!(screen);
    } else if (step.anchor != null) {
      // bring it on screen before pointing at it
      if (_revealedFor != t.index) {
        _revealedFor = t.index;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          TutorialAnchors.reveal(step.anchor!);
          if (mounted) setState(() {});
        });
      }
      target = TutorialAnchors.of(step.anchor!);
    }
    } catch (_) {
      target = null;
    }
    // an anchor that hasn't laid out yet: show the caption, skip the spotlight
    if (target != null && (target.isEmpty || !target.isFinite)) target = null;
    // A target that is off-screen (or barely on it) cannot be spotlighted or
    // tapped, so the step falls back to a plain "next" — being unable to
    // continue is the one failure a tutorial must never have.
    final visible = target != null &&
        target.bottom > 8 &&
        target.top < screen.height - 8 &&
        target.right > 8 &&
        target.left < screen.width - 8;
    if (!visible) target = null;
    final mustTap = step.tapTarget && target != null;

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final pulse = 0.5 + 0.5 * math.sin(_c.value * math.pi * 2);
          return Stack(
            children: [
              // The dim is painted, never tapped.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                      painter: _SpotlightPainter(target, pulse)),
                ),
              ),
              // Tap absorption. When the player has to press the real button,
              // the blockers are laid out AROUND the hole so the button
              // underneath still receives the tap; otherwise one sheet covers
              // everything so nobody wanders off mid-explanation.
              if (mustTap)
                ..._blockersAround(target!, screen)
              else
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: t.next,
                  ),
                ),
              if (target != null)
                _Hand(rect: target, pulse: pulse, screen: screen),
              _caption(context, step, target, screen, t, mustTap),
            ],
          );
        },
      ),
    );
  }

  /// Four absorbing panes around the spotlight, leaving the hole live.
  List<Widget> _blockersAround(Rect hole, Size screen) {
    final r = hole.inflate(10);
    Widget pane(double l, double t, double w, double h) => Positioned(
          left: l,
          top: t,
          width: w.clamp(0.0, screen.width),
          height: h.clamp(0.0, screen.height),
          child: const AbsorbPointer(child: SizedBox.expand()),
        );
    return [
      pane(0, 0, screen.width, r.top),
      pane(0, r.bottom, screen.width, screen.height - r.bottom),
      pane(0, r.top, r.left, r.height),
      pane(r.right, r.top, screen.width - r.right, r.height),
    ];
  }

  /// The caption card.
  ///
  /// Placement is done with Align rather than an absolute top offset: the card
  /// grows with however long the translated text is, and a guessed offset put
  /// the NEXT button off the bottom of the screen. Align cannot overflow, and
  /// the height cap plus a scroll view covers the worst case.
  Widget _caption(BuildContext context, TutorialStep step, Rect? target,
      Size screen, Tutorial t, bool mustTap) {
    // Sit opposite the spotlight so the card never covers what it explains.
    // With no target at all, sit dead centre.
    final Alignment align;
    if (target == null) {
      align = Alignment.center;
    } else {
      final targetIsHigh = target.center.dy < screen.height * 0.5;
      final x = ((target.center.dx / screen.width) * 2 - 1).clamp(-0.75, 0.75);
      align = Alignment(x.toDouble(), targetIsHigh ? 0.86 : -0.86);
    }
    return Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Align(
          alignment: align,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 330,
              maxHeight: screen.height - 24,
            ),
            child: TweenAnimationBuilder<double>(
              key: ValueKey(t.index),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutBack,
              builder: (_, v, child) => Transform.scale(
                scale: 0.92 + 0.08 * v,
                child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
              ),
              child: _card(context, step, t, mustTap),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(
      BuildContext context, TutorialStep step, Tutorial t, bool mustTap) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
      decoration: BoxDecoration(
        color: const Color(0xF210141C),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: ZR.primary.withValues(alpha: 0.85), width: 1.4),
        boxShadow: [
          BoxShadow(
              color: ZR.primary.withValues(alpha: 0.3),
              blurRadius: 30,
              spreadRadius: -6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ZR.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('${t.index + 1}/${t.total}',
                    style: ZR.mono(8, color: ZR.primary, spacing: 0.5)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text((step.title).toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ZR.display(19, color: ZR.primary, spacing: 1)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // the body is the part that varies most between languages
          Flexible(
            child: SingleChildScrollView(
              child: Text(step.body,
                  style: ZR.body(11.5, color: Colors.white70, height: 1.4)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (t.canSkip)
                GestureDetector(
                  onTap: () => _confirmSkip(context),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(('SKIP TUTORIAL').toUpperCase(),
                        style: ZR.mono(8, color: Colors.white30)),
                  ),
                ),
              const Spacer(),
              if (mustTap)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const _MiniHand(),
                  const SizedBox(width: 6),
                  Text(('TAP HERE').toUpperCase(),
                      style: ZR.display(15, color: ZR.primary)),
                ])
              else
                // A hand nudging the button, so even a step with nothing to
                // point at still tells you what to do next without reading.
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const _MiniHand(),
                  const SizedBox(width: 4),
                  _NextButton(
                    label: t.index == t.total - 1 ? 'START PLAYING' : 'NEXT',
                    onTap: t.next,
                  ),
                ]),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSkip(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZR.surface,
        title: Text(('SKIP TUTORIAL').toUpperCase(), style: ZR.display(20)),
        content: Text(
            'You can watch it again any time from the profile screen.',
            style: ZR.body(12, color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(('CANCEL').toUpperCase(),
                  style: ZR.display(16, color: ZR.primary))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(('SKIP TUTORIAL').toUpperCase(),
                  style: ZR.display(16, color: Colors.white38))),
        ],
      ),
    );
    if (sure == true) Tutorial.instance.skip();
  }
}

/// The caption's own NEXT button.
///
/// Deliberately NOT ZrButton: that lays its label out with a Flex child, and
/// a flex child inside a Row that can receive unbounded width throws on every
/// frame — which is how this overlay once stopped the whole app from
/// presenting a single frame. Nothing here flexes.
class _NextButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NextButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: ZR.cta(radius: 9),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              maxLines: 1,
              style: ZR.display(15,
                  color: const Color(0xFF10131A), spacing: 1)),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_forward,
              size: 14, color: Color(0xFF10131A)),
        ]),
      ),
    );
  }
}

/// A small pointing hand that nudges the button beside it. Used inside the
/// caption so every step has the "press this" cue, not just the ones with
/// something on screen to spotlight.
class _MiniHand extends StatefulWidget {
  const _MiniHand();

  @override
  State<_MiniHand> createState() => _MiniHandState();
}

class _MiniHandState extends State<_MiniHand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Transform.translate(
        // bob sideways toward the button it sits next to
        offset: Offset(-4 + 5 * Curves.easeInOut.transform(_c.value), 0),
        child: SizedBox(
          width: 22,
          height: 24,
          child: CustomPaint(
              painter: _HandPainter(pulse: _c.value, pointUp: false)),
        ),
      ),
    );
  }
}

/// Dim pass with a rounded hole punched out, plus a pulsing ring.
class _SpotlightPainter extends CustomPainter {
  final Rect? target;
  final double pulse;
  const _SpotlightPainter(this.target, this.pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    if (target == null) {
      canvas.drawRect(full, Paint()..color = const Color(0xD0000000));
      return;
    }
    final hole = target!.inflate(10 + 3 * pulse);
    final rr = RRect.fromRectAndRadius(hole, Radius.circular(hole.shortestSide * 0.35));
    // even-odd instead of saveLayer+clear: no offscreen render target, which
    // matters because this draws over a live match
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(full)
      ..addRRect(rr);
    canvas.drawPath(path, Paint()..color = const Color(0xD0000000));
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = ZR.primary.withValues(alpha: 0.65 + 0.35 * pulse));
    canvas.drawRRect(
        rr.inflate(6 * pulse),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = ZR.primary.withValues(alpha: 0.30 * (1 - pulse)));
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.target != target || old.pulse != pulse;
}

/// The pointing hand — bobs toward the target along the shortest edge, with a
/// tap ripple under it. This is the bit that makes "press this" unmistakable
/// without a word of text.
class _Hand extends StatelessWidget {
  final Rect rect;
  final double pulse;
  final Size screen;
  const _Hand({required this.rect, required this.pulse, required this.screen});

  @override
  Widget build(BuildContext context) {
    // approach from whichever side has room, so the hand never sits off-screen
    final fromBelow = rect.center.dy < screen.height * 0.62;
    final bob = 10 * pulse;
    final left = (rect.center.dx - 22).clamp(4.0, screen.width - 48);
    final top = fromBelow
        ? rect.bottom + 6 + bob
        : rect.top - 54 - bob;
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: SizedBox(
          width: 44,
          height: 48,
          child: CustomPaint(
              painter: _HandPainter(pulse: pulse, pointUp: !fromBelow)),
        ),
      ),
    );
  }
}

class _HandPainter extends CustomPainter {
  final double pulse;
  final bool pointUp;
  const _HandPainter({required this.pulse, required this.pointUp});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (!pointUp) {
      // flip so the fingertip points up at a target above
      canvas.translate(0, size.height);
      canvas.scale(1, -1);
    }
    final c = Offset(size.width / 2, size.height * 0.26);

    // tap ripple at the fingertip
    for (var i = 0; i < 2; i++) {
      final k = (pulse + i * 0.5) % 1.0;
      canvas.drawCircle(
          c,
          6 + 16 * k,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = ZR.primary.withValues(alpha: (1 - k) * 0.7));
    }

    final skin = Paint()..color = const Color(0xFFF4CBA2);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFF3A2A1E);

    // palm
    final palm = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(size.width / 2, size.height * 0.68),
            width: size.width * 0.62,
            height: size.height * 0.46),
        Radius.circular(size.width * 0.24));
    canvas.drawRRect(palm, skin);
    canvas.drawRRect(palm, line);

    // index finger, extended toward the target
    final finger = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(size.width / 2, size.height * 0.36),
            width: size.width * 0.26,
            height: size.height * 0.42),
        Radius.circular(size.width * 0.13));
    canvas.drawRRect(finger, skin);
    canvas.drawRRect(finger, line);

    // knuckle creases, so it reads as a hand rather than a mitten
    for (var i = 0; i < 2; i++) {
      final y = size.height * (0.62 + i * 0.11);
      canvas.drawLine(
          Offset(size.width * 0.36, y),
          Offset(size.width * 0.64, y),
          Paint()
            ..strokeWidth = 1.1
            ..color = const Color(0x553A2A1E));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HandPainter old) =>
      old.pulse != pulse || old.pointUp != pointUp;
}
