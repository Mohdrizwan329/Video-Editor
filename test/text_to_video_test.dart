import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:saleem_video_editor/data/models/enums.dart';
import 'package:saleem_video_editor/data/models/keyframe.dart';
import 'package:saleem_video_editor/data/models/project.dart';
import 'package:saleem_video_editor/data/services/text_to_video_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('scene splitting', () {
    test('every line becomes its own scene', () {
      final scenes = TextToVideoService.splitScenes(
          'First line\nSecond line\n\n  \nThird line');
      expect(scenes, ['First line', 'Second line', 'Third line']);
    });

    test('sentences inside one line split, keeping their punctuation', () {
      final scenes = TextToVideoService.splitScenes(
          'One thing happened. Then another! And you? Done');
      expect(scenes, [
        'One thing happened.',
        'Then another!',
        'And you?',
        'Done',
      ]);
    });

    test('the Devanagari danda ends a sentence too', () {
      final scenes = TextToVideoService.splitScenes('पहला वाक्य। दूसरा वाक्य।');
      expect(scenes, ['पहला वाक्य।', 'दूसरा वाक्य।']);
    });

    test('an over-long sentence is chunked on word boundaries', () {
      final long = List.filled(40, 'word').join(' ');
      final scenes = TextToVideoService.splitScenes(long, maxChars: 40);
      expect(scenes.length, greaterThan(1));
      for (final s in scenes) {
        expect(s.length, lessThanOrEqualTo(40));
        expect(s.trim(), s);
      }
      // Nothing may be dropped on the way.
      expect(scenes.join(' ').split(' ').length, 40);
    });

    test('empty input yields no scenes', () {
      expect(TextToVideoService.splitScenes('   \n\n  '), isEmpty);
    });
  });

  group('line wrapping', () {
    test('wraps at the budget without splitting words', () {
      final wrapped = TextToVideoService.wrapLines(
          'the quick brown fox jumps over the lazy dog', 14);
      for (final line in wrapped.split('\n')) {
        expect(line.length, lessThanOrEqualTo(14));
      }
      expect(wrapped.replaceAll('\n', ' '),
          'the quick brown fox jumps over the lazy dog');
    });

    test('a word longer than the budget stays on its own line', () {
      final wrapped =
          TextToVideoService.wrapLines('short supercalifragilistic end', 10);
      expect(wrapped.split('\n'), ['short', 'supercalifragilistic', 'end']);
    });
  });

  group('estimate', () {
    test('grows with the number of scenes', () {
      const one = TextToVideoRequest(script: 'One line');
      const three = TextToVideoRequest(script: 'One line\nTwo\nThree');
      expect(TextToVideoService.estimate(three),
          greaterThan(TextToVideoService.estimate(one)));
    });

    test('an empty script estimates nothing', () {
      expect(TextToVideoService.estimate(const TextToVideoRequest(script: '')),
          Duration.zero);
    });

    test('a longer scene floor makes a longer video', () {
      const fast = TextToVideoRequest(
          script: 'A\nB\nC', sceneDuration: Duration(seconds: 2));
      const slow = TextToVideoRequest(
          script: 'A\nB\nC', sceneDuration: Duration(seconds: 6));
      expect(TextToVideoService.estimate(slow),
          greaterThan(TextToVideoService.estimate(fast)));
    });
  });

  group('styles', () {
    test('every style has a unique id and resolves back', () {
      final ids = TextVideoStyle.all.map((s) => s.id).toSet();
      expect(ids.length, TextVideoStyle.all.length);
      for (final s in TextVideoStyle.all) {
        expect(TextVideoStyle.byId(s.id).name, s.name);
      }
    });

    test('an unknown id falls back to the first style', () {
      expect(TextVideoStyle.byId('nope').id, TextVideoStyle.all.first.id);
    });

    test('a request exposes the style it was built with', () {
      const request = TextToVideoRequest(
        script: 'hi',
        styleId: 'neon',
        ratio: CanvasRatio.r16x9,
      );
      expect(request.style.id, 'neon');
      expect(request.ratio.value, 16 / 9);
    });
  });

  group('generation', () {
    late Directory sandbox;

    // One sandbox for the whole group: [ProjectRepository] caches the
    // directory it resolved the first time, so a per-test folder would be
    // deleted out from under it.
    setUpAll(() {
      // The service writes artwork and the project JSON through
      // path_provider, which has no implementation under `flutter test`.
      sandbox = Directory.systemTemp.createTempSync('t2v_test');
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

    testWidgets('builds a clip, artwork and a text layer per scene',
        (tester) async {
      Project? built;
      await tester.runAsync(() async {
        built = await TextToVideoService.instance.generate(
          const TextToVideoRequest(
            script: 'First scene here\nSecond scene here',
            title: 'My headline',
            ratio: CanvasRatio.r9x16,
          ),
        );
      });
      final p = built!;

      // Title plus the two script lines.
      expect(p.clips.length, 3);
      expect(p.texts.length, 3);
      expect(p.audios, isEmpty);
      expect(p.name, 'My headline');

      for (final clip in p.clips) {
        expect(clip.isImage, isTrue);
        expect(clip.hasAudio, isFalse);
        expect(File(clip.path).existsSync(), isTrue,
            reason: 'scene artwork must be written to disk');
        // 9:16 art at the service's 1920 long side, both sides even.
        expect(clip.sourceHeight, 1920);
        expect(clip.sourceWidth.isEven, isTrue);
      }

      expect(p.texts.first.text, 'My headline');
      expect(p.coverPath, p.clips.first.path);
      // Every scene but the last carries the style's transition.
      expect(p.clips.last.transitionType, TransitionType.none);
      expect(p.clips.first.transitionType, isNot(TransitionType.none));
      // Ken Burns is two scale keys per clip by default.
      expect(p.clips.first.trackOrNull(KeyframeProperty.scale)?.keys.length, 2);
      // The saved JSON is what the home screen will list.
      expect(
        Directory('${sandbox.path}/sve_projects')
            .listSync()
            .whereType<File>()
            .any((f) => f.path.endsWith('${p.id}.json')),
        isTrue,
      );
    });

    testWidgets('text is laid out inside each scene, never past its end',
        (tester) async {
      Project? built;
      await tester.runAsync(() async {
        built = await TextToVideoService.instance.generate(
          const TextToVideoRequest(script: 'One\nTwo\nThree'),
        );
      });
      final p = built!;
      for (var i = 0; i < p.clips.length; i++) {
        final text = p.texts[i];
        expect(text.start, p.clipStart(i));
        expect(text.end, lessThanOrEqualTo(p.totalDuration));
      }
    });

    testWidgets('an empty script is refused rather than saved',
        (tester) async {
      await tester.runAsync(() async {
        expect(
          () => TextToVideoService.instance
              .generate(const TextToVideoRequest(script: '   ')),
          throwsA(isA<TextToVideoException>()),
        );
      });
    });
  });
}
