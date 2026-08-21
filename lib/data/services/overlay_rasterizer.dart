import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/constants.dart';
import '../models/layers.dart';
import '../models/video_effect.dart';
import 'effect_painter.dart';
import '../models/watermark.dart';

/// Result of baking one overlay into a PNG for the renderer.
class RasterizedLayer {
  RasterizedLayer({
    required this.path,
    required this.width,
    required this.height,
    required this.centerX,
    required this.centerY,
  });

  final String path;
  final int width;
  final int height;

  /// Centre of the layer in output-pixel coordinates.
  final double centerX;
  final double centerY;

  /// Top-left position FFmpeg's `overlay` filter expects.
  int get x => (centerX - width / 2).round();
  int get y => (centerY - height / 2).round();
}

/// Bakes text and sticker layers into transparent PNGs at output resolution.
///
/// The preview draws these layers with Flutter; baking them with the very same
/// painting code is what keeps the render identical to what the user saw.
class OverlayRasterizer {
  OverlayRasterizer._();

  static final OverlayRasterizer instance = OverlayRasterizer._();

  Future<Directory> _dir() async {
    final base = await getTemporaryDirectory();
    final d = Directory('${base.path}/sve_overlays');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// [opacity] is baked into the PNG rather than left to the filter graph.
  /// The preview draws the layer inside an [Opacity], so folding the same
  /// factor into the alpha channel here is what keeps the two in step —
  /// and it costs nothing at render time, unlike a per-frame `geq`.
  Future<RasterizedLayer?> rasterizeText(
    TextLayer layer, {
    required int outWidth,
    required int outHeight,
    double opacity = 1.0,
  }) async {
    final scale = outHeight / kCanvasReferenceHeight;
    // Measure once to size the gradient, then build the real painter.
    final measure = buildTextPainter(layer, scale * layer.transform.scale)
      ..layout(maxWidth: outWidth * 1.6);
    final painter = buildTextPainter(
      layer,
      scale * layer.transform.scale,
      gradientBounds: Size(measure.width, measure.height),
    )..layout(maxWidth: outWidth * 1.6);

    final pad = layer.backgroundPadding * scale * layer.transform.scale;
    final hasBg = (layer.backgroundColor >> 24) != 0;
    final stroke = layer.strokeWidth * scale * layer.transform.scale;
    final blur = layer.shadowBlur * scale;
    final margin = math.max(stroke * 2 + blur * 2 + 8, 12.0);

    final contentW = painter.width + (hasBg ? pad * 2 : 0);
    final contentH = painter.height + (hasBg ? pad * 2 : 0);
    final rot = layer.transform.rotation;

    // Rotate around the centre, so the canvas must fit the rotated bounds.
    final cos = math.cos(rot).abs(), sin = math.sin(rot).abs();
    final boxW = (contentW * cos + contentH * sin) + margin * 2;
    final boxH = (contentW * sin + contentH * cos) + margin * 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (opacity < 1) {
      canvas.saveLayer(Rect.fromLTWH(0, 0, boxW, boxH),
          Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)));
    }
    canvas.translate(boxW / 2, boxH / 2);
    if (rot != 0) canvas.rotate(rot);

