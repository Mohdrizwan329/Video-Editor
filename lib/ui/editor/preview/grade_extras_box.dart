import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../data/models/adjustments.dart';

/// The second half of the live grade: gamma, the tone curve, sharpening,
/// noise reduction and grain.
///
/// [GradedBox] carries everything a 4x5 colour matrix can express. These
/// cannot be written as a matrix at all, so before this existed the six
/// sliders behind them moved and the picture did not — the work only showed
/// up in the exported file. The child is rasterized by [SnapshotWidget] and
/// redrawn through a fragment shader, the same route the chroma key takes.
/// A missing shader falls back to the child untouched: no effect is better
/// than no picture.
class GradeExtrasBox extends StatefulWidget {
  const GradeExtrasBox({
    super.key,
    required this.adjustments,
    required this.gamma,
    required this.seed,
    required this.child,
  });

  final Adjustments adjustments;

  /// From the [FilterPreset] underneath — the one grade value the matrix
  /// cannot carry either.
  final double gamma;

  /// Keeps two clips from graining in lockstep.
  final double seed;

  final Widget child;

  /// True when there is anything here for the shader to do.
  static bool wanted(Adjustments adjustments, double gamma) =>
      adjustments.hasShaderExtras || gamma != 1;

  static ui.FragmentProgram? _program;
  static bool _loadFailed = false;

  static Future<void> warmUp() async {
    if (_program != null || _loadFailed) return;
    try {
      _program =
          await ui.FragmentProgram.fromAsset('shaders/grade_extras.frag');
    } catch (e) {
      _loadFailed = true;
      debugPrint('grade shader unavailable: $e');
    }
  }

  @override
  State<GradeExtrasBox> createState() => _GradeExtrasBoxState();
}

class _GradeExtrasBoxState extends State<GradeExtrasBox> {
  final SnapshotController _controller =
      SnapshotController(allowSnapshotting: true);
  late final _GradeExtrasPainter _painter = _GradeExtrasPainter();

  @override
  void initState() {
    super.initState();
    if (GradeExtrasBox._program == null && !GradeExtrasBox._loadFailed) {
      GradeExtrasBox.warmUp().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _painter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final program = GradeExtrasBox._program;
    if (program == null) return widget.child;

    final adj = widget.adjustments;
    final (lo, mid, hi) = adj.curvePoints;
    _painter
      ..program = program
      ..hasCurves = adj.hasCurves
      ..curveLo = lo
      ..curveMid = mid
      ..curveHi = hi
      ..gamma = widget.gamma
      // The exporter's own scaling: `unsharp=…:amount`, `hqdn3d` strength and
      // `noise=alls=` out of the 0..255 range the filter counts in.
      ..sharpen = adj.sharpen * 1.5
      ..denoise = adj.denoise
      ..grain = adj.grain * 30 / 255
      ..seed = widget.seed;

    return SnapshotWidget(
      controller: _controller,
      // Permissive keeps a platform view from asserting; it skips the effect
      // for that subtree instead of losing the frame.
      mode: SnapshotMode.permissive,
      painter: _painter,
      child: widget.child,
    );
  }
}

class _GradeExtrasPainter extends SnapshotPainter {
  ui.FragmentProgram? program;
  bool hasCurves = false;
  double curveLo = 0;
  double curveMid = 0.5;
  double curveHi = 1;
  double gamma = 1;
  double sharpen = 0;
  double denoise = 0;
  double grain = 0;
  double seed = 0;

  ui.FragmentShader? _shader;
  ui.FragmentProgram? _shaderFor;

  ui.FragmentShader? _obtain() {
    final p = program;
    if (p == null) return null;
    if (_shader == null || _shaderFor != p) {
      _shader?.dispose();
      _shader = p.fragmentShader();
      _shaderFor = p;
    }
    return _shader;
  }

  @override
  void paint(PaintingContext context, Offset offset, Size size,
      PaintingContextCallback painter) {
    // No snapshot this frame: draw the child as it is.
    painter(context, offset);
  }

  @override
  void paintSnapshot(
    PaintingContext context,
    Offset offset,
    Size size,
    ui.Image image,
    Size sourceSize,
    double pixelRatio,
  ) {
    final shader = _obtain();
    if (shader == null) {
      context.canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, sourceSize.width, sourceSize.height),
        Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height),
        Paint(),
      );
      return;
    }
    shader
      ..setFloat(0, sourceSize.width)
      ..setFloat(1, sourceSize.height)
      ..setFloat(2, curveLo)
      ..setFloat(3, curveMid)
      ..setFloat(4, curveHi)
      ..setFloat(5, hasCurves ? 1 : 0)
      ..setFloat(6, gamma)
      ..setFloat(7, sharpen)
      ..setFloat(8, denoise)
      ..setFloat(9, grain)
      ..setFloat(10, seed)
      ..setImageSampler(0, image);

    context.canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      // The snapshot is in physical pixels; scale back to logical space.
      ..scale(size.width / sourceSize.width, size.height / sourceSize.height)
      ..drawRect(
        Rect.fromLTWH(0, 0, sourceSize.width, sourceSize.height),
        Paint()..shader = shader,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _GradeExtrasPainter old) =>
      old.program != program ||
      old.hasCurves != hasCurves ||
      old.curveLo != curveLo ||
      old.curveMid != curveMid ||
      old.curveHi != curveHi ||
      old.gamma != gamma ||
      old.sharpen != sharpen ||
      old.denoise != denoise ||
      old.grain != grain ||
      old.seed != seed;

  @override
  void dispose() {
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }
}
