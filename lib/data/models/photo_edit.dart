import 'dart:ui';

import 'adjustments.dart';
import 'enums.dart';
import 'filter_preset.dart';
import 'layers.dart';
import 'watermark.dart';

/// How a pixelate stroke hides what is under it.
enum PixelStyle {
  mosaic('Mosaic'),
  blur('Blur');

  const PixelStyle(this.label);

  final String label;
}

/// One freehand stroke — a markup line, or a mask the pixelate and retouch
/// brushes paint through.
///
/// Points and widths are fractions of the *finished* picture (widths of its
/// shorter side), so a stroke drawn on a 300pt preview lands in the same
/// place at the same thickness in a 4000px export.
class PhotoStroke {
  PhotoStroke({
    this.color = 0xFFFF3B30,
    this.width = 0.02,
    this.erase = false,
    List<Offset>? points,
  }) : points = points ?? <Offset>[];

  int color;

  /// Stroke thickness as a fraction of the picture's shorter side.
  double width;

  /// Markup only: rubs out what earlier strokes drew instead of adding.
  bool erase;

  final List<Offset> points;

  bool get isEmpty => points.isEmpty;

  PhotoStroke copy() => PhotoStroke(
    color: color,
    width: width,
    erase: erase,
    points: List<Offset>.of(points),
  );
}

/// A picture laid over the photo — what the PIP tool adds.
///
/// It carries the same [LayerTransform] a caption or a sticker does, so the
/// stage drags, pinches and turns all three with one piece of code, and the
/// renderer paints them in one pass.
class PhotoImageLayer {
  PhotoImageLayer({required this.path, LayerTransform? transform})
    : id = 'pip_${DateTime.now().microsecondsSinceEpoch}',
      transform = transform ?? LayerTransform();

  final String id;

  /// Where the picture lives on disk.
  final String path;

  final LayerTransform transform;

  /// Rounded corners, 0..1 of the shorter side.
  double corner = 0;

  PhotoImageLayer copy() {
    final out = PhotoImageLayer(path: path, transform: transform.copy())
      ..corner = corner;
    return out;
  }
}

/// The portrait pass: soften skin, lift it, even it out and put the detail
/// back. Every slider is 0..1 and every one of them is off by default.
///
/// Nothing here touches the picture outside the skin the mask found, which is
/// what separates it from the Adjust panel's global sliders.
class FaceEnhance {
  FaceEnhance({
    this.smooth = 0,
    this.brighten = 0,
    this.evenTone = 0,
    this.clarity = 0,
  });

  double smooth;
  double brighten;
  double evenTone;
  double clarity;

  bool get isNeutral =>
      smooth <= 0 && brighten <= 0 && evenTone <= 0 && clarity <= 0;

  /// The one-tap setting: a visible clean-up that still looks like the person
  /// who was photographed.
  void auto() {
    smooth = 0.55;
    brighten = 0.3;
    evenTone = 0.4;
    clarity = 0.25;
  }

  void reset() => smooth = brighten = evenTone = clarity = 0;

  FaceEnhance copy() => FaceEnhance(
    smooth: smooth,
    brighten: brighten,
    evenTone: evenTone,
    clarity: clarity,
  );
}

/// Everything one photo edit holds: how the picture is framed, how it is
/// graded, and what is laid over it.
///
/// The geometry is stored as fractions rather than pixels so the same edit
/// describes the 300pt preview on screen and the full-resolution PNG that
/// gets written out — the picture the user approves is the picture that
/// lands in the gallery.
class PhotoEdit {
  PhotoEdit();

  // ------------------------------------------------------------------ grade
  String filterId = 'none';
  double filterIntensity = 1;
  Adjustments adjustments = Adjustments();

  // --------------------------------------------------------------- geometry
  /// Crop insets as fractions of the *displayed* picture — that is, after the
  /// quarter turns and the mirrors have been applied.
  double cropLeft = 0;
  double cropTop = 0;
  double cropRight = 0;
  double cropBottom = 0;

