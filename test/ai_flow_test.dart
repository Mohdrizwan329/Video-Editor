import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/core/utils/app_env.dart';
import 'package:video_editor/data/services/ai_video_service.dart';
import 'package:video_editor/data/services/gemini_video_client.dart';

/// A stand-in for the Gemini API: lists models, accepts a generation, reports
/// the operation as running and then done, and serves the finished file.
///
/// The point is to exercise the real start/poll/download loop — the part that
/// cannot be checked by reading the code alone — without a paid account.
class FakeGemini {
  FakeGemini({
    this.pollsBeforeDone = 1,
    this.failWith,
    this.responseBuilder,
    this.models = const ['veo-3.0-fast-generate-preview', 'veo-2.0-generate-001'],
  });

  final int pollsBeforeDone;

  /// When set, the operation finishes carrying this error instead of a video.
  final String? failWith;

  /// Overrides the finished operation's `response` object.
  final Map<String, dynamic> Function(String host)? responseBuilder;
  final List<String> models;

  late final HttpServer _server;
  int polls = 0;
  int generationsStarted = 0;
  int modelListings = 0;
  Map<String, dynamic>? lastBody;
  String? lastApiKeyHeader;
  String? downloadKeyHeader;
  Uri? downloadUri;

  String get host => '${_server.address.host}:${_server.port}';

  static final List<int> videoBytes =
      List<int>.generate(8192, (i) => (i * 11) % 251);

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    lastApiKeyHeader = request.headers.value('x-goog-api-key');

    if (path == '/v1beta/models') {
      modelListings++;
      _json(request, {
        'models': [
          {
            'name': 'models/gemini-2.5-flash',
            'displayName': 'Gemini Flash',
            'supportedGenerationMethods': ['generateContent'],
          },
          for (final id in models)
            {
              'name': 'models/$id',
              'displayName': id,
              'supportedGenerationMethods': ['predictLongRunning'],
            },
        ],
      });
      return;
    }
    if (path.endsWith(':predictLongRunning')) {
      generationsStarted++;
      final asked = path
          .replaceFirst('/v1beta/models/', '')
          .replaceFirst(':predictLongRunning', '');
      if (!models.contains(asked)) {
        request.response.statusCode = 404;
        _json(request, {
          'error': {
            'code': 404,
            'message': 'models/$asked is not found',
            'status': 'NOT_FOUND',
          }
        });
        return;
      }
      lastBody = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
          .cast<String, dynamic>();
      _json(request, {'name': 'models/veo/operations/op1'});
      return;
    }
    if (path == '/v1beta/models/veo/operations/op1') {
      polls++;
      if (polls <= pollsBeforeDone) {
        _json(request, {'name': 'op1', 'done': false});
      } else if (failWith != null) {
        _json(request, {
          'name': 'op1',
          'done': true,
          'error': {'code': 3, 'message': failWith},
        });
      } else {
        _json(request, {
          'name': 'op1',
          'done': true,
          'response': responseBuilder?.call(host) ??
              {
                'generateVideoResponse': {
                  'generatedSamples': [
                    {
                      'video': {'uri': 'http://$host/v1beta/files/out'}
                    }
                  ]
                }
              },
        });
      }
      return;
    }
    if (path == '/v1beta/files/out') {
      downloadKeyHeader = request.headers.value('x-goog-api-key');
      downloadUri = request.uri;
      request.response
        ..headers.contentType = ContentType('video', 'mp4')
        ..add(videoBytes);
      await request.response.close();
      return;
    }
    request.response.statusCode = 404;
    _json(request, {
      'error': {'code': 404, 'message': 'not found', 'status': 'NOT_FOUND'}
    });
  }

  void _json(HttpRequest request, Map<String, dynamic> body) {
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  }
}

