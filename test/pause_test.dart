import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/editor_tools.dart';
import 'package:provider/provider.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/core/utils/responsive.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/state/editor_controller.dart';
import 'package:video_editor/state/preview_engine.dart';
import 'package:video_editor/state/projects_controller.dart';
import 'package:video_editor/ui/editor/editor_screen.dart';
import 'package:video_editor/ui/editor/preview/preview_stage.dart';
import 'package:video_editor/ui/editor/timeline/clip_strip.dart';

/// Pause has to stop the transport, not just the icon. Every one of these
/// went wrong the same way: the flag said paused while the clock kept
/// running, so the playhead carried on and the button lied.
void main() {
  const phone = Size(390, 844);

  Project project() => Project(
    name: 'Pause',
    ratio: CanvasRatio.r9x16,
    clips: [
      for (var i = 0; i < 2; i++)
        VideoClip(
          path: '/nonexistent/c$i.jpg',
          isImage: true,
          sourceDuration: const Duration(seconds: 4),
        ),
    ],
  );

  Future<(EditorController, PreviewEngine)> open(WidgetTester tester) async {
    tester.view.physicalSize = phone * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ProjectsController(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          scrollBehavior: const AppScrollBehavior(),
          home: EditorScreen(project: project()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final element = tester.element(find.byType(PreviewStage).first);
    return (
      Provider.of<EditorController>(element, listen: false),
      Provider.of<PreviewEngine>(element, listen: false),
    );
  }

  testWidgets('the play button stops the clock, not just the icon', (
    tester,
  ) async {
    final (editor, engine) = await open(tester);

    await engine.play();
    await tester.pump(const Duration(milliseconds: 300));
    expect(editor.isPlaying.value, isTrue);

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump(const Duration(milliseconds: 200));
    expect(editor.isPlaying.value, isFalse);

    final parked = editor.position.value;
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      editor.position.value,
      parked,
      reason: 'the playhead kept moving after pause',
    );
  });

  testWidgets('a tap on the canvas plays and pauses', (tester) async {
    final (editor, _) = await open(tester);

    await tester.tap(find.byType(PreviewStage).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      editor.isPlaying.value,
      isTrue,
      reason: 'tapping the canvas did not start playback',
    );

    await tester.tap(find.byType(PreviewStage).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      editor.isPlaying.value,
      isFalse,
      reason: 'tapping the canvas did not stop playback',
    );
  });

  testWidgets('taking hold of the timeline stops playback for real', (
    tester,
  ) async {
    final (editor, engine) = await open(tester);

    await engine.play();
    await tester.pump(const Duration(milliseconds: 300));
    expect(editor.isPlaying.value, isTrue);

    // Drag the track: the user saying "put the playhead here". The strip runs
    // off both edges of the window, so grab a point that is actually on
    // screen — its centre is not.
    final strip = tester.getRect(find.byType(ClipStrip).first);
    final grab = strip.intersect(Offset.zero & phone).center;
    await tester.dragFrom(grab, const Offset(-40, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      editor.isPlaying.value,
      isFalse,
      reason: 'a finger on the timeline did not stop playback',
    );

    final parked = editor.position.value;
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      editor.position.value,
      parked,
      reason: 'scrubbing left the clock running behind the paused icon',
    );
  });

  testWidgets('the timeline following the playhead does not stop playback', (
    tester,
  ) async {
    final (editor, engine) = await open(tester);

    await engine.play();
    // Long enough for the track to have scrolled itself along under the
    // playhead several times — the scroll that used to read as the user
    // grabbing the timeline.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      editor.isPlaying.value,
      isTrue,
      reason: 'the timeline auto-follow paused playback',
    );
    expect(editor.position.value, greaterThan(Duration.zero));
  });

  testWidgets('a tool tap while playing pauses first', (tester) async {
    final (editor, engine) = await open(tester);

    await engine.play();
    await tester.pump(const Duration(milliseconds: 300));
    expect(editor.isPlaying.value, isTrue);

    await tapEditorTool(tester, 'Crop');
    await tester.pump(const Duration(milliseconds: 400));
    expect(editor.isPlaying.value, isFalse);
  });
}
