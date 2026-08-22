import 'dart:async';

import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/duration_ext.dart';
import '../models/enums.dart';
import '../models/keyframe.dart';
import '../models/layers.dart';
import '../models/project.dart';
import '../models/video_clip.dart';
import '../repositories/project_repository.dart';
import 'export_settings.dart';
import 'hsl_lut.dart';
import 'overlay_rasterizer.dart';
import '../models/watermark.dart';

/// Live state of a render.
class ExportProgress {
  const ExportProgress({
    required this.stage,
    required this.value,
    this.eta,
    this.speed = 0,
  });

  final String stage;

  /// 0..1, or -1 when the stage is indeterminate.
  final double value;
  final Duration? eta;
  final double speed;
}

class ExportResult {
  const ExportResult({required this.success, this.path, this.error, this.log});

  final bool success;
  final String? path;
  final String? error;
  final String? log;
}

/// Turns a [Project] into a single H.264/AAC MP4.
///
/// The whole timeline is described as one FFmpeg filter graph, which keeps the
/// render to a single pass: no intermediate files, no generation loss.
class ExportService {
  ExportService._();

  static final ExportService instance = ExportService._();

  int? _sessionId;
  bool _cancelled = false;

  Future<void> cancel() async {
    _cancelled = true;
    final id = _sessionId;
    if (id != null) await FFmpegKit.cancel(id);
  }

  /// The filter graph the exporter would build for [project], without
  /// running it.
  ///
  /// A setting can be stored, serialised and shown in its panel and still
  /// reach nothing — clip animation was exactly that for a long time: two
  /// fields the model carried, the JSON kept and no renderer ever read. A
  /// test that only presses the button cannot see it. This is how a test
  /// asks the one question that matters: does the tool reach the render.
  @visibleForTesting
  static String debugCommandFor(
    Project project,
    ExportSettings settings, {
    Map<String, RasterizedLayer> rasterized = const {},
    Map<String, String> hslLuts = const {},
  }) => _GraphBuilder(
    project: project,
    settings: settings,
    rasterized: rasterized,
    totalDuration: project.totalDuration,
    hslLuts: hslLuts,
  ).build('/tmp/probe.mp4');

  /// The key the watermark's baked PNG is filed under, so a test can supply
  /// one without reaching into the private half of this file.
  @visibleForTesting
  static const String watermarkKey = _kWatermarkKey;

  /// The same, for the design frame and the FX texture.
  @visibleForTesting
  static const String frameKey = _kFrameKey;

  @visibleForTesting
  static const String fxKey = _kFxKey;

  Future<ExportResult> export(
    Project project,
    ExportSettings settings, {
    void Function(ExportProgress)? onProgress,
    String? outputPath,
  }) async {
    _cancelled = false;
    if (project.clips.isEmpty) {
      return const ExportResult(success: false, error: 'Timeline is empty');
    }

    final total = project.totalDuration;
    onProgress?.call(const ExportProgress(stage: 'Preparing', value: -1));

    final dir = await ProjectRepository.instance.exportDir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = project.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final out = outputPath ?? '${dir.path}/${safeName}_$stamp.mp4';

    // Bake text and sticker layers to PNG at output resolution.
    onProgress?.call(
      const ExportProgress(stage: 'Rendering overlays', value: -1),
    );
    final rasterized = <String, RasterizedLayer>{};
    for (final t in project.texts) {
      if (t.text.trim().isEmpty) continue;
      final r = await OverlayRasterizer.instance.rasterizeText(
        t,
        outWidth: settings.width,
        outHeight: settings.height,
      );
      if (r != null) rasterized[t.id] = r;
    }
    for (final s in project.stickers) {
      final r = await OverlayRasterizer.instance.rasterizeSticker(
        s,
        outWidth: settings.width,
        outHeight: settings.height,
      );
      if (r != null) rasterized[s.id] = r;
    }
    if (project.hasFx) {
      final r = await OverlayRasterizer.instance.rasterizeFx(
        project.fx,
        project.fxIntensity,
        outWidth: settings.width,
        outHeight: settings.height,
      );
      if (r != null) rasterized[_kFxKey] = r;
    }
    if (project.hasFrame) {
      final r = await OverlayRasterizer.instance.rasterizeFrame(
        project.frame,
        outWidth: settings.width,
        outHeight: settings.height,
      );
      if (r != null) rasterized[_kFrameKey] = r;
    }
    final mark = project.watermark;
    if (mark.isReady) {
      // The text mark is baked through the very same path a text layer takes,
      // so what the creator positioned in the preview is what gets burned in.
      final r = mark.type == WatermarkType.text
          ? await OverlayRasterizer.instance.rasterizeText(
              mark.asTextLayer(),
              outWidth: settings.width,
              outHeight: settings.height,
              opacity: mark.transform.opacity,
            )
          : await OverlayRasterizer.instance.rasterizeWatermarkImage(
              mark,
              outWidth: settings.width,
              outHeight: settings.height,
            );
      if (r != null) rasterized[_kWatermarkKey] = r;
    }
    if (_cancelled) {
      return const ExportResult(success: false, error: 'Cancelled');
    }

    // Per-hue grading has no FFmpeg filter of its own, so each target that
    // carries one gets its grade baked into a 3D LUT here and applied with
    // `lut3d`. Baking is cheap — a 33-point cube — and it happens once per
    // export rather than once per frame.
    final hslLuts = <String, String>{};
    for (final clip in project.clips) {
      if (clip.adjustments.hsl.isNeutral) continue;
      final path = await HslLut.write(clip.adjustments.hsl, dir);
      if (path != null) hslLuts[clip.id] = path;
    }
    for (final pip in project.overlays) {
      if (pip.adjustments.hsl.isNeutral) continue;
      final path = await HslLut.write(pip.adjustments.hsl, dir);
      if (path != null) hslLuts[pip.id] = path;
    }

    final graph = _GraphBuilder(
      project: project,
      settings: settings,
      rasterized: rasterized,
      totalDuration: total,
      hslLuts: hslLuts,
    );
    final command = graph.build(out);
    debugPrint('FFmpeg command:\n$command');

    final completer = Completer<ExportResult>();
    final logBuffer = StringBuffer();
    final startedAt = DateTime.now();

    FFmpegKitConfig.enableStatisticsCallback((stats) {
      if (total.inMilliseconds <= 0) return;
      final done = stats.getTime().clamp(0, total.inMilliseconds);
      final value = done / total.inMilliseconds;
      final elapsed = DateTime.now().difference(startedAt);
      final eta = value > 0.02
          ? Duration(
              milliseconds: (elapsed.inMilliseconds * (1 - value) / value)
                  .round(),
            )
          : null;
      onProgress?.call(
        ExportProgress(
          stage: 'Exporting',
          value: value.toDouble(),
          eta: eta,
          speed: stats.getSpeed(),
        ),
      );
    });

    final session = await FFmpegKit.executeAsync(
      command,
      (s) async {
        _sessionId = null;
        final rc = await s.getReturnCode();
        if (ReturnCode.isSuccess(rc)) {
          onProgress?.call(const ExportProgress(stage: 'Finishing', value: 1));
          completer.complete(ExportResult(success: true, path: out));
        } else if (ReturnCode.isCancel(rc) || _cancelled) {
          completer.complete(
            const ExportResult(success: false, error: 'Cancelled'),
          );
        } else {
          completer.complete(
            ExportResult(
              success: false,
              error: 'Render failed (code ${rc?.getValue()})',
              log: logBuffer.toString(),
            ),
          );
        }
      },
      (log) {
        final m = log.getMessage();
        logBuffer.write(m);
        if (logBuffer.length > 20000) {
          final s = logBuffer.toString();
          logBuffer
            ..clear()
            ..write(s.substring(s.length - 12000));
        }
      },
    );
    _sessionId = session.getSessionId();
    return completer.future;
  }
}

