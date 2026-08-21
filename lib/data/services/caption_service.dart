import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
// Aliased because the package's top-level `downloadModel` would otherwise be
// shadowed by this class's own method of the same name.
import 'package:whisper_flutter_new/download_model.dart' as whisper_dl;
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

import '../models/layers.dart';
import '../repositories/project_repository.dart';
import 'clip_operations.dart';

/// One transcribed line.
class CaptionLine {
  const CaptionLine({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;

  Duration get duration => end - start;
}

/// Progress of a transcription run.
class CaptionProgress {
  const CaptionProgress({required this.stage, required this.value});

  final String stage;

  /// 0..1, or -1 when indeterminate.
  final double value;
}

/// Model sizes the user can pick between. Bigger is slower but far better on
/// accents and noise.
enum CaptionModel {
  tiny('Tiny', '~75 MB', WhisperModel.tiny),
  base('Base', '~142 MB', WhisperModel.base),
  small('Small', '~466 MB', WhisperModel.small);

  const CaptionModel(this.label, this.size, this.model);

  final String label;
  final String size;
  final WhisperModel model;

  /// File name whisper.cpp expects inside the model directory.
  String get fileName => 'ggml-${model.modelName}.bin';
}

/// Auto-captions, SRT interchange, and turning lines into text layers.
///
/// Recognition runs fully on device with whisper.cpp. The model is *not*
/// bundled — it is downloaded once on first use, which is why every entry
/// point here reports whether the model is present before starting.
class CaptionService {
  CaptionService._();

  static final CaptionService instance = CaptionService._();

  bool _busy = false;

  bool get isBusy => _busy;

  /// Where the weights live. Pinned explicitly rather than left to the
  /// plugin's default so the readiness check and the download agree.
  Future<String> _modelDir() async {
    final base = Platform.isAndroid
        ? await getApplicationSupportDirectory()
        : await getLibraryDirectory();
    final dir = Directory('${base.path}/whisper');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  /// True when the weights are already on disk, so the caller can warn about
  /// a download before starting one on mobile data.
  Future<bool> isModelReady(CaptionModel model) async {
    try {
      final f = File('${await _modelDir()}/${model.fileName}');
      return await f.exists() && await f.length() > 1024 * 1024;
    } catch (e) {
      debugPrint('model check failed: $e');
      return false;
    }
  }

  Future<bool> downloadModel(CaptionModel model) async {
    try {
      await whisper_dl.downloadModel(
        model: model.model,
        destinationPath: await _modelDir(),
      );
      return await isModelReady(model);
    } catch (e) {
      debugPrint('model download failed: $e');
      return false;
    }
  }

  /// Transcribe the audio of [sourcePath].
  ///
  /// Whisper wants 16 kHz mono PCM, so the media is converted first rather
  /// than handed over as-is — passing a video container straight in is the
  /// most common reason this silently returns nothing.
  Future<List<CaptionLine>> transcribe(
    String sourcePath, {
    CaptionModel model = CaptionModel.base,
    String language = 'en',
    void Function(CaptionProgress)? onProgress,
  }) async {
    if (_busy) return const [];
    _busy = true;
    String? wav;
    try {
      onProgress?.call(
          const CaptionProgress(stage: 'Extracting audio', value: -1));
      wav = await _toWhisperWav(sourcePath);
      if (wav == null) {
        debugPrint('caption: could not extract audio');
        return const [];
      }

      // whisper.cpp reports no progress callback, so this stage stays
      // indeterminate rather than faking a percentage.
      onProgress?.call(
          const CaptionProgress(stage: 'Transcribing', value: -1));
      final whisper = Whisper(
        model: model.model,
        modelDir: await _modelDir(),
      );
      final result = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: wav,
          language: language,
          isNoTimestamps: false,
          splitOnWord: false,
          isTranslate: false,
        ),
      );

      final segments = result.segments;
      if (segments == null || segments.isEmpty) {
        final whole = result.text.trim();
        if (whole.isEmpty) return const [];
        // No timings came back; better one long caption than nothing.
        return [
          CaptionLine(
              start: Duration.zero,
              end: const Duration(seconds: 5),
              text: whole)
        ];
      }

      return segments
          .map((s) => CaptionLine(
                start: s.fromTs,
                end: s.toTs,
                text: s.text.trim(),
              ))
          .where((l) => l.text.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('transcription failed: $e');
      return const [];
    } finally {
      _busy = false;
      if (wav != null) ClipOperations.unawaitedDelete(wav);
    }
  }

  Future<String?> _toWhisperWav(String sourcePath) async {
    final dir = await ProjectRepository.instance.exportDir();
    final out =
        '${dir.path}/asr_${DateTime.now().millisecondsSinceEpoch}.wav';
    final ok = await ClipOperations.runRaw(
        '-hide_banner -y -i "$sourcePath" -vn -ac 1 -ar 16000 '
        '-c:a pcm_s16le "$out"');
    if (!ok) return null;
    final f = File(out);
    if (!await f.exists() || await f.length() < 1024) return null;
    return out;
  }

  // ------------------------------------------------------------------ SRT

  /// Parse SubRip. Malformed blocks are skipped rather than failing the file,
  /// because hand-edited SRT usually has at least one bad block.
  static List<CaptionLine> parseSrt(String raw) {
    final out = <CaptionLine>[];
    final blocks = raw.replaceAll('\r\n', '\n').split(RegExp(r'\n{2,}'));
    final timeLine = RegExp(
        r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*'
        r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})');

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 2) continue;
      final match = timeLine.firstMatch(block);
      if (match == null) continue;

      Duration at(int base) => Duration(
            hours: int.parse(match.group(base)!),
            minutes: int.parse(match.group(base + 1)!),
            seconds: int.parse(match.group(base + 2)!),
            milliseconds: int.parse(match.group(base + 3)!.padRight(3, '0')),
          );

      final textStart = lines.indexWhere((l) => timeLine.hasMatch(l)) + 1;
      if (textStart <= 0 || textStart >= lines.length) continue;
      final text = lines.sublist(textStart).join('\n').trim();
      if (text.isEmpty) continue;
      out.add(CaptionLine(start: at(1), end: at(5), text: text));
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  static String toSrt(List<CaptionLine> lines) {
    String stamp(Duration d) {
      final h = d.inHours.toString().padLeft(2, '0');
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      final ms = d.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
      return '$h:$m:$s,$ms';
    }

    final b = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      b
        ..writeln(i + 1)
        ..writeln('${stamp(lines[i].start)} --> ${stamp(lines[i].end)}')
        ..writeln(lines[i].text)
        ..writeln();
    }
    return b.toString();
  }

