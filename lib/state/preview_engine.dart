import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:video_player/video_player.dart';

import '../data/models/keyframe.dart';
import '../data/models/layers.dart';
import '../data/models/video_clip.dart';
import 'editor_controller.dart';

/// Drives preview playback across the whole timeline.
///
/// A wall clock is the master and every player is a follower, re-synced when
/// it drifts past [_maxDrift]. The clock is only started once the active
/// decoder is actually open, and corrections are rate-limited by
/// [_seekCooldown] — without either, setup time gets counted as playback and a
/// slow decoder gets seek-thrashed into never advancing at all.
class PreviewEngine extends ChangeNotifier {
  PreviewEngine(this.editor) {
    editor.addListener(_onProjectChanged);
    // Nothing else drives a sync until the user plays or scrubs, so an
    // untouched project would sit on a black canvas. Prime it once.
    Future.microtask(prime);
  }

  final EditorController editor;

  static const Duration _tick = Duration(milliseconds: 16);
  static const Duration _maxDrift = Duration(milliseconds: 130);

  /// Minimum gap between drift-correcting seeks on the same clip.
  static const Duration _seekCooldown = Duration(milliseconds: 600);

  final Map<String, VideoPlayerController> _video = {};
  final Map<String, ja.AudioPlayer> _audio = {};
  final Set<String> _loading = {};

  Timer? _timer;
  final Stopwatch _clock = Stopwatch();
  Duration _clockOrigin = Duration.zero;

  int _activeIndex = -1;
  String? _activeClipId;
  bool _disposed = false;
  bool _muted = false;
  bool _priming = false;
  DateTime? _lastSeekAt;

  bool get isPlaying => editor.isPlaying.value;

  /// Controller for the clip currently under the playhead, if it is ready.
  VideoPlayerController? get activeController {
    final id = _activeClipId;
    if (id == null) return null;
    final c = _video[id];
    return (c != null && c.value.isInitialized) ? c : null;
  }

  VideoPlayerController? controllerFor(String id) {
    final c = _video[id];
    return (c != null && c.value.isInitialized) ? c : null;
  }

  @override
  void dispose() {
    _disposed = true;
    editor.removeListener(_onProjectChanged);
    _timer?.cancel();
    for (final c in _video.values) {
      c.dispose();
    }
    for (final p in _audio.values) {
      p.dispose();
    }
    _video.clear();
    _audio.clear();
    super.dispose();
  }

  // ------------------------------------------------------------- transport

