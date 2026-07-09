// Generates the game's sound effects as real .wav files under assets/sfx/.
// The waveforms are synthesised here (no recordings needed), baked to disk once,
// then shipped as assets and played with AssetSource — the most reliable audio
// path on Android (in-memory byte sources are flaky with the low-latency player).
//
// Run from the project root:  dart run tool/gen_sfx.dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int rate = 22050;
final math.Random rng = math.Random(7); // fixed seed -> reproducible builds

double sin(double freq, int i) => math.sin(2 * math.pi * freq * i / rate);

Uint8List wav(List<double> samples) {
  final n = samples.length;
  final data = ByteData(44 + n * 2);
  void str(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(off + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

List<double> gunShot() {
  final n = (0.12 * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / n;
    final env = (1 - t) * (1 - t);
    final noise = rng.nextDouble() * 2 - 1;
    return (noise * 0.7 + sin(80, i) * 0.5) * env * 0.9;
  });
}

List<double> hitBlip() {
  final n = (0.06 * rate).round();
  return List<double>.generate(n, (i) => sin(620, i) * (1 - i / n) * 0.6);
}

List<double> thud() {
  final n = (0.16 * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / n;
    return sin(200 - 120 * t, i) * (1 - t) * (1 - t) * 0.7;
  });
}

List<double> blip() {
  final n = (0.12 * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / n;
    return sin(500 + 500 * t, i) * (1 - t) * 0.5;
  });
}

List<double> reloadClicks() {
  final n = (0.2 * rate).round();
  return List<double>.generate(n, (i) {
    final ph = i / rate;
    var v = 0.0;
    for (final ct in const [0.0, 0.1]) {
      final dt = ph - ct;
      if (dt >= 0 && dt < 0.03) {
        v += (rng.nextDouble() * 2 - 1) * (1 - dt / 0.03) * 0.5;
      }
    }
    return v;
  });
}

List<double> explosion() {
  final n = (0.5 * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / n;
    final env = math.pow(1 - t, 1.5).toDouble();
    final noise = rng.nextDouble() * 2 - 1;
    return (noise * 0.6 + sin(60 - 30 * t, i) * 0.6) * env * 0.95;
  });
}

List<double> descend() {
  final n = (0.4 * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / n;
    return sin(300 - 200 * t, i) * (1 - t) * 0.6;
  });
}

List<double> fanfare() {
  final n = (0.6 * rate).round();
  const notes = [523.0, 659.0, 784.0];
  return List<double>.generate(n, (i) {
    final t = i / n;
    final seg = (t * 3).floor().clamp(0, 2);
    final localT = (t * 3) - seg;
    return sin(notes[seg], i) * ((1 - localT) * 0.5 + 0.2) * 0.5;
  });
}

List<double> sweep() {
  final n = (0.3 * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / n;
    return sin(300 + 700 * t, i) * math.sin(math.pi * t) * 0.5;
  });
}

List<double> zonePulse() {
  final n = (0.5 * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / n;
    final saw = ((80 * i / rate) % 1.0) * 2 - 1;
    return saw * math.sin(math.pi * t) * 0.4;
  });
}

void main() {
  final dir = Directory('assets/sfx');
  dir.createSync(recursive: true);
  final files = <String, List<double>>{
    'shoot': gunShot(),
    'hit': hitBlip(),
    'hurt': thud(),
    'pickup': blip(),
    'reload': reloadClicks(),
    'boom': explosion(),
    'death': descend(),
    'win': fanfare(),
    'skill': sweep(),
    'zone': zonePulse(),
  };
  files.forEach((name, samples) {
    final f = File('assets/sfx/$name.wav');
    f.writeAsBytesSync(wav(samples));
    print('wrote ${f.path} (${f.lengthSync()} bytes)');
  });
  print('done: ${files.length} sfx files');
}
