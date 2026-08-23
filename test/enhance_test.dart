import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/data/services/export_service.dart';
import 'package:video_editor/data/services/export_settings.dart';

/// Enhance is one clean-up shown twice: painted by the preview and rendered
/// by the exporter. The danger in sharing it is the tone landing in both the
/// grade and its own filter, which would apply it twice in the file and once
/// on screen — a preview that quietly lies about the result.
void main() {
  VideoClip clip() => VideoClip(
    path: '/nonexistent/c.mp4',
    isImage: false,
    sourceDuration: const Duration(seconds: 3),
  );

  String commandFor(VideoClip c) => ExportService.debugCommandFor(
    Project(name: 'p', ratio: CanvasRatio.r9x16, clips: [c]),
    ExportSettings(),
  );

  test('off, it changes nothing', () {
    final c = clip();
    expect(c.shownAdjustments.sharpen, 0);
    expect(c.gradedFilter.contrast, 1);
    expect(c.enhanceFilters(), isEmpty);
  });

  test('on, the preview is given the sharpening and the denoise', () {
    final c = clip()..enhance = true;
    expect(c.shownAdjustments.sharpen, VideoClip.enhanceSharpen);
    expect(c.shownAdjustments.denoise, VideoClip.enhanceDenoise);
  });

  test('on, the grade carries the tonal lift', () {
    final c = clip()..enhance = true;
    expect(
      c.gradedFilter.contrast,
      closeTo(1 + VideoClip.enhanceContrast, 1e-9),
    );
    expect(
      c.gradedFilter.saturation,
      closeTo(1 + VideoClip.enhanceSaturation, 1e-9),
    );
    expect(c.gradedFilter.gamma, closeTo(VideoClip.enhanceGamma, 1e-9));
  });

  test('the tone is applied once, not once in each half', () {
    final c = clip()..enhance = true;
    // The grade is where the tone lives, so the enhance filters must not
    // carry an `eq` of their own.
    expect(
      c.enhanceFilters().where((f) => f.startsWith('eq=')),
      isEmpty,
      reason: 'the tonal lift is emitted twice, so the file gets it twice',
    );
    final command = commandFor(c);
    expect('eq='.allMatches(command).length, 1);
  });

  test('the render still gets what a matrix cannot say', () {
    final c = clip()..enhance = true;
    final command = commandFor(c);
    expect(command, contains('hqdn3d'));
    expect(command, contains('unsharp'));
  });

  test('it adds to what the user set rather than replacing it', () {
    final c = clip()..enhance = true;
    c.adjustments.sharpen = 0.3;
    expect(c.shownAdjustments.sharpen, closeTo(0.9, 1e-9));
    // And never past the end of the slider.
    c.adjustments.sharpen = 0.8;
    expect(c.shownAdjustments.sharpen, 1.0);
  });

  test('it does not touch the clip the user is actually editing', () {
    final c = clip()..enhance = true;
    c.shownAdjustments.sharpen = 1;
    expect(
      c.adjustments.sharpen,
      0,
      reason: 'the preview copy is writing back into the project',
    );
  });

  test('the preview has something to paint with it on', () {
    final c = clip()..enhance = true;
    expect(c.shownAdjustments.hasShaderExtras, isTrue);
  });
}
