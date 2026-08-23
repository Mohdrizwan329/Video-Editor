import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/data/models/adjustments.dart';
import 'package:video_editor/ui/editor/panels/curve_editor.dart';

/// The editor is only honest if a point lands where the finger left it, and
/// if what it draws is what the renderer will apply. Both come down to the
/// mapping between the model's three values and the curve's three heights.
void main() {
  test('a point dragged to a height reports the value that puts it there', () {
    for (var i = 0; i < 3; i++) {
      for (final y in [0.0, 0.2, 0.35, 0.5, 0.65, 0.8, 1.0]) {
        final v = CurveEditor.valueFor(i, y);
        final back = CurveEditor.outputFor(i, v);
        // Inside the point's own range the round trip is exact; outside it
        // the clamp is doing its job and the point stops at the edge.
        final (lo, span) = CurveEditor.ranges[i];
        if (y >= lo && y <= lo + span) {
          expect(
            back,
            closeTo(y, 1e-9),
            reason: 'point $i dragged to $y settled at $back',
          );
        } else {
          expect(back, inInclusiveRange(lo, lo + span));
        }
      }
    }
  });

  test('the model value never leaves the slider range', () {
    for (var i = 0; i < 3; i++) {
      for (var k = 0; k <= 20; k++) {
        final v = CurveEditor.valueFor(i, k / 20);
        expect(v, inInclusiveRange(-1.0, 1.0));
      }
    }
  });

  test('an untouched curve draws the straight diagonal', () {
    expect(CurveEditor.outputFor(0, 0), 0.0);
    expect(CurveEditor.outputFor(1, 0), 0.5);
    expect(CurveEditor.outputFor(2, 0), 1.0);
  });

  test('what the editor draws is what the renderer is given', () {
    final adj = Adjustments()
      ..curveLow = 0.8
      ..curveMid = -0.4
      ..curveHigh = -0.6;
    final (lo, mid, hi) = adj.curvePoints;
    expect(CurveEditor.outputFor(0, adj.curveLow), closeTo(lo, 1e-9));
    expect(CurveEditor.outputFor(1, adj.curveMid), closeTo(mid, 1e-9));
    expect(CurveEditor.outputFor(2, adj.curveHigh), closeTo(hi, 1e-9));
  });

  test('the blacks point lifts but does not crush', () {
    // The renderer clamps it that way, so the editor has to stop there too.
    expect(CurveEditor.outputFor(0, -1), 0.0);
    expect(CurveEditor.outputFor(0, 1), closeTo(0.25, 1e-9));
  });

  test('the highlights point pulls down but does not push past white', () {
    expect(CurveEditor.outputFor(2, 1), 1.0);
    expect(CurveEditor.outputFor(2, -1), closeTo(0.75, 1e-9));
  });
}
