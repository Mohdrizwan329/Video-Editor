import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/utils/constants.dart';
import '../data/models/enums.dart';
import '../data/models/keyframe.dart';
import '../data/models/layers.dart';
import '../data/models/project.dart';
import '../data/models/template.dart';
import '../data/models/video_clip.dart';
import '../data/models/watermark.dart';
import '../data/services/media_library.dart';
import '../data/repositories/project_repository.dart';
import '../data/services/media_probe.dart';
import 'history.dart';
import 'selection.dart';

/// Owns the project being edited: every mutation, the playhead, the selection
/// and the undo stack live here. Widgets listen to this and to the two hot
/// [ValueNotifier]s ([position], [isPlaying]) so a moving playhead never
/// rebuilds the toolbars.
class EditorController extends ChangeNotifier {
  EditorController(this._project);

  Project _project;
  Project get project => _project;

  final EditHistory _history = EditHistory();
  final ProjectRepository _repo = ProjectRepository.instance;

  /// Playhead, updated many times per second by the preview engine.
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> isPlaying = ValueNotifier(false);

  /// Timeline zoom in pixels per second.
  final ValueNotifier<double> pixelsPerSecond = ValueNotifier(
    kDefaultPixelsPerSecond,
  );

  EditorSelection _selection = const EditorSelection.none();
  EditorSelection get selection => _selection;

  Timer? _saveTimer;
  bool _busy = false;
  String? _busyMessage;

  bool get isBusy => _busy;
  String? get busyMessage => _busyMessage;

  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;

