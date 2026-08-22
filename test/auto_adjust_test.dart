import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/data/services/auto_adjust.dart';

/// Auto is only worth a button if it answers the frame in front of it: a dark
/// frame opens up, a blown one comes down, a flat one gets stretched, and one
/// that is already right is left alone.
void main() {
  /// A block of one colour, as the raw RGBA the analyser reads.
  Uint8List flat(int r, int g, int b, {int pixels = 4096}) {
    final out = Uint8List(pixels * 4);
    for (var i = 0; i < pixels; i++) {
      out[i * 4] = r;
      out[i * 4 + 1] = g;
      out[i * 4 + 2] = b;
      out[i * 4 + 3] = 255;
    }
    return out;
  }

  /// A frame that runs from [lo] to [hi] in even steps — a real histogram
  /// rather than a single spike.
  Uint8List ramp(int lo, int hi, {int pixels = 4096}) {
    final out = Uint8List(pixels * 4);
    for (var i = 0; i < pixels; i++) {
      final v = lo + ((hi - lo) * i ~/ (pixels - 1));
      out[i * 4] = v;
      out[i * 4 + 1] = v;
      out[i * 4 + 2] = v;
      out[i * 4 + 3] = 255;
    }
    return out;
  }

  test('a dark frame is opened up', () {
    final a = AutoAdjust.measure(ramp(0, 90));
    expect(a.brightness, greaterThan(0),
        reason: 'a frame sitting in the shadows was not lifted');
  });

  test('a blown frame is brought down', () {
    final a = AutoAdjust.measure(ramp(190, 255));
    expect(a.brightness, lessThan(0),
        reason: 'a frame sitting in the highlights was not pulled back');
  });

  test('a flat frame is stretched', () {
    // Half the range, centred: exposure is fine, contrast is not.
    final a = AutoAdjust.measure(ramp(64, 190));
    expect(a.contrast, greaterThan(0),
        reason: 'a frame using half the range was not given contrast');
  });

  test('a frame already using the range is left alone', () {
    final a = AutoAdjust.measure(ramp(0, 255));
    expect(a.brightness.abs(), lessThan(0.05));
    expect(a.contrast.abs(), lessThan(0.05));
  });

  test('a monochrome frame keeps its colour choice', () {
    final a = AutoAdjust.measure(ramp(0, 255));
    expect(a.saturation, 0,
        reason: 'grey footage was pushed towards colour it does not have');
  });

  test('a flat-coloured frame is given some colour back', () {
    // A muted blue-grey: some chroma, but not much.
    final a = AutoAdjust.measure(flat(110, 122, 140));
    expect(a.saturation, greaterThan(0));
  });

  test('an already saturated frame is not pushed further', () {
    final a = AutoAdjust.measure(flat(220, 30, 30));
    expect(a.saturation, 0);
  });

  test('an empty frame is answered with nothing rather than a crash', () {
    expect(AutoAdjust.measure(Uint8List(0)).isNeutral, isTrue);
  });
}
