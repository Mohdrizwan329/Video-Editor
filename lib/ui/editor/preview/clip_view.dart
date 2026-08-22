import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../data/models/enums.dart';
import '../../../data/models/filter_preset.dart';
import '../../../data/models/keyframe.dart';
import '../../../data/models/video_clip.dart';
import 'chroma_box.dart';
import 'grade_extras_box.dart';
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
    this.unopenable = false,
  });

  final VideoClip clip;

  /// Offset inside the clip, used to evaluate its keyframe tracks.
  final Duration localTime;

  /// Null for image clips, or while the decoder is still opening.
  final VideoPlayerController? controller;
  final bool showGrade;

  /// The clip's file could not be opened at all. Without this the stage has
  /// no way to tell "still decoding" from "this file is gone", and both look
  /// like a video that happens to be black.
  final bool unopenable;

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
          clip.mirrored ? -1.0 : 1.0,
          clip.flippedVertical ? -1.0 : 1.0,
          1.0,
        ),
        child: media,
      );
    }
    if (showGrade) {
      final intensity = clip.animated(
        KeyframeProperty.filterIntensity,
        localTime,
        clip.filterIntensity,
      );
      final adj = clip.adjustments;
      final grade = adj.merge(
        FilterPreset.fromId(clip.filterId).lerpFromIdentity(intensity),
      );
      // Innermost of the three, so grain and sharpening land on the softened
      // picture — the order the exporter's own filter chain has them in.
      if (adj.blur > 0) media = SoftenedBox(blur: adj.blur, child: media);
      if (!grade.isIdentity) media = GradedBox(filter: grade, child: media);
      if (GradeExtrasBox.wanted(adj, grade.gamma)) {
        media = GradeExtrasBox(
          adjustments: adj,
          gamma: grade.gamma,
          seed: (clip.id.hashCode % 997).toDouble(),
          child: media,
        );
      }
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
    // The ease and the alpha animation are opacity over time, and the
    // exporter has always drawn them. The preview did not, so both read as
    // sliders that moved and changed nothing until the file came out.
    final opacity = clip.animated(
      KeyframeProperty.opacity,
      localTime,
      clip.opacityAt(localTime),
    );
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
        final kScale = clip.animated(
          KeyframeProperty.scale,
          localTime,
          clip.scale,
        );
        final kRot = clip.animated(KeyframeProperty.rotation, localTime, 0);
        // The in and out animations ride on top of the transform the clip
        // already has, so a slide plays over whatever pan and zoom the user
        // set rather than replacing it.
        final (ax, ay, aScale, aRot) = clip.animationTransformAt(localTime);
        return ClipRect(
          child: Transform.rotate(
            angle: kRot + aRot,
            child: Transform.translate(
              offset: Offset(
                (kx + ax * 2) * constraints.maxWidth / 2,
                (ky + ay * 2) * constraints.maxHeight / 2,
              ),
              child: Transform.scale(
                scale: kScale * aScale,
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
    return SizedBox(width: 1000 * aspect, height: 1000, child: media);
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
        errorBuilder: (_, _, _) => const MissingMedia(),
      );
    }
    final c = controller;
    if (c != null && c.value.isInitialized) return VideoPlayer(c);
    // A file that will not open never becomes a picture, so saying so beats
    // a black rectangle the user has no way to read.
    return unopenable
        ? const MissingMedia()
        : const ColoredBox(color: Colors.black);
  }
}

/// What the stage shows in place of a clip whose file has gone.
///
/// It is drawn against the clip's own 1000-unit box and scaled down with it,
/// so the wording stays the same size relative to the picture whether the
/// stage is a phone preview or a tablet's.
class MissingMedia extends StatelessWidget {
  const MissingMedia({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF141414),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.videocam_off_outlined,
                  size: 130,
                  color: Color(0xFF8C8C99),
                ),
                SizedBox(height: 28),
                Text(
                  'This clip could not be opened',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE8E6F2),
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  'Its file may have been moved or deleted.\n'
                  'Use Replace to point it at the video again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 34,
                    height: 1.35,
                    color: Color(0xFF9C98AE),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

/// The preview twin of the exporter's `gblur`.
///
/// The exported sigma is 12px at 1080p, which is 1.11% of the frame height.
/// This box is drawn inside the 1000-tall media box, so the same softening
/// is 11.1 units here whatever size the canvas is on screen.
class SoftenedBox extends StatelessWidget {
  const SoftenedBox({super.key, required this.blur, required this.child});

  /// 0..1, straight off the Blur slider.
  final double blur;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sigma = blur * 11.1;
    return ImageFiltered(
      // Clamp, not the default decal: a decal edge fades the frame's border
      // to transparent and reads as a dark rim over the background.
      imageFilter: ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.clamp,
      ),
      child: child,
    );
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
