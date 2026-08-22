import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/duration_ext.dart';
import '../models/video_clip.dart';
import '../repositories/project_repository.dart';

/// Separates the person in a clip from everything behind them.
///
/// The segmenter is an on-device model: it hands back a confidence per pixel,
/// not a picture, so this turns each frame's confidences into a grey matte and
/// bakes the run of them into a video. The exporter then pairs that matte with
/// the original through FFmpeg's `alphamerge`, which is what actually knocks
/// the background out — there is no way to run a model inside a filter graph,
/// and no way to keep alpha in an H.264 file, so the matte travels beside the
/// footage instead of inside it.
class CutoutService {
  CutoutService._();

  /// Frames a second in the baked matte.
  ///
  /// Below the footage's own rate on purpose: segmentation is the expensive
  /// step, a matte is a soft-edged shape rather than detail, and `alphamerge`
  /// is fed through `fps` at export anyway, so the in-between frames cost real
  /// seconds and buy nothing the eye can find.
  static const int _fps = 15;

  /// Long edge the segmenter sees. The model's own input is smaller than this,
  /// so a bigger frame is decode cost with no more mask in it.
  static const int _side = 512;

  /// The share of a frame the subject has to fill before that frame counts as
  /// holding one. Below this the model is picking out specks, not a person.
  static const double _minCoverage = 0.01;

  /// How many of the clip's frames have to hold a subject before the matte is
  /// worth keeping.
  static const double _minSubjectShare = 0.2;

  /// Build the matte for [clip]'s trimmed region and return its path.
  ///
  /// [onProgress] is called with 0..1 as the frames are worked through, and
  /// null comes back when the clip holds no person the model is sure of — the
  /// caller says so rather than handing back a clip gone entirely transparent.
  static Future<String?> bakeMatte(
    VideoClip clip, {
    void Function(double)? onProgress,
  }) async {
    if (clip.isImage) return null;
    Directory? work;
    SelfieSegmenter? segmenter;
    try {
      work = await _workDir();
      final framesDir = Directory('${work.path}/f')
        ..createSync(recursive: true);
      final masksDir = Directory('${work.path}/m')..createSync(recursive: true);

      final grabbed = await _run(
        '-hide_banner -y '
        '-ss ${clip.trimStart.seconds.toStringAsFixed(3)} '
        '-t ${clip.trimmedDuration.seconds.toStringAsFixed(3)} '
        '-i ${_q(clip.path)} '
        // A fit-box rather than a conditional: FFmpeg splits a filter
        // string on commas, and the commas inside an `if(gt(iw,ih),…)`
        // expression made it read the tail as a filter of its own.
        '-vf fps=$_fps,scale=$_side:$_side:force_original_aspect_ratio=decrease '
        '-q:v 4 ${_q('${framesDir.path}/%05d.jpg')}',
      );
      if (!grabbed) return null;

      final frames =
          framesDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.jpg'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      if (frames.isEmpty) return null;

      segmenter = SelfieSegmenter(mode: SegmenterMode.stream);
      var withSubject = 0;
      for (var i = 0; i < frames.length; i++) {
        final mask = await segmenter.processImage(
          InputImage.fromFilePath(frames[i].path),
        );
        final matte = await _matteFrame(mask);
        if (matte != null && matte.coverage >= _minCoverage) withSubject++;
        // Every frame gets a file even when the model found nobody: a gap in
        // the numbering ends FFmpeg's `%05d` sequence early, and the rest of
        // the clip would silently vanish. A black frame is the honest matte
        // for a frame with no subject in it.
        await File(
          '${masksDir.path}/${(i + 1).toString().padLeft(5, '0')}.png',
        ).writeAsBytes(matte?.png ?? await _blankFrame(), flush: true);
        onProgress?.call((i + 1) / frames.length);
      }
      // A matte that is black nearly everywhere is not a cutout — it is a
      // clip the model found nobody in, and merging it would leave the user
      // with a few seconds of nothing.
      if (withSubject < frames.length * _minSubjectShare) return null;

      final dir = await ProjectRepository.instance.mediaDir();
      final out =
          '${dir.path}/matte_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final encoded = await _run(
        '-hide_banner -y -framerate $_fps '
        '-i ${_q('${masksDir.path}/%05d.png')} '
        '-vf format=gray,format=yuv420p '
        '-c:v libx264 -preset veryfast -crf 18 ${_q(out)}',
      );
      return encoded ? out : null;
    } catch (e) {
      debugPrint('cutout threw: $e');
      return null;
    } finally {
      await segmenter?.close();
      // The frames and masks are worth tens of megabytes; the matte is the
      // only thing the project keeps.
      try {
        await work?.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// One frame's confidences as a grey PNG: white where the subject is.
  static Future<_Matte?> _matteFrame(SegmentationMask? mask) async {
    if (mask == null) return null;
    final w = mask.width, h = mask.height;
    if (w <= 0 || h <= 0) return null;
    final conf = mask.confidences;
    if (conf.length < w * h) return null;

    final rgba = Uint8List(w * h * 4);
    var solid = 0;
    for (var i = 0; i < w * h; i++) {
      final c = conf[i].clamp(0.0, 1.0);
      if (c > 0.5) solid++;
      final v = (c * 255).round();
      final o = i * 4;
      rgba[o] = v;
      rgba[o + 1] = v;
      rgba[o + 2] = v;
      rgba[o + 3] = 255;
    }
    final image = await _imageFromPixels(rgba, w, h);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return null;
      return _Matte(bytes.buffer.asUint8List(), solid / (w * h));
    } finally {
      image.dispose();
    }
  }

  /// A 2x2 black PNG, cached: the matte for a frame with nobody in it. FFmpeg
  /// scales it up with the rest of the sequence.
  static Uint8List? _blank;

  static Future<Uint8List> _blankFrame() async {
    if (_blank != null) return _blank!;
    final rgba = Uint8List(2 * 2 * 4);
    for (var i = 0; i < 4; i++) {
      rgba[i * 4 + 3] = 255;
    }
    final image = await _imageFromPixels(rgba, 2, 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return _blank = bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  static Future<ui.Image> _imageFromPixels(Uint8List rgba, int w, int h) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  static Future<Directory> _workDir() async {
    final base = await getTemporaryDirectory();
    final d = Directory(
      '${base.path}/sve_cutout_${DateTime.now().millisecondsSinceEpoch}',
    );
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<bool> _run(String command) async {
    try {
      final session = await FFmpegKit.execute(command);
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) {
        debugPrint(
          'cutout ffmpeg failed: ${await session.getAllLogsAsString()}',
        );
      }
      return ReturnCode.isSuccess(rc);
    } catch (e) {
      debugPrint('cutout ffmpeg threw: $e');
      return false;
    }
  }

  static String _q(String p) => '"${p.replaceAll('"', r'\"')}"';
}

/// One frame's matte and how much of it the subject fills.
class _Matte {
  const _Matte(this.png, this.coverage);

  final Uint8List png;
  final double coverage;
}
