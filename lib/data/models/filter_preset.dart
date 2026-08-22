import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A colour-grade preset. The same numbers drive both the live preview
/// (via a 4x5 colour matrix) and the exported file (via FFmpeg filters),
/// so what you see in the player is what lands in the render.
class FilterPreset {
  const FilterPreset({
    required this.id,
    required this.name,
    required this.category,
    this.brightness = 0,
    this.contrast = 1,
    this.saturation = 1,
    this.temperature = 0,
    this.tint = 0,
    this.gamma = 1,
    this.fade = 0,
    this.vignette = 0,
    this.hue = 0,
  });

  final String id;
  final String name;
  final String category;

  /// -1..1 additive lift.
  final double brightness;

  /// 0..2 multiplier around mid grey.
  final double contrast;

  /// 0..2 (0 = greyscale).
  final double saturation;

  /// -1..1 (warm positive, cool negative).
  final double temperature;

  /// -1..1 (magenta positive, green negative).
  final double tint;

  /// 0.3..3 gamma.
  final double gamma;

  /// 0..1 milky film lift.
  final double fade;

  /// 0..1 corner darkening (preview-only overlay + FFmpeg vignette).
  final double vignette;

  /// -1..1 hue rotation, mapped to -180..180 degrees.
  final double hue;

  bool get isIdentity =>
      brightness == 0 &&
      contrast == 1 &&
      saturation == 1 &&
      temperature == 0 &&
      tint == 0 &&
      gamma == 1 &&
      fade == 0 &&
      vignette == 0 &&
      hue == 0;

  FilterPreset lerpFromIdentity(double t) => FilterPreset(
    id: id,
    name: name,
    category: category,
    brightness: brightness * t,
    contrast: 1 + (contrast - 1) * t,
    saturation: 1 + (saturation - 1) * t,
    temperature: temperature * t,
    tint: tint * t,
    gamma: 1 + (gamma - 1) * t,
    fade: fade * t,
    vignette: vignette * t,
    hue: hue * t,
  );

  /// 4x5 colour matrix consumed by [ColorFiltered] for the live preview.
  List<double> toColorMatrix() {
    // saturation
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final s = saturation;
    var m = <double>[
      lr + (1 - lr) * s, lg - lg * s, lb - lb * s, 0, 0, //
      lr - lr * s, lg + (1 - lg) * s, lb - lb * s, 0, 0, //
      lr - lr * s, lg - lg * s, lb + (1 - lb) * s, 0, 0, //
      0, 0, 0, 1, 0,
    ];

    // Contrast and brightness the way FFmpeg's `eq` applies them: to the luma
    // only, with the chroma left where it is.
    //
    // Scaling R, G and B each by the contrast — which is what this used to do
    // — drives a channel that is already high straight into the clip, and the
    // exported file, which goes through `eq`, does not follow it there. The
    // gap was widest on the most saturated looks in the library: the preview
    // painted 255 where the render wrote 240. Holding the chroma and moving
    // the luma is the same arithmetic `eq` does, and it is still a matrix, so
    // the preview pays nothing for the agreement.
    final c = contrast;
    final k = c - 1;
    final t = 128 * (1 - c) + brightness * 255.0;
    m = _multiply(<double>[
      1 + k * lr, k * lg, k * lb, 0, t, //
      k * lr, 1 + k * lg, k * lb, 0, t, //
      k * lr, k * lg, 1 + k * lb, 0, t, //
      0, 0, 0, 1, 0,
    ], m);

    // white balance: push red up / blue down for warmth, green for tint
    final wr = 1 + temperature * 0.35;
    final wb = 1 - temperature * 0.35;
    final wg = 1 - tint * 0.25;
    m = _multiply(<double>[
      wr, 0, 0, 0, 0, //
      0, wg, 0, 0, 0, //
      0, 0, wb, 0, 0, //
      0, 0, 0, 1, 0,
    ], m);

    // hue rotation about the luma axis
    if (hue != 0) {
      final angle = hue * math.pi;
      final c = math.cos(angle), sn = math.sin(angle);
      const lr = 0.213, lg = 0.715, lb = 0.072;
      m = _multiply(<double>[
        lr + c * (1 - lr) - sn * lr,
        lg - c * lg - sn * lg,
        lb - c * lb + sn * (1 - lb),
        0,
        0,
        lr - c * lr + sn * 0.143,
        lg + c * (1 - lg) + sn * 0.140,
        lb - c * lb - sn * 0.283,
        0,
        0,
        lr - c * lr - sn * (1 - lr),
        lg - c * lg + sn * lg,
        lb + c * (1 - lb) + sn * lb,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ], m);
    }

    // film fade lifts the blacks
    if (fade > 0) {
      final k = 1 - fade * 0.35;
      final lift = fade * 42.0;
      m = _multiply(<double>[
        k, 0, 0, 0, lift, //
        0, k, 0, 0, lift, //
        0, 0, k, 0, lift * 1.1, //
        0, 0, 0, 1, 0,
      ], m);
    }
    return m;
  }