  Future<void> play() async {
    if (editor.project.clips.isEmpty) return;
    if (editor.position.value >= editor.totalDuration) {
      editor.seek(Duration.zero);
    }
    editor.isPlaying.value = true;
    _clockOrigin = editor.position.value;

    // Open and seek every player *before* starting the master clock. Opening
    // three decoders takes a moment on a slow device, and a clock started
    // first would count that setup time as playback and jump the playhead
    // seconds ahead of the picture.
    _clock
      ..stop()
      ..reset();
    await _syncAll(force: true, playing: true);
    if (!editor.isPlaying.value) return;
    _clock.start();

    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) => _onTick());
    notifyListeners();
  }

  Future<void> pause() async {
    editor.isPlaying.value = false;
    _clock.stop();
    _timer?.cancel();
    _timer = null;
    for (final c in _video.values) {
      if (c.value.isInitialized && c.value.isPlaying) await c.pause();
    }
    for (final p in _audio.values) {
      if (p.playing) await p.pause();
    }
    notifyListeners();
  }

  Future<void> toggle() => isPlaying ? pause() : play();

  /// Open the player for the clip under the playhead and park it on that
  /// frame, so the canvas shows the picture without playing first.
  Future<void> prime() async {
    if (_disposed || _priming || isPlaying) return;
    if (editor.project.clips.isEmpty) return;
    _priming = true;
    try {
      await _syncAll(force: true, playing: false);
    } finally {
      _priming = false;
    }
  }

  Future<void> seek(Duration to) async {
    editor.seek(to);
    _clockOrigin = editor.position.value;
    // Same reasoning as play(): the seek itself must not be counted as
    // elapsed playback time.
    _clock
      ..stop()
      ..reset();
    await _syncAll(force: true, playing: isPlaying);
    if (isPlaying) _clock.start();
  }

  void setMuted(bool value) {
    _muted = value;
    _applyVolumes();
    notifyListeners();
  }

  // ---------------------------------------------------------------- clock

  /// Advance the playhead in real time.
  ///
  /// The wall clock is the master and the players are followers: a timeline
  /// second has to mean a second regardless of how fast any one decoder can
  /// keep up. When a device cannot decode in real time the picture stutters
  /// and the drift corrector re-seeks it — the playhead does not slow down to
  /// match, because that would make the timeline lie about its own length.
  Future<void> _onTick() async {
    if (_disposed) return;
    final t = _clockOrigin + _clock.elapsed;
    final total = editor.totalDuration;
    if (t >= total) {
      editor.seek(total);
      await pause();
      return;
    }
    editor.position.value = t;
    await _syncAll(playing: true);
  }

  // ----------------------------------------------------------------- sync

  Future<void> _syncAll({bool force = false, required bool playing}) async {
    await _syncMainTrack(force: force, playing: playing);
    await _syncTransitionPartner(
      force: force,
      playing: playing,
      index: editor.project.clipIndexAt(editor.position.value),
    );
    await _syncOverlays(force: force, playing: playing);
    await _syncAudio(force: force, playing: playing);
  }

  Future<void> _syncMainTrack({required bool force, required bool playing}) async {
    final project = editor.project;
    if (project.clips.isEmpty) {
      _activeIndex = -1;
      _activeClipId = null;
      return;
    }
    final t = editor.position.value;
    final index = project.clipIndexAt(t);
    if (index < 0) return;
    final clip = project.clips[index];

    if (index != _activeIndex) {
      final previous = _activeClipId;
      _activeIndex = index;
      _activeClipId = clip.id;
      _lastSeekAt = null;
      if (previous != null && previous != clip.id) {
        final old = _video[previous];
        if (old != null && old.value.isInitialized && old.value.isPlaying) {
          await old.pause();
        }
      }
      notifyListeners();
    }

    // On a forced sync the caller is about to start the clock, so the active
    // clip's decoder must actually be open before we return — firing it off
    // unawaited is what let the clock run ahead of the picture.
    if (force) {
      await _ensureController(clip);
    } else {
      unawaited(_ensureController(clip));
    }
    // The neighbour only needs to be warm before the boundary arrives.
    if (index + 1 < project.clips.length) {
      unawaited(_ensureController(project.clips[index + 1]));
    }
    _evictDistantControllers(index);

    if (clip.isImage) return;
    final controller = _video[clip.id];
    if (controller == null || !controller.value.isInitialized) return;

    final local = t - project.clipStart(index);
    final target = clip.sourcePositionFor(local);
    final drift = controller.value.position - target;

    // Correct drift, but no more often than [_seekCooldown]. Seeking every
    // tick is what stalls a slow decoder: each seek throws away the work in
    // flight, so the player never gets far enough to report progress.
    if (force || drift.abs() > _maxDrift) {
      final now = DateTime.now();
      if (force ||
          _lastSeekAt == null ||
          now.difference(_lastSeekAt!) > _seekCooldown) {
        _lastSeekAt = now;
        await controller.seekTo(target);
      }
    }
    if (controller.value.playbackSpeed != clip.effectiveSpeed) {
      await controller.setPlaybackSpeed(clip.effectiveSpeed.clamp(0.1, 8.0));
    }
    // The volume *track* when there is one: a keyframed level that only moved
    // in the render is a keyframe the user cannot hear themselves setting.
    final level = clip.animated(KeyframeProperty.volume, local, clip.volume);
    final wantedVolume = _muted
        ? 0.0
        : level * editor.project.masterVolume * clip.fadeGainAt(local);
    if ((controller.value.volume - wantedVolume).abs() > 0.01) {
      await controller.setVolume(wantedVolume.clamp(0.0, 1.0));
    }
    if (playing && !controller.value.isPlaying) {
      await controller.play();
    } else if (!playing && controller.value.isPlaying) {
      await controller.pause();
    }
  }

  /// The clip on the far side of a transition, while the playhead is inside
  /// the overlap between the two.
  ///
  /// The canvas composites both frames there, the way the exporter's `xfade`
  /// does, so the incoming decoder has to be running as well — left alone it
  /// holds its first frame and every transition plays against a still.
  Future<void> _syncTransitionPartner({
    required bool force,
    required bool playing,
    required int index,
  }) async {
    final project = editor.project;
    if (index < 0 || index + 1 >= project.clips.length) return;
    final next = project.clips[index + 1];
    final controller = _video[next.id];
    if (controller == null || !controller.value.isInitialized) return;

    final joinStart = project.clipStart(index + 1);
    final t = editor.position.value;
    if (project.overlapAfter(index) <= Duration.zero || t < joinStart) {
      // Not on screen: a warmed decoder must not be left running behind it.
      if (controller.value.isPlaying) await controller.pause();
      return;
    }

    final target = next.sourcePositionFor(t - joinStart);
    if (force || (controller.value.position - target).abs() > _maxDrift) {
      await controller.seekTo(target);
    }
    if (controller.value.playbackSpeed != next.effectiveSpeed) {
      await controller.setPlaybackSpeed(next.effectiveSpeed.clamp(0.1, 8.0));
    }
    // Its audio already starts at its own slot in the render, so it comes in
    // under the transition here too.
    final wanted = _muted
        ? 0.0
        : next.volume *
            editor.project.masterVolume *
            next.fadeGainAt(t - joinStart);
    if ((controller.value.volume - wanted).abs() > 0.01) {
      await controller.setVolume(wanted.clamp(0.0, 1.0));
    }
    if (playing && !controller.value.isPlaying) {
      await controller.play();
    } else if (!playing && controller.value.isPlaying) {
      await controller.pause();
    }
  }

  Future<void> _syncOverlays({required bool force, required bool playing}) async {
    final t = editor.position.value;
    for (final pip in editor.project.overlays) {
      if (pip.isImage) continue;
      final visible = pip.isVisibleAt(t);
      if (!visible) {
        final c = _video[pip.id];
        if (c != null && c.value.isInitialized && c.value.isPlaying) {
          await c.pause();
        }
        continue;
      }
      if (force) {
        await _ensureOverlayController(pip);
      } else {
        unawaited(_ensureOverlayController(pip));
      }
      final c = _video[pip.id];
      if (c == null || !c.value.isInitialized) continue;
      final local = t - pip.start;
      final target = pip.trimStart +
          Duration(microseconds: (local.inMicroseconds * pip.speed).round());
      if (force || (c.value.position - target).abs() > _maxDrift) {
        await c.seekTo(target);
      }
      final vol = _muted ? 0.0 : pip.volume * editor.project.masterVolume;
      if ((c.value.volume - vol).abs() > 0.01) {
        await c.setVolume(vol.clamp(0.0, 1.0));
      }
      if (playing && !c.value.isPlaying) {
        await c.play();
      } else if (!playing && c.value.isPlaying) {
        await c.pause();
      }
    }
  }

  Future<void> _syncAudio({required bool force, required bool playing}) async {
    final t = editor.position.value;
    for (final layer in editor.project.audios) {
      final player = await _ensureAudioPlayer(layer);
      if (player == null) continue;
      final visible = layer.isVisibleAt(t);
      if (!visible) {
        if (player.playing) await player.pause();
        continue;
      }
      final target = layer.trimStart + (t - layer.start);
      final drift = player.position - target;
      if (force || drift.abs() > _maxDrift) {
        await player.seek(target);
      }
      final vol = _muted ? 0.0 : _audioGainAt(layer, t);
      if ((player.volume - vol).abs() > 0.01) {
        await player.setVolume(vol.clamp(0.0, 1.0));
      }
      if (player.speed != layer.speed) {
        await player.setSpeed(layer.speed.clamp(0.25, 4.0));
      }
      // The pitch slider and the pitched half of the voice changer, which
      // the renderer does with `asetrate`. Only the platforms that carry a
      // pitch shifter can preview it — the rest still export it, so a failure
      // here is not worth losing the rest of the sync over.
      final semitones = layer.pitch + layer.voiceEffect.semitones;
      final wantedPitch = math.pow(2, semitones / 12).toDouble();
      if ((player.pitch - wantedPitch).abs() > 0.01) {
        try {
          await player.setPitch(wantedPitch);
        } catch (_) {
          // No pitch shifting on this platform.
        }
      }
      final wantedLoop = layer.loop ? ja.LoopMode.one : ja.LoopMode.off;
      if (player.loopMode != wantedLoop) {
        await player.setLoopMode(wantedLoop);
      }
      if (playing && !player.playing) {
        unawaited(player.play());
      } else if (!playing && player.playing) {
        await player.pause();
      }
    }
  }

  /// Applies the layer's fade envelope so the preview matches the render.
  double _audioGainAt(AudioLayer layer, Duration t) {
    final level = layer.animated(
        KeyframeProperty.volume, t - layer.start, layer.volume);
    var gain = level * editor.project.masterVolume;
    final into = t - layer.start;
    final left = layer.end - t;
    if (layer.fadeIn > Duration.zero && into < layer.fadeIn) {
      gain *= into.inMicroseconds / layer.fadeIn.inMicroseconds;
    }
    if (layer.fadeOut > Duration.zero && left < layer.fadeOut) {
      gain *= left.inMicroseconds / layer.fadeOut.inMicroseconds;
    }
    return gain.clamp(0.0, 1.0);
  }

  void _applyVolumes() {
    for (final c in _video.values) {
      if (c.value.isInitialized) c.setVolume(_muted ? 0 : c.value.volume);
    }
    unawaited(_syncAudio(force: false, playing: isPlaying));
  }

  // ------------------------------------------------------------ resources

  Future<void> _ensureController(VideoClip clip) async {
    if (clip.isImage) return;
    if (_video.containsKey(clip.id) || _loading.contains(clip.id)) return;
    _loading.add(clip.id);
    try {
      final file = File(clip.path);
      if (!await file.exists()) return;
      final c = VideoPlayerController.file(file);
      await c.initialize();
      if (_disposed) {
        await c.dispose();
        return;
      }
      await c.setVolume(_muted ? 0 : clip.volume.clamp(0.0, 1.0));
      await c.setLooping(false);
      _video[clip.id] = c;
      notifyListeners();
    } catch (e) {
      debugPrint('preview: cannot open ${clip.path}: $e');
    } finally {
      _loading.remove(clip.id);
    }
  }

  Future<void> _ensureOverlayController(OverlayLayer pip) async {
    if (pip.isImage) return;
    if (_video.containsKey(pip.id) || _loading.contains(pip.id)) return;
    _loading.add(pip.id);
    try {
      final file = File(pip.path);
      if (!await file.exists()) return;
      final c = VideoPlayerController.file(file);
      await c.initialize();
      if (_disposed) {
        await c.dispose();
        return;
      }
      await c.setVolume(_muted ? 0 : pip.volume.clamp(0.0, 1.0));
      _video[pip.id] = c;
      notifyListeners();
    } catch (e) {
      debugPrint('preview: cannot open overlay ${pip.path}: $e');
    } finally {
      _loading.remove(pip.id);
    }
  }

  Future<ja.AudioPlayer?> _ensureAudioPlayer(AudioLayer layer) async {
    final existing = _audio[layer.id];
    if (existing != null) return existing;
    if (_loading.contains(layer.id)) return null;
    _loading.add(layer.id);
    try {
      final player = ja.AudioPlayer();
      await player.setFilePath(layer.path);
      if (_disposed) {
        await player.dispose();
        return null;
      }
      _audio[layer.id] = player;
      return player;
    } catch (e) {
      debugPrint('preview: cannot open audio ${layer.path}: $e');
      return null;
    } finally {
      _loading.remove(layer.id);
    }
  }

  /// Only the neighbourhood of the playhead stays decoded — a 60-clip
  /// timeline would otherwise hold 60 decoders open.
  void _evictDistantControllers(int index) {
    final keep = <String>{};
    final clips = editor.project.clips;
    for (var i = index - 1; i <= index + 1; i++) {
      if (i >= 0 && i < clips.length) keep.add(clips[i].id);
    }
    for (final pip in editor.project.overlays) {
      keep.add(pip.id);
    }
    final drop = _video.keys.where((k) => !keep.contains(k)).toList();
    for (final k in drop) {
      _video.remove(k)?.dispose();
    }
  }

  /// Drop players for media that is no longer in the project, and prime the
  /// canvas the first time a clip appears.
  void _onProjectChanged() {
    if (!isPlaying && _activeClipId == null && editor.project.clips.isNotEmpty) {
      Future.microtask(prime);
    }
    final live = <String>{
      ...editor.project.clips.map((c) => c.id),
      ...editor.project.overlays.map((o) => o.id),
    };
    final deadVideo =
        _video.keys.where((k) => !live.contains(k)).toList(growable: false);
    for (final k in deadVideo) {
      if (k == _activeClipId) continue;
      _video.remove(k)?.dispose();
    }
    final liveAudio = editor.project.audios.map((a) => a.id).toSet();
    final deadAudio =
        _audio.keys.where((k) => !liveAudio.contains(k)).toList(growable: false);
    for (final k in deadAudio) {
      _audio.remove(k)?.dispose();
    }
  }
}
