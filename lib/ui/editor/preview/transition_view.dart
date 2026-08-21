import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../data/models/enums.dart';

enum _Dir { left, right, up, down }

/// The shapes the incoming frame can be uncovered through.
enum _Shape {
  wipeLeft,
  wipeRight,
  wipeUp,
  wipeDown,
  diagTopLeft,
  diagTopRight,
  diagBottomLeft,
  diagBottomRight,
  horzOpen,
  horzClose,
  vertOpen,
  vertClose,
  sliceLeft,
  sliceRight,
  sliceUp,
  sliceDown,
  circleOpen,
  circleClose,
  rect,
  diamond,
  radial,
}

/// One frame of a transition: the two clips either side of the cut,
/// composited the way the exporter's `xfade` will composite them.
///
/// Without this the whole Transition tool was invisible — a user could pick
/// any of the fifty-odd looks and the canvas would show the outgoing clip
/// straight through the cut, with the choice only ever surfacing in the
/// exported file.
class TransitionView extends StatelessWidget {
  const TransitionView({
    super.key,
    required this.type,
    required this.progress,
    required this.outgoing,
    required this.incoming,
  });

  final TransitionType type;

  /// 0 at the first frame of the overlap, 1 at the last.
  final double progress;

  final Widget outgoing;
  final Widget incoming;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    return switch (type) {
      TransitionType.none => incoming,
      TransitionType.fade ||
      TransitionType.dissolve ||
      TransitionType.distance =>
        _stack(outgoing, Opacity(opacity: p, child: incoming)),
      TransitionType.blackFade => _dip(p, Colors.black),
      TransitionType.whiteFlash => _dip(p, Colors.white),
      TransitionType.greyFade => _dip(p, const Color(0xFF808080)),
      TransitionType.slideLeft || TransitionType.smoothLeft =>
        _push(p, _Dir.left),
      TransitionType.slideRight || TransitionType.smoothRight =>
        _push(p, _Dir.right),
      TransitionType.slideUp || TransitionType.smoothUp => _push(p, _Dir.up),
      TransitionType.slideDown || TransitionType.smoothDown =>
        _push(p, _Dir.down),
      TransitionType.coverLeft => _cover(p, _Dir.left),
      TransitionType.coverRight => _cover(p, _Dir.right),
      TransitionType.coverUp => _cover(p, _Dir.up),
      TransitionType.coverDown => _cover(p, _Dir.down),
      TransitionType.revealLeft => _reveal(p, _Dir.left),
      TransitionType.revealRight => _reveal(p, _Dir.right),
      TransitionType.wipeLeft || TransitionType.wind =>
        _through(p, _Shape.wipeLeft),
      TransitionType.wipeRight => _through(p, _Shape.wipeRight),
      TransitionType.wipeUp => _through(p, _Shape.wipeUp),
      TransitionType.wipeDown => _through(p, _Shape.wipeDown),
      TransitionType.wipeTopLeft || TransitionType.diagTopLeft =>
        _through(p, _Shape.diagTopLeft),
      TransitionType.wipeTopRight || TransitionType.diagTopRight =>
        _through(p, _Shape.diagTopRight),
      TransitionType.wipeBottomLeft || TransitionType.diagBottomLeft =>
        _through(p, _Shape.diagBottomLeft),
      TransitionType.wipeBottomRight || TransitionType.diagBottomRight =>
        _through(p, _Shape.diagBottomRight),
      TransitionType.horzOpen => _through(p, _Shape.horzOpen),
      TransitionType.horzClose => _through(p, _Shape.horzClose),
      TransitionType.vertOpen => _through(p, _Shape.vertOpen),
      TransitionType.vertClose => _through(p, _Shape.vertClose),
      TransitionType.hlSlice => _through(p, _Shape.sliceLeft),
      TransitionType.hrSlice => _through(p, _Shape.sliceRight),
      TransitionType.vuSlice => _through(p, _Shape.sliceUp),
      TransitionType.vdSlice => _through(p, _Shape.sliceDown),
      TransitionType.circleOpen || TransitionType.circleCrop =>
        _through(p, _Shape.circleOpen),
      TransitionType.circleClose => _through(p, _Shape.circleClose),
      TransitionType.rectCrop => _through(p, _Shape.rect),
      TransitionType.diamond => _through(p, _Shape.diamond),
      TransitionType.radial => _through(p, _Shape.radial),
      TransitionType.zoomIn => _zoom(p),
      TransitionType.squeezeH => _squeeze(p, horizontal: true),
      TransitionType.squeezeV => _squeeze(p, horizontal: false),
      TransitionType.pixelize => _soften(p),
    };
  }

  Widget _stack(Widget below, Widget above) => Stack(
        fit: StackFit.expand,
        children: [below, above],
      );

  /// Out through a colour and back in — the half-way frame is the colour
  /// itself, which is what makes a flash read as a flash.
  Widget _dip(double p, Color color) {
    final veil = 1 - (2 * p - 1).abs();
    return _stack(
      p < 0.5 ? outgoing : incoming,
      IgnorePointer(
        child: ColoredBox(color: color.withValues(alpha: veil)),
      ),
    );
  }

  /// Both frames travel: the outgoing leaves the way the incoming arrives.
  Widget _push(double p, _Dir dir) {
    final offset = _unit(dir);
    return _stack(
      FractionalTranslation(translation: offset * p, child: outgoing),
      FractionalTranslation(
        translation: -offset * (1 - p),
        child: incoming,
      ),
    );
  }

  Widget _cover(double p, _Dir dir) => _stack(
        outgoing,
        FractionalTranslation(
          translation: -_unit(dir) * (1 - p),
          child: incoming,
        ),
      );

  Widget _reveal(double p, _Dir dir) => _stack(
        incoming,
        FractionalTranslation(translation: _unit(dir) * p, child: outgoing),
      );

  Widget _through(double p, _Shape shape) => _stack(
        outgoing,
        ClipPath(
          clipper: _ShapeClipper(shape: shape, progress: p),
          child: incoming,
        ),
      );

  /// The incoming frame grows in, fading as it goes so the first frames do
  /// not read as a hard-edged card dropped on the picture.
  Widget _zoom(double p) => _stack(
        outgoing,
        Opacity(
          opacity: Curves.easeIn.transform(p),
          child: Transform.scale(scale: 0.3 + 0.7 * p, child: incoming),
        ),
      );

  Widget _squeeze(double p, {required bool horizontal}) => _stack(
        outgoing,
        Transform.scale(
          scaleX: horizontal ? p : 1,
          scaleY: horizontal ? 1 : p,
          child: incoming,
        ),
      );

  /// Pixelize has no cheap twin in Flutter; a blur that peaks at the cut
  /// carries the same "the picture breaks up and re-forms" reading.
  Widget _soften(double p) {
    final sigma = (1 - (2 * p - 1).abs()) * 14;
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.clamp,
      ),
      child: _stack(outgoing, Opacity(opacity: p, child: incoming)),
    );
  }

  /// The direction the outgoing frame leaves in, as a fraction of the canvas.
  Offset _unit(_Dir dir) => switch (dir) {
        _Dir.left => const Offset(-1, 0),
        _Dir.right => const Offset(1, 0),
        _Dir.up => const Offset(0, -1),
        _Dir.down => const Offset(0, 1),
      };
}

