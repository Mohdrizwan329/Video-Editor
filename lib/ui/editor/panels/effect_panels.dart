import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/layers.dart';
import '../../../data/models/video_clip.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_strip.dart';
import '../../widgets/panel_shell.dart';
import '../../widgets/app_slider.dart';

/// Shape mask with feather, size, position and invert — works on a main-track
/// clip or a PIP layer.
class MaskPanel extends StatefulWidget {
  const MaskPanel({
    super.key,
    required this.editor,
    required this.onClose,
    this.clipIndex,
    this.overlay,
  });

  final EditorController editor;
  final VoidCallback onClose;
  final int? clipIndex;
  final OverlayLayer? overlay;

  @override
  State<MaskPanel> createState() => _MaskPanelState();
}

class _MaskPanelState extends State<MaskPanel> {
  MaskShape get _shape =>
      widget.overlay?.maskShape ??
      widget.editor.project.clips[widget.clipIndex!].maskShape;

  double get _size =>
      widget.overlay?.maskSize ??
      widget.editor.project.clips[widget.clipIndex!].maskSize;

  double get _feather =>
      widget.overlay?.maskFeather ??
      widget.editor.project.clips[widget.clipIndex!].maskFeather;

  double get _x =>
      widget.overlay?.maskX ??
      widget.editor.project.clips[widget.clipIndex!].maskX;

  double get _y =>
      widget.overlay?.maskY ??
      widget.editor.project.clips[widget.clipIndex!].maskY;

  double get _rotation =>
      widget.overlay?.maskRotation ??
      widget.editor.project.clips[widget.clipIndex!].maskRotation;

  bool get _inverted =>
      widget.overlay?.maskInverted ??
      widget.editor.project.clips[widget.clipIndex!].maskInverted;

