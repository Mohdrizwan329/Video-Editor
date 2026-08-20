import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A failure the user can act on, rather than a raw socket or format error.
class GeminiException implements Exception {
  const GeminiException(this.message, {this.statusCode, this.retryable = false});

  final String message;
  final int? statusCode;

  /// True for transient conditions (quota, 5xx) where retrying later helps.
  final bool retryable;

  @override
  String toString() => message;
}

/// A video model the key can actually reach, as reported by the API.
///
/// Listing rather than hard-coding is what keeps the app working when Google
/// renames or retires a Veo version — the picker only ever offers what the
/// account really has.
class VeoModel {
  const VeoModel({
    required this.id,
    required this.displayName,
    this.description,
  });

  /// Bare id without the `models/` prefix, e.g. `veo-3.0-generate-preview`.
  final String id;
  final String displayName;
  final String? description;

  /// Veo 3 always renders 8 seconds; only Veo 2 takes a duration.
  bool get takesDuration => id.contains('veo-2');

  /// Resolution is a Veo 3 option, and 1080p only exists in landscape.
  bool get takesResolution => !id.contains('veo-2');

  bool get hasAudio => !id.contains('veo-2');

  factory VeoModel.fromJson(Map<String, dynamic> j) {
    final raw = (j['name'] as String? ?? '').replaceFirst('models/', '');
    return VeoModel(
      id: raw,
      displayName: j['displayName'] as String? ?? raw,
      description: j['description'] as String?,
    );
  }
}

/// A long-running generation on the Gemini API.
class VeoOperation {
  const VeoOperation({
    required this.name,
    required this.done,
    this.error,
    this.videoUri,
    this.videoBase64,
  });

  final String name;
  final bool done;
  final String? error;

  /// Where the finished file lives, when the API returns a link.
  final String? videoUri;

  /// The file itself, for the responses that inline it instead.
  final String? videoBase64;

  bool get hasVideo => videoUri != null || videoBase64 != null;

  /// Reads the operation regardless of which response shape it uses: Veo has
  /// moved the video between `generatedSamples`, `generatedVideos` and
  /// `videos` across versions, so the payload is searched rather than indexed.
  factory VeoOperation.fromJson(Map<String, dynamic> j) {
    final error = (j['error'] as Map?)?.cast<String, dynamic>();
    return VeoOperation(
      name: j['name'] as String? ?? '',
      done: j['done'] as bool? ?? false,
      error: error == null
          ? null
          : (error['message']?.toString() ?? 'The model reported an error.'),
      videoUri: _find(j['response'], _uriKeys, (v) => v.startsWith('http')),
      videoBase64: _find(j['response'], _base64Keys, (v) => v.length > 128),
    );
  }

  static const List<String> _uriKeys = ['uri', 'videoUri', 'gcsUri', 'fileUri'];
  static const List<String> _base64Keys = [
    'bytesBase64Encoded',
    'videoBytes',
    'data',
  ];

  /// Depth-first search for the first string under one of [keys] that passes
  /// [accept].
  static String? _find(
      Object? node, List<String> keys, bool Function(String) accept) {
    if (node is Map) {
      for (final key in keys) {
        final value = node[key];
        if (value is String && accept(value)) return value;
      }
      for (final value in node.values) {
        final found = _find(value, keys, accept);
        if (found != null) return found;
      }
    }
    if (node is List) {
      for (final value in node) {
        final found = _find(value, keys, accept);
        if (found != null) return found;
      }
    }
    return null;
  }
}

/// Client for Google's Gemini API — the same Veo models the Gemini app uses
/// for video, reached with the user's own AI Studio key.
///
/// Built on `dart:io` so the app takes on no extra dependency for it.
class GeminiVideoClient {
  GeminiVideoClient(this.apiKey, {this.host = defaultHost, this.secure = true});

  final String apiKey;

  /// Host the API lives on. Only ever changed by tests, which point it at a
  /// loopback server so the whole request/poll/download loop can be exercised
  /// without a real account.
  final String host;
  final bool secure;

  static const String defaultHost = 'generativelanguage.googleapis.com';
  static const String apiVersion = 'v1beta';
  static const Duration _timeout = Duration(seconds: 45);

  Uri _uri(String path, [Map<String, String>? query]) => secure
      ? Uri.https(host, path, query)
      : Uri.http(host, path, query);

  Map<String, String> get _headers => {
        'x-goog-api-key': apiKey,
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.userAgentHeader: 'VideoEditor/1.0 (Flutter)',
      };

  /// Every video-capable model this key can use, newest-looking first.
  ///
  /// Throws when the key is rejected, so this doubles as the key check —
  /// listing models costs nothing.
  Future<List<VeoModel>> listVideoModels() async {
    final models = <VeoModel>[];
    String? pageToken;
    // Bounded: the model list is short, and an unbounded loop on a broken
    // nextPageToken would hang the settings screen.
    for (var page = 0; page < 5; page++) {
      final json = await _get(_uri('/$apiVersion/models', {
        'pageSize': '200',
        'pageToken': ?pageToken,
      }));
      for (final raw in (json['models'] as List?) ?? const []) {
        if (raw is! Map) continue;
        final entry = raw.cast<String, dynamic>();
        final methods = ((entry['supportedGenerationMethods'] as List?) ??
                const [])
            .map((e) => e.toString())
            .toList();
        final name = (entry['name'] as String? ?? '').toLowerCase();
        // Video models are the ones that answer `predictLongRunning`; the
        // name check keeps out any future long-running non-video model.
        if (methods.contains('predictLongRunning') || name.contains('veo')) {
          models.add(VeoModel.fromJson(entry));
        }
      }
      pageToken = json['nextPageToken'] as String?;
      if (pageToken == null || pageToken.isEmpty) break;
    }
    models.sort((a, b) => b.id.compareTo(a.id));
    return models;
  }

