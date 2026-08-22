import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/utils/id.dart';
import 'adjustments.dart';
import 'enums.dart';
import 'filter_preset.dart';
import 'keyframe.dart';

/// One item on the main video track. Images are treated as clips with a
/// synthetic source duration so every timeline rule stays uniform.
class VideoClip with Keyframable {
  VideoClip({
    String? id,
    required this.path,
    required this.isImage,
    required this.sourceDuration,
    this.hasAudio = true,
    Duration? trimStart,
    Duration? trimEnd,
    this.speed = 1.0,
    this.volume = 1.0,
    this.reversed = false,
    this.mirrored = false,
    this.flippedVertical = false,
    this.rotation = 0,
    this.opacity = 1.0,
    String? filterId,
    this.filterIntensity = 1.0,
    Adjustments? adjustments,
    this.transitionType = TransitionType.none,
    this.transitionDuration = const Duration(milliseconds: 600),
    this.scale = 1.0,
    this.offsetX = 0,
    this.offsetY = 0,
    this.fit = FitMode.contain,
    this.fadeIn = Duration.zero,
    this.fadeOut = Duration.zero,
    this.animationIn = LayerAnimation.none,
    this.animationOut = LayerAnimation.none,
    this.sourceWidth = 0,
    this.sourceHeight = 0,
    this.cropLeft = 0,
    this.cropTop = 0,
    this.cropRight = 0,
    this.cropBottom = 0,
    this.thumbnailPath,
    this.speedCurve = SpeedCurve.none,
    this.maskShape = MaskShape.none,
    this.maskFeather = 0.1,
    this.maskSize = 0.6,
    this.maskX = 0.5,
    this.maskY = 0.5,
    this.maskRotation = 0,
    this.maskInverted = false,
    this.chromaKeyColor,
    this.chromaSimilarity = 0.25,
    this.chromaBlend = 0.1,
    this.stabilize = false,
    this.enhance = false,
    this.voiceEnhance = false,
    this.voiceEffect = VoiceEffect.none,
    this.cutoutMattePath,
    this.lutPath,
  })  : id = id ?? newId(),
        trimStart = trimStart ?? Duration.zero,
        trimEnd = trimEnd ?? sourceDuration,
        filterId = filterId ?? 'none',
        adjustments = adjustments ?? Adjustments();

  final String id;
  String path;
  bool isImage;

  /// False for images and for videos whose container carries no audio stream.
  bool hasAudio;

  /// Full length of the underlying file (images get a default 4s).
  Duration sourceDuration;
  Duration trimStart;
  Duration trimEnd;

  double speed;
  double volume;
  bool reversed;
  bool mirrored;
  bool flippedVertical;

  /// 0 / 90 / 180 / 270.
  int rotation;
  double opacity;

  String filterId;
  double filterIntensity;
  Adjustments adjustments;

  /// Transition applied at the *end* of this clip (into the next one).
  TransitionType transitionType;
  Duration transitionDuration;

  /// Canvas placement.
  double scale;
  double offsetX;
  double offsetY;
  FitMode fit;

  Duration fadeIn;
  Duration fadeOut;
  LayerAnimation animationIn;
  LayerAnimation animationOut;

  int sourceWidth;
  int sourceHeight;

  /// Normalised crop insets, 0..1 from each edge.
  double cropLeft;
  double cropTop;
  double cropRight;
  double cropBottom;

  String? thumbnailPath;

  /// Speed ramping preset. When set it overrides the flat [speed].
  SpeedCurve speedCurve;

  MaskShape maskShape;
  double maskFeather;
  double maskSize;
  double maskX;
  double maskY;
  double maskRotation;
  bool maskInverted;

  /// Green-screen key. Null disables it.
  int? chromaKeyColor;
  double chromaSimilarity;
  double chromaBlend;

  bool stabilize;

