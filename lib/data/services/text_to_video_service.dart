import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/utils/constants.dart';
import '../models/enums.dart';
import '../models/keyframe.dart';
import '../models/layers.dart';
import '../models/project.dart';
import '../models/video_clip.dart';
import '../repositories/project_repository.dart';
import 'media_probe.dart';
import 'tts_service.dart';

/// A ready-made look for a generated video: the background it paints and the
/// way the words sit on top of it.
///
/// Every field is a plain value rather than a Flutter object so a style can be
/// stored and compared by [id] alone.
class TextVideoStyle {
  const TextVideoStyle({
    required this.id,
    required this.name,
    required this.top,
    required this.bottom,
    required this.glow,
    required this.textColor,
    this.gradientTextColor,
    this.fontFamily = 'Poppins',
    this.bold = true,
    this.letterSpacing = 0,
    this.strokeColor = 0xCC000000,
    this.strokeWidth = 0,
    this.shadowBlur = 26,
    this.transition = TransitionType.fade,
    this.animationIn = LayerAnimation.fade,
    this.animationOut = LayerAnimation.fade,
    this.darkBackdrop = true,
  });

  final String id;
  final String name;

  /// Background gradient ends and the colour of the soft light blobs on it.
  final int top;
  final int bottom;
  final int glow;

  final int textColor;
  final int? gradientTextColor;
  final String fontFamily;
  final bool bold;
  final double letterSpacing;
  final int strokeColor;
  final double strokeWidth;
  final double shadowBlur;

  final TransitionType transition;
  final LayerAnimation animationIn;
  final LayerAnimation animationOut;

  /// False for the light styles, where the vignette under the text has to be
  /// painted white instead of black to keep dark words readable.
  final bool darkBackdrop;

  Color get topColor => Color(top);
  Color get bottomColor => Color(bottom);

  static const List<TextVideoStyle> all = [
    TextVideoStyle(
      id: 'aurora',
      name: 'Aurora',
      top: 0xFF3A1C71,
      bottom: 0xFF25123F,
      glow: 0xFFD76D77,
      textColor: 0xFFFFFFFF,
      animationIn: LayerAnimation.driftUp,
    ),
    TextVideoStyle(
      id: 'ocean',
      name: 'Ocean',
      top: 0xFF0F2027,
      bottom: 0xFF2C5364,
      glow: 0xFF2FC6FF,
      textColor: 0xFFFFFFFF,
      fontFamily: 'Oswald',
      letterSpacing: 1,
      animationIn: LayerAnimation.fade,
    ),
    TextVideoStyle(
      id: 'sunset',
      name: 'Sunset',
      top: 0xFFFF512F,
      bottom: 0xFF8A1E5C,
      glow: 0xFFFFC371,
      textColor: 0xFFFFFFFF,
      fontFamily: 'Anton',
      animationIn: LayerAnimation.pop,
      transition: TransitionType.smoothLeft,
    ),
    TextVideoStyle(
      id: 'neon',
      name: 'Neon',
      top: 0xFF0B0B1F,
      bottom: 0xFF1B0F3B,
      glow: 0xFF7C3AED,
      textColor: 0xFF7DF9FF,
      gradientTextColor: 0xFFFF6EC7,
      fontFamily: 'Bebas Neue',
      letterSpacing: 2,
      strokeWidth: 1.5,
      strokeColor: 0xFF120A2A,
      animationIn: LayerAnimation.scale,
      transition: TransitionType.dissolve,
    ),
    TextVideoStyle(
      id: 'ink',
      name: 'Ink',
      top: 0xFF161616,
      bottom: 0xFF2E2E2E,
      glow: 0xFF8A8A8A,
      textColor: 0xFFFFFFFF,
      fontFamily: 'Bebas Neue',
      letterSpacing: 1.5,
      transition: TransitionType.blackFade,
      animationIn: LayerAnimation.slideUp,
    ),
    TextVideoStyle(
      id: 'cream',
      name: 'Cream',
      top: 0xFFFFE9C7,
      bottom: 0xFFFFB79B,
      glow: 0xFFFFFFFF,
      textColor: 0xFF241A12,
      fontFamily: 'Poppins',
      shadowBlur: 0,
      darkBackdrop: false,
      animationIn: LayerAnimation.driftUp,
      transition: TransitionType.smoothUp,
    ),
  ];

