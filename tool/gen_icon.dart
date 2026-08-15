// Generates the app launcher icon (assets/icon.png) — the ZONE ROYALE mark:
// a medal/shield silhouette holding a crosshair ring with a four-point star,
// in amber on a near-black plate. Same geometry as `ZrEmblemPainter` in
// lib/ui/logo.dart, so the launcher icon and the in-app logo always match.
//
// Pure Dart pixel math + a minimal PNG encoder (dart:io zlib) — no image
// tooling needed. Run:  dart run tool/gen_icon.dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int kSize = 1024;
const int kSamples = 3; // supersampling per axis (3x3 = 9 samples/pixel)

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
double _lerp(double a, double b, double t) => a + (b - a) * t;

// (The crosshair-ring and star constants the old outlined mark used are
// gone; the mark is a filled shield with a Z cut out of it now.)

/// Everything is expressed in "unit" space: the emblem lives in -0.5..0.5 on
/// both axes — the same geometry as `ZrMark` in lib/ui/logo.dart.
const List<List<double>> _shield = [
  [-0.35, -0.40],
  [0.35, -0.40],
  [0.35, 0.02],
  [0.31, 0.16],
  [0.23, 0.28],
  [0.12, 0.37],
  [0.0, 0.43],
  [-0.12, 0.37],
  [-0.23, 0.28],
  [-0.31, 0.16],
  [-0.35, 0.02],
];
const double _notchW = 0.075;
const double _notchH = 0.10;
const double _notchX = 0.115;

/// Distance from (px,py) to the segment (ax,ay)-(bx,by).
double _segDist(
    double px, double py, double ax, double ay, double bx, double by) {
  final vx = bx - ax, vy = by - ay;
  final wx = px - ax, wy = py - ay;
  final len2 = vx * vx + vy * vy;
  var t = len2 == 0 ? 0.0 : (wx * vx + wy * vy) / len2;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  final dx = px - (ax + vx * t), dy = py - (ay + vy * t);
  return math.sqrt(dx * dx + dy * dy);
}