/// Keys the baked whole-canvas overlays are filed under in the rasterized
/// map, alongside the per-layer entries.
const String _kFrameKey = 'design_frame';
const String _kFxKey = 'design_fx';

/// Key the baked watermark is filed under in the rasterized map. Layer ids
/// are uuids, so this cannot collide with a real layer.
const String _kWatermarkKey = 'watermark';

/// Builds the single filter graph that represents the whole timeline.
class _GraphBuilder {
  _GraphBuilder({
    required this.project,
    required this.settings,
    required this.rasterized,
    required this.totalDuration,
    required this.hslLuts,
  });

  final Project project;
  final ExportSettings settings;
  final Map<String, RasterizedLayer> rasterized;
  final Duration totalDuration;

  /// Baked per-hue grades, by the id of the clip or overlay they belong to.
  final Map<String, String> hslLuts;

  final List<String> _inputs = [];
  final List<String> _filters = [];
  int _inputIndex = 0;

  /// Input index of each main-track clip. Background generators add extra
  /// inputs in between, so positions cannot be assumed from the clip order.
  final Map<int, int> _clipInputs = {};

  /// Input index of each PIP layer, recorded while its video chain is built
  /// so the audio pass can reference the same input.
  final Map<int, int> _pipInputs = {};

  int get _w => settings.width;
  int get _h => settings.height;
  int get _fps => settings.fps.value;

  String build(String outputPath) {
    final videoLabel = _buildVideoTrack();
    final composited = _applyVisualOverlays(videoLabel);
    final audioLabel = _buildAudio();

    final filterComplex = _filters.join(';');
    final maps = StringBuffer('-map "[$composited]"');
    if (audioLabel != null) maps.write(' -map "[$audioLabel]"');

    final b = StringBuffer('-hide_banner -y ');
    b.write(_inputs.join(' '));
    b.write(' -filter_complex "$filterComplex" ');
    b.write(maps.toString());
    b.write(' -c:v libx264 -preset ${settings.preset}');
    b.write(' -b:v ${settings.videoBitrateKbps}k');
    b.write(' -maxrate ${(settings.videoBitrateKbps * 1.5).round()}k');
    b.write(' -bufsize ${(settings.videoBitrateKbps * 2).round()}k');
    b.write(' -pix_fmt yuv420p -profile:v high -level 4.2');
    b.write(' -r $_fps -g ${_fps * 2}');
    if (audioLabel != null) {
      b.write(' -c:a aac -b:a ${settings.audioBitrateKbps}k -ar 48000 -ac 2');
    } else {
      b.write(' -an');
    }
    b.write(' -movflags +faststart');
    b.write(' -t ${totalDuration.seconds.toStringAsFixed(3)}');
    b.write(' ${_quote(outputPath)}');
    return b.toString();
  }

  // ---------------------------------------------------------------- video

  String _buildVideoTrack() {
    final clipLabels = <String>[];
    for (var i = 0; i < project.clips.length; i++) {
      clipLabels.add(_buildClip(project.clips[i], i));
    }

    // Runs of clips with no transition are concatenated; the boundaries that
    // do carry a transition become xfade joints between those runs.
    final groups = <List<int>>[
      [0],
    ];
    for (var i = 1; i < project.clips.length; i++) {
      if (project.clips[i - 1].transitionType == TransitionType.none) {
        groups.last.add(i);
      } else {
        groups.add([i]);
      }
    }

    final groupLabels = <String>[];
    for (var g = 0; g < groups.length; g++) {
      final members = groups[g];
      if (members.length == 1) {
        groupLabels.add(clipLabels[members.first]);
      } else {
        final ins = members.map((i) => '[${clipLabels[i]}]').join();
        final label = 'g$g';
        _filters.add('$ins concat=n=${members.length}:v=1:a=0 [$label]');
        groupLabels.add(label);
      }
    }

    var current = groupLabels.first;
    for (var g = 1; g < groups.length; g++) {
      final joinIndex = groups[g].first - 1;
      final clip = project.clips[joinIndex];
      final overlap = project.overlapAfter(joinIndex);
      final offset = project.clipStart(groups[g].first).seconds;
      final label = 'x$g';
      _filters.add(
        '[$current][${groupLabels[g]}] '
        'xfade=transition=${clip.transitionType.ffmpegName}'
        ':duration=${overlap.seconds.toStringAsFixed(3)}'
        ':offset=${offset.toStringAsFixed(3)} [$label]',
      );
      current = label;
    }

    // Normalise the joined track once more so overlays land on a known format.
    _filters.add('[$current] format=yuv420p,fps=$_fps,setsar=1 [track]');
    return 'track';
  }

  /// The clip's animation as FFmpeg expressions in `t`.
  ///
  /// The shape is the one [VideoClip.animationTransformAt] evaluates for the
  /// preview, written out here rather than re-invented: the departure eases
  /// back over the animation's length — squared for the ones that arrive, a
  /// damped swing for the ones that oscillate. Two spellings of one curve is
  /// how a preview and a render begin to disagree, so both are driven by the
  /// same [AnimOffset].
  static String _awayExpr(LayerAnimation anim, double ad, {String? since}) {
    final t = 'min(1\\,max(0\\,(${since ?? 't'})/$ad))';
    return anim.offset.oscillates ? '(1-$t)*sin($t*PI*4)' : 'pow(1-$t\\,2)';
  }