  /// Clockwise quarter turns, 0..3.
  int quarterTurns = 0;
  bool flipH = false;
  bool flipV = false;

  /// The locked crop ratio (width / height), or null while the crop is free.
  double? cropAspect;

  /// Which ratio chip is lit. Kept here so undo restores the row too.
  String cropRatioId = 'free';

  // ------------------------------------------------------------------ skin
  /// The portrait pass, painted through a skin mask by the renderer.
  FaceEnhance face = FaceEnhance();

  // ----------------------------------------------------------------- brushes
  /// Freehand ink, drawn over the finished picture.
  final List<PhotoStroke> markup = [];

  /// The mask the mosaic paints through, and how coarse it is.
  final List<PhotoStroke> pixelate = [];
  PixelStyle pixelStyle = PixelStyle.mosaic;
  double pixelSize = 0.45;

  /// The mask the healing brush paints through, and how hard it softens.
  final List<PhotoStroke> retouch = [];
  double retouchStrength = 0.6;

  // ---------------------------------------------------------------- overlays
  /// Text and stickers laid over the picture. They are the video editor's own
  /// layer types with the timing left at zero, so the two editors draw a
  /// caption or an emoji with exactly the same code.
  final List<TextLayer> texts = [];
  final List<StickerLayer> stickers = [];

  /// The creator's mark, burned into the saved file.
  Watermark watermark = Watermark();

  /// Pictures laid over this one, each dragged, pinched and turned like any
  /// other overlay. The PIP tool's whole output.
  final List<PhotoImageLayer> pips = [];

  // ------------------------------------------------------------------ canvas
  /// The shape of the finished picture. Null keeps the photo's own, which is
  /// what every edit that never opens Canvas wants.
  double? canvasAspect;

  /// Which ratio chip is lit, so undo restores the row as well as the shape.
  String canvasRatioId = 'original';

  /// What fills the canvas either side of a letterboxed photo.
  int canvasBackground = 0xFFFFFFFF;

  /// A blurred copy of the photo behind it instead of a flat colour — the
  /// backdrop a square crop of a tall photo usually wants.
  bool canvasBlurBackdrop = false;

  // ------------------------------------------------------------------ effect
  /// An effect preset over the finished picture: grain, a light leak, a
  /// vignette. Separate from [filterId] because they stack.
  String effectId = 'none';
  double effectIntensity = 0.7;

  // ----------------------------------------------------------------- enhance
  /// The one-tap pass: a little contrast, a little colour, a little
  /// sharpening. It is the same tone the video editor's Enhance applies, so
  /// a photo and a clip come out of it looking alike.
  bool enhance = false;

  // ------------------------------------------------------------------ cutout
  /// The subject mask the Cutout tool baked, as a greyscale PNG the renderer
  /// merges. Null until the pass has run.
  String? cutoutMattePath;

  /// Whether the cut is showing. Baking it and turning it off is cheaper than
  /// baking it twice.
  bool cutoutOn = false;

  // -------------------------------------------------------------------- mask
  /// A shape the picture is shown through. Off by default.
  MaskShape maskShape = MaskShape.none;
  double maskSize = 0.7;
  double maskFeather = 0.1;
  double maskX = 0.5;
  double maskY = 0.5;
  double maskRotation = 0;
  bool maskInverted = false;

  // ----------------------------------------------------------------- reshape
  /// Face and body shaping, applied through the same skin mask the portrait
  /// pass uses. Each is -1..1 and each is off at zero.
  double reshapeSlim = 0;
  double reshapeEyes = 0;
  double reshapeSmooth = 0;

  /// The chosen look at the chosen strength.
  FilterPreset get filter =>
      FilterPreset.fromId(filterId).lerpFromIdentity(filterIntensity);

  /// The look with the manual sliders folded in — the one grade the renderer
  /// paints, exactly as a clip does in the video editor.
  FilterPreset get grade => adjustments.merge(filter);

  double get cropWidth => (1 - cropLeft - cropRight).clamp(0.02, 1.0);

