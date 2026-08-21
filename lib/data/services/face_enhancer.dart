import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Finds the skin in a photograph and hands back a soft mask of it.
///
/// There is no face-detection model on the device, so this does the next best
/// thing and one that costs nothing to ship: it classifies every pixel by
/// chrominance — the YCbCr window skin occupies is narrow and holds across
/// complexions, because it describes hue rather than lightness — then blurs
/// the result so the retouch it gates fades in and out instead of stamping a
/// hard edge across a cheek.
///
/// The mask is computed on a thumbnail. That is deliberate: the smoothing it
/// gates is itself a blur, so mask detail beyond a couple of hundred pixels
/// would never be visible, and a 50MP photo classified pixel by pixel would
/// stall the editor for seconds.
class FaceEnhancer {
  const FaceEnhancer._();

  /// Below this share of the frame there is no face worth retouching — a
  /// landscape with a sandstone wall in it should not quietly get soft.
  static const double _minSkinShare = 0.012;

  /// A white image whose alpha is the skin likelihood, in the *source*
  /// photo's own coordinates, or null when the picture holds no skin.
  ///
  /// The renderer draws it through the same crop, turn and mirror as the
  /// photo, so it stays registered to the face however the picture is framed.
  static Future<ui.Image?> skinMask(ui.Image source, {int side = 256}) async {
    if (source.width <= 0 || source.height <= 0) return null;
    try {
      final scale = side / math.max(source.width, source.height);
      final w = math.max(8, (source.width * scale).round());
      final h = math.max(8, (source.height * scale).round());

      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        source,
        ui.Rect.fromLTWH(
          0,
          0,
          source.width.toDouble(),
          source.height.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      final small = await picture.toImage(w, h);
      picture.dispose();

      final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
      small.dispose();
      if (data == null) return null;

      final mask = _classify(data.buffer.asUint8List(), w, h);
      if (mask == null) return null;
      return _toImage(mask, w, h);
    } catch (e) {
      debugPrint('skin mask failed: $e');
      return null;
    }
  }

  /// Marks the skin pixels, then blurs and lifts the result into a soft mask.
  /// Returns null when too little of the frame is skin to be a face.
  static Uint8List? _classify(Uint8List rgba, int w, int h) {
    final raw = Uint8List(w * h);
    var hits = 0;
    for (var i = 0, p = 0; p < raw.length; i += 4, p++) {
      final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
      // Rec.601 chrominance. Cb and Cr are stored offset by 128, the same as
      // a JPEG stores them, so the window below is the textbook one.
      final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
      final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
      final luma = 0.299 * r + 0.587 * g + 0.114 * b;
      final skin =
          cb >= 77 &&
          cb <= 130 &&
          cr >= 133 &&
          cr <= 178 &&
          luma > 40 &&
          r > g &&
          r > b;
      if (skin) {
        raw[p] = 255;
        hits++;
      }
    }
    if (hits < raw.length * _minSkinShare) return null;

    // Three box passes ≈ a Gaussian: it closes the gaps around eyes and lips
    // and feathers the edge so the retouch has nowhere to show a seam.
    var mask = raw;
    final radius = math.max(2, (math.min(w, h) * 0.035).round());
    for (var i = 0; i < 3; i++) {
      mask = _blur(mask, w, h, radius);
    }
    return mask;
  }

  /// Separable box blur over a single-channel image.
  static Uint8List _blur(Uint8List src, int w, int h, int radius) {
    final tmp = Uint8List(w * h);
    final out = Uint8List(w * h);
    final span = radius * 2 + 1;

    for (var y = 0; y < h; y++) {
      final row = y * w;
      var sum = 0;
      for (var x = -radius; x <= radius; x++) {
        sum += src[row + x.clamp(0, w - 1)];
      }
      for (var x = 0; x < w; x++) {
        tmp[row + x] = sum ~/ span;
        sum += src[row + (x + radius + 1).clamp(0, w - 1)];
        sum -= src[row + (x - radius).clamp(0, w - 1)];
      }
    }
    for (var x = 0; x < w; x++) {
      var sum = 0;
      for (var y = -radius; y <= radius; y++) {
        sum += tmp[y.clamp(0, h - 1) * w + x];
      }
      for (var y = 0; y < h; y++) {
        out[y * w + x] = sum ~/ span;
        sum += tmp[(y + radius + 1).clamp(0, h - 1) * w + x];
        sum -= tmp[(y - radius).clamp(0, h - 1) * w + x];
      }
    }
    return out;
  }

  /// Packs the single-channel mask into a white RGBA image carrying it in the
  /// alpha channel, which is the shape `BlendMode.srcIn` wants.
  static Future<ui.Image> _toImage(Uint8List mask, int w, int h) {
    final rgba = Uint8List(w * h * 4);
    for (var p = 0, i = 0; p < mask.length; p++, i += 4) {
      rgba[i] = rgba[i + 1] = rgba[i + 2] = 255;
      rgba[i + 3] = mask[p];
    }
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