  /// One-tap picture clean-up: denoise, a touch of contrast and saturation,
  /// then unsharp. Applied at export, and flagged in the preview rather than
  /// simulated there — the sharpening has no cheap colour-matrix equivalent.
  bool enhance;

  /// One-tap voice clean-up on the clip's own audio: rumble filter, spectral
  /// denoise, compression and loudness normalisation.
  bool voiceEnhance;

  /// Pitch/timbre effect on the clip's own audio.
  VoiceEffect voiceEffect;

  /// A baked grey matte covering the trimmed region: white where the subject
  /// is. Set by the Cutout tool, and paired back with the footage through
  /// `alphamerge` at export. Null means the clip keeps its background.
  String? cutoutMattePath;

  bool get hasCutout => cutoutMattePath != null;

  /// Optional .cube LUT applied after the grade.
  String? lutPath;

  bool get hasMask => maskShape != MaskShape.none;
  bool get hasChroma => chromaKeyColor != null;

  /// Length of the trimmed source region before speed is applied.
  Duration get trimmedDuration => trimEnd - trimStart;

  /// Effective flat rate — the curve's average when ramping is on.
  double get effectiveSpeed =>
      speedCurve == SpeedCurve.none ? speed : speed * speedCurve.averageSpeed;

  /// Length this clip occupies on the timeline.
  Duration get timelineDuration => Duration(
      microseconds:
          (trimmedDuration.inMicroseconds / effectiveSpeed).round().clamp(1, 1 << 62));

  /// How much of the picture the fade envelope leaves at [local], an offset
  /// inside the clip's own span. 1 is the untouched frame, 0 is full black.
  ///
  /// The exporter emits these as `fade=t=in` / `fade=t=out`, which fade to
  /// black over the finished canvas — letterbox bars included — so the
  /// preview veils the whole canvas rather than dimming the footage alone.
  double fadeGainAt(Duration local) {
    var gain = 1.0;
    if (fadeIn > Duration.zero && local < fadeIn) {
      gain *= local.inMicroseconds / fadeIn.inMicroseconds;
    }
    final left = timelineDuration - local;
    if (fadeOut > Duration.zero && left < fadeOut) {
      gain *= left.inMicroseconds / fadeOut.inMicroseconds;
    }
    return gain.clamp(0.0, 1.0);
  }

  FilterPreset get filter =>
      FilterPreset.fromId(filterId).lerpFromIdentity(filterIntensity);

  /// Preview/export grade = preset (scaled by intensity) + manual adjustments.
  FilterPreset get gradedFilter => adjustments.merge(filter);

  /// The picture clean-up [enhance] stands for, as FFmpeg filters.
  ///
  /// Denoise first so the sharpener has nothing granular to bite on, then a
  /// small tonal lift, then unsharp — the order a stills workflow uses, and
  /// the one that keeps the noise from being amplified into speckle.
  List<String> enhanceFilters() => enhance
      ? const [
          'hqdn3d=2:1.5:3:3',
          'eq=contrast=1.06:saturation=1.06:gamma=1.02',
          'unsharp=5:5:0.9:5:5:0.0',
        ]
      : const [];

  /// The clip's own audio treatment: [voiceEnhance] first — it is a clean-up,
  /// and cleaning up after a pitch shift would fight the shift's artefacts —
  /// then [voiceEffect].
  ///
  /// Pitch shifting is done by resampling then correcting the tempo, the same
  /// way [AudioLayer] does it, so the two stay interchangeable.
  List<String> audioFilterChain() {
    final out = <String>[];
    if (voiceEnhance) {
      out.addAll(const [
        'highpass=f=90',
        'afftdn=nf=-25',
        'acompressor=threshold=-18dB:ratio=3:attack=15:release=180',
        'loudnorm=I=-16:TP=-1.5:LRA=11',
      ]);
    }
    final semitones = voiceEffect.semitones;
    if (semitones != 0) {
      final ratio = math.pow(2, semitones / 12).toDouble();
      out.add('asetrate=48000*${ratio.toStringAsFixed(5)}');
      out.add('aresample=48000');
      out.add('atempo=${(1 / ratio).clamp(0.5, 2.0).toStringAsFixed(5)}');
    }
    if (voiceEffect.echo) out.add('aecho=0.8:0.85:60:0.35');
    if (voiceEffect.isRobot) {
      out.add("afftfilt=real='hypot(re,im)*cos(0)':"
          "imag='hypot(re,im)*sin(0)':win_size=512:overlap=0.75");
    }
    return out;
  }

