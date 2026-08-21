import 'dart:math' as math;
import 'dart:ui';

import '../../core/utils/id.dart';
import 'adjustments.dart';
import 'enums.dart';
import 'filter_preset.dart';
import 'keyframe.dart';

/// Anything that lives on a secondary lane and is bounded by a start time
/// and a duration on the master timeline.
abstract class TimelineLayer {
  TimelineLayer({
    String? id,
    required this.start,
    required this.duration,
  }) : id = id ?? newId();

  final String id;
  Duration start;
  Duration duration;

  Duration get end => start + duration;

  bool isVisibleAt(Duration t) => t >= start && t < end;

  Map<String, dynamic> toJson();
}

/// Transform shared by every visual overlay (text, sticker, PIP).
class LayerTransform {
  LayerTransform({
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.opacity = 1.0,
  });

  /// Normalised canvas position, 0..1 (centre of the layer).
  double x;
  double y;
  double scale;

  /// Radians.
  double rotation;
  double opacity;

  LayerTransform copy() =>
      LayerTransform(x: x, y: y, scale: scale, rotation: rotation, opacity: opacity);

  Map<String, dynamic> toJson() =>
      {'x': x, 'y': y, 's': scale, 'r': rotation, 'o': opacity};

  factory LayerTransform.fromJson(Map<String, dynamic>? j) {
    if (j == null) return LayerTransform();
    double v(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
    return LayerTransform(
      x: v('x', 0.5),
      y: v('y', 0.5),
      scale: v('s', 1),
      rotation: v('r', 0),
      opacity: v('o', 1),
    );
  }
}

/// Text layer with full styling controls.
class TextLayer extends TimelineLayer with Keyframable {
  TextLayer({
    super.id,
    required super.start,
    required super.duration,
    this.text = 'Tap to edit',
    this.fontFamily = 'Poppins',
    this.fontSize = 64,
    this.color = 0xFFFFFFFF,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.align = TextAlign.center,
    this.letterSpacing = 0,
    this.lineHeight = 1.2,
    this.strokeWidth = 0,
    this.strokeColor = 0xFF000000,
    this.shadowBlur = 0,
    this.shadowColor = 0xB3000000,
    this.shadowOffsetX = 4,
    this.shadowOffsetY = 4,
    this.backgroundColor = 0x00000000,
    this.backgroundRadius = 14,
    this.backgroundPadding = 22,
    this.animationIn = LayerAnimation.none,
    this.animationOut = LayerAnimation.none,
    this.animationDuration = const Duration(milliseconds: 500),
    this.stylePresetId,
    this.gradientColor,
    this.isCaption = false,
    LayerTransform? transform,
  }) : transform = transform ?? LayerTransform();

  String text;
  String fontFamily;
  double fontSize;
  int color;
  bool bold;
  bool italic;
  bool underline;
  TextAlign align;
  double letterSpacing;
  double lineHeight;

  double strokeWidth;
  int strokeColor;
  double shadowBlur;
  int shadowColor;
  double shadowOffsetX;
  double shadowOffsetY;
  int backgroundColor;
  double backgroundRadius;
  double backgroundPadding;

  LayerAnimation animationIn;
  LayerAnimation animationOut;
  Duration animationDuration;

  /// Id of the preset this text was styled from, for the picker's highlight.
  String? stylePresetId;

  /// Second colour for a gradient fill; null keeps the flat [color].
  int? gradientColor;

  /// Marks a layer produced by the caption tool, so captions can be
  /// restyled or cleared as a group without touching hand-placed text.
  bool isCaption;
  LayerTransform transform;

  TextLayer copy() => TextLayer.fromJson(toJson()..['id'] = newId());

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.inMicroseconds,
        'dur': duration.inMicroseconds,
        'text': text,
        'font': fontFamily,
        'size': fontSize,
        'color': color,
        'bold': bold,
        'italic': italic,
        'underline': underline,
        'align': align.name,
        'ls': letterSpacing,
        'lh': lineHeight,
        'sw': strokeWidth,
        'sc': strokeColor,
        'sb': shadowBlur,
        'shc': shadowColor,
        'sox': shadowOffsetX,
        'soy': shadowOffsetY,
        'bg': backgroundColor,
        'bgr': backgroundRadius,
        'bgp': backgroundPadding,
        'ain': animationIn.name,
        'aout': animationOut.name,
        'ad': animationDuration.inMicroseconds,
        'tf': transform.toJson(),
        'preset': stylePresetId,
        'grad': gradientColor,
        'caption': isCaption,
        'kf': keyframesToJson(),
      };

