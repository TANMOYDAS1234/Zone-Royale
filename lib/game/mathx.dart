import 'dart:math' as math;
import 'package:flame/components.dart' show Vector2;

const double kTau = math.pi * 2;

final math.Random _rng = math.Random();

double clampd(double v, double a, double b) => v < a ? a : (v > b ? b : v);
double lerpd(double a, double b, double t) => a + (b - a) * t;

double randRange(double a, double b) => a + _rng.nextDouble() * (b - a);
int randIntRange(int a, int b) => a + _rng.nextInt(b - a + 1);
bool chance(double p) => _rng.nextDouble() < p;

T choice<T>(List<T> list) => list[_rng.nextInt(list.length)];

T weighted<T>(List<MapEntry<T, int>> table) {
  var total = 0;
  for (final e in table) {
    total += e.value;
  }
  var r = _rng.nextDouble() * total;
  for (final e in table) {
    r -= e.value;
    if (r <= 0) return e.key;
  }
  return table.last.key;
}

/// Rough standard-normal sample in ~[-1, 1] (sum of uniforms).
double gaussian() {
  return (_rng.nextDouble() +
          _rng.nextDouble() +
          _rng.nextDouble() +
          _rng.nextDouble() -
          2) /
      2;
}

double angleOf(Vector2 v) => math.atan2(v.y, v.x);
Vector2 fromAngle(double r, [double m = 1]) =>
    Vector2(math.cos(r) * m, math.sin(r) * m);

/// Normalize, but return a zero vector instead of NaN when the input is ~zero.
Vector2 safeNorm(Vector2 v) {
  final l = v.length;
  return l < 1e-6 ? Vector2.zero() : v / l;
}

/// Interpolate along the shortest arc between two angles.
double angleLerp(double a, double b, double t) {
  var d = ((b - a + math.pi) % kTau) - math.pi;
  if (d < -math.pi) d += kTau;
  return a + d * t;
}

/// Push vector that separates a circle from an axis-aligned rect,
/// or null when they do not overlap. Add it to the circle centre to resolve.
Vector2? circleRectPush(
  double cx, double cy, double r,
  double rx, double ry, double rw, double rh,
) {
  final nx = clampd(cx, rx, rx + rw);
  final ny = clampd(cy, ry, ry + rh);
  final dx = cx - nx;
  final dy = cy - ny;
  final d2 = dx * dx + dy * dy;
  if (d2 > r * r) return null;
  if (d2 > 1e-6) {
    final d = math.sqrt(d2);
    final o = r - d;
    return Vector2(dx / d * o, dy / d * o);
  }
  // centre lies inside the rect -> push out along the shallowest edge
  final left = cx - rx;
  final right = rx + rw - cx;
  final top = cy - ry;
  final bottom = ry + rh - cy;
  final m = math.min(math.min(left, right), math.min(top, bottom));
  if (m == left) return Vector2(-(left + r), 0);
  if (m == right) return Vector2(right + r, 0);
  if (m == top) return Vector2(0, -(top + r));
  return Vector2(0, bottom + r);
}

/// First intersection t in [0,1] of segment a->b with a circle, or -1.
double segCircle(
  double ax, double ay, double bx, double by,
  double cx, double cy, double r,
) {
  final dx = bx - ax;
  final dy = by - ay;
  final fx = ax - cx;
  final fy = ay - cy;
  final a = dx * dx + dy * dy;
  if (a < 1e-9) return (fx * fx + fy * fy <= r * r) ? 0 : -1;
  final b = 2 * (fx * dx + fy * dy);
  final c = fx * fx + fy * fy - r * r;
  var disc = b * b - 4 * a * c;
  if (disc < 0) return -1;
  disc = math.sqrt(disc);
  final t1 = (-b - disc) / (2 * a);
  final t2 = (-b + disc) / (2 * a);
  if (t1 >= 0 && t1 <= 1) return t1;
  if (t2 >= 0 && t2 <= 1) return t2;
  if (t1 < 0 && t2 > 0) return 0; // segment starts inside the circle
  return -1;
}

/// Entry t in [0,1] of segment a->b with an AABB, or -1 (0 if it starts inside).
double segRect(
  double ax, double ay, double bx, double by,
  double rx, double ry, double rw, double rh,
) {
  final dx = bx - ax;
  final dy = by - ay;
  var tmin = 0.0;
  var tmax = 1.0;
  for (var axis = 0; axis < 2; axis++) {
    final p = axis == 0 ? ax : ay;
    final d = axis == 0 ? dx : dy;
    final lo = axis == 0 ? rx : ry;
    final hi = axis == 0 ? rx + rw : ry + rh;
    if (d.abs() < 1e-9) {
      if (p < lo || p > hi) return -1;
    } else {
      var t1 = (lo - p) / d;
      var t2 = (hi - p) / d;
      if (t1 > t2) {
        final tmp = t1;
        t1 = t2;
        t2 = tmp;
      }
      tmin = math.max(tmin, t1);
      tmax = math.min(tmax, t2);
      if (tmin > tmax) return -1;
    }
  }
  return tmin;
}
