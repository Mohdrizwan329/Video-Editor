import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../repositories/project_repository.dart';

/// A voice offered by the platform's speech engine.
class TtsVoice {
  const TtsVoice({required this.name, required this.locale});

  final String name;
  final String locale;

  Map<String, String> toMap() => {'name': name, 'locale': locale};

  String get shortLabel {
    // Engine voice names are long and machine-ish; show the useful part.
    final cleaned = name.replaceAll('_', ' ').replaceAll('-', ' ');
    final parts = cleaned.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return cleaned;
    return parts.sublist(parts.length - 2).join(' ');
  }
}

/// Text-to-speech that writes a real audio file so the result can go on the
/// timeline like any other clip.
///
/// This uses the platform's own engine (Android TextToSpeech,
/// iOS AVSpeechSynthesizer) rather than shipping voices, so what is available
/// depends on the device — hence [voices] is queried rather than assumed.
class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _configured = false;

  Future<void> _configure() async {
    if (_configured) return;
    // Android needs this or synthesizeToFile returns before the file exists.
    await _tts.awaitSynthCompletion(true);
    _configured = true;
  }

  Future<List<String>> languages() async {
    try {
      final raw = await _tts.getLanguages;
      if (raw is List) {
        return raw.map((e) => e.toString()).toList()..sort();
      }
    } catch (e) {
      debugPrint('tts languages failed: $e');
    }
    return const [];
  }

  Future<List<TtsVoice>> voices({String? languagePrefix}) async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final out = <TtsVoice>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final name = entry['name']?.toString();
        final locale = entry['locale']?.toString();
        if (name == null || locale == null) continue;
        if (languagePrefix != null && !locale.startsWith(languagePrefix)) {
          continue;
        }
        out.add(TtsVoice(name: name, locale: locale));
      }
      out.sort((a, b) => a.locale.compareTo(b.locale));
      return out;
    } catch (e) {
      debugPrint('tts voices failed: $e');
      return const [];
    }
  }

  /// Speak [text] into a file and return its path.
  ///
  /// Returns null when the engine reports success but produces nothing, which
  /// some Android engines do for unsupported voices — the caller must treat
  /// that as a failure rather than adding an empty clip.
  Future<String?> synthesize(
    String text, {
    TtsVoice? voice,
    String? language,
    double rate = 0.5,
    double pitch = 1.0,
    double volume = 1.0,
  }) async {
    if (text.trim().isEmpty) return null;
    await _configure();
    try {
      if (language != null) await _tts.setLanguage(language);
      if (voice != null) await _tts.setVoice(voice.toMap());
      await _tts.setSpeechRate(rate.clamp(0.1, 1.0));
      await _tts.setPitch(pitch.clamp(0.5, 2.0));
      await _tts.setVolume(volume.clamp(0.0, 1.0));

      final dir = await ProjectRepository.instance.mediaDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      // Android writes into its own media dir when given a bare file name, so
      // ask for both and take whichever landed.
      final fileName = 'tts_$stamp.wav';
      final absolute = '${dir.path}/$fileName';

      await _tts.synthesizeToFile(text, Platform.isIOS ? fileName : absolute);

      for (final candidate in [absolute, '${dir.path}/$fileName']) {
        final f = File(candidate);
        if (await f.exists() && await f.length() > 1024) return candidate;
      }

      // iOS writes to the documents directory under the bare name.
      final docs = await ProjectRepository.instance.mediaDir();
      final fallback = File('${docs.parent.path}/$fileName');
      if (await fallback.exists() && await fallback.length() > 1024) {
        final moved = await fallback.rename(absolute);
        return moved.path;
      }
      debugPrint('tts produced no usable file for "$text"');
      return null;
    } catch (e) {
      debugPrint('tts synthesize failed: $e');
      return null;
    }
  }

  Future<void> preview(String text) async {
    await _configure();
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