  /// The offset, scale and rotation the animation adds, as expressions — or
  /// null when the clip has nothing to move.
  (String, String, String, String)? _clipAnimationExprs(
    VideoClip clip,
    Duration dur,
  ) {
    if (!clip.hasTransformAnimation) return null;
    final ad = clip.animationDuration.seconds.clamp(0.05, 10.0);
    final total = dur.seconds;
    final dx = <String>[], dy = <String>[], sc = <String>[], rt = <String>[];

    void add(LayerAnimation anim, {required bool atEnd}) {
      final o = anim.offset;
      if (o.isIdentity) return;
      final away = _awayExpr(
        anim,
        ad,
        since: atEnd ? '(${total.toStringAsFixed(3)}-t)' : null,
      );
      if (o.dx != 0) dx.add('(${o.dx.toStringAsFixed(4)})*($away)');
      if (o.dy != 0) dy.add('(${o.dy.toStringAsFixed(4)})*($away)');
      if (o.scale != 1) {
        sc.add('(1+(${(o.scale - 1).toStringAsFixed(4)})*($away))');
      }
      if (o.turns != 0) {
        rt.add('(${(o.turns * 2 * math.pi).toStringAsFixed(5)})*($away)');
      }
    }

    add(clip.animationIn, atEnd: false);
    add(clip.animationOut, atEnd: true);
    return (
      dx.isEmpty ? '0' : dx.join('+'),
      dy.isEmpty ? '0' : dy.join('+'),
      sc.isEmpty ? '1' : sc.join('*'),
      rt.isEmpty ? '0' : rt.join('+'),
    );
  }

  /// One clip: decode window, speed, geometry, grade, canvas fit.
  String _buildClip(VideoClip clip, int index) {
    final dur = clip.timelineDuration;
    final srcDur = clip.trimmedDuration;

    if (clip.isImage) {
      _inputs.add(
        '-loop 1 -framerate $_fps '
        '-t ${dur.seconds.toStringAsFixed(3)} -i ${_quote(clip.path)}',
      );
    } else {
      _inputs.add(
        '-ss ${clip.trimStart.seconds.toStringAsFixed(3)} '
        '-t ${srcDur.seconds.toStringAsFixed(3)} -i ${_quote(clip.path)}',
      );
    }
    final idx = _inputIndex++;
    _clipInputs[index] = idx;

    final chain = <String>['setpts=PTS-STARTPTS'];
    if (clip.reversed && !clip.isImage) chain.add('reverse');
    if (clip.stabilize && !clip.isImage) {
      // One-pass smoothing; the two-pass vidstab route needs a side file.
      chain.add('deshake=rx=32:ry=32');
    }
    if (!clip.isImage) {
      if (clip.speedCurve != SpeedCurve.none) {
        chain.add(_speedCurveExpression(clip));
      } else if (clip.speed != 1.0) {
        chain.add('setpts=PTS/${clip.speed.toStringAsFixed(4)}');
      }
    }
    if (clip.hasCrop) {
      final cw = (1 - clip.cropLeft - clip.cropRight).clamp(0.05, 1.0);
      final ch = (1 - clip.cropTop - clip.cropBottom).clamp(0.05, 1.0);
      chain.add(
        'crop=iw*${cw.toStringAsFixed(4)}:ih*${ch.toStringAsFixed(4)}'
        ':iw*${clip.cropLeft.toStringAsFixed(4)}:ih*${clip.cropTop.toStringAsFixed(4)}',
      );
    }
    switch (clip.rotation % 360) {
      case 90:
        chain.add('transpose=1');
      case 180:
        chain.add('transpose=1,transpose=1');
      case 270:
        chain.add('transpose=2');
    }
    if (clip.mirrored) chain.add('hflip');
    if (clip.flippedVertical) chain.add('vflip');

    if (clip.hasChroma) {
      chain.add(
        'chromakey=${_hex(clip.chromaKeyColor!)}'
        ':${clip.chromaSimilarity.toStringAsFixed(3)}'
        ':${clip.chromaBlend.toStringAsFixed(3)}',
      );
    }
    chain.addAll(clip.enhanceFilters());
    final grade = clip.gradedFilter.toFFmpegFilter();
    if (grade.isNotEmpty) chain.add(grade);
    chain.addAll(clip.adjustments.toFFmpegExtras());
    // The HSL grade goes on before any LUT the user brought in of their own:
    // theirs is the look, this is the correction underneath it.
    final hslLut = hslLuts[clip.id];
    if (hslLut != null) {
      chain.add('lut3d=file=${_escapePath(hslLut)}');
    }
    if (clip.lutPath != null) {
      chain.add('lut3d=file=${_escapePath(clip.lutPath!)}');
    }
    if (clip.hasMask) {
      chain.add(
        _maskExpression(
          shape: clip.maskShape,
          size: clip.maskSize,
          feather: clip.maskFeather,
          x: clip.maskX,
          y: clip.maskY,
          inverted: clip.maskInverted,
        ),
      );
    }

    // User pan/zoom inside the canvas.
    final zoom = clip.scale;
    final fitted = switch (clip.fit) {
      FitMode.cover => 'scale=$_w:$_h:force_original_aspect_ratio=increase',
      FitMode.stretch => 'scale=$_w:$_h',
      FitMode.contain => 'scale=$_w:$_h:force_original_aspect_ratio=decrease',
    };

    var src = '[$idx:v]';
    var base = 'b$index';

    // Opacity is alpha on the clip, and alpha only means anything once
    // something is composited under it. Setting it here — before the
    // background — is what makes the backdrop show through; the branch that
    // used to name opacity did nothing with it, so the slider moved and the
    // exported file never changed.
    if (clip.opacity < 1) {
      _filters.add(
        '$src format=yuva420p,'
        'colorchannelmixer=aa=${clip.opacity.toStringAsFixed(4)} '
        '[op$index]',
      );
      src = '[op$index]';
    }

    // Cutout: the baked matte carries the subject's shape, and `alphamerge`
    // is what turns it into an alpha channel on the footage. It goes in
    // before the geometry so the background composite below sees a clip that
    // is already transparent behind the subject — the matte is baked at a
    // lower rate and size than the footage, so it is stretched onto the
    // clip's own dimensions first.
    if (clip.hasCutout && !clip.isImage) {
      _inputs.add('-i ${_quote(clip.cutoutMattePath!)}');
      final mIdx = _inputIndex++;
      // `scale2ref` sizes its first input to its second and passes the second
      // through untouched, so this is what puts a 512-wide matte onto the
      // footage's own dimensions without knowing either of them here.
      _filters.add(
        '[$mIdx:v] fps=$_fps,setpts=PTS-STARTPTS,format=gray '
        '[mt$index]',
      );
      _filters.add('[mt$index]$src scale2ref [ms$index][cs$index]');
      _filters.add('[cs$index] format=yuva420p [ca$index]');
      _filters.add('[ca$index][ms$index] alphamerge [cut$index]');
      src = '[cut$index]';
    }
    // The clip's own in and out animation. Only the alpha family is drawn —
    // the same family an overlay's is drawn from — and it goes on the
    // foreground chain, not after the composite: alpha added once the
    // backdrop is already flattened in is alpha the next `format=yuv420p`
    // throws away, which is a fade nobody sees. Two fields, written by no
    // panel, read by no renderer, and faithfully kept in the JSON.
    if (clip.hasAlphaAnimation) {
      final ad = clip.animationDuration.seconds.clamp(0.05, 10.0);
      chain.add('format=yuva420p');
      if (clip.animationIn.exportKind == AnimExport.alpha) {
        chain.add('fade=t=in:st=0:d=${ad.toStringAsFixed(3)}:alpha=1');
      }
      if (clip.animationOut.exportKind == AnimExport.alpha) {
        final st = (dur.seconds - ad).clamp(0.0, double.infinity);
        chain.add(
          'fade=t=out:st=${st.toStringAsFixed(3)}'
          ':d=${ad.toStringAsFixed(3)}:alpha=1',
        );
      }
    }

    // A cut-out clip needs something behind it whatever its fit: the alpha
    // alphamerge gave it only becomes a hole once it is composited, and the
    // `crop` path below would drop the alpha plane and leave the background
    // it was supposed to remove sitting there untouched.
    final needsBackground =
        clip.fit == FitMode.contain ||
        clip.hasCutout ||
        clip.opacity < 1 ||
        clip.hasAnimation;

    final scaleTrack = clip.trackOrNull(KeyframeProperty.scale);
    if (scaleTrack != null) {
      // Keyframed zoom: the scale filter re-evaluates per frame.
      final start = project.clipStart(index).seconds;
      final expr = scaleTrack.toExpression(offset: start);
      chain.add('$fitted,scale=w=\'iw*($expr)\':h=\'ih*($expr)\':eval=frame');
    } else if (zoom != 1.0 || clip.offsetX != 0 || clip.offsetY != 0) {
      final zw = (_w * zoom).round();
      final zh = (_h * zoom).round();
      chain.add(
        '$fitted,scale=${_even(zw)}:${_even(zh)}'
        ':force_original_aspect_ratio=decrease',
      );
    } else {
      chain.add(fitted);
    }

    // The scale and turn halves of the animation act on the picture rather
    // than on where it sits, so they go on the clip's own chain — and they
    // go *after* the fit. Put before it, the fit scales the frame straight
    // back to the canvas and the animation is wiped: the graph runs, FFmpeg
    // is happy, and the picture does not move.
    final motion = _clipAnimationExprs(clip, dur);
    if (motion != null) {
      final (_, _, aScale, aRot) = motion;
      if (aScale != '1') {
        chain.add("scale=w='iw*($aScale)':h='ih*($aScale)':eval=frame");
      }
      if (aRot != '0') {
        chain.add("rotate='$aRot':c=none:ow=iw:oh=ih");
      }
    }

    if (needsBackground) {
      // The largest the fitted frame ever gets. No easing here overshoots its
      // keys, so the highest key is the true peak; the 2% is slack for
      // FFmpeg's own float evaluation of the same curve.
      final peakZoom = scaleTrack != null
          ? scaleTrack.keys.fold<double>(1, (m, k) => math.max(m, k.value)) *
                1.02
          : zoom;
      _buildBackgroundComposite(
        src,
        chain,
        base,
        clip,
        index,
        peakZoom: peakZoom,
      );
    } else {
      chain.add('crop=$_w:$_h');
      _filters.add(
        '$src ${chain.join(',')},setsar=1,fps=$_fps,format=yuv420p [$base]',
      );
    }

    if (clip.fadeIn > Duration.zero || clip.fadeOut > Duration.zero) {
      final fades = <String>[];
      if (clip.fadeIn > Duration.zero) {
        fades.add('fade=t=in:st=0:d=${clip.fadeIn.seconds.toStringAsFixed(3)}');
      }
      if (clip.fadeOut > Duration.zero) {
        final st = (dur - clip.fadeOut).seconds.clamp(0, double.infinity);
        fades.add(
          'fade=t=out:st=${st.toStringAsFixed(3)}'
          ':d=${clip.fadeOut.seconds.toStringAsFixed(3)}',
        );
      }
      if (fades.isNotEmpty) {
        final faded = 'f$index';
        _filters.add('[$base] ${fades.join(',')} [$faded]');
        return faded;
      }
    }
    return base;
  }

