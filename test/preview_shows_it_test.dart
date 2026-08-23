import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/video_clip.dart';

/// The other half of the same question.
///
/// A tool that reaches the render and not the preview is a slider that moves
/// and changes nothing until the file comes out — which from the outside is
/// a tool that does not work. Ease and the clip's animation were both in
/// that state: drawn by the exporter, invisible on screen.
void main() {
  VideoClip clip() => VideoClip(
    path: '/nonexistent/c.mp4',
    isImage: false,
    sourceDuration: const Duration(seconds: 4),
  )..trimEnd = const Duration(seconds: 4);

  test('an untouched clip is solid the whole way through', () {
    final c = clip();
    for (final t in [0, 1, 2, 4]) {
      expect(c.opacityAt(Duration(seconds: t)), 1.0);
    }
  });

  test('opacity holds across the clip', () {
    final c = clip()..opacity = 0.4;
    expect(c.opacityAt(Duration.zero), closeTo(0.4, 1e-9));
    expect(c.opacityAt(const Duration(seconds: 2)), closeTo(0.4, 1e-9));
  });

  test('ease in climbs from nothing to whole', () {
    final c = clip()..fadeIn = const Duration(seconds: 1);
    expect(c.opacityAt(Duration.zero), 0.0);
    expect(c.opacityAt(const Duration(milliseconds: 500)), closeTo(0.5, 1e-9));
    expect(c.opacityAt(const Duration(seconds: 1)), 1.0);
    expect(c.opacityAt(const Duration(seconds: 3)), 1.0);
  });

  test('ease out falls away at the end', () {
    final c = clip()..fadeOut = const Duration(seconds: 1);
    expect(c.opacityAt(Duration.zero), 1.0);
    expect(c.opacityAt(const Duration(seconds: 3)), 1.0);
    expect(c.opacityAt(const Duration(milliseconds: 3500)), closeTo(0.5, 1e-9));
    expect(c.opacityAt(const Duration(seconds: 4)), 0.0);
  });

  test('the alpha animation shows on screen too', () {
    final c = clip()
      ..animationIn = LayerAnimation.fade
      ..animationDuration = const Duration(milliseconds: 600);
    expect(c.opacityAt(Duration.zero), 0.0);
    expect(c.opacityAt(const Duration(milliseconds: 300)), closeTo(0.5, 1e-9));
    expect(c.opacityAt(const Duration(seconds: 1)), 1.0);
  });

  test('an animation the renderer cannot draw does not fake one on screen', () {
    // Only the alpha family is rendered. A slide showing as a fade in the
    // preview would promise a move the file never makes.
    final c = clip()..animationIn = LayerAnimation.slideUp;
    expect(c.opacityAt(Duration.zero), 1.0);
  });

  test('ease and animation and opacity compound, as the render does', () {
    final c = clip()
      ..opacity = 0.5
      ..fadeIn = const Duration(seconds: 1);
    expect(
      c.opacityAt(const Duration(milliseconds: 500)),
      closeTo(0.25, 1e-9),
      reason: 'half a clip at half strength should be a quarter',
    );
  });

  test('it stays inside zero and one wherever it is asked', () {
    final c = clip()
      ..opacity = 0.9
      ..fadeIn = const Duration(seconds: 2)
      ..fadeOut = const Duration(seconds: 2)
      ..animationIn = LayerAnimation.fade
      ..animationOut = LayerAnimation.dissolve;
    for (var ms = -500; ms <= 5000; ms += 250) {
      final v = c.opacityAt(Duration(milliseconds: ms));
      expect(v, inInclusiveRange(0.0, 1.0), reason: 'at ${ms}ms it was $v');
    }
  });

  test('a clip with no length is answered rather than divided by zero', () {
    final c = VideoClip(
      path: '/nonexistent/c.mp4',
      isImage: false,
      sourceDuration: Duration.zero,
    )..fadeIn = const Duration(seconds: 1);
    expect(c.opacityAt(Duration.zero), inInclusiveRange(0.0, 1.0));
  });
}
