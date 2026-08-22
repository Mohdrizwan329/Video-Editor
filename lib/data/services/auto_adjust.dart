import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../models/adjustments.dart';

/// Reads a frame and works out the grade it is asking for.
///
/// This is the one-tap Auto the phone editors put at the head of their adjust
/// row. It is not a look: it is the correction the picture already needs —
/// open up a frame that is sitting dark, pull one that is blown out back
/// down, stretch the tones of a flat one, and leave alone anything that is
/// already exposed. A frame that needs nothing gets nothing, which is the
/// part that makes the button trustworthy.
class AutoAdjust {
  const AutoAdjust._();

  /// Where the histogram is measured from and to. Sampling the extremes
  /// themselves would let one blown highlight or one crushed shadow — a
  /// specular glint, a letterbox bar — decide the whole grade, so the ends
  /// are trimmed to these percentiles first.
  static const double _lowPercentile = 0.02;
  static const double _highPercentile = 0.98;

  /// Below this the frame is close enough to right that moving it would be
  /// meddling rather than correcting.
  static const double _deadZone = 0.03;

  /// The grade [path]'s frame is asking for, or null when the file cannot be
  /// read. The returned object carries only what Auto sets; everything else
  /// on it is left at zero for the caller to merge as it likes.
  static Future<Adjustments?> forFrame(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 96,
        targetHeight: 96,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      frame.image.dispose();
      codec.dispose();
      if (data == null) return null;
      return _measure(data.buffer.asUint8List());
    } catch (e) {
      debugPrint('auto adjust could not read $path: $e');
      return null;
    }
  }

  /// The maths, split out so a test can hand it pixels without a file.
  @visibleForTesting
  static Adjustments measure(Uint8List rgba) => _measure(rgba);

  static Adjustments _measure(Uint8List rgba) {
    final out = Adjustments();
    final pixels = rgba.length ~/ 4;
    if (pixels == 0) return out;

    // A 256-bin luma histogram, plus the mean distance from grey, which is
    // what says whether the frame is flat in colour as well as in tone.
    final bins = List<int>.filled(256, 0);
    var chromaSum = 0.0;
    for (var i = 0; i < pixels; i++) {
      final o = i * 4;
      final r = rgba[o], g = rgba[o + 1], b = rgba[o + 2];
      final luma = (0.2126 * r + 0.7152 * g + 0.0722 * b).round().clamp(0, 255);
      bins[luma]++;
      final maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
      chromaSum += (maxC - minC) / 255.0;
    }

    final lowCut = (pixels * _lowPercentile).round();
    final highCut = (pixels * _highPercentile).round();
    var seen = 0;
    var black = 0, white = 255;
    for (var v = 0; v < 256; v++) {
      seen += bins[v];
      if (seen >= lowCut) {
        black = v;
        break;
      }
    }
    seen = 0;
    for (var v = 255; v >= 0; v--) {
      seen += bins[v];
      if (seen >= pixels - highCut) {
        white = v;
        break;
      }
    }
    var weighted = 0.0;
    for (var v = 0; v < 256; v++) {
      weighted += v * bins[v];
    }
    final mean = weighted / pixels / 255.0;
    final chroma = chromaSum / pixels;

    // Exposure: carry the mean towards mid grey, but only part of the way.
    // Landing it exactly on 0.5 turns every night shot into a grey one.
    final lift = ((0.5 - mean) * 1.4).clamp(-0.6, 0.6);
    if (lift.abs() > _deadZone) out.brightness = lift;

    // Contrast: a frame using less of the range than this wants stretching,
    // and one already using all of it wants nothing. A frame with no spread
    // at all — a title card, a black gap — is skipped rather than handed the
    // maximum: there are no tones in it to pull apart.
    if (white > black) {
      final spread = (white - black) / 255.0;
      // Never below zero: Auto pulls a flat frame's tones apart, it does not
      // push a frame that already fills the range back together. Flattening
      // a well-exposed shot is a look, and a look is not Auto's to choose.
      final stretch = ((0.92 - spread) * 1.1).clamp(0.0, 0.5);
      if (stretch > _deadZone) out.contrast = stretch;
    }

    // Colour: only lift a frame that is genuinely flat. A shot that is
    // already saturated does not need help, and pushing one that is
    // deliberately monochrome would undo the choice.
    if (chroma > 0.04 && chroma < 0.22) {
      out.saturation = ((0.24 - chroma) * 1.6).clamp(0.0, 0.35);
    }
    return out;
  }
}