/// The growing window the incoming frame is seen through.
class _ShapeClipper extends CustomClipper<Path> {
  const _ShapeClipper({required this.shape, required this.progress});

  final _Shape shape;
  final double progress;

  /// How many bars a sliced transition breaks the frame into.
  static const int _slices = 8;

  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height;
    final p = progress;
    final path = Path();
    switch (shape) {
      case _Shape.wipeLeft:
        path.addRect(Rect.fromLTRB(w * (1 - p), 0, w, h));
      case _Shape.wipeRight:
        path.addRect(Rect.fromLTRB(0, 0, w * p, h));
      case _Shape.wipeUp:
        path.addRect(Rect.fromLTRB(0, h * (1 - p), w, h));
      case _Shape.wipeDown:
        path.addRect(Rect.fromLTRB(0, 0, w, h * p));
      case _Shape.diagTopLeft:
        path.addPath(_diagonal(size, p, fromLeft: true, fromTop: true),
            Offset.zero);
      case _Shape.diagTopRight:
        path.addPath(_diagonal(size, p, fromLeft: false, fromTop: true),
            Offset.zero);
      case _Shape.diagBottomLeft:
        path.addPath(_diagonal(size, p, fromLeft: true, fromTop: false),
            Offset.zero);
      case _Shape.diagBottomRight:
        path.addPath(_diagonal(size, p, fromLeft: false, fromTop: false),
            Offset.zero);
      case _Shape.horzOpen:
        // Curtains parting from the middle of the frame outwards.
        path.addRect(Rect.fromCenter(
            center: Offset(w / 2, h / 2), width: w, height: h * p));
      case _Shape.horzClose:
        path
          ..addRect(Rect.fromLTRB(0, 0, w, h * p / 2))
          ..addRect(Rect.fromLTRB(0, h - h * p / 2, w, h));
      case _Shape.vertOpen:
        path.addRect(Rect.fromCenter(
            center: Offset(w / 2, h / 2), width: w * p, height: h));
      case _Shape.vertClose:
        path
          ..addRect(Rect.fromLTRB(0, 0, w * p / 2, h))
          ..addRect(Rect.fromLTRB(w - w * p / 2, 0, w, h));
      case _Shape.sliceLeft:
      case _Shape.sliceRight:
        final band = h / _slices;
        for (var i = 0; i < _slices; i++) {
          final t = _staggered(p, i);
          final width = w * t;
          path.addRect(shape == _Shape.sliceRight
              ? Rect.fromLTWH(0, i * band, width, band)
              : Rect.fromLTWH(w - width, i * band, width, band));
        }
      case _Shape.sliceUp:
      case _Shape.sliceDown:
        final band = w / _slices;
        for (var i = 0; i < _slices; i++) {
          final t = _staggered(p, i);
          final height = h * t;
          path.addRect(shape == _Shape.sliceDown
              ? Rect.fromLTWH(i * band, 0, band, height)
              : Rect.fromLTWH(i * band, h - height, band, height));
        }
      case _Shape.circleOpen:
        final r = _corner(size) * p;
        path.addOval(Rect.fromCircle(center: Offset(w / 2, h / 2), radius: r));
      case _Shape.circleClose:
        // Everything except a circle that shrinks to nothing.
        final r = _corner(size) * (1 - p);
        path
          ..addRect(Rect.fromLTWH(0, 0, w, h))
          ..addOval(Rect.fromCircle(center: Offset(w / 2, h / 2), radius: r))
          ..fillType = PathFillType.evenOdd;
      case _Shape.rect:
        path.addRect(Rect.fromCenter(
            center: Offset(w / 2, h / 2), width: w * p, height: h * p));
      case _Shape.diamond:
        final rx = w * p, ry = h * p;
        path
          ..moveTo(w / 2, h / 2 - ry)
          ..lineTo(w / 2 + rx, h / 2)
          ..lineTo(w / 2, h / 2 + ry)
          ..lineTo(w / 2 - rx, h / 2)
          ..close();
      case _Shape.radial:
        // A hand sweeping round the clock from twelve.
        path
          ..moveTo(w / 2, h / 2)
          ..arcTo(
            Rect.fromCircle(
                center: Offset(w / 2, h / 2), radius: _corner(size)),
            -math.pi / 2,
            2 * math.pi * p,
            false,
          )
          ..close();
    }
    return path;
  }

  /// A half-plane sweeping in from one corner, wide enough to clear the far
  /// corner by the end of the transition.
  Path _diagonal(Size size, double p, {
    required bool fromLeft,
    required bool fromTop,
  }) {
    final w = size.width, h = size.height;
    final reach = (w + h) * p;
    final path = Path();
    final x = fromLeft ? 0.0 : w;
    final y = fromTop ? 0.0 : h;
    final sx = fromLeft ? 1.0 : -1.0;
    final sy = fromTop ? 1.0 : -1.0;
    path
      ..moveTo(x, y)
      ..lineTo(x + sx * reach, y)
      ..lineTo(x, y + sy * reach)
      ..close();
    return path;
  }

  /// Bar [i] of a sliced wipe starts a little after the bar before it, so the
  /// frame comes apart in a stagger rather than one straight edge.
  double _staggered(double p, int i) {
    const lead = 0.35;
    final start = lead * i / (_slices - 1);
    final span = 1 - lead;
    return ((p - start) / span).clamp(0.0, 1.0);
  }

  double _corner(Size size) =>
      math.sqrt(size.width * size.width + size.height * size.height) / 2;

  @override
  bool shouldReclip(covariant _ShapeClipper old) =>
      old.shape != shape || old.progress != progress;
}