  static TextVideoStyle byId(String? id) =>
      all.firstWhere((s) => s.id == id, orElse: () => all.first);
}

/// Everything the generator needs to turn a block of text into a project.
class TextToVideoRequest {
  const TextToVideoRequest({
    required this.script,
    this.title,
    this.ratio = CanvasRatio.r9x16,
    this.styleId = 'aurora',
    this.sceneDuration = const Duration(milliseconds: 3200),
    this.narrate = false,
    this.voice,
    this.speechRate = 0.5,
    this.kenBurns = true,
  });

  final String script;

  /// Optional headline shown as the first scene; null means the script alone.
  final String? title;
  final CanvasRatio ratio;
  final String styleId;

  /// Minimum on-screen time per scene. Longer lines get proportionally more.
  final Duration sceneDuration;

  /// Speak every scene with the device voice and time the scene to the audio.
  final bool narrate;
  final TtsVoice? voice;
  final double speechRate;
  final bool kenBurns;

  TextVideoStyle get style => TextVideoStyle.byId(styleId);
}

/// Progress report while a video is being built, so the screen can show what
/// is happening instead of a bare spinner.
class TextToVideoProgress {
  const TextToVideoProgress({
    required this.done,
    required this.total,
    required this.message,
  });

  final int done;
  final int total;
  final String message;

  double get fraction => total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);
}

/// Builds a complete, editable project out of nothing but typed text.
///
/// There is no cloud model behind this: every scene is a background this
/// service paints itself, the words on top of it, and — when asked — the
/// device's own speech engine narrating them. The result is an ordinary
/// project, so the editor and the FFmpeg exporter handle it like any other.
class TextToVideoService {
  TextToVideoService._();

  static final TextToVideoService instance = TextToVideoService._();

  /// Longest side of a generated background. 1920 keeps a 1080p export sharp
  /// while a flat gradient still compresses to a few hundred KB.
  static const int _maxSide = 1920;

  static const Duration _voiceLead = Duration(milliseconds: 250);
  static const Duration _voiceTail = Duration(milliseconds: 550);
  static const Duration _transitionLength = Duration(milliseconds: 500);
  static const Duration _minScene = Duration(milliseconds: 1200);
  static const Duration _maxScene = Duration(seconds: 14);

  // ------------------------------------------------------------ splitting

