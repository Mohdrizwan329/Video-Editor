import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/core/utils/responsive.dart';
import 'package:video_editor/data/models/adjustments.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/state/editor_controller.dart';
import 'package:video_editor/state/projects_controller.dart';
import 'package:video_editor/ui/editor/editor_screen.dart';
import 'package:video_editor/ui/editor/preview/clip_view.dart';
import 'package:video_editor/ui/editor/preview/grade_extras_box.dart';
import 'package:video_editor/ui/editor/preview/preview_stage.dart';
import 'package:video_editor/ui/editor/preview/transition_view.dart';

/// Every control in the bottom sheets is judged against the canvas. A value
/// the exporter honours but the preview drops is a slider that looks dead,
/// however correct the rendered file turns out to be — so the two have to
/// stay in step.
void main() {
  group('the fade sliders reach the picture', () {
    VideoClip clip() => VideoClip(
      path: '/nonexistent/a.jpg',
      isImage: true,
      sourceDuration: const Duration(seconds: 4),
      fadeIn: const Duration(seconds: 1),
      fadeOut: const Duration(seconds: 1),
    );

    test('fades up from black and back down to it', () {
      final c = clip();
      expect(c.fadeGainAt(Duration.zero), 0);
      expect(c.fadeGainAt(const Duration(milliseconds: 500)), closeTo(0.5, 0.01));
      expect(c.fadeGainAt(const Duration(seconds: 2)), 1);
      expect(c.fadeGainAt(const Duration(milliseconds: 3500)),
          closeTo(0.5, 0.01));
      expect(c.fadeGainAt(const Duration(seconds: 4)), 0);
    });

    test('a clip with no fades is never veiled', () {
      final c = VideoClip(
        path: '/nonexistent/a.jpg',
        isImage: true,
        sourceDuration: const Duration(seconds: 4),
      );
      for (final ms in [0, 1, 2000, 3999, 4000]) {
        expect(c.fadeGainAt(Duration(milliseconds: ms)), 1);
      }
    });
  });

  testWidgets('the fade veils the canvas, bars and all', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final project = Project(
      name: 'Fade',
      ratio: CanvasRatio.r9x16,
      clips: [
        VideoClip(
          path: '/nonexistent/a.jpg',
          isImage: true,
          sourceDuration: const Duration(seconds: 4),
          fadeIn: const Duration(seconds: 1),
        ),
      ],
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ProjectsController(),
        child: MaterialApp(
          theme: AppTheme.light,
          scrollBehavior: const AppScrollBehavior(),
          home: EditorScreen(project: project),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final editor = Provider.of<EditorController>(
      tester.element(find.byType(PreviewStage).first),
      listen: false,
    );

    /// How black the canvas is veiled, 0 when there is no veil at all.
    double veil() {
      final found = tester.widgetList<FadeVeil>(find.byType(FadeVeil));
      return found.isEmpty ? 0 : 1 - found.first.gain;
    }

    editor.seek(Duration.zero);
    await tester.pump(const Duration(milliseconds: 100));
    expect(veil(), closeTo(1, 0.02), reason: 'the first frame is black');

    editor.seek(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));
    expect(veil(), closeTo(0.5, 0.05));

    editor.seek(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(veil(), 0, reason: 'past the fade there is nothing to veil');
  });

  group('the adjustments a colour matrix cannot carry', () {
    test('are the ones that ask for the shader pass', () {
      expect(GradeExtrasBox.wanted(Adjustments(), 1), isFalse);
      // Brightness is a matrix value: it needs no second pass.
      expect(GradeExtrasBox.wanted(Adjustments(brightness: 0.5), 1), isFalse);
      for (final a in [
        Adjustments(sharpen: 0.4),
        Adjustments(grain: 0.4),
        Adjustments(denoise: 0.4),
        Adjustments(curveMid: 0.4),
      ]) {
        expect(GradeExtrasBox.wanted(a, 1), isTrue);
      }
      // A preset's gamma is the one grade value the matrix drops too.
      expect(GradeExtrasBox.wanted(Adjustments(), 0.9), isTrue);
    });

    test('the shader and FFmpeg read the same curve points', () {
      final a = Adjustments(curveLow: 0.8, curveMid: -0.4, curveHigh: -0.6);
      final (lo, mid, hi) = a.curvePoints;
      expect(
        a.curveExpression,
        '0/${lo.toStringAsFixed(3)}'
        ' 0.5/${mid.toStringAsFixed(3)}'
        ' 1/${hi.toStringAsFixed(3)}',
      );
      // Monotone and inside the range the filter accepts.
      expect(lo, inInclusiveRange(0.0, 0.4));
      expect(mid, inInclusiveRange(0.1, 0.9));
      expect(hi, inInclusiveRange(0.5, 1.0));
    });
  });

  group('a transition shows on the canvas', () {
    const phone = Size(390, 844);

    Project twoClips({TransitionType transition = TransitionType.fade}) {
      final clips = [
        for (var i = 0; i < 2; i++)
          VideoClip(
            path: '/nonexistent/clip$i.jpg',
            isImage: true,
            sourceDuration: const Duration(seconds: 4),
          ),
      ];
      clips.first
        ..transitionType = transition
        ..transitionDuration = const Duration(milliseconds: 600);
      return Project(
        name: 'Join',
        ratio: CanvasRatio.r9x16,
        clips: clips,
      );
    }

    Future<EditorController> open(WidgetTester tester, Project project) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ProjectsController(),
          child: MaterialApp(
            theme: AppTheme.light,
            scrollBehavior: const AppScrollBehavior(),
            home: EditorScreen(project: project),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      return Provider.of<EditorController>(
        tester.element(find.byType(PreviewStage).first),
        listen: false,
      );
    }

    testWidgets('both clips are on screen inside the overlap', (tester) async {
      final project = twoClips();
      final editor = await open(tester, project);

      // Mid-clip: one clip, no transition.
      editor.seek(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(TransitionView), findsNothing);

      // The overlap sits at the end of the first clip.
      final overlap = project.overlapAfter(0);
      expect(overlap, greaterThan(Duration.zero));
      editor.seek(project.clipStart(1) + overlap ~/ 2);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(TransitionView), findsOneWidget);
      // The outgoing clip and the incoming one, composited together.
      expect(
        find.descendant(
          of: find.byType(TransitionView),
          matching: find.byType(ClipView),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('a cut with no transition composites nothing', (tester) async {
      final project = twoClips(transition: TransitionType.none);
      final editor = await open(tester, project);
      editor.seek(project.clipStart(1) - const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(TransitionView), findsNothing);
    });

    testWidgets('every transition in the library renders', (tester) async {
      // A look with no case of its own would throw on the switch rather than
      // quietly falling back, so this is the guard for the whole library.
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final type in TransitionType.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 200,
              height: 300,
              child: TransitionView(
                type: type,
                progress: 0.5,
                outgoing: const ColoredBox(color: Colors.red),
                incoming: const ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '${type.name} threw');
      }
    });
  });
}
