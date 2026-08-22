import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';

import '../../../core/utils/constants.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/layers.dart';
import '../../../data/models/keyframe.dart';
import '../../../data/models/watermark.dart';
import '../../../data/services/overlay_rasterizer.dart';
import 'chroma_box.dart';
import 'grade_extras_box.dart';
import 'clip_view.dart';
import 'mask_box.dart';

/// Animation state a layer is in at a given moment.
class _AnimState {
  const _AnimState({
    this.opacity = 1,
    this.offset = Offset.zero,
    this.scale = 1,
    this.scaleX = 1,
    this.scaleY = 1,
    this.rotation = 0,
    this.blur = 0,
    this.visibleCharacters = -1,
    this.glow = 0,
  });

  final double opacity;

  /// Normalised canvas offset added to the layer's position.
  final Offset offset;
  final double scale;

  /// Non-uniform scale, used by stretch and squeeze.
  final double scaleX;
  final double scaleY;
  final double rotation;
  final double blur;

  /// -1 means "all characters"; used by the reveal animations.
  final int visibleCharacters;

  /// Extra shadow strength for the neon animation.
  final double glow;

  _AnimState merge(_AnimState other) => _AnimState(
        opacity: math.min(opacity, other.opacity),
        offset: offset + other.offset,
        scale: scale * other.scale,
        scaleX: scaleX * other.scaleX,
        scaleY: scaleY * other.scaleY,
        rotation: rotation + other.rotation,
        blur: math.max(blur, other.blur),
        visibleCharacters:
            other.visibleCharacters >= 0 ? other.visibleCharacters : visibleCharacters,
        glow: math.max(glow, other.glow),
      );
}

/// One edge of an animation, evaluated with progress 0 (fully animated away)
/// to 1 (fully settled).
_AnimState _edge(LayerAnimation a, double p, bool entering, int textLength) {
  final eased = entering
      ? Curves.easeOutCubic.transform(p)
      : Curves.easeInCubic.transform(p);
  final away = 1 - eased;
  final dir = entering ? 1.0 : -1.0;

  return switch (a) {
    LayerAnimation.none => const _AnimState(),
    LayerAnimation.fade => _AnimState(opacity: eased),
    LayerAnimation.dissolve => _AnimState(opacity: eased * eased),
    LayerAnimation.fadeBlur => _AnimState(opacity: eased, blur: away * 12),

    LayerAnimation.slideUp =>
      _AnimState(opacity: eased, offset: Offset(0, away * 0.25 * dir)),
    LayerAnimation.slideDown =>
      _AnimState(opacity: eased, offset: Offset(0, -away * 0.25 * dir)),
    LayerAnimation.slideLeft =>
      _AnimState(opacity: eased, offset: Offset(away * 0.35 * dir, 0)),
    LayerAnimation.slideRight =>
      _AnimState(opacity: eased, offset: Offset(-away * 0.35 * dir, 0)),
    LayerAnimation.driftUp => _AnimState(offset: Offset(0, away * 0.06 * dir)),
    LayerAnimation.driftDown => _AnimState(offset: Offset(0, -away * 0.06 * dir)),
    LayerAnimation.swipeIn => _AnimState(
        opacity: eased, offset: Offset(away * 0.6 * dir, 0), scale: 0.9 + 0.1 * eased),
    LayerAnimation.flyIn => _AnimState(
        opacity: eased,
        offset: Offset(away * 0.5 * dir, away * 0.3 * dir),
        scale: 0.5 + 0.5 * eased),

    LayerAnimation.scale => _AnimState(opacity: eased, scale: 0.6 + 0.4 * eased),
    LayerAnimation.scaleDown => _AnimState(opacity: eased, scale: 1.5 - 0.5 * eased),
    LayerAnimation.pop => _AnimState(
        opacity: p > 0.02 ? 1 : 0,
        scale: entering ? Curves.elasticOut.transform(p) : 0.4 + 0.6 * eased),
    LayerAnimation.bounce => _AnimState(
        opacity: eased,
        offset: Offset(0, -(entering ? Curves.bounceOut.transform(p) - 1 : away) * 0.2)),
    LayerAnimation.zoomBlur =>
      _AnimState(opacity: eased, scale: 1 + away * 0.8, blur: away * 14),
    LayerAnimation.stretch => _AnimState(opacity: eased, scaleX: 0.2 + 0.8 * eased),
    LayerAnimation.squeeze => _AnimState(opacity: eased, scaleY: 0.2 + 0.8 * eased),

    LayerAnimation.spin =>
      _AnimState(opacity: eased, rotation: away * math.pi * dir),
    LayerAnimation.spinFast =>
      _AnimState(opacity: eased, rotation: away * math.pi * 3 * dir),
    LayerAnimation.swing =>
      _AnimState(opacity: eased, rotation: math.sin(away * math.pi * 3) * 0.35),
    LayerAnimation.flip => _AnimState(opacity: eased, scaleX: math.cos(away * math.pi)),
    LayerAnimation.tilt =>
      _AnimState(opacity: eased, rotation: away * 0.4 * dir, scale: 0.85 + 0.15 * eased),

    LayerAnimation.typewriter =>
      _AnimState(visibleCharacters: (textLength * p).ceil()),
    LayerAnimation.wordByWord => _AnimState(visibleCharacters: -1, opacity: eased),
    LayerAnimation.lineByLine => _AnimState(visibleCharacters: -1, opacity: eased),
    LayerAnimation.wave => _AnimState(opacity: eased),
    LayerAnimation.neon => _AnimState(opacity: eased, glow: eased),

    LayerAnimation.shake => _AnimState(opacity: eased),
    LayerAnimation.pulse => _AnimState(opacity: eased),
    LayerAnimation.blink => _AnimState(opacity: eased),
    LayerAnimation.wobble => _AnimState(opacity: eased),
  };
}

