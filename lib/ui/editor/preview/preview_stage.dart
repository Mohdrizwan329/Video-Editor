import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/layers.dart';
import '../../../data/models/project.dart';
import '../../../state/editor_controller.dart';
import '../../../state/preview_engine.dart';
import 'canvas_background.dart';
import 'clip_view.dart';
import 'effects_view.dart';
import 'layer_views.dart';
import 'transition_view.dart';

/// The player canvas: background, the clip under the playhead, then every
/// overlay lane — composited in the same order the exporter uses.
class PreviewStage extends StatelessWidget {
  const PreviewStage({
    super.key,
    this.interactive = true,
    this.watermarkFocus = false,
    this.markKey,
    this.onEditWatermark,
  });

  final bool interactive;

  /// True while the watermark panel is open: the mark is framed and can be
  /// dragged, pinched and twisted straight on the canvas.
  final bool watermarkFocus;

  /// Carried by the drawn mark so a tap can be tested against it. It is a
  /// [GlobalKey] owned by the screen, not made here: the stage rebuilds on
  /// every frame of playback and a key made in build would be a new key each
  /// time. Null wherever the mark is not editable — the fullscreen player.
  final GlobalKey? markKey;

  /// Tapping the mark on the canvas opens its panel, which is how a creator
  /// who can see their watermark gets to the controls for it without going
  /// back to the toolbar.
  final VoidCallback? onEditWatermark;

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
                        unopenable: engine.cannotOpen(clip.id, clip.path),
                      );
                // Inside a transition the exporter has both clips on screen
                // at once. So does this: without it the whole Transition tool
                // was invisible, and picking a look changed nothing the user
                // could see until the file came out.
                final stageView = _withTransition(
                  project: project,
                  engine: engine,
                  index: index,
                  time: time,
                  outgoing: clipView,
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
                              unopenable: engine.cannotOpen(clip.id, clip.path),
                            )
                          : clipView,
                    ),
                    ?stageView,
                    if (clip != null && clip.fadeGainAt(localTime) < 1)
                      Positioned.fill(
                        child: FadeVeil(gain: clip.fadeGainAt(localTime)),
                      ),
                    for (final pip in project.overlays)
                      if (pip.isVisibleAt(time))
                        OverlayLayerView(
                          layer: pip,
                          time: time,
                          canvasSize: canvasSize,
                          controller: engine.controllerFor(pip.id),
                          unopenable: engine.cannotOpen(pip.id, pip.path),
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
                    // Whole-frame texture and border sit above every lane and
                    // below the mark, in the exporter's own compositing order.
                    if (project.hasFx)
                      FxView(
                        preset: project.fx,
                        intensity: project.fxIntensity,
                        time: time,
                      ),
                    if (project.hasFrame) FrameView(preset: project.frame),
                    // Above every lane: the creator's own mark covers the
                    // whole timeline, exactly as the exporter composites it.
                    if (project.watermark.isReady)
                      WatermarkView(
                        mark: project.watermark,
                        canvasSize: canvasSize,
                        focused: watermarkFocus,
                        contentKey: markKey,
                      ),
                    if (project.clips.isEmpty) const _EmptyCanvas(),
                    if (interactive &&
                        !watermarkFocus &&
                        project.clips.isNotEmpty)
                      const _TransportBadge(),
                    if (interactive && !watermarkFocus)
                      _LayerGestureLayer(
                        canvasSize: canvasSize,
                        time: time,
                        markKey: markKey,
                        onEditWatermark: onEditWatermark,
                      ),
                    if (interactive && watermarkFocus)
                      _WatermarkGestureLayer(canvasSize: canvasSize),
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

/// The play mark in the middle of the canvas.
///
/// It says two things at once: that the preview is stopped, and that the
/// canvas itself is what starts it. It fades out of the way the moment
/// playback begins, and stands down while a layer is selected so it never
/// covers the handles the user is dragging.
class _TransportBadge extends StatelessWidget {
  const _TransportBadge();

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final busy = !editor.selection.isEmpty;
    return ValueListenableBuilder<bool>(
      valueListenable: editor.isPlaying,
      builder: (context, playing, _) {
        final show = !playing && !busy;
        return IgnorePointer(
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.34),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The clip's own fade to black.
///
/// The exporter lays `fade=t=in` / `fade=t=out` over the finished canvas —
/// letterbox bars and all — with every overlay lane composited on top
/// afterwards, so the veil sits between the two here as well.
class FadeVeil extends StatelessWidget {
  const FadeVeil({super.key, required this.gain});

  /// How much of the picture the fade leaves: 1 is untouched, 0 is black.
  final double gain;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: (1 - gain).clamp(0.0, 1.0)),
        ),
      );
}

/// Wraps the clip under the playhead in its outgoing transition when the
/// playhead is inside the overlap with the clip after it.
Widget? _withTransition({
  required Project project,
  required PreviewEngine engine,
  required int index,
  required Duration time,
  required Widget? outgoing,
}) {
  if (outgoing == null || index < 0 || index + 1 >= project.clips.length) {
    return outgoing;
  }
  final overlap = project.overlapAfter(index);
  if (overlap <= Duration.zero) return outgoing;
  final joinStart = project.clipStart(index + 1);
  if (time < joinStart) return outgoing;

  final next = project.clips[index + 1];
  return TransitionView(
    type: project.clips[index].transitionType,
    progress: (time - joinStart).inMicroseconds / overlap.inMicroseconds,
    outgoing: outgoing,
    incoming: ClipView(
      clip: next,
      controller: engine.controllerFor(next.id),
      localTime: time - joinStart,
      unopenable: engine.cannotOpen(next.id, next.path),
    ),
  );
}

class _EmptyCanvas extends StatelessWidget {
  const _EmptyCanvas();

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    // With a panel open on a short window the canvas can shrink to a strip.
    // The prompt drops its icon rather than drawing an overflow stripe.
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxHeight < r.dp(34) + r.sp(12) * 2 + 16;
        return Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: r.dp(12)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!tight) ...[
                  Icon(Icons.add_photo_alternate_outlined,
                      size: r.ic(34), color: AppColors.textFaint),
                  SizedBox(height: r.vp(8)),
                ],
                Text('Add media to begin',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: r.sp(12), color: AppColors.textFaint)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Direct manipulation of the selected overlay: drag to move, pinch to scale,
/// twist to rotate. Tapping empty canvas clears the selection.
class _LayerGestureLayer extends StatefulWidget {
  const _LayerGestureLayer({
    required this.canvasSize,
    required this.time,
    this.markKey,
    this.onEditWatermark,
  });

  final Size canvasSize;
  final Duration time;

  /// The drawn watermark's box, so a tap can be tested against it.
  final GlobalKey? markKey;
  final VoidCallback? onEditWatermark;

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

  /// Whether [global] landed on the watermark as it is drawn right now.
  ///
  /// The box is asked for its own transform rather than the position being
  /// worked out from the mark's numbers, so a rotated or scaled mark answers
  /// for the pixels it actually covers. The margin makes a one-line caption a
  /// target a finger can hit.
  bool _hitsWatermark(EditorController editor, Offset global) {
    if (widget.onEditWatermark == null) return false;
    if (!editor.project.watermark.isReady) return false;
    final box = widget.markKey?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    return (Offset.zero & box.size)
        .inflate(12)
        .contains(box.globalToLocal(global));
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) {
        // The mark comes first: it is drawn over every lane, so a tap that
        // lands on it is meant for it.
        if (_hitsWatermark(editor, details.globalPosition)) {
          widget.onEditWatermark!();
          return;
        }
        final kind = editor.selection.kind;
        if (kind == LaneKind.text ||
            kind == LaneKind.sticker ||
            kind == LaneKind.overlay) {
          editor.clearSelection();
          return;
        }
        // Nothing to let go of, so the canvas is the transport — the tap
        // every video player answers, and the one people reach for to stop
        // playback rather than hunting for the button under the frame.
        context.read<PreviewEngine>().toggle();
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


/// Direct manipulation of the watermark while its panel is open. It takes
/// over from [_LayerGestureLayer] so a drag cannot be stolen by whichever
/// layer happened to be selected before.
class _WatermarkGestureLayer extends StatefulWidget {
  const _WatermarkGestureLayer({required this.canvasSize});

  final Size canvasSize;

  @override
  State<_WatermarkGestureLayer> createState() => _WatermarkGestureLayerState();
}

class _WatermarkGestureLayerState extends State<_WatermarkGestureLayer> {
  double _startScale = 1;
  double _startRotation = 0;
  Offset _startPosition = Offset.zero;
  Offset _dragged = Offset.zero;
  bool _recorded = false;

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onScaleStart: (_) {
        final t = editor.project.watermark.transform;
        _startScale = t.scale;
        _startRotation = t.rotation;
        _startPosition = Offset(t.x, t.y);
        _dragged = Offset.zero;
        _recorded = false;
      },
      onScaleUpdate: (details) {
        _dragged += details.focalPointDelta;
        // Only the gesture that starts the drag goes on the undo stack, so a
        // single reposition is one undo step rather than hundreds.
        editor.setWatermark(record: !_recorded, (mark) {
          final t = mark.transform;
          // Clamped to the frame, not past it like a timeline layer: see
          // [Watermark.keepOnCanvas].
          t.x = (_startPosition.dx + _dragged.dx / widget.canvasSize.width)
              .clamp(0.0, 1.0);
          t.y = (_startPosition.dy + _dragged.dy / widget.canvasSize.height)
              .clamp(0.0, 1.0);
          if (details.pointerCount > 1) {
            t.scale = (_startScale * details.scale).clamp(0.1, 4.0);
            t.rotation = _startRotation + details.rotation;
          }
        });
        _recorded = true;
      },
      onScaleEnd: (_) => _recorded = false,
    );
  }
}