  /// Letterbox filler: flat colour, blurred copy of the frame, or a gradient.
  void _buildBackgroundComposite(
    String src,
    List<String> chain,
    String outLabel,
    VideoClip clip,
    int index, {

    /// The largest scale the clip reaches. Above 1 the fitted frame outgrows
    /// the canvas, which changes how it can be composited.
    required double peakZoom,
  }) {
    final bg = project.background;
    final start = project.clipStart(index).seconds;
    final xTrack = clip.trackOrNull(KeyframeProperty.x);
    final yTrack = clip.trackOrNull(KeyframeProperty.y);
    var dx = xTrack != null
        ? '(${xTrack.toExpression(offset: start, scale: _w / 2)})'
        : (clip.offsetX * _w / 2).round().toString();
    var dy = yTrack != null
        ? '(${yTrack.toExpression(offset: start, scale: _h / 2)})'
        : (clip.offsetY * _h / 2).round().toString();
    var animated = xTrack != null || yTrack != null;

    // A slide, drift or fly rides on the same offset the pan already uses,
    // which is what makes it play over whatever framing the user set rather
    // than replacing it. It also forces the composited spelling: `pad` has
    // no `t`, so a position that moves cannot be padded into place.
    final anim = _clipAnimationExprs(clip, clip.timelineDuration);
    if (anim != null) {
      final (ax, ay, _, _) = anim;
      if (ax != '0') {
        dx = '($dx+($ax)*${_w.toString()})';
        animated = true;
      }
      if (ay != '0') {
        dy = '($dy+($ay)*${_h.toString()})';
        animated = true;
      }
    }
    // Centring for the *overlay* filter, whose variables are W/H (the canvas
    // it draws onto) and w/h (the clip). The blur and gradient backgrounds
    // composite, so this is the spelling they need.
    final pos = animated
        ? "'(W-w)/2+$dx':'(H-h)/2+$dy'"
        : '(W-w)/2+$dx:(H-h)/2+$dy';

    switch (bg.type) {
      case BackgroundType.color:
        final color = _hex(bg.color);
        // `pad` fills the letterbox and nothing else — it draws no pixels
        // under the frame, so a transparent subject stays transparent and
        // `format=yuv420p` then throws the alpha away. Compositing is the
        // only branch that puts the backdrop *behind* the clip.
        if (animated ||
            clip.hasCutout ||
            clip.opacity < 1 ||
            clip.hasAnimation) {
          // pad exposes no `t`, not even with eval=frame, so a keyframed
          // position has to be composited. This is the one path that pays for
          // an extra input, so it is kept to the case that needs it.
          _inputs.add(
            '-f lavfi -t ${clip.timelineDuration.seconds.toStringAsFixed(3)} '
            '-i color=c=$color:s=${_w}x$_h:r=$_fps',
          );
          final cIdx = _inputIndex++;
          final fgLabel = 'fg$index';
          _filters.add('$src ${chain.join(',')},setsar=1 [$fgLabel]');
          _filters.add(
            '[$cIdx:v][$fgLabel] overlay=$pos:format=auto,'
            'fps=$_fps,format=yuv420p [$outLabel]',
          );
        } else {
          // pad has its own variable names — ow/oh for the padded output and
          // iw/ih for the input. It has no W/H at all, so the overlay
          // spelling made FFmpeg reject the whole expression with
          // "Undefined constant or missing '(' in 'W-w)/2+0'".
          //
          // pad also refuses an input larger than its output, which a zoom
          // above 1 produces. Padding out to the peak the zoom reaches and
          // cropping the canvas back out of the middle covers both
          // directions — letterbox when the frame is small, crop when it has
          // grown past the canvas — without adding an input.
          final grow = peakZoom > 1;
          final pw = grow ? _even((_w * peakZoom).ceil()) : _w;
          final ph = grow ? _even((_h * peakZoom).ceil()) : _h;
          _filters.add(
            '$src ${chain.join(',')},'
            'pad=$pw:$ph:(ow-iw)/2+$dx:(oh-ih)/2+$dy:color=$color,'
            '${grow ? 'crop=$_w:$_h,' : ''}'
            'setsar=1,fps=$_fps,format=yuv420p [$outLabel]',
          );
        }
      case BackgroundType.blur:
        final fgLabel = 'fg$index';
        final bgLabel = 'bgl$index';
        _filters.add('$src split=2 [bs$index][fs$index]');
        _filters.add(
          '[bs$index] scale=$_w:$_h:force_original_aspect_ratio=increase,'
          'crop=$_w:$_h,boxblur=luma_radius=${bg.blurAmount.round()}:luma_power=2,'
          'eq=brightness=-0.06,setsar=1 [$bgLabel]',
        );
        _filters.add('[fs$index] ${chain.join(',')},setsar=1 [$fgLabel]');
        _filters.add(
          '[$bgLabel][$fgLabel] overlay=$pos:format=auto,'
          'fps=$_fps,format=yuv420p [$outLabel]',
        );
      case BackgroundType.gradient:
        _inputs.add(
          '-f lavfi -t ${clip.timelineDuration.seconds.toStringAsFixed(3)} '
          '-i gradients=s=${_w}x$_h:c0=${_hex(bg.gradientStart)}'
          ':c1=${_hex(bg.gradientEnd)}:x0=0:y0=0:x1=$_w:y1=$_h:r=$_fps',
        );
        final gIdx = _inputIndex++;
        final fgLabel = 'fg$index';
        _filters.add('$src ${chain.join(',')},setsar=1 [$fgLabel]');
        _filters.add(
          '[$gIdx:v][$fgLabel] overlay=$pos:format=auto,'
          'fps=$_fps,format=yuv420p [$outLabel]',
        );
    }
  }