/// Animations that run for the layer's whole life rather than only its edges.
_AnimState _continuous(LayerAnimation a, double seconds) {
  return switch (a) {
    LayerAnimation.shake => _AnimState(
        offset: Offset(math.sin(seconds * 34) * 0.006,
            math.cos(seconds * 41) * 0.006)),
    LayerAnimation.pulse =>
      _AnimState(scale: 1 + math.sin(seconds * 5) * 0.06),
    LayerAnimation.blink =>
      _AnimState(opacity: (math.sin(seconds * 7) * 0.5 + 0.5).clamp(0.15, 1.0)),
    LayerAnimation.wobble =>
      _AnimState(rotation: math.sin(seconds * 4) * 0.08),
    LayerAnimation.neon =>
      _AnimState(glow: (math.sin(seconds * 6) * 0.5 + 0.5).clamp(0.3, 1.0)),
    LayerAnimation.wave =>
      _AnimState(offset: Offset(0, math.sin(seconds * 3) * 0.012)),
    _ => const _AnimState(),
  };
}

/// Resolves in/out animations plus any continuous motion into a transform
/// for the current playhead.
_AnimState _animate({
  required Duration t,
  required Duration start,
  required Duration end,
  required LayerAnimation animIn,
  required LayerAnimation animOut,
  required Duration animDuration,
  required int textLength,
}) {
  final d = animDuration.inMicroseconds.clamp(1, 1 << 40);
  final into = (t - start).inMicroseconds;
  final left = (end - t).inMicroseconds;
  final seconds = into / 1e6;

  var state = const _AnimState();

  if (animIn != LayerAnimation.none && !animIn.isContinuous && into < d) {
    state = state.merge(_edge(animIn, (into / d).clamp(0.0, 1.0), true, textLength));
  }
  if (animOut != LayerAnimation.none && !animOut.isContinuous && left < d) {
    state = state.merge(_edge(animOut, (left / d).clamp(0.0, 1.0), false, textLength));
  }
  if (animIn.isContinuous) state = state.merge(_continuous(animIn, seconds));
  if (animOut.isContinuous) state = state.merge(_continuous(animOut, seconds));

  return state;
}

/// Resolves a layer's transform for the current playhead, letting any
/// keyframe track override the static value.
LayerTransform _resolveTransform(
    Keyframable owner, LayerTransform base, Duration local) {
  if (!owner.hasKeyframes) return base;
  return LayerTransform(
    x: owner.animated(KeyframeProperty.x, local, base.x),
    y: owner.animated(KeyframeProperty.y, local, base.y),
    scale: owner.animated(KeyframeProperty.scale, local, base.scale),
    rotation: owner.animated(KeyframeProperty.rotation, local, base.rotation),
    opacity: owner.animated(KeyframeProperty.opacity, local, base.opacity),
  );
}

