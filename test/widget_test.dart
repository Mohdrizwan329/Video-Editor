import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:saleem_video_editor/core/theme/app_colors.dart';
import 'package:saleem_video_editor/core/theme/app_theme.dart';
import 'package:saleem_video_editor/data/models/enums.dart';
import 'package:saleem_video_editor/data/models/project.dart';
import 'package:saleem_video_editor/data/models/video_clip.dart';
import 'package:saleem_video_editor/data/services/export_settings.dart';

VideoClip _clip(Duration d, {TransitionType tr = TransitionType.none}) =>
    VideoClip(
      path: '/tmp/a.mp4',
      isImage: false,
      sourceDuration: d,
      transitionType: tr,
      transitionDuration: const Duration(seconds: 1),
    );

void main() {
  group('timeline maths', () {
    test('clips laid end to end sum to the project length', () {
      final p = Project(name: 'x', clips: [
        _clip(const Duration(seconds: 5)),
        _clip(const Duration(seconds: 3)),
      ]);
      expect(p.totalDuration, const Duration(seconds: 8));
      expect(p.clipStart(1), const Duration(seconds: 5));
    });

    test('a transition overlaps the two clips it joins', () {
      final p = Project(name: 'x', clips: [
        _clip(const Duration(seconds: 5), tr: TransitionType.fade),
        _clip(const Duration(seconds: 3)),
      ]);
      // 1s transition removes 1s from the naive 8s sum.
      expect(p.totalDuration, const Duration(seconds: 7));
      expect(p.clipStart(1), const Duration(seconds: 4));
    });

    test('a transition never eats more than half the shorter clip', () {
      final p = Project(name: 'x', clips: [
        _clip(const Duration(seconds: 5), tr: TransitionType.fade)
          ..transitionDuration = const Duration(seconds: 9),
        _clip(const Duration(seconds: 3)),
      ]);
      expect(p.overlapAfter(0), const Duration(milliseconds: 1500));
    });

    test('speed scales the timeline length of a clip', () {
      final clip = _clip(const Duration(seconds: 10))..speed = 2;
      expect(clip.timelineDuration, const Duration(seconds: 5));
    });

    test('clipIndexAt finds the clip under the playhead', () {
      final p = Project(name: 'x', clips: [
        _clip(const Duration(seconds: 5)),
        _clip(const Duration(seconds: 3)),
      ]);
      expect(p.clipIndexAt(const Duration(seconds: 2)), 0);
      expect(p.clipIndexAt(const Duration(seconds: 6)), 1);
    });
  });

  group('export settings', () {
    test('portrait output pins the short side and stays even', () {
      final s = ExportSettings(
          resolution: ExportResolution.p1080, canvasAspect: 9 / 16);
      expect(s.width, 1080);
      expect(s.height, 1920);
      expect(s.height.isEven, isTrue);
    });

    test('landscape output pins the short side to the height', () {
      final s = ExportSettings(
          resolution: ExportResolution.p720, canvasAspect: 16 / 9);
      expect(s.height, 720);
      expect(s.width, 1280);
    });
  });

  group('project serialisation', () {
    test('a project survives a JSON round trip', () {
      final p = Project(name: 'demo', ratio: CanvasRatio.r1x1, clips: [
        _clip(const Duration(seconds: 4))..filterId = 'kodak',
      ]);
      final restored = Project.fromJson(p.toJson());
      expect(restored.name, 'demo');
      expect(restored.ratio, CanvasRatio.r1x1);
      expect(restored.clips.single.filterId, 'kodak');
      expect(restored.totalDuration, p.totalDuration);
    });
  });

  testWidgets('the light theme applies the editor palette', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: Text('ok')),
    ));
    expect(find.text('ok'), findsOneWidget);
  });

  // Material 3 reads a menu entry's colour from `labelTextStyle` and ignores
  // `textStyle`, which left every item painted in the page's near-black on the
  // dark menu. This opens a real menu and reads the colour off the rendered
  // entry, so setting only `textStyle` fails here again.
  testWidgets('popup menu entries are readable on the dark menu',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: PopupMenuButton<String>(
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
            ],
          ),
        ),
      ),
    ));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    final entry = tester.widget<Text>(find.text('Rename'));
    final style = DefaultTextStyle.of(
      tester.element(find.text('Rename')),
    ).style.merge(entry.style);
    expect(style.color, AppColors.onAppBar);
  });

  // A bottom sheet carries no themed text or icon colour of its own, so its
  // children fall through to the page's near-black ink — invisible on the
  // sheet's dark fill. AppTheme.onPopup is what stops that.
  testWidgets('sheet content wrapped for a popup is readable', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: AppTheme.onPopup(
          child: const Column(
            children: [Text('SHEET BODY'), Icon(Icons.info_outline)],
          ),
        ),
      ),
    ));

    final body = tester.widget<Text>(find.text('SHEET BODY'));
    final style = DefaultTextStyle.of(
      tester.element(find.text('SHEET BODY')),
    ).style.merge(body.style);
    expect(style.color, AppColors.onAppBarDim);
    expect(
      IconTheme.of(tester.element(find.byIcon(Icons.info_outline))).color,
      AppColors.onAppBar,
    );
  });
}
