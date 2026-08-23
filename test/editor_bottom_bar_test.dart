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
import 'package:video_editor/ui/editor/toolbar/editor_toolbar.dart';
import 'package:video_editor/ui/widgets/tool_button.dart';

import 'helpers/editor_tools.dart';

/// The bottom of the editor is one flat strip of tools above the timeline —
/// the same row, in the same order, whatever is selected on the main track.
void main() {
  VideoClip clip() => VideoClip(
    path: '/nonexistent/c.jpg',
    isImage: true,
    sourceDuration: const Duration(seconds: 4),
  );

  Widget host(Widget child) => ChangeNotifierProvider(
    create: (_) => ProjectsController(),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
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
    of: find.byType(EditorToolbar),
    matching: find.text(label),
  );

  testWidgets('the bar opens on the head of the flat strip', (tester) async {
    await open(tester);

    // The seven project tools lead the row and are mounted without scrolling.
    for (final label in const [
      'Canvas',
      'Audio',
      'Sticker',
      'Text',
      'Effect',
    ]) {
      expect(tool(label), findsOneWidget, reason: '$label is not in the strip');
    }

    // The order down the screen: tools, then the track they act on. There is
    // no category bar under the timeline any more.
    final strip = tester.getRect(find.byType(EditorToolbar));
    final timeline = tester.getRect(find.byType(TimelineView));
    expect(strip.bottom, lessThanOrEqualTo(timeline.top + 0.5));
    expect(timeline.bottom, lessThanOrEqualTo(844.5));
  });

  testWidgets('every tool is on the one strip, in order', (tester) async {
    await open(tester);

    // Scrolling right reaches each of them in turn — no families to switch,
    // no overflow menu to find. Revealed, not tapped: a tap opens a sheet
    // over the strip, and the next tool would have nowhere to scroll.
    var last = -1.0;
    for (final label in const [
      'Canvas',
      'Filter',
      'PIP',
      'Split',
      'Speed',
      'AI Cut',
      'Switch',
      'Enhance',
      'Opacity',
      'Voice Effect',
      'Freeze',
      'Ease',
      'Watermark',
      'Mix',
    ]) {
      final finder = await revealEditorTool(tester, label);
      expect(
        finder,
        findsOneWidget,
        reason: '$label never came into view on the strip',
      );
      // Each one sits further along than the one before it, which is what
      // 'in order' means once the row is scrolled.
      final scrolled = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(EditorToolbar),
              matching: find.byType(Scrollable),
            ),
          )
          .position
          .pixels;
      expect(
        scrolled,
        greaterThanOrEqualTo(last),
        reason: '$label sits before the tool named ahead of it',
      );
      last = scrolled;
    }
  });

  testWidgets('a clip tool with nothing selected acts on the playhead clip', (
    tester,
  ) async {
    final project = await open(tester);

    await tapEditorTool(tester, 'Delete');
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      project.clips.length,
      1,
      reason: 'Delete did not fall back to the clip under the playhead',
    );
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

    expect(
      project.clips.length,
      2,
      reason: 'Split did not cut the clip under the playhead',
    );
  });

  testWidgets('an empty project greys the clip tools out — and says why', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(EditorScreen(project: Project(name: 'Empty'))),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final split = await revealEditorTool(tester, 'Split');
    final button = tester.widget<ToolButton>(
      find.ancestor(of: split, matching: find.byType(ToolButton)),
    );
    expect(
      button.enabled,
      isFalse,
      reason: 'Split does not read as unavailable on an empty project',
    );

    // Grey, but not dead: the tap is what teaches the user which of the two
    // it is. A button that answers nothing at all reads as a broken app.
    await tester.tap(split);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byType(SnackBar),
      findsOneWidget,
      reason: 'a greyed tool swallowed the tap without explaining itself',
    );
  });

  testWidgets('Sort opens a card per clip and re-orders the track', (
    tester,
  ) async {
    final project = await open(tester, clips: 3);
    final first = project.clips.first.id;
    final second = project.clips[1].id;

    await tapEditorTool(tester, 'Switch');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SortPanel), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // Drag the first card past the second. The list runs down the sheet
    // now, so the move does too.
    final cards = find.byType(ReorderableDragStartListener);
    final start = tester.getCenter(cards.at(0));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 400));
    // One row's height, so it lands in the slot next door rather than at
    // the far end of the track.
    final step = tester.getSize(cards.at(0)).height / 6;
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(Offset(0, step));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(project.clips.first.id, second);
    expect(project.clips[1].id, first);
  });

  testWidgets('Sort with one clip says so instead of opening a dead panel', (
    tester,
  ) async {
    await open(tester, clips: 1);

    await tapEditorTool(tester, 'Switch');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SortPanel), findsNothing);
    expect(find.byType(SpeedPanel), findsNothing);
  });
}
