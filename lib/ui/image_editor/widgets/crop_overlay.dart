import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Which part of the rectangle a drag has hold of.
enum CropGrip {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  left,
  right,
  top,
  bottom,
  move,
}

extension on CropGrip {
  bool get isCorner =>
      this == CropGrip.topLeft ||
      this == CropGrip.topRight ||
      this == CropGrip.bottomLeft ||
      this == CropGrip.bottomRight;

  bool get movesLeft =>
      this == CropGrip.topLeft ||
      this == CropGrip.bottomLeft ||
      this == CropGrip.left;

  bool get movesTop =>
      this == CropGrip.topLeft ||
      this == CropGrip.topRight ||
      this == CropGrip.top;
}

/// The crop rectangle laid over the photo: drag a corner or an edge to resize
/// it, drag the middle to move it.
///
/// It is sized to the picture exactly, so its own pixels and the photo's are
/// the same coordinate system — which is what lets a locked ratio be honoured
/// in plain widget pixels and reported back as fractions the renderer reads.
class CropOverlay extends StatefulWidget {
  const CropOverlay({
    super.key,
    required this.rect,
    required this.onChanged,
    required this.onCommit,
    this.aspect,
  });

  /// The crop window as fractions of the picture (0..1 on both axes).
  final Rect rect;

  /// Locked width / height, or null while the crop is free.
  final double? aspect;

  /// Fires continuously through a drag.
  final ValueChanged<Rect> onChanged;

  /// Fires once the finger lifts, for the undo stack.
  final VoidCallback onCommit;

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  CropGrip? _grip;
  Rect _startRect = Rect.zero;
  Offset _startPoint = Offset.zero;

  /// A finger is a good deal wider than the handle it is aiming at.
  static const double _touchSlop = 32;

