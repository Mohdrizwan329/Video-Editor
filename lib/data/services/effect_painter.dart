import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/video_effect.dart';

/// Draws design frames and FX textures onto a canvas.
///
/// Every measurement is a fraction of [size], and every random scatter runs
/// off the preset's fixed seed, so painting a preset into a 300pt preview and
/// into a 1080px export PNG produces the same picture at two resolutions.
/// The preview widget and the exporter both come through here — that is what
/// keeps what the creator sees and what lands in the file in step.
class EffectPainter {
  const EffectPainter._();

  // ------------------------------------------------------------------ frames

  static void paintFrame(Canvas canvas, Size size, FramePreset f) {
    if (f.isNone || size.isEmpty) return;
    final short = math.min(size.width, size.height);
    final t = (f.thickness * short).clamp(1.0, short / 3);
    final color = Color(f.color);
    final accent = Color(f.accent);
    final rect = Offset.zero & size;

    switch (f.style) {
      case FrameStyle.none:
        return;

      case FrameStyle.solid:
        canvas.drawRect(
          rect.deflate(t / 2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = t
            ..color = color,
        );

      case FrameStyle.rounded:
        canvas.drawPath(
          Path()
            ..addRect(rect)
            ..addRRect(RRect.fromRectAndRadius(
                rect.deflate(t), Radius.circular(t * 1.8)))
            ..fillType = PathFillType.evenOdd,
          Paint()..color = color,
        );

      case FrameStyle.doubleLine:
        canvas.drawRect(
          rect.deflate(t * 0.75),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = t * 0.45
            ..color = color,
        );
        canvas.drawRect(
          rect.deflate(t * 1.9),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = t * 0.22
            ..color = color,
        );

      case FrameStyle.corners:
        final len = short * 0.13;
        final w = t * 1.1;
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.square
          ..color = color;
        final i = t * 1.2;
        final r = rect.deflate(i);
        for (final corner in [
          [r.topLeft, const Offset(1, 0), const Offset(0, 1)],
          [r.topRight, const Offset(-1, 0), const Offset(0, 1)],
          [r.bottomLeft, const Offset(1, 0), const Offset(0, -1)],
          [r.bottomRight, const Offset(-1, 0), const Offset(0, -1)],
        ]) {
          final o = corner[0];
          canvas.drawLine(o, o + corner[1] * len, p);
          canvas.drawLine(o, o + corner[2] * len, p);
        }

      case FrameStyle.polaroid:
        // The classic deep chin along the bottom edge.
        final bottom = t * 3.4;
        canvas.drawPath(
          Path()
            ..addRect(rect)
            ..addRect(Rect.fromLTRB(
                t, t, size.width - t, size.height - bottom))
            ..fillType = PathFillType.evenOdd,
          Paint()..color = color,
        );

      case FrameStyle.mat:
        canvas.drawPath(
          Path()
            ..addRect(rect)
            ..addRect(rect.deflate(t))
            ..fillType = PathFillType.evenOdd,
          Paint()..color = color,
        );
        canvas.drawRect(
          rect.deflate(t),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, t * 0.06)
            ..color = Colors.black.withValues(alpha: 0.18),
        );

      case FrameStyle.filmStrip:
        final bar = t * 2.6;
        final p = Paint()..color = color;
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, bar), p);
        canvas.drawRect(
            Rect.fromLTWH(0, size.height - bar, size.width, bar), p);
        final hw = bar * 0.46;
        final hh = bar * 0.4;
        final gap = hw * 0.85;
        final hole = Paint()..color = accent;
        final radius = Radius.circular(hh * 0.3);
        for (var x = gap; x + hw < size.width; x += hw + gap) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(x, (bar - hh) / 2, hw, hh), radius),
              hole);
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(x, size.height - bar + (bar - hh) / 2, hw, hh),
                  radius),
              hole);
        }

      case FrameStyle.tape:
        canvas.drawPath(
          Path()
            ..addRect(rect)
            ..addRect(rect.deflate(t))
            ..fillType = PathFillType.evenOdd,
          Paint()..color = color,
        );
        final len = short * 0.17;
        final w = short * 0.055;
        final strip = Paint()..color = accent;
        for (final c in [
          [rect.topLeft, 1.0],
          [rect.topRight, -1.0],
          [rect.bottomLeft, -1.0],
          [rect.bottomRight, 1.0],
        ]) {
          canvas.save();
          canvas.translate((c[0] as Offset).dx, (c[0] as Offset).dy);
          canvas.rotate((c[1] as double) * math.pi / 4);
          canvas.drawRect(
              Rect.fromCenter(center: Offset.zero, width: len, height: w),
              strip);
          canvas.restore();
        }

      case FrameStyle.neon:
        final r = RRect.fromRectAndRadius(
            rect.deflate(t * 1.6), Radius.circular(t * 2.2));
        canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = t * 1.7
            ..color = accent.withValues(alpha: 0.5)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, t * 1.6),
        );
        canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = t * 0.8
            ..color = accent,
        );
        canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = t * 0.28
            ..color = color,
        );
    }
  }

  // ---------------------------------------------------------------------- fx

  static void paintFx(
      Canvas canvas, Size size, FxPreset fx, double intensity) {
    if (fx.isNone || size.isEmpty) return;
    final a = (intensity.clamp(0.0, 1.0) * fx.opacity).clamp(0.0, 1.0);
    if (a <= 0) return;
    final rnd = math.Random(fx.seed);
    final rect = Offset.zero & size;

    switch (fx.pattern) {
      case FxPattern.none:
        return;

      case FxPattern.grain:
        _grain(canvas, size, rnd, a);

      case FxPattern.scanlines:
        _scanlines(canvas, size, a);

      case FxPattern.halftone:
        final step = math.max(3.0, size.shortestSide / 46);
        final p = Paint()..color = Colors.black.withValues(alpha: a * 0.32);
        for (var y = step / 2; y < size.height; y += step) {
          for (var x = step / 2; x < size.width; x += step) {
            canvas.drawCircle(Offset(x, y), step * 0.23, p);
          }
        }

      case FxPattern.vhs:
        _scanlines(canvas, size, a * 0.8);
        // Colour fringe down each edge, plus a rolling bright band.
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width * 0.03, size.height),
          Paint()
            ..color = const Color(0xFFFF2D95).withValues(alpha: a * 0.35),
        );
        canvas.drawRect(
          Rect.fromLTWH(
              size.width * 0.97, 0, size.width * 0.03, size.height),
          Paint()
            ..color = const Color(0xFF00E5FF).withValues(alpha: a * 0.35),
        );
        final band = Rect.fromLTWH(
            0, size.height * 0.18, size.width, size.height * 0.06);
        canvas.drawRect(
          band,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: a * 0.22),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(band),
        );
        _grain(canvas, size, rnd, a * 0.4);

      case FxPattern.lightLeak:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                const Color(0xFFFFC978).withValues(alpha: a * 0.7),
                const Color(0xFFFF5E3A).withValues(alpha: a * 0.28),
                Colors.transparent,
              ],
              stops: const [0, 0.34, 0.78],
            ).createShader(rect),
        );

      case FxPattern.bloom:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              radius: 0.8,
              colors: [
                Colors.white.withValues(alpha: a * 0.4),
                Colors.white.withValues(alpha: a * 0.1),
                Colors.transparent,
              ],
              stops: const [0, 0.5, 1],
            ).createShader(rect),
        );

      case FxPattern.prism:
        final w = size.width * 0.06;
        final left = Rect.fromLTWH(0, 0, w, size.height);
        canvas.drawRect(
          left,
          Paint()
            ..shader = LinearGradient(
              colors: [
                const Color(0xFFFF2D2D).withValues(alpha: a * 0.5),
                Colors.transparent,
              ],
            ).createShader(left),
        );
        final right = Rect.fromLTWH(size.width - w, 0, w, size.height);
        canvas.drawRect(
          right,
          Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.transparent,
                const Color(0xFF2D6BFF).withValues(alpha: a * 0.5),
              ],
            ).createShader(right),
        );

      case FxPattern.dust:
        final specks = (size.width * size.height / 5200)
            .round()
            .clamp(40, 1400);
        final p = Paint();
        for (var i = 0; i < specks; i++) {
          p.color = Colors.white
              .withValues(alpha: a * (0.2 + rnd.nextDouble() * 0.5));
          canvas.drawCircle(
            Offset(rnd.nextDouble() * size.width,
                rnd.nextDouble() * size.height),
            size.shortestSide / 540 * (0.6 + rnd.nextDouble() * 1.4),
            p,
          );
        }
        // A handful of vertical scratches, the way a worn print looks.
        final line = Paint()
          ..strokeWidth = math.max(0.8, size.shortestSide / 700)
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 6; i++) {
          final x = rnd.nextDouble() * size.width;
          final top = rnd.nextDouble() * size.height * 0.5;
          line.color =
              Colors.white.withValues(alpha: a * (0.15 + rnd.nextDouble() * 0.3));
          canvas.drawLine(Offset(x, top),
              Offset(x + size.width * 0.004, top + size.height * 0.45), line);
        }

      case FxPattern.glitch:
        for (var i = 0; i < 9; i++) {
          final y = rnd.nextDouble() * size.height;
          final h = size.height * (0.005 + rnd.nextDouble() * 0.028);
          final off = (rnd.nextDouble() - 0.5) * size.width * 0.14;
          canvas.drawRect(
            Rect.fromLTWH(off, y, size.width, h),
            Paint()
              ..color = (i.isEven
                      ? const Color(0xFF00E5FF)
                      : const Color(0xFFFF2D95))
                  .withValues(alpha: a * 0.4),
          );
          canvas.drawRect(
            Rect.fromLTWH(0, y + h, size.width, h * 0.55),
            Paint()..color = Colors.black.withValues(alpha: a * 0.32),
          );
        }

      case FxPattern.staticNoise:
        final blocks = (size.width * size.height / 2600)
            .round()
            .clamp(120, 4200);
        final p = Paint();
        final unit = size.shortestSide / 220;
        for (var i = 0; i < blocks; i++) {
          p.color = (rnd.nextBool() ? Colors.white : Colors.black)
              .withValues(alpha: a * (0.08 + rnd.nextDouble() * 0.3));
          canvas.drawRect(
            Rect.fromLTWH(
              rnd.nextDouble() * size.width,
              rnd.nextDouble() * size.height,
              unit * (1 + rnd.nextDouble() * 3),
              unit,
            ),
            p,
          );
        }
    }
  }

  /// Density is per unit area so the grain reads the same at preview size and
  /// at export size instead of turning into mush on the big canvas.
  static void _grain(Canvas canvas, Size size, math.Random rnd, double a) {
    final count =
        (size.width * size.height / 850).round().clamp(150, 26000);
    final unit = size.shortestSide / 540;
    final p = Paint();
    for (var i = 0; i < count; i++) {
      p.color = (rnd.nextBool() ? Colors.white : Colors.black)
          .withValues(alpha: a * (0.08 + rnd.nextDouble() * 0.18));
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        unit * (0.35 + rnd.nextDouble() * 0.9),
        p,
      );
    }
  }

  static void _scanlines(Canvas canvas, Size size, double a) {
    final gap = math.max(1.5, size.height / 260);
    final p = Paint()..color = Colors.black.withValues(alpha: a * 0.34);
    for (var y = 0.0; y < size.height; y += gap * 2) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, gap), p);
    }
  }
}
