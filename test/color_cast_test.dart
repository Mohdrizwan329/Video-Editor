import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/data/models/adjustments.dart';

/// The cast is scaled channels, and the shader and the exporter have to be
/// given the same three numbers — otherwise the preview shows one tint and
/// the file carries another.
void main() {
  test('no cast leaves the channels alone', () {
    final a = Adjustments();
    expect(a.colorCastFactors, (1.0, 1.0, 1.0));
    expect(
      a.toFFmpegExtras().where((f) => f.startsWith('colorchannelmixer')),
      isEmpty,
    );
  });

  test('a cast at zero strength is still no cast', () {
    final a = Adjustments()..colorCastHue = 0.6;
    expect(a.colorCastFactors, (1.0, 1.0, 1.0));
    expect(a.isNeutral, isTrue);
  });

  test('red pulls the red channel up and the others down', () {
    final a = Adjustments()
      ..colorCastHue = 0
      ..colorCastAmount = 1;
    final (r, g, b) = a.colorCastFactors;
    expect(r, closeTo(1.0, 1e-6));
    expect(g, closeTo(0.0, 1e-6));
    expect(b, closeTo(0.0, 1e-6));
  });

  test('half strength lands halfway to the colour', () {
    final a = Adjustments()
      ..colorCastHue = 0
      ..colorCastAmount = 0.5;
    final (r, g, b) = a.colorCastFactors;
    expect(r, closeTo(1.0, 1e-6));
    expect(g, closeTo(0.5, 1e-6));
    expect(b, closeTo(0.5, 1e-6));
  });

  test('the exporter is handed the same factors the shader gets', () {
    final a = Adjustments()
      ..colorCastHue = 0.55
      ..colorCastAmount = 0.4;
    final (r, g, b) = a.colorCastFactors;
    final filter = a.toFFmpegExtras().firstWhere(
      (f) => f.startsWith('colorchannelmixer'),
    );
    expect(filter, contains('rr=${r.toStringAsFixed(4)}'));
    expect(filter, contains('gg=${g.toStringAsFixed(4)}'));
    expect(filter, contains('bb=${b.toStringAsFixed(4)}'));
  });

  test('a cast counts as something for the shader to do', () {
    final a = Adjustments()
      ..colorCastHue = 0.2
      ..colorCastAmount = 0.3;
    expect(a.hasShaderExtras, isTrue);
    expect(a.isNeutral, isFalse);
  });

  test('reset clears it and json carries it', () {
    final a = Adjustments()
      ..colorCastHue = 0.75
      ..colorCastAmount = 0.6;
    final back = Adjustments.fromJson(a.toJson());
    expect(back.colorCastHue, 0.75);
    expect(back.colorCastAmount, 0.6);
    a.reset();
    expect(a.colorCastAmount, 0);
    expect(a.isNeutral, isTrue);
  });

  test('every factor stays a sane multiplier', () {
    for (var h = 0; h < 12; h++) {
      for (final amount in [0.25, 0.5, 1.0]) {
        final a = Adjustments()
          ..colorCastHue = h / 12
          ..colorCastAmount = amount;
        final (r, g, b) = a.colorCastFactors;
        for (final v in [r, g, b]) {
          expect(v, inInclusiveRange(0.0, 1.0));
        }
      }
    }
  });
}