  double get sourceAspect =>
      (sourceWidth > 0 && sourceHeight > 0) ? sourceWidth / sourceHeight : 16 / 9;

  bool get hasCrop =>
      cropLeft > 0 || cropTop > 0 || cropRight > 0 || cropBottom > 0;

  /// Map a timeline offset inside this clip back to a position in the source file.
  Duration sourcePositionFor(Duration localOffset) {
    final scaled = Duration(
        microseconds: (localOffset.inMicroseconds * effectiveSpeed).round());
    if (reversed) {
      final p = trimEnd - scaled;
      return p < trimStart ? trimStart : p;
    }
    final p = trimStart + scaled;
    return p > trimEnd ? trimEnd : p;
  }

  VideoClip copyWith({String? id, String? path}) {
    return VideoClip(
      id: id,
      path: path ?? this.path,
      isImage: isImage,
      hasAudio: hasAudio,
      sourceDuration: sourceDuration,
      trimStart: trimStart,
      trimEnd: trimEnd,
      speed: speed,
      volume: volume,
      reversed: reversed,
      mirrored: mirrored,
      flippedVertical: flippedVertical,
      rotation: rotation,
      opacity: opacity,
      filterId: filterId,
      filterIntensity: filterIntensity,
      adjustments: adjustments.copy(),
      transitionType: transitionType,
      transitionDuration: transitionDuration,
      scale: scale,
      offsetX: offsetX,
      offsetY: offsetY,
      fit: fit,
      fadeIn: fadeIn,
      fadeOut: fadeOut,
      animationIn: animationIn,
      animationOut: animationOut,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      cropLeft: cropLeft,
      cropTop: cropTop,
      cropRight: cropRight,
      cropBottom: cropBottom,
      thumbnailPath: thumbnailPath,
      speedCurve: speedCurve,
      maskShape: maskShape,
      maskFeather: maskFeather,
      maskSize: maskSize,
      maskX: maskX,
      maskY: maskY,
      maskRotation: maskRotation,
      maskInverted: maskInverted,
      chromaKeyColor: chromaKeyColor,
      chromaSimilarity: chromaSimilarity,
      chromaBlend: chromaBlend,
      stabilize: stabilize,
      enhance: enhance,
      voiceEnhance: voiceEnhance,
      voiceEffect: voiceEffect,
      cutoutMattePath: cutoutMattePath,
      lutPath: lutPath,
    )..copyKeyframesFrom(this);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'isImage': isImage,
        'hasAudio': hasAudio,
        'src': sourceDuration.inMicroseconds,
        'ts': trimStart.inMicroseconds,
        'te': trimEnd.inMicroseconds,
        'speed': speed,
        'volume': volume,
        'reversed': reversed,
        'mirrored': mirrored,
        'flipV': flippedVertical,
        'rotation': rotation,
        'opacity': opacity,
        'filterId': filterId,
        'filterIntensity': filterIntensity,
        'adj': adjustments.toJson(),
        'tr': transitionType.name,
        'trd': transitionDuration.inMicroseconds,
        'scale': scale,
        'ox': offsetX,
        'oy': offsetY,
        'fit': fit.name,
        'fin': fadeIn.inMicroseconds,
        'fout': fadeOut.inMicroseconds,
        'ain': animationIn.name,
        'aout': animationOut.name,
        'w': sourceWidth,
        'h': sourceHeight,
        'cl': cropLeft,
        'ct': cropTop,
        'cr': cropRight,
        'cb': cropBottom,
        'thumb': thumbnailPath,
        'sc': speedCurve.name,
        'mk': maskShape.name,
        'mkf': maskFeather,
        'mks': maskSize,
        'mkx': maskX,
        'mky': maskY,
        'mkr': maskRotation,
        'mki': maskInverted,
        'ck': chromaKeyColor,
        'cks': chromaSimilarity,
        'ckb': chromaBlend,
        'stab': stabilize,
        'enh': enhance,
        'venh': voiceEnhance,
        'vfx': voiceEffect.name,
        'matte': cutoutMattePath,
        'lut': lutPath,
        'kf': keyframesToJson(),
      };

