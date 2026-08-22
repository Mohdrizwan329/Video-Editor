import 'dart:convert';

import '../../core/utils/id.dart';
import 'enums.dart';
import 'layers.dart';
import 'video_clip.dart';
import 'video_effect.dart';
import 'watermark.dart';

/// Canvas background behind letterboxed clips.
class BackgroundStyle {
  BackgroundStyle({
    this.type = BackgroundType.color,
    this.color = 0xFF000000,
    this.blurAmount = 18,
    this.gradientStart = 0xFF232526,
    this.gradientEnd = 0xFF414345,
  });

  BackgroundType type;
  int color;
  double blurAmount;
  int gradientStart;
  int gradientEnd;

  BackgroundStyle copy() => BackgroundStyle(
        type: type,
        color: color,
        blurAmount: blurAmount,
        gradientStart: gradientStart,
        gradientEnd: gradientEnd,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'color': color,
        'blur': blurAmount,
        'gs': gradientStart,
        'ge': gradientEnd,
      };

  factory BackgroundStyle.fromJson(Map<String, dynamic>? j) {
    if (j == null) return BackgroundStyle();
    return BackgroundStyle(
      type: BackgroundType.values
          .firstWhere((e) => e.name == j['type'], orElse: () => BackgroundType.color),
      color: (j['color'] as num?)?.toInt() ?? 0xFF000000,
      blurAmount: (j['blur'] as num?)?.toDouble() ?? 18,
      gradientStart: (j['gs'] as num?)?.toInt() ?? 0xFF232526,
      gradientEnd: (j['ge'] as num?)?.toInt() ?? 0xFF414345,
    );
  }
}

/// A full editing session: the main track plus every secondary lane.
class Project {
  Project({
    String? id,
    required this.name,
    this.ratio = CanvasRatio.r9x16,
    List<VideoClip>? clips,
    List<AudioLayer>? audios,
    List<TextLayer>? texts,
    List<StickerLayer>? stickers,
    List<OverlayLayer>? overlays,
    BackgroundStyle? background,
    Watermark? watermark,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.coverPath,
    this.masterVolume = 1.0,
    String? frameId,
    String? fxId,
    this.fxIntensity = 1.0,
  })  : id = id ?? newId(),
        frameId = frameId ?? 'none',
        fxId = fxId ?? 'none',
        clips = clips ?? [],
        audios = audios ?? [],
        texts = texts ?? [],
        stickers = stickers ?? [],
        overlays = overlays ?? [],
        background = background ?? BackgroundStyle(),
        watermark = watermark ?? Watermark(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String name;
  CanvasRatio ratio;
  final List<VideoClip> clips;
  final List<AudioLayer> audios;
  final List<TextLayer> texts;
  final List<StickerLayer> stickers;
  final List<OverlayLayer> overlays;
  BackgroundStyle background;

  /// The creator's own mark, drawn over every frame of the export.
  Watermark watermark;
  DateTime createdAt;
  DateTime updatedAt;
  String? coverPath;
  double masterVolume;

  /// Design frame drawn over every finished frame, like the watermark.
  String frameId;

  /// FX texture laid over every finished frame, and how strongly.
  String fxId;
  double fxIntensity;

  FramePreset get frame => FrameLibrary.fromId(frameId);
  FxPreset get fx => FxLibrary.fromId(fxId);
  bool get hasFrame => !frame.isNone;
  bool get hasFx => !fx.isNone && fxIntensity > 0;

  Duration _maxOverlapAt(int i) {
    final a = clips[i].timelineDuration;
    final b = clips[i + 1].timelineDuration;
    final shorter = a < b ? a : b;
    // Never eat more than half of the shorter neighbour.
    return Duration(microseconds: (shorter.inMicroseconds ~/ 2));
  }

  /// Effective overlap actually applied after clip i.
  Duration overlapAfter(int i) {
    if (i < 0 || i >= clips.length - 1) return Duration.zero;
    final c = clips[i];
    if (c.transitionType == TransitionType.none) return Duration.zero;
    final max = _maxOverlapAt(i);
    return c.transitionDuration <= max ? c.transitionDuration : max;
  }

  /// Timeline start of clip [i], accounting for transition overlaps.
  Duration clipStart(int i) {
    var t = Duration.zero;
    for (var k = 0; k < i; k++) {
      t += clips[k].timelineDuration - overlapAfter(k);
    }
    return t;
  }

  Duration get videoDuration {
    if (clips.isEmpty) return Duration.zero;
    return clipStart(clips.length - 1) + clips.last.timelineDuration;
  }

  /// Whole project length: the video track, or the furthest layer if longer.
  Duration get totalDuration {
    var d = videoDuration;
    for (final l in <TimelineLayer>[...audios, ...texts, ...stickers, ...overlays]) {
      if (l.end > d) d = l.end;
    }
    return d;
  }

  /// Index of the clip under [t] on the timeline, or -1.
  int clipIndexAt(Duration t) {
    for (var i = 0; i < clips.length; i++) {
      final s = clipStart(i);
      final e = s + clips[i].timelineDuration;
      if (t >= s && t < e) return i;
    }
    return clips.isEmpty ? -1 : clips.length - 1;
  }

  double get canvasAspect {
    final r = ratio.value;
    if (r != null) return r;
    if (clips.isNotEmpty) return clips.first.sourceAspect;
    return 9 / 16;
  }

  Project deepCopy() => Project.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ratio': ratio.name,
        'clips': clips.map((e) => e.toJson()).toList(),
        'audios': audios.map((e) => e.toJson()).toList(),
        'texts': texts.map((e) => e.toJson()).toList(),
        'stickers': stickers.map((e) => e.toJson()).toList(),
        'overlays': overlays.map((e) => e.toJson()).toList(),
        'bg': background.toJson(),
        'wm': watermark.toJson(),
        'created': createdAt.millisecondsSinceEpoch,
        'updated': updatedAt.millisecondsSinceEpoch,
        'cover': coverPath,
        'mvol': masterVolume,
        'frame': frameId,
        'fx': fxId,
        'fxi': fxIntensity,
      };

  factory Project.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) =>
        ((j[key] as List?) ?? const [])
            .map((e) => f((e as Map).cast<String, dynamic>()))
            .toList();
    return Project(
      id: j['id'] as String?,
      name: j['name'] as String? ?? 'Untitled',
      ratio: CanvasRatio.fromName(j['ratio'] as String?),
      clips: list('clips', VideoClip.fromJson),
      audios: list('audios', AudioLayer.fromJson),
      texts: list('texts', TextLayer.fromJson),
      stickers: list('stickers', StickerLayer.fromJson),
      overlays: list('overlays', OverlayLayer.fromJson),
      background: BackgroundStyle.fromJson(j['bg'] as Map<String, dynamic>?),
      watermark: Watermark.fromJson(j['wm'] as Map<String, dynamic>?),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (j['created'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (j['updated'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
      coverPath: j['cover'] as String?,
      masterVolume: (j['mvol'] as num?)?.toDouble() ?? 1,
      frameId: j['frame'] as String?,
      fxId: j['fx'] as String?,
      fxIntensity: (j['fxi'] as num?)?.toDouble() ?? 1,
    );
  }
}
