import 'package:flutter_test/flutter_test.dart';

import 'package:saleem_video_editor/core/utils/app_env.dart';
import 'package:saleem_video_editor/data/models/enums.dart';
import 'package:saleem_video_editor/data/services/ai_video_service.dart';
import 'package:saleem_video_editor/data/services/gemini_video_client.dart';

void main() {
  group('model listing', () {
    test('a model entry keeps its id without the models/ prefix', () {
      final model = VeoModel.fromJson({
        'name': 'models/veo-3.0-generate-preview',
        'displayName': 'Veo 3',
        'description': 'Video with audio',
      });
      expect(model.id, 'veo-3.0-generate-preview');
      expect(model.displayName, 'Veo 3');
    });

    test('Veo 2 takes a duration, Veo 3 does not', () {
      const veo2 = VeoModel(id: 'veo-2.0-generate-001', displayName: 'Veo 2');
      const veo3 =
          VeoModel(id: 'veo-3.0-generate-preview', displayName: 'Veo 3');
      expect(veo2.takesDuration, isTrue);
      expect(veo3.takesDuration, isFalse);
      // Resolution and audio are the other way round.
      expect(veo2.takesResolution, isFalse);
      expect(veo3.takesResolution, isTrue);
      expect(veo3.hasAudio, isTrue);
      expect(veo2.hasAudio, isFalse);
    });
  });

  group('operation reading', () {
    VeoOperation read(Map<String, dynamic> j) => VeoOperation.fromJson(j);

    test('a job still running is not done and has no video', () {
      final op = read({'name': 'models/veo/operations/abc', 'done': false});
      expect(op.done, isFalse);
      expect(op.hasVideo, isFalse);
      expect(op.error, isNull);
    });

    test('the video uri is found in the generatedSamples shape', () {
      final op = read({
        'name': 'op1',
        'done': true,
        'response': {
          'generateVideoResponse': {
            'generatedSamples': [
              {
                'video': {'uri': 'https://g.dev/files/abc:download?alt=media'}
              }
            ]
          }
        },
      });
      expect(op.videoUri, 'https://g.dev/files/abc:download?alt=media');
      expect(op.hasVideo, isTrue);
    });

    test('the video uri is found in the generatedVideos shape too', () {
      final op = read({
        'name': 'op1',
        'done': true,
        'response': {
          'generatedVideos': [
            {
              'video': {'uri': 'https://g.dev/files/xyz'}
            }
          ]
        },
      });
      expect(op.videoUri, 'https://g.dev/files/xyz');
    });

    test('an inlined base64 video is picked up when there is no link', () {
      final long = 'A' * 200;
      final op = read({
        'name': 'op1',
        'done': true,
        'response': {
          'videos': [
            {'bytesBase64Encoded': long}
          ]
        },
      });
      expect(op.videoUri, isNull);
      expect(op.videoBase64, long);
      expect(op.hasVideo, isTrue);
    });

    test('an error on the operation is surfaced as a message', () {
      final op = read({
        'name': 'op1',
        'done': true,
        'error': {'code': 3, 'message': 'prompt blocked by safety filters'},
      });
      expect(op.error, 'prompt blocked by safety filters');
      expect(op.hasVideo, isFalse);
    });

    test('a done job with an empty response has no video', () {
      final op = read({'name': 'op1', 'done': true, 'response': {}});
      expect(op.done, isTrue);
      expect(op.hasVideo, isFalse);
    });
  });

  group('shots and settings', () {
    test('a blank line starts a new shot', () {
      final shots = AiVideoService.splitShots(
          'A wide desert road.\nDust in the air.\n\nClose up of the driver.');
      expect(shots.length, 2);
      expect(shots.first, 'A wide desert road. Dust in the air.');
      expect(shots.last, 'Close up of the driver.');
    });

    test('empty text is no shots at all', () {
      expect(AiVideoService.splitShots('  \n\n '), isEmpty);
    });

    test('only the two shapes Veo renders are offered', () {
      expect(AiVideoService.aspectRatios, ['9:16', '16:9']);
      expect(AiVideoService.aspectFor(CanvasRatio.r16x9), '16:9');
      expect(AiVideoService.aspectFor(CanvasRatio.r9x16), '9:16');
      // Anything else falls back to portrait rather than sending a ratio the
      // model would reject.
      expect(AiVideoService.aspectFor(CanvasRatio.r1x1), '9:16');
      expect(AiVideoService.ratioFor('16:9'), CanvasRatio.r16x9);
      expect(AiVideoService.ratioFor('9:16'), CanvasRatio.r9x16);
    });

    test('settings survive a JSON round trip', () {
      final settings = AiSettings(
        model: 'veo-3.0-generate-preview',
        aspectRatio: '16:9',
        durationSeconds: 8,
        resolution: '1080p',
      );
      final copy = AiSettings.fromJson(settings.toJson());
      expect(copy.model, 'veo-3.0-generate-preview');
      expect(copy.aspectRatio, '16:9');
      expect(copy.durationSeconds, 8);
      expect(copy.resolution, '1080p');
    });

    test('the key is never written to the settings file', () {
      AppEnv.overrideKey = 'AIzaSecret';
      addTearDown(() => AppEnv.overrideKey = null);
      final settings = AiSettings();
      expect(settings.apiKey, 'AIzaSecret');
      expect(settings.hasKey, isTrue);
      expect(settings.toJson().toString(), isNot(contains('AIzaSecret')),
          reason: 'the key belongs to the build, not to saved state');
    });

    test('no key configured reads as not connected', () {
      AppEnv.overrideKey = '   ';
      addTearDown(() => AppEnv.overrideKey = null);
      expect(AiSettings().hasKey, isFalse);
    });

    test('fresh settings default to portrait on the fast model', () {
      final settings = AiSettings();
      expect(settings.aspectRatio, '9:16');
      expect(settings.model, AiVideoService.defaultModel);
      expect(settings.resolution, isNull);
    });
  });

  group('settings migration', () {
    test('a model id from another provider is dropped', () {
      // What a settings file written before this app spoke to Google holds.
      final settings = AiSettings.fromJson({
        'token': 'r8_old_secret',
        'model': 'bytedance/seedance-1-lite',
        'aspect': '9:16',
        'duration': 5,
      });
      expect(settings.model, AiVideoService.defaultModel);
      expect(settings.hasKey, isFalse, reason: 'an old token is not a Google key');
    });

    test('a real Veo id is kept', () {
      final settings =
          AiSettings.fromJson({'model': 'veo-3.0-generate-preview'});
      expect(settings.model, 'veo-3.0-generate-preview');
    });

    test('an aspect ratio Veo cannot render becomes portrait', () {
      expect(AiSettings.fromJson({'aspect': '1:1'}).aspectRatio, '9:16');
      expect(AiSettings.fromJson({'aspect': '16:9'}).aspectRatio, '16:9');
    });

    test('shot length follows what the model really does', () {
      final veo3 = AiSettings(model: 'veo-3.0-fast-generate-preview')
        ..durationSeconds = 5;
      final veo2 = AiSettings(model: 'veo-2.0-generate-001')
        ..durationSeconds = 5;
      expect(veo3.takesDuration, isFalse);
      expect(veo3.shotSeconds, 8, reason: 'Veo 3 always renders 8 seconds');
      expect(veo2.takesDuration, isTrue);
      expect(veo2.shotSeconds, 5);
    });
  });

  group('environment', () {
    tearDown(() => AppEnv.overrideKey = null);

    test('a key that is only whitespace counts as missing', () {
      AppEnv.overrideKey = '   ';
      expect(AppEnv.hasGeminiKey, isFalse);
      expect(AppEnv.geminiKey, isEmpty);
    });

    test('a configured key is trimmed', () {
      AppEnv.overrideKey = '  AIzaKey  ';
      expect(AppEnv.geminiKey, 'AIzaKey');
      expect(AppEnv.hasGeminiKey, isTrue);
    });

    test('the missing-key message names the file to edit', () {
      expect(AppEnv.missingKeyMessage, contains('.env'));
      expect(AppEnv.missingKeyMessage, contains('GEMINI_API_KEY'));
    });
  });

  group('choosing a model for the user', () {
    List<VeoModel> models(List<String> ids) =>
        [for (final id in ids) VeoModel(id: id, displayName: id)];

    test('the cheapest tier wins when the app has to pick', () {
      expect(
        AiVideoService.preferredModel(models([
          'veo-3.1-generate-preview',
          'veo-3.1-fast-generate-preview',
          'veo-3.1-lite-generate-preview',
        ])),
        'veo-3.1-lite-generate-preview',
      );
    });

    test('fast is taken when there is no lite', () {
      expect(
        AiVideoService.preferredModel(models([
          'veo-3.1-generate-preview',
          'veo-3.1-fast-generate-preview',
        ])),
        'veo-3.1-fast-generate-preview',
      );
    });

    test('within a tier the newer name wins', () {
      expect(
        AiVideoService.preferredModel(models([
          'veo-3.0-lite-generate-preview',
          'veo-3.1-lite-generate-preview',
        ])),
        'veo-3.1-lite-generate-preview',
      );
    });

    test('a single full model is still used', () {
      expect(AiVideoService.preferredModel(models(['veo-3.1-generate-preview'])),
          'veo-3.1-generate-preview');
    });
  });
}