/// Point-in-polygon for the shield outline.
bool _inShield(double x, double y) {
  var inside = false;
  for (var i = 0, j = _shield.length - 1; i < _shield.length; j = i++) {
    final xi = _shield[i][0], yi = _shield[i][1];
    final xj = _shield[j][0], yj = _shield[j][1];
    if ((yi > y) != (yj > y) &&
        x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

// The Z, as three thick strokes. Z for Zone — a letterform is the single most
// recognisable thing you can put in a small icon, and it survives being shrunk
// to a 48px launcher tile in a way a fine crosshair never does.
const double _zHalf = 0.046; // half thickness
const List<List<double>> _zStrokes = [
  [-0.165, -0.185, 0.165, -0.185], // top bar
  [0.165, -0.185, -0.165, 0.165], // diagonal
  [-0.165, 0.165, 0.165, 0.165], // bottom bar
];

bool _inZ(double x, double y) {
  for (final st in _zStrokes) {
    if (_segDist(x, y, st[0], st[1], st[2], st[3]) <= _zHalf) return true;
  }
  return false;
}

/// The mark: a SOLID shield with the Z cut out of it, two scope ticks either
/// side, and the ribbon notches along the top.
///
/// The old mark was an outlined shield holding a crosshair ring and a star —
/// four separate thin shapes, which turns to mush at launcher size. A filled
/// silhouette with one bold letter knocked through it reads at any scale.
bool _inEmblem(double x, double y) {
  // ribbon notches punched through the top edge
  final inNotch = y <= -0.40 + _notchH &&
      y >= -0.42 &&
      ((x >= _notchX && x <= _notchX + _notchW) ||
          (x <= -_notchX && x >= -_notchX - _notchW));
  if (inNotch) return false;

  if (_inShield(x, y)) {
    // the Z is a hole in the shield, not a shape on top of it
    return !_inZ(x, y);
  }

  // two scope ticks flanking the shield, so it still reads as a sight
  if (y.abs() <= _tickHalf) {
    final ax = x.abs();
    if (ax >= _tickNear && ax <= _tickFar) return true;
  }
  return false;
}

const double _tickHalf = 0.020;
const double _tickNear = 0.385;
const double _tickFar = 0.455;

/// Rounded-square plate mask (the icon background shape).
bool _inPlate(double x, double y) {
  const half = 0.5, r = 0.14;
  final ax = x.abs(), ay = y.abs();
  if (ax <= half - r || ay <= half - r) return ax <= half && ay <= half;
  final dx = ax - (half - r), dy = ay - (half - r);
  return dx * dx + dy * dy <= r * r;
}

void main() {
  final px = Uint8List(kSize * kSize * 3);
  const amber = [255.0, 176.0, 46.0];
  const amberLite = [255.0, 217.0, 138.0];
  const plateIn = [26.0, 33.0, 44.0]; // #1A212C
  const plateEdge = [10.0, 12.0, 18.0];
  const outside = [5.0, 7.0, 12.0]; // matches the app background

  for (var iy = 0; iy < kSize; iy++) {
    for (var ix = 0; ix < kSize; ix++) {
      var plate = 0.0, mark = 0.0;
      for (var sy = 0; sy < kSamples; sy++) {
        for (var sx = 0; sx < kSamples; sx++) {
          final ux = (ix + (sx + 0.5) / kSamples) / kSize - 0.5;
          final uy = (iy + (sy + 0.5) / kSamples) / kSize - 0.5;
          // the emblem is drawn slightly smaller than the plate
          if (_inPlate(ux / 0.94, uy / 0.94)) plate += 1;
          if (_inEmblem(ux / 0.86, uy / 0.86)) mark += 1;
        }
      }
      const total = kSamples * kSamples;
      plate /= total;
      mark /= total;

      // plate: warm-dark centre fading to near-black at the edges
      final dist = math.sqrt(math.pow(ix / kSize - 0.5, 2) +
              math.pow(iy / kSize - 0.5, 2)) *
          2;
      final t = _clamp01(dist);
      final base = [
        _lerp(plateIn[0], plateEdge[0], t),
        _lerp(plateIn[1], plateEdge[1], t),
        _lerp(plateIn[2], plateEdge[2], t),
      ];
      final col = [
        _lerp(outside[0], base[0], plate),
        _lerp(outside[1], base[1], plate),
        _lerp(outside[2], base[2], plate),
      ];

      // amber glow around the mark, then the mark itself (lit from top-left)
      final glow = _clamp01(mark * 1.4) * 0.35;
      for (var i = 0; i < 3; i++) {
        col[i] = math.min(255.0, col[i] + amber[i] * glow * 0.35);
      }
      final lit = _clamp01(0.5 - (iy / kSize - 0.5) * 0.9); // top brighter
      final markCol = [
        _lerp(amber[0], amberLite[0], lit),
        _lerp(amber[1], amberLite[1], lit),
        _lerp(amber[2], amberLite[2], lit),
      ];
      for (var i = 0; i < 3; i++) {
        col[i] = _lerp(col[i], markCol[i], mark);
      }

      final o = (iy * kSize + ix) * 3;
      px[o] = col[0].round().clamp(0, 255);
      px[o + 1] = col[1].round().clamp(0, 255);
      px[o + 2] = col[2].round().clamp(0, 255);
    }
  }

  final file = File('assets/icon.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(_encodePng(px, kSize, kSize));
  print('wrote ${file.path} (${kSize}x$kSize)');

  // Second pass: the branding mark used by the native launch screen.
  //
  // Two things matter here and both were wrong before:
  //  * TRANSPARENT background. The file used to be opaque RGB, so the splash
  //    showed a black square sitting on the dark-blue splash colour.
  //  * ROOM around the mark. The shield is taller than it is wide and its
  //    point runs past the canonical box, so at the old scale the bottom tip
  //    was cropped off. It is drawn smaller and nudged up to sit centred.
  const brand = 768;
  const fit = 0.60; // fraction of the canvas the emblem may occupy
  const shiftY = -0.02; // the shield's mass sits low; lift it to optical centre
  final bp = Uint8List(brand * brand * 4);
  for (var iy = 0; iy < brand; iy++) {
    for (var ix = 0; ix < brand; ix++) {
      var mark = 0.0;
      for (var sy = 0; sy < kSamples; sy++) {
        for (var sx = 0; sx < kSamples; sx++) {
          final ux = (ix + (sx + 0.5) / kSamples) / brand - 0.5;
          final uy = (iy + (sy + 0.5) / kSamples) / brand - 0.5 - shiftY;
          if (_inEmblem(ux / fit, uy / fit)) mark += 1;
        }
      }
      mark /= kSamples * kSamples;
      final lit = _clamp01(0.5 - (iy / brand - 0.5) * 0.9);
      final o = (iy * brand + ix) * 4;
      // premultiplied-safe: colour is the amber gradient, alpha is coverage
      bp[o] = 255;
      bp[o + 1] = _lerp(176, 217, lit).round().clamp(0, 255);
      bp[o + 2] = _lerp(46, 138, lit).round().clamp(0, 255);
      bp[o + 3] = (mark * 255).round().clamp(0, 255);
    }
  }
  final logo = File('assets/branding/logo.png');
  logo.parent.createSync(recursive: true);
  logo.writeAsBytesSync(_encodePngRgba(bp, brand, brand));
  print('wrote ${logo.path} (${brand}x$brand)');
}

// ---------------------------------------------------------------- PNG writer
Uint8List _encodePng(Uint8List rgb, int w, int h) {
  final raw = Uint8List(h * (w * 3 + 1));
  var o = 0;
  for (var y = 0; y < h; y++) {
    raw[o++] = 0; // filter: none
    raw.setRange(o, o + w * 3, rgb, y * w * 3);
    o += w * 3;
  }
  final out = BytesBuilder();
  out.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  out.add(_chunk('IHDR', _ihdr(w, h)));
  out.add(_chunk('IDAT', Uint8List.fromList(ZLibCodec(level: 6).encode(raw))));
  out.add(_chunk('IEND', Uint8List(0)));
  return out.toBytes();
}

/// PNG writer for images WITH an alpha channel (colour type 6).
Uint8List _encodePngRgba(Uint8List rgba, int w, int h) {
  final raw = Uint8List(h * (w * 4 + 1));
  var o = 0;
  for (var y = 0; y < h; y++) {
    raw[o++] = 0; // filter: none
    raw.setRange(o, o + w * 4, rgba, y * w * 4);
    o += w * 4;
  }
  final out = BytesBuilder();
  out.add(Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]));
  out.add(_chunk('IHDR', _ihdr(w, h, alpha: true)));
  out.add(_chunk('IDAT', Uint8List.fromList(ZLibCodec(level: 6).encode(raw))));
  out.add(_chunk('IEND', Uint8List(0)));
  return out.toBytes();
}

Uint8List _ihdr(int w, int h, {bool alpha = false}) {
  final b = ByteData(13);
  b.setUint32(0, w);
  b.setUint32(4, h);
  b.setUint8(8, 8); // bit depth
  b.setUint8(9, alpha ? 6 : 2); // 6 = truecolour + alpha, 2 = truecolour
  return b.buffer.asUint8List();
}

Uint8List _chunk(String type, Uint8List data) {
  final b = BytesBuilder();
  final len = ByteData(4)..setUint32(0, data.length);
  b.add(len.buffer.asUint8List());
  final body = Uint8List.fromList([...type.codeUnits, ...data]);
  b.add(body);
  final crc = ByteData(4)..setUint32(0, _crc32(body));
  b.add(crc.buffer.asUint8List());
  return b.toBytes();
}

int _crc32(Uint8List data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
