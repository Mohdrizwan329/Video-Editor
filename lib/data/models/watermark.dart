import 'layers.dart';

/// Which of the two marks the user picked.
///
/// A project carries exactly one watermark and it is *either* text *or* an
/// image — never both — so the two field groups below live side by side and
/// [Watermark.type] alone decides which one is drawn.
enum WatermarkType {
  text('Text'),
  image('Logo');

  const WatermarkType(this.label);

  final String label;

  static WatermarkType fromName(String? n) =>
      values.firstWhere((e) => e.name == n, orElse: () => text);
}

/// The nine placement presets offered by the panel. Dragging the mark on the
/// canvas afterwards writes straight to the transform, so this is a shortcut
/// rather than stored state.
enum WatermarkAnchor {
  topLeft('Top left', 0.16, 0.10),
  topCenter('Top', 0.5, 0.10),
  topRight('Top right', 0.84, 0.10),
  centerLeft('Left', 0.16, 0.5),
  center('Centre', 0.5, 0.5),
  centerRight('Right', 0.84, 0.5),
  bottomLeft('Bottom left', 0.16, 0.90),
  bottomCenter('Bottom', 0.5, 0.90),
  bottomRight('Bottom right', 0.84, 0.90);

  const WatermarkAnchor(this.label, this.x, this.y);

  final String label;
  final double x;
  final double y;
}

/// The creator's own branding, burned over the entire video.
///
/// Unlike a [TextLayer] this is not a timeline item: it has no start or
/// duration because it covers the whole export, and it is never selectable
/// from a lane. Geometry is authored against the same virtual canvas every
/// other overlay uses, so the preview and the render agree at any resolution.
class Watermark {
  Watermark({
    this.enabled = false,
    this.type = WatermarkType.text,
    this.text = 'Your brand',
    this.fontFamily = 'Poppins',
    this.fontSize = 46,
    this.color = 0xFFFFFFFF,
    this.bold = true,
    this.italic = false,
    this.strokeWidth = 0,
    this.strokeColor = 0xFF000000,
    this.shadowBlur = 8,
    this.shadowColor = 0xB3000000,
    this.backgroundColor = 0x00000000,
    this.backgroundRadius = 10,
    this.backgroundPadding = 14,
    this.imagePath,
    this.imageSize = 180,
    LayerTransform? transform,
  }) : transform = transform ??
            LayerTransform(x: 0.84, y: 0.90, opacity: 0.75);

  bool enabled;
  WatermarkType type;

  // --- text mark
  String text;
  String fontFamily;
  double fontSize;
  int color;
  bool bold;
  bool italic;
  double strokeWidth;
  int strokeColor;
  double shadowBlur;
  int shadowColor;
  int backgroundColor;
  double backgroundRadius;
  double backgroundPadding;

  // --- image mark
  /// Absolute path to a copy of the user's logo kept in app storage.
  String? imagePath;

  /// Width of the logo on the reference canvas, before [transform].scale.
  double imageSize;

  /// Position, scale, rotation and opacity on the canvas.
  LayerTransform transform;

  /// Whether there is actually something to draw. An enabled mark with an
  /// empty caption or a logo the user never picked renders nothing.
  bool get isReady {
    if (!enabled) return false;
    return switch (type) {
      WatermarkType.text => text.trim().isNotEmpty,
      WatermarkType.image => (imagePath ?? '').isNotEmpty,
    };
  }

  /// Adapts the text mark to the [TextLayer] the preview widget and the
  /// rasterizer already know how to draw, so both paths stay pixel-identical
  /// to a hand-placed text layer without duplicating any painting code.
  ///
  /// The transform is shared, not copied, so a drag on the canvas lands on
  /// this watermark.
  TextLayer asTextLayer() => TextLayer(
        id: 'watermark',
        start: Duration.zero,
        duration: const Duration(hours: 6),
        text: text,
        fontFamily: fontFamily,
        fontSize: fontSize,
        color: color,
        bold: bold,
        italic: italic,
        strokeWidth: strokeWidth,
        strokeColor: strokeColor,
        shadowBlur: shadowBlur,
        shadowColor: shadowColor,
        backgroundColor: backgroundColor,
        backgroundRadius: backgroundRadius,
        backgroundPadding: backgroundPadding,
        transform: transform,
      );

  void applyAnchor(WatermarkAnchor a) {
    transform.x = a.x;
    transform.y = a.y;
  }

  /// The preset whose position matches the current transform, or null once
  /// the user has dragged the mark somewhere of their own.
  WatermarkAnchor? get anchor {
    for (final a in WatermarkAnchor.values) {
      if ((transform.x - a.x).abs() < 0.005 &&
          (transform.y - a.y).abs() < 0.005) {
        return a;
      }
    }
    return null;
  }

  Watermark copy() => Watermark.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'on': enabled,
        'type': type.name,
        'text': text,
        'font': fontFamily,
        'size': fontSize,
        'color': color,
        'bold': bold,
        'italic': italic,
        'sw': strokeWidth,
        'sc': strokeColor,
        'sb': shadowBlur,
        'shc': shadowColor,
        'bg': backgroundColor,
        'bgr': backgroundRadius,
        'bgp': backgroundPadding,
        'img': imagePath,
        'imgs': imageSize,
        'tf': transform.toJson(),
      };

  factory Watermark.fromJson(Map<String, dynamic>? j) {
    if (j == null) return Watermark();
    double v(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
    int c(String k, int f) => (j[k] as num?)?.toInt() ?? f;
    return Watermark(
      enabled: j['on'] as bool? ?? false,
      type: WatermarkType.fromName(j['type'] as String?),
      text: j['text'] as String? ?? 'Your brand',
      fontFamily: j['font'] as String? ?? 'Poppins',
      fontSize: v('size', 46),
      color: c('color', 0xFFFFFFFF),
      bold: j['bold'] as bool? ?? true,
      italic: j['italic'] as bool? ?? false,
      strokeWidth: v('sw', 0),
      strokeColor: c('sc', 0xFF000000),
      shadowBlur: v('sb', 8),
      shadowColor: c('shc', 0xB3000000),
      backgroundColor: c('bg', 0x00000000),
      backgroundRadius: v('bgr', 10),
      backgroundPadding: v('bgp', 14),
      imagePath: j['img'] as String?,
      imageSize: v('imgs', 180),
      // A project saved before watermarks existed has no transform; letting
      // it stay null keeps the bottom-right default instead of centring.
      transform: j['tf'] == null
          ? null
          : LayerTransform.fromJson(j['tf'] as Map<String, dynamic>),
    );
  }
}