  static Future<String?> writeSrt(
      List<CaptionLine> lines, String projectName) async {
    try {
      final dir = await ProjectRepository.instance.exportDir();
      final safe = projectName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final file = File('${dir.path}/$safe.srt');
      await file.writeAsString(toSrt(lines));
      return file.path;
    } catch (e) {
      debugPrint('srt write failed: $e');
      return null;
    }
  }

  /// Split long lines so a caption never overflows the canvas.
  static List<CaptionLine> wrap(List<CaptionLine> lines,
      {int maxChars = 42}) {
    final out = <CaptionLine>[];
    for (final line in lines) {
      if (line.text.length <= maxChars) {
        out.add(line);
        continue;
      }
      final words = line.text.split(RegExp(r'\s+'));
      final chunks = <String>[];
      var current = StringBuffer();
      for (final w in words) {
        if (current.isEmpty) {
          current.write(w);
        } else if (current.length + 1 + w.length <= maxChars) {
          current.write(' $w');
        } else {
          chunks.add(current.toString());
          current = StringBuffer(w);
        }
      }
      if (current.isNotEmpty) chunks.add(current.toString());

      // Share the original window out by character count so timing stays put.
      final totalChars = chunks.fold<int>(0, (s, c) => s + c.length);
      var cursor = line.start;
      for (final chunk in chunks) {
        final share = totalChars == 0
            ? line.duration
            : Duration(
                microseconds: (line.duration.inMicroseconds *
                        chunk.length /
                        totalChars)
                    .round());
        out.add(CaptionLine(
            start: cursor, end: cursor + share, text: chunk));
        cursor += share;
      }
    }
    return out;
  }

  /// Turn lines into styled text layers pinned to the bottom of the canvas.
  static List<TextLayer> toLayers(
    List<CaptionLine> lines, {
    double y = 0.84,
    double fontSize = 46,
  }) {
    return lines
        .map((l) => TextLayer(
              start: l.start,
              duration: l.duration < const Duration(milliseconds: 250)
                  ? const Duration(milliseconds: 600)
                  : l.duration,
              text: l.text,
              fontSize: fontSize,
              backgroundColor: 0xB3000000,
              backgroundPadding: 18,
              backgroundRadius: 8,
              isCaption: true,
              transform: LayerTransform(x: 0.5, y: y),
            ))
        .toList();
  }
}
