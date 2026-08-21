import 'package:flutter/material.dart';

import '../../../data/models/video_effect.dart';
import '../../../data/services/effect_painter.dart';

/// The project's FX texture, laid over every lane on the canvas.
///
/// Both this and the exporter paint through [EffectPainter], so the texture
/// the creator sees is the texture that gets burned into the file.
class FxView extends StatelessWidget {
  const FxView({super.key, required this.preset, required this.intensity});

  final FxPreset preset;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    if (preset.isNone || intensity <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _FxPainter(preset, intensity),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// The project's design frame, drawn above the FX texture.
class FrameView extends StatelessWidget {
  const FrameView({super.key, required this.preset});

  final FramePreset preset;

  @override
  Widget build(BuildContext context) {
    if (preset.isNone) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _FramePainter(preset),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _FxPainter extends CustomPainter {
  const _FxPainter(this.preset, this.intensity);

  final FxPreset preset;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) =>
      EffectPainter.paintFx(canvas, size, preset, intensity);

  // The stage rebuilds on every playhead tick; scattering thousands of grain
  // dots again each time would cost more than the whole video pipeline.
  @override
  bool shouldRepaint(_FxPainter old) =>
      old.preset.id != preset.id || old.intensity != intensity;
}

class _FramePainter extends CustomPainter {
  const _FramePainter(this.preset);

  final FramePreset preset;

  @override
  void paint(Canvas canvas, Size size) =>
      EffectPainter.paintFrame(canvas, size, preset);

  @override
  bool shouldRepaint(_FramePainter old) => old.preset.id != preset.id;
}