  Duration get totalDuration => _project.totalDuration;

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    position.dispose();
    isPlaying.dispose();
    pixelsPerSecond.dispose();
    super.dispose();
  }

  /// The renders this controller kicks off — reverse, freeze, extract, the
  /// cutout pass — outlive the screen when the user walks away mid-pass, and
  /// each of them reports back when it lands. Reporting to a controller that
  /// is already gone is what raises 'used after being disposed', so the
  /// notification is dropped rather than the caller having to remember.
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  // ------------------------------------------------------------- plumbing

  /// Wrap every mutation so undo, autosave and notification stay in sync.
  void edit(void Function() action, {bool record = true}) {
    if (record) _history.push(_project.deepCopy());
    action();
    _clampPosition();
    _scheduleSave();
    notifyListeners();
  }

  void setBusy(String? message) {
    _busy = message != null;
    _busyMessage = message;
    notifyListeners();
  }

  void undo() {
    final p = _history.undo(_project);
    if (p == null) return;
    _project = p;
    _selection = const EditorSelection.none();
    _clampPosition();
    _scheduleSave();
    notifyListeners();
  }

  void redo() {
    final p = _history.redo(_project);
    if (p == null) return;
    _project = p;
    _selection = const EditorSelection.none();
    _clampPosition();
    _scheduleSave();
    notifyListeners();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(kAutosaveDelay, saveNow);
  }

  Future<void> saveNow() async {
    _project.coverPath ??= _project.clips.isNotEmpty
        ? _project.clips.first.thumbnailPath
        : null;
    await _repo.save(_project);
  }

  void _clampPosition() {
    final total = totalDuration;
    if (position.value > total) position.value = total;
    if (position.value < Duration.zero) position.value = Duration.zero;
  }

  // ------------------------------------------------------------ selection

  void select(LaneKind kind, String id, {int? index}) {
    _selection = EditorSelection(kind: kind, id: id, index: index);
    notifyListeners();
  }

  void selectClip(int index) {
    if (index < 0 || index >= _project.clips.length) return;
    _selection = EditorSelection(
      kind: LaneKind.video,
      id: _project.clips[index].id,
      index: index,
    );
    notifyListeners();
  }

  void clearSelection() {
    if (_selection.isEmpty) return;
    _selection = const EditorSelection.none();
    notifyListeners();
  }

  VideoClip? get selectedClip {
    if (_selection.kind != LaneKind.video) return null;
    return _project.clips.firstWhereOrNullById(_selection.id);
  }

  int get selectedClipIndex =>
      _project.clips.indexWhere((c) => c.id == _selection.id);

  TextLayer? get selectedText => _selection.kind == LaneKind.text
      ? _project.texts.where((t) => t.id == _selection.id).firstOrNull
      : null;

  StickerLayer? get selectedSticker => _selection.kind == LaneKind.sticker
      ? _project.stickers.where((t) => t.id == _selection.id).firstOrNull
      : null;

  OverlayLayer? get selectedOverlay => _selection.kind == LaneKind.overlay
      ? _project.overlays.where((t) => t.id == _selection.id).firstOrNull
      : null;

  AudioLayer? get selectedAudio => _selection.kind == LaneKind.audio
      ? _project.audios.where((t) => t.id == _selection.id).firstOrNull
      : null;

  TimelineLayer? get selectedLayer =>
      selectedText ?? selectedSticker ?? selectedOverlay ?? selectedAudio;

  // ------------------------------------------------------------- playhead

  void seek(Duration to) {
    final total = totalDuration;
    var t = to;
    if (t < Duration.zero) t = Duration.zero;
    if (t > total) t = total;
    position.value = t;
  }

  void setZoom(double pps) {
    pixelsPerSecond.value = pps.clamp(kMinPixelsPerSecond, kMaxPixelsPerSecond);
  }

  // ---------------------------------------------------------- main track

  /// Brings a picked file into the app's own storage and returns its new
  /// path.
  ///
  /// A gallery path is not a promise. The user can delete the photo, Android
  /// can evict the cache copy the picker hands over for a cloud item, and a
  /// project pointing at either opens black — every tool then acts on a frame
  /// that is not there, which is what "nothing works any more" looks like
  /// from the outside. One copy at import is what keeps a project working,
  /// the same thing the watermark already does.
  ///
  /// A file that is already ours is left where it is, and a copy that fails —
  /// a full disk — falls back to the original rather than losing the import.
  Future<String> _keep(String sourcePath) async {
    try {
      final dir = await _repo.mediaDir();
      if (sourcePath.startsWith(dir.path)) return sourcePath;
      return await MediaLibrary.instance.materialise(sourcePath, dir);
    } catch (e) {
      debugPrint('import: keeping $sourcePath where it is ($e)');
      return sourcePath;
    }
  }

  Future<void> addMedia(List<String> paths, {int? at}) async {
    setBusy('Importing ${paths.length} item${paths.length == 1 ? '' : 's'}');
    final clips = <VideoClip>[];
    for (final source in paths) {
      final path = await _keep(source);
      final info = await MediaProbe.probe(path);
      clips.add(
        VideoClip(
          path: path,
          isImage: info.isImage,
          hasAudio: info.hasAudio,
          sourceDuration: info.duration,
          sourceWidth: info.displayWidth,
          sourceHeight: info.displayHeight,
        ),
      );
    }
    setBusy(null);
    edit(() {
      final index = at ?? _project.clips.length;
      _project.clips.insertAll(index.clamp(0, _project.clips.length), clips);
    });
  }

  /// Cut the clip under the playhead in two at the exact playhead frame.
  bool splitAtPlayhead() {
    final t = position.value;
    final index = _project.clipIndexAt(t);
    if (index < 0) return false;
    final clip = _project.clips[index];
    final localOffset = t - _project.clipStart(index);
    if (localOffset <= kMinClipDuration ||
        clip.timelineDuration - localOffset <= kMinClipDuration) {
      return false;
    }
    edit(() {
      final cutInSource = Duration(
        microseconds:
            clip.trimStart.inMicroseconds +
            (localOffset.inMicroseconds * clip.speed).round(),
      );
      final right = clip.copyWith()
        ..trimStart = cutInSource
        ..trimEnd = clip.trimEnd
        ..transitionType = clip.transitionType
        ..transitionDuration = clip.transitionDuration;
      clip.trimEnd = cutInSource;
      clip.transitionType = TransitionType.none;
      _project.clips.insert(index + 1, right);
      _selection = EditorSelection(
        kind: LaneKind.video,
        id: right.id,
        index: index + 1,
      );
    });
    return true;
  }

  void deleteClip(int index) {
    if (index < 0 || index >= _project.clips.length) return;
    edit(() {
      _project.clips.removeAt(index);
      _selection = const EditorSelection.none();
    });
  }

  /// Rebuild one clip as the run of segments [keep] describes, in source
  /// time. Used by AI Cut, which works out which stretches are worth keeping
  /// and hands the rest back as a single edit the user can undo in one step.
  ///
  /// Segments shorter than [kMinClipDuration] are dropped rather than added
  /// as clips the timeline cannot show. Returns how many clips replaced the
  /// original, or 0 when nothing usable was left.
  int replaceClipWithSegments(int index, List<(Duration, Duration)> keep) {
    if (index < 0 || index >= _project.clips.length) return 0;
    final source = _project.clips[index];
    final speed = source.speed;
    final usable = [
      for (final (from, to) in keep)
        if ((to - from).inMicroseconds / speed >=
            kMinClipDuration.inMicroseconds)
          (from, to),
    ];
    if (usable.isEmpty) return 0;
    edit(() {
      final rebuilt = <VideoClip>[];
      for (var i = 0; i < usable.length; i++) {
        final (from, to) = usable[i];
        final part = source.copyWith()
          ..trimStart = from
          ..trimEnd = to
          // Only the last piece keeps the transition into whatever followed;
          // the joins this cut created are hard cuts, which is the point.
          ..transitionType = i == usable.length - 1
              ? source.transitionType
              : TransitionType.none
          ..transitionDuration = source.transitionDuration;
        rebuilt.add(part);
      }
      _project.clips.removeAt(index);
      _project.clips.insertAll(index, rebuilt);
      _selection = EditorSelection(
        kind: LaneKind.video,
        id: rebuilt.first.id,
        index: index,
      );
    });
    return usable.length;
  }

  void duplicateClip(int index) {
    if (index < 0 || index >= _project.clips.length) return;
    edit(() {
      final copy = _project.clips[index].copyWith();
      _project.clips.insert(index + 1, copy);
      _selection = EditorSelection(
        kind: LaneKind.video,
        id: copy.id,
        index: index + 1,
      );
    });
  }

  void reorderClip(int from, int to) {
    if (from == to) return;
    edit(() {
      final c = _project.clips.removeAt(from);
      _project.clips.insert(to.clamp(0, _project.clips.length), c);
    });
  }

  /// Live trim: called continuously while a handle is dragged, so it only
  /// records history on the first call of a gesture.
  void trimClip(
    int index, {
    Duration? start,
    Duration? end,
    bool record = false,
  }) {
    if (index < 0 || index >= _project.clips.length) return;
    final clip = _project.clips[index];
    edit(record: record, () {
      if (start != null) {
        final maxStart = clip.trimEnd - kMinClipDuration;
        clip.trimStart = start.clamp(Duration.zero, maxStart);
      }
      if (end != null) {
        final minEnd = clip.trimStart + kMinClipDuration;
        clip.trimEnd = end.clamp(minEnd, clip.sourceDuration);
      }
    });
  }

  void setClipDuration(int index, Duration d) {
    final clip = _project.clips[index];
    edit(() {
      if (clip.isImage) {
        clip.sourceDuration = d;
        clip.trimStart = Duration.zero;
        clip.trimEnd = d;
      } else {
        clip.trimEnd = (clip.trimStart + d).clamp(
          clip.trimStart + kMinClipDuration,
          clip.sourceDuration,
        );
      }
    });
  }

  void updateClip(
    int index,
    void Function(VideoClip) mutate, {
    bool record = true,
  }) {
    if (index < 0 || index >= _project.clips.length) return;
    edit(record: record, () => mutate(_project.clips[index]));
  }

  void applyToAllClips(void Function(VideoClip) mutate) {
    edit(() {
      for (final c in _project.clips) {
        mutate(c);
      }
    });
  }

  void setTransition(int index, TransitionType type, Duration duration) {
    if (index < 0 || index >= _project.clips.length - 1) return;
    edit(() {
      _project.clips[index]
        ..transitionType = type
        ..transitionDuration = duration;
    });
  }

  /// Freeze the frame under the playhead into a still image clip.
  Future<void> freezeFrame(int index, String framePath) async {
    edit(() {
      final freeze = VideoClip(
        path: framePath,
        isImage: true,
        hasAudio: false,
        sourceDuration: const Duration(seconds: 3),
        sourceWidth: _project.clips[index].sourceWidth,
        sourceHeight: _project.clips[index].sourceHeight,
      );
      _project.clips.insert(index + 1, freeze);
    });
  }

  // --------------------------------------------------------------- layers

  /// How far apart two overlays dropped on the same frame are placed.
  static const double _kDropStep = 0.09;

  /// A spot on the canvas that nothing already on screen is sitting on.
  ///
  /// Every new overlay is born in the middle of the frame, so a second one
  /// added over the first landed exactly on top of it: two 'Tap to edit'
  /// texts drawn glyph over glyph, which reads as one smeared line rather
  /// than as two layers. This steps the newcomer down the frame — and up,
  /// once the room below is taken — until it is somewhere the user can see
  /// it and grab it.
  double _freeSpot(Iterable<LayerTransform> taken) {
    bool free(double y) =>
        taken.every((t) => (t.y - y).abs() >= _kDropStep / 2);
    if (free(0.5)) return 0.5;
    for (var n = 1; n <= 4; n++) {
      for (final y in [0.5 + _kDropStep * n, 0.5 - _kDropStep * n]) {
        if (y >= 0.12 && y <= 0.88 && free(y)) return y;
      }
    }
    // Past a stack of nine the frame has no clear room left; the middle is
    // still where the user is looking.
    return 0.5;
  }

  TextLayer addText({String? text}) {
    final at = position.value;
    final layer = TextLayer(
      start: at,
      duration: const Duration(seconds: 3),
      text: text ?? 'Tap to edit',
    );
    layer.transform.y = _freeSpot(_project.texts
        .where((t) => t.isVisibleAt(at))
        .map((t) => t.transform));
    edit(() {
      _project.texts.add(layer);
      _selection = EditorSelection(kind: LaneKind.text, id: layer.id);
    });
    return layer;
  }

  StickerLayer addSticker(String content, {bool isEmoji = true}) {
    final at = position.value;
    final layer = StickerLayer(
      start: at,
      duration: const Duration(seconds: 3),
      content: content,
      isEmoji: isEmoji,
    );
    layer.transform.y = _freeSpot(_project.stickers
        .where((s) => s.isVisibleAt(at))
        .map((s) => s.transform));
    edit(() {
      _project.stickers.add(layer);
      _selection = EditorSelection(kind: LaneKind.sticker, id: layer.id);
    });
    return layer;
  }

  Future<OverlayLayer?> addOverlay(String source) async {
    setBusy('Adding overlay');
    final path = await _keep(source);
    final info = await MediaProbe.probe(path);
    setBusy(null);
    final layer = OverlayLayer(
      start: position.value,
      duration: info.duration > const Duration(seconds: 10)
          ? const Duration(seconds: 10)
          : info.duration,
      path: path,
      isImage: info.isImage,
      hasAudio: info.hasAudio,
      sourceDuration: info.duration,
      sourceWidth: info.displayWidth,
      sourceHeight: info.displayHeight,
    );
    edit(() {
      _project.overlays.add(layer);
      _selection = EditorSelection(kind: LaneKind.overlay, id: layer.id);
    });
    return layer;
  }

  Future<AudioLayer?> addAudio(
    String source, {
    AudioKind kind = AudioKind.music,
    String? title,
  }) async {
    setBusy('Loading audio');
    final path = await _keep(source);
    final info = await MediaProbe.probe(path);
    setBusy(null);
    final remaining = totalDuration - position.value;
    final take = info.duration < remaining || remaining <= Duration.zero
        ? info.duration
        : remaining;
    final layer = AudioLayer(
      start: position.value,
      duration: take <= Duration.zero ? info.duration : take,
      path: path,
      title: title ?? path.split('/').last,
      sourceDuration: info.duration,
      kind: kind,
    );
    edit(() {
      _project.audios.add(layer);
      _selection = EditorSelection(kind: LaneKind.audio, id: layer.id);
    });
    return layer;
  }

  void updateLayer<T extends TimelineLayer>(
    T layer,
    void Function(T) mutate, {
    bool record = true,
  }) {
    edit(record: record, () => mutate(layer));
  }

  void moveLayer(
    TimelineLayer layer,
    Duration newStart, {
    bool record = false,
  }) {
    edit(record: record, () {
      layer.start = newStart < Duration.zero ? Duration.zero : newStart;
    });
  }

  void resizeLayer(
    TimelineLayer layer, {
    Duration? start,
    Duration? end,
    bool record = false,
  }) {
    edit(record: record, () {
      if (start != null) {
        final maxStart = layer.end - kMinClipDuration;
        final s = start.clamp(Duration.zero, maxStart);
        layer.duration = layer.end - s;
        layer.start = s;
      }
      if (end != null) {
        final e = end.clamp(
          layer.start + kMinClipDuration,
          const Duration(hours: 6),
        );
        layer.duration = e - layer.start;
      }
    });
  }

  void deleteLayer(TimelineLayer layer) {
    edit(() {
      _project.texts.removeWhere((e) => e.id == layer.id);
      _project.stickers.removeWhere((e) => e.id == layer.id);
      _project.overlays.removeWhere((e) => e.id == layer.id);
      _project.audios.removeWhere((e) => e.id == layer.id);
      _selection = const EditorSelection.none();
    });
  }

  void duplicateLayer(TimelineLayer layer) {
    edit(() {
      if (layer is TextLayer) {
        _project.texts.add(layer.copy()..start = layer.end);
      } else if (layer is StickerLayer) {
        _project.stickers.add(layer.copy()..start = layer.end);
      } else if (layer is OverlayLayer) {
        _project.overlays.add(layer.copy()..start = layer.end);
      } else if (layer is AudioLayer) {
        _project.audios.add(layer.copy()..start = layer.end);
      }
    });
  }

  /// Split a secondary-lane layer at the playhead.
  bool splitLayerAtPlayhead(TimelineLayer layer) {
    final t = position.value;
    if (!layer.isVisibleAt(t)) return false;
    final left = t - layer.start;
    final right = layer.end - t;
    if (left < kMinClipDuration || right < kMinClipDuration) return false;
    edit(() {
      if (layer is TextLayer) {
        final copy = layer.copy()
          ..start = t
          ..duration = right;
        layer.duration = left;
        _project.texts.add(copy);
      } else if (layer is StickerLayer) {
        final copy = layer.copy()
          ..start = t
          ..duration = right;
        layer.duration = left;
        _project.stickers.add(copy);
      } else if (layer is OverlayLayer) {
        final copy = layer.copy()
          ..start = t
          ..trimStart = layer.trimStart + left
          ..duration = right;
        layer.duration = left;
        _project.overlays.add(copy);
      } else if (layer is AudioLayer) {
        final copy = layer.copy()
          ..start = t
          ..trimStart = layer.trimStart + left
          ..duration = right;
        layer.duration = left;
        _project.audios.add(copy);
      }
    });
    return true;
  }

  /// Re-cut the timeline the user already has with [template]'s pacing, moves
  /// and titles, reusing the clips on the track as the template's media.
  ///
  /// This replaces the timeline wholesale, so it goes through [edit] and
  /// stays one undo step away.
  Future<void> applyTemplateToCurrentMedia(VideoTemplate template) async {
    if (_project.clips.isEmpty) return;
    final media = _project.clips.map((c) => c.copyWith()).toList();
    edit(() {
      TemplateApplier.apply(
        template: template,
        project: _project,
        media: media,
      );
      _selection = const EditorSelection.none();
    });
    position.value = Duration.zero;
    await saveNow();
  }

  // ------------------------------------------------------------ keyframes

  /// The keyframable thing the selection points at, plus the playhead offset
  /// inside it. Keyframe times are stored relative to the owner so trimming
  /// and moving never invalidate them.
  (Keyframable, Duration)? get keyframeTarget {
    final clip = selectedClip;
    if (clip != null) {
      final i = selectedClipIndex;
      if (i < 0) return null;
      return (clip, position.value - _project.clipStart(i));
    }
    final text = selectedText;
    if (text != null) return (text, position.value - text.start);
    final sticker = selectedSticker;
    if (sticker != null) return (sticker, position.value - sticker.start);
    final overlay = selectedOverlay;
    if (overlay != null) return (overlay, position.value - overlay.start);
    final audio = selectedAudio;
    if (audio != null) return (audio, position.value - audio.start);
    return null;
  }

  /// Properties that make sense for whatever is selected.
  List<KeyframeProperty> get availableProperties {
    if (selectedAudio != null) return const [KeyframeProperty.volume];
    if (selectedClip != null) {
      return const [
        KeyframeProperty.x,
        KeyframeProperty.y,
        KeyframeProperty.scale,
        KeyframeProperty.rotation,
        KeyframeProperty.opacity,
        KeyframeProperty.volume,
        KeyframeProperty.filterIntensity,
      ];
    }
    if (selectedOverlay != null) {
      return const [
        KeyframeProperty.x,
        KeyframeProperty.y,
        KeyframeProperty.scale,
        KeyframeProperty.rotation,
        KeyframeProperty.opacity,
        KeyframeProperty.cornerRadius,
      ];
    }
    return const [
      KeyframeProperty.x,
      KeyframeProperty.y,
      KeyframeProperty.scale,
      KeyframeProperty.rotation,
      KeyframeProperty.opacity,
    ];
  }

  /// Current static value of [p] on the selection, used as the seed when a
  /// first keyframe is dropped.
  double currentValueOf(KeyframeProperty p) {
    final clip = selectedClip;
    if (clip != null) {
      return switch (p) {
        KeyframeProperty.x => clip.offsetX,
        KeyframeProperty.y => clip.offsetY,
        KeyframeProperty.scale => clip.scale,
        KeyframeProperty.rotation => 0,
        KeyframeProperty.opacity => clip.opacity,
        KeyframeProperty.volume => clip.volume,
        KeyframeProperty.filterIntensity => clip.filterIntensity,
        _ => 0,
      };
    }
    final audio = selectedAudio;
    if (audio != null) return p == KeyframeProperty.volume ? audio.volume : 0;

    final overlay = selectedOverlay;
    if (overlay != null && p == KeyframeProperty.cornerRadius) {
      return overlay.cornerRadius;
    }
    final t =
        selectedText?.transform ??
        selectedSticker?.transform ??
        selectedOverlay?.transform;
    if (t == null) return 0;
    return switch (p) {
      KeyframeProperty.x => t.x,
      KeyframeProperty.y => t.y,
      KeyframeProperty.scale => t.scale,
      KeyframeProperty.rotation => t.rotation,
      KeyframeProperty.opacity => t.opacity,
      _ => 0,
    };
  }

  /// Drop a key for every property that already has a track, seeding the
  /// first one from the static value — the behaviour a single keyframe
  /// button needs to feel predictable.
  bool addKeyframeAtPlayhead({KeyframeProperty? only}) {
    final target = keyframeTarget;
    if (target == null) return false;
    final (owner, local) = target;
    if (local < Duration.zero) return false;

    final props = only != null
        ? [only]
        : (owner.hasKeyframes
              ? owner.keyframes.entries
                    .where((e) => e.value.isNotEmpty)
                    .map((e) => e.key)
                    .toList()
              : availableProperties.take(3).toList());

    edit(() {
      for (final p in props) {
        final track = owner.track(p);
        final seed = track.isEmpty
            ? currentValueOf(p)
            : track.valueAt(local, currentValueOf(p));
        track.set(local, seed);
      }
    });
    return true;
  }

  void setKeyframe(KeyframeProperty p, double value, {bool record = true}) {
    final target = keyframeTarget;
    if (target == null) return;
    final (owner, local) = target;
    edit(record: record, () => owner.track(p).set(local, value));
  }

  bool removeKeyframeAtPlayhead() {
    final target = keyframeTarget;
    if (target == null) return false;
    final (owner, local) = target;
    if (owner.keyframeTimes.every(
      (t) => (t - local).abs() > KeyframeTrack.snapTolerance,
    )) {
      return false;
    }
    edit(() => owner.removeKeyframesAt(local));
    return true;
  }

  void clearKeyframes() {
    final target = keyframeTarget;
    if (target == null) return;
    edit(() => target.$1.clearKeyframes());
  }

  /// Jump to the next or previous keyframe on the selection.
  void stepKeyframe({required bool forward}) {
    final target = keyframeTarget;
    if (target == null) return;
    final (owner, local) = target;
    final times = owner.keyframeTimes;
    if (times.isEmpty) return;
    final base = position.value - local;
    if (forward) {
      for (final t in times) {
        if (t > local + KeyframeTrack.snapTolerance) {
          seek(base + t);
          return;
        }
      }
    } else {
      for (final t in times.reversed) {
        if (t < local - KeyframeTrack.snapTolerance) {
          seek(base + t);
          return;
        }
      }
    }
  }

  bool get hasKeyframeAtPlayhead {
    final target = keyframeTarget;
    if (target == null) return false;
    final (owner, local) = target;
    return owner.keyframeTimes.any(
      (t) => (t - local).abs() <= KeyframeTrack.snapTolerance,
    );
  }

  /// Every detected beat on the timeline, in master-timeline time.
  List<Duration> get beatMarkers {
    final out = <Duration>[];
    for (final a in _project.audios) {
      for (final b in a.beats) {
        final local = b - a.trimStart;
        if (local < Duration.zero || local > a.duration) continue;
        out.add(a.start + local);
      }
    }
    out.sort();
    return out;
  }

  /// Move the playhead to the closest beat; returns false when there is none
  /// within a musically useful distance.
  bool snapToNearestBeat() {
    final beats = beatMarkers;
    if (beats.isEmpty) return false;
    final t = position.value;
    Duration? best;
    var bestDelta = const Duration(days: 1);
    for (final b in beats) {
      final d = (b - t).abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = b;
      }
    }
    if (best == null || bestDelta > const Duration(seconds: 2)) return false;
    seek(best);
    return true;
  }

  // ------------------------------------------------------------- captions

  /// Swap the caption set wholesale, leaving hand-placed text alone.
  void replaceCaptions(List<TextLayer> layers) {
    edit(() {
      _project.texts.removeWhere((t) => t.isCaption);
      _project.texts.addAll(layers);
    });
  }

  void clearCaptions() {
    edit(() {
      _project.texts.removeWhere((t) => t.isCaption);
      if (_selection.kind == LaneKind.text) {
        _selection = const EditorSelection.none();
      }
    });
  }

  Future<String?> readSrtFile() async {
    final picked = await MediaLibrary.instance.pickFiles(
      allowMultiple: false,
      extensions: ['srt', 'vtt', 'txt'],
    );
    final path = picked.firstOrNull?.filePath;
    if (path == null) return null;
    try {
      return await File(path).readAsString();
    } catch (e) {
      debugPrint('srt read failed: $e');
      return null;
    }
  }

  // -------------------------------------------------------------- project

  void setRatio(CanvasRatio ratio) => edit(() => _project.ratio = ratio);

  void setBackground(void Function(BackgroundStyle) mutate) =>
      edit(() => mutate(_project.background));

  // ------------------------------------------------------------ watermark

  void setWatermark(void Function(Watermark) mutate, {bool record = true}) =>
      edit(record: record, () => mutate(_project.watermark));

  /// Copies the picked logo into app storage before pointing the mark at it,
  /// so deleting it from the gallery later cannot break the project, and
  /// switches the mark to image so the choice takes effect immediately.
  Future<void> setWatermarkImage(String sourcePath) async {
    setBusy('Adding watermark');
    try {
      final dir = await _repo.mediaDir();
      final stored = await MediaLibrary.instance.materialise(sourcePath, dir);
      edit(() {
        final w = _project.watermark;
        w.imagePath = stored;
        w.type = WatermarkType.image;
        w.enabled = true;
      });
    } finally {
      setBusy(null);
    }
  }

  void rename(String name) => edit(() => _project.name = name);

  void setMasterVolume(double v) =>
      edit(record: false, () => _project.masterVolume = v.clamp(0, 2));
}

extension _FirstById on List<VideoClip> {
  VideoClip? firstWhereOrNullById(String? id) {
    for (final c in this) {
      if (c.id == id) return c;
    }
    return null;
  }
}

extension _ClampDuration on Duration {
  Duration clamp(Duration min, Duration max) {
    if (this < min) return min;
    if (this > max) return max;
    return this;
  }
}