  // ------------------------------------------------------------- overlays

  /// PIP clips, then stickers, then text — same z-order as the preview.
  String _applyVisualOverlays(String base) {
    var current = base;
    var n = 0;

    for (final pip in project.overlays) {
      current = _overlayPip(current, pip, n++);
    }
    for (final s in project.stickers) {
      final r = rasterized[s.id];
      if (r == null) continue;
      current = _overlayImage(
        current,
        r,
        s,
        s.start,
        s.end,
        s.animationIn,
        s.animationOut,
        s.animationDuration,
        n++,
      );
    }
    for (final t in project.texts) {
      final r = rasterized[t.id];
      if (r == null) continue;
      current = _overlayImage(
        current,
        r,
        t,
        t.start,
        t.end,
        t.animationIn,
        t.animationOut,
        t.animationDuration,
        n++,
      );
    }
    // Whole-frame texture then border, both spanning the full timeline — the
    // same order the preview stacks them in.
    final fx = rasterized[_kFxKey];
    if (fx != null) current = _overlayFullSpan(current, fx, n++);
    final frame = rasterized[_kFrameKey];
    if (frame != null) current = _overlayFullSpan(current, frame, n++);
    // The watermark sits above everything and spans the whole timeline, so it
    // is composited last and carries no `enable` window.
    final mark = rasterized[_kWatermarkKey];
    if (mark != null) current = _overlayFullSpan(current, mark, n++);
    if (current == base) {
      _filters.add('[$base] null [outv]');
      return 'outv';
    }
    _filters.add('[$current] null [outv]');
    return 'outv';
  }

  String _overlayImage(
    String base,
    RasterizedLayer r,
    TimelineLayer layer,
    Duration start,
    Duration end,
    LayerAnimation animIn,
    LayerAnimation animOut,
    Duration animDur,
    int n,
  ) {
    _inputs.add('-loop 1 -framerate $_fps -i ${_quote(r.path)}');
    final idx = _inputIndex++;
    final label = 'ov$n';
    final src = 'os$n';
    final owner = layer as Keyframable;
    final offset = start.seconds;

    final chain = <String>['format=rgba'];

    // Keyframed scale re-evaluates per frame; a static layer is already
    // rasterized at its final size.
    final scaleTrack = owner.trackOrNull(KeyframeProperty.scale);
    if (scaleTrack != null) {
      final e = scaleTrack.toExpression(offset: offset);
      chain.add("scale=w='iw*($e)':h='ih*($e)':eval=frame");
    }
    final rotTrack = owner.trackOrNull(KeyframeProperty.rotation);
    if (rotTrack != null) {
      final e = rotTrack.toExpression(offset: offset);
      chain.add("rotate='$e':c=none:ow=rotw('$e'):oh=roth('$e')");
    }
    final opacityTrack = owner.trackOrNull(KeyframeProperty.opacity);
    if (opacityTrack != null) {
      final e = opacityTrack.toExpression(offset: offset);
      chain.add("geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*($e)'");
    }

    final ad = animDur.seconds.clamp(0.05, 10.0);
    if (_usesAlpha(animIn)) {
      chain.add(
        'fade=t=in:st=${offset.toStringAsFixed(3)}'
        ':d=${ad.toStringAsFixed(3)}:alpha=1',
      );
    }
    if (_usesAlpha(animOut)) {
      final st = (end.seconds - ad).clamp(0.0, double.infinity);
      chain.add(
        'fade=t=out:st=${st.toStringAsFixed(3)}'
        ':d=${ad.toStringAsFixed(3)}:alpha=1',
      );
    }
    _filters.add('[$idx:v] ${chain.join(',')} [$src]');

    final (x, y) = _position(
      owner: owner,
      staticX: r.centerX,
      staticY: r.centerY,
      halfW: r.width / 2,
      halfH: r.height / 2,
      start: start,
      end: end,
      animIn: animIn,
      animOut: animOut,
      ad: ad,
    );
    _filters.add(
      '[$base][$src] overlay=$x:$y:format=auto'
      ':enable=\'between(t,${offset.toStringAsFixed(3)}'
      ',${end.seconds.toStringAsFixed(3)})\' [$label]',
    );
    return label;
  }

