import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/video_clip.dart';

/// Treated copies of a clip's own audio, so Voice Enhance and the voice
/// changer can be heard in the preview.
///
/// The clip's sound comes out of the video decoder, which has no compressor,
/// no de-noiser and no pitch shifter — the render did all of that in FFmpeg,
/// which is why both tools used to be silent on screen and only turn up in
/// the exported file. This runs the same [VideoClip.audioFilterChain] over
/// the source once and leaves a wav beside the cache; the preview mutes the
/// decoder and plays that instead.
///
/// The chain preserves duration — `atempo` undoes what `asetrate` did to the
/// clock, and nothing else moves it — so a position in the copy is the same
/// position in the source, and the existing sync needs no offset of its own.
class VoicePreview {
  VoicePreview._();

  /// Finished bakes, by [_key]. Keyed by the treatment as well as the file,
  /// so changing the effect makes a new one rather than reusing the old
  /// sound.
  static final Map<String, String> _done = {};

  /// Bakes in flight, so a sync pass running every 60ms starts one bake and
  /// not sixty.
  static final Set<String> _running = {};

  static String _key(VideoClip clip) =>
      '${clip.path}|${clip.audioFilterChain().join(',')}';

  /// The treated file for [clip] if one has already been made.
  ///
  /// Deliberately synchronous: the sync pass has to decide what to do with
  /// this frame's audio now, and the answer before a bake lands is "play the
  /// clip as it is".
  static String? ready(VideoClip clip) =>
      clip.hasVoiceWork ? _done[_key(clip)] : null;

  /// Makes the treated copy if it is wanted and not already there.
  static Future<String?> ensure(VideoClip clip) async {
    if (!clip.hasVoiceWork || clip.isImage) return null;
    final key = _key(clip);
    final done = _done[key];
    if (done != null) return done;
    if (_running.contains(key)) return null;
    _running.add(key);
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/voice');
      if (!await dir.exists()) await dir.create(recursive: true);
      final out = '${dir.path}/${key.hashCode.hex}.wav';
      // Uncompressed, because this is played back seconds after it is written
      // and a seek into it has to be immediate.
      final ok = await _run(
        '-hide_banner -y -i ${_q(clip.path)} -vn '
        '-af ${_q(clip.audioFilterChain().join(','))} '
        '-ar 48000 -ac 2 -c:a pcm_s16le ${_q(out)}',
      );
      if (!ok) return null;
      return _done[key] = out;
    } catch (e) {
      debugPrint('voice preview threw: $e');
      return null;
    } finally {
      _running.remove(key);
    }
  }

  static Future<bool> _run(String command) async {
    final session = await FFmpegKit.execute(command);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      debugPrint('voice preview failed: ${await session.getAllLogsAsString()}');
    }
    return ReturnCode.isSuccess(rc);
  }

  static String _q(String s) => "'${s.replaceAll("'", r"'\''")}'";

  @visibleForTesting
  static void reset() {
    _done.clear();
    _running.clear();
  }
}

extension on int {
  /// Hash codes can be negative, and a minus sign at the front of a file name
  /// is a flag to the next thing that reads it.
  String get hex => toUnsigned(32).toRadixString(16);
}
