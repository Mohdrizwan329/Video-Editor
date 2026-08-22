import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:video_editor/core/theme/app_colors.dart';
import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/state/projects_controller.dart';
import 'package:video_editor/ui/editor/editor_screen.dart';
import 'package:video_editor/ui/widgets/panel_shell.dart';
import 'helpers/editor_tools.dart';

/// A sheet's rounded top corners cut two notches out of it, and what belongs
/// behind them is whatever strip the sheet is docked under. Getting that
/// wrong is what leaves two coloured shoulders sticking out past the corners.
///
/// This lives in a file of its own: raising the keyboard on the editor is a
/// whole-screen relayout, and running it alongside the window sweeps in
/// responsive_layout_test.dart changed what those sweeps measured.
void main() {
  Iterable<Color> behindTheSheet(WidgetTester tester) => tester
      .widgetList<ColoredBox>(
        find.ancestor(
          of: find.byType(PanelShell),
          matching: find.byType(ColoredBox),
        ),
      )
      .map((b) => b.color);

  Future<void> openWatermark(
    WidgetTester tester, {
    double keyboard = 0,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ProjectsController(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewInsets: EdgeInsets.only(bottom: keyboard),
              ),
              child: EditorScreen(
                project: Project(name: 'p', ratio: CanvasRatio.r9x16),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tapEditorTool(tester, 'Watermark');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PanelShell), findsWidgets);
  }

  testWidgets('a docked sheet shows the timeline through its corners',
      (tester) async {
    await openWatermark(tester);
    expect(behindTheSheet(tester), contains(AppColors.timelineBg));
  });

  testWidgets('with the keyboard up it shows the page it is docked under',
      (tester) async {
    // The keyboard takes the timeline away and moves the sheet under the
    // preview, so the timeline's colour would show as two lavender shoulders.
    await openWatermark(tester, keyboard: 320);
    expect(behindTheSheet(tester), contains(AppColors.surface));
    expect(behindTheSheet(tester), isNot(contains(AppColors.timelineBg)));
  });
}