  double get cropHeight => (1 - cropTop - cropBottom).clamp(0.02, 1.0);

  bool get hasCrop =>
      cropLeft > 0 || cropTop > 0 || cropRight > 0 || cropBottom > 0;

  /// The cut is only showing when the pass has actually left a matte.
  bool get hasCutout => cutoutOn && cutoutMattePath != null;

  bool get hasMask => maskShape != MaskShape.none;

  bool get hasReshape =>
      reshapeSlim != 0 || reshapeEyes != 0 || reshapeSmooth != 0;

  /// The grade with Enhance folded in, which is the one the renderer paints.
  ///
  /// Enhance is a tone rather than a look: it rides on top of whatever filter
  /// is chosen instead of replacing it.
  FilterPreset get gradedFilter {
    if (!enhance) return grade;
    final g = grade;
    return FilterPreset(
      id: g.id,
      name: g.name,
      category: g.category,
      brightness: g.brightness,
      contrast: g.contrast * (1 + kEnhanceContrast),
      saturation: g.saturation * (1 + kEnhanceSaturation),
      temperature: g.temperature,
      tint: g.tint,
      gamma: g.gamma * kEnhanceGamma,
      fade: g.fade,
      vignette: g.vignette,
      hue: g.hue,
    );
  }

  /// The tone one tap of Enhance adds. The same numbers the video editor
  /// uses, so a photo and a clip come out of it looking alike.
  static const double kEnhanceContrast = 0.06;
  static const double kEnhanceSaturation = 0.06;
  static const double kEnhanceGamma = 1.02;
  static const double kEnhanceSharpen = 0.6;

  bool get isClean =>
      !hasCrop &&
      quarterTurns == 0 &&
      !flipH &&
      !flipV &&
      filterId == 'none' &&
      adjustments.isNeutral &&
      face.isNeutral &&
      markup.isEmpty &&
      pixelate.isEmpty &&
      retouch.isEmpty &&
      texts.isEmpty &&
      stickers.isEmpty &&
      !watermark.isReady &&
      pips.isEmpty &&
      canvasAspect == null &&
      effectId == 'none' &&
      !enhance &&
      !cutoutOn &&
      !hasMask &&
      !hasReshape;

  /// Every overlay the stage can select, back to front — the order the
  /// renderer paints them in.
  List<Object> get overlays => [
    ...pips,
    ...stickers,
    ...texts,
    if (watermark.isReady) watermark,
  ];

  /// The overlay carrying [id], or null once it has been deleted.
  Object? overlayById(String? id) {
    if (id == null) return null;
    if (id == 'watermark') return watermark.isReady ? watermark : null;
    for (final s in stickers) {
      if (s.id == id) return s;
    }
    for (final t in texts) {
      if (t.id == id) return t;
    }
    for (final p in pips) {
      if (p.id == id) return p;
    }
    return null;
  }

  void removeOverlay(String id) {
    stickers.removeWhere((s) => s.id == id);
    texts.removeWhere((t) => t.id == id);
    pips.removeWhere((p) => p.id == id);
    if (id == 'watermark') watermark.enabled = false;
  }

  void setCrop(double left, double top, double right, double bottom) {
    cropLeft = left.clamp(0.0, 0.98);
    cropTop = top.clamp(0.0, 0.98);
    cropRight = right.clamp(0.0, 0.98);
    cropBottom = bottom.clamp(0.0, 0.98);
  }

  void resetCrop() {
    cropLeft = cropTop = cropRight = cropBottom = 0;
    cropAspect = null;
    cropRatioId = 'free';
  }

  void reset() {
    resetCrop();
    quarterTurns = 0;
    flipH = flipV = false;
    filterId = 'none';
    filterIntensity = 1;
    adjustments.reset();
    face.reset();
    markup.clear();
    pixelate.clear();
    retouch.clear();
    texts.clear();
    stickers.clear();
    watermark = Watermark();
  }