    if (hasBg) {
      final rect = Rect.fromCenter(
          center: Offset.zero, width: contentW, height: contentH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            rect, Radius.circular(layer.backgroundRadius * scale)),
        Paint()..color = Color(layer.backgroundColor),
      );
    }

    final origin = Offset(-painter.width / 2, -painter.height / 2);
    if (stroke > 0) {
      final strokePainter = buildTextPainter(
        layer,
        scale * layer.transform.scale,
        strokeOnly: true,
      )..layout(maxWidth: outWidth * 1.6);
      strokePainter.paint(canvas, origin);
    }
    painter.paint(canvas, origin);
    if (opacity < 1) canvas.restore();

    final picture = recorder.endRecording();
    return _writePng(picture, boxW.ceil(), boxH.ceil(), layer.transform,
        outWidth, outHeight, 'text_${layer.id}');
  }

  Future<RasterizedLayer?> rasterizeSticker(
    StickerLayer layer, {
    required int outWidth,
    required int outHeight,
  }) async {
    final scale = outHeight / kCanvasReferenceHeight * layer.transform.scale;
    final size = layer.size * scale;
    final rot = layer.transform.rotation;
    final cos = math.cos(rot).abs(), sin = math.sin(rot).abs();
    final boxW = size * cos + size * sin + 8;
    final boxH = size * sin + size * cos + 8;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(boxW / 2, boxH / 2);
    if (rot != 0) canvas.rotate(rot);

    if (layer.isEmoji) {
      final tp = TextPainter(
        text: TextSpan(
          text: layer.content,
          style: TextStyle(fontSize: size * 0.86, color: Color(layer.color)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    } else {
      paintShape(canvas, layer.content, size, Color(layer.color));
    }

    final picture = recorder.endRecording();
    return _writePng(picture, boxW.ceil(), boxH.ceil(), layer.transform,
        outWidth, outHeight, 'sticker_${layer.id}');
  }

  /// Bakes the project's design frame at full output size. It covers the whole
  /// canvas, so it lands at 0,0 and the renderer only has to composite it.
  Future<RasterizedLayer?> rasterizeFrame(
    FramePreset preset, {
    required int outWidth,
    required int outHeight,
  }) {
    if (preset.isNone) return Future.value(null);
    return _rasterizeFullCanvas(
      'frame_${preset.id}',
      outWidth,
      outHeight,
      (canvas, size) => EffectPainter.paintFrame(canvas, size, preset),
    );
  }

  /// Bakes the project's FX texture at full output size. [intensity] is folded
  /// into the pattern's alpha here, exactly as the preview folds it in.
  Future<RasterizedLayer?> rasterizeFx(
    FxPreset preset,
    double intensity, {
    required int outWidth,
    required int outHeight,
  }) {
    if (preset.isNone || intensity <= 0) return Future.value(null);
    return _rasterizeFullCanvas(
      'fx_${preset.id}',
      outWidth,
      outHeight,
      (canvas, size) => EffectPainter.paintFx(canvas, size, preset, intensity),
    );
  }

  Future<RasterizedLayer?> _rasterizeFullCanvas(
    String name,
    int outWidth,
    int outHeight,
    void Function(Canvas, Size) paint,
  ) async {
    if (outWidth <= 0 || outHeight <= 0) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    paint(canvas, Size(outWidth.toDouble(), outHeight.toDouble()));
    return _writePng(recorder.endRecording(), outWidth, outHeight,
        LayerTransform(), outWidth, outHeight, name);
  }

  /// Bakes an image watermark: the user's logo scaled to its canvas size,
  /// rotated, and faded to the mark's opacity. Going through a PNG rather
  /// than feeding the original file to FFmpeg means the geometry maths lives
  /// in exactly one place and matches what the preview drew.
  Future<RasterizedLayer?> rasterizeWatermarkImage(
    Watermark mark, {
    required int outWidth,
    required int outHeight,
  }) async {
    final path = mark.imagePath;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;

    final ui.Image src;
    try {
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      src = (await codec.getNextFrame()).image;
      codec.dispose();
    } catch (_) {
      return null;
    }
    if (src.width <= 0 || src.height <= 0) {
      src.dispose();
      return null;
    }

    final scale = outHeight / kCanvasReferenceHeight * mark.transform.scale;
    final drawW = mark.imageSize * scale;
    final drawH = drawW * src.height / src.width;
    final rot = mark.transform.rotation;
    final cos = math.cos(rot).abs(), sin = math.sin(rot).abs();
    final boxW = drawW * cos + drawH * sin + 4;
    final boxH = drawW * sin + drawH * cos + 4;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final opacity = mark.transform.opacity.clamp(0.0, 1.0);
    canvas.translate(boxW / 2, boxH / 2);
    if (rot != 0) canvas.rotate(rot);
    canvas.drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: drawW, height: drawH),
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high
        ..color = Color.fromRGBO(0, 0, 0, opacity),
    );
    src.dispose();

    final picture = recorder.endRecording();
    return _writePng(picture, boxW.ceil(), boxH.ceil(), mark.transform,
        outWidth, outHeight, 'watermark');
  }

  Future<RasterizedLayer?> _writePng(
    ui.Picture picture,
    int w,
    int h,
    LayerTransform transform,
    int outWidth,
    int outHeight,
    String name,
  ) async {
    if (w <= 0 || h <= 0) return null;
    final image = await picture.toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (bytes == null) return null;
    final dir = await _dir();
    final file = File('${dir.path}/$name.png');
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return RasterizedLayer(
      path: file.path,
      width: w,
      height: h,
      centerX: transform.x * outWidth,
      centerY: transform.y * outHeight,
    );
  }

  /// Shared by the preview widget and the renderer so both draw the same glyph.
  static TextPainter buildTextPainter(
    TextLayer layer,
    double scale, {
    bool strokeOnly = false,
    Size? gradientBounds,
  }) {
    // A gradient fill has to be a shader on the foreground paint; the flat
    // case stays a plain colour so text stays cheap to lay out.
    Paint? fill;
    if (!strokeOnly && layer.gradientColor != null) {
      final box = gradientBounds ?? const Size(400, 120);
      fill = Paint()
        ..shader = LinearGradient(
          colors: [Color(layer.color), Color(layer.gradientColor!)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, box.width, box.height));
    }
    final style = TextStyle(
      fontFamily: layer.fontFamily,
      fontSize: layer.fontSize * scale,
      fontWeight: layer.bold ? FontWeight.w800 : FontWeight.w500,
      fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
      decoration:
          layer.underline ? TextDecoration.underline : TextDecoration.none,
      decorationColor: Color(layer.color),
      letterSpacing: layer.letterSpacing * scale,
      height: layer.lineHeight,
      color: (strokeOnly || fill != null) ? null : Color(layer.color),
      foreground: strokeOnly
          ? (Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = layer.strokeWidth * scale * 2
            ..strokeJoin = StrokeJoin.round
            ..color = Color(layer.strokeColor))
          : fill,
      shadows: layer.shadowBlur > 0 && !strokeOnly
          ? [
              Shadow(
                color: Color(layer.shadowColor),
                blurRadius: layer.shadowBlur * scale,
                offset: Offset(
                    layer.shadowOffsetX * scale, layer.shadowOffsetY * scale),
              )
            ]
          : null,
    );
    return TextPainter(
      text: TextSpan(text: layer.text, style: style),
      textAlign: layer.align,
      textDirection: TextDirection.ltr,
      maxLines: null,
    );
  }

  /// Vector sticker shapes — kept in one place so preview and export agree.
  static void paintShape(Canvas canvas, String key, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final r = size / 2;
    switch (key) {
      case 'circle':
        canvas.drawCircle(Offset.zero, r, paint);
      case 'ring':
        canvas.drawCircle(
            Offset.zero,
            r - size * 0.08,
            paint
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.14);
      case 'square':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: size, height: size),
              Radius.circular(size * 0.1)),
          paint,
        );
      case 'triangle':
        final p = Path()
          ..moveTo(0, -r)
          ..lineTo(r, r)
          ..lineTo(-r, r)
          ..close();
        canvas.drawPath(p, paint);
      case 'star':
        canvas.drawPath(_starPath(r), paint);
      case 'heart':
        canvas.drawPath(_heartPath(r), paint);
      case 'arrow':
        final p = Path()
          ..moveTo(-r, -r * 0.3)
          ..lineTo(r * 0.2, -r * 0.3)
          ..lineTo(r * 0.2, -r * 0.8)
          ..lineTo(r, 0)
          ..lineTo(r * 0.2, r * 0.8)
          ..lineTo(r * 0.2, r * 0.3)
          ..lineTo(-r, r * 0.3)
          ..close();
        canvas.drawPath(p, paint);
      case 'bubble':
        final rect = Rect.fromCenter(
            center: Offset(0, -r * 0.15), width: size, height: size * 0.7);
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(size * 0.2)), paint);
        final tail = Path()
          ..moveTo(-r * 0.15, r * 0.2)
          ..lineTo(-r * 0.05, r * 0.7)
          ..lineTo(r * 0.3, r * 0.2)
          ..close();
        canvas.drawPath(tail, paint);
      default:
        canvas.drawCircle(Offset.zero, r, paint);
    }
  }

  static Path _starPath(double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.45;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  static Path _heartPath(double r) {
    final path = Path()..moveTo(0, r * 0.72);
    path.cubicTo(-r * 1.5, -r * 0.2, -r * 0.55, -r * 1.15, 0, -r * 0.35);
    path.cubicTo(r * 0.55, -r * 1.15, r * 1.5, -r * 0.2, 0, r * 0.72);
    return path..close();
  }

  Future<void> clear() async {
    final d = await _dir();
    if (await d.exists()) await d.delete(recursive: true);
  }
}

/// Small helper so callers can request bytes without touching files.
Future<Uint8List?> pictureToPng(ui.Picture picture, int w, int h) async {
  final image = await picture.toImage(w, h);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes?.buffer.asUint8List();
}
