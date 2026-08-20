import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../data/models/enums.dart';
import '../../../data/models/project.dart';

/// Paints whatever shows through the letterbox around a contained clip.
class CanvasBackground extends StatelessWidget {
  const CanvasBackground({
    super.key,
    required this.style,
    this.blurSource,
  });

  final BackgroundStyle style;

  /// The current frame, used as the source for the blurred variant.
  final Widget? blurSource;

  @override
  Widget build(BuildContext context) {
    switch (style.type) {
      case BackgroundType.color:
        return ColoredBox(color: Color(style.color));
      case BackgroundType.gradient:
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(style.gradientStart), Color(style.gradientEnd)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        );
      case BackgroundType.blur:
        if (blurSource == null) return const ColoredBox(color: Colors.black);
        return Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(fit: BoxFit.cover, child: blurSource),
            BackdropFilter(
              filter: ImageFilter.blur(
                  sigmaX: style.blurAmount, sigmaY: style.blurAmount),
              child: Container(color: Colors.black.withValues(alpha: 0.18)),
            ),
          ],
        );
    }
  }
}