  /// Static, full-duration overlay: the FX texture, the design frame and the
  /// watermark all take this path. Opacity and rotation are already baked into
  /// the PNG, so this only has to place it.
  String _overlayFullSpan(String base, RasterizedLayer r, int n) {
    // A still is one PNG held for the whole timeline; a moving effect is a
    // strip of PNGs run at its own rate. `-loop 1` is the image demuxer's
    // own option and covers both — it repeats the sequence for as long as
    // the graph asks, and the output's `-t` is what finally ends it. Feeding
    // the strip at the effect's rate rather than the video's is what puts
    // the exported motion on the same frames the preview showed.
    final rate = r.isSequence ? r.frameRate : _fps;
    _inputs.add('-loop 1 -framerate $rate -i ${_quote(r.path)}');
    final idx = _inputIndex++;
    final label = 'wm$n';
    final src = 'ws$n';
    _filters.add('[$idx:v] format=rgba [$src]');
    _filters.add('[$base][$src] overlay=${r.x}:${r.y}:format=auto [$label]');
    return label;
  }

  /// Animations the renderer reproduces with an alpha ramp.
  static bool _usesAlpha(LayerAnimation a) =>
      a != LayerAnimation.none &&
      a.exportKind != AnimExport.move &&
      a.exportKind != AnimExport.none;

  String _overlayPip(String base, OverlayLayer pip, int n) {
    if (pip.isImage) {
      _inputs.add(
        '-loop 1 -framerate $_fps '
        '-t ${pip.duration.seconds.toStringAsFixed(3)} -i ${_quote(pip.path)}',
      );
    } else {
      _inputs.add(
        '-ss ${pip.trimStart.seconds.toStringAsFixed(3)} '
        '-t ${(pip.duration.seconds * pip.speed).toStringAsFixed(3)} '
        '-i ${_quote(pip.path)}',
      );
    }
    final idx = _inputIndex++;
    _pipInputs[project.overlays.indexOf(pip)] = idx;
    final src = 'ps$n';
    final label = 'pv$n';
    final offset = pip.start.seconds;

    final targetW = _even((_w * pip.transform.scale).round());
    final targetH = _even((targetW / pip.sourceAspect).round());

    final chain = <String>['setpts=PTS-STARTPTS'];
    if (pip.speed != 1.0 && !pip.isImage) {
      chain.add('setpts=PTS/${pip.speed.toStringAsFixed(4)}');
    }

    final scaleTrack = pip.trackOrNull(KeyframeProperty.scale);
    if (scaleTrack != null) {
      final e = scaleTrack.toExpression(offset: offset, scale: _w.toDouble());
      chain.add(
        "scale=w='($e)':h='($e)/${pip.sourceAspect.toStringAsFixed(5)}'"
        ":eval=frame",
      );
    } else {
      chain.add('scale=$targetW:$targetH');
    }

    if (pip.chromaKeyColor != null) {
      chain.add(
        'chromakey=${_hex(pip.chromaKeyColor!)}'
        ':${pip.chromaSimilarity.toStringAsFixed(3)}'
        ':${pip.chromaBlend.toStringAsFixed(3)}',
      );
    }
    final grade = pip.gradedFilter.toFFmpegFilter();
    if (grade.isNotEmpty) chain.add(grade);
    chain.addAll(pip.adjustments.toFFmpegExtras());
    chain.add('format=rgba');

    if (pip.maskShape != MaskShape.none) {
      chain.add(
        _maskExpression(
          shape: pip.maskShape,
          size: pip.maskSize,
          feather: pip.maskFeather,
          x: pip.maskX,
          y: pip.maskY,
          inverted: pip.maskInverted,
        ),
      );
    }

    final opacityTrack = pip.trackOrNull(KeyframeProperty.opacity);
    if (opacityTrack != null) {
      final e = opacityTrack.toExpression(offset: offset);
      chain.add("geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*($e)'");
    } else if (pip.transform.opacity < 1) {
      chain.add(
        'colorchannelmixer=aa=${pip.transform.opacity.toStringAsFixed(3)}',
      );
    }

    final rotTrack = pip.trackOrNull(KeyframeProperty.rotation);
    if (rotTrack != null) {
      final e = rotTrack.toExpression(offset: offset);
      chain.add("rotate='$e':c=none:ow=rotw('$e'):oh=roth('$e')");
    } else if (pip.transform.rotation != 0) {
      final a = pip.transform.rotation.toStringAsFixed(4);
      chain.add('rotate=$a:c=none:ow=rotw($a):oh=roth($a)');
    }

    final ad = pip.animationDuration.seconds.clamp(0.05, 10.0);
    if (_usesAlpha(pip.animationIn)) {
      chain.add('fade=t=in:st=0:d=${ad.toStringAsFixed(3)}:alpha=1');
    }
    if (_usesAlpha(pip.animationOut)) {
      final st = (pip.duration.seconds - ad).clamp(0.0, double.infinity);
      chain.add(
        'fade=t=out:st=${st.toStringAsFixed(3)}'
        ':d=${ad.toStringAsFixed(3)}:alpha=1',
      );
    }
    // Shift the layer to its slot on the master timeline.
    chain.add('setpts=PTS+${offset.toStringAsFixed(3)}/TB');
    _filters.add('[$idx:v] ${chain.join(',')} [$src]');

    final (x, y) = _position(
      owner: pip,
      staticX: pip.transform.x * _w,
      staticY: pip.transform.y * _h,
      halfW: targetW / 2,
      halfH: targetH / 2,
      start: pip.start,
      end: pip.end,
      animIn: pip.animationIn,
      animOut: pip.animationOut,
      ad: ad,
    );

    final enable =
        ':enable=\'between(t,${offset.toStringAsFixed(3)}'
        ',${pip.end.seconds.toStringAsFixed(3)})\'';

    if (pip.blendMode == BlendMode2.normal) {
      _filters.add(
        '[$base][$src] overlay=$x:$y:format=auto:eof_action=pass'
        '$enable [$label]',
      );
      return label;
    }

    // A blend mode needs both layers at full canvas size, so the PIP is
    // padded onto a transparent canvas first and then blended.
    final padded = 'pb$n';
    _filters.add('[$src] pad=$_w:$_h:$x:$y:color=0x00000000@0.0 [$padded]');
    _filters.add(
      '[$base][$padded] blend=all_mode=${pip.blendMode.ffmpegName}'
      ':shortest=0$enable [$label]',
    );
    return label;
  }