  /// Turns the picture a quarter turn and carries the crop window with it, so
  /// the framing the user chose keeps the same content rather than jumping to
  /// a different part of the photo.
  void rotate({bool clockwise = true}) {
    final l = cropLeft, t = cropTop, r = cropRight, b = cropBottom;
    if (clockwise) {
      quarterTurns = (quarterTurns + 1) % 4;
      setCrop(b, l, t, r);
    } else {
      quarterTurns = (quarterTurns + 3) % 4;
      setCrop(t, r, b, l);
    }
    final a = cropAspect;
    if (a != null && a > 0) cropAspect = 1 / a;
  }

  /// Mirrors the picture, taking the crop window along for the same reason.
  void mirror({required bool horizontal}) {
    if (horizontal) {
      flipH = !flipH;
      setCrop(cropRight, cropTop, cropLeft, cropBottom);
    } else {
      flipV = !flipV;
      setCrop(cropLeft, cropBottom, cropRight, cropTop);
    }
  }

  PhotoEdit copy() => PhotoEdit()
    ..filterId = filterId
    ..filterIntensity = filterIntensity
    ..adjustments = adjustments.copy()
    ..cropLeft = cropLeft
    ..cropTop = cropTop
    ..cropRight = cropRight
    ..cropBottom = cropBottom
    ..quarterTurns = quarterTurns
    ..flipH = flipH
    ..flipV = flipV
    ..cropAspect = cropAspect
    ..cropRatioId = cropRatioId
    ..face = face.copy()
    ..pixelStyle = pixelStyle
    ..pixelSize = pixelSize
    ..retouchStrength = retouchStrength
    ..watermark = watermark.copy()
    ..canvasAspect = canvasAspect
    ..canvasRatioId = canvasRatioId
    ..canvasBackground = canvasBackground
    ..canvasBlurBackdrop = canvasBlurBackdrop
    ..effectId = effectId
    ..effectIntensity = effectIntensity
    ..enhance = enhance
    ..cutoutMattePath = cutoutMattePath
    ..cutoutOn = cutoutOn
    ..maskShape = maskShape
    ..maskSize = maskSize
    ..maskFeather = maskFeather
    ..maskX = maskX
    ..maskY = maskY
    ..maskRotation = maskRotation
    ..maskInverted = maskInverted
    ..reshapeSlim = reshapeSlim
    ..reshapeEyes = reshapeEyes
    ..reshapeSmooth = reshapeSmooth
    // The layer ids survive the copy: the stage tracks its selection by id,
    // so an undo has to hand back the same overlay rather than a twin of it.
    ..markup.addAll([for (final s in markup) s.copy()])
    ..pixelate.addAll([for (final s in pixelate) s.copy()])
    ..retouch.addAll([for (final s in retouch) s.copy()])
    ..texts.addAll([for (final t in texts) TextLayer.fromJson(t.toJson())])
    ..stickers.addAll([
      for (final s in stickers) StickerLayer.fromJson(s.toJson()),
    ])
    ..pips.addAll([for (final p in pips) p.copy()]);
}

/// One entry in the crop ratio row. A null [value] leaves the rectangle free;
/// [original] resolves to whatever the photo itself is.
class CropRatio {
  const CropRatio(this.id, this.label, this.value, {this.original = false});

  final String id;
  final String label;
  final double? value;
  final bool original;

  static const List<CropRatio> all = [
    CropRatio('free', 'Free', null),
    CropRatio('original', 'Original', null, original: true),
    CropRatio('1:1', '1:1', 1),
    CropRatio('4:5', '4:5', 4 / 5),
    CropRatio('3:4', '3:4', 3 / 4),
    CropRatio('2:3', '2:3', 2 / 3),
    CropRatio('9:16', '9:16', 9 / 16),
    CropRatio('5:4', '5:4', 5 / 4),
    CropRatio('4:3', '4:3', 4 / 3),
    CropRatio('3:2', '3:2', 3 / 2),
    CropRatio('16:9', '16:9', 16 / 9),
    CropRatio('2.35:1', '2.35:1', 2.35),
  ];
}
