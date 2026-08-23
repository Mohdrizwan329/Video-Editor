import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/data/models/hsl_grade.dart';

/// HSL is the tool that grades one colour without touching its neighbours.
/// If a band leaks into the next one, or grey picks up a tint, the tool is
/// worse than not having it — so those are what these check.
void main() {
  int band(String name) => HslGrade.bandNames.indexOf(name);

  test('the weights always sum to one, all the way round the wheel', () {
    for (var d = 0; d < 360; d++) {
      final w = HslGrade.weightsFor(d.toDouble());
      final sum = w.fold<double>(0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-9), reason: 'hue $d° sums to $sum');
    }
  });

  test('a band centre belongs entirely to that band', () {
    for (var i = 0; i < HslGrade.bandCount; i++) {
      final w = HslGrade.weightsFor(HslGrade.bandCentres[i]);
      expect(
        w[i],
        closeTo(1.0, 1e-9),
        reason: '${HslGrade.bandNames[i]} does not own its own centre',
      );
    }
  });

  test('the wheel wraps: just under 360° is shared with red', () {
    final w = HslGrade.weightsFor(359);
    expect(w[band('Red')], greaterThan(0));
    expect(w[band('Magenta')], greaterThan(0));
  });

  test('an untouched grade returns the colour it was given', () {
    final g = HslGrade();
    expect(g.apply(0.8, 0.4, 0.2), (0.8, 0.4, 0.2));
  });

  test('grey is left alone even with every band pushed', () {
    final g = HslGrade();
    for (var i = 0; i < HslGrade.bandCount; i++) {
      g.hue[i] = 1;
      g.saturation[i] = 1;
      g.luminance[i] = 1;
    }
    final (r, gg, b) = g.apply(0.5, 0.5, 0.5);
    expect(r, 0.5);
    expect(gg, 0.5);
    expect(b, 0.5);
  });

  test('dropping the blue band leaves a red pixel alone', () {
    final g = HslGrade()..saturation[band('Blue')] = -1;
    // Pure red sits at 0°, two bands away from blue.
    final (r, gg, b) = g.apply(0.9, 0.1, 0.1);
    expect(r, closeTo(0.9, 1e-6));
    expect(gg, closeTo(0.1, 1e-6));
    expect(b, closeTo(0.1, 1e-6));
  });

  test('dropping the blue band drains a blue pixel', () {
    final g = HslGrade()..saturation[band('Blue')] = -1;
    // 240° is the blue centre.
    final (r, gg, b) = g.apply(0.1, 0.1, 0.9);
    // Saturation gone means the three channels have met.
    expect((r - gg).abs(), lessThan(1e-6));
    expect((gg - b).abs(), lessThan(1e-6));
  });

  test('lifting a band raises only that colour', () {
    final g = HslGrade()..luminance[band('Green')] = 1;
    final green = g.apply(0.2, 0.7, 0.2);
    final red = g.apply(0.7, 0.2, 0.2);
    expect(green.$2, greaterThan(0.7), reason: 'green was not lifted');
    expect(red.$1, closeTo(0.7, 1e-6), reason: 'red moved with green');
  });

  test('a hue shift moves the band and stays on the wheel', () {
    final g = HslGrade()..hue[band('Red')] = 1;
    final (r, gg, b) = g.apply(0.9, 0.1, 0.1);
    for (final v in [r, gg, b]) {
      expect(v, inInclusiveRange(0.0, 1.0));
    }
    // Turning red the positive way sends it towards orange: green rises.
    expect(gg, greaterThan(0.1));
  });

  test('json survives a round trip', () {
    final g = HslGrade()
      ..hue[2] = 0.4
      ..saturation[5] = -0.6
      ..luminance[7] = 0.25;
    final back = HslGrade.fromJson(g.toJson());
    expect(back.hue[2], 0.4);
    expect(back.saturation[5], -0.6);
    expect(back.luminance[7], 0.25);
    expect(back.isNeutral, isFalse);
  });
}