  /// Overlay position expression.
  ///
  /// Keyframed position wins; otherwise slide animations become a
  /// time-dependent expression and everything else stays put.
  (String, String) _position({
    required Keyframable owner,
    required double staticX,
    required double staticY,
    required double halfW,
    required double halfH,
    required Duration start,
    required Duration end,
    required LayerAnimation animIn,
    required LayerAnimation animOut,
    required double ad,
  }) {
    final offset = start.seconds;
    final xTrack = owner.trackOrNull(KeyframeProperty.x);
    final yTrack = owner.trackOrNull(KeyframeProperty.y);

    if (xTrack != null || yTrack != null) {
      final xe = xTrack != null
          ? xTrack.toExpression(
              offset: offset,
              scale: _w.toDouble(),
              bias: -halfW,
            )
          : (staticX - halfW).toStringAsFixed(2);
      final ye = yTrack != null
          ? yTrack.toExpression(
              offset: offset,
              scale: _h.toDouble(),
              bias: -halfH,
            )
          : (staticY - halfH).toStringAsFixed(2);
      return ("'$xe'", "'$ye'");
    }

    final x = staticX - halfW;
    final y = staticY - halfH;
    final e = end.seconds;
    var xExpr = x.round().toString();
    var yExpr = y.round().toString();

    String slideIn(double base, double from) {
      final p =
          'min(1,max(0,(t-${offset.toStringAsFixed(3)})'
          '/${ad.toStringAsFixed(3)}))';
      return '(${from.round()}+(${base.round()}-${from.round()})*$p)';
    }

    switch (animIn) {
      case LayerAnimation.slideLeft:
      case LayerAnimation.swipeIn:
      case LayerAnimation.flyIn:
        xExpr = slideIn(x, x + _w * 0.6);
      case LayerAnimation.slideRight:
        xExpr = slideIn(x, x - _w * 0.6);
      case LayerAnimation.slideUp:
      case LayerAnimation.driftUp:
        yExpr = slideIn(y, y + _h * 0.4);
      case LayerAnimation.slideDown:
      case LayerAnimation.driftDown:
        yExpr = slideIn(y, y - _h * 0.4);
      default:
        break;
    }

    String slideOut(double base, double to, String current) {
      final st = (e - ad).toStringAsFixed(3);
      final p = 'min(1,max(0,(t-$st)/${ad.toStringAsFixed(3)}))';
      return 'if(lt(t,$st),$current,'
          '(${base.round()}+(${to.round()}-${base.round()})*$p))';
    }

    switch (animOut) {
      case LayerAnimation.slideLeft:
      case LayerAnimation.swipeIn:
      case LayerAnimation.flyIn:
        xExpr = slideOut(x, x - _w * 0.6, xExpr);
      case LayerAnimation.slideRight:
        xExpr = slideOut(x, x + _w * 0.6, xExpr);
      case LayerAnimation.slideUp:
      case LayerAnimation.driftUp:
        yExpr = slideOut(y, y - _h * 0.4, yExpr);
      case LayerAnimation.slideDown:
      case LayerAnimation.driftDown:
        yExpr = slideOut(y, y + _h * 0.4, yExpr);
      default:
        break;
    }

    // Continuous emphasis animations are cheap to express directly.
    if (animIn == LayerAnimation.shake || animOut == LayerAnimation.shake) {
      xExpr = '($xExpr+${(_w * 0.006).toStringAsFixed(2)}*sin(t*34))';
      yExpr = '($yExpr+${(_h * 0.006).toStringAsFixed(2)}*cos(t*41))';
    }
    return ("'$xExpr'", "'$yExpr'");
  }

  // ---------------------------------------------------------------- audio

  /// Every audible source is delayed to its timeline slot and then mixed,
  /// which keeps clip audio and music lanes on one code path.
  String? _buildAudio() {
    final parts = <String>[];

    for (var i = 0; i < project.clips.length; i++) {
      final clip = project.clips[i];
      if (clip.isImage || clip.volume <= 0 || !clip.hasAudio) continue;
      final inputIdx = _clipInputs[i];
      if (inputIdx == null) continue;
      final start = project.clipStart(i);
      final label = 'ca$i';
      final chain = <String>['aresample=48000', 'asetpts=PTS-STARTPTS'];
      if (clip.reversed) chain.add('areverse');
      chain.addAll(_atempoChain(clip.effectiveSpeed));
      chain.addAll(clip.audioFilterChain());
      final volTrack = clip.trackOrNull(KeyframeProperty.volume);
      if (volTrack != null) {
        final e = volTrack.toExpression(
          offset: start.seconds,
          scale: project.masterVolume,
        );
        chain.add("volume=volume='$e':eval=frame");
      } else {
        final vol = clip.volume * project.masterVolume;
        if (vol != 1.0) chain.add('volume=${vol.toStringAsFixed(3)}');
      }
      // The same envelope the picture gets. The fade sliders sit in the
      // Volume panel, so a fade that left the sound at full level was the one
      // thing the control could not be read as meaning.
      if (clip.fadeIn > Duration.zero) {
        chain.add(
          'afade=t=in:st=0:d=${clip.fadeIn.seconds.toStringAsFixed(3)}',
        );
      }
      if (clip.fadeOut > Duration.zero) {
        // After atempo the stream runs at timeline length, so the fade starts
        // that far in rather than at the untimed source's end.
        final st = (clip.timelineDuration - clip.fadeOut).seconds.clamp(
          0,
          double.infinity,
        );
        chain.add(
          'afade=t=out:st=${st.toStringAsFixed(3)}'
          ':d=${clip.fadeOut.seconds.toStringAsFixed(3)}',
        );
      }
      chain.add('adelay=${start.inMilliseconds}|${start.inMilliseconds}');
      chain.add('apad=pad_dur=0.05');
      _filters.add('[$inputIdx:a] ${chain.join(',')} [$label]');
      parts.add(label);
    }

    for (var i = 0; i < project.audios.length; i++) {
      final a = project.audios[i];
      if (a.volume <= 0) continue;
      _inputs.add(
        '-ss ${a.trimStart.seconds.toStringAsFixed(3)} '
        '-t ${(a.duration.seconds * a.speed).toStringAsFixed(3)} '
        '-i ${_quote(a.path)}',
      );
      final idx = _inputIndex++;
      final label = 'la$i';
      final chain = <String>['aresample=48000', 'asetpts=PTS-STARTPTS'];
      chain.addAll(_atempoChain(a.speed));
      chain.addAll(a.audioFilterChain());
      final volTrack = a.trackOrNull(KeyframeProperty.volume);
      if (volTrack != null) {
        // Keyframed level: `volume` re-evaluates per sample frame.
        final e = volTrack.toExpression(
          offset: a.start.seconds,
          scale: project.masterVolume,
        );
        chain.add("volume=volume='$e':eval=frame");
      } else {
        final vol = a.volume * project.masterVolume;
        if (vol != 1.0) chain.add('volume=${vol.toStringAsFixed(3)}');
      }
      if (a.fadeIn > Duration.zero) {
        chain.add('afade=t=in:st=0:d=${a.fadeIn.seconds.toStringAsFixed(3)}');
      }
      if (a.fadeOut > Duration.zero) {
        final st = (a.duration.seconds - a.fadeOut.seconds).clamp(0.0, 1e9);
        chain.add(
          'afade=t=out:st=${st.toStringAsFixed(3)}'
          ':d=${a.fadeOut.seconds.toStringAsFixed(3)}',
        );
      }
      chain.add('adelay=${a.start.inMilliseconds}|${a.start.inMilliseconds}');
      _filters.add('[$idx:a] ${chain.join(',')} [$label]');
      parts.add(label);
    }

    for (var i = 0; i < project.overlays.length; i++) {
      final pip = project.overlays[i];
      if (pip.isImage || pip.volume <= 0 || !pip.hasAudio) continue;
      // The PIP video input was already added by _overlayPip.
      final label = 'pa$i';
      final inputIdx = _pipInputIndex(i);
      if (inputIdx == null) continue;
      final chain = <String>['aresample=48000', 'asetpts=PTS-STARTPTS'];
      chain.addAll(_atempoChain(pip.speed));
      final vol = pip.volume * project.masterVolume;
      if (vol != 1.0) chain.add('volume=${vol.toStringAsFixed(3)}');
      chain.add(
        'adelay=${pip.start.inMilliseconds}|${pip.start.inMilliseconds}',
      );
      _filters.add('[$inputIdx:a] ${chain.join(',')} [$label]');
      parts.add(label);
    }

    if (parts.isEmpty) return null;
    if (parts.length == 1) {
      _filters.add(
        '[${parts.first}] aformat=sample_fmts=fltp:'
        'sample_rates=48000:channel_layouts=stereo [outa]',
      );
      return 'outa';
    }
    final ins = parts.map((p) => '[$p]').join();
    _filters.add(
      '$ins amix=inputs=${parts.length}:duration=longest'
      ':dropout_transition=0:normalize=0,'
      'alimiter=limit=0.97,'
      'aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo [outa]',
    );
    return 'outa';
  }

