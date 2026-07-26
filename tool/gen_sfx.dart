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


// ---------------------------------------------------------------- UI sounds
//
// The menus were silent, which made them feel like a settings app bolted onto
// a game. These are deliberately small and dry: a UI sound you notice twice is
// a UI sound you mute.

/// Soft, short tap — the default for any button.
List<double> uiTap() {
  final n = (0.045 * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / n;
    final env = math.exp(-t * 16);
    return (sin(1400, i) * 0.55 + sin(2100, i) * 0.25) * env * 0.5;
  });
}

/// Two-tone rising click — moving forward: a tab, a nav destination.
List<double> uiSelect() {
  final n = (0.10 * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / n;
    final f = t < 0.45 ? 880.0 : 1320.0;
    final env = math.exp(-((t % 0.45) / 0.45) * 7) * (1 - t * 0.3);
    return sin(f, i) * env * 0.45;
  });
}

/// Two-tone falling click — going back / closing.
List<double> uiBack() {
  final n = (0.10 * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / n;
    final f = t < 0.45 ? 1180.0 : 720.0;
    final env = math.exp(-((t % 0.45) / 0.45) * 7) * (1 - t * 0.3);
    return sin(f, i) * env * 0.42;
  });
}

/// Bright confirm chord — a purchase, an equip, a claimed reward.
List<double> uiBuy() {
  final n = (0.42 * rate).round();
  const notes = [659.0, 988.0, 1319.0];
  return List<double>.generate(n, (i) {
    final t = i / n;
    var v = 0.0;
    for (var k = 0; k < notes.length; k++) {
      final start = k * 0.11;
      if (t < start) continue;
      final lt = (t - start) / (1 - start);
      v += sin(notes[k], i) * math.exp(-lt * 5.5);
    }
    // a little metallic shimmer on top so it reads as "coin"
    v += sin(2637, i) * math.exp(-t * 12) * 0.25;
    return v * 0.22;
  });
}

/// Low refusal buzz — can't afford it, invalid code.
List<double> uiDeny() {
  final n = (0.18 * rate).round();
  return List<double>.generate(n, (i) {
    final t = i / n;
    final saw = ((150 * i / rate) % 1.0) * 2 - 1;
    final gate = ((t * 6).floor() % 2 == 0) ? 1.0 : 0.25;
    return saw * gate * (1 - t) * 0.35;
  });
}

/// Air-moving whoosh under a screen transition.
List<double> uiWhoosh() {
  final n = (0.30 * rate).round();
  var lp = 0.0;
  return List<double>.generate(n, (i) {
    final t = i / n;
    final noise = rng.nextDouble() * 2 - 1;
    // one-pole low-pass that opens then closes: reads as movement, not static
    final k = 0.04 + 0.35 * math.sin(math.pi * t);
    lp += (noise - lp) * k;
    return lp * math.sin(math.pi * t) * 0.45;
  });
}

/// The menu bed: a slow, tense loop that sits under the whole front end.
///
/// Built to loop seamlessly — the length is a whole number of bars and the
/// tail is cross-faded into the head, so there is no click at the seam.
List<double> menuLoop() {
  const bpm = 76.0;
  const beats = 32; // 8 bars of 4
  final beat = 60.0 / bpm;
  final n = (beats * beat * rate).round();
  final out = List<double>.filled(n, 0.0);

  // A minor: root drone + fifth, detuned for movement
  for (var i = 0; i < n; i++) {
    final t = i / rate;
    final swell = 0.55 + 0.45 * math.sin(2 * math.pi * t / (beats * beat));
    out[i] += sin(55, i) * 0.30 * swell;
    out[i] += sin(82.5, i) * 0.13 * swell;
    out[i] += sin(110.4, i) * 0.10 * swell; // slight detune = slow chorus
  }

  // sparse pentatonic arpeggio, one note every two beats
  const notes = [440.0, 523.25, 659.25, 587.33, 440.0, 392.0, 523.25, 659.25];
  for (var b = 0; b < beats; b += 2) {
    final start = (b * beat * rate).round();
    final len = (1.1 * beat * rate).round();
    final f = notes[(b ~/ 2) % notes.length];
    for (var k = 0; k < len && start + k < n; k++) {
      final t = k / len;
      final env = math.exp(-t * 4.2) * (1 - math.exp(-t * 90));
      final i = start + k;
      out[i] += (sin(f, i) * 0.5 + sin(f * 2, i) * 0.12) * env * 0.34;
    }
  }

  // a soft heartbeat pulse on the downbeat of every bar
  for (var b = 0; b < beats; b += 4) {
    final start = (b * beat * rate).round();
    final len = (0.5 * rate).round();
    for (var k = 0; k < len && start + k < n; k++) {
      final t = k / len;
      out[start + k] += sin(48 - 14 * t, start + k) * math.exp(-t * 7) * 0.30;
    }
  }

  // breath of noise so it isn't clinically clean
  var lp = 0.0;
  for (var i = 0; i < n; i++) {
    final noise = rng.nextDouble() * 2 - 1;
    lp += (noise - lp) * 0.012;
    out[i] += lp * 0.10 * (0.6 + 0.4 * math.sin(2 * math.pi * i / rate / 7));
  }

  // cross-fade the tail into the head so the seam is inaudible
  final fade = (0.5 * rate).round();
  for (var k = 0; k < fade; k++) {
    final w = k / fade;
    out[k] = out[k] * w + out[n - fade + k] * (1 - w);
  }
  final body = out.sublist(0, n - fade);
  return body.map((v) => (v * 0.62).clamp(-1.0, 1.0)).toList();
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
    'ui_tap': uiTap(),
    'ui_select': uiSelect(),
    'ui_back': uiBack(),
    'ui_buy': uiBuy(),
    'ui_deny': uiDeny(),
    'ui_whoosh': uiWhoosh(),
    'menu_loop': menuLoop(),
  };
  files.forEach((name, samples) {
    final f = File('assets/sfx/$name.wav');
    f.writeAsBytesSync(wav(samples));
    print('wrote ${f.path} (${f.lengthSync()} bytes)');
  });
  print('done: ${files.length} sfx files');
}
