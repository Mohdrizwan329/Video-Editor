import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/core/utils/responsive.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/state/editor_controller.dart';
import 'package:video_editor/state/projects_controller.dart';
import 'package:video_editor/ui/editor/editor_screen.dart';
import 'package:video_editor/ui/editor/preview/preview_stage.dart';
import 'package:video_editor/ui/editor/toolbar/editor_toolbar.dart';

/// A panel edits the *selected* clip while the canvas only ever draws the clip
/// under the *playhead*, and the playhead is fixed at the centre of the
/// timeline — so scrolling the track away from the selection is enough to put
/// the two on different clips. Every slider in the panel then changes a clip
/// that is nowhere on screen, which is indistinguishable from a dead panel.
void main() {
  const phone = Size(390, 844);

  Project projectWithClips() => Project(
    name: 'Clip project',
    ratio: CanvasRatio.r9x16,
    clips: [
      for (var i = 0; i < 3; i++)
        VideoClip(
          path: '/nonexistent/clip$i.jpg',
          isImage: true,
          sourceDuration: const Duration(seconds: 4),
        ),
    ],
  );

  Widget host(Widget child) => ChangeNotifierProvider(
    create: (_) => ProjectsController(),
    child: MaterialApp(
      theme: AppTheme.light,
      scrollBehavior: const AppScrollBehavior(),
      home: child,
    ),
  );

  /// The toolbar is a lazily-built strip, so a tool far along it has to be
  /// scrolled into view before it can be tapped.
  Future<void> tapTool(WidgetTester tester, String label) async {
    final button = find.text(label);
    if (button.evaluate().isEmpty) {
      await tester.dragUntilVisible(
        button,
        find.byType(EditorToolbar),
        const Offset(-120, 0),
        maxIteration: 40,
      );
    }
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }

  EditorController editorOf(WidgetTester tester) => Provider.of<EditorController>(
    tester.element(find.byType(PreviewStage).first),
    listen: false,
  );

  /// The clip the preview is drawing.
  int shownClip(EditorController editor) =>
      editor.project.clipIndexAt(editor.position.value);

  Future<EditorController> openEditor(WidgetTester tester) async {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(EditorScreen(project: projectWithClips())));
    await tester.pump(const Duration(milliseconds: 300));
    return editorOf(tester);
  }

  testWidgets('opening a clip tool puts the preview on the clip it edits',
      (tester) async {
    final editor = await openEditor(tester);
    editor.selectClip(0);
    editor.seek(const Duration(seconds: 9)); // inside the third clip
    await tester.pump(const Duration(milliseconds: 300));
    expect(shownClip(editor), 2, reason: 'the test itself set this up wrong');

    await tapTool(tester, 'Crop');

    expect(editor.selectedClipIndex, 0);
    expect(shownClip(editor), 0);
  });

  testWidgets('picking another clip with the tool open brings the preview along',
      (tester) async {
    final editor = await openEditor(tester);
    editor.selectClip(0);
    await tester.pump(const Duration(milliseconds: 300));
    await tapTool(tester, 'Crop');
    expect(shownClip(editor), 0);

    editor.selectClip(2);
    await tester.pump(const Duration(milliseconds: 300));

    expect(shownClip(editor), 2);
  });

  testWidgets('a slider drag does not move the playhead off the clip',
      (tester) async {
    final editor = await openEditor(tester);
    editor.selectClip(2);
    await tester.pump(const Duration(milliseconds: 300));
    await tapTool(tester, 'Crop');
    final at = editor.position.value;

    // What a drag does, frame by frame: notify on every step.
    for (var i = 1; i <= 5; i++) {
      editor.updateClip(2, (c) => c.scale = 1 + i / 10, record: false);
      await tester.pump();
    }

    expect(editor.position.value, at);
    expect(editor.project.clips[2].scale, closeTo(1.5, 0.001));
  });
}