  factory TextLayer.fromJson(Map<String, dynamic> j) {
    double v(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
    return TextLayer(
      id: j['id'] as String?,
      start: Duration(microseconds: (j['start'] as num?)?.toInt() ?? 0),
      duration: Duration(microseconds: (j['dur'] as num?)?.toInt() ?? 3000000),
      text: j['text'] as String? ?? '',
      fontFamily: j['font'] as String? ?? 'Poppins',
      fontSize: v('size', 64),
      color: (j['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
      bold: j['bold'] as bool? ?? false,
      italic: j['italic'] as bool? ?? false,
      underline: j['underline'] as bool? ?? false,
      align: TextAlign.values.firstWhere((e) => e.name == j['align'],
          orElse: () => TextAlign.center),
      letterSpacing: v('ls', 0),
      lineHeight: v('lh', 1.2),
      strokeWidth: v('sw', 0),
      strokeColor: (j['sc'] as num?)?.toInt() ?? 0xFF000000,
      shadowBlur: v('sb', 0),
      shadowColor: (j['shc'] as num?)?.toInt() ?? 0xB3000000,
      shadowOffsetX: v('sox', 2),
      shadowOffsetY: v('soy', 2),
      backgroundColor: (j['bg'] as num?)?.toInt() ?? 0x00000000,
      backgroundRadius: v('bgr', 6),
      backgroundPadding: v('bgp', 10),
      animationIn: LayerAnimation.fromName(j['ain'] as String?),
      animationOut: LayerAnimation.fromName(j['aout'] as String?),
      animationDuration:
          Duration(microseconds: (j['ad'] as num?)?.toInt() ?? 500000),
      transform: LayerTransform.fromJson(j['tf'] as Map<String, dynamic>?),
      stylePresetId: j['preset'] as String?,
      gradientColor: (j['grad'] as num?)?.toInt(),
      isCaption: j['caption'] as bool? ?? false,
    )..keyframesFromJson(j['kf'] as List?);
  }
}

/// Emoji / shape sticker layer.
class StickerLayer extends TimelineLayer with Keyframable {
  StickerLayer({
    super.id,
    required super.start,
    required super.duration,
    required this.content,
    this.isEmoji = true,
    this.color = 0xFFFFFFFF,
    this.size = 200,
    this.animationIn = LayerAnimation.none,
    this.animationOut = LayerAnimation.none,
    this.animationDuration = const Duration(milliseconds: 400),
    LayerTransform? transform,
  }) : transform = transform ?? LayerTransform();

  /// Emoji glyph, or a shape key when [isEmoji] is false.
  String content;
  bool isEmoji;
  int color;
  double size;
  LayerAnimation animationIn;
  LayerAnimation animationOut;
  Duration animationDuration;
  LayerTransform transform;

  StickerLayer copy() => StickerLayer.fromJson(toJson()..['id'] = newId());

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.inMicroseconds,
        'dur': duration.inMicroseconds,
        'content': content,
        'emoji': isEmoji,
        'color': color,
        'size': size,
        'ain': animationIn.name,
        'aout': animationOut.name,
        'ad': animationDuration.inMicroseconds,
        'tf': transform.toJson(),
        'kf': keyframesToJson(),
      };

  factory StickerLayer.fromJson(Map<String, dynamic> j) => StickerLayer(
        id: j['id'] as String?,
        start: Duration(microseconds: (j['start'] as num?)?.toInt() ?? 0),
        duration: Duration(microseconds: (j['dur'] as num?)?.toInt() ?? 3000000),
        content: j['content'] as String? ?? '⭐',
        isEmoji: j['emoji'] as bool? ?? true,
        color: (j['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
        size: (j['size'] as num?)?.toDouble() ?? 200,
        animationIn: LayerAnimation.fromName(j['ain'] as String?),
        animationOut: LayerAnimation.fromName(j['aout'] as String?),
        animationDuration:
            Duration(microseconds: (j['ad'] as num?)?.toInt() ?? 400000),
        transform: LayerTransform.fromJson(j['tf'] as Map<String, dynamic>?),
      )..keyframesFromJson(j['kf'] as List?);
}

/// Picture-in-picture video/image layer floating over the main track.
class OverlayLayer extends TimelineLayer with Keyframable {
  OverlayLayer({
    super.id,
    required super.start,
    required super.duration,
    required this.path,
    required this.isImage,
    required this.sourceDuration,
    this.hasAudio = true,
    Duration? trimStart,
    this.speed = 1.0,
    this.volume = 1.0,
    this.filterId = 'none',
    this.filterIntensity = 1.0,
    Adjustments? adjustments,
    this.cornerRadius = 0,
    this.blendMode = BlendMode2.normal,
    this.chromaKeyColor,
    this.chromaSimilarity = 0.2,
    this.chromaBlend = 0.1,
    this.animationIn = LayerAnimation.none,
    this.animationOut = LayerAnimation.none,
    this.animationDuration = const Duration(milliseconds: 400),
    LayerTransform? transform,
    this.sourceWidth = 0,
    this.sourceHeight = 0,
    this.maskShape = MaskShape.none,
    this.maskFeather = 0.1,
    this.maskSize = 0.6,
    this.maskX = 0.5,
    this.maskY = 0.5,
    this.maskRotation = 0,
    this.maskInverted = false,
  })  : trimStart = trimStart ?? Duration.zero,
        adjustments = adjustments ?? Adjustments(),
        transform = transform ?? LayerTransform(scale: 0.5);

  String path;
  bool isImage;
  bool hasAudio;
  Duration sourceDuration;
  Duration trimStart;
  double speed;
  double volume;
  String filterId;
  double filterIntensity;
  Adjustments adjustments;
  double cornerRadius;
  BlendMode2 blendMode;
  MaskShape maskShape;
  double maskFeather;
  double maskSize;
  double maskX;
  double maskY;
  double maskRotation;
  bool maskInverted;
  int? chromaKeyColor;
  double chromaSimilarity;
  double chromaBlend;
  LayerAnimation animationIn;
  LayerAnimation animationOut;
  Duration animationDuration;
  LayerTransform transform;
  int sourceWidth;
  int sourceHeight;

  FilterPreset get gradedFilter => adjustments
      .merge(FilterPreset.fromId(filterId).lerpFromIdentity(filterIntensity));

  double get sourceAspect =>
      (sourceWidth > 0 && sourceHeight > 0) ? sourceWidth / sourceHeight : 16 / 9;

  OverlayLayer copy() => OverlayLayer.fromJson(toJson()..['id'] = newId());

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.inMicroseconds,
        'dur': duration.inMicroseconds,
        'path': path,
        'isImage': isImage,
        'hasAudio': hasAudio,
        'src': sourceDuration.inMicroseconds,
        'ts': trimStart.inMicroseconds,
        'speed': speed,
        'volume': volume,
        'filterId': filterId,
        'filterIntensity': filterIntensity,
        'adj': adjustments.toJson(),
        'radius': cornerRadius,
        'blend': blendMode.name,
        'ck': chromaKeyColor,
        'cks': chromaSimilarity,
        'ckb': chromaBlend,
        'mk': maskShape.name,
        'mkf': maskFeather,
        'mks': maskSize,
        'mkx': maskX,
        'mky': maskY,
        'mkr': maskRotation,
        'mki': maskInverted,
        'kf': keyframesToJson(),
        'ain': animationIn.name,
        'aout': animationOut.name,
        'ad': animationDuration.inMicroseconds,
        'tf': transform.toJson(),
        'w': sourceWidth,
        'h': sourceHeight,
      };

  factory OverlayLayer.fromJson(Map<String, dynamic> j) => OverlayLayer(
        id: j['id'] as String?,
        start: Duration(microseconds: (j['start'] as num?)?.toInt() ?? 0),
        duration: Duration(microseconds: (j['dur'] as num?)?.toInt() ?? 3000000),
        path: j['path'] as String,
        isImage: j['isImage'] as bool? ?? false,
        hasAudio: j['hasAudio'] as bool? ?? true,
        sourceDuration: Duration(microseconds: (j['src'] as num?)?.toInt() ?? 0),
        trimStart: Duration(microseconds: (j['ts'] as num?)?.toInt() ?? 0),
        speed: (j['speed'] as num?)?.toDouble() ?? 1,
        volume: (j['volume'] as num?)?.toDouble() ?? 1,
        filterId: j['filterId'] as String? ?? 'none',
        filterIntensity: (j['filterIntensity'] as num?)?.toDouble() ?? 1,
        adjustments: Adjustments.fromJson(j['adj'] as Map<String, dynamic>?),
        cornerRadius: (j['radius'] as num?)?.toDouble() ?? 0,
        blendMode: BlendMode2.fromName(j['blend'] as String?),
        chromaKeyColor: (j['ck'] as num?)?.toInt(),
        chromaSimilarity: (j['cks'] as num?)?.toDouble() ?? 0.2,
        chromaBlend: (j['ckb'] as num?)?.toDouble() ?? 0.1,
        maskShape: MaskShape.fromName(j['mk'] as String?),
        maskFeather: (j['mkf'] as num?)?.toDouble() ?? 0.1,
        maskSize: (j['mks'] as num?)?.toDouble() ?? 0.6,
        maskX: (j['mkx'] as num?)?.toDouble() ?? 0.5,
        maskY: (j['mky'] as num?)?.toDouble() ?? 0.5,
        maskRotation: (j['mkr'] as num?)?.toDouble() ?? 0,
        maskInverted: j['mki'] as bool? ?? false,
        animationIn: LayerAnimation.fromName(j['ain'] as String?),
        animationOut: LayerAnimation.fromName(j['aout'] as String?),
        animationDuration:
            Duration(microseconds: (j['ad'] as num?)?.toInt() ?? 400000),
        transform: LayerTransform.fromJson(j['tf'] as Map<String, dynamic>?),
        sourceWidth: (j['w'] as num?)?.toInt() ?? 0,
        sourceHeight: (j['h'] as num?)?.toInt() ?? 0,
      )..keyframesFromJson(j['kf'] as List?);
}

/// Music / voice-over / sound-effect lane item.
class AudioLayer extends TimelineLayer with Keyframable {
  AudioLayer({
    super.id,
    required super.start,
    required super.duration,
    required this.path,
    required this.title,
    required this.sourceDuration,
    Duration? trimStart,
    this.kind = AudioKind.music,
    this.volume = 1.0,
    this.speed = 1.0,
    this.fadeIn = Duration.zero,
    this.fadeOut = Duration.zero,
    this.loop = false,
    this.pitch = 0,
    this.voiceEffect = VoiceEffect.none,
    List<double>? waveform,
    List<Duration>? beats,
  })  : trimStart = trimStart ?? Duration.zero,
        waveform = waveform ?? const [],
        beats = beats ?? const [];

  String path;
  String title;
  Duration sourceDuration;
  Duration trimStart;
  AudioKind kind;
  double volume;
  double speed;
  Duration fadeIn;
  Duration fadeOut;
  bool loop;

  /// Semitone shift, -12..12.
  double pitch;
  VoiceEffect voiceEffect;

  /// Cached 0..1 amplitude samples used to draw the lane.
  List<double> waveform;

  /// Detected onsets, drawn as tick marks so cuts can be snapped to them.
  List<Duration> beats;

  Duration get trimEnd => trimStart + duration;

  AudioLayer copy() => AudioLayer.fromJson(toJson()..['id'] = newId());

  /// Combined rate/pitch chain for FFmpeg. Pitch shifting is done by
  /// resampling then correcting the tempo, so speed and pitch stay separable.
  List<String> audioFilterChain() {
    final out = <String>[];
    final semitones = pitch + voiceEffect.semitones;
    if (semitones != 0) {
      final ratio = math.pow(2, semitones / 12).toDouble();
      out.add('asetrate=48000*${ratio.toStringAsFixed(5)}');
      out.add('aresample=48000');
      out.add('atempo=${(1 / ratio).clamp(0.5, 2.0).toStringAsFixed(5)}');
    }
    if (voiceEffect.echo) out.add('aecho=0.8:0.85:60:0.35');
    if (voiceEffect.isRobot) out.add('afftfilt=real=\'hypot(re,im)*cos(0)\':imag=\'hypot(re,im)*sin(0)\':win_size=512:overlap=0.75');
    return out;
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.inMicroseconds,
        'dur': duration.inMicroseconds,
        'path': path,
        'title': title,
        'src': sourceDuration.inMicroseconds,
        'ts': trimStart.inMicroseconds,
        'kind': kind.name,
        'volume': volume,
        'speed': speed,
        'fin': fadeIn.inMicroseconds,
        'fout': fadeOut.inMicroseconds,
        'loop': loop,
        'pitch': pitch,
        'fx': voiceEffect.name,
        'wave': waveform,
        'beats': beats.map((b) => b.inMilliseconds).toList(),
        'kf': keyframesToJson(),
      };

  factory AudioLayer.fromJson(Map<String, dynamic> j) => AudioLayer(
        id: j['id'] as String?,
        start: Duration(microseconds: (j['start'] as num?)?.toInt() ?? 0),
        duration: Duration(microseconds: (j['dur'] as num?)?.toInt() ?? 0),
        path: j['path'] as String,
        title: j['title'] as String? ?? 'Audio',
        sourceDuration: Duration(microseconds: (j['src'] as num?)?.toInt() ?? 0),
        trimStart: Duration(microseconds: (j['ts'] as num?)?.toInt() ?? 0),
        kind: AudioKind.values.firstWhere((e) => e.name == j['kind'],
            orElse: () => AudioKind.music),
        volume: (j['volume'] as num?)?.toDouble() ?? 1,
        speed: (j['speed'] as num?)?.toDouble() ?? 1,
        fadeIn: Duration(microseconds: (j['fin'] as num?)?.toInt() ?? 0),
        fadeOut: Duration(microseconds: (j['fout'] as num?)?.toInt() ?? 0),
        loop: j['loop'] as bool? ?? false,
        pitch: (j['pitch'] as num?)?.toDouble() ?? 0,
        voiceEffect: VoiceEffect.fromName(j['fx'] as String?),
        waveform: (j['wave'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        beats: (j['beats'] as List?)
            ?.map((e) => Duration(milliseconds: (e as num).toInt()))
            .toList(),
      )..keyframesFromJson(j['kf'] as List?);
}
