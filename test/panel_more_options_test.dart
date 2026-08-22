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
import 'package:video_editor/ui/widgets/app_slider.dart';
import 'package:video_editor/ui/widgets/panel_shell.dart';
import 'helpers/editor_tools.dart';

/// A panel sheet shows what its height has room for and nothing more — the
/// body does not scroll. Everything past that fold is reached through the
/// 'More options' button, which opens the whole tool in a sheet of its own.
///
/// The controls in that second sheet are the panel's own, not a copy taken
/// when it opened: what they write and what they read back have to be the
/// same project the docked sheet is editing.
void main() {
  Project project() => Project(
        name: 'More',
        ratio: CanvasRatio.r9x16,
        clips: [
          VideoClip(
            path: '/nonexistent/c.jpg',
            isImage: true,
            sourceDuration: const Duration(seconds: 4),
          ),
        ],
      );

  /// The Watermark tool, which is the one whose controls still outrun a
  /// phone-sized sheet. Adjust used to be that tool — nineteen sliders in a
  /// stack — and is now one slider and a row of knobs, so it has nothing
  /// past its fold to test with.
  Future<Project> openAdjust(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    final p = project();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ProjectsController(),
        child: MaterialApp(
          theme: AppTheme.light,
          scrollBehavior: const AppScrollBehavior(),
          home: EditorScreen(project: p),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tapEditorTool(tester, 'Watermark');
    await tester.pump(const Duration(milliseconds: 400));
    return p;
  }

  /// The Slider inside the labelled control of the 'More options' sheet.
  /// The docked sheet keeps its own controls in the tree and clips the ones
  /// past its fold, so a control open in both matches twice.
  Finder sliderFor(String label) => find.descendant(
        of: find.byType(BottomSheet),
        matching: find.descendant(
          of: find.ancestor(
            of: find.text(label),
            matching: find.byType(AppSlider),
          ),
          matching: find.byType(Slider),
        ),
      );

  testWidgets('the sliders past the fold are behind the button',
      (tester) async {
    await openAdjust(tester);

    // Watermark's controls outrun the sheet: Size sits above the fold and
    // Opacity below it.
    expect(find.text('Size').hitTestable(), findsOneWidget);
    // Clipped, not absent: it is in the tree the sheet built and out of
    // reach behind its bottom edge.
    expect(find.text('Opacity').hitTestable(), findsNothing,
        reason: 'a control the sheet has no room for is reachable anyway');
    expect(find.text('More options'), findsOneWidget);

    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Opacity').hitTestable(), findsOneWidget,
        reason: 'the sheet the button opens is missing the controls it '
            'was opened for');
  });

  testWidgets('a slider in that sheet edits the project and shows it',
      (tester) async {
    final project = await openAdjust(tester);

    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();

    await tester.drag(sliderFor('Opacity'), const Offset(-60, 0));
    // Two frames: the panel writes the value on the first and the sheet
    // picks the rebuilt controls up on the next.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(project.watermark.transform.opacity, lessThan(0.75));
    // And the sheet is showing the value it just wrote — it renders the
    // panel as the panel now is, not as it was when the sheet opened.
    expect(tester.widget<Slider>(sliderFor('Opacity')).value, lessThan(1));
  });

  testWidgets('closing that sheet leaves the panel open behind it',
      (tester) async {
    await openAdjust(tester);

    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.byType(PanelShell), findsOneWidget);
    expect(find.text('Size').hitTestable(), findsOneWidget);
  });
}