  factory VideoClip.fromJson(Map<String, dynamic> j) {
    Duration us(String k, [int fallback = 0]) =>
        Duration(microseconds: (j[k] as num?)?.toInt() ?? fallback);
    double d(String k, double fallback) => (j[k] as num?)?.toDouble() ?? fallback;
    return VideoClip(
      id: j['id'] as String?,
      path: j['path'] as String,
      isImage: j['isImage'] as bool? ?? false,
      hasAudio: j['hasAudio'] as bool? ?? true,
      sourceDuration: us('src'),
      trimStart: us('ts'),
      trimEnd: us('te'),
      speed: d('speed', 1),
      volume: d('volume', 1),
      reversed: j['reversed'] as bool? ?? false,
      mirrored: j['mirrored'] as bool? ?? false,
      flippedVertical: j['flipV'] as bool? ?? false,
      rotation: (j['rotation'] as num?)?.toInt() ?? 0,
      opacity: d('opacity', 1),
      filterId: j['filterId'] as String?,
      filterIntensity: d('filterIntensity', 1),
      adjustments: Adjustments.fromJson(j['adj'] as Map<String, dynamic>?),
      transitionType: TransitionType.fromName(j['tr'] as String?),
      transitionDuration: us('trd', 600000),
      scale: d('scale', 1),
      offsetX: d('ox', 0),
      offsetY: d('oy', 0),
      fit: FitMode.values.firstWhere((e) => e.name == j['fit'],
          orElse: () => FitMode.contain),
      fadeIn: us('fin'),
      fadeOut: us('fout'),
      animationIn: LayerAnimation.fromName(j['ain'] as String?),
      animationOut: LayerAnimation.fromName(j['aout'] as String?),
      sourceWidth: (j['w'] as num?)?.toInt() ?? 0,
      sourceHeight: (j['h'] as num?)?.toInt() ?? 0,
      cropLeft: d('cl', 0),
      cropTop: d('ct', 0),
      cropRight: d('cr', 0),
      cropBottom: d('cb', 0),
      thumbnailPath: j['thumb'] as String?,
      speedCurve: SpeedCurve.fromName(j['sc'] as String?),
      maskShape: MaskShape.fromName(j['mk'] as String?),
      maskFeather: d('mkf', 0.1),
      maskSize: d('mks', 0.6),
      maskX: d('mkx', 0.5),
      maskY: d('mky', 0.5),
      maskRotation: d('mkr', 0),
      maskInverted: j['mki'] as bool? ?? false,
      chromaKeyColor: (j['ck'] as num?)?.toInt(),
      chromaSimilarity: d('cks', 0.25),
      chromaBlend: d('ckb', 0.1),
      stabilize: j['stab'] as bool? ?? false,
      enhance: j['enh'] as bool? ?? false,
      voiceEnhance: j['venh'] as bool? ?? false,
      voiceEffect: VoiceEffect.values.firstWhere(
        (e) => e.name == j['vfx'],
        orElse: () => VoiceEffect.none,
      ),
      cutoutMattePath: j['matte'] as String?,
      lutPath: j['lut'] as String?,
    )..keyframesFromJson(j['kf'] as List?);
  }

  @override
  String toString() => 'VideoClip(${describeIdentity(this)}, $path)';
}