  /// Cuts [script] into one scene per thought: blank lines and line breaks
  /// first, then sentence endings, then a hard wrap for anything still too
  /// long to read in one breath.
  static List<String> splitScenes(String script, {int maxChars = 140}) {
    final out = <String>[];
    for (final line in script.split(RegExp(r'[\r\n]+'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      for (final sentence in _splitSentences(trimmed)) {
        out.addAll(_chunk(sentence, maxChars));
      }
    }
    return out;
  }

  /// Sentence boundaries for Latin punctuation plus the Devanagari danda, so
  /// Hindi scripts split as naturally as English ones.
  static List<String> _splitSentences(String text) {
    final out = <String>[];
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(ch);
      if (ch == '.' || ch == '!' || ch == '?' || ch == '।' || ch == '؟') {
        final s = buffer.toString().trim();
        if (s.isNotEmpty) out.add(s);
        buffer.clear();
      }
    }
    final rest = buffer.toString().trim();
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  /// Splits an over-long sentence at a comma if there is one, otherwise on
  /// word boundaries, so a scene never runs off the canvas.
  static List<String> _chunk(String sentence, int maxChars) {
    if (sentence.length <= maxChars) return [sentence];
    final out = <String>[];
    final words = sentence.split(RegExp(r'\s+'));
    final buffer = StringBuffer();
    for (final word in words) {
      final candidate = buffer.isEmpty ? word : '${buffer.toString()} $word';
      if (candidate.length > maxChars && buffer.isNotEmpty) {
        out.add(buffer.toString().trim());
        buffer
          ..clear()
          ..write(word);
      } else {
        buffer
          ..clear()
          ..write(candidate);
      }
      // A comma inside a long sentence is a natural cut point.
      if (buffer.length > maxChars * 0.6 && word.endsWith(',')) {
        out.add(buffer.toString().trim().replaceAll(RegExp(r',$'), ''));
        buffer.clear();
      }
    }
    final rest = buffer.toString().trim();
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  /// Greedy word wrap. The preview draws text unconstrained, so the line
  /// breaks have to live in the string itself.
  static String wrapLines(String text, int maxChars) {
    final words = text.split(RegExp(r'\s+'));
    final lines = <String>[];
    final buffer = StringBuffer();
    for (final word in words) {
      final candidate = buffer.isEmpty ? word : '${buffer.toString()} $word';
      if (candidate.length > maxChars && buffer.isNotEmpty) {
        lines.add(buffer.toString());
        buffer
          ..clear()
          ..write(word);
      } else {
        buffer
          ..clear()
          ..write(candidate);
      }
    }
    if (buffer.isNotEmpty) lines.add(buffer.toString());
    return lines.join('\n');
  }

  /// Characters that fit comfortably on one line at a readable size.
  static int _lineBudget(double aspect) {
    if (aspect < 0.8) return 18;
    if (aspect < 1.2) return 24;
    return 30;
  }

  /// Font size, in the editor's reference-canvas units, that keeps the
  /// longest line inside the frame and the whole block inside the height.
  static double _fitFontSize(String wrapped, double aspect) {
    final lines = wrapped.split('\n');
    final longest =
        lines.fold<int>(1, (m, l) => l.length > m ? l.length : m);
    final refWidth = kCanvasReferenceHeight * aspect;
    // Poppins/Anton average out near 0.55em per glyph at these weights.
    var size = (refWidth * 0.84) / (longest * 0.55);
    final byHeight = (kCanvasReferenceHeight * 0.74) / (lines.length * 1.28);
    size = math.min(size, byHeight);
    return size.clamp(26.0, 96.0);
  }

  /// How long a scene stays up when nobody is narrating it: the floor the
  /// user picked, stretched for lines that take longer to read.
  static Duration _readingTime(String scene, Duration floor) {
    final words = scene.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final read = Duration(milliseconds: (words * 420) + 900);
    final d = read > floor ? read : floor;
    if (d < _minScene) return _minScene;
    return d > _maxScene ? _maxScene : d;
  }

  /// Rough length of the finished video, used to label the generate button
  /// before anything is rendered.
  static Duration estimate(TextToVideoRequest request) {
    final scenes = splitScenes(request.script);
    if (scenes.isEmpty) return Duration.zero;
    var total = Duration.zero;
    for (final s in scenes) {
      total += _readingTime(s, request.sceneDuration);
    }
    // Every transition but the last eats its own length off the total.
    if (request.style.transition != TransitionType.none) {
      total -= _transitionLength * (scenes.length - 1);
    }
    return total < Duration.zero ? Duration.zero : total;
  }

  // ----------------------------------------------------------- generation

  /// Renders every scene and returns a saved, ready-to-edit project.
  ///
  /// Throws [TextToVideoException] when the script has nothing usable in it.
  Future<Project> generate(
    TextToVideoRequest request, {
    void Function(TextToVideoProgress)? onProgress,
  }) async {
    final scenes = <String>[
      if (request.title != null && request.title!.trim().isNotEmpty)
        request.title!.trim(),
      ...splitScenes(request.script),
    ];
    if (scenes.isEmpty) {
      throw const TextToVideoException('Type something to turn into a video.');
    }

    final style = request.style;
    final aspect = request.ratio.value ?? 9 / 16;
    final (width, height) = _frameSize(aspect);
    final project = Project(
      name: _projectName(request, scenes.first),
      ratio: request.ratio,
    );
    // The canvas behind the frames matches the art, so a ratio change in the
    // editor never reveals a black bar that clashes with the background.
    project.background
      ..type = BackgroundType.gradient
      ..gradientStart = style.top
      ..gradientEnd = style.bottom;

    final total = scenes.length;
    final voices = <String?>[];
    final voiceLengths = <Duration>[];

    for (var i = 0; i < scenes.length; i++) {
      final scene = scenes[i];
      onProgress?.call(TextToVideoProgress(
        done: i,
        total: total,
        message: 'Scene ${i + 1} of $total',
      ));

      final background = await _paintBackground(
        style: style,
        index: i,
        width: width,
        height: height,
        projectId: project.id,
      );

      String? voicePath;
      var voiceLength = Duration.zero;
      if (request.narrate) {
        onProgress?.call(TextToVideoProgress(
          done: i,
          total: total,
          message: 'Recording narration ${i + 1} of $total',
        ));
        voicePath = await TtsService.instance.synthesize(
          scene,
          voice: request.voice,
          rate: request.speechRate,
        );
        if (voicePath != null) {
          voiceLength = (await MediaProbe.probe(voicePath)).duration;
          if (voiceLength <= Duration.zero) {
            // An engine that reported success but wrote silence must not
            // collapse the scene to nothing.
            voicePath = null;
            voiceLength = Duration.zero;
          }
        }
      }
      voices.add(voicePath);
      voiceLengths.add(voiceLength);

      final duration = voiceLength > Duration.zero
          ? voiceLength + _voiceLead + _voiceTail
          : _readingTime(scene, request.sceneDuration);

      final clip = VideoClip(
        path: background,
        isImage: true,
        hasAudio: false,
        sourceDuration: duration,
        sourceWidth: width,
        sourceHeight: height,
        fit: FitMode.cover,
        transitionType:
            i == scenes.length - 1 ? TransitionType.none : style.transition,
        transitionDuration: _transitionLength,
      );

      if (request.kenBurns) {
        // Slow push in and out on alternate scenes — the same two-keyframe
        // Ken Burns the templates use, so it stays editable afterwards.
        final zoomIn = i.isEven;
        clip.track(KeyframeProperty.scale)
          ..set(Duration.zero, zoomIn ? 1.0 : 1.10,
              easing: KeyframeEasing.linear)
          ..set(duration, zoomIn ? 1.10 : 1.0,
              easing: KeyframeEasing.easeInOut);
      }

      project.clips.add(clip);
      if (i == 0) project.coverPath = background;
    }

    // Text and narration are laid out only once every clip exists, because a
    // scene's start depends on how much the transitions before it overlap.
    final budget = _lineBudget(aspect);
    for (var i = 0; i < scenes.length; i++) {
      final start = project.clipStart(i);
      final span =
          project.clips[i].timelineDuration - project.overlapAfter(i);
      final isTitle = i == 0 && request.title != null;
      // A title wraps sooner, which is what makes it read bigger — scaling
      // the fitted size up instead would push it past the frame edge.
      final wrapped = wrapLines(scenes[i], isTitle ? budget - 4 : budget);

      project.texts.add(TextLayer(
        start: start,
        duration: span < _minScene ? _minScene : span,
        text: wrapped,
        fontFamily: style.fontFamily,
        fontSize: _fitFontSize(wrapped, aspect),
        color: style.textColor,
        gradientColor: style.gradientTextColor,
        bold: style.bold,
        letterSpacing: style.letterSpacing,
        lineHeight: 1.28,
        strokeWidth: style.strokeWidth,
        strokeColor: style.strokeColor,
        shadowBlur: style.shadowBlur,
        shadowColor: style.darkBackdrop ? 0xAA000000 : 0x33000000,
        shadowOffsetX: 0,
        shadowOffsetY: 6,
        animationIn: style.animationIn,
        animationOut: style.animationOut,
        animationDuration: const Duration(milliseconds: 420),
        transform: LayerTransform(x: 0.5, y: 0.5),
      ));

      final voicePath = voices[i];
      if (voicePath != null) {
        project.audios.add(AudioLayer(
          start: start + _voiceLead,
          duration: voiceLengths[i],
          path: voicePath,
          title: 'Narration ${i + 1}',
          sourceDuration: voiceLengths[i],
          kind: AudioKind.voiceover,
        ));
      }
    }

    onProgress?.call(TextToVideoProgress(
      done: total,
      total: total,
      message: 'Saving project',
    ));
    await ProjectRepository.instance.save(project);
    return project;
  }

  String _projectName(TextToVideoRequest request, String firstScene) {
    final source = (request.title?.trim().isNotEmpty ?? false)
        ? request.title!.trim()
        : firstScene;
    final flat = source.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.isEmpty) return 'Text video';
    return flat.length <= 28 ? flat : '${flat.substring(0, 28).trim()}…';
  }

  /// Output pixels for [aspect], kept even because encoders reject odd sizes.
  (int, int) _frameSize(double aspect) {
    int even(num v) {
      final r = v.round();
      return r.isEven ? r : r + 1;
    }

    if (aspect >= 1) return (even(_maxSide), even(_maxSide / aspect));
    return (even(_maxSide * aspect), even(_maxSide));
  }

  // --------------------------------------------------------- backgrounds

  /// Paints one scene background and writes it into the project media folder.
  ///
  /// Each scene is seeded by its index, so the same script re-generates the
  /// same art and no two neighbouring scenes look identical.
  Future<String> _paintBackground({
    required TextVideoStyle style,
    required int index,
    required int width,
    required int height,
    required String projectId,
  }) async {
    final random = math.Random(index * 977 + 13);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

    // Base gradient, rotated a little per scene so a long script does not
    // read as the same frame repeated.
    final tilt = (index % 4) * 0.25;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-1 + tilt, -1),
          end: Alignment(1, 1 - tilt),
          colors: [style.topColor, style.bottomColor],
        ).createShader(rect),
    );