  /// FFmpeg `-vf` fragment that reproduces this grade at export time.
  String toFFmpegFilter() {
    final parts = <String>[];
    if (brightness != 0 || contrast != 1 || saturation != 1 || gamma != 1) {
      parts.add(
        'eq=brightness=${brightness.toStringAsFixed(3)}'
        ':contrast=${contrast.toStringAsFixed(3)}'
        ':saturation=${saturation.toStringAsFixed(3)}'
        ':gamma=${gamma.toStringAsFixed(3)}',
      );
    }
    if (temperature != 0 || tint != 0) {
      final rr = (1 + temperature * 0.35).toStringAsFixed(3);
      final gg = (1 - tint * 0.25).toStringAsFixed(3);
      final bb = (1 - temperature * 0.35).toStringAsFixed(3);
      parts.add('colorchannelmixer=rr=$rr:gg=$gg:bb=$bb');
    }
    if (fade > 0) {
      final lift = (fade * 0.16).toStringAsFixed(3);
      // The points of a curve are separated by spaces and the whole list is
      // quoted. A colon between them reads as `curves`' own option separator,
      // which makes the second point a stray argument and FFmpeg rejects the
      // entire graph — so a look with any fade at all would fail its export.
      parts.add("curves=all='0/$lift 1/1'");
    }
    if (hue != 0) {
      parts.add('hue=h=${(hue * 180).toStringAsFixed(2)}');
    }
    if (vignette > 0) {
      final angle = (math.pi / 5) * (0.6 + vignette * 0.9);
      parts.add('vignette=angle=${angle.toStringAsFixed(3)}');
    }
    return parts.join(',');
  }

  static List<double> _multiply(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 5; col++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += a[row * 5 + k] * b[k * 5 + col];
        }
        if (col == 4) sum += a[row * 5 + 4];
        out[row * 5 + col] = sum;
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {'id': id};

  static FilterPreset fromId(String? id) => FilterLibrary.all.firstWhere(
    (f) => f.id == id,
    orElse: () => FilterLibrary.none,
  );
}

/// The built-in grade library, grouped into the filter tabs.
class FilterLibrary {
  FilterLibrary._();

  static const none = FilterPreset(id: 'none', name: 'None', category: 'None');

