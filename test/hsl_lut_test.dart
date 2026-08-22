import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/data/models/hsl_grade.dart';
import 'package:video_editor/data/services/hsl_lut.dart';

/// The LUT is the exporter's only route to a per-hue grade, so what matters
/// is that it is a well-formed cube and that it carries the same answer the
/// preview shows.
void main() {
  const n = HslLut.size;

  List<String> rows(String cube) => cube
      .split('\n')
      .where((l) => l.isNotEmpty && !l.startsWith('#') && l.contains('.'))
      .where((l) => !l.startsWith('DOMAIN'))
      .toList();

  test('the cube has a point for every grid position', () {
    final body = rows(HslLut.cube(HslGrade()));
    expect(body.length, n * n * n);
  });

  test('an untouched grade bakes the identity', () {
    final body = rows(HslLut.cube(HslGrade()));
    // First point is black, last is white, and red runs fastest.
    expect(body.first.split(' ').map(double.parse), everyElement(0.0));
    expect(body.last.split(' ').map(double.parse), everyElement(1.0));
    // The second point moves red only.
    final second = body[1].split(' ').map(double.parse).toList();
    expect(second[0], greaterThan(0));
    expect(second[1], 0);
    expect(second[2], 0);
  });

  test('red runs fastest and blue slowest', () {
    final body = rows(HslLut.cube(HslGrade()));
    // One full red sweep in, green should have stepped once.
    final afterRedSweep = body[n].split(' ').map(double.parse).toList();
    expect(afterRedSweep[0], 0);
    expect(afterRedSweep[1], greaterThan(0));
    expect(afterRedSweep[2], 0);
    // One full red-green plane in, blue should have stepped once.
    final afterPlane = body[n * n].split(' ').map(double.parse).toList();
    expect(afterPlane[2], greaterThan(0));
  });

  test('the baked point matches what the grade itself returns', () {
    final grade = HslGrade()
      ..saturation[HslGrade.bandNames.indexOf('Blue')] = -1
      ..luminance[HslGrade.bandNames.indexOf('Green')] = 0.5;
    final body = rows(HslLut.cube(grade));

    // A point well inside the cube, addressed the way the format orders them.
    const ri = 8, gi = 20, bi = 26;
    final baked = body[ri + gi * n + bi * n * n]
        .split(' ')
        .map(double.parse)
        .toList();
    final direct = grade.apply(ri / (n - 1), gi / (n - 1), bi / (n - 1));
    expect(baked[0], closeTo(direct.$1, 1e-6));
    expect(baked[1], closeTo(direct.$2, 1e-6));
    expect(baked[2], closeTo(direct.$3, 1e-6));
  });

  test('every baked value stays inside the cube', () {
    final grade = HslGrade();
    for (var i = 0; i < HslGrade.bandCount; i++) {
      grade.hue[i] = 1;
      grade.saturation[i] = 1;
      grade.luminance[i] = 1;
    }
    for (final line in rows(HslLut.cube(grade))) {
      for (final v in line.split(' ').map(double.parse)) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
    }
  });

  test('the header says what FFmpeg needs to read it', () {
    final cube = HslLut.cube(HslGrade());
    expect(cube, contains('LUT_3D_SIZE $n'));
  });
}