/// Draws a text layer on the preview canvas at the current playhead.
class TextLayerView extends StatelessWidget {
  const TextLayerView({
    super.key,
    required this.layer,
    required this.time,
    required this.canvasSize,
    this.selected = false,
    this.contentKey,
  });

  final TextLayer layer;
  final Duration time;
  final Size canvasSize;
  final bool selected;

  /// See [_Positioned.contentKey].
  final Key? contentKey;

  @override
  Widget build(BuildContext context) {
    final scale = canvasSize.height / kCanvasReferenceHeight;
    final anim = _animate(
      t: time,
      start: layer.start,
      end: layer.end,
      animIn: layer.animationIn,
      animOut: layer.animationOut,
      animDuration: layer.animationDuration,
      textLength: layer.text.length,
    );
    final shown = anim.visibleCharacters < 0
        ? layer.text
        : layer.text.substring(
            0, anim.visibleCharacters.clamp(0, layer.text.length));

    final resolved =
        _resolveTransform(layer, layer.transform, time - layer.start);
    final effective = resolved.scale * anim.scale;
    final painterStyle = _style(scale * effective, false);
    final hasBg = (layer.backgroundColor >> 24) != 0;

    Widget content = Stack(
      children: [
        if (layer.strokeWidth > 0)
          Text(shown,
              textAlign: layer.align, style: _style(scale * effective, true)),
        Text(shown, textAlign: layer.align, style: painterStyle),
      ],
    );

    // Gradient fill: paint the glyphs white, then tint through them.
    if (layer.gradientColor != null) {
      content = ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) => LinearGradient(
          colors: [Color(layer.color), Color(layer.gradientColor!)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect),
        child: content,
      );
    }

    if (hasBg) {
      content = Container(
        padding: EdgeInsets.all(layer.backgroundPadding * scale * effective),
        decoration: BoxDecoration(
          color: Color(layer.backgroundColor),
          borderRadius:
              BorderRadius.circular(layer.backgroundRadius * scale * effective),
        ),
        child: content,
      );
    }

    return _Positioned(
      transform: resolved,
      canvasSize: canvasSize,
      anim: anim,
      selected: selected,
      contentKey: contentKey,
      child: content,
    );
  }

  TextStyle _style(double scale, bool stroke) => TextStyle(
        fontFamily: layer.fontFamily,
        fontSize: layer.fontSize * scale,
        fontWeight: layer.bold ? FontWeight.w800 : FontWeight.w500,
        fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
        decoration:
            layer.underline ? TextDecoration.underline : TextDecoration.none,
        decorationColor: Color(layer.color),
        letterSpacing: layer.letterSpacing * scale,
        height: layer.lineHeight,
        color: stroke ? null : Color(layer.color),
        foreground: stroke
            ? (Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = layer.strokeWidth * scale * 2
              ..strokeJoin = StrokeJoin.round
              ..color = Color(layer.strokeColor))
            : null,
        shadows: layer.shadowBlur > 0 && !stroke
            ? [
                Shadow(
                  color: Color(layer.shadowColor),
                  blurRadius: layer.shadowBlur * scale,
                  offset: Offset(layer.shadowOffsetX * scale,
                      layer.shadowOffsetY * scale),
                )
              ]
            : null,
      );
}

/// Draws the project watermark. It is not a timeline item, so it carries no
/// playhead and no animation — it simply sits over every frame.
///
/// The text mark is handed to [TextLayerView] through [Watermark.asTextLayer],
/// which is what guarantees it looks the same as the text the exporter bakes.
class WatermarkView extends StatelessWidget {
  const WatermarkView({
    super.key,
    required this.mark,
    required this.canvasSize,
    this.focused = false,
    this.contentKey,
  });

  final Watermark mark;
  final Size canvasSize;

  /// True while the watermark panel is open, which frames the mark so the
  /// creator can see what they are dragging.
  final bool focused;

  /// Lands on the box the mark occupies, so a tap on the canvas can tell
  /// whether it landed on the mark and open the panel for it.
  final Key? contentKey;

