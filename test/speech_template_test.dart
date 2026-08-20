import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/keyframe.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/template.dart';
import 'package:video_editor/data/models/template_library.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/data/services/caption_service.dart';
import 'package:video_editor/data/services/sound_library.dart';

VideoClip _media(Duration d) => VideoClip(
      path: '/tmp/a.mp4',
      isImage: false,
      sourceDuration: d,
    );

void main() {
  group('SRT', () {
    const srt = '''
1
00:00:01,000 --> 00:00:03,500
Hello there

2
00:00:04,000 --> 00:00:06,000
Second line
spanning two rows
''';

    test('parses blocks with their timings', () {
      final lines = CaptionService.parseSrt(srt);
      expect(lines.length, 2);
      expect(lines.first.start, const Duration(seconds: 1));
      expect(lines.first.end, const Duration(milliseconds: 3500));
      expect(lines.first.text, 'Hello there');
      expect(lines.last.text, 'Second line\nspanning two rows');
    });

    test('skips malformed blocks instead of failing the file', () {
      final lines = CaptionService.parseSrt('''
1
not a timestamp
junk

2
00:00:02,000 --> 00:00:03,000
Good line
''');
      expect(lines.length, 1);
      expect(lines.single.text, 'Good line');
    });

    test('accepts a dot as the millisecond separator', () {
      final lines = CaptionService.parseSrt(
          '1\n00:00:01.250 --> 00:00:02.750\nDotted\n');
      expect(lines.single.start, const Duration(milliseconds: 1250));
    });

    test('round trips through toSrt', () {
      final original = CaptionService.parseSrt(srt);
      final restored = CaptionService.parseSrt(CaptionService.toSrt(original));
      expect(restored.length, original.length);
      expect(restored.first.text, original.first.text);
      expect(restored.first.start, original.first.start);
    });
  });

  group('caption wrapping', () {
    test('leaves short lines alone', () {
      final lines = [
        const CaptionLine(
            start: Duration.zero,
            end: Duration(seconds: 2),
            text: 'Short enough')
      ];
      expect(CaptionService.wrap(lines).length, 1);
    });

    test('splits a long line and keeps the total window', () {
      const line = CaptionLine(
        start: Duration(seconds: 1),
        end: Duration(seconds: 5),
        text: 'This sentence is definitely far too long to sit on one '
            'single caption line without spilling over the canvas',
      );
      final wrapped = CaptionService.wrap([line], maxChars: 30);
      expect(wrapped.length, greaterThan(1));
      expect(wrapped.first.start, line.start);
      // Allow a millisecond of rounding across the shares.
      expect((wrapped.last.end - line.end).inMilliseconds.abs(),
          lessThanOrEqualTo(2));
      for (final w in wrapped) {
        expect(w.text.length, lessThanOrEqualTo(30));
      }
    });

    test('caption layers are flagged so they can be cleared as a group', () {
      final layers = CaptionService.toLayers([
        const CaptionLine(
            start: Duration.zero, end: Duration(seconds: 2), text: 'Hi')
      ]);
      expect(layers.single.isCaption, isTrue);
    });
  });

  group('templates', () {
    test('every template has slots and a reachable category', () {
      expect(TemplateLibrary.all, isNotEmpty);
      for (final t in TemplateLibrary.all) {
        expect(t.slots, isNotEmpty, reason: t.id);
        expect(TemplateLibrary.categories, contains(t.category));
      }
    });

    test('template ids are unique', () {
      final ids = TemplateLibrary.all.map((t) => t.id).toSet();
      expect(ids.length, TemplateLibrary.all.length);
    });

    test('applying a template fills every slot and sets the ratio', () {
      final template = TemplateLibrary.byId('beatDrop')!;
      final project = Project(name: 'x');
      TemplateApplier.apply(
        template: template,
        project: project,
        media: [_media(const Duration(seconds: 6))],
      );
      expect(project.clips.length, template.slotCount);
      expect(project.ratio, template.ratio);
      expect(project.texts, isNotEmpty);
    });

    test('media is cycled when there are fewer items than slots', () {
      final template = TemplateLibrary.byId('listicle')!;
      final project = Project(name: 'x');
      TemplateApplier.apply(
        template: template,
        project: project,
        media: [_media(const Duration(seconds: 5))],
      );
      expect(project.clips.length, 5);
      // Each slot gets its own clip object, not a shared reference.
      expect(project.clips.map((c) => c.id).toSet().length, 5);
    });

    test('the last clip never carries a transition', () {
      final template = TemplateLibrary.byId('quickIntro')!;
      final project = Project(name: 'x');
      TemplateApplier.apply(
        template: template,
        project: project,
        media: [_media(const Duration(seconds: 8))],
      );
      expect(project.clips.last.transitionType, TransitionType.none);
    });

    test('a Ken Burns slot becomes real keyframes', () {
      final template = TemplateLibrary.byId('travelDiary')!;
      final project = Project(name: 'x');
      TemplateApplier.apply(
        template: template,
        project: project,
        media: [_media(const Duration(seconds: 10))],
      );
      final moved = project.clips.where((c) => c.hasKeyframes).toList();
      expect(moved, isNotEmpty);
      expect(moved.first.trackOrNull(KeyframeProperty.scale), isNotNull);
    });

    test('applying twice does not stack layers', () {
      final template = TemplateLibrary.byId('birthday')!;
      final project = Project(name: 'x');
      for (var i = 0; i < 2; i++) {
        TemplateApplier.apply(
          template: template,
          project: project,
          media: [_media(const Duration(seconds: 5))],
        );
      }
      expect(project.clips.length, template.slotCount);
      expect(project.stickers.length, template.stickers.length);
    });
  });

  group('sound library', () {
    test('ids are unique and categories are reachable', () {
      final ids = SoundLibrary.all.map((s) => s.id).toSet();
      expect(ids.length, SoundLibrary.all.length);
      for (final s in SoundLibrary.all) {
        expect(SoundLibrary.categories, contains(s.category));
      }
    });

    test('every category has at least one entry', () {
      for (final c in SoundLibrary.categories) {
        expect(SoundLibrary.byCategory(c), isNotEmpty, reason: c);
      }
    });

    test('beds are long enough to loop under a clip', () {
      final beds = SoundLibrary.all.where((s) => s.kind == SoundKind.bed);
      expect(beds, isNotEmpty);
      for (final b in beds) {
        expect(b.duration.inSeconds, greaterThanOrEqualTo(4));
      }
    });
  });
}
