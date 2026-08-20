import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The app's brand mark: a film strip with a play head cut out of it.
///
/// Drawn rather than shipped as an image so it stays crisp at every size the
/// app asks for, from the 34px app-bar tile to the 84px splash mark. The
/// geometry is expressed as fractions of [size], so one set of proportions
/// serves all of them.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 84, this.glow = false});

  final double size;

  /// Splash-sized uses lift the mark off the page; the app bar does not.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.violet,
        borderRadius: BorderRadius.circular(size * 0.29),
        boxShadow:
            glow ? AppColors.glow(AppColors.violet, opacity: 0.5) : null,
      ),
      child: CustomPaint(painter: const _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()..color = Colors.white;

    // Sprocket holes down both edges — the film-strip half of the mark.
    final holePaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    final holeW = s * 0.075;
    final holeH = s * 0.085;
    final radius = Radius.circular(s * 0.022);
    for (final cx in [s * 0.135, s * 0.865]) {
      for (final cy in [s * 0.235, s * 0.5, s * 0.765]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(cx, cy), width: holeW, height: holeH),
            radius,
          ),
          holePaint,
        );
      }
    }

    // Play head, centred in the gap between the two sprocket columns.
    final triW = s * 0.235;
    final triH = s * 0.27;
    final cx = s * 0.52;
    final cy = s * 0.5;
    final path = Path()
      ..moveTo(cx - triW / 2, cy - triH / 2)
      ..lineTo(cx + triW / 2, cy)
      ..lineTo(cx - triW / 2, cy + triH / 2)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}
