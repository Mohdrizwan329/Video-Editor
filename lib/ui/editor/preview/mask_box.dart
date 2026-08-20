import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/enums.dart';

/// Applies a feathered mask to whatever it wraps.
///
/// The gradient stops are computed from the same size/feather numbers the
/// renderer feeds FFmpeg's `geq` alpha expression, so the soft edge lands in
/// the same place in the export.
class MaskBox extends StatelessWidget {
  const MaskBox({
    super.key,
    required this.shape,
    required this.size,
    required this.feather,
    required this.x,
    required this.y,
    required this.rotation,
    required this.inverted,
    required this.child,
  });

  final MaskShape shape;

  /// Radius or half-width as a fraction of the box, 0..1.
  final double size;

  /// Soft edge width as a fraction of the box, 0..1.
  final double feather;
  final double x;
  final double y;
  final double rotation;
  final bool inverted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (shape == MaskShape.none) return child;

    if (shape == MaskShape.linear || shape == MaskShape.mirror) {
      return ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => _linearShader(rect),
        child: child,
      );
    }
    if (shape == MaskShape.circle) {
      return ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => _radialShader(rect),
        child: child,
      );
    }
    // Rectangle, heart and star are path shapes: clip, then feather the edge
    // with a second pass so the result still reads as a soft mask.
    return ClipPath(
      clipper: _ShapeClipper(shape, size, x, y, rotation, inverted),
      child: child,
    );
  }

  Shader _linearShader(Rect rect) {
    final soft = feather.clamp(0.01, 0.9);
    final mid = size.clamp(0.0, 1.0);
    final stops = <double>[
      (mid - soft / 2).clamp(0.0, 1.0),
      (mid + soft / 2).clamp(0.0, 1.0),
    ];
    final opaque = inverted ? Colors.transparent : Colors.white;
    final clear = inverted ? Colors.white : Colors.transparent;

    if (shape == MaskShape.mirror) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [clear, opaque, opaque, clear],
        stops: [
          (0.5 - mid / 2 - soft / 2).clamp(0.0, 1.0),
          (0.5 - mid / 2 + soft / 2).clamp(0.0, 1.0),
          (0.5 + mid / 2 - soft / 2).clamp(0.0, 1.0),
          (0.5 + mid / 2 + soft / 2).clamp(0.0, 1.0),
        ],
        transform: GradientRotation(rotation),
      ).createShader(rect);
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [opaque, clear],
      stops: stops.first <= stops.last ? stops : [stops.last, stops.first],
      transform: GradientRotation(rotation),
    ).createShader(rect);
  }

  Shader _radialShader(Rect rect) {
    final soft = feather.clamp(0.01, 0.9);
    final r = size.clamp(0.02, 1.5);
    final opaque = inverted ? Colors.transparent : Colors.white;
    final clear = inverted ? Colors.white : Colors.transparent;
    return RadialGradient(
      center: Alignment(x * 2 - 1, y * 2 - 1),
      radius: r,
      colors: [opaque, opaque, clear],
      stops: [0, (1 - soft).clamp(0.0, 0.99), 1],
    ).createShader(rect);
  }
}

class _ShapeClipper extends CustomClipper<Path> {
  _ShapeClipper(
      this.shape, this.size, this.x, this.y, this.rotation, this.inverted);

  final MaskShape shape;
  final double size;
  final double x;
  final double y;
  final double rotation;
  final bool inverted;

  @override
  Path getClip(Size s) {
    final cx = s.width * x;
    final cy = s.height * y;
    final r = math.min(s.width, s.height) * size / 2;

    var path = switch (shape) {
      MaskShape.rectangle => Path()
        ..addRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: r * 2.4, height: r * 1.6),
            Radius.circular(r * 0.08))),
      MaskShape.heart => _heart(r),
      MaskShape.star => _star(r),
      _ => Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)),
    };

    path = path.transform(
        (Matrix4.identity()..rotateZ(rotation)).storage);
    path = path.shift(Offset(cx, cy));

    if (inverted) {
      return Path.combine(
          PathOperation.difference, Path()..addRect(Offset.zero & s), path);
    }
    return path;
  }

  static Path _heart(double r) {
    final p = Path()..moveTo(0, r * 0.72);
    p.cubicTo(-r * 1.5, -r * 0.2, -r * 0.55, -r * 1.15, 0, -r * 0.35);
    p.cubicTo(r * 0.55, -r * 1.15, r * 1.5, -r * 0.2, 0, r * 0.72);
    return p..close();
  }

  static Path _star(double r) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = Offset(math.cos(a) * radius, math.sin(a) * radius);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  bool shouldReclip(covariant _ShapeClipper old) =>
      old.shape != shape ||
      old.size != size ||
      old.x != x ||
      old.y != y ||
      old.rotation != rotation ||
      old.inverted != inverted;
}
