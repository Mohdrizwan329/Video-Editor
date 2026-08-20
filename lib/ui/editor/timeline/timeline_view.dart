import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/duration_ext.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/layers.dart';
import '../../../state/editor_controller.dart';
import 'clip_strip.dart';
import 'keyframe_markers.dart';
import 'lane_row.dart';
import 'time_ruler.dart';

/// The timeline: a fixed centre playhead with the track scrolling underneath,
/// pinch to zoom, and a lane per overlay type — the main editing surface.
class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.editor,
    required this.onAddMedia,
    required this.onTransitionTap,
  });

  final EditorController editor;
  final VoidCallback onAddMedia;
  final void Function(int index) onTransitionTap;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  final ScrollController _scroll = ScrollController();

  bool _userDriving = false;
  bool _programmatic = false;
  double _viewportWidth = 0;

  /// Live pointers, so a two-finger pinch can take over from scrolling.
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDistance;
  double _pinchStartPps = kDefaultPixelsPerSecond;
  Duration _pinchAnchor = Duration.zero;

  EditorController get _editor => widget.editor;
  double get _pps => _editor.pixelsPerSecond.value;

  @override
  void initState() {
    super.initState();
    _editor.position.addListener(_followPlayhead);
    _editor.pixelsPerSecond.addListener(_onZoomChanged);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _editor.position.removeListener(_followPlayhead);
    _editor.pixelsPerSecond.removeListener(_onZoomChanged);
    _scroll.dispose();
    super.dispose();
  }

  double _offsetFor(Duration t) => t.inMicroseconds / 1000000 * _pps;

  Duration _timeAt(double offset) =>
      Duration(microseconds: (offset / _pps * 1000000).round());

  void _followPlayhead() {
    if (_userDriving || !_scroll.hasClients) return;
    final target = _offsetFor(_editor.position.value);
    if ((_scroll.offset - target).abs() < 0.5) return;
    _programmatic = true;
    _scroll.jumpTo(target.clamp(
        _scroll.position.minScrollExtent, _scroll.position.maxScrollExtent));
    _programmatic = false;
  }

  void _onScroll() {
    if (_programmatic || !_scroll.hasClients) return;
    _editor.seek(_timeAt(_scroll.offset));
  }

  void _onZoomChanged() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _followPlayhead());
  }

  // ------------------------------------------------------------ pinch zoom

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      final list = _pointers.values.toList();
      _pinchStartDistance = (list[0] - list[1]).distance;
      _pinchStartPps = _pps;
      _pinchAnchor = _editor.position.value;
      setState(() {});
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length < 2 || _pinchStartDistance == null) return;
    final list = _pointers.values.toList();
    final distance = (list[0] - list[1]).distance;
    if (_pinchStartDistance! < 1) return;
    final factor = distance / _pinchStartDistance!;
    _editor.setZoom(_pinchStartPps * factor);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _programmatic = true;
      _scroll.jumpTo(_offsetFor(_pinchAnchor).clamp(
          _scroll.position.minScrollExtent, _scroll.position.maxScrollExtent));
      _programmatic = false;
    });
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) {
      _pinchStartDistance = null;
      if (mounted) setState(() {});
    }
  }

  bool get _pinching => _pointers.length >= 2;

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportWidth = constraints.maxWidth;
        final project = _editor.project;
        final total = project.totalDuration;
        final contentWidth = math.max(
            total.inMicroseconds / 1000000 * _pps, 1.0);
        final pad = _viewportWidth / 2;

        return Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is ScrollStartNotification) {
                    _userDriving = true;
                    if (_editor.isPlaying.value) {
                      _editor.isPlaying.value = false;
                    }
                  } else if (n is ScrollEndNotification) {
                    _userDriving = false;
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  physics: _pinching
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        TimeRuler(
                          duration: total,
                          pixelsPerSecond: _pps,
                          width: contentWidth,
                        ),
                        const SizedBox(height: 4),
                        ClipStrip(
                          editor: _editor,
                          pixelsPerSecond: _pps,
                          onAddMedia: widget.onAddMedia,
                          onTransitionTap: widget.onTransitionTap,
                        ),
                        _keyframeRow(contentWidth),
                        _lanes(contentWidth),
                        const SizedBox(height: 26),
                      ],
                    ),
                  ),
                ),
              ),
              _playhead(),
              _zoomBadge(),
            ],
          ),
        );
      },
    );
  }

  /// Keyframe diamonds for whatever is selected, aligned to its own start.
  Widget _keyframeRow(double width) {
    final target = _editor.keyframeTarget;
    if (target == null) return const SizedBox(height: 2);
    final (owner, local) = target;
    if (!owner.hasKeyframes) return const SizedBox(height: 2);
    final ownerStart = _editor.position.value - local;
    return Padding(
      padding: EdgeInsets.only(
          left: ownerStart.inMicroseconds / 1e6 * _pps, top: 2),
      child: KeyframeMarkers(
        owner: owner,
        pixelsPerSecond: _pps,
        width: width,
        onSeek: (t) => _editor.seek(ownerStart + t),
      ),
    );
  }

  Widget _lanes(double width) {
    final p = _editor.project;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LaneRow(
          editor: _editor,
          kind: LaneKind.overlay,
          layers: p.overlays,
          pixelsPerSecond: _pps,
          width: width,
          color: AppColors.trackOverlay,
          icon: Icons.picture_in_picture_alt,
          labelBuilder: (l) => 'Overlay',
        ),
        LaneRow(
          editor: _editor,
          kind: LaneKind.text,
          layers: p.texts,
          pixelsPerSecond: _pps,
          width: width,
          color: AppColors.trackText,
          icon: Icons.title,
          labelBuilder: (l) => (l as TextLayer).text,
        ),
        LaneRow(
          editor: _editor,
          kind: LaneKind.sticker,
          layers: p.stickers,
          pixelsPerSecond: _pps,
          width: width,
          color: AppColors.trackSticker,
          icon: Icons.emoji_emotions_outlined,
          labelBuilder: (l) => (l as StickerLayer).content,
        ),
        LaneRow(
          editor: _editor,
          kind: LaneKind.audio,
          layers: p.audios,
          pixelsPerSecond: _pps,
          width: width,
          color: AppColors.trackAudio,
          icon: Icons.music_note,
          labelBuilder: (l) => (l as AudioLayer).title,
        ),
      ],
    );
  }

  Widget _playhead() {
    return Positioned(
      left: _viewportWidth / 2 - 1,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Column(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: AppColors.playhead,
                borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(3), top: Radius.circular(1)),
              ),
            ),
            Expanded(
              child: Container(width: 2, color: AppColors.playhead),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zoomBadge() {
    if (!_pinching) return const SizedBox.shrink();
    return Positioned(
      right: 10,
      top: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('${_pps.round()} px/s',
            style: const TextStyle(fontSize: 10, color: Colors.white)),
      ),
    );
  }
}