  @override
  Widget build(BuildContext context) {
    if (!mark.isReady) return const SizedBox.shrink();

    if (mark.type == WatermarkType.text) {
      return TextLayerView(
        layer: mark.asTextLayer(),
        time: Duration.zero,
        canvasSize: canvasSize,
        selected: focused,
        contentKey: contentKey,
      );
    }

    final scale =
        canvasSize.height / kCanvasReferenceHeight * mark.transform.scale;
    return _Positioned(
      transform: mark.transform,
      canvasSize: canvasSize,
      anim: const _AnimState(),
      selected: focused,
      contentKey: contentKey,
      child: Image.file(
        File(mark.imagePath!),
        width: mark.imageSize * scale,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// Draws an emoji or vector sticker at the current playhead.
class StickerLayerView extends StatelessWidget {
  const StickerLayerView({
    super.key,
    required this.layer,
    required this.time,
    required this.canvasSize,
    this.selected = false,
  });

  final StickerLayer layer;
  final Duration time;
  final Size canvasSize;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scale = canvasSize.height / kCanvasReferenceHeight;
    final anim = _animate(
      t: time,
      start: layer.start,
      end: layer.end,
      animIn: layer.animationIn,
      animOut: layer.animationOut,
      animDuration: layer.animationDuration,
      textLength: 0,
    );
    final resolved =
        _resolveTransform(layer, layer.transform, time - layer.start);
    final size = layer.size * scale * resolved.scale * anim.scale;
    final Widget content = layer.isEmoji
        ? Text(layer.content,
            style: TextStyle(fontSize: size * 0.86, color: Color(layer.color)))
        : SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _ShapePainter(layer.content, size, Color(layer.color)),
            ),
          );

    return _Positioned(
      transform: resolved,
      canvasSize: canvasSize,
      anim: anim,
      selected: selected,
      child: content,
    );
  }
}

class _ShapePainter extends CustomPainter {
  _ShapePainter(this.shape, this.size, this.color);

  final String shape;
  final double size;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    canvas.translate(s.width / 2, s.height / 2);
    OverlayRasterizer.paintShape(canvas, shape, size, color);
  }

  @override
  bool shouldRepaint(covariant _ShapePainter old) =>
      old.shape != shape || old.size != size || old.color != color;
}

/// Draws a picture-in-picture layer over the main track.
class OverlayLayerView extends StatelessWidget {
  const OverlayLayerView({
    super.key,
    required this.layer,
    required this.time,
    required this.canvasSize,
    required this.controller,
    this.selected = false,
    this.unopenable = false,
  });

  final OverlayLayer layer;
  final Duration time;
  final Size canvasSize;
  final VideoPlayerController? controller;
  final bool selected;

  /// The layer's file could not be opened. A floating clip that has lost its
  /// media should say so too, rather than sitting there as a grey rectangle.
  final bool unopenable;

  @override
  Widget build(BuildContext context) {
    final anim = _animate(
      t: time,
      start: layer.start,
      end: layer.end,
      animIn: layer.animationIn,
      animOut: layer.animationOut,
      animDuration: layer.animationDuration,
      textLength: 0,
    );

    final resolved =
        _resolveTransform(layer, layer.transform, time - layer.start);
    final width = canvasSize.width * resolved.scale * anim.scale;
    final height = width / layer.sourceAspect;

    Widget media = layer.isImage
        ? Image.file(File(layer.path),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const MissingMedia())
        : (controller != null && controller!.value.isInitialized
            ? VideoPlayer(controller!)
            : unopenable
                ? const MissingMedia()
                : const ColoredBox(color: Colors.black45));

    if (layer.chromaKeyColor != null) {
      media = ChromaBox(
        keyColor: Color(layer.chromaKeyColor!),
        similarity: layer.chromaSimilarity,
        blend: layer.chromaBlend,
        child: media,
      );
    }
    final grade = layer.gradedFilter;
    final adj = layer.adjustments;
    if (adj.blur > 0) media = SoftenedBox(blur: adj.blur, child: media);
    if (!grade.isIdentity) media = GradedBox(filter: grade, child: media);
    if (GradeExtrasBox.wanted(adj, grade.gamma)) {
      media = GradeExtrasBox(
        adjustments: adj,
        gamma: grade.gamma,
        seed: (layer.id.hashCode % 997).toDouble(),
        child: media,
      );
    }
    if (layer.maskShape != MaskShape.none) {
      media = MaskBox(
        shape: layer.maskShape,
        size: layer.maskSize,
        feather: layer.maskFeather,
        x: layer.maskX,
        y: layer.maskY,
        rotation: layer.maskRotation,
        inverted: layer.maskInverted,
        child: media,
      );
    }

    Widget content = SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
            layer.animated(KeyframeProperty.cornerRadius, time - layer.start,
                    layer.cornerRadius) *
                canvasSize.height /
                kCanvasReferenceHeight),
        child: media,
      ),
    );
    if (layer.blendMode != BlendMode2.normal) {
      content = _Blended(mode: layer.blendMode, child: content);
    }

    return _Positioned(
      transform: resolved,
      canvasSize: canvasSize,
      anim: anim,
      selected: selected,
      child: content,
    );
  }
}

