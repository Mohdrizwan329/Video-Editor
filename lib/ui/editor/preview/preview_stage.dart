import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/layers.dart';
import '../../../state/editor_controller.dart';
import '../../../state/preview_engine.dart';
import 'canvas_background.dart';
import 'clip_view.dart';
import 'layer_views.dart';

/// The player canvas: background, the clip under the playhead, then every
/// overlay lane — composited in the same order the exporter uses.
class PreviewStage extends StatelessWidget {
  const PreviewStage({super.key, this.interactive = true});

  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final engine = context.watch<PreviewEngine>();
    final project = editor.project;

    return Center(
      child: AspectRatio(
        aspectRatio: project.canvasAspect,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final canvasSize =
                Size(constraints.maxWidth, constraints.maxHeight);
            return ValueListenableBuilder<Duration>(
              valueListenable: editor.position,
              builder: (context, time, _) {
                final index = project.clipIndexAt(time);
                final clip = index >= 0 ? project.clips[index] : null;
                final localTime =
                    index >= 0 ? time - project.clipStart(index) : Duration.zero;
                final clipView = clip == null
                    ? null
                    : ClipView(
                        clip: clip,
                        controller: engine.controllerFor(clip.id),
                        localTime: localTime,
                      );

                return Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    CanvasBackground(
                      style: project.background,
                      blurSource: clip != null && !clip.isImage
                          ? ClipView(
                              clip: clip,
                              controller: engine.controllerFor(clip.id),
                              showGrade: false,
                            )
                          : clipView,
                    ),
                    ?clipView,
                    for (final pip in project.overlays)
                      if (pip.isVisibleAt(time))
                        OverlayLayerView(
                          layer: pip,
                          time: time,
                          canvasSize: canvasSize,
                          controller: engine.controllerFor(pip.id),
                          selected: editor.selection
                              .matches(LaneKind.overlay, pip.id),
                        ),
                    for (final sticker in project.stickers)
                      if (sticker.isVisibleAt(time))
                        StickerLayerView(
                          layer: sticker,
                          time: time,
                          canvasSize: canvasSize,
                          selected: editor.selection
                              .matches(LaneKind.sticker, sticker.id),
                        ),
                    for (final text in project.texts)
                      if (text.isVisibleAt(time))
                        TextLayerView(
                          layer: text,
                          time: time,
                          canvasSize: canvasSize,
                          selected:
                              editor.selection.matches(LaneKind.text, text.id),
                        ),
                    if (project.clips.isEmpty) const _EmptyCanvas(),
                    if (interactive)
                      _LayerGestureLayer(canvasSize: canvasSize, time: time),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _EmptyCanvas extends StatelessWidget {
  const _EmptyCanvas();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 34, color: AppColors.textFaint),
          SizedBox(height: 8),
          Text('Add media to begin',
              style: TextStyle(fontSize: 12, color: AppColors.textFaint)),
        ],
      ),
    );
  }
}

/// Direct manipulation of the selected overlay: drag to move, pinch to scale,
/// twist to rotate. Tapping empty canvas clears the selection.
class _LayerGestureLayer extends StatefulWidget {
  const _LayerGestureLayer({required this.canvasSize, required this.time});

  final Size canvasSize;
  final Duration time;

  @override
  State<_LayerGestureLayer> createState() => _LayerGestureLayerState();
}

class _LayerGestureLayerState extends State<_LayerGestureLayer> {
  double _startScale = 1;
  double _startRotation = 0;
  Offset _startPosition = Offset.zero;
  Offset _dragged = Offset.zero;
  bool _recorded = false;

  LayerTransform? _transformOf(EditorController editor) {
    final sel = editor.selection;
    return switch (sel.kind) {
      LaneKind.text => editor.selectedText?.transform,
      LaneKind.sticker => editor.selectedSticker?.transform,
      LaneKind.overlay => editor.selectedOverlay?.transform,
      _ => null,
    };
  }

  TimelineLayer? _selectedLayer(EditorController editor) =>
      editor.selectedText ?? editor.selectedSticker ?? editor.selectedOverlay;

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final kind = editor.selection.kind;
        if (kind == LaneKind.text ||
            kind == LaneKind.sticker ||
            kind == LaneKind.overlay) {
          editor.clearSelection();
        }
      },
      onScaleStart: (_) {
        final t = _transformOf(editor);
        if (t == null) return;
        _startScale = t.scale;
        _startRotation = t.rotation;
        _startPosition = Offset(t.x, t.y);
        _dragged = Offset.zero;
        _recorded = false;
      },
      onScaleUpdate: (details) {
        final layer = _selectedLayer(editor);
        final t = _transformOf(editor);
        if (t == null || layer == null) return;
        _dragged += details.focalPointDelta;
        editor.updateLayer<TimelineLayer>(layer, (_) {
          t.x = (_startPosition.dx + _dragged.dx / widget.canvasSize.width)
              .clamp(-0.25, 1.25);
          t.y = (_startPosition.dy + _dragged.dy / widget.canvasSize.height)
              .clamp(-0.25, 1.25);
          if (details.pointerCount > 1) {
            t.scale = (_startScale * details.scale).clamp(0.05, 6.0);
            t.rotation = _startRotation + details.rotation;
          }
        }, record: !_recorded);
        _recorded = true;
      },
      onScaleEnd: (_) => _recorded = false,
    );
  }
}
