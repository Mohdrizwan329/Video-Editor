import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';

/// Finds the subject in a still and hands back a matte of it.
///
/// The video editor's Cutout runs the same segmenter frame by frame and
/// merges the result with `alphamerge`. A photo needs one frame and no
/// FFmpeg at all, so this returns the matte as an image the renderer can
/// draw with rather than a file — but the matte itself is the same thing:
/// white where the subject is, black where it is not.
class PhotoCutout {
  PhotoCutout._();

  /// The longest side the model is given. The mask is a soft-edged shape
  /// rather than detail, so a bigger frame is decode cost with no more mask
  /// in it — and the renderer scales it back up.
  static const int _side = 512;

  /// Below this share of the frame there is no subject, only noise: merging
  /// that matte would leave the user with an empty picture.
  static const double _minCoverage = 0.02;

  /// The matte for [image], or null when the model found nobody.
  static Future<ui.Image?> matteFor(ui.Image image) async {
    SelfieSegmenter? segmenter;
    try {
      final input = await _inputFrom(image);
      if (input == null) return null;
      segmenter = SelfieSegmenter(mode: SegmenterMode.single);
      final mask = await segmenter.processImage(input);
      if (mask == null) return null;

      final w = mask.width, h = mask.height;
      final conf = mask.confidences;
      if (w <= 0 || h <= 0 || conf.length < w * h) return null;

      final rgba = Uint8List(w * h * 4);
      var solid = 0;
      for (var i = 0; i < w * h; i++) {
        final c = conf[i].clamp(0.0, 1.0);
        if (c > 0.5) solid++;
        final v = (c * 255).round();
        final o = i * 4;
        rgba[o] = rgba[o + 1] = rgba[o + 2] = v;
        rgba[o + 3] = 255;
      }
      // A matte that is black nearly everywhere is not a cutout — it is a
      // photo the model found nobody in.
      if (solid / (w * h) < _minCoverage) return null;
      return _imageFromPixels(rgba, w, h);
    } catch (e) {
      debugPrint('photo cutout threw: $e');
      return null;
    } finally {
      await segmenter?.close();
    }
  }

  /// The photo as the bytes the model wants: NV21-free, plain RGBA at a size
  /// it can chew through.
  static Future<InputImage?> _inputFrom(ui.Image image) async {
    final scale = _side / image.width.clamp(1, 1 << 24);
    final k = scale < 1 ? scale : 1.0;
    final w = (image.width * k).round().clamp(1, _side * 4);
    final h = (image.height * k).round().clamp(1, _side * 4);

    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final small = await picture.toImage(w, h);
    picture.dispose();
    try {
      final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return InputImage.fromBytes(
        bytes: data.buffer.asUint8List(),
        metadata: InputImageMetadata(
          size: ui.Size(w.toDouble(), h.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: w * 4,
        ),
      );
    } finally {
      small.dispose();
    }
  }

  static Future<ui.Image> _imageFromPixels(Uint8List rgba, int w, int h) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }
}
