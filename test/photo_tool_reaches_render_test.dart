import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/photo_edit.dart';
import 'package:video_editor/data/services/photo_renderer.dart';

/// Every tool on the photo editor's bar has to change the picture.
///
/// A panel whose slider moves and whose renderer never reads the value is
/// the failure this catches: it renders the same photo twice, once
/// untouched and once with one tool turned on, and compares the pixels. A
/// tool that reaches nothing comes out identical.
void main() {
  late ui.Image photo;
  late ui.Image matte;

  setUpAll(() async {
    // Wider than it is tall, so a canvas shape has a margin to fill: a
    // square photo in a square box leaves the Canvas tool nothing to do.
    photo = await _swatch(64, 32, (x, y) {
      // Something with structure in it, so a blur or a sharpen has
      // somewhere to show.
      final on = ((x ~/ 8) + (y ~/ 8)).isEven;
      return on ? const Color(0xFFE08040) : const Color(0xFF204060);
    });
    // A matte with the middle bright, the way the cutout pass leaves one.
    matte = await _swatch(64, 64, (x, y) {
      final inside = x > 16 && x < 48 && y > 16 && y < 48;
      return inside ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    });
  });

  /// Renders [e] and returns its pixels.
  Future<ByteData> render(PhotoEdit e) async {
    const size = Size(64, 64);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    PhotoRenderer.paintPicture(canvas, size, photo, e, cutoutMatte: matte);
    PhotoRenderer.paintDecorations(canvas, size, e);
    PhotoRenderer.paintOverlays(canvas, size, e);
    final picture = recorder.endRecording();
    final image = await picture.toImage(64, 64);
    picture.dispose();
    final data = (await image.toByteData())!;
    image.dispose();
    return data;
  }

  /// How many of the two renders' bytes differ.
  int differences(ByteData a, ByteData b) {
    var n = 0;
    for (var i = 0; i < a.lengthInBytes; i++) {
      if (a.getUint8(i) != b.getUint8(i)) n++;
    }
    return n;
  }

  /// Each tool, and the smallest thing turning it on means.
  final tools = <String, void Function(PhotoEdit)>{
    'Canvas': (e) {
      e.canvasAspect = 1;
      e.canvasBackground = 0xFF00FF00;
    },
    'Canvas backdrop': (e) {
      e.canvasAspect = 2;
      e.canvasBlurBackdrop = true;
    },
    'Filter': (e) => e.filterId = 'noir',
    'Adjust': (e) => e.adjustments.brightness = 0.4,
    'Effect grain': (e) => e.effectId = 'grain',
    'Effect leak': (e) => e.effectId = 'leak',
    'Effect glow': (e) => e.effectId = 'glow',
    'Effect vignette': (e) => e.effectId = 'vignette',
    'Effect dust': (e) => e.effectId = 'dust',
    'Effect fringe': (e) => e.effectId = 'chroma',
    'Enhance': (e) => e.enhance = true,
    'Cutout': (e) {
      e.cutoutMattePath = 'memory';
      e.cutoutOn = true;
    },
    'Mask': (e) => e.maskShape = MaskShape.circle,
    'Mask invert': (e) {
      e.maskShape = MaskShape.star;
      e.maskInverted = true;
    },
    'Crop': (e) => e.setCrop(0.2, 0.1, 0.1, 0.2),
    'Rotate': (e) => e.quarterTurns = 1,
    'Flip': (e) => e.flipH = true,
    'Detail grain': (e) => e.adjustments.grain = 0.8,
    'Doodle': (e) => e.markup.add(
      PhotoStroke(width: 0.2)
        ..points.addAll(const [Offset(0.1, 0.5), Offset(0.9, 0.5)]),
    ),
    'Pixelate': (e) => e.pixelate.add(
      PhotoStroke(width: 0.4)
        ..points.addAll(const [Offset(0.3, 0.3), Offset(0.7, 0.7)]),
    ),
    'Remove': (e) => e.retouch.add(
      PhotoStroke(width: 0.4)
        ..points.addAll(const [Offset(0.3, 0.3), Offset(0.7, 0.7)]),
    ),
  };

  for (final entry in tools.entries) {
    test('${entry.key} changes the picture', () async {
      final untouched = await render(PhotoEdit());
      final edited = PhotoEdit();
      entry.value(edited);
      final after = await render(edited);

      expect(
        differences(untouched, after),
        greaterThan(0),
        reason:
            '${entry.key} rendered exactly the same photo, so whatever '
            'its panel writes the renderer never reads',
      );
    });
  }

  test('an untouched edit renders the photo as it is', () async {
    final a = await render(PhotoEdit());
    final b = await render(PhotoEdit());
    expect(differences(a, b), 0, reason: 'the render is not repeatable');
  });

  test('the canvas shape is the shape that comes out', () {
    final e = PhotoEdit()..canvasAspect = 1;
    final size = PhotoRenderer.outputSize(photo, e);
    expect(size.width / size.height, closeTo(1, 0.001));

    e.canvasAspect = 16 / 9;
    final wide = PhotoRenderer.outputSize(photo, e);
    expect(wide.width / wide.height, closeTo(16 / 9, 0.001));
  });
}

/// A test picture built from a function of its coordinates.
Future<ui.Image> _swatch(int w, int h, Color Function(int, int) at) async {
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = at(x, y);
      final o = (y * w + x) * 4;
      rgba[o] = (c.r * 255).round();
      rgba[o + 1] = (c.g * 255).round();
      rgba[o + 2] = (c.b * 255).round();
      rgba[o + 3] = 255;
    }
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: w,
    height: h,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  codec.dispose();
  descriptor.dispose();
  return frame.image;
}