  /// Never let the window close to nothing — there would be no handle left
  /// to grab to reopen it.
  static const double _minSide = 56;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final box = c.biggest;
        final rect = _toPixels(widget.rect, box);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            _grip = _gripAt(d.localPosition, rect);
            _startRect = rect;
            _startPoint = d.localPosition;
          },
          onPanUpdate: (d) {
            final grip = _grip;
            if (grip == null) return;
            final next = _resize(
              _startRect,
              d.localPosition - _startPoint,
              grip,
              box,
            );
            widget.onChanged(_toFractions(next, box));
          },
          onPanEnd: (_) {
            if (_grip == null) return;
            _grip = null;
            widget.onCommit();
          },
          onPanCancel: () => _grip = null,
          child: CustomPaint(painter: _CropPainter(rect), size: box),
        );
      },
    );
  }

  Rect _toPixels(Rect r, Size box) => Rect.fromLTRB(
    r.left * box.width,
    r.top * box.height,
    r.right * box.width,
    r.bottom * box.height,
  );

  Rect _toFractions(Rect r, Size box) => Rect.fromLTRB(
    box.width == 0 ? 0 : r.left / box.width,
    box.height == 0 ? 0 : r.top / box.height,
    box.width == 0 ? 1 : r.right / box.width,
    box.height == 0 ? 1 : r.bottom / box.height,
  );

  /// Corners win over edges, and the inside of the rectangle moves it.
  CropGrip _gripAt(Offset p, Rect r) {
    bool near(double a, double b) => (a - b).abs() <= _touchSlop;
    final onLeft = near(p.dx, r.left), onRight = near(p.dx, r.right);
    final onTop = near(p.dy, r.top), onBottom = near(p.dy, r.bottom);
    final insideX = p.dx >= r.left - _touchSlop && p.dx <= r.right + _touchSlop;
    final insideY = p.dy >= r.top - _touchSlop && p.dy <= r.bottom + _touchSlop;

    if (onLeft && onTop) return CropGrip.topLeft;
    if (onRight && onTop) return CropGrip.topRight;
    if (onLeft && onBottom) return CropGrip.bottomLeft;
    if (onRight && onBottom) return CropGrip.bottomRight;
    if (onLeft && insideY) return CropGrip.left;
    if (onRight && insideY) return CropGrip.right;
    if (onTop && insideX) return CropGrip.top;
    if (onBottom && insideX) return CropGrip.bottom;
    return CropGrip.move;
  }

  Rect _resize(Rect start, Offset delta, CropGrip grip, Size box) {
    if (grip == CropGrip.move) {
      final dx = delta.dx.clamp(-start.left, box.width - start.right);
      final dy = delta.dy.clamp(-start.top, box.height - start.bottom);
      return start.shift(Offset(dx, dy));
    }

    var l = start.left, t = start.top, r = start.right, b = start.bottom;
    switch (grip) {
      case CropGrip.topLeft:
        l += delta.dx;
        t += delta.dy;
      case CropGrip.topRight:
        r += delta.dx;
        t += delta.dy;
      case CropGrip.bottomLeft:
        l += delta.dx;
        b += delta.dy;
      case CropGrip.bottomRight:
        r += delta.dx;
        b += delta.dy;
      case CropGrip.left:
        l += delta.dx;
      case CropGrip.right:
        r += delta.dx;
      case CropGrip.top:
        t += delta.dy;
      case CropGrip.bottom:
        b += delta.dy;
      case CropGrip.move:
        break;
    }

    final aspect = widget.aspect;
    if (aspect == null || aspect <= 0) {
      // Free: every edge stops at the picture's border and at the minimum,
      // and no edge is allowed to cross the one opposite it.
      final minW = math.min(_minSide, box.width);
      final minH = math.min(_minSide, box.height);
      l = l.clamp(0.0, math.max(0.0, r - minW));
      t = t.clamp(0.0, math.max(0.0, b - minH));
      r = r.clamp(math.min(box.width, l + minW), box.width);
      b = b.clamp(math.min(box.height, t + minH), box.height);
      return Rect.fromLTRB(l, t, r, b);
    }

    // Locked: the dragged edge leads and the other follows the ratio, pinned
    // to whatever the drag is not allowed to move — the opposite corner for a
    // corner, the middle of the opposite axis for an edge.
    var w = math.max(1.0, r - l);
    var h = math.max(1.0, b - t);
    if (grip.isCorner) {
      w = math.max(w, h * aspect);
    } else if (grip == CropGrip.left || grip == CropGrip.right) {
      // width leads
    } else {
      w = h * aspect;
    }
    h = w / aspect;

    final anchor = _anchorOf(start, grip);
    final limit = _room(anchor, grip, box);
    final k = math.min(1.0, math.min(limit.width / w, limit.height / h));
    w *= k;
    h *= k;
    final minW = math.min(
      math.min(_minSide, limit.width),
      math.min(_minSide, limit.height) * aspect,
    );
    if (w < minW) {
      w = minW;
      h = w / aspect;
    }
    return _fromAnchor(anchor, w, h, grip);
  }

  /// The point a locked drag pivots around.
  Offset _anchorOf(Rect r, CropGrip grip) => switch (grip) {
    CropGrip.topLeft => r.bottomRight,
    CropGrip.topRight => r.bottomLeft,
    CropGrip.bottomLeft => r.topRight,
    CropGrip.bottomRight => r.topLeft,
    CropGrip.left => Offset(r.right, r.center.dy),
    CropGrip.right => Offset(r.left, r.center.dy),
    CropGrip.top => Offset(r.center.dx, r.bottom),
    CropGrip.bottom => Offset(r.center.dx, r.top),
    CropGrip.move => r.center,
  };

  /// How much room the rectangle has to grow into, measured from the anchor.
  Size _room(Offset a, CropGrip grip, Size box) {
    final width = grip.movesLeft ? a.dx : box.width - a.dx;
    final height = grip.movesTop ? a.dy : box.height - a.dy;
    return switch (grip) {
      CropGrip.left ||
      CropGrip.right => Size(width, 2 * math.min(a.dy, box.height - a.dy)),
      CropGrip.top ||
      CropGrip.bottom => Size(2 * math.min(a.dx, box.width - a.dx), height),
      _ => Size(math.max(1, width), math.max(1, height)),
    };
  }

  Rect _fromAnchor(Offset a, double w, double h, CropGrip grip) =>
      switch (grip) {
        CropGrip.topLeft => Rect.fromLTWH(a.dx - w, a.dy - h, w, h),
        CropGrip.topRight => Rect.fromLTWH(a.dx, a.dy - h, w, h),
        CropGrip.bottomLeft => Rect.fromLTWH(a.dx - w, a.dy, w, h),
        CropGrip.bottomRight => Rect.fromLTWH(a.dx, a.dy, w, h),
        CropGrip.left => Rect.fromLTWH(a.dx - w, a.dy - h / 2, w, h),
        CropGrip.right => Rect.fromLTWH(a.dx, a.dy - h / 2, w, h),
        CropGrip.top => Rect.fromLTWH(a.dx - w / 2, a.dy - h, w, h),
        CropGrip.bottom => Rect.fromLTWH(a.dx - w / 2, a.dy, w, h),
        CropGrip.move => Rect.fromCenter(center: a, width: w, height: h),
      };
}

/// Scrim outside the window, thirds grid inside it, and a handle on every
/// corner and edge.
class _CropPainter extends CustomPainter {
  const _CropPainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(rect),
    );
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), line);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), line);
    }
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    final grip = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final arm = math.min(22.0, math.min(rect.width, rect.height) / 3);
    void corner(Offset c, double dx, double dy) {
      canvas.drawLine(c, c.translate(arm * dx, 0), grip);
      canvas.drawLine(c, c.translate(0, arm * dy), grip);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);

    final bar = arm * 0.7;
    canvas.drawLine(
      Offset(rect.left, rect.center.dy - bar / 2),
      Offset(rect.left, rect.center.dy + bar / 2),
      grip,
    );
    canvas.drawLine(
      Offset(rect.right, rect.center.dy - bar / 2),
      Offset(rect.right, rect.center.dy + bar / 2),
      grip,
    );
    canvas.drawLine(
      Offset(rect.center.dx - bar / 2, rect.top),
      Offset(rect.center.dx + bar / 2, rect.top),
      grip,
    );
    canvas.drawLine(
      Offset(rect.center.dx - bar / 2, rect.bottom),
      Offset(rect.center.dx + bar / 2, rect.bottom),
      grip,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.rect != rect;
}