/// Compact transport readout shown above the timeline.
class TimelineHeader extends StatelessWidget {
  const TimelineHeader({
    super.key,
    required this.editor,
    required this.onPlayPause,
    required this.onUndo,
    required this.onRedo,
    required this.onFullscreen,
    required this.onSnapToBeat,
    required this.onAddKeyframe,
  });

  final EditorController editor;
  final VoidCallback onPlayPause;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onFullscreen;
  final VoidCallback onSnapToBeat;
  final VoidCallback onAddKeyframe;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    // The row is a fixed set of buttons around a timecode. Scaling the button
    // boxes and letting the timecode flex is what keeps it inside a 320pt
    // phone and stops it looking sparse on a desktop window.
    final box = BoxConstraints(minWidth: r.dp(32), minHeight: r.vp(30));
    return SizedBox(
      height: math.max(r.vp(34), 32),
      child: Row(
        children: [
          SizedBox(width: r.dp(6)),
          ValueListenableBuilder<bool>(
            valueListenable: editor.isPlaying,
            builder: (context, playing, _) => IconButton(
              padding: EdgeInsets.zero,
              constraints: box,
              icon: Icon(playing ? Icons.pause : Icons.play_arrow,
                  size: r.ic(22)),
              color: AppColors.text,
              onPressed: onPlayPause,
            ),
          ),
          SizedBox(width: r.dp(4)),
          Expanded(
            child: ValueListenableBuilder<Duration>(
              valueListenable: editor.position,
              builder: (context, t, _) => Text(
                '${t.timecode}  /  ${editor.totalDuration.timecode}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: r.sp(11),
                  color: AppColors.textDim,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          if (editor.project.audios.any((a) => a.beats.isNotEmpty))
            IconButton(
              tooltip: 'Snap to beat',
              padding: EdgeInsets.zero,
              constraints: box,
              icon: Icon(Icons.graphic_eq, size: r.ic(17)),
              color: AppColors.textDim,
              onPressed: onSnapToBeat,
            ),
          if (!editor.selection.isEmpty)
            IconButton(
              tooltip: 'Add keyframe',
              padding: EdgeInsets.zero,
              constraints: box,
              icon: Transform.rotate(
                angle: 0.785,
                child: Icon(
                  editor.hasKeyframeAtPlayhead
                      ? Icons.square
                      : Icons.square_outlined,
                  size: r.ic(13),
                ),
              ),
              color: editor.hasKeyframeAtPlayhead
                  ? AppColors.accent
                  : AppColors.textDim,
              onPressed: onAddKeyframe,
            ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: box,
            icon: Icon(Icons.undo, size: r.ic(18)),
            color: editor.canUndo ? AppColors.text : AppColors.textFaint,
            onPressed: editor.canUndo ? onUndo : null,
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: box,
            icon: Icon(Icons.redo, size: r.ic(18)),
            color: editor.canRedo ? AppColors.text : AppColors.textFaint,
            onPressed: editor.canRedo ? onRedo : null,
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: box,
            icon: Icon(Icons.fullscreen, size: r.ic(20)),
            color: AppColors.text,
            onPressed: onFullscreen,
          ),
          SizedBox(width: r.dp(4)),
        ],
      ),
    );
  }
}
