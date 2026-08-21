import 'filter_preset.dart';

/// Manual colour adjustments layered on top of the selected [FilterPreset].
class Adjustments {
  Adjustments({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.temperature = 0,
    this.tint = 0,
    this.sharpen = 0,
    this.vignette = 0,
    this.fade = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.hue = 0,
    this.grain = 0,
    this.blur = 0,
    this.denoise = 0,
    this.curveLow = 0,
    this.curveMid = 0,
    this.curveHigh = 0,
  });

  /// All values are normalised to -1..1 with 0 = untouched.
  double brightness;
  double contrast;
  double saturation;
  double temperature;
  double tint;
  double sharpen;
  double vignette;
  double fade;
  double highlights;
  double shadows;

  /// Hue rotation in -1..1, mapped to -180..180 degrees.
  double hue;

  /// Film grain strength.
  double grain;

  /// Gaussian softening.
  double blur;

  /// Temporal/spatial noise reduction.
  double denoise;

  /// Three-point tone curve lift for shadows, midtones and highlights.
  double curveLow;
  double curveMid;
  double curveHigh;

  bool get isNeutral =>
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      temperature == 0 &&
      tint == 0 &&
      sharpen == 0 &&
      vignette == 0 &&
      fade == 0 &&
      highlights == 0 &&
      shadows == 0 &&
      hue == 0 &&
      grain == 0 &&
      blur == 0 &&
      denoise == 0 &&
      curveLow == 0 &&
      curveMid == 0 &&
      curveHigh == 0;

  void reset() {
    brightness = contrast = saturation = temperature = tint = 0;
    sharpen = vignette = fade = highlights = shadows = 0;
    hue = grain = blur = denoise = 0;
    curveLow = curveMid = curveHigh = 0;
  }

  /// Filters that have no colour-matrix equivalent and so are emitted
  /// separately from the grade at export time.
  List<String> toFFmpegExtras() {
    final out = <String>[];
    if (hasCurves) out.add('curves=all=\'$curveExpression\'');
    if (denoise > 0) {
      final v = (denoise * 6).toStringAsFixed(2);
      out.add('hqdn3d=$v:$v:${(denoise * 8).toStringAsFixed(2)}:'
          '${(denoise * 8).toStringAsFixed(2)}');
    }
    if (blur > 0) out.add('gblur=sigma=${(blur * 12).toStringAsFixed(2)}');
    if (sharpen > 0) {
      out.add('unsharp=5:5:${(sharpen * 1.5).toStringAsFixed(2)}:5:5:0');
    }
    if (grain > 0) {
      out.add('noise=alls=${(grain * 30).round()}:allf=t+u');
    }
    return out;
  }

  bool get hasCurves => curveLow != 0 || curveMid != 0 || curveHigh != 0;

  /// True when something here needs the preview's second shader pass. These
  /// are the sliders with no colour-matrix equivalent, so without it they
  /// only ever show up in the exported file.
  bool get hasShaderExtras =>
      hasCurves || sharpen > 0 || grain > 0 || denoise > 0;

  /// The three control points of the tone curve, shared by the exporter's
  /// `curves` filter and the preview shader so the two cannot drift apart.
  (double, double, double) get curvePoints => (
        (curveLow * 0.25).clamp(0.0, 0.4),
        (0.5 + curveMid * 0.25).clamp(0.1, 0.9),
        (1 + curveHigh * 0.25).clamp(0.5, 1.0),
      );

  /// FFmpeg `curves` control points for the three-point tone curve.
  String get curveExpression {
    final (lo, mid, hi) = curvePoints;
    return '0/${lo.toStringAsFixed(3)}'
        ' 0.5/${mid.toStringAsFixed(3)}'
        ' 1/${hi.toStringAsFixed(3)}';
  }

  /// Fold the manual sliders into a preset so preview and export share one path.
  FilterPreset merge(FilterPreset base) => FilterPreset(
        id: '${base.id}+adj',
        name: base.name,
        category: base.category,
        brightness: base.brightness + brightness * 0.35 + shadows * 0.12,
        contrast: base.contrast + contrast * 0.5 - highlights * 0.1,
        saturation: (base.saturation + saturation * 0.7).clamp(0.0, 3.0),
        temperature: (base.temperature + temperature).clamp(-1.0, 1.0),
        tint: (base.tint + tint).clamp(-1.0, 1.0),
        gamma: base.gamma,
        fade: (base.fade + fade).clamp(0.0, 1.0),
        vignette: (base.vignette + vignette).clamp(0.0, 1.0),
        hue: (base.hue + hue).clamp(-1.0, 1.0),
      );

  Adjustments copy() => Adjustments(
        brightness: brightness,
        contrast: contrast,
        saturation: saturation,
        temperature: temperature,
        tint: tint,
        sharpen: sharpen,
        vignette: vignette,
        fade: fade,
        highlights: highlights,
        shadows: shadows,
        hue: hue,
        grain: grain,
        blur: blur,
        denoise: denoise,
        curveLow: curveLow,
        curveMid: curveMid,
        curveHigh: curveHigh,
      );

  Map<String, dynamic> toJson() => {
        'b': brightness,
        'c': contrast,
        's': saturation,
        'tp': temperature,
        'tn': tint,
        'sh': sharpen,
        'vg': vignette,
        'fd': fade,
        'hl': highlights,
        'sd': shadows,
        'hu': hue,
        'gr': grain,
        'bl': blur,
        'dn': denoise,
        'c0': curveLow,
        'c1': curveMid,
        'c2': curveHigh,
      };

  factory Adjustments.fromJson(Map<String, dynamic>? j) {
    if (j == null) return Adjustments();
    double v(String k) => (j[k] as num?)?.toDouble() ?? 0;
    return Adjustments(
      brightness: v('b'),
      contrast: v('c'),
      saturation: v('s'),
      temperature: v('tp'),
      tint: v('tn'),
      sharpen: v('sh'),
      vignette: v('vg'),
      fade: v('fd'),
      highlights: v('hl'),
      shadows: v('sd'),
      hue: v('hu'),
      grain: v('gr'),
      blur: v('bl'),
      denoise: v('dn'),
      curveLow: v('c0'),
      curveMid: v('c1'),
      curveHigh: v('c2'),
    );
  }
}
