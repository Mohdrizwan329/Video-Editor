import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/core/utils/responsive.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/state/projects_controller.dart';
import 'package:video_editor/ui/editor/editor_screen.dart';
import 'package:video_editor/ui/export/export_screen.dart';
import 'package:video_editor/ui/image_editor/image_editor_screen.dart';
import 'package:video_editor/ui/widgets/panel_shell.dart';
import 'package:video_editor/ui/editor/toolbar/editor_toolbar.dart';
import 'helpers/editor_tools.dart';

/// A sheet shows what it has room for and names the way to the rest.
///
/// Nothing in one scrolls — not the sheet, not a row of presets inside it.
/// A row that slides sideways gives no sign of how much is off the edge, and
/// a sheet that slides under a finger hides how much of the tool is left; in
/// both cases the user is left guessing at a gesture. What does not fit goes
/// behind a button that says so, in a sheet that shows it all at once.
void main() {
  Project project() => Project(
    name: 'Sheets',
    ratio: CanvasRatio.r9x16,
    clips: [
      VideoClip(
        path: '/nonexistent/c.jpg',
        isImage: true,
        sourceDuration: const Duration(seconds: 4),
      ),
    ],
  );

  Future<void> openEditor(WidgetTester tester) async {
    tester.view.physicalSize =
        const Size(390, 844) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ProjectsController(),
        child: MaterialApp(
          theme: AppTheme.light,
          scrollBehavior: const AppScrollBehavior(),
          home: EditorScreen(project: project()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Every scroll view inside the sheet that belongs to the layout, which is
  /// where a row that still slides would be hiding.
  ///
  /// A text field brings a scroll view of its own for the caret to run in.
  /// That one is the field's business, not the sheet's.
  Iterable<ScrollableState> scrollersIn(WidgetTester tester, Finder of) =>
      tester
          .stateList<ScrollableState>(
            find.descendant(
              of: of,
              matching: find.byType(Scrollable),
              matchRoot: false,
            ),
          )
          .where(
            (s) => find
                .ancestor(
                  of: find.byWidget(s.widget),
                  matching: find.byType(EditableText),
                )
                .evaluate()
                .isEmpty,
          );

  for (final tool in const [
    'Filter',
    'Effect',
    'Sticker',
    'Canvas',
    'Speed',
    'Watermark',
    'Animation',
    'Voice Effect',
  ]) {
    testWidgets('$tool does not slide in any direction', (tester) async {
      await openEditor(tester);
      await tapEditorTool(tester, tool);
      await tester.pump(const Duration(milliseconds: 400));
      if (find.byType(PanelShell).evaluate().isEmpty) return;

      for (final scroller in scrollersIn(tester, find.byType(PanelShell))) {
        // The shell's own viewport is there to measure and to clip; it
        // refuses the gesture. Anything else with a scroll extent is a row
        // that still slides.
        expect(
          scroller.position.physics,
          isA<NeverScrollableScrollPhysics>(),
          reason: '$tool has a scroll view that takes a drag',
        );
      }
    });
  }

  testWidgets('a tool the sheet cannot hold names the way to the rest', (
    tester,
  ) async {
    await openEditor(tester);
    await tapEditorTool(tester, 'Filter');
    await tester.pump(const Duration(milliseconds: 400));

    // The library runs to a hundred looks; no sheet holds it.
    expect(find.text('More options'), findsOneWidget);

    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();

    // And that sheet *is* a list: the user asked for it by name, so its
    // scroll bar is a list's rather than a panel quietly hiding itself.
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('the sheet keeps the height it opened at', (tester) async {
    await openEditor(tester);
    await tapEditorTool(tester, 'Canvas');
    await tester.pump(const Duration(milliseconds: 400));
    final opened = tester.getSize(find.byType(PanelShell).first).height;

    final sheet = tester.getRect(find.byType(PanelShell).first);
    await tester.dragFrom(
      Offset(sheet.center.dx, sheet.top + PanelShell.kHandleHeight / 2),
      const Offset(0, -200),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(PanelShell).first).height, opened);
  });

  testWidgets('the toolbar itself still slides — it is not a sheet', (
    tester,
  ) async {
    // The rule is about sheets. The tool bar is a strip of twenty-nine tools
    // along the bottom of the editor, and it has always slid.
    await openEditor(tester);
    expect(scrollersIn(tester, find.byType(EditorToolbar)).isNotEmpty, isTrue);
  });

  testWidgets('Switch re-orders down the sheet rather than across it', (
    tester,
  ) async {
    await openEditor(tester);
    await tapEditorTool(tester, 'Switch');
    await tester.pump(const Duration(milliseconds: 400));
    if (find.byType(PanelShell).evaluate().isEmpty) return;

    // A drag-to-reorder list is still a list, but it does not slide: the
    // clips past the fold are behind the button, where the whole track is
    // laid out and every one of them can still be dragged.
    for (final scroller in scrollersIn(tester, find.byType(PanelShell))) {
      expect(scroller.position.physics, isA<NeverScrollableScrollPhysics>());
    }
  });

  testWidgets('the photo editor panel does not slide either', (tester) async {
    tester.view.physicalSize =
        const Size(390, 844) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: ImageEditorScreen(path: '/nonexistent.jpg')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Its tool bar slides, the way the editor's does — it is a strip of
    // tools, not a panel. The panel above it must not.
    final panel = find.byKey(const ValueKey('photo-panel'));
    expect(panel, findsOneWidget);
    for (final scroller in scrollersIn(tester, panel)) {
      expect(scroller.position.physics, isA<NeverScrollableScrollPhysics>());
    }
  });

  testWidgets('a photo tool too long for the panel names the way to the rest', (
    tester,
  ) async {
    tester.view.physicalSize =
        const Size(390, 844) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: ImageEditorScreen(path: '/nonexistent.jpg')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // The tool bar is a strip; the tool has to be brought into view first.
    await tester.ensureVisible(find.text('Watermark').last);
    await tester.pump();
    await tester.tap(find.text('Watermark').last);
    await tester.pump(const Duration(milliseconds: 400));
    // The overflow is measured after the frame that laid the panel out, so
    // the button lands on the frame after that.
    await tester.pump();

    expect(find.text('More options'), findsOneWidget);
  });

  testWidgets('the export screen pins its button and hides no dial', (
    tester,
  ) async {
    tester.view.physicalSize =
        const Size(390, 844) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        scrollBehavior: const AppScrollBehavior(),
        home: ExportScreen(project: project()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // The thing the screen is for is on it, not below a scroll.
    expect(find.text('Start export').hitTestable(), findsOneWidget);
    for (final scroller in scrollersIn(tester, find.byType(ExportScreen))) {
      expect(scroller.position.physics, isA<NeverScrollableScrollPhysics>());
    }

    // And every dial is reachable, including the two the screen also shows.
    await tester.tap(find.text('More settings'));
    await tester.pumpAndSettle();
    for (final dial in const [
      'Format',
      'Resolution',
      'Frame rate',
      'Quality',
    ]) {
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(dial),
        ),
        findsOneWidget,
        reason: '$dial is not in the sheet the button opens',
      );
    }
  });
}