/// Shared placement: normalised position, rotation, opacity and the dashed
/// selection frame.
class _Positioned extends StatelessWidget {
  const _Positioned({
    required this.transform,
    required this.canvasSize,
    required this.anim,
    required this.child,
    required this.selected,
    this.contentKey,
  });

  final LayerTransform transform;
  final Size canvasSize;
  final _AnimState anim;
  final Widget child;
  final bool selected;

  /// Goes on the drawn content rather than on the full-canvas [Positioned],
  /// so a caller can hit-test a tap against the box the layer really covers.
  final Key? contentKey;

  @override
  Widget build(BuildContext context) {
    final dx = (transform.x + anim.offset.dx) * canvasSize.width;
    final dy = (transform.y + anim.offset.dy) * canvasSize.height;
    Widget content =
        contentKey == null ? child : KeyedSubtree(key: contentKey, child: child);
    if (anim.blur > 0) {
      content = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: anim.blur, sigmaY: anim.blur),
        child: content,
      );
    }
    if (selected) {
      content = Container(
        decoration: BoxDecoration(
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.2),
        ),
        child: content,
      );
    }
    if (anim.scaleX != 1 || anim.scaleY != 1) {
      content = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(anim.scaleX, anim.scaleY, 1),
        child: content,
      );
    }

    return Positioned(
      left: 0,
      top: 0,
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Transform.rotate(
          angle: transform.rotation + anim.rotation,
          child: Opacity(
            opacity: (transform.opacity * anim.opacity).clamp(0.0, 1.0),
            child: FractionalTranslation(
              translation: const Offset(-0.5, -0.5),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}


/// Real compositing for PIP layers. Flutter's [BlendMode] covers the same
/// modes FFmpeg's `blend` filter does, so preview and export agree.
class _Blended extends StatelessWidget {
  const _Blended({required this.mode, required this.child});

  final BlendMode2 mode;
  final Widget child;

  static BlendMode _flutterMode(BlendMode2 m) => switch (m) {
        BlendMode2.normal => BlendMode.srcOver,
        BlendMode2.multiply => BlendMode.multiply,
        BlendMode2.screen => BlendMode.screen,
        BlendMode2.overlay => BlendMode.overlay,
        BlendMode2.darken => BlendMode.darken,
        BlendMode2.lighten => BlendMode.lighten,
        BlendMode2.colorDodge => BlendMode.colorDodge,
        BlendMode2.colorBurn => BlendMode.colorBurn,
        BlendMode2.hardLight => BlendMode.hardLight,
        BlendMode2.softLight => BlendMode.softLight,
        BlendMode2.difference => BlendMode.difference,
        BlendMode2.exclusion => BlendMode.exclusion,
        BlendMode2.addition => BlendMode.plus,
        BlendMode2.subtract => BlendMode.difference,
      };

  @override
  Widget build(BuildContext context) {
    return BlendMask(blendMode: _flutterMode(mode), child: child);
  }
}

/// Applies a blend mode against whatever is already painted beneath it.
class BlendMask extends SingleChildRenderObjectWidget {
  const BlendMask({super.key, required this.blendMode, super.child});

  final BlendMode blendMode;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderBlendMask(blendMode);

  @override
  void updateRenderObject(BuildContext context, RenderBlendMask renderObject) {
    renderObject.blendMode = blendMode;
  }
}

class RenderBlendMask extends RenderProxyBox {
  RenderBlendMask(this._blendMode);

  BlendMode _blendMode;

  set blendMode(BlendMode value) {
    if (_blendMode == value) return;
    _blendMode = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    // saveLayer is what gives the blend a backdrop to composite against.
    context.canvas.saveLayer(offset & size, Paint()..blendMode = _blendMode);
    context.paintChild(child!, offset);
    context.canvas.restore();
  }
}