  /// `atempo` only accepts 0.5..2.0, so extreme speeds are chained.
  List<String> _atempoChain(double speed) {
    if (speed == 1.0) return const [];
    final out = <String>[];
    var remaining = speed;
    while (remaining > 2.0) {
      out.add('atempo=2.0');
      remaining /= 2.0;
    }
    while (remaining < 0.5) {
      out.add('atempo=0.5');
      remaining /= 0.5;
    }
    out.add('atempo=${remaining.toStringAsFixed(4)}');
    return out;
  }

  int? _pipInputIndex(int overlayIndex) => _pipInputs[overlayIndex];

  // ------------------------------------------------------------- helpers

  /// Variable-rate `setpts` for a speed ramp.
  ///
  /// The curve gives a speed at each point of the clip; the presentation
  /// timestamp is the integral of 1/speed, so the ramp is turned into a
  /// piecewise-linear PTS map over the source timeline.
  static String _speedCurveExpression(VideoClip clip) {
    final curve = clip.speedCurve;
    final srcSeconds = clip.trimmedDuration.seconds;
    if (srcSeconds <= 0 || curve.points.length < 2) return 'setpts=PTS';

    // Walk the curve accumulating output time for each input segment.
    final inputs = <double>[];
    final outputs = <double>[];
    var outAcc = 0.0;
    for (var i = 0; i < curve.points.length; i++) {
      final (p, _) = curve.points[i];
      inputs.add(p * srcSeconds);
      outputs.add(outAcc);
      if (i == curve.points.length - 1) break;
      final (p1, s1) = curve.points[i + 1];
      final (p0, s0) = curve.points[i];
      final width = (p1 - p0) * srcSeconds;
      final meanSpeed = ((s0 + s1) / 2) * clip.speed;
      outAcc += width / (meanSpeed <= 0 ? 1 : meanSpeed);
    }

    // Nested if() mapping source PTS to output PTS.
    var expr = outputs.last.toStringAsFixed(5);
    for (var i = inputs.length - 2; i >= 0; i--) {
      final t0 = inputs[i], t1 = inputs[i + 1];
      final o0 = outputs[i], o1 = outputs[i + 1];
      final span = math.max(t1 - t0, 0.0001);
      final seg =
          '($o0+(${(o1 - o0).toStringAsFixed(5)})'
          '*(T-${t0.toStringAsFixed(5)})/${span.toStringAsFixed(5)})';
      expr = 'if(lt(T,${t1.toStringAsFixed(5)}),$seg,$expr)';
    }
    return "setpts='($expr)/TB'";
  }

  /// Alpha mask as a `geq` expression over the frame's normalised coordinates.
  static String _maskExpression({
    required MaskShape shape,
    required double size,
    required double feather,
    required double x,
    required double y,
    required bool inverted,
  }) {
    final f = feather.clamp(0.005, 0.9);
    final s = size.clamp(0.02, 1.5);
    // Normalised distance term per shape, 0 at the centre of the kept area.
    final distance = switch (shape) {
      MaskShape.circle => 'hypot((X/W-$x)*1.0,(Y/H-$y)*1.0)/$s',
      MaskShape.rectangle =>
        'max(abs(X/W-$x)/${(s * 0.6).toStringAsFixed(4)},'
            'abs(Y/H-$y)/${(s * 0.4).toStringAsFixed(4)})',
      MaskShape.linear => '(Y/H-$y)/$s+0.5',
      MaskShape.mirror => 'abs(Y/H-$y)/$s',
      // Heart and star have no cheap closed form; a circle keeps the export
      // honest rather than silently dropping the mask.
      _ => 'hypot((X/W-$x),(Y/H-$y))/$s',
    };
    final inside = '(1-clip(($distance-(1-$f))/$f,0,1))';
    final alpha = inverted ? '(1-$inside)' : inside;
    return "format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*$alpha*255/255'";
  }

  static String _escapePath(String p) =>
      p.replaceAll('\\', '/').replaceAll(':', '\\:').replaceAll("'", "\\'");

  static String _quote(String p) => '"${p.replaceAll('"', r'\"')}"';

  static String _hex(int argb) {
    final rgb = argb & 0xFFFFFF;
    final alpha = (argb >> 24) & 0xFF;
    final base = '0x${rgb.toRadixString(16).padLeft(6, '0')}';
    return alpha == 0xFF
        ? base
        : '$base${alpha.toRadixString(16).padLeft(2, '0')}';
  }

  static int _even(int v) => v.isEven ? math.max(v, 2) : math.max(v + 1, 2);
}