  /// Starts a generation and returns the operation name to poll.
  Future<String> startGeneration({
    required String model,
    required String prompt,
    String? aspectRatio,
    String? negativePrompt,
    int? durationSeconds,
    String? resolution,
  }) async {
    final parameters = <String, Object?>{
      'aspectRatio': ?aspectRatio,
      if (negativePrompt != null && negativePrompt.trim().isNotEmpty)
        'negativePrompt': negativePrompt.trim(),
      'durationSeconds': ?durationSeconds,
      'resolution': ?resolution,
    };
    final json = await _post(
      _uri('/$apiVersion/models/$model:predictLongRunning'),
      {
        'instances': [
          {'prompt': prompt}
        ],
        if (parameters.isNotEmpty) 'parameters': parameters,
      },
    );
    final name = json['name'] as String?;
    if (name == null || name.isEmpty) {
      throw const GeminiException(
          'The API accepted the prompt but returned no job to follow.');
    }
    return name;
  }

  Future<VeoOperation> pollOperation(String operationName) async {
    final path = operationName.startsWith('/')
        ? operationName
        : '/$apiVersion/$operationName';
    return VeoOperation.fromJson(await _get(_uri(path)));
  }

  /// Downloads the finished video. The file link needs the same key, so this
  /// cannot be handed to a plain downloader.
  Future<File> downloadVideo(
    String uri,
    File destination, {
    void Function(double)? onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      var target = Uri.parse(uri);
      // Google's file links serve metadata unless asked for the bytes.
      if (!target.queryParameters.containsKey('alt')) {
        target = target.replace(queryParameters: {
          ...target.queryParameters,
          'alt': 'media',
        });
      }
      final request = await client.getUrl(target);
      request.headers.set('x-goog-api-key', apiKey);
      final response =
          await request.close().timeout(const Duration(minutes: 5));
      if (response.statusCode >= 400) {
        throw GeminiException(
          'Could not download the finished video '
          '(HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
          retryable: true,
        );
      }
      final total = response.contentLength;
      var received = 0;
      final sink = destination.openWrite();
      try {
        await for (final chunk in response) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (await destination.length() < 1024) {
        throw const GeminiException('The downloaded video was empty.');
      }
      return destination;
    } on SocketException {
      throw const GeminiException(
        'No internet connection while downloading the video.',
        retryable: true,
      );
    } finally {
      client.close();
    }
  }

  /// Writes an inlined base64 video to [destination].
  Future<File> writeBase64(String base64Data, File destination) async {
    final bytes = base64Decode(base64Data);
    if (bytes.length < 1024) {
      throw const GeminiException('The model returned an empty video.');
    }
    await destination.writeAsBytes(bytes, flush: true);
    return destination;
  }

  // ------------------------------------------------------------ internals

  Future<Map<String, dynamic>> _get(Uri uri) =>
      _send(uri, method: 'GET', body: null);

  Future<Map<String, dynamic>> _post(Uri uri, Map<String, Object?> body) =>
      _send(uri, method: 'POST', body: body);

  Future<Map<String, dynamic>> _send(
    Uri uri, {
    required String method,
    Map<String, Object?>? body,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const GeminiException(
          'Add your Google AI Studio API key before generating.');
    }
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = method == 'GET'
          ? await client.getUrl(uri)
          : await client.postUrl(uri);
      _headers.forEach(request.headers.set);
      if (body != null) request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(_timeout);
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty ? const {} : jsonDecode(text);
      final json = decoded is Map
          ? decoded.cast<String, dynamic>()
          : <String, dynamic>{'response': decoded};

      if (response.statusCode >= 400) {
        throw GeminiException(
          _errorMessage(response.statusCode, json),
          statusCode: response.statusCode,
          retryable: response.statusCode == 429 || response.statusCode >= 500,
        );
      }
      return json;
    } on SocketException {
      throw const GeminiException(
        'No internet connection. Check your network and try again.',
        retryable: true,
      );
    } on TimeoutException {
      throw const GeminiException(
        'Google did not answer in time. Try again.',
        retryable: true,
      );
    } on FormatException {
      throw const GeminiException('Google sent a response we could not read.');
    } finally {
      client.close();
    }
  }

  /// Turns an API error into something worth showing on screen.
  ///
  /// The quota case is the one that matters most here: Veo is not on the free
  /// tier, so a key that works fine for text will fail on video until billing
  /// is switched on — and the raw message does not say that.
  String _errorMessage(int status, Map<String, dynamic> json) {
    final error = (json['error'] as Map?)?.cast<String, dynamic>();
    final detail = error?['message']?.toString();
    final reason = error?['status']?.toString();

    if (detail != null && detail.toLowerCase().contains('api key not valid')) {
      return 'That API key was rejected. Check GEMINI_API_KEY in the .env '
          'file and rebuild the app.';
    }
    return switch (status) {
      400 => detail ?? 'The model rejected these settings.',
      401 || 403 =>
        'This key cannot use video generation. Enable the Generative Language '
            'API and billing for it in Google AI Studio.',
      404 => 'That model is not available to this key.',
      429 =>
        'Out of video quota. Veo is not on the free tier: open '
            'aistudio.google.com, and under Settings → Plan switch this key\'s '
            'project to a paid plan with billing on. Nothing was charged.',
      _ when status >= 500 => 'Google is having trouble right now. Try again.',
      _ => detail ?? reason ?? 'Google returned an error (HTTP $status).',
    };
  }
}
