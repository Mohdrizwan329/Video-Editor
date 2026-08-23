import 'dart:typed_data';
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
    final image = await recorder.endRecording().toImage(
      size.width.round(),
      size.height.round(),
    );
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

/// The raw pixels [paint] produced, for comparing one frame against another.
Future<Uint8List> _pixels(
  WidgetTester tester,
  Size size,
  void Function(Canvas, Size) paint,
) async {
  final bytes = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder), size);
    final image = await recorder.endRecording().toImage(
      size.width.round(),
      size.height.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data?.buffer.asUint8List() ?? Uint8List(0);
  });
  return bytes!;
}

void main() {
  // A preview canvas and a 1080p export frame — the two sizes the same preset
  // has to look right at.
  const preview = Size(304, 540);
  const export = Size(810, 1440);

  group('design frames', () {
    for (final preset in FrameLibrary.all) {
      testWidgets('${preset.name} paints at preview and export size', (
        tester,
      ) async {
        for (final size in [preview, export]) {
          final covered = await _coveredPixels(
            tester,
            size,
            (c, s) => EffectPainter.paintFrame(c, s, preset),
          );
          if (preset.isNone) {
            expect(covered, 0, reason: 'None must paint nothing');
          } else {
            expect(
              covered,
              greaterThan(0),
              reason: '${preset.id} painted nothing at $size',
            );
            // A border wraps the picture; it must never fill it.
            expect(
              covered,
              lessThan(size.width * size.height * 0.9),
              reason: '${preset.id} covered the whole canvas at $size',
            );
          }
        }
      });
    }
  });

  group('fx textures', () {
    for (final preset in FxLibrary.all) {
      testWidgets('${preset.name} paints at preview and export size', (
        tester,
      ) async {
        for (final size in [preview, export]) {
          final covered = await _coveredPixels(
            tester,
            size,
            (c, s) => EffectPainter.paintFx(c, s, preset, 1),
          );
          if (preset.isNone) {
            expect(covered, 0, reason: 'None must paint nothing');
          } else {
            expect(
              covered,
              greaterThan(0),
              reason: '${preset.id} painted nothing at $size',
            );
          }
        }
      });
    }

    testWidgets('intensity 0 paints nothing at all', (tester) async {
      for (final preset in FxLibrary.all) {
        expect(
          await _coveredPixels(
            tester,
            preview,
            (c, s) => EffectPainter.paintFx(c, s, preset, 0),
          ),
          0,
          reason: '${preset.id} still painted at zero intensity',
        );
      }
    });

    testWidgets('grain keeps its density as the canvas grows', (tester) async {
      const grain = FxPreset(
        id: 'g',
        name: 'g',
        category: 'Grit',
        pattern: FxPattern.grain,
      );
      final small = await _coveredPixels(
        tester,
        preview,
        (c, s) => EffectPainter.paintFx(c, s, grain, 1),
      );
      final large = await _coveredPixels(
        tester,
        export,
        (c, s) => EffectPainter.paintFx(c, s, grain, 1),
      );
      final smallShare = small / (preview.width * preview.height);
      final largeShare = large / (export.width * export.height);
      // Same look at both sizes, not a fine dusting on one and mush on the
      // other. Anti-aliasing moves the number a little; the shares stay close.
      expect(
        (smallShare - largeShare).abs(),
        lessThan(0.12),
        reason:
            'grain covered $smallShare of the preview but '
            '$largeShare of the export frame',
      );
    });
  });

  group('effects that move', () {
    // Every one of these is a *loop*: the renderer bakes frames 0..n-1 once
    // and plays them over and over, and the preview asks the preset which of
    // those frames the playhead is on. The two only line up while the frame
    // maths below holds.
    test('the loop wraps and never leaves its range', () {
      for (final preset in FxLibrary.all.where((f) => f.isAnimated)) {
        final n = preset.frameCount;
        expect(
          n,
          greaterThanOrEqualTo(2),
          reason: '${preset.id} claims to move but has one frame',
        );

        // Sampled mid-frame. On the boundary itself a microsecond of
        // rounding either way decides which frame you are on, which is a
        // question about float maths rather than about the loop.
        for (var i = 0; i < n * 3; i++) {
          final t = Duration(
            microseconds:
                ((i + 0.5) * Duration.microsecondsPerSecond / preset.frameRate)
                    .round(),
          );
          expect(
            preset.frameAt(t),
            i % n,
            reason: '${preset.id} lost its place at frame $i',
          );
        }
      }
    });

    test('a still effect sits on frame zero whatever the playhead says', () {
      for (final preset in FxLibrary.all.where((f) => !f.isAnimated)) {
        expect(
          preset.frameAt(const Duration(seconds: 7)),
          0,
          reason: '${preset.id} moved, and nothing was baked for it',
        );
      }
    });

    testWidgets('every moving effect actually redraws between frames', (
      tester,
    ) async {
      // The whole point of the loop. A preset with a period but a painter
      // that ignores the frame index would export as a still and nobody
      // would find out until they watched the file.
      for (final preset in FxLibrary.all.where((f) => f.isAnimated)) {
        final first = await _pixels(
          tester,
          preview,
          (c, s) => EffectPainter.paintFx(c, s, preset, 1, frame: 0),
        );

        // Against every other frame, not just the halfway one: an effect
        // that breathes on a sine passes back through its opening state at
        // the half mark, and comparing only those two would call it still.
        var moved = false;
        for (var f = 1; f < preset.frameCount && !moved; f++) {
          final other = await _pixels(
            tester,
            preview,
            (c, s) => EffectPainter.paintFx(c, s, preset, 1, frame: f),
          );
          for (var i = 0; i < first.length; i++) {
            if (first[i] != other[i]) {
              moved = true;
              break;
            }
          }
        }
        expect(
          moved,
          isTrue,
          reason:
              '${preset.id} paints the same picture on every frame of '
              'its loop, so it would export as a still',
        );
      }
    });

    testWidgets('and paints something on every frame of the loop', (
      tester,
    ) async {
      // A frame that lands empty is a hole in the effect. The Basic pack is
      // the exception and the reason it is its own pack: Strobe and Flash
      // are *meant* to go dark, that being what a flash is.
      for (final preset in FxLibrary.all.where(
        (f) => f.isAnimated && f.category != 'Basic',
      )) {
        for (var i = 0; i < preset.frameCount; i++) {
          final covered = await _coveredPixels(
            tester,
            preview,
            (c, s) => EffectPainter.paintFx(c, s, preset, 1, frame: i),
          );
          expect(
            covered,
            greaterThan(0),
            reason: '${preset.id} painted nothing on frame $i',
          );
        }
      }
    });

    test('the exporter is never asked for an unreasonable strip of PNGs', () {
      for (final preset in FxLibrary.all) {
        expect(
          preset.frameCount,
          lessThanOrEqualTo(48),
          reason:
              '${preset.id} would bake ${preset.frameCount} full-size '
              'frames at export time',
        );
      }
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
