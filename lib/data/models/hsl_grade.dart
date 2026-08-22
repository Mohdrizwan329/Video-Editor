import 'dart:math' as math;

/// Per-hue grading: eight colour bands, each with a hue shift, a saturation
/// scale and a luminance lift.
///
/// This is the tool that lets a user warm the skin without warming the sky,
/// or drop the green of a lawn without touching anything else. It cannot be
/// written as a colour matrix — what it does to a pixel depends on the hue
/// that pixel already has — so the preview runs it in a shader and the
/// exporter bakes it into a 3D LUT. Both read the numbers here, which is
/// what keeps the two from drifting.
class HslGrade {
  HslGrade({
    List<double>? hue,
    List<double>? saturation,
    List<double>? luminance,
  }) : hue = hue ?? List<double>.filled(bandCount, 0),
       saturation = saturation ?? List<double>.filled(bandCount, 0),
       luminance = luminance ?? List<double>.filled(bandCount, 0);

  static const int bandCount = 8;

  /// The bands, in the order they are shown.
  static const List<String> bandNames = [
    'Red',
    'Orange',
    'Yellow',
    'Green',
    'Aqua',
    'Blue',
    'Purple',
    'Magenta',
  ];

  /// Where each band sits on the hue wheel, in degrees. The spacing is
  /// uneven on purpose: it follows how much of the wheel each name actually
  /// covers, which is what the stills tools settled on.
  static const List<double> bandCentres = [0, 30, 60, 120, 180, 240, 280, 320];

  /// How far a hue slider at full travel turns the band, in degrees. Beyond
  /// this a band stops reading as a shifted version of itself and starts
  /// reading as a different colour, which is the effects tool's job.
  static const double maxHueShift = 30;

  /// How far a luminance slider at full travel lifts or drops the band.
  static const double maxLumShift = 0.35;

  /// -1..1 per band.
  final List<double> hue;
  final List<double> saturation;
  final List<double> luminance;

  bool get isNeutral =>
      !hue.any((v) => v != 0) &&
      !saturation.any((v) => v != 0) &&
      !luminance.any((v) => v != 0);

  void reset() {
    for (var i = 0; i < bandCount; i++) {
      hue[i] = saturation[i] = luminance[i] = 0;
    }
  }

  HslGrade copy() => HslGrade(
    hue: List<double>.from(hue),
    saturation: List<double>.from(saturation),
    luminance: List<double>.from(luminance),
  );

  /// How much each band owns a pixel at [degrees] on the wheel.
  ///
  /// The two nearest centres share it, linearly. Sharing between exactly two
  /// keeps the weights summing to one at every hue, so a pixel is never
  /// graded twice over or left half-graded in the gap between two bands.
  static List<double> weightsFor(double degrees) {
    final out = List<double>.filled(bandCount, 0);
    var h = degrees % 360;
    if (h < 0) h += 360;
    for (var i = 0; i < bandCount; i++) {
      final lo = bandCentres[i];
      final next = (i + 1) % bandCount;
      // The last band wraps past 360 back to the first.
      final hi = next == 0 ? bandCentres[0] + 360 : bandCentres[next];
      final x = h < lo && next == 0 ? h + 360 : h;
      if (x >= lo && x < hi) {
        final t = (x - lo) / (hi - lo);
        out[i] = 1 - t;
        out[next] = t;
        return out;
      }
    }
    // Below the first centre: shared with the band that wraps into it.
    final lo = bandCentres[bandCount - 1];
    final hi = bandCentres[0] + 360;
    final t = (h + 360 - lo) / (hi - lo);
    out[bandCount - 1] = 1 - t;
    out[0] = t;
    return out;
  }

  /// Grade one colour. Components are 0..1.
  ///
  /// The same arithmetic the shader runs per pixel and the LUT baker runs per
  /// grid point, written once so a test can check it without either.
  (double, double, double) apply(double r, double g, double b) {
    if (isNeutral) return (r, g, b);
    final (h, s, l) = _toHsl(r, g, b);
    // A pixel with no colour in it has no band to belong to: grading grey by
    // hue would tint it out of nowhere.
    if (s <= 0.001) return (r, g, b);

    final w = weightsFor(h * 360);
    var dh = 0.0, ds = 0.0, dl = 0.0;
    for (var i = 0; i < bandCount; i++) {
      if (w[i] == 0) continue;
      dh += w[i] * hue[i];
      ds += w[i] * saturation[i];
      dl += w[i] * luminance[i];
    }

    final h2 = (h + dh * maxHueShift / 360) % 1.0;
    final s2 = (s * (1 + ds)).clamp(0.0, 1.0);
    final l2 = (l + dl * maxLumShift).clamp(0.0, 1.0);
    return _toRgb(h2 < 0 ? h2 + 1 : h2, s2, l2);
  }

  static (double, double, double) _toHsl(double r, double g, double b) {
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final l = (max + min) / 2;
    if (max == min) return (0, 0, l);
    final d = max - min;
    final s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    double h;
    if (max == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (max == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    return (h / 6, s, l);
  }

  static (double, double, double) _toRgb(double h, double s, double l) {
    if (s == 0) return (l, l, l);
    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    return (_hue(p, q, h + 1 / 3), _hue(p, q, h), _hue(p, q, h - 1 / 3));
  }

  static double _hue(double p, double q, double t) {
    var x = t;
    if (x < 0) x += 1;
    if (x > 1) x -= 1;
    if (x < 1 / 6) return p + (q - p) * 6 * x;
    if (x < 1 / 2) return q;
    if (x < 2 / 3) return p + (q - p) * (2 / 3 - x) * 6;
    return p;
  }

  Map<String, dynamic> toJson() => {'h': hue, 's': saturation, 'l': luminance};

  factory HslGrade.fromJson(Map<String, dynamic>? j) {
    if (j == null) return HslGrade();
    List<double> read(String k) {
      final raw = j[k];
      final out = List<double>.filled(bandCount, 0);
      if (raw is List) {
        for (var i = 0; i < bandCount && i < raw.length; i++) {
          out[i] = (raw[i] as num?)?.toDouble() ?? 0;
        }
      }
      return out;
    }

    return HslGrade(
      hue: read('h'),
      saturation: read('s'),
      luminance: read('l'),
    );
  }
}
