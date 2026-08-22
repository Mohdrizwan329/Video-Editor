import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../data/models/video_effect.dart';
import '../../../data/services/effect_painter.dart';

/// The project's FX texture, laid over every lane on the canvas.
///
/// Both this and the exporter paint through [EffectPainter], so the texture
/// the creator sees is the texture that gets burned into the file.
///
/// A moving effect is driven by the *playhead*, not by a ticker of its own.
/// That is what makes it reproducible: the renderer bakes the same loop out
/// frame by frame and plays it at the same rate, so scrubbing to 4.2s here
/// and looking at 4.2s of the exported file show the same picture. A ticker
/// would drift from the first frame and there would be no way to line the
/// two back up.
class FxView extends StatelessWidget {
  const FxView({
    super.key,
    required this.preset,
    required this.intensity,
    this.time = Duration.zero,
  });

  final FxPreset preset;
  final double intensity;

  /// Where the playhead is. Still effects ignore it.
  final Duration time;

  @override
  Widget build(BuildContext context) {
    if (preset.isNone || intensity <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _FxPainter(preset, intensity, preset.frameAt(time)),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// A live FX swatch for the picker.
///
/// The canvas draws its effect off the playhead, which is right for the
/// canvas and useless for a row of thumbnails: parked on a paused frame,
/// Rain and Snow are the same handful of white specks. A swatch runs on a
/// clock of its own so the choice is legible before it is made, and it is the
/// only place in the app where an effect is not tied to the timeline.
class FxSwatch extends StatefulWidget {
  const FxSwatch({super.key, required this.preset, this.intensity = 1});

  final FxPreset preset;
  final double intensity;

  @override
  State<FxSwatch> createState() => _FxSwatchState();
}

class _FxSwatchState extends State<FxSwatch>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.preset.isAnimated) _ticker.start();
  }

  @override
  void didUpdateWidget(FxSwatch old) {
    super.didUpdateWidget(old);
    if (old.preset.id == widget.preset.id) return;
    if (widget.preset.isAnimated && !_ticker.isActive) {
      _ticker.start();
    } else if (!widget.preset.isAnimated && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// The ticker fires per display frame; the effect runs at a fraction of
  /// that. Rebuilding only when its frame index actually turns over keeps a
  /// row of swatches at the effect's rate rather than the screen's.
  void _tick(Duration elapsed) {
    if (widget.preset.frameAt(elapsed) == widget.preset.frameAt(_elapsed)) {
      return;
    }
    setState(() => _elapsed = elapsed);
  }

  @override
  Widget build(BuildContext context) => FxView(
        preset: widget.preset,
        intensity: widget.intensity,
        time: _elapsed,
      );
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
  const _FxPainter(this.preset, this.intensity, this.frame);

  final FxPreset preset;
  final double intensity;
  final int frame;

  @override
  void paint(Canvas canvas, Size size) =>
      EffectPainter.paintFx(canvas, size, preset, intensity, frame: frame);

  // The stage rebuilds on every playhead tick, which is several times per
  // frame of a 12fps effect; scattering thousands of grain dots again on each
  // of those would cost more than the whole video pipeline. Repainting on the
  // frame *index* rather than on the timestamp is what keeps the cost down to
  // the effect's own rate.
  @override
  bool shouldRepaint(_FxPainter old) =>
      old.preset.id != preset.id ||
      old.intensity != intensity ||
      old.frame != frame;
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
