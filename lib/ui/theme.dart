import 'package:flutter/material.dart';

/// ZONE ROYALE design system — one place for every colour, type style and
/// surface treatment in the app. Screens compose from here instead of
/// hard-coding hexes, so a brand tweak is a one-file change.
///
/// Palette and type come straight from the tactical UI kit:
///   primary   #FFB02E   amber — CTAs, XP, coins, selection
///   secondary #37D0FF   cyan  — info, secondary actions, safe zone
///   tertiary  #7FE8FF   ice   — shield tech, highlights
///   neutral   #8B8B8C   grey  — muted copy, disabled
class ZR {
  // ---------------- colour ----------------
  static const primary = Color(0xFFFFB02E);
  static const primaryLite = Color(0xFFFFD98A);
  static const primaryDeep = Color(0xFFE08A00);
  static const secondary = Color(0xFF37D0FF);
  static const tertiary = Color(0xFF7FE8FF);
  static const danger = Color(0xFFFF5A5F);
  static const success = Color(0xFF52E06A);
  static const neutral = Color(0xFF8B8B8C);

  /// Backgrounds, darkest first.
  static const bg = Color(0xFF05070C);
  static const bgAlt = Color(0xFF080B12);
  static const surface = Color(0xFF12161E);
  static const surfaceHi = Color(0xFF1A202B);
  static const line = Color(0x1AFFFFFF);
  static const lineStrong = Color(0x33FFFFFF);

  // ---------------- type ----------------
  /// Big condensed headline. Bebas Neue is caps-only by design.
  static TextStyle display(double size,
          {Color color = Colors.white, double spacing = 1.5, double? height}) =>
      TextStyle(
        fontFamily: 'Display',
        fontSize: size,
        color: color,
        letterSpacing: spacing,
        height: height,
      );

  static TextStyle body(double size,
          {Color color = Colors.white,
          FontWeight weight = FontWeight.w500,
          double spacing = 0,
          double? height}) =>
      TextStyle(
        fontFamily: 'Body',
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: spacing,
        height: height,
      );

  /// Tactical readouts: codes, coordinates, pings, labels.
  static TextStyle mono(double size,
          {Color color = neutral,
          FontWeight weight = FontWeight.w500,
          double spacing = 1}) =>
      TextStyle(
        fontFamily: 'Mono',
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: spacing,
      );

  // ---------------- surfaces ----------------
  /// The standard panel: near-black glass with a hairline border.
  static BoxDecoration panel({
    Color? border,
    double radius = 14,
    Color? fill,
    bool glow = false,
  }) =>
      BoxDecoration(
        color: fill ?? surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? line),
        boxShadow: glow
            ? [
                BoxShadow(
                    color: (border ?? primary).withValues(alpha: 0.28),
                    blurRadius: 22,
                    spreadRadius: -6)
              ]
            : null,
      );

  /// A selected/active panel — amber edge and a soft outer glow.
  static BoxDecoration panelActive({double radius = 14, Color color = primary}) =>
      BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color, width: 1.6),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.32),
              blurRadius: 20,
              spreadRadius: -6)
        ],
      );

  /// Primary call-to-action fill (DROP IN, CLAIM, START MISSION).
  static BoxDecoration cta({double radius = 12}) => BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primaryLite, primary, primaryDeep],
          stops: [0.0, 0.45, 1.0],
        ),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
              color: primary.withValues(alpha: 0.45),
              blurRadius: 26,
              spreadRadius: -6),
        ],
      );

  /// The faint tactical grid used behind every screen.
  static const gridColor = Color(0x0DFFFFFF);
}

/// A fixed design canvas that scales to the screen.
///
/// This is what makes the whole UI genuinely responsive. Every screen is laid
/// out against a constant [designHeight] (the vertical rhythm the mockups were
/// drawn at) and then scaled to whatever the device actually has, with the
/// width left free to flex. A short 360dp landscape phone and a 900dp tablet
/// therefore get the *same* proportions — no clipped chips, no giant text, no
/// per-device tweaking.
class ZrCanvas extends StatelessWidget {
  final Widget child;
  final double designHeight;
  /// Never scale below this, or a very short screen would make text unreadable.
  final double minScale;
  final double maxScale;
  const ZrCanvas({
    super.key,
    required this.child,
    this.designHeight = 400,
    this.minScale = 0.7,
    this.maxScale = 2.2,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (!box.hasBoundedHeight || box.maxHeight <= 0) return child;
      final scale =
          (box.maxHeight / designHeight).clamp(minScale, maxScale).toDouble();
      // FittedBox, not OverflowBox + Transform: it scales AND transforms hit
      // testing correctly. The hand-rolled version painted in the right place
      // but sent taps to the wrong widget — a tap on the bottom nav was
      // landing on the tabs at the top of the screen.
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: box.maxWidth / scale,
            height: box.maxHeight / scale,
            child: child,
          ),
        ),
      );
    });
  }
}

/// Faint blueprint grid + vignette. Every screen sits on this so the app feels
/// like one continuous piece of hardware rather than a stack of pages.
class TacticalBackdrop extends StatelessWidget {
  final Widget child;
  final double cell;
  const TacticalBackdrop({super.key, required this.child, this.cell = 46});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ZR.bg,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _GridPainter(cell)),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 1.1,
                    colors: [Colors.transparent, Color(0xCC000000)],
                    stops: [0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final double cell;
  const _GridPainter(this.cell);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = ZR.gridColor
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.cell != cell;
}

/// The primary button used for DROP IN / START MISSION / CLAIM REWARDS.
class ZrButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool expand;
  final double height;
  final double fontSize;
  const ZrButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.expand = true,
    this.height = 54,
    this.fontSize = 22,
  });

  @override
  State<ZrButton> createState() => _ZrButtonState();
}

class _ZrButtonState extends State<ZrButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          width: widget.expand ? double.infinity : null,
          height: widget.height,
          padding: widget.expand
              ? null
              : const EdgeInsets.symmetric(horizontal: 26),
          alignment: Alignment.center,
          decoration: enabled
              ? ZR.cta()
              : BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon,
                    size: widget.fontSize,
                    color: enabled ? const Color(0xFF10131A) : Colors.white30),
                const SizedBox(width: 10),
              ],
              Text(widget.label,
                  style: ZR.display(widget.fontSize,
                      color:
                          enabled ? const Color(0xFF10131A) : Colors.white30,
                      spacing: 2)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Outlined secondary action (CUSTOM ROOM, QUICK MATCH, CHANGE SETTINGS).
class ZrGhostButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color color;
  final double height;
  const ZrGhostButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.color = ZR.secondary,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.75)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 9),
            ],
            Text(label,
                style: ZR.display(16, color: color, spacing: 1.6)),
          ],
        ),
      ),
    );
  }
}

/// Small uppercase section label with a leading accent bar.
class ZrSectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const ZrSectionLabel(this.text, {super.key, this.color = ZR.primary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 14, color: color),
        const SizedBox(width: 8),
        Text(text.toUpperCase(),
            style: ZR.mono(11, color: Colors.white70, spacing: 2)),
      ],
    );
  }
}
