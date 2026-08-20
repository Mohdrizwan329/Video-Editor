import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/app_env.dart';
import '../models/enums.dart';
import '../models/project.dart';
import '../models/video_clip.dart';
import '../repositories/project_repository.dart';
import 'gemini_video_client.dart';
import 'media_probe.dart';

/// What the app remembers between runs: the last setup used.
///
/// The key is deliberately not part of this — it comes from [AppEnv], so
/// there is nothing to type in and nothing to store. This file only holds the
/// choices the screen makes, in the app's private documents folder.
class AiSettings {
  AiSettings({
    this.model = AiVideoService.defaultModel,
    this.aspectRatio = '9:16',
    this.durationSeconds = 8,
    this.resolution,
  });

  /// The key the app was built with. Never written to disk.
  String get apiKey => AppEnv.geminiKey;

  String model;

  /// Veo renders 16:9 and 9:16 only, so those are the two the app offers.
  String aspectRatio;
  int durationSeconds;

  /// `720p` / `1080p`, or null to let the model decide.
  String? resolution;

  bool get hasKey => apiKey.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'model': model,
        'aspect': aspectRatio,
        'duration': durationSeconds,
        'resolution': resolution,
      };

  factory AiSettings.fromJson(Map<String, dynamic> j) => AiSettings(
        // A settings file written before this app spoke to Google can hold a
        // model id from another provider; anything that is not a Veo id is
        // dropped rather than sent to an API that would 404 on it.
        model: _veoOrDefault(j['model'] as String?),
        aspectRatio: j['aspect'] == '16:9' ? '16:9' : '9:16',
        durationSeconds: (j['duration'] as num?)?.toInt() ?? 8,
        resolution: j['resolution'] as String?,
      );

  static String _veoOrDefault(String? stored) {
    final id = stored?.trim() ?? '';
    return id.startsWith('veo') ? id : AiVideoService.defaultModel;
  }

  /// True when the chosen model takes a length; Veo 3 renders a fixed 8
  /// seconds and rejects the parameter.
  bool get takesDuration =>
      VeoModel(id: model, displayName: model).takesDuration;

  /// Seconds one shot will actually run for, used for the on-screen estimate.
  int get shotSeconds => takesDuration ? durationSeconds : 8;
}

/// Loads and stores [AiSettings].
class AiSettingsStore {
  AiSettingsStore._();

  static final AiSettingsStore instance = AiSettingsStore._();

  AiSettings? _cached;

  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}/sve_ai_settings.json');
  }

  Future<AiSettings> load() async {
    if (_cached != null) return _cached!;
    var settings = AiSettings();
    try {
      final f = await _file();
      if (await f.exists()) {
        settings = AiSettings.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('ai settings unreadable: $e');
    }
    return _cached = settings;
  }

  Future<void> save(AiSettings settings) async {
    _cached = settings;
    final f = await _file();
    await f.writeAsString(jsonEncode(settings.toJson()), flush: true);
  }

}

/// Stage a generation is in, so the screen can say something true while the
/// user waits several minutes.
enum AiJobStage { preparing, queued, rendering, downloading, done }

class AiJobUpdate {
  const AiJobUpdate({
    required this.stage,
    required this.message,
    this.shot = 1,
    this.shots = 1,
    this.fraction,
    this.elapsed = Duration.zero,
  });

  final AiJobStage stage;
  final String message;
  final int shot;
  final int shots;

  /// 0..1 where it is genuinely known (downloads); null while the model runs,
  /// because the API reports no progress for a running job.
  final double? fraction;
  final Duration elapsed;
}

/// Lets the user abort a run that is already in flight.
class AiCancelToken {
  bool _cancelled = false;

  /// Name of the operation on Google once it exists, for the record.
  String? operationName;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Raised when a generation cannot finish, with a message worth showing.
class AiVideoException implements Exception {
  const AiVideoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Turns a written prompt into real AI-generated footage on the timeline.
///
/// The model is Google's Veo, reached through the Gemini API with the user's
/// own AI Studio key — the same family of models the Gemini app uses for
/// video. The app posts the prompt, waits for the long-running operation,
/// downloads the MP4 and hands back a local path.
class AiVideoService {
  AiVideoService._();

