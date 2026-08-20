import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import '../repositories/project_repository.dart';

/// A voice offered by the platform's speech engine.
class TtsVoice {
  const TtsVoice({required this.name, required this.locale});

  final String name;
  final String locale;

  Map<String, String> toMap() => {'name': name, 'locale': locale};

  Map<String, dynamic> toJson() => {'name': name, 'locale': locale};

  static TtsVoice? fromJson(Map<String, dynamic>? j) {
    final name = j?['name'] as String?;
    final locale = j?['locale'] as String?;
    if (name == null || locale == null) return null;
    return TtsVoice(name: name, locale: locale);
  }

  /// Language tag without the engine's punctuation quirks, for comparing a
  /// voice against the device locale (`en_US.UTF-8` and `en-US` must match).
  static String normaliseLocale(String raw) =>
      raw.split('.').first.replaceAll('_', '-').toLowerCase();

  String get language => normaliseLocale(locale).split('-').first;

  String get shortLabel {
    // Engine voice names are long and machine-ish; show the useful part.
    final cleaned = name.replaceAll('_', ' ').replaceAll('-', ' ');
    final parts = cleaned.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return cleaned;
    return parts.sublist(parts.length - 2).join(' ');
  }

  // Value equality lets a voice restored from disk match the one the engine
  // reports, which is also what DropdownButton needs to show a selection.
  @override
  bool operator ==(Object other) =>
      other is TtsVoice && other.name == name && other.locale == locale;

  @override
  int get hashCode => Object.hash(name, locale);
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

  TtsVoice? _saved;
  bool _savedLoaded = false;

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

  // ------------------------------------------------------- chosen voice

  Future<File> _voiceFile() async {
    final dir = await ProjectRepository.instance.mediaDir();
    return File('${dir.path}/tts_voice.json');
  }

  /// The voice the user picked last time, or null if they never picked one.
  Future<TtsVoice?> savedVoice() async {
    if (_savedLoaded) return _saved;
    _savedLoaded = true;
    try {
      final f = await _voiceFile();
      if (await f.exists()) {
        _saved = TtsVoice.fromJson(
            (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>());
      }
    } catch (e) {
      debugPrint('tts saved voice read failed: $e');
    }
    return _saved;
  }

  /// Remembers the user's choice so the next project starts with it.
  Future<void> rememberVoice(TtsVoice? voice) async {
    _saved = voice;
    _savedLoaded = true;
    try {
      final f = await _voiceFile();
      if (voice == null) {
        if (await f.exists()) await f.delete();
      } else {
        await f.writeAsString(jsonEncode(voice.toJson()), flush: true);
      }
    } catch (e) {
      debugPrint('tts saved voice write failed: $e');
    }
  }

  /// Which voice to start on: the one the user chose, else the closest match
  /// for the device's own language, else whatever the engine lists first.
  ///
  /// Taking `available.first` on its own is what made an English script
  /// narrate in Arabic — engines list locales alphabetically, so `ar` wins.
  Future<TtsVoice?> defaultVoice(List<TtsVoice> available) async {
    if (available.isEmpty) return null;

    final saved = await savedVoice();
    if (saved != null) {
      final exact = available.firstWhereOrNull((v) => v == saved);
      if (exact != null) return exact;
      // The engine can rename a voice across updates; the locale still holds.
      final sameLocale = available.firstWhereOrNull(
          (v) => TtsVoice.normaliseLocale(v.locale) ==
              TtsVoice.normaliseLocale(saved.locale));
      if (sameLocale != null) return sameLocale;
    }

    final device = TtsVoice.normaliseLocale(Platform.localeName);
    final language = device.split('-').first;
    return available.firstWhereOrNull(
            (v) => TtsVoice.normaliseLocale(v.locale) == device) ??
        available.firstWhereOrNull((v) => v.language == language) ??
        available.first;
  }

  /// Pushes one voice and its delivery settings onto the engine. Language is
  /// set before the voice, never after, or it would override the choice.
  Future<void> _applyVoice(
    TtsVoice? voice,
    String? language,
    double rate,
    double pitch,
    double volume,
  ) async {
    final locale = language ?? voice?.locale;
    if (locale != null) await _tts.setLanguage(locale);
    if (voice != null) await _tts.setVoice(voice.toMap());
    await _tts.setSpeechRate(rate.clamp(0.1, 1.0));
    await _tts.setPitch(pitch.clamp(0.5, 2.0));
    await _tts.setVolume(volume.clamp(0.0, 1.0));
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
      await _applyVoice(voice, language, rate, pitch, volume);

      final dir = await ProjectRepository.instance.mediaDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'tts_$stamp.wav';
      final absolute = '${dir.path}/$fileName';

      await _tts.synthesizeToFile(text, Platform.isIOS ? fileName : absolute);

      final f = File(absolute);
      if (await _usable(f)) return absolute;

      final rescued = await _rescue(fileName, absolute);
      if (rescued != null) return rescued;

      debugPrint('tts produced no usable file for "$text"');
      return null;
    } catch (e) {
      debugPrint('tts synthesize failed: $e');
      return null;
    }
  }

  Future<bool> _usable(File f) async =>
      await f.exists() && await f.length() > 1024;

  /// Finds the clip when the engine ignored the path we asked for.
  ///
  /// Android's TextToSpeech publishes through MediaStore instead of writing
  /// where it was told, landing the file in shared storage under the whole
  /// requested path with every `/` turned into `_`. iOS drops it in the
  /// documents directory under the bare name. Either way the audio is real,
  /// so it is moved into app storage and the stray copy cleaned up.
  Future<String?> _rescue(String fileName, String absolute) async {
    final names = {absolute.replaceAll('/', '_'), fileName};
    for (final dir in await _strayDirs()) {
      for (final name in names) {
        final stray = File('${dir.path}/$name');
        if (!await _usable(stray)) continue;
        try {
          await stray.copy(absolute);
          // Best effort: shared storage may refuse the delete, and a leftover
          // file is worth far less than losing the narration.
          try {
            await stray.delete();
          } catch (_) {}
          return absolute;
        } catch (e) {
          debugPrint('tts rescue copy failed from ${stray.path}: $e');
        }
      }
    }
    return null;
  }

  Future<List<Directory>> _strayDirs() async {
    final out = <Directory>[];
    try {
      final docs = await getApplicationDocumentsDirectory();
      out.add(docs);
      out.add(docs.parent);
    } catch (_) {}
    if (Platform.isAndroid) {
      try {
        // <shared>/Android/data/<pkg>/files — four levels below shared root.
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          out.add(ext);
          var root = ext;
          for (var i = 0; i < 4 && root.parent.path != root.path; i++) {
            root = root.parent;
          }
          out.add(Directory('${root.path}/Music'));
          out.add(root);
        }
      } catch (_) {}
      out.add(Directory('/sdcard/Music'));
    }
    return out;
  }

  /// Speaks a sample out loud with the very settings the render will use, so
  /// "hear the voice" is a real preview and not a different voice entirely.
  Future<void> preview(
    String text, {
    TtsVoice? voice,
    String? language,
    double rate = 0.5,
    double pitch = 1.0,
    double volume = 1.0,
  }) async {
    await _configure();
    await _tts.stop();
    await _applyVoice(voice, language, rate, pitch, volume);
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
