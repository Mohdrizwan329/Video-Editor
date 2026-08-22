import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/models/adjustments.dart';

/// The tone curve as a curve, rather than as three sliders called Low, Mid
/// and High.
///
/// The model has always held three control points — the exporter fits
/// `curves` to them and the preview shader walks the same three — but they
/// were shown as three separate bars, which is the one presentation that
/// hides what a tone curve is. Dragging the shape is the whole idea: the
/// user is shaping where the blacks sit, where the midtones bend and where
/// the highlights land, and they can see it.
class CurveEditor extends StatelessWidget {
  const CurveEditor({
    super.key,
    required this.adjustments,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final Adjustments adjustments;

  /// Called continuously while a point is dragged.
  final void Function(int point, double value) onChanged;

  /// Called once the finger lifts, so history records one step per drag.
  final void Function(int point, double value) onChangeEnd;

  /// Where each point can actually go, as (offset, span) in output space.
  ///
  /// Not the bounds [Adjustments.curvePoints] clamps to — those are wider
  /// than the sliders can reach. A point is driven by a value in -1..1 at a
  /// quarter scale, so the blacks climb a quarter and no further, and the
  /// highlights drop a quarter and no further. Drawing a handle anywhere
  /// else would let the user drag to a place the render never goes.
  static const List<(double, double)> ranges = [
    (0.0, 0.25), // blacks: lifted only, which is what a film fade does
    (0.25, 0.5), // midtones, either way from centre
    (0.75, 0.25), // highlights: pulled down only
  ];

  /// Output value of point [i] for the model value [v].
  static double outputFor(int i, double v) => switch (i) {
    0 => (v * 0.25).clamp(0.0, 0.4),
    1 => (0.5 + v * 0.25).clamp(0.1, 0.9),
    _ => (1 + v * 0.25).clamp(0.5, 1.0),
  };

  /// The model value that puts point [i] at output [y] — [outputFor] run
  /// backwards, so a drag lands exactly where the finger is.
  static double valueFor(int i, double y) => switch (i) {
    0 => (y / 0.25).clamp(-1.0, 1.0),
    1 => ((y - 0.5) / 0.25).clamp(-1.0, 1.0),
    _ => ((y - 1) / 0.25).clamp(-1.0, 1.0),
  };

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final side = r.dp(150);
    final values = [
      adjustments.curveLow,
      adjustments.curveMid,
      adjustments.curveHigh,
    ];
    return Center(
      child: SizedBox(
        width: side,
        height: side,
        child: _CurveSurface(
          values: values,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ),
    );
  }
}

class _CurveSurface extends StatefulWidget {
  const _CurveSurface({
    required this.values,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final List<double> values;
  final void Function(int, double) onChanged;
  final void Function(int, double) onChangeEnd;

  @override
  State<_CurveSurface> createState() => _CurveSurfaceState();
}

class _CurveSurfaceState extends State<_CurveSurface> {
  /// Which point the finger took hold of, so a drag that wanders nearer
  /// another point does not hand itself over mid-gesture.
  int? _held;

  /// The x of each control point across the box.
  static const List<double> _xs = [0.0, 0.5, 1.0];

  int _nearest(Offset local, Size size) {
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < 3; i++) {
      final p = Offset(
        _xs[i] * size.width,
        (1 - CurveEditor.outputFor(i, widget.values[i])) * size.height,
      );
      final d = (p - local).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  void _drag(Offset local, Size size, {required bool end}) {
    final i = _held;
    if (i == null) return;
    final y = (1 - local.dy / size.height).clamp(0.0, 1.0);
    final v = CurveEditor.valueFor(i, y);
    if (end) {
      widget.onChangeEnd(i, v);
    } else {
      widget.onChanged(i, v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            setState(() => _held = _nearest(d.localPosition, size));
            _drag(d.localPosition, size, end: false);
          },
          onPanUpdate: (d) => _drag(d.localPosition, size, end: false),
          onPanEnd: (_) {
            final i = _held;
            if (i != null) widget.onChangeEnd(i, widget.values[i]);
            setState(() => _held = null);
          },
          child: CustomPaint(
            painter: _CurvePainter(values: widget.values, held: _held),
          ),
        );
      },
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({required this.values, required this.held});

  final List<double> values;
  final int? held;

  static const List<double> _xs = [0.0, 0.5, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = BorderRadius.circular(10);

    canvas.drawRRect(
      radius.toRRect(rect),
      Paint()..color = AppColors.surfaceHigh,
    );

    // A four-square grid, and the untouched diagonal behind the curve so the
    // shape reads as a departure from something.
    final grid = Paint()
      ..color = AppColors.stroke
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final t = i / 4;
      canvas.drawLine(
        Offset(t * size.width, 0),
        Offset(t * size.width, size.height),
        grid,
      );
      canvas.drawLine(
        Offset(0, t * size.height),
        Offset(size.width, t * size.height),
        grid,
      );
    }
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      Paint()
        ..color = AppColors.stroke
        ..strokeWidth = 1.5,
    );

    final points = [
      for (var i = 0; i < 3; i++)
        Offset(
          _xs[i] * size.width,
          (1 - CurveEditor.outputFor(i, values[i])) * size.height,
        ),
    ];

    // Straight between the points, which is exactly what the preview shader
    // interpolates — drawing a spline here would promise a shape the render
    // does not make.
    canvas.drawPath(
      Path()
        ..moveTo(points[0].dx, points[0].dy)
        ..lineTo(points[1].dx, points[1].dy)
        ..lineTo(points[2].dx, points[2].dy),
      Paint()
        ..color = AppColors.accent
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    for (var i = 0; i < 3; i++) {
      final p = points[i];
      final on = held == i;
      canvas.drawCircle(p, on ? 9 : 7, Paint()..color = AppColors.surface);
      canvas.drawCircle(
        p,
        on ? 9 : 7,
        Paint()
          ..color = AppColors.accent
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.held != held ||
      old.values[0] != values[0] ||
      old.values[1] != values[1] ||
      old.values[2] != values[2];
}
