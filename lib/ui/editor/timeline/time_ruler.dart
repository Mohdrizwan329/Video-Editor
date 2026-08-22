import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Time ruler with a tick interval chosen for the current zoom.
class TimeRuler extends StatelessWidget {
  const TimeRuler({
    super.key,
    required this.duration,
    required this.pixelsPerSecond,
    required this.width,
  });

  final Duration duration;
  final double pixelsPerSecond;
  final double width;

  /// The strip's fixed height — [TimelineView.heightFor] adds it up.
  static const double kHeight = 18;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: kHeight,
      child: CustomPaint(
        painter: _RulerPainter(
          seconds: duration.inMicroseconds / 1000000,
          pps: pixelsPerSecond,
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.seconds, required this.pps});

  final double seconds;
  final double pps;

  /// Pick the smallest interval whose labels will not collide.
  double get _interval {
    const candidates = [0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 300.0];
    for (final c in candidates) {
      if (c * pps >= 56) return c;
    }
    return 600;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final interval = _interval;
    final tick = Paint()
      ..color = AppColors.textFaint.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final minorTick = Paint()
      ..color = AppColors.textFaint.withValues(alpha: 0.25)
      ..strokeWidth = 1;

    for (var t = 0.0; t <= seconds + interval; t += interval) {
      final x = t * pps;
      if (x > size.width) break;
      canvas.drawLine(Offset(x, size.height - 6), Offset(x, size.height), tick);

      final label = _label(t);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(fontSize: 8.5, color: AppColors.textFaint),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 3, 1));

      // one midpoint tick between labels
      final mid = x + interval * pps / 2;
      if (mid <= size.width) {
        canvas.drawLine(
            Offset(mid, size.height - 3), Offset(mid, size.height), minorTick);
      }
    }
  }

  static String _label(double t) {
    if (t < 60) {
      return t % 1 == 0 ? '${t.toInt()}s' : '${t.toStringAsFixed(1)}s';
    }
    final m = (t ~/ 60);
    final s = (t % 60).round();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.seconds != seconds || old.pps != pps;
}
