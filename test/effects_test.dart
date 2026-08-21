import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_effect.dart';
import 'package:video_editor/data/services/effect_painter.dart';

/// Paints [paint] into [size] and reports how many pixels it actually covered.
///
/// Rasterising goes through [WidgetTester.runAsync]: `Picture.toImage` needs
/// the real event loop, and never completes inside the test zone's fake one.
Future<int> _coveredPixels(
  WidgetTester tester,
  Size size,
  void Function(Canvas, Size) paint,
) async {
  final covered = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder), size);
    final image = await recorder
        .endRecording()
        .toImage(size.width.round(), size.height.round());
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return 0;
    final px = data.buffer.asUint8List();
    var count = 0;
    for (var i = 3; i < px.length; i += 4) {
      if (px[i] != 0) count++;
    }
    return count;
  });
  return covered!;
}

void main() {
  // A preview canvas and a 1080p export frame — the two sizes the same preset
  // has to look right at.
  const preview = Size(304, 540);
  const export = Size(810, 1440);

  group('design frames', () {
    for (final preset in FrameLibrary.all) {
      testWidgets('${preset.name} paints at preview and export size',
          (tester) async {
        for (final size in [preview, export]) {
          final covered = await _coveredPixels(
              tester, size, (c, s) => EffectPainter.paintFrame(c, s, preset));
          if (preset.isNone) {
            expect(covered, 0, reason: 'None must paint nothing');
          } else {
            expect(covered, greaterThan(0),
                reason: '${preset.id} painted nothing at $size');
            // A border wraps the picture; it must never fill it.
            expect(covered, lessThan(size.width * size.height * 0.9),
                reason: '${preset.id} covered the whole canvas at $size');
          }
        }
      });
    }
  });

  group('fx textures', () {
    for (final preset in FxLibrary.all) {
      testWidgets('${preset.name} paints at preview and export size',
          (tester) async {
        for (final size in [preview, export]) {
          final covered = await _coveredPixels(
              tester, size, (c, s) => EffectPainter.paintFx(c, s, preset, 1));
          if (preset.isNone) {
            expect(covered, 0, reason: 'None must paint nothing');
          } else {
            expect(covered, greaterThan(0),
                reason: '${preset.id} painted nothing at $size');
          }
        }
      });
    }

    testWidgets('intensity 0 paints nothing at all', (tester) async {
      for (final preset in FxLibrary.all) {
        expect(
          await _coveredPixels(
              tester, preview, (c, s) => EffectPainter.paintFx(c, s, preset, 0)),
          0,
          reason: '${preset.id} still painted at zero intensity',
        );
      }
    });

    testWidgets('grain keeps its density as the canvas grows', (tester) async {
      const grain = FxPreset(
          id: 'g', name: 'g', category: 'Grit', pattern: FxPattern.grain);
      final small = await _coveredPixels(
          tester, preview, (c, s) => EffectPainter.paintFx(c, s, grain, 1));
      final large = await _coveredPixels(
          tester, export, (c, s) => EffectPainter.paintFx(c, s, grain, 1));
      final smallShare = small / (preview.width * preview.height);
      final largeShare = large / (export.width * export.height);
      // Same look at both sizes, not a fine dusting on one and mush on the
      // other. Anti-aliasing moves the number a little; the shares stay close.
      expect((smallShare - largeShare).abs(), lessThan(0.12),
          reason: 'grain covered $smallShare of the preview but '
              '$largeShare of the export frame');
    });
  });

  group('project', () {
    test('carries the frame and fx through a save and load', () {
      final project = Project(name: 'Effects')
        ..frameId = 'filmstrip'
        ..fxId = 'vhs'
        ..fxIntensity = 0.4;

      final restored = Project.fromJson(project.toJson());

      expect(restored.frameId, 'filmstrip');
      expect(restored.fxId, 'vhs');
      expect(restored.fxIntensity, 0.4);
      expect(restored.frame.style, FrameStyle.filmStrip);
      expect(restored.fx.pattern, FxPattern.vhs);
      expect(restored.hasFrame, isTrue);
      expect(restored.hasFx, isTrue);
    });

    test('a project with no effects reports none', () {
      final project = Project(name: 'Plain');
      expect(project.hasFrame, isFalse);
      expect(project.hasFx, isFalse);
      expect(Project.fromJson(project.toJson()).frameId, 'none');
    });

    test('an unknown id falls back to none rather than throwing', () {
      expect(FrameLibrary.fromId('gone').isNone, isTrue);
      expect(FxLibrary.fromId('gone').isNone, isTrue);
      expect(FrameLibrary.fromId(null).isNone, isTrue);
    });
  });
}
