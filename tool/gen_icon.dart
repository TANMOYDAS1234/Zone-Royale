// Generates the app launcher icon (assets/icon.png) — the Zone Royale crosshair:
// a glowing amber scope with four white reticle blades on a dark tile. Rendered
// with pure Dart pixel math + a minimal PNG encoder (dart:io zlib), so no image
// tooling is needed. Run:  dart run tool/gen_icon.dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int W = 1024;

double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
double smooth(double a, double b, double x) {
  final t = clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
}

double lerp(double a, double b, double t) => a + (b - a) * t;

void main() {
  final px = Uint8List(W * W * 3);
  final half = W / 2.0;
  final cx = half, cy = half;

  // geometry (relative to half)
  final outerR = 0.60 * half, outerT = 0.052 * half;
  final innerR = 0.40 * half, innerT = 0.028 * half;
  final bInner = 0.14 * half, bOuter = 0.72 * half;
  final bWin = 0.022 * half, bWout = 0.095 * half;
  final dotR = 0.05 * half;
  final sigma = 0.20 * half;

  // colours
  final amber = [255.0, 176.0, 46.0];
  final glowC = [255.0, 120.0, 24.0];
  final white = [250.0, 250.0, 250.0];
  final bgIn = [30.0, 14.0, 10.0];
  final bgEdge = [8.0, 7.0, 11.0];

  for (var y = 0; y < W; y++) {
    for (var x = 0; x < W; x++) {
      final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
      final dist = math.sqrt(dx * dx + dy * dy);

      // 1) background: warm dark centre -> near-black edges
      final bt = smooth(0, half * 1.15, dist);
      final col = [
        lerp(bgIn[0], bgEdge[0], bt),
        lerp(bgIn[1], bgEdge[1], bt),
        lerp(bgIn[2], bgEdge[2], bt),
      ];

      // 2) additive amber glow around the outer ring
      final gd = dist - outerR;
      final glow = math.exp(-(gd * gd) / (2 * sigma * sigma)) * 0.85;
      for (var i = 0; i < 3; i++) {
        col[i] = math.min(255.0, col[i] + glowC[i] * glow);
      }

      // helper to composite an opaque colour with coverage a
      void over(List<double> c, double a) {
        if (a <= 0) return;
        for (var i = 0; i < 3; i++) {
          col[i] = col[i] * (1 - a) + c[i] * a;
        }
      }

      // 3) rings (amber annuli, anti-aliased)
      final ringOuter = 1 - smooth(outerT - 1.5, outerT + 1.5, (dist - outerR).abs());
      over(amber, ringOuter);
      final ringInner = 1 - smooth(innerT - 1.5, innerT + 1.5, (dist - innerR).abs());
      over(amber, ringInner);

      // 4) four white reticle blades (N/E/S/W), tapering inward
      double blade = 0;
      for (var k = 0; k < 4; k++) {
        final ang = k * math.pi / 2;
        final rr = dx * math.cos(ang) + dy * math.sin(ang); // along blade
        final pp = (-dx * math.sin(ang) + dy * math.cos(ang)).abs(); // perp
        if (rr >= bInner && rr <= bOuter) {
          final f = (rr - bInner) / (bOuter - bInner);
          final hw = lerp(bWin, bWout, f);
          blade = math.max(blade, 1 - smooth(hw - 1.5, hw + 1.5, pp));
        }
      }
      over(white, blade);

      // 5) centre dot
      over(white, 1 - smooth(dotR - 1.5, dotR + 1.5, dist));

      final o = (y * W + x) * 3;
      px[o] = col[0].round().clamp(0, 255);
      px[o + 1] = col[1].round().clamp(0, 255);
      px[o + 2] = col[2].round().clamp(0, 255);
    }
  }

  Directory('assets').createSync(recursive: true);
  File('assets/icon.png').writeAsBytesSync(_png(px, W, W));
  print('wrote assets/icon.png (${W}x$W)');
}

// ---- minimal PNG encoder (RGB, 8-bit) ----
Uint8List _png(Uint8List rgb, int w, int h) {
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0); // filter: none
    raw.add(Uint8List.sublistView(rgb, y * w * 3, (y + 1) * w * 3));
  }
  final idat = ZLibCodec(level: 6).encode(raw.toBytes());

  final out = BytesBuilder();
  out.add([137, 80, 78, 71, 13, 10, 26, 10]); // signature

  void chunk(String type, List<int> data) {
    final len = data.length;
    out.add([(len >> 24) & 255, (len >> 16) & 255, (len >> 8) & 255, len & 255]);
    final td = <int>[...type.codeUnits, ...data];
    out.add(td);
    final crc = _crc32(td);
    out.add([(crc >> 24) & 255, (crc >> 16) & 255, (crc >> 8) & 255, crc & 255]);
  }

  final ihdr = <int>[
    (w >> 24) & 255, (w >> 16) & 255, (w >> 8) & 255, w & 255,
    (h >> 24) & 255, (h >> 16) & 255, (h >> 8) & 255, h & 255,
    8, 2, 0, 0, 0, // bitdepth 8, colour type 2 (RGB)
  ];
  chunk('IHDR', ihdr);
  chunk('IDAT', idat);
  chunk('IEND', const []);
  return out.toBytes();
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