  static const List<FilterPreset> all = [
    none,
    // ---------------------------------------------------------------- Film
    FilterPreset(
      id: 'kodak',
      name: 'Kodak',
      category: 'Film',
      contrast: 1.08,
      saturation: 1.12,
      temperature: 0.18,
      fade: 0.12,
    ),
    FilterPreset(
      id: 'portra',
      name: 'Portra',
      category: 'Film',
      brightness: 0.04,
      contrast: 0.94,
      saturation: 1.05,
      temperature: 0.12,
      fade: 0.2,
    ),
    FilterPreset(
      id: 'fuji',
      name: 'Fuji',
      category: 'Film',
      contrast: 1.05,
      saturation: 1.1,
      temperature: -0.1,
      tint: -0.08,
    ),
    FilterPreset(
      id: 'vintage',
      name: 'Vintage',
      category: 'Film',
      contrast: 0.9,
      saturation: 0.82,
      temperature: 0.22,
      fade: 0.3,
      vignette: 0.35,
    ),
    FilterPreset(
      id: 'super8',
      name: 'Super8',
      category: 'Film',
      brightness: 0.03,
      contrast: 1.12,
      saturation: 0.9,
      temperature: 0.3,
      fade: 0.25,
      vignette: 0.5,
    ),
    FilterPreset(
      id: 'polaroid',
      name: 'Polaroid',
      category: 'Film',
      brightness: 0.08,
      contrast: 0.88,
      saturation: 0.94,
      temperature: 0.16,
      fade: 0.34,
    ),
    FilterPreset(
      id: 'ektar',
      name: 'Ektar',
      category: 'Film',
      contrast: 1.16,
      saturation: 1.24,
      temperature: 0.1,
    ),
    FilterPreset(
      id: 'agfa',
      name: 'Agfa',
      category: 'Film',
      contrast: 1.02,
      saturation: 0.96,
      temperature: -0.06,
      tint: 0.1,
      fade: 0.18,
    ),
    FilterPreset(
      id: 'cinestill',
      name: 'Cinestll',
      category: 'Film',
      contrast: 1.1,
      saturation: 1.06,
      temperature: -0.14,
      fade: 0.22,
      vignette: 0.2,
    ),
    FilterPreset(
      id: 'expired',
      name: 'Expired',
      category: 'Film',
      contrast: 0.86,
      saturation: 0.72,
      temperature: 0.28,
      tint: 0.18,
      fade: 0.4,
    ),
    FilterPreset(
      id: 'grain8mm',
      name: '8mm',
      category: 'Film',
      brightness: -0.02,
      contrast: 1.2,
      saturation: 0.8,
      temperature: 0.24,
      fade: 0.2,
      vignette: 0.55,
    ),
    FilterPreset(
      id: 'faded70',
      name: 'Faded 70',
      category: 'Film',
      brightness: 0.06,
      contrast: 0.84,
      saturation: 0.86,
      temperature: 0.2,
      fade: 0.42,
    ),
    // ---------------------------------------------------------------- Mood
    FilterPreset(
      id: 'teal',
      name: 'Teal',
      category: 'Mood',
      contrast: 1.14,
      saturation: 1.05,
      temperature: -0.22,
      tint: -0.1,
    ),
    FilterPreset(
      id: 'moody',
      name: 'Moody',
      category: 'Mood',
      brightness: -0.05,
      contrast: 1.2,
      saturation: 0.86,
      temperature: -0.1,
      vignette: 0.4,
    ),
    FilterPreset(
      id: 'noir',
      name: 'Noir',
      category: 'Mood',
      contrast: 1.3,
      saturation: 0,
      vignette: 0.45,
    ),
    FilterPreset(
      id: 'mono',
      name: 'Mono',
      category: 'Mood',
      contrast: 1.06,
      saturation: 0,
    ),
    FilterPreset(
      id: 'monoSoft',
      name: 'Mono Sft',
      category: 'Mood',
      contrast: 0.9,
      saturation: 0,
      fade: 0.24,
    ),
    FilterPreset(
      id: 'sepia',
      name: 'Sepia',
      category: 'Mood',
      saturation: 0.25,
      temperature: 0.45,
      fade: 0.16,
    ),
    FilterPreset(
      id: 'midnight',
      name: 'Midnight',
      category: 'Mood',
      brightness: -0.1,
      contrast: 1.24,
      saturation: 0.8,
      temperature: -0.3,
      vignette: 0.5,
    ),
    FilterPreset(
      id: 'ember',
      name: 'Ember',
      category: 'Mood',
      brightness: -0.04,
      contrast: 1.18,
      saturation: 1.1,
      temperature: 0.38,
      vignette: 0.4,
    ),
    FilterPreset(
      id: 'ash',
      name: 'Ash',
      category: 'Mood',
      contrast: 1.05,
      saturation: 0.42,
      temperature: -0.08,
      fade: 0.2,
    ),
    FilterPreset(
      id: 'ink',
      name: 'Ink',
      category: 'Mood',
      contrast: 1.5,
      saturation: 0,
      gamma: 0.9,
    ),
    FilterPreset(
      id: 'rain',
      name: 'Rain',
      category: 'Mood',
      brightness: -0.03,
      contrast: 1.02,
      saturation: 0.68,
      temperature: -0.24,
      fade: 0.22,
    ),
    // -------------------------------------------------------------- Bright
    FilterPreset(
      id: 'clean',
      name: 'Clean',
      category: 'Bright',
      brightness: 0.05,
      contrast: 1.05,
      saturation: 1.06,
    ),
    FilterPreset(
      id: 'bright',
      name: 'Bright',
      category: 'Bright',
      brightness: 0.12,
      contrast: 0.98,
      saturation: 1.1,
    ),
    FilterPreset(
      id: 'airy',
      name: 'Airy',
      category: 'Bright',
      brightness: 0.1,
      contrast: 0.9,
      saturation: 0.95,
      fade: 0.24,
    ),
    FilterPreset(
      id: 'pop',
      name: 'Pop',
      category: 'Bright',
      contrast: 1.22,
      saturation: 1.4,
    ),
    FilterPreset(
      id: 'crisp',
      name: 'Crisp',
      category: 'Bright',
      brightness: 0.04,
      contrast: 1.18,
      saturation: 1.14,
      gamma: 1.05,
    ),
    FilterPreset(
      id: 'daylight',
      name: 'Daylight',
      category: 'Bright',
      brightness: 0.1,
      contrast: 1.04,
      saturation: 1.08,
      temperature: 0.1,
    ),
    FilterPreset(
      id: 'snow',
      name: 'Snow',
      category: 'Bright',
      brightness: 0.16,
      contrast: 0.94,
      saturation: 0.9,
      temperature: -0.12,
    ),
    FilterPreset(
      id: 'pastel',
      name: 'Pastel',
      category: 'Bright',
      brightness: 0.12,
      contrast: 0.82,
      saturation: 0.88,
      fade: 0.3,
    ),
    FilterPreset(
      id: 'honey',
      name: 'Honey',
      category: 'Bright',
      brightness: 0.08,
      contrast: 1.0,
      saturation: 1.16,
      temperature: 0.26,
    ),
    FilterPreset(
      id: 'linen',
      name: 'Linen',
      category: 'Bright',
      brightness: 0.09,
      contrast: 0.92,
      saturation: 0.82,
      temperature: 0.14,
      fade: 0.26,
    ),
    // ---------------------------------------------------------------- Cine
    FilterPreset(
      id: 'cine',
      name: 'Cine',
      category: 'Cine',
      contrast: 1.16,
      saturation: 0.95,
      temperature: -0.12,
      fade: 0.16,
      vignette: 0.24,
    ),
    FilterPreset(
      id: 'blockbuster',
      name: 'Blockbst',
      category: 'Cine',
      contrast: 1.24,
      saturation: 1.1,
      temperature: 0.14,
      tint: -0.14,
      vignette: 0.3,
    ),
    FilterPreset(
      id: 'cyberpunk',
      name: 'Cyber',
      category: 'Cine',
      contrast: 1.3,
      saturation: 1.35,
      temperature: -0.28,
      tint: 0.2,
      vignette: 0.35,
    ),
    FilterPreset(
      id: 'sunset',
      name: 'Sunset',
      category: 'Cine',
      brightness: 0.03,
      contrast: 1.08,
      saturation: 1.18,
      temperature: 0.34,
    ),
    FilterPreset(
      id: 'bleach',
      name: 'Bleach',
      category: 'Cine',
      contrast: 1.36,
      saturation: 0.44,
      fade: 0.14,
      vignette: 0.26,
    ),
    FilterPreset(
      id: 'matrix',
      name: 'Matrix',
      category: 'Cine',
      contrast: 1.2,
      saturation: 0.9,
      temperature: -0.2,
      tint: -0.34,
      vignette: 0.32,
    ),
    FilterPreset(
      id: 'desert',
      name: 'Desert',
      category: 'Cine',
      contrast: 1.12,
      saturation: 1.02,
      temperature: 0.32,
      tint: 0.08,
      vignette: 0.22,
    ),
    FilterPreset(
      id: 'nordic',
      name: 'Nordic',
      category: 'Cine',
      brightness: 0.02,
      contrast: 1.1,
      saturation: 0.78,
      temperature: -0.26,
      fade: 0.18,
    ),
    FilterPreset(
      id: 'thriller',
      name: 'Thriller',
      category: 'Cine',
      brightness: -0.08,
      contrast: 1.32,
      saturation: 0.72,
      temperature: -0.16,
      vignette: 0.52,
    ),
    FilterPreset(
      id: 'goldenHour',
      name: 'Golden',
      category: 'Cine',
      brightness: 0.06,
      contrast: 1.06,
      saturation: 1.22,
      temperature: 0.4,
      vignette: 0.2,
    ),
    FilterPreset(
      id: 'anamorphic',
      name: 'Anamorph',
      category: 'Cine',
      contrast: 1.2,
      saturation: 1.04,
      temperature: -0.16,
      tint: -0.08,
      fade: 0.14,
      vignette: 0.38,
    ),
    // --------------------------------------------------------------- Vivid
    FilterPreset(
      id: 'vivid',
      name: 'Vivid',
      category: 'Vivid',
      contrast: 1.24,
      saturation: 1.5,
    ),
    FilterPreset(
      id: 'punch',
      name: 'Punch',
      category: 'Vivid',
      brightness: -0.02,
      contrast: 1.4,
      saturation: 1.34,
      vignette: 0.18,
    ),
    FilterPreset(
      id: 'candy',
      name: 'Candy',
      category: 'Vivid',
      brightness: 0.06,
      contrast: 1.1,
      saturation: 1.55,
      tint: 0.12,
    ),
    FilterPreset(
      id: 'tropical',
      name: 'Tropical',
      category: 'Vivid',
      contrast: 1.14,
      saturation: 1.42,
      temperature: 0.16,
      tint: -0.12,
    ),
    FilterPreset(
      id: 'neonNight',
      name: 'Neon',
      category: 'Vivid',
      brightness: -0.06,
      contrast: 1.34,
      saturation: 1.6,
      temperature: -0.24,
      tint: 0.26,
      vignette: 0.4,
    ),
    FilterPreset(
      id: 'popArt',
      name: 'Pop Art',
      category: 'Vivid',
      contrast: 1.5,
      saturation: 1.7,
      gamma: 1.1,
    ),
    FilterPreset(
      id: 'sunburst',
      name: 'Sunburst',
      category: 'Vivid',
      brightness: 0.08,
      contrast: 1.16,
      saturation: 1.38,
      temperature: 0.3,
    ),
    FilterPreset(
      id: 'aqua',
      name: 'Aqua',
      category: 'Vivid',
      contrast: 1.12,
      saturation: 1.36,
      temperature: -0.3,
      tint: -0.16,
    ),
    // -------------------------------------------------------------- Beauty
    FilterPreset(
      id: 'softSkin',
      name: 'Soft',
      category: 'Beauty',
      brightness: 0.07,
      contrast: 0.92,
      saturation: 1.02,
      temperature: 0.08,
      fade: 0.2,
    ),
    FilterPreset(
      id: 'glow',
      name: 'Glow',
      category: 'Beauty',
      brightness: 0.12,
      contrast: 0.9,
      saturation: 1.06,
      temperature: 0.12,
      fade: 0.28,
    ),
    FilterPreset(
      id: 'rosy',
      name: 'Rosy',
      category: 'Beauty',
      brightness: 0.08,
      contrast: 0.96,
      saturation: 1.1,
      temperature: 0.18,
      tint: 0.16,
    ),
    FilterPreset(
      id: 'porcelain',
      name: 'Porcelan',
      category: 'Beauty',
      brightness: 0.14,
      contrast: 0.86,
      saturation: 0.88,
      temperature: 0.06,
      fade: 0.3,
    ),
    FilterPreset(
      id: 'bronze',
      name: 'Bronze',
      category: 'Beauty',
      brightness: 0.02,
      contrast: 1.08,
      saturation: 1.12,
      temperature: 0.3,
      vignette: 0.18,
    ),
    FilterPreset(
      id: 'velvet',
      name: 'Velvet',
      category: 'Beauty',
      brightness: -0.02,
      contrast: 1.06,
      saturation: 0.94,
      temperature: 0.1,
      fade: 0.22,
      vignette: 0.3,
    ),
    // ---------------------------------------------------------------- Vlog
    FilterPreset(
      id: 'vlogDaily',
      name: 'Daily',
      category: 'Vlog',
      brightness: 0.05,
      contrast: 1.08,
      saturation: 1.12,
      temperature: 0.06,
    ),
    FilterPreset(
      id: 'vlogCity',
      name: 'City',
      category: 'Vlog',
      contrast: 1.16,
      saturation: 1.02,
      temperature: -0.14,
      tint: -0.06,
      vignette: 0.16,
    ),
    FilterPreset(
      id: 'vlogTravel',
      name: 'Travel',
      category: 'Vlog',
      brightness: 0.03,
      contrast: 1.12,
      saturation: 1.24,
      temperature: 0.1,
    ),
    FilterPreset(
      id: 'vlogSoft',
      name: 'SoftVlog',
      category: 'Vlog',
      brightness: 0.08,
      contrast: 0.94,
      saturation: 1.05,
      fade: 0.18,
    ),
    FilterPreset(
      id: 'vlogStreet',
      name: 'Street',
      category: 'Vlog',
      brightness: -0.02,
      contrast: 1.22,
      saturation: 0.9,
      temperature: -0.08,
      fade: 0.12,
      vignette: 0.24,
    ),
    FilterPreset(
      id: 'vlogFresh',
      name: 'Fresh',
      category: 'Vlog',
      brightness: 0.06,
      contrast: 1.05,
      saturation: 1.18,
      temperature: -0.06,
      tint: -0.08,
    ),
    FilterPreset(
      id: 'vlogWarm',
      name: 'Warm',
      category: 'Vlog',
      brightness: 0.04,
      contrast: 1.04,
      saturation: 1.1,
      temperature: 0.24,
    ),
    FilterPreset(
      id: 'vlogCool',
      name: 'Cool',
      category: 'Vlog',
      brightness: 0.04,
      contrast: 1.06,
      saturation: 1.05,
      temperature: -0.22,
    ),
    // ------------------------------------------------------------ Portrait
    FilterPreset(
      id: 'portraitNatural',
      name: 'Natural',
      category: 'Portrait',
      brightness: 0.04,
      contrast: 1.02,
      saturation: 1.04,
      temperature: 0.08,
    ),
    FilterPreset(
      id: 'portraitWarmSkin',
      name: 'WarmSkin',
      category: 'Portrait',
      brightness: 0.06,
      contrast: 0.98,
      saturation: 1.08,
      temperature: 0.2,
      fade: 0.12,
    ),
    FilterPreset(
      id: 'portraitFair',
      name: 'Fair',
      category: 'Portrait',
      brightness: 0.12,
      contrast: 0.9,
      saturation: 0.94,
      temperature: 0.05,
      fade: 0.2,
    ),
    FilterPreset(
      id: 'portraitTan',
      name: 'Tan',
      category: 'Portrait',
      brightness: 0.02,
      contrast: 1.06,
      saturation: 1.14,
      temperature: 0.26,
      tint: 0.06,
    ),
    FilterPreset(
      id: 'portraitStudio',
      name: 'Studio',
      category: 'Portrait',
      contrast: 1.1,
      temperature: 0.04,
      gamma: 1.04,
    ),
    FilterPreset(
      id: 'portraitFilmSkin',
      name: 'FilmSkin',
      category: 'Portrait',
      saturation: 0.98,
      temperature: 0.14,
      fade: 0.24,
      vignette: 0.14,
    ),
    FilterPreset(
      id: 'portraitDusk',
      name: 'Dusk',
      category: 'Portrait',
      brightness: -0.03,
      contrast: 1.1,
      saturation: 1.02,
      temperature: 0.18,
      vignette: 0.28,
    ),
    // --------------------------------------------------------------- Retro
    FilterPreset(
      id: 'retro70',
      name: 'Retro 70',
      category: 'Retro',
      contrast: 0.92,
      saturation: 0.9,
      temperature: 0.26,
      tint: 0.1,
      fade: 0.32,
    ),
    FilterPreset(
      id: 'retro80',
      name: 'Retro 80',
      category: 'Retro',
      contrast: 1.14,
      saturation: 1.28,
      temperature: -0.1,
      tint: 0.22,
      vignette: 0.24,
    ),
    FilterPreset(
      id: 'retroVhs',
      name: 'VHS',
      category: 'Retro',
      brightness: 0.02,
      contrast: 0.94,
      saturation: 1.16,
      temperature: -0.12,
      tint: 0.18,
      fade: 0.28,
    ),
    FilterPreset(
      id: 'retroDisco',
      name: 'Disco',
      category: 'Retro',
      contrast: 1.2,
      saturation: 1.45,
      temperature: 0.08,
      tint: 0.24,
      vignette: 0.3,
    ),
    FilterPreset(
      id: 'retroOldTape',
      name: 'OldTape',
      category: 'Retro',
      contrast: 0.9,
      saturation: 0.6,
      temperature: 0.34,
      fade: 0.36,
      vignette: 0.3,
    ),
    FilterPreset(
      id: 'retroInstant',
      name: 'Instant',
      category: 'Retro',
      brightness: 0.09,
      contrast: 0.86,
      saturation: 0.92,
      temperature: 0.2,
      fade: 0.36,
    ),
    FilterPreset(
      id: 'retroPrint',
      name: 'Print',
      category: 'Retro',
      contrast: 1.26,
      saturation: 0.15,
      gamma: 0.95,
      fade: 0.14,
    ),
    FilterPreset(
      id: 'retroWashed',
      name: 'Washed',
      category: 'Retro',
      brightness: 0.05,
      contrast: 0.82,
      saturation: 0.7,
      temperature: 0.16,
      fade: 0.44,
    ),
    // ------------------------------------------------------------- Scenery
    FilterPreset(
      id: 'sceneryForest',
      name: 'Forest',
      category: 'Scenery',
      contrast: 1.12,
      saturation: 1.2,
      temperature: -0.1,
      tint: -0.2,
    ),
    FilterPreset(
      id: 'scenerySky',
      name: 'Sky',
      category: 'Scenery',
      brightness: 0.04,
      contrast: 1.14,
      saturation: 1.18,
      temperature: -0.2,
      tint: -0.06,
    ),
    FilterPreset(
      id: 'sceneryBeach',
      name: 'Beach',
      category: 'Scenery',
      brightness: 0.08,
      contrast: 1.08,
      saturation: 1.26,
      temperature: 0.12,
      tint: -0.14,
    ),
    FilterPreset(
      id: 'sceneryMountain',
      name: 'Mountn',
      category: 'Scenery',
      contrast: 1.2,
      saturation: 1.05,
      temperature: -0.14,
      gamma: 0.96,
      vignette: 0.2,
    ),
    FilterPreset(
      id: 'sceneryDune',
      name: 'Dune',
      category: 'Scenery',
      brightness: 0.04,
      contrast: 1.1,
      saturation: 1.12,
      temperature: 0.3,
      tint: 0.08,
    ),
    FilterPreset(
      id: 'sceneryLake',
      name: 'Lake',
      category: 'Scenery',
      brightness: 0.02,
      contrast: 1.1,
      saturation: 1.14,
      temperature: -0.24,
      tint: -0.12,
    ),
    FilterPreset(
      id: 'sceneryUrban',
      name: 'Urban',
      category: 'Scenery',
      contrast: 1.24,
      saturation: 0.92,
      temperature: -0.06,
      fade: 0.1,
      vignette: 0.26,
    ),
    FilterPreset(
      id: 'sceneryDawn',
      name: 'Dawn',
      category: 'Scenery',
      brightness: 0.07,
      contrast: 1.02,
      saturation: 1.16,
      temperature: 0.22,
      tint: 0.1,
    ),
    // ---------------------------------------------------------------- Food
    FilterPreset(
      id: 'foodTasty',
      name: 'Tasty',
      category: 'Food',
      brightness: 0.05,
      contrast: 1.12,
      saturation: 1.26,
      temperature: 0.2,
    ),
    FilterPreset(
      id: 'foodServe',
      name: 'Serve',
      category: 'Food',
      brightness: 0.12,
      contrast: 1.06,
      saturation: 1.18,
      temperature: 0.1,
    ),
    FilterPreset(
      id: 'foodRich',
      name: 'Rich',
      category: 'Food',
      brightness: -0.02,
      contrast: 1.24,
      saturation: 1.3,
      temperature: 0.14,
      vignette: 0.22,
    ),
    FilterPreset(
      id: 'foodGrill',
      name: 'Grill',
      category: 'Food',
      brightness: -0.04,
      contrast: 1.28,
      saturation: 1.22,
      temperature: 0.3,
      vignette: 0.3,
    ),
    FilterPreset(
      id: 'foodSweet',
      name: 'Sweet',
      category: 'Food',
      brightness: 0.1,
      contrast: 0.96,
      saturation: 1.3,
      temperature: 0.12,
      tint: 0.16,
    ),
    FilterPreset(
      id: 'foodSalad',
      name: 'Salad',
      category: 'Food',
      brightness: 0.06,
      contrast: 1.1,
      saturation: 1.28,
      temperature: -0.08,
      tint: -0.18,
    ),
    FilterPreset(
      id: 'foodCafe',
      name: 'Cafe',
      category: 'Food',
      brightness: 0.03,
      contrast: 1.04,
      saturation: 1.02,
      temperature: 0.28,
      fade: 0.2,
      vignette: 0.18,
    ),
    // ----------------------------------------------------------------- B&W
    FilterPreset(
      id: 'bwClassic',
      name: 'Classic',
      category: 'B&W',
      contrast: 1.12,
      saturation: 0,
    ),
    FilterPreset(
      id: 'bwHighKey',
      name: 'HighKey',
      category: 'B&W',
      brightness: 0.16,
      contrast: 0.94,
      saturation: 0,
      fade: 0.2,
    ),
    FilterPreset(
      id: 'bwLowKey',
      name: 'LowKey',
      category: 'B&W',
      brightness: -0.1,
      contrast: 1.34,
      saturation: 0,
      vignette: 0.5,
    ),
    FilterPreset(
      id: 'bwTriX',
      name: 'TriX',
      category: 'B&W',
      contrast: 1.2,
      saturation: 0,
      gamma: 0.95,
      fade: 0.12,
      vignette: 0.18,
    ),
    FilterPreset(
      id: 'bwSilver',
      name: 'Silver',
      category: 'B&W',
      brightness: 0.05,
      contrast: 1.06,
      saturation: 0,
      gamma: 1.06,
    ),
    FilterPreset(
      id: 'bwCharcoal',
      name: 'Charcol',
      category: 'B&W',
      brightness: -0.05,
      contrast: 1.26,
      saturation: 0,
      gamma: 0.92,
    ),
    FilterPreset(
      id: 'bwPlatinum',
      name: 'Platinm',
      category: 'B&W',
      brightness: 0.08,
      contrast: 0.9,
      saturation: 0,
      fade: 0.26,
    ),
    FilterPreset(
      id: 'bwSharp',
      name: 'SharpBW',
      category: 'B&W',
      contrast: 1.45,
      saturation: 0,
      gamma: 0.98,
    ),
    // -------------------------------------------------------------- Season
    FilterPreset(
      id: 'seasonSummer',
      name: 'Summer',
      category: 'Season',
      brightness: 0.1,
      contrast: 1.1,
      saturation: 1.3,
      temperature: 0.16,
      tint: -0.08,
    ),
    FilterPreset(
      id: 'seasonWinter',
      name: 'Winter',
      category: 'Season',
      brightness: 0.08,
      contrast: 1.08,
      saturation: 0.82,
      temperature: -0.3,
      tint: -0.06,
    ),
    FilterPreset(
      id: 'seasonAutumn',
      name: 'Autumn',
      category: 'Season',
      contrast: 1.12,
      saturation: 1.28,
      temperature: 0.3,
      tint: 0.08,
      vignette: 0.16,
    ),
    FilterPreset(
      id: 'seasonSpring',
      name: 'Spring',
      category: 'Season',
      brightness: 0.09,
      saturation: 1.2,
      temperature: 0.04,
      tint: -0.12,
      fade: 0.12,
    ),
    FilterPreset(
      id: 'seasonMonsoon',
      name: 'Monsoon',
      category: 'Season',
      brightness: -0.02,
      contrast: 1.05,
      saturation: 0.76,
      temperature: -0.2,
      fade: 0.2,
    ),
    FilterPreset(
      id: 'seasonHoliday',
      name: 'Holiday',
      category: 'Season',
      brightness: 0.04,
      contrast: 1.16,
      saturation: 1.34,
      temperature: 0.18,
      vignette: 0.24,
    ),
    // --------------------------------------------------------------- Party
    FilterPreset(
      id: 'partyClub',
      name: 'Club',
      category: 'Party',
      brightness: -0.08,
      contrast: 1.3,
      saturation: 1.45,
      temperature: -0.18,
      tint: 0.3,
      vignette: 0.42,
    ),
    FilterPreset(
      id: 'partyLaser',
      name: 'Laser',
      category: 'Party',
      brightness: -0.04,
      contrast: 1.26,
      saturation: 1.5,
      temperature: -0.26,
      tint: 0.34,
      vignette: 0.36,
    ),
    FilterPreset(
      id: 'partyGlow',
      name: 'Glowstck',
      category: 'Party',
      brightness: 0.02,
      contrast: 1.2,
      saturation: 1.55,
      temperature: -0.1,
      tint: 0.22,
    ),
    FilterPreset(
      id: 'partyNight',
      name: 'Night',
      category: 'Party',
      brightness: -0.12,
      contrast: 1.28,
      saturation: 1.1,
      temperature: -0.24,
      vignette: 0.5,
    ),
    FilterPreset(
      id: 'partyConfetti',
      name: 'Confeti',
      category: 'Party',
      brightness: 0.08,
      contrast: 1.14,
      saturation: 1.42,
      temperature: 0.06,
      tint: 0.18,
    ),
    FilterPreset(
      id: 'partyStage',
      name: 'Stage',
      category: 'Party',
      brightness: -0.06,
      contrast: 1.34,
      saturation: 1.28,
      temperature: 0.12,
      tint: 0.2,
      vignette: 0.44,
    ),
    // ------------------------------------------------------------- Wedding
    FilterPreset(
      id: 'weddingBridal',
      name: 'Bridal',
      category: 'Wedding',
      brightness: 0.1,
      contrast: 0.94,
      saturation: 0.98,
      temperature: 0.1,
      fade: 0.24,
    ),
    FilterPreset(
      id: 'weddingBlush',
      name: 'Blush',
      category: 'Wedding',
      brightness: 0.09,
      contrast: 0.96,
      saturation: 1.08,
      temperature: 0.14,
      tint: 0.2,
      fade: 0.2,
    ),
    FilterPreset(
      id: 'weddingIvory',
      name: 'Ivory',
      category: 'Wedding',
      brightness: 0.14,
      contrast: 0.88,
      saturation: 0.86,
      temperature: 0.12,
      fade: 0.3,
    ),
    FilterPreset(
      id: 'weddingRomance',
      name: 'Romance',
      category: 'Wedding',
      brightness: 0.06,
      saturation: 1.1,
      temperature: 0.18,
      tint: 0.12,
      vignette: 0.2,
    ),
    FilterPreset(
      id: 'weddingGold',
      name: 'Gold',
      category: 'Wedding',
      brightness: 0.08,
      contrast: 1.02,
      saturation: 1.14,
      temperature: 0.32,
      fade: 0.16,
    ),
    FilterPreset(
      id: 'weddingPearl',
      name: 'Pearl',
      category: 'Wedding',
      brightness: 0.16,
      contrast: 0.86,
      saturation: 0.9,
      temperature: 0.04,
      tint: 0.06,
      fade: 0.32,
    ),
  ];

  /// Tab order. The six groups the library opened with keep their places —
  /// a pack that moves is a pack the user has to hunt for — and the packs
  /// that fill out a phone editor's filter row follow them.
  static List<String> get categories => [
    'None',
    'Film',
    'Mood',
    'Bright',
    'Cine',
    'Vivid',
    'Beauty',
    'Vlog',
    'Portrait',
    'Retro',
    'B&W',
    'Scenery',
    'Food',
    'Season',
    'Party',
    'Wedding',
  ];

  static List<FilterPreset> byCategory(String c) =>
      all.where((f) => f.category == c).toList();
}
