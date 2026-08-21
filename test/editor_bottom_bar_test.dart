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
import 'package:video_editor/ui/editor/panels/clip_panels.dart';
import 'package:video_editor/ui/editor/panels/sort_panel.dart';
import 'package:video_editor/ui/editor/preview/preview_stage.dart';
import 'package:video_editor/ui/editor/timeline/timeline_view.dart';
import 'package:video_editor/ui/editor/toolbar/category_bar.dart';
import 'package:video_editor/ui/editor/toolbar/editor_toolbar.dart';

import 'helpers/editor_tools.dart';

/// The bottom of the editor is two strips: the tools for the open category,
/// above the timeline, and the category bar itself along the very bottom.
void main() {
  VideoClip clip() => VideoClip(
        path: '/nonexistent/c.jpg',
        isImage: true,
        sourceDuration: const Duration(seconds: 4),
      );

  Widget host(Widget child) => ChangeNotifierProvider(
        create: (_) => ProjectsController(),
        child: MaterialApp(
          theme: AppTheme.light,
          scrollBehavior: const AppScrollBehavior(),
          home: child,
        ),
      );

  Future<Project> open(WidgetTester tester, {int clips = 2}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final project = Project(
      name: 'Bottom bar',
      ratio: CanvasRatio.r9x16,
      clips: [for (var i = 0; i < clips; i++) clip()],
    );
    await tester.pumpWidget(host(EditorScreen(project: project)));
    await tester.pump(const Duration(milliseconds: 300));
    return project;
  }

  /// A tool label as the strip — not the category bar — shows it.
  Finder tool(String label) => find.descendant(
      of: find.byType(EditorToolbar), matching: find.text(label));

  testWidgets('the bar opens on the clip tools from the screenshot',
      (tester) async {
    await open(tester);

    expect(find.byType(CategoryBar), findsOneWidget);
    for (final label in const [
      'Split',
      'Replace',
      'Delete',
      'Crop',
      'Change speed',
      'Sort',
    ]) {
      expect(tool(label), findsOneWidget, reason: '$label is not in the strip');
    }

    // The order down the screen: tools, then the track they act on, then the
    // bar that chose them.
    final strip = tester.getRect(find.byType(EditorToolbar));
    final timeline = tester.getRect(find.byType(TimelineView));
    final bar = tester.getRect(find.byType(CategoryBar));
    expect(strip.bottom, lessThanOrEqualTo(timeline.top + 0.5));
    expect(timeline.bottom, lessThanOrEqualTo(bar.top + 0.5));
    expect(bar.bottom, closeTo(844, 1));
  });

  testWidgets('each category swaps the strip for its own tools',
      (tester) async {
    await open(tester);

    await openToolCategory(tester, 'Audio');
    expect(tool('Audio'), findsOneWidget);
    expect(tool('Voice'), findsOneWidget);
    expect(tool('Split'), findsNothing);

    await openToolCategory(tester, 'Text');
    expect(tool('Text'), findsOneWidget);
    expect(tool('Captions'), findsOneWidget);

    await openToolCategory(tester, 'Filter');
    expect(tool('Filter'), findsOneWidget);
    expect(tool('Effects'), findsOneWidget);

    await openToolCategory(tester, 'Canvas');
    expect(tool('Canvas'), findsOneWidget);
    expect(tool('Watermark'), findsOneWidget);
  });

  testWidgets('a clip tool with nothing selected acts on the playhead clip',
      (tester) async {
    final project = await open(tester);

    await tapEditorTool(tester, 'Delete');
    await tester.pump(const Duration(milliseconds: 300));

    expect(project.clips.length, 1,
        reason: 'Delete did not fall back to the clip under the playhead');
  });

  testWidgets('Split cuts the clip the playhead is inside', (tester) async {
    final project = await open(tester, clips: 1);
    final editor = Provider.of<EditorController>(
      tester.element(find.byType(PreviewStage)),
      listen: false,
    );
    editor.seek(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));

    await tapEditorTool(tester, 'Split');
    await tester.pump(const Duration(milliseconds: 300));

    expect(project.clips.length, 2,
        reason: 'Split did not cut the clip under the playhead');
  });

  testWidgets('an empty project greys the clip tools out', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(EditorScreen(project: Project(name: 'Empty'))));
    await tester.pump(const Duration(milliseconds: 300));

    final split = tester.widget<InkWell>(find.ancestor(
      of: tool('Split'),
      matching: find.byType(InkWell),
    ));
    expect(split.onTap, isNull, reason: 'Split is live on an empty project');
  });

  testWidgets('Sort opens a card per clip and re-orders the track',
      (tester) async {
    final project = await open(tester, clips: 3);
    final first = project.clips.first.id;
    final second = project.clips[1].id;

    await tapEditorTool(tester, 'Sort');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SortPanel), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // Drag the first card past the second.
    final cards = find.byType(ReorderableDragStartListener);
    final start = tester.getCenter(cards.at(0));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 400));
    // One card's width — 64pt tile plus its 4pt margins — so it lands in
    // the slot next door rather than at the far end.
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(13, 0));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(project.clips.first.id, second);
    expect(project.clips[1].id, first);
  });

  testWidgets('Sort with one clip says so instead of opening a dead panel',
      (tester) async {
    await open(tester, clips: 1);

    await tapEditorTool(tester, 'Sort');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SortPanel), findsNothing);
    expect(find.byType(SpeedPanel), findsNothing);
  });
}