/// A server that answers everything with one error, for the failure paths.
Future<HttpServer> erroringServer(int status, Map<String, dynamic> body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  });
  return server;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;

  setUpAll(() {
    // The widget binding installs HttpOverrides that answer every request
    // with a 400. These tests talk to a loopback server on purpose, so the
    // override is lifted for the suite.
    HttpOverrides.global = null;
    sandbox = Directory.systemTemp.createTempSync('ai_flow');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => sandbox.path,
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  setUp(() {
    // Stands in for the .env the app is built with.
    AppEnv.overrideKey = 'AIzaTest';
    AiVideoService.instance.pollInterval = const Duration(milliseconds: 20);
  });

  tearDown(() {
    AppEnv.overrideKey = null;
    AiVideoService.instance
      ..testHost = null
      ..pollInterval = const Duration(seconds: 8);
  });

  AiSettings settings({String model = 'veo-3.0-fast-generate-preview'}) =>
      AiSettings(
        model: model,
        aspectRatio: '9:16',
        durationSeconds: 8,
      );

  Future<FakeGemini> serve(FakeGemini fake) async {
    await fake.start();
    AiVideoService.instance.testHost = fake.host;
    addTearDown(fake.stop);
    return fake;
  }

  test('a prompt runs end to end and the video lands on disk', () async {
    final fake = await serve(FakeGemini(pollsBeforeDone: 2));

    final stages = <AiJobStage>[];
    final path = await AiVideoService.instance.generateShot(
      prompt: 'a cartoon with two people talking',
      settings: settings(),
      onUpdate: (u) => stages.add(u.stage),
    );

    final file = File(path);
    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync().length, FakeGemini.videoBytes.length);

    // The prompt went out in the shape the API expects.
    final instances = fake.lastBody!['instances'] as List;
    expect((instances.first as Map)['prompt'],
        'a cartoon with two people talking');
    expect(fake.generationsStarted, 1);

    // It really waited for the operation instead of taking the first answer.
    expect(fake.polls, greaterThanOrEqualTo(3));
    expect(stages, contains(AiJobStage.rendering));
    expect(stages.last, AiJobStage.done);

    // The key travels as a header, never in the URL, and the download needs
    // it too — a plain link would 403.
    expect(fake.lastApiKeyHeader, 'AIzaTest');
    expect(fake.downloadKeyHeader, 'AIzaTest');
    expect(fake.downloadUri!.queryParameters['alt'], 'media');
  });

  test('Veo 3 is sent an aspect ratio but never a duration', () async {
    final fake = await serve(FakeGemini(pollsBeforeDone: 0));
    await AiVideoService.instance.generateShot(
      prompt: 'x',
      settings: settings(),
      negativePrompt: 'blurry, watermark',
    );
    final params = fake.lastBody!['parameters'] as Map;
    expect(params['aspectRatio'], '9:16');
    expect(params['negativePrompt'], 'blurry, watermark');
    expect(params.containsKey('durationSeconds'), isFalse,
        reason: 'Veo 3 renders a fixed length and rejects the parameter');
  });

  test('Veo 2 is sent a duration, clamped to what it allows', () async {
    final fake = await serve(FakeGemini(pollsBeforeDone: 0));
    await AiVideoService.instance.generateShot(
      prompt: 'x',
      settings: settings(model: 'veo-2.0-generate-001')..durationSeconds = 30,
    );
    final params = fake.lastBody!['parameters'] as Map;
    expect(params['durationSeconds'], 8);
    expect(params.containsKey('resolution'), isFalse);
  });

  test('1080p is stepped down to 720p in portrait', () async {
    final fake = await serve(FakeGemini(pollsBeforeDone: 0));
    await AiVideoService.instance.generateShot(
      prompt: 'x',
      settings: settings()..resolution = '1080p',
    );
    expect((fake.lastBody!['parameters'] as Map)['resolution'], '720p');

    await AiVideoService.instance.generateShot(
      prompt: 'x',
      settings: settings()
        ..resolution = '1080p'
        ..aspectRatio = '16:9',
    );
    expect((fake.lastBody!['parameters'] as Map)['resolution'], '1080p');
  });

  test('an empty negative prompt is not sent at all', () async {
    final fake = await serve(FakeGemini(pollsBeforeDone: 0));
    await AiVideoService.instance
        .generateShot(prompt: 'x', settings: settings(), negativePrompt: '  ');
    expect((fake.lastBody!['parameters'] as Map).containsKey('negativePrompt'),
        isFalse);
  });

  test('a video inlined as base64 is written out instead of downloaded',
      () async {
    final bytes = base64Encode(FakeGemini.videoBytes);
    await serve(FakeGemini(
      pollsBeforeDone: 0,
      responseBuilder: (_) => {
        'videos': [
          {'bytesBase64Encoded': bytes}
        ]
      },
    ));
    final path = await AiVideoService.instance
        .generateShot(prompt: 'x', settings: settings());
    expect(File(path).readAsBytesSync().length, FakeGemini.videoBytes.length);
  });

  test('a blocked prompt is reported in the model\'s own words', () async {
    await serve(FakeGemini(
        pollsBeforeDone: 0, failWith: 'blocked by safety filters'));
    await expectLater(
      AiVideoService.instance.generateShot(prompt: 'x', settings: settings()),
      throwsA(isA<AiVideoException>().having(
          (e) => e.message, 'message', contains('safety filters'))),
    );
  });

  test('a finished job with no video is reported, not downloaded', () async {
    await serve(FakeGemini(pollsBeforeDone: 0, responseBuilder: (_) => {}));
    await expectLater(
      AiVideoService.instance.generateShot(prompt: 'x', settings: settings()),
      throwsA(isA<AiVideoException>()
          .having((e) => e.message, 'message', contains('no video'))),
    );
  });

  test('cancelling ends the wait', () async {
    // Never finishes on its own, so only the cancel can end it.
    await serve(FakeGemini(pollsBeforeDone: 1000));
    final cancel = AiCancelToken();
    await expectLater(
      AiVideoService.instance.generateShot(
        prompt: 'x',
        settings: settings(),
        cancelToken: cancel,
        onUpdate: (u) {
          if (u.stage == AiJobStage.rendering) cancel.cancel();
        },
      ),
      throwsA(isA<AiVideoException>()
          .having((e) => e.message, 'message', contains('cancelled'))),
    );
  });

  test('listing models keeps the video ones and drops the text ones',
      () async {
    final fake = await serve(FakeGemini());
    final models =
        await AiVideoService.instance.availableModels('AIzaTest');
    expect(models.map((m) => m.id),
        containsAll(['veo-3.0-fast-generate-preview', 'veo-2.0-generate-001']));
    expect(models.any((m) => m.id.contains('gemini-2.5-flash')), isFalse);
    expect(fake.modelListings, 1);
  });

  test('a rejected key is reported in plain words', () async {
    final server = await erroringServer(400, {
      'error': {
        'code': 400,
        'message': 'API key not valid. Please pass a valid API key.',
        'status': 'INVALID_ARGUMENT',
      }
    });
    addTearDown(() => server.close(force: true));

    final client = GeminiVideoClient('bad',
        host: '${server.address.host}:${server.port}', secure: false);
    await expectLater(
      client.listVideoModels(),
      throwsA(isA<GeminiException>()
          .having((e) => e.message, 'message', contains('rejected'))
          .having((e) => e.message, 'message', contains('.env'))),
    );
  });

  test('a quota error explains that video is not on the free tier', () async {
    final server = await erroringServer(429, {
      'error': {'code': 429, 'message': 'Quota exceeded', 'status': 'RESOURCE_EXHAUSTED'}
    });
    addTearDown(() => server.close(force: true));

    final client = GeminiVideoClient('AIzaTest',
        host: '${server.address.host}:${server.port}', secure: false);
    await expectLater(
      client.listVideoModels(),
      throwsA(isA<GeminiException>()
          .having((e) => e.message, 'message', contains('free tier'))
          .having((e) => e.message, 'message', contains('paid plan'))
          .having((e) => e.retryable, 'retryable', isTrue)),
    );
  });

  test('a key with no video access is refused before any billing happens',
      () async {
    final server = await erroringServer(403, {
      'error': {'code': 403, 'message': 'PERMISSION_DENIED'}
    });
    addTearDown(() => server.close(force: true));

    final client = GeminiVideoClient('AIzaTest',
        host: '${server.address.host}:${server.port}', secure: false);
    await expectLater(
      client.listVideoModels(),
      throwsA(isA<GeminiException>()
          .having((e) => e.message, 'message', contains('billing'))),
    );
  });

  test('an unconfigured .env never reaches the network', () async {
    AppEnv.overrideKey = '';
    await expectLater(
      AiVideoService.instance.generateShot(prompt: 'x', settings: AiSettings()),
      throwsA(isA<AiVideoException>()
          .having((e) => e.message, 'message', contains('.env'))),
    );
  });

  test('a retired model id is swapped for one the key can use', () async {
    // The stored id 404s; the key really has veo-3.0-fast.
    final fake = await serve(FakeGemini(pollsBeforeDone: 0));
    final chosen = settings(model: 'veo-9.9-does-not-exist');

    final path = await AiVideoService.instance
        .generateShot(prompt: 'x', settings: chosen);

    expect(File(path).existsSync(), isTrue);
    expect(fake.modelListings, 1, reason: 'it asked what the key can film');
    expect(fake.generationsStarted, 2,
        reason: 'one rejected attempt, then the resolved model');
    expect(chosen.model, 'veo-3.0-fast-generate-preview',
        reason: 'the working model is remembered for next time');
  });

  test('a key with no video models fails with a billing message', () async {
    await serve(FakeGemini(pollsBeforeDone: 0, models: const []));
    await expectLater(
      AiVideoService.instance.generateShot(
          prompt: 'x', settings: settings(model: 'veo-9.9-does-not-exist')),
      throwsA(isA<AiVideoException>()
          .having((e) => e.message, 'message', contains('billing'))),
    );
  });
}