  static final AiVideoService instance = AiVideoService._();

  /// Used until the settings screen has listed what the key can really reach.
  static const String defaultModel = 'veo-3.0-fast-generate-preview';

  static const Duration _maxWait = Duration(minutes: 15);

  /// How often a running job is polled. Google reports no progress for a
  /// running operation, so this only decides how soon the result is noticed.
  @visibleForTesting
  Duration pollInterval = const Duration(seconds: 8);

  /// Test seam: sends every request to a loopback server instead of the real
  /// API. Left null in the app.
  @visibleForTesting
  String? testHost;

  GeminiVideoClient client(String apiKey) => testHost == null
      ? GeminiVideoClient(apiKey)
      : GeminiVideoClient(apiKey, host: testHost!, secure: false);

  /// The two shapes Veo renders.
  static const List<String> aspectRatios = ['9:16', '16:9'];

  static String aspectFor(CanvasRatio ratio) =>
      ratio == CanvasRatio.r16x9 ? '16:9' : '9:16';

  static CanvasRatio ratioFor(String aspect) =>
      aspect == '16:9' ? CanvasRatio.r16x9 : CanvasRatio.r9x16;

  /// Splits a script into one prompt per shot. Blank lines separate shots, so
  /// a single paragraph stays one shot no matter how many sentences it has.
  static List<String> splitShots(String script) => script
      .split(RegExp(r'\n\s*\n|\r\n\s*\r\n'))
      .map((s) => s.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// Every video model the key can reach. Also the cheapest possible key
  /// check: listing models is free.
  Future<List<VeoModel>> availableModels(String apiKey) =>
      client(apiKey).listVideoModels();

  /// Generates one shot and returns the path of the downloaded video.
  Future<String> generateShot({
    required String prompt,
    required AiSettings settings,
    String? negativePrompt,
    AiCancelToken? cancelToken,
    void Function(AiJobUpdate)? onUpdate,
    int shot = 1,
    int shots = 1,
  }) async {
    if (prompt.trim().isEmpty) {
      throw const AiVideoException('Write what the video should show.');
    }
    if (!settings.hasKey) {
      throw const AiVideoException(AppEnv.missingKeyMessage);
    }
    final api = client(settings.apiKey);
    final started = DateTime.now();

    void report(AiJobStage stage, String message, {double? fraction}) {
      onUpdate?.call(AiJobUpdate(
        stage: stage,
        message: message,
        shot: shot,
        shots: shots,
        fraction: fraction,
        elapsed: DateTime.now().difference(started),
      ));
    }

    report(AiJobStage.queued, 'Sending the prompt to Veo');
    String operation;
    try {
      operation = await _start(api, settings.model, settings, prompt,
          negativePrompt);
    } on GeminiException catch (e) {
      // Google retires and renames Veo versions, so a stored id can simply
      // stop existing. Rather than dead-ending the user, ask the key what it
      // can film and try that once.
      if (e.statusCode != 404) throw AiVideoException(e.message);
      report(AiJobStage.preparing, 'Finding a model this key can use');
      final resolved = await _resolveModel(api);
      settings.model = resolved;
      await AiSettingsStore.instance.save(settings);
      try {
        operation =
            await _start(api, resolved, settings, prompt, negativePrompt);
      } on GeminiException catch (e) {
        throw AiVideoException(e.message);
      }
    }
    cancelToken?.operationName = operation;

    VeoOperation status;
    while (true) {
      if (cancelToken?.isCancelled ?? false) {
        throw const AiVideoException('Generation cancelled.');
      }
      if (DateTime.now().difference(started) > _maxWait) {
        throw const AiVideoException(
            'The model took too long. Try a shorter prompt or the fast model.');
      }
      await Future<void>.delayed(pollInterval);
      try {
        status = await api.pollOperation(operation);
      } on GeminiException catch (e) {
        // A blip while polling should not throw away a job that is still
        // running; only a hard failure ends the wait.
        if (e.retryable) continue;
        throw AiVideoException(e.message);
      }
      if (status.done) break;
      report(AiJobStage.rendering, 'Veo is filming your shot');
    }

    if (status.error != null) {
      throw AiVideoException('Veo could not make this shot: ${status.error}');
    }
    if (!status.hasVideo) {
      throw const AiVideoException(
          'The model finished but returned no video. Try rewording the prompt.');
    }

    report(AiJobStage.downloading, 'Downloading the video', fraction: 0);
    final dir = await ProjectRepository.instance.mediaDir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/ai_${stamp}_$shot.mp4');
    try {
      if (status.videoUri != null) {
        await api.downloadVideo(
          status.videoUri!,
          file,
          onProgress: (f) => report(AiJobStage.downloading,
              'Downloading the video',
              fraction: f),
        );
      } else {
        await api.writeBase64(status.videoBase64!, file);
      }
    } on GeminiException catch (e) {
      throw AiVideoException(e.message);
    }
    report(AiJobStage.done, 'Ready');
    return file.path;
  }

  /// One start attempt, sending only the parameters [model] really takes: an
  /// unsupported parameter is a hard 400 from this API, while a missing one
  /// just falls back to the model's default.
  Future<String> _start(
    GeminiVideoClient api,
    String model,
    AiSettings settings,
    String prompt,
    String? negativePrompt,
  ) {
    final shape = VeoModel(id: model, displayName: model);
    return api.startGeneration(
      model: model,
      prompt: prompt.trim(),
      aspectRatio: settings.aspectRatio,
      negativePrompt: negativePrompt,
      durationSeconds:
          shape.takesDuration ? settings.durationSeconds.clamp(5, 8) : null,
      resolution: shape.takesResolution ? _resolutionFor(settings) : null,
    );
  }

  /// Picks a model when the configured one no longer exists.
  ///
  /// The cheap variants come first on purpose: this runs without the user
  /// asking for it, and a substitution they did not choose should not be the
  /// one that bills the most. Within a tier the newest name wins.
  Future<String> _resolveModel(GeminiVideoClient api) async {
    final List<VeoModel> models;
    try {
      models = await api.listVideoModels();
    } on GeminiException catch (e) {
      throw AiVideoException(e.message);
    }
    if (models.isEmpty) {
      throw const AiVideoException(
          'This key cannot reach any video model. Veo needs a Google account '
          'with billing switched on.');
    }
    return preferredModel(models);
  }

  /// Cheapest-first ordering: `lite`, then `fast`, then the full model.
  @visibleForTesting
  static String preferredModel(List<VeoModel> models) {
    int tier(VeoModel m) {
      if (m.id.contains('lite')) return 0;
      if (m.id.contains('fast')) return 1;
      return 2;
    }

    final sorted = [...models]..sort((a, b) {
        final byTier = tier(a).compareTo(tier(b));
        return byTier != 0 ? byTier : b.id.compareTo(a.id);
      });
    return sorted.first.id;
  }

  /// 1080p only exists in landscape, so a portrait request is stepped down
  /// rather than being rejected by the API.
  String? _resolutionFor(AiSettings settings) {
    final wanted = settings.resolution;
    if (wanted == null) return null;
    if (wanted == '1080p' && settings.aspectRatio != '16:9') return '720p';
    return wanted;
  }

  /// Lays generated shots onto a fresh project and saves it.
  Future<Project> assembleProject({
    required List<String> paths,
    required CanvasRatio ratio,
    required String name,
    TransitionType transition = TransitionType.fade,
  }) async {
    if (paths.isEmpty) {
      throw const AiVideoException('Nothing was generated.');
    }
    final project = Project(name: name, ratio: ratio);
    for (var i = 0; i < paths.length; i++) {
      final info = await MediaProbe.probe(paths[i]);
      project.clips.add(VideoClip(
        path: paths[i],
        isImage: false,
        hasAudio: info.hasAudio,
        sourceDuration: info.duration,
        sourceWidth: info.displayWidth,
        sourceHeight: info.displayHeight,
        fit: FitMode.cover,
        transitionType: i == paths.length - 1 ? TransitionType.none : transition,
        transitionDuration: const Duration(milliseconds: 400),
      ));
    }
    await ProjectRepository.instance.save(project);
    return project;
  }
}