    // Soft light blobs. Drawn with a blur mask rather than many gradient
    // stops so the cost stays flat regardless of output size.
    final glow = Color(style.glow);
    for (var i = 0; i < 3; i++) {
      final radius = rect.shortestSide * (0.30 + random.nextDouble() * 0.32);
      final center = Offset(
        rect.width * (0.12 + random.nextDouble() * 0.76),
        rect.height * (0.12 + random.nextDouble() * 0.76),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = glow.withValues(alpha: 0.12 + random.nextDouble() * 0.14)
          // Sigma stays a modest fraction of the frame: a blur wider than
          // this costs real time per scene without looking any softer.
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, rect.shortestSide * 0.09),
      );
    }

    // A couple of thin arcs give the flat gradient some structure.
    for (var i = 0; i < 2; i++) {
      final r = rect.shortestSide * (0.55 + i * 0.22);
      canvas.drawCircle(
        Offset(rect.width * (i.isEven ? 0.18 : 0.86),
            rect.height * (i.isEven ? 0.24 : 0.78)),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rect.shortestSide * 0.006
          ..color = glow.withValues(alpha: 0.10),
      );
    }

    // Vignette: darker at the edges on dark styles, lighter on the pale one,
    // so the words in the middle always keep their contrast.
    final veil = style.darkBackdrop ? Colors.black : Colors.white;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [
            veil.withValues(alpha: 0.0),
            veil.withValues(alpha: style.darkBackdrop ? 0.34 : 0.24),
          ],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );
    // A gentle band behind the centre line where the text sits.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            veil.withValues(alpha: 0.0),
            veil.withValues(alpha: style.darkBackdrop ? 0.26 : 0.18),
            veil.withValues(alpha: 0.0),
          ],
          stops: const [0.22, 0.5, 0.82],
        ).createShader(rect),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (bytes == null) {
      throw const TextToVideoException('Could not render the scene artwork.');
    }

    final dir = await ProjectRepository.instance.mediaDir();
    final file = File('${dir.path}/t2v_${projectId}_$index.png');
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file.path;
  }
}

/// Raised when a script cannot be turned into a video at all.
class TextToVideoException implements Exception {
  const TextToVideoException(this.message);

  final String message;

  @override
  String toString() => message;
}
