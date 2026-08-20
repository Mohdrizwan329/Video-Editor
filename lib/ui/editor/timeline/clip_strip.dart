import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/duration_ext.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/project.dart';
import '../../../data/models/video_clip.dart';
import '../../../state/editor_controller.dart';
import 'filmstrip.dart';

/// The main video track: clips laid end to end, transition handles at each
/// boundary, trim grips on the selected clip and long-press reordering.
class ClipStrip extends StatefulWidget {
  const ClipStrip({
    super.key,
    required this.editor,
    required this.pixelsPerSecond,
    required this.onAddMedia,
    required this.onTransitionTap,
  });

  final EditorController editor;
  final double pixelsPerSecond;
  final VoidCallback onAddMedia;
  final void Function(int index) onTransitionTap;

  @override
  State<ClipStrip> createState() => _ClipStripState();
}

class _ClipStripState extends State<ClipStrip> {
  int? _draggingIndex;
  double _dragDx = 0;
  int? _dropIndex;

  Project get _project => widget.editor.project;
  double get _pps => widget.pixelsPerSecond;

  double _widthOf(VideoClip c) =>
      c.timelineDuration.inMicroseconds / 1000000 * _pps;

  @override
  Widget build(BuildContext context) {
    final clips = _project.clips;
    final selection = widget.editor.selection;

    return SizedBox(
      height: kVideoTrackHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < clips.length; i++)
                _clipTile(i, clips[i],
                    selected: selection.kind == LaneKind.video &&
                        selection.id == clips[i].id),
              _addButton(),
            ],
          ),
          for (var i = 0; i < clips.length - 1; i++) _transitionBadge(i),
        ],
      ),
    );
  }

  Widget _clipTile(int index, VideoClip clip, {required bool selected}) {
    final width = _widthOf(clip);
    final dragging = _draggingIndex == index;

    return Transform.translate(
      offset: Offset(dragging ? _dragDx : 0, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.editor.selectClip(index),
        onLongPressStart: (_) {
          HapticFeedback.mediumImpact();
          setState(() {
            _draggingIndex = index;
            _dragDx = 0;
            _dropIndex = index;
          });
        },
        onLongPressMoveUpdate: (d) {
          if (_draggingIndex == null) return;
          setState(() {
            _dragDx = d.offsetFromOrigin.dx;
            _dropIndex = _targetIndex(index, _dragDx);
          });
        },
        onLongPressEnd: (_) {
          final from = _draggingIndex;
          final to = _dropIndex;
          setState(() {
            _draggingIndex = null;
            _dragDx = 0;
            _dropIndex = null;
          });
          if (from != null && to != null && from != to) {
            widget.editor.reorderClip(from, to);
          }
        },
        child: Container(
          width: width,
          margin: const EdgeInsets.symmetric(horizontal: 0.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected
                  ? AppColors.accent
                  : dragging
                      ? AppColors.text.withValues(alpha: 0.6)
                      : AppColors.clipBorder,
              width: selected ? 2 : 0.8,
            ),
            boxShadow: dragging
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 8)
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Filmstrip(
                    clip: clip,
                    width: width,
                    height: kVideoTrackHeight),
                Positioned(
                  left: 3,
                  bottom: 2,
                  child: _badgeRow(clip),
                ),
                if (selected) ...[
                  _trimHandle(index, clip, left: true),
                  _trimHandle(index, clip, left: false),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badgeRow(VideoClip clip) {
    final badges = <Widget>[
      _badge(clip.timelineDuration.mmss),
      if (clip.speed != 1.0) _badge('${clip.speed.toStringAsFixed(clip.speed % 1 == 0 ? 0 : 1)}x'),
      if (clip.volume == 0 && !clip.isImage) _badge('🔇'),
      if (clip.reversed) _badge('◀'),
      if (clip.filterId != 'none') _badge('◆'),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final b in badges) ...[b, const SizedBox(width: 3)],
      ],
    );
  }

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 8, color: Colors.white)),
      );

  /// Grips on the selected clip. Dragging changes the trim window live and
  /// records a single undo entry per gesture.
  Widget _trimHandle(int index, VideoClip clip, {required bool left}) {
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => HapticFeedback.selectionClick(),
        onHorizontalDragUpdate: (d) {
          final deltaSource = Duration(
              microseconds:
                  (d.delta.dx / _pps * 1000000 * clip.speed).round());
          if (left) {
            widget.editor.trimClip(index,
                start: clip.trimStart + deltaSource, record: false);
          } else {
            widget.editor.trimClip(index,
                end: clip.trimEnd + deltaSource, record: false);
          }
        },
        child: Container(
          width: 13,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(left ? 3 : 0),
              right: Radius.circular(left ? 0 : 3),
            ),
          ),
          child: const Center(
            child: SizedBox(
              width: 2.5,
              height: 18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _transitionBadge(int index) {
    final clip = _project.clips[index];
    var x = 0.0;
    for (var i = 0; i <= index; i++) {
      x += _widthOf(_project.clips[i]) + 1;
    }
    final active = clip.transitionType != TransitionType.none;
    return Positioned(
      left: x - 11,
      top: kVideoTrackHeight / 2 - 11,
      child: GestureDetector(
        onTap: () => widget.onTransitionTap(index),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: active ? AppColors.accent : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: AppColors.background, width: 1.5),
          ),
          child: Icon(
            active ? clip.transitionType.icon : Icons.add,
            size: 12,
            color: active ? AppColors.onAccent : AppColors.textDim,
          ),
        ),
      ),
    );
  }

  Widget _addButton() {
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: GestureDetector(
        onTap: widget.onAddMedia,
        child: Container(
          width: 42,
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.divider),
          ),
          child: const Icon(Icons.add, size: 19, color: AppColors.text),
        ),
      ),
    );
  }

  /// Which slot the dragged clip would land in for the current offset.
  int _targetIndex(int from, double dx) {
    final clips = _project.clips;
    var target = from;
    var travelled = 0.0;
    if (dx > 0) {
      for (var i = from + 1; i < clips.length; i++) {
        travelled += _widthOf(clips[i]);
        if (dx > travelled - _widthOf(clips[i]) / 2) {
          target = i;
        } else {
          break;
        }
      }
    } else {
      for (var i = from - 1; i >= 0; i--) {
        travelled += _widthOf(clips[i]);
        if (-dx > travelled - _widthOf(clips[i]) / 2) {
          target = i;
        } else {
          break;
        }
      }
    }
    return target;
  }
}
