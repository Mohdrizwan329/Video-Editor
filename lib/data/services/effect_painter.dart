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

  /// Paints [fx] at [frame] of its loop.
  ///
  /// [frame] is an index into [FxPreset.frameCount], not a timestamp: the
  /// preview asks the preset which frame the playhead is on and the renderer
  /// bakes the whole loop out at the same indices, so the two cannot drift
  /// apart the way a wall-clock phase would. Everything scattered is drawn
  /// off a seed derived from the frame, so frame 7 of a grain loop is the
  /// same scatter on a 300pt preview and on a 1080px export.
  static void paintFx(
    Canvas canvas,
    Size size,
    FxPreset fx,
    double intensity, {
    int frame = 0,
  }) {
    if (fx.isNone || size.isEmpty) return;
    final a = (intensity.clamp(0.0, 1.0) * fx.opacity).clamp(0.0, 1.0);
    if (a <= 0) return;

    final count = fx.frameCount;
    // 0..1 around the loop. Every cycle below is built on whole multiples of
    // this so the last frame runs back into the first with no jump.
    final phase = count <= 1 ? 0.0 : (frame % count) / count;
    // Re-drawn scatter — grain, dirt, snow on the wind. Reseeded per frame.
    final rnd = math.Random(fx.seed * 7919 + frame);
    // The scatter that has to *stay put* while it moves: where a raindrop's
    // column is, how big a bokeh disc is. Seeded off the preset alone, so
    // every frame of the loop agrees about which particle is which.
    final fixed = math.Random(fx.seed);
    final rect = Offset.zero & size;

    switch (fx.pattern) {
      case FxPattern.none:
        return;

      case FxPattern.grain:
        _grain(canvas, size, rnd, a);

      case FxPattern.scanlines:
        _scanlines(canvas, size, a, phase);

      case FxPattern.halftone:
        final step = math.max(3.0, size.shortestSide / 46);
        // The dot grid creeps a whole cell over the loop, which reads as a
        // print shifting under the light rather than as a still screen.
        final slide = phase * step;
        final p = Paint()..color = Colors.black.withValues(alpha: a * 0.32);
        for (var y = step / 2 - step; y < size.height + step; y += step) {
          for (var x = step / 2 - step; x < size.width + step; x += step) {
            canvas.drawCircle(
                Offset(x + slide, y + slide), step * 0.23, p);
          }
        }

      case FxPattern.vhs:
        _scanlines(canvas, size, a * 0.8, phase);
        // Colour fringe down each edge, plus the tracking band rolling up
        // the picture the way a worn tape drifts out of sync.
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
        final bandH = size.height * 0.06;
        final bandY = (1 - phase) * (size.height + bandH) - bandH;
        final band = Rect.fromLTWH(0, bandY, size.width, bandH);
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
        // The leak breathes and swings across the corner rather than sitting
        // in it — a leak is light getting past a seam, not a gel.
        final swing = math.sin(phase * 2 * math.pi);
        final pulse = 0.72 + 0.28 * math.cos(phase * 2 * math.pi);
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment(1 - swing * 0.35, -1 + swing * 0.2),
              end: Alignment(-1, 1),
              colors: [
                const Color(0xFFFFC978).withValues(alpha: a * 0.7 * pulse),
                const Color(0xFFFF5E3A).withValues(alpha: a * 0.28 * pulse),
                Colors.transparent,
              ],
              stops: const [0, 0.34, 0.78],
            ).createShader(rect),
        );

      case FxPattern.bloom:
        final pulse = 0.7 + 0.3 * math.cos(phase * 2 * math.pi);
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              radius: 0.8 * (0.88 + 0.12 * pulse),
              colors: [
                Colors.white.withValues(alpha: a * 0.4 * pulse),
                Colors.white.withValues(alpha: a * 0.1 * pulse),
                Colors.transparent,
              ],
              stops: const [0, 0.5, 1],
            ).createShader(rect),
        );

      case FxPattern.prism:
        // The two fringes breathe in opposite directions, which is what
        // separation looks like when a lens is being pushed.
        final swell = math.sin(phase * 2 * math.pi);
        final w = size.width * 0.06;
        final lw = w * (1 + swell * 0.45);
        final rw = w * (1 - swell * 0.45);
        final left = Rect.fromLTWH(0, 0, math.max(1, lw), size.height);
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
        final right = Rect.fromLTWH(
            size.width - math.max(1, rw), 0, math.max(1, rw), size.height);
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
        _dust(canvas, size, rnd, a);

      case FxPattern.glitch:
        // A glitch that fires every frame is a texture, not a fault. This
        // one tears for a third of the loop and leaves the picture alone
        // the rest of the time.
        final firing = phase < 0.34;
        final slices = firing ? 9 : 2;
        final force = firing ? 1.0 : 0.35;
        for (var i = 0; i < slices; i++) {
          final y = rnd.nextDouble() * size.height;
          final h = size.height * (0.005 + rnd.nextDouble() * 0.028);
          final off = (rnd.nextDouble() - 0.5) * size.width * 0.14 * force;
          canvas.drawRect(
            Rect.fromLTWH(off, y, size.width, h),
            Paint()
              ..color = (i.isEven
                      ? const Color(0xFF00E5FF)
                      : const Color(0xFFFF2D95))
                  .withValues(alpha: a * 0.4 * force),
          );
          canvas.drawRect(
            Rect.fromLTWH(0, y + h, size.width, h * 0.55),
            Paint()
              ..color = Colors.black.withValues(alpha: a * 0.32 * force),
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

      // ------------------------------------------------------------ motion

      case FxPattern.strobe:
        // Hard on/off. A quarter of the loop lit is the ratio that reads as
        // a strobe rather than as a flicker fault.
        if (phase < 0.25) {
          canvas.drawRect(
              rect, Paint()..color = Colors.white.withValues(alpha: a * 0.72));
        }

      case FxPattern.flash:
        final pulse = 0.5 + 0.5 * math.cos(phase * 2 * math.pi);
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              radius: 1.1,
              colors: [
                Colors.white.withValues(alpha: a * 0.5 * pulse),
                Colors.white.withValues(alpha: a * 0.16 * pulse),
                Colors.transparent,
              ],
              stops: const [0, 0.55, 1],
            ).createShader(rect),
        );

      case FxPattern.oldTv:
        _scanlines(canvas, size, a * 0.9, phase);
        final rollH = size.height * 0.14;
        final rollY = (1 - phase) * (size.height + rollH) - rollH;
        final roll = Rect.fromLTWH(0, rollY, size.width, rollH);
        canvas.drawRect(
          roll,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: a * 0.16),
                Colors.black.withValues(alpha: a * 0.2),
                Colors.white.withValues(alpha: 0),
              ],
              stops: const [0, 0.35, 0.65, 1],
            ).createShader(roll),
        );
        _grain(canvas, size, rnd, a * 0.5);
        // The tube's own falloff, which is most of why old footage reads old.
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              radius: 0.86,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: a * 0.55),
              ],
              stops: const [0.6, 1],
            ).createShader(rect),
        );

      case FxPattern.filmBurn:
        // The burn swells out of one corner and dies back, the way a frame
        // catches in a stuck projector.
        final swell = 0.35 + 0.65 * (0.5 + 0.5 * math.cos(phase * 2 * math.pi));
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.9, 1.0),
              radius: 0.55 + swell * 0.85,
              colors: [
                const Color(0xFFFFF1B8).withValues(alpha: a * 0.85 * swell),
                const Color(0xFFFF9330).withValues(alpha: a * 0.6 * swell),
                const Color(0xFFB4260A).withValues(alpha: a * 0.3 * swell),
                Colors.transparent,
              ],
              stops: const [0, 0.28, 0.55, 1],
            ).createShader(rect),
        );
        _grain(canvas, size, rnd, a * 0.35);

      case FxPattern.neonPulse:
        // Two colours trading places round the border, which is what a neon
        // sign's chase looks like from across a room.
        final swing = 0.5 + 0.5 * math.cos(phase * 2 * math.pi);
        final band = size.shortestSide * (0.05 + 0.03 * swing);
        const pink = Color(0xFFFF2D95);
        const cyan = Color(0xFF00E5FF);
        void edge(Rect r, Alignment from, Alignment to, Color c, double k) {
          canvas.drawRect(
            r,
            Paint()
              ..shader = LinearGradient(
                begin: from,
                end: to,
                colors: [
                  c.withValues(alpha: a * 0.75 * k),
                  Colors.transparent,
                ],
              ).createShader(r),
          );
        }
        edge(Rect.fromLTWH(0, 0, size.width, band), Alignment.topCenter,
            Alignment.bottomCenter, pink, swing);
        edge(Rect.fromLTWH(0, size.height - band, size.width, band),
            Alignment.bottomCenter, Alignment.topCenter, cyan, 1 - swing);
        edge(Rect.fromLTWH(0, 0, band, size.height), Alignment.centerLeft,
            Alignment.centerRight, cyan, 1 - swing);
        edge(Rect.fromLTWH(size.width - band, 0, band, size.height),
            Alignment.centerRight, Alignment.centerLeft, pink, swing);

      case FxPattern.sparkle:
        final n = (size.width * size.height / 26000).round().clamp(14, 90);
        for (var i = 0; i < n; i++) {
          final x = fixed.nextDouble() * size.width;
          final y = fixed.nextDouble() * size.height;
          final r = size.shortestSide * (0.006 + fixed.nextDouble() * 0.012);
          final offset = fixed.nextDouble();
          final beats = 1 + fixed.nextInt(3);
          // Each star keeps its own beat and its own place in it, so they
          // twinkle out of step instead of blinking as one sheet.
          final k = 0.5 + 0.5 * math.cos((phase * beats + offset) * 2 * math.pi);
          final alpha = a * k * k;
          if (alpha <= 0.01) continue;
          final p = Paint()..color = Colors.white.withValues(alpha: alpha);
          final arm = r * (1 + k);
          canvas.drawLine(Offset(x - arm, y), Offset(x + arm, y),
              p..strokeWidth = math.max(0.7, r * 0.35));
          canvas.drawLine(Offset(x, y - arm), Offset(x, y + arm), p);
          canvas.drawCircle(Offset(x, y), r * 0.4, p);
        }

      case FxPattern.rain:
        final n = (size.width * size.height / 5200).round().clamp(60, 520);
        final p = Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(0.9, size.shortestSide / 620);
        for (var i = 0; i < n; i++) {
          final x = fixed.nextDouble() * size.width;
          final len = size.height * (0.05 + fixed.nextDouble() * 0.07);
          final offset = fixed.nextDouble();
          // Whole numbers of passes per loop, so the last frame runs back
          // into the first without a jump.
          final passes = 2 + fixed.nextInt(2);
          final travel = (phase * passes + offset) % 1;
          final y = travel * (size.height + len) - len;
          final slant = size.width * 0.012;
          p.color = Colors.white
              .withValues(alpha: a * (0.2 + fixed.nextDouble() * 0.35));
          canvas.drawLine(Offset(x, y), Offset(x + slant, y + len), p);
        }

      case FxPattern.snow:
        final n = (size.width * size.height / 9000).round().clamp(40, 320);
        final p = Paint();
        for (var i = 0; i < n; i++) {
          final x0 = fixed.nextDouble() * size.width;
          final r = size.shortestSide * (0.004 + fixed.nextDouble() * 0.008);
          final offset = fixed.nextDouble();
          final sway = size.width * (0.01 + fixed.nextDouble() * 0.035);
          final beats = 1 + fixed.nextInt(3);
          final travel = (phase + offset) % 1;
          final y = travel * (size.height + r * 2) - r;
          final x = x0 + math.sin((phase * beats + offset) * 2 * math.pi) * sway;
          p.color = Colors.white
              .withValues(alpha: a * (0.4 + fixed.nextDouble() * 0.5));
          canvas.drawCircle(Offset(x, y), r, p);
        }

      case FxPattern.bokeh:
        final n = (size.width * size.height / 34000).round().clamp(10, 60);
        for (var i = 0; i < n; i++) {
          final x0 = fixed.nextDouble() * size.width;
          final r = size.shortestSide * (0.03 + fixed.nextDouble() * 0.07);
          final offset = fixed.nextDouble();
          final sway = size.width * (0.01 + fixed.nextDouble() * 0.03);
          final travel = (phase + offset) % 1;
          // Drifting up, and fading in and out at the two ends so nothing
          // pops into being at the edge of frame.
          final y = (1 - travel) * (size.height + r * 2) - r;
          final x = x0 + math.sin((phase + offset) * 2 * math.pi) * sway;
          final fade = math.sin(travel * math.pi);
          final tint = i.isEven
              ? const Color(0xFFFFF0C4)
              : const Color(0xFFC4E4FF);
          final disc = Rect.fromCircle(center: Offset(x, y), radius: r);
          canvas.drawCircle(
            Offset(x, y),
            r,
            Paint()
              ..shader = RadialGradient(
                colors: [
                  tint.withValues(alpha: a * 0.42 * fade),
                  tint.withValues(alpha: a * 0.16 * fade),
                  Colors.transparent,
                ],
                stops: const [0, 0.62, 1],
              ).createShader(disc),
          );
        }

      case FxPattern.confetti:
        final n = (size.width * size.height / 11000).round().clamp(30, 240);
        const palette = [
          Color(0xFFFF4D6D), Color(0xFFFFD166), Color(0xFF06D6A0),
          Color(0xFF4CC9F0), Color(0xFFB388FF), Color(0xFFFF8FAB),
        ];
        for (var i = 0; i < n; i++) {
          final x0 = fixed.nextDouble() * size.width;
          final w = size.shortestSide * (0.012 + fixed.nextDouble() * 0.016);
          final h = w * (0.45 + fixed.nextDouble() * 0.5);
          final offset = fixed.nextDouble();
          final sway = size.width * (0.01 + fixed.nextDouble() * 0.04);
          final spins = 1 + fixed.nextInt(3);
          final colour = palette[fixed.nextInt(palette.length)];
          final travel = (phase + offset) % 1;
          final y = travel * (size.height + h * 2) - h;
          final x = x0 + math.sin((phase * 2 + offset) * 2 * math.pi) * sway;
          canvas.save();
          canvas.translate(x, y);
          canvas.rotate((phase * spins + offset) * 2 * math.pi);
          canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: w, height: h),
            Paint()..color = colour.withValues(alpha: a * 0.9),
          );
          canvas.restore();
        }

      case FxPattern.hearts:
        final n = (size.width * size.height / 26000).round().clamp(12, 90);
        for (var i = 0; i < n; i++) {
          final x0 = fixed.nextDouble() * size.width;
          final r = size.shortestSide * (0.018 + fixed.nextDouble() * 0.028);
          final offset = fixed.nextDouble();
          final sway = size.width * (0.015 + fixed.nextDouble() * 0.04);
          final beats = 1 + fixed.nextInt(2);
          final travel = (phase + offset) % 1;
          final y = (1 - travel) * (size.height + r * 2) - r;
          final x = x0 + math.sin((phase * beats + offset) * 2 * math.pi) * sway;
          // Brightest in the middle of the rise, gone at both ends.
          final fade = math.sin(travel * math.pi);
          if (fade <= 0.02) continue;
          canvas.save();
          canvas.translate(x, y);
          canvas.drawPath(
            _heart(r),
            Paint()
              ..color = const Color(0xFFFF4D6D)
                  .withValues(alpha: a * 0.85 * fade),
          );
          canvas.restore();
        }

      case FxPattern.bubbles:
        final n = (size.width * size.height / 20000).round().clamp(14, 110);
        for (var i = 0; i < n; i++) {
          final x0 = fixed.nextDouble() * size.width;
          final r = size.shortestSide * (0.012 + fixed.nextDouble() * 0.038);
          final offset = fixed.nextDouble();
          final sway = size.width * (0.008 + fixed.nextDouble() * 0.03);
          final travel = (phase + offset) % 1;
          final y = (1 - travel) * (size.height + r * 2) - r;
          final x = x0 + math.sin((phase * 2 + offset) * 2 * math.pi) * sway;
          final fade = math.sin(travel * math.pi);
          if (fade <= 0.02) continue;
          canvas.drawCircle(
            Offset(x, y),
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(0.8, r * 0.12)
              ..color = Colors.white.withValues(alpha: a * 0.5 * fade),
          );
          // The catch-light is what stops a ring reading as a plain circle.
          canvas.drawCircle(
            Offset(x - r * 0.32, y - r * 0.34),
            r * 0.17,
            Paint()..color = Colors.white.withValues(alpha: a * 0.6 * fade),
          );
        }
    }
  }

  /// Film dirt and a few worn scratches. Reseeded every frame by its caller,
  /// which is what makes dirt sit on the print rather than on the lens.
  static void _dust(
      Canvas canvas, Size size, math.Random rnd, double a) {
    final specks =
        (size.width * size.height / 5200).round().clamp(40, 1400);
    final p = Paint();
    for (var i = 0; i < specks; i++) {
      p.color =
          Colors.white.withValues(alpha: a * (0.2 + rnd.nextDouble() * 0.5));
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        size.shortestSide / 540 * (0.6 + rnd.nextDouble() * 1.4),
        p,
      );
    }
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
  }

  /// A heart of radius [r] centred on the origin.
  static Path _heart(double r) {
    final path = Path()..moveTo(0, r * 0.72);
    path.cubicTo(-r * 1.5, -r * 0.2, -r * 0.55, -r * 1.15, 0, -r * 0.35);
    path.cubicTo(r * 0.55, -r * 1.15, r * 1.5, -r * 0.2, 0, r * 0.72);
    return path..close();
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

  /// [phase] rolls the lines a whole cell over the loop, so a still frame
  /// and a running one are the same picture at rest and a drifting raster in
  /// motion.
  static void _scanlines(Canvas canvas, Size size, double a,
      [double phase = 0]) {
    final gap = math.max(1.5, size.height / 260);
    final slide = phase * gap * 2;
    final p = Paint()..color = Colors.black.withValues(alpha: a * 0.34);
    for (var y = slide - gap * 2; y < size.height; y += gap * 2) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, gap), p);
    }
  }
}
