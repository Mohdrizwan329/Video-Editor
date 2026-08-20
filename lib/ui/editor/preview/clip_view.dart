import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../data/models/enums.dart';
import '../../../data/models/filter_preset.dart';
import '../../../data/models/keyframe.dart';
import '../../../data/models/video_clip.dart';
import 'chroma_box.dart';
import 'mask_box.dart';

/// Renders one clip exactly the way the exporter will: crop, rotate, mirror,
/// grade, then fit into the canvas with the user's pan and zoom.
class ClipView extends StatelessWidget {
  const ClipView({
    super.key,
    required this.clip,
    required this.controller,
    this.showGrade = true,
    this.localTime = Duration.zero,
  });

  final VideoClip clip;

  /// Offset inside the clip, used to evaluate its keyframe tracks.
  final Duration localTime;

  /// Null for image clips, or while the decoder is still opening.
  final VideoPlayerController? controller;
  final bool showGrade;

  @override
  Widget build(BuildContext context) {
    Widget media = _media();
    media = CroppedBox(
      left: clip.cropLeft,
      top: clip.cropTop,
      right: clip.cropRight,
      bottom: clip.cropBottom,
      aspect: clip.sourceAspect,
      child: media,
    );

    if (clip.rotation % 360 != 0) {
      media = RotatedBox(quarterTurns: (clip.rotation ~/ 90) % 4, child: media);
    }
    if (clip.mirrored || clip.flippedVertical) {
      media = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(
            clip.mirrored ? -1.0 : 1.0, clip.flippedVertical ? -1.0 : 1.0, 1.0),
        child: media,
      );
    }
    if (showGrade) {
      final intensity = clip.animated(
          KeyframeProperty.filterIntensity, localTime, clip.filterIntensity);
      final grade = clip.adjustments.merge(
          FilterPreset.fromId(clip.filterId).lerpFromIdentity(intensity));
      if (!grade.isIdentity) media = GradedBox(filter: grade, child: media);
    }
    if (clip.hasChroma) {
      media = ChromaBox(
        keyColor: Color(clip.chromaKeyColor!),
        similarity: clip.chromaSimilarity,
        blend: clip.chromaBlend,
        child: media,
      );
    }
    if (clip.hasMask) {
      media = MaskBox(
        shape: clip.maskShape,
        size: clip.maskSize,
        feather: clip.maskFeather,
        x: clip.maskX,
        y: clip.maskY,
        rotation: clip.maskRotation,
        inverted: clip.maskInverted,
        child: media,
      );
    }
    final opacity = clip.animated(KeyframeProperty.opacity, localTime, clip.opacity);
    if (opacity < 1) {
      media = Opacity(opacity: opacity.clamp(0.0, 1.0), child: media);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = switch (clip.fit) {
          FitMode.cover => BoxFit.cover,
          FitMode.stretch => BoxFit.fill,
          FitMode.contain => BoxFit.contain,
        };
        final kx = clip.animated(KeyframeProperty.x, localTime, clip.offsetX);
        final ky = clip.animated(KeyframeProperty.y, localTime, clip.offsetY);
        final kScale = clip.animated(KeyframeProperty.scale, localTime, clip.scale);
        final kRot =
            clip.animated(KeyframeProperty.rotation, localTime, 0);
        return ClipRect(
          child: Transform.rotate(
            angle: kRot,
            child: Transform.translate(
            offset: Offset(
              kx * constraints.maxWidth / 2,
              ky * constraints.maxHeight / 2,
            ),
            child: Transform.scale(
              scale: kScale,
              child: FittedBox(fit: fit, child: _sized(media)),
            ),
            ),
          ),
        );
      },
    );
  }

  Widget _sized(Widget media) {
    final aspect = _croppedAspect;
    return SizedBox(
      width: 1000 * aspect,
      height: 1000,
      child: media,
    );
  }

  double get _croppedAspect {
    final w = (1 - clip.cropLeft - clip.cropRight).clamp(0.05, 1.0);
    final h = (1 - clip.cropTop - clip.cropBottom).clamp(0.05, 1.0);
    return clip.sourceAspect * w / h;
  }

  Widget _media() {
    if (clip.isImage) {
      return Image.file(
        File(clip.path),
        fit: BoxFit.fill,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
      );
    }
    final c = controller;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return VideoPlayer(c);
  }
}

/// Applies a [FilterPreset] as a colour matrix — the preview twin of the
/// FFmpeg chain the exporter emits.
class GradedBox extends StatelessWidget {
  const GradedBox({super.key, required this.filter, required this.child});

  final FilterPreset filter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget out = ColorFiltered(
      colorFilter: ColorFilter.matrix(filter.toColorMatrix()),
      child: child,
    );
    if (filter.vignette > 0) {
      out = Stack(
        fit: StackFit.passthrough,
        children: [
          out,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.85,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: filter.vignette * 0.75),
                    ],
                    stops: const [0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return out;
  }
}

/// Shows only the region left after the crop insets, keeping the visible
/// window's aspect ratio intact.
class CroppedBox extends StatelessWidget {
  const CroppedBox({
    super.key,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.aspect,
    required this.child,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
  final double aspect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (left == 0 && top == 0 && right == 0 && bottom == 0) return child;
    final kx = (1 - left - right).clamp(0.05, 1.0);
    final ky = (1 - top - bottom).clamp(0.05, 1.0);
    // Slide the oversized child so the kept window lands inside the box.
    final ax = (left + right) == 0 ? 0.0 : (2 * left / (left + right)) - 1;
    final ay = (top + bottom) == 0 ? 0.0 : (2 * top / (top + bottom)) - 1;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment(ax, ay),
            minWidth: 0,
            minHeight: 0,
            maxWidth: w / kx,
            maxHeight: h / ky,
            child: SizedBox(width: w / kx, height: h / ky, child: child),
          ),
        );
      },
    );
  }
}
