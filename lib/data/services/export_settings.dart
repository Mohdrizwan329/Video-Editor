import '../models/enums.dart';

/// User-facing render options, plus the derived numbers the encoder needs.
class ExportSettings {
  ExportSettings({
    this.resolution = ExportResolution.p1080,
    this.fps = ExportFps.fps30,
    this.quality = ExportQuality.standard,
    this.canvasAspect = 9 / 16,
  });

  ExportResolution resolution;
  ExportFps fps;
  ExportQuality quality;
  double canvasAspect;

  /// Output size with the short side pinned to the chosen resolution and both
  /// dimensions forced even (H.264 requires it).
  (int, int) get outputSize {
    final short = resolution.shortSide;
    int w, h;
    if (canvasAspect >= 1) {
      h = short;
      w = (short * canvasAspect).round();
    } else {
      w = short;
      h = (short / canvasAspect).round();
    }
    w = w.isEven ? w : w + 1;
    h = h.isEven ? h : h + 1;
    return (w, h);
  }

  int get width => outputSize.$1;
  int get height => outputSize.$2;

  /// Rough bitrate target: pixels x fps x bits-per-pixel x quality factor.
  int get videoBitrateKbps {
    final pixels = width * height;
    final base = pixels * fps.value * 0.07 / 1000;
    return (base * quality.factor).round().clamp(600, 90000);
  }

  int get audioBitrateKbps => quality == ExportQuality.low ? 96 : 192;

  /// x264 speed/efficiency trade-off per quality tier.
  String get preset => switch (quality) {
        ExportQuality.low => 'veryfast',
        ExportQuality.standard => 'faster',
        ExportQuality.high => 'medium',
        ExportQuality.max => 'slow',
      };

  /// Estimated output size for the given timeline length.
  int estimatedBytes(Duration d) =>
      (((videoBitrateKbps + audioBitrateKbps) * 1000 / 8) * d.inMilliseconds / 1000)
          .round();

  ExportSettings copy() => ExportSettings(
        resolution: resolution,
        fps: fps,
        quality: quality,
        canvasAspect: canvasAspect,
      );
}