  /// One writer for both targets keeps the panel free of branching.
  void _apply(
    void Function(VideoClip) onClip,
    void Function(OverlayLayer) onOverlay, {
    bool record = true,
  }) {
    final overlay = widget.overlay;
    if (overlay != null) {
      widget.editor.updateLayer<OverlayLayer>(
        overlay,
        onOverlay,
        record: record,
      );
    } else {
      widget.editor.updateClip(widget.clipIndex!, onClip, record: record);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Mask',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      onReset: () => _apply(
        (c) {
          c.maskShape = MaskShape.none;
          c.maskSize = 0.6;
          c.maskFeather = 0.1;
          c.maskX = c.maskY = 0.5;
          c.maskRotation = 0;
          c.maskInverted = false;
        },
        (o) {
          o.maskShape = MaskShape.none;
          o.maskSize = 0.6;
          o.maskFeather = 0.1;
          o.maskX = o.maskY = 0.5;
          o.maskRotation = 0;
          o.maskInverted = false;
        },
      ),
      trailing: IconButton(
        tooltip: 'Invert',
        icon: Icon(
          _inverted ? Icons.invert_colors : Icons.invert_colors_off,
          size: 19,
        ),
        color: _inverted ? AppColors.accent : AppColors.textDim,
        onPressed: () => _apply(
          (c) => c.maskInverted = !c.maskInverted,
          (o) => o.maskInverted = !o.maskInverted,
        ),
      ),
      child: PanelBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            PanelStrip(
              gap: 10,
              runGap: 10,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final m in MaskShape.values)
                  GestureDetector(
                    onTap: () =>
                        _apply((c) => c.maskShape = m, (o) => o.maskShape = m),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 44,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _shape == m
                                ? AppColors.accent.withValues(alpha: 0.18)
                                : AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: _shape == m
                                  ? AppColors.accent
                                  : Colors.transparent,
                            ),
                          ),
                          child: Icon(
                            m.icon,
                            size: 18,
                            color: _shape == m
                                ? AppColors.accent
                                : AppColors.textDim,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          m.label,
                          style: TextStyle(
                            fontSize: 9,
                            color: _shape == m
                                ? AppColors.accent
                                : AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // No shape means no sliders, and then the sheet is the shape
            // strip and nothing else.
            if (_shape != MaskShape.none) ...[
              AppSlider(
                label: 'Size',
                value: _size,
                min: 0.05,
                max: 1.5,
                defaultValue: 0.6,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) => _apply(
                  (c) => c.maskSize = v,
                  (o) => o.maskSize = v,
                  record: false,
                ),
                onChangeEnd: (v) =>
                    _apply((c) => c.maskSize = v, (o) => o.maskSize = v),
              ),
              AppSlider(
                label: 'Feather',
                value: _feather,
                min: 0.005,
                max: 0.8,
                defaultValue: 0.1,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) => _apply(
                  (c) => c.maskFeather = v,
                  (o) => o.maskFeather = v,
                  record: false,
                ),
                onChangeEnd: (v) =>
                    _apply((c) => c.maskFeather = v, (o) => o.maskFeather = v),
              ),
              AppSlider(
                label: 'Position X',
                value: _x,
                min: 0,
                max: 1,
                defaultValue: 0.5,
                format: (v) => v.toStringAsFixed(2),
                onChanged: (v) => _apply(
                  (c) => c.maskX = v,
                  (o) => o.maskX = v,
                  record: false,
                ),
                onChangeEnd: (v) =>
                    _apply((c) => c.maskX = v, (o) => o.maskX = v),
              ),
              AppSlider(
                label: 'Position Y',
                value: _y,
                min: 0,
                max: 1,
                defaultValue: 0.5,
                format: (v) => v.toStringAsFixed(2),
                onChanged: (v) => _apply(
                  (c) => c.maskY = v,
                  (o) => o.maskY = v,
                  record: false,
                ),
                onChangeEnd: (v) =>
                    _apply((c) => c.maskY = v, (o) => o.maskY = v),
              ),
              AppSlider(
                label: 'Rotation',
                value: _rotation,
                min: -3.15,
                max: 3.15,
                bipolar: true,
                defaultValue: 0,
                format: (v) => '${(v * 57.2958).round()}°',
                onChanged: (v) => _apply(
                  (c) => c.maskRotation = v,
                  (o) => o.maskRotation = v,
                  record: false,
                ),
                onChangeEnd: (v) => _apply(
                  (c) => c.maskRotation = v,
                  (o) => o.maskRotation = v,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Green-screen key: pick the colour to remove, then tune the tolerance.
class ChromaPanel extends StatefulWidget {
  const ChromaPanel({
    super.key,
    required this.editor,
    required this.onClose,
    this.clipIndex,
    this.overlay,
  });

  final EditorController editor;
  final VoidCallback onClose;
  final int? clipIndex;
  final OverlayLayer? overlay;

  @override
  State<ChromaPanel> createState() => _ChromaPanelState();
}

class _ChromaPanelState extends State<ChromaPanel> {
  static const List<int> _presets = [
    0xFF00FF00,
    0xFF00B140,
    0xFF0000FF,
    0xFF0047AB,
    0xFFFF0000,
    0xFF000000,
    0xFFFFFFFF,
    0xFFFF00FF,
  ];

  // Branch on the target, not on its value: the key colour is itself
  // nullable, so `overlay?.chromaKeyColor ?? clips[clipIndex!]` fell through
  // to the clip lookup for every overlay that had no key picked yet — and
  // clipIndex is null on that path, which took the whole panel down.
  int? get _key => widget.overlay != null
      ? widget.overlay!.chromaKeyColor
      : widget.editor.project.clips[widget.clipIndex!].chromaKeyColor;

  double get _similarity =>
      widget.overlay?.chromaSimilarity ??
      widget.editor.project.clips[widget.clipIndex!].chromaSimilarity;

  double get _blend =>
      widget.overlay?.chromaBlend ??
      widget.editor.project.clips[widget.clipIndex!].chromaBlend;

  void _apply(
    void Function(VideoClip) onClip,
    void Function(OverlayLayer) onOverlay, {
    bool record = true,
  }) {
    final overlay = widget.overlay;
    if (overlay != null) {
      widget.editor.updateLayer<OverlayLayer>(
        overlay,
        onOverlay,
        record: record,
      );
    } else {
      widget.editor.updateClip(widget.clipIndex!, onClip, record: record);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    return PanelShell(
      title: 'Chroma key',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      onReset: () => _apply(
        (c) => c.chromaKeyColor = null,
        (o) => o.chromaKeyColor = null,
      ),
      child: PanelBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Text(
                'Key colour',
                style: TextStyle(fontSize: 11, color: AppColors.textDim),
              ),
            ),
            PanelStrip(
              gap: 9,
              runGap: 9,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final c in _presets)
                  GestureDetector(
                    onTap: () => _apply(
                      (v) => v.chromaKeyColor = c,
                      (o) => o.chromaKeyColor = c,
                    ),
                    child: Container(
                      width: 32,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: key == c
                              ? AppColors.accent
                              : AppColors.divider,
                          width: key == c ? 2.6 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (key != null) ...[
              AppSlider(
                label: 'Similarity',
                value: _similarity,
                min: 0.01,
                max: 0.8,
                defaultValue: 0.25,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) => _apply(
                  (c) => c.chromaSimilarity = v,
                  (o) => o.chromaSimilarity = v,
                  record: false,
                ),
                onChangeEnd: (v) => _apply(
                  (c) => c.chromaSimilarity = v,
                  (o) => o.chromaSimilarity = v,
                ),
              ),
              AppSlider(
                label: 'Edge blend',
                value: _blend,
                min: 0,
                max: 0.6,
                defaultValue: 0.1,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) => _apply(
                  (c) => c.chromaBlend = v,
                  (o) => o.chromaBlend = v,
                  record: false,
                ),
                onChangeEnd: (v) =>
                    _apply((c) => c.chromaBlend = v, (o) => o.chromaBlend = v),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 22, 16, 0),
                child: Text(
                  'Pick the colour to remove.',
                  style: TextStyle(fontSize: 12, color: AppColors.textFaint),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compositing mode for a PIP layer.
class BlendPanel extends StatelessWidget {
  const BlendPanel({
    super.key,
    required this.editor,
    required this.layer,
    required this.onClose,
  });

  final EditorController editor;
  final OverlayLayer layer;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Blend mode',
      onClose: onClose,
      onConfirm: onClose,
      onReset: () => editor.updateLayer<OverlayLayer>(
        layer,
        (o) => o.blendMode = BlendMode2.normal,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // Four to a line, the way the grid had them. The width is worked
          // out rather than delegated because a Wrap has no column count of
          // its own — and a Wrap is what lets the lines past the fold fall
          // into 'More options' instead of scrolling under a finger.
          const gap = 8.0;
          final tile = (box.maxWidth - 28 - gap * 3) / 4;
          return PanelStrip(
            gap: gap,
            runGap: gap,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            children: [
              for (final m in BlendMode2.values)
                GestureDetector(
                  onTap: () => editor.updateLayer<OverlayLayer>(
                    layer,
                    (o) => o.blendMode = m,
                  ),
                  child: Container(
                    width: tile,
                    height: tile / 2.2,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: layer.blendMode == m
                          ? AppColors.accent.withValues(alpha: 0.18)
                          : AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: layer.blendMode == m
                            ? AppColors.accent
                            : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      m.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: layer.blendMode == m
                            ? AppColors.accent
                            : AppColors.textDim,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
