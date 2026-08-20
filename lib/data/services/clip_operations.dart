import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/duration_ext.dart';
import '../models/video_clip.dart';
import '../repositories/project_repository.dart';

/// One-off media operations that must be baked into a real file because they
/// cannot be expressed as a preview-time transform.
class ClipOperations {
  ClipOperations._();

  /// Grab a single frame as a PNG, used by the freeze-frame tool.
  static Future<String?> freezeFrame(VideoClip clip, Duration atSource) async {
    final dir = await ProjectRepository.instance.mediaDir();
    final out = '${dir.path}/freeze_${DateTime.now().millisecondsSinceEpoch}.png';
    final ok = await _run('-hide_banner -y -ss ${atSource.seconds.toStringAsFixed(3)} '
        '-i ${_q(clip.path)} -frames:v 1 ${_q(out)}');
    return ok ? out : null;
  }

  /// Extract the clip's audio into an AAC file so it can live on its own lane.
  static Future<String?> extractAudio(VideoClip clip) async {
    final dir = await ProjectRepository.instance.mediaDir();
    final out = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final ok = await _run('-hide_banner -y '
        '-ss ${clip.trimStart.seconds.toStringAsFixed(3)} '
        '-t ${clip.trimmedDuration.seconds.toStringAsFixed(3)} '
        '-i ${_q(clip.path)} -vn -c:a aac -b:a 192k ${_q(out)}');
    return ok ? out : null;
  }

  /// Physically reverse the trimmed region.
  ///
  /// FFmpeg's `reverse` filter buffers the whole segment in memory, so this is
  /// rendered once to a file instead of being re-applied on every preview
  /// frame — and the caller keeps the result as a normal clip.
  static Future<String?> reverse(VideoClip clip) async {
    final dir = await ProjectRepository.instance.mediaDir();
    final out = '${dir.path}/rev_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final audio = clip.hasAudio ? '-af areverse -c:a aac -b:a 192k' : '-an';
    final ok = await _run('-hide_banner -y '
        '-ss ${clip.trimStart.seconds.toStringAsFixed(3)} '
        '-t ${clip.trimmedDuration.seconds.toStringAsFixed(3)} '
        '-i ${_q(clip.path)} -vf reverse $audio '
        '-c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p ${_q(out)}');
    return ok ? out : null;
  }

  /// Rough amplitude envelope for the audio lane waveform.
  static Future<List<double>> waveform(String path, {int buckets = 200}) async {
    final dir = await ProjectRepository.instance.exportDir();
    final raw = '${dir.path}/wave_${DateTime.now().millisecondsSinceEpoch}.pcm';
    final ok = await _run('-hide_banner -y -i ${_q(path)} '
        '-ac 1 -ar 4000 -f s16le -acodec pcm_s16le ${_q(raw)}');
    if (!ok) return const [];
    try {
      final bytes = await File(raw).readAsBytes();
      final samples = bytes.buffer.asInt16List();
      if (samples.isEmpty) return const [];
      final step = (samples.length / buckets).ceil();
      final out = <double>[];
      for (var i = 0; i < samples.length; i += step) {
        var peak = 0;
        for (var k = i; k < i + step && k < samples.length; k++) {
          final v = samples[k].abs();
          if (v > peak) peak = v;
        }
        out.add((peak / 32768).clamp(0.0, 1.0));
      }
      return out;
    } catch (e) {
      debugPrint('waveform failed: $e');
      return const [];
    } finally {
      unawaitedDelete(raw);
    }
  }

  /// Detect beats by finding energy onsets in the decoded envelope.
  ///
  /// Deliberately simple: a rising edge that clears a rolling local mean by a
  /// margin, with a refractory window so one hit is not counted twice. Good
  /// enough to snap cuts to music, and it costs one decode.
  static Future<List<Duration>> detectBeats(String path) async {
    final dir = await ProjectRepository.instance.exportDir();
    final raw = '${dir.path}/beat_${DateTime.now().millisecondsSinceEpoch}.pcm';
    const rate = 8000;
    final ok = await _run('-hide_banner -y -i ${_q(path)} '
        '-ac 1 -ar $rate -f s16le -acodec pcm_s16le ${_q(raw)}');
    if (!ok) return const [];
    try {
      final bytes = await File(raw).readAsBytes();
      final samples = bytes.buffer.asInt16List();
      if (samples.length < rate) return const [];

      // 10 ms energy frames.
      const frame = rate ~/ 100;
      final energy = <double>[];
      for (var i = 0; i + frame <= samples.length; i += frame) {
        var sum = 0.0;
        for (var k = i; k < i + frame; k++) {
          final v = samples[k] / 32768.0;
          sum += v * v;
        }
        energy.add(sum / frame);
      }

      const window = 43; // ~430 ms of history
      const refractory = 18; // ~180 ms between beats
      final beats = <Duration>[];
      var lastBeat = -refractory;
      for (var i = window; i < energy.length; i++) {
        var mean = 0.0;
        for (var k = i - window; k < i; k++) {
          mean += energy[k];
        }
        mean /= window;
        final isOnset = energy[i] > mean * 1.6 && energy[i] > 0.0015;
        if (isOnset && i - lastBeat >= refractory) {
          beats.add(Duration(milliseconds: i * 10));
          lastBeat = i;
        }
      }
      return beats;
    } catch (e) {
      debugPrint('beat detection failed: $e');
      return const [];
    } finally {
      unawaitedDelete(raw);
    }
  }

  /// Render a looping GIF of the timeline range, using a generated palette so
  /// the colours do not band.
  static Future<String?> exportGif(
    String sourcePath, {
    Duration start = Duration.zero,
    Duration? duration,
    int width = 480,
    int fps = 12,
  }) async {
    final dir = await ProjectRepository.instance.exportDir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final palette = '${dir.path}/palette_$stamp.png';
    final out = '${dir.path}/clip_$stamp.gif';
    final range = duration == null
        ? ''
        : '-t ${duration.seconds.toStringAsFixed(3)} ';
    final filters = 'fps=$fps,scale=$width:-1:flags=lanczos';

    final madePalette = await _run('-hide_banner -y '
        '-ss ${start.seconds.toStringAsFixed(3)} $range-i ${_q(sourcePath)} '
        '-vf "$filters,palettegen=stats_mode=diff" ${_q(palette)}');
    if (!madePalette) return null;

    final ok = await _run('-hide_banner -y '
        '-ss ${start.seconds.toStringAsFixed(3)} $range-i ${_q(sourcePath)} '
        '-i ${_q(palette)} '
        '-lavfi "$filters[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" '
        '-loop 0 ${_q(out)}');
    unawaitedDelete(palette);
    return ok ? out : null;
  }

  static void unawaitedDelete(String path) {
    File(path).delete().catchError((_) => File(path));
  }

  /// Run an arbitrary FFmpeg command. Exposed so sibling services can reuse
  /// the same logging and failure handling instead of each rolling their own.
  static Future<bool> runRaw(String command) => _run(command);

  static Future<bool> _run(String command) async {
    try {
      final session = await FFmpegKit.execute(command);
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) {
        debugPrint('ffmpeg op failed: ${await session.getAllLogsAsString()}');
      }
      return ReturnCode.isSuccess(rc);
    } catch (e) {
      debugPrint('ffmpeg op threw: $e');
      return false;
    }
  }

  static String _q(String p) => '"${p.replaceAll('"', r'\"')}"';
}
