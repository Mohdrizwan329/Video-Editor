import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Live chroma key for the preview.
///
/// The child is rasterized by [SnapshotWidget] and the snapshot is drawn
/// through a fragment shader, which is the only way to key a moving video
/// texture in Flutter. If the shader cannot be loaded the child renders
/// unkeyed rather than disappearing — a missing shader must not lose the
/// user's footage on screen.
class ChromaBox extends StatefulWidget {
  const ChromaBox({
    super.key,
    required this.keyColor,
    required this.similarity,
    required this.blend,
    required this.child,
  });

  final Color keyColor;

  /// 0..1 chroma distance treated as fully keyed.
  final double similarity;

  /// 0..1 soft edge beyond [similarity].
  final double blend;
  final Widget child;

  /// Compiled once per process; the program is stateless and reusable.
  static ui.FragmentProgram? _program;
  static bool _loadFailed = false;

  static Future<void> warmUp() async {
    if (_program != null || _loadFailed) return;
    try {
      _program =
          await ui.FragmentProgram.fromAsset('shaders/chroma_key.frag');
    } catch (e) {
      _loadFailed = true;
      debugPrint('chroma shader unavailable: $e');
    }
  }

  @override
  State<ChromaBox> createState() => _ChromaBoxState();
}

class _ChromaBoxState extends State<ChromaBox> {
  final SnapshotController _controller = SnapshotController(allowSnapshotting: true);
  late final _ChromaPainter _painter = _ChromaPainter();

  @override
  void initState() {
    super.initState();
    if (ChromaBox._program == null && !ChromaBox._loadFailed) {
      ChromaBox.warmUp().then((_) {
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
    final program = ChromaBox._program;
    if (program == null) return widget.child;

    _painter
      ..program = program
      ..keyColor = widget.keyColor
      ..similarity = widget.similarity
      ..blend = widget.blend;

    return SnapshotWidget(
      controller: _controller,
      // Permissive keeps a platform view from asserting; it just skips the
      // effect for that subtree instead of crashing the frame.
      mode: SnapshotMode.permissive,
      painter: _painter,
      child: widget.child,
    );
  }
}

class _ChromaPainter extends SnapshotPainter {
  ui.FragmentProgram? program;
  Color keyColor = const Color(0xFF00FF00);
  double similarity = 0.25;
  double blend = 0.1;

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
    // No snapshot available this frame: draw the child directly.
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
      _drawPlain(context, offset, size, image, sourceSize);
      return;
    }
    shader
      ..setFloat(0, sourceSize.width)
      ..setFloat(1, sourceSize.height)
      ..setFloat(2, keyColor.r)
      ..setFloat(3, keyColor.g)
      ..setFloat(4, keyColor.b)
      ..setFloat(5, similarity)
      ..setFloat(6, blend)
      ..setImageSampler(0, image);

    context.canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      // The snapshot is in physical pixels; scale back to logical space.
      ..scale(size.width / sourceSize.width, size.height / sourceSize.height)
      ..drawRect(
          Rect.fromLTWH(0, 0, sourceSize.width, sourceSize.height),
          Paint()..shader = shader)
      ..restore();
  }

  void _drawPlain(PaintingContext context, Offset offset, Size size,
      ui.Image image, Size sourceSize) {
    context.canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, sourceSize.width, sourceSize.height),
      Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height),
      Paint(),
    );
  }

  @override
  bool shouldRepaint(covariant _ChromaPainter old) =>
      old.program != program ||
      old.keyColor != keyColor ||
      old.similarity != similarity ||
      old.blend != blend;

  @override
  void dispose() {
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }
}
