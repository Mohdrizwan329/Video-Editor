import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/core/utils/responsive.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/data/models/watermark.dart';
import 'package:video_editor/state/projects_controller.dart';
import 'package:video_editor/ui/editor/editor_screen.dart';

import 'helpers/editor_tools.dart';

Widget _host(Widget child) => ChangeNotifierProvider(
  create: (_) => ProjectsController(),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    scrollBehavior: const AppScrollBehavior(),
    home: child,
  ),
);

Project _project({Watermark? mark}) {
  final p = Project(
    name: 'Mark',
    clips: [
      VideoClip(
        path: '/nonexistent/clip.jpg',
        isImage: true,
        sourceDuration: const Duration(seconds: 4),
      ),
    ],
  );
  if (mark != null) p.watermark = mark;
  return p;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
}

void main() {
  group('the watermark caption', () {
    testWidgets('lands on the project and on the canvas as it is typed', (
      tester,
    ) async {
      _phone(tester);
      final project = _project();
      await tester.pumpWidget(_host(EditorScreen(project: project)));
      await tester.pump(const Duration(milliseconds: 300));

      await tapEditorTool(tester, 'Watermark');
      await tester.pump(const Duration(milliseconds: 400));

      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Saleem');
      await tester.pump(const Duration(milliseconds: 300));

      expect(project.watermark.text, 'Saleem');
      // Typing is what turns the mark on, so it has to be on the canvas now —
      // the field and the panel both show it, hence three.
      expect(project.watermark.enabled, isTrue);
      expect(find.text('Saleem'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('the watermark on the canvas', () {
    testWidgets('cannot be dragged out of the frame', (tester) async {
      _phone(tester);
      final project = _project(mark: Watermark(enabled: true, text: 'Saleem'));
      await tester.pumpWidget(_host(EditorScreen(project: project)));
      await tester.pump(const Duration(milliseconds: 300));

      await tapEditorTool(tester, 'Watermark');
      await tester.pump(const Duration(milliseconds: 400));

      // A long drag towards the top left, well past the corner.
      final mark = find.text('Saleem').first;
      await tester.dragFrom(tester.getCenter(mark), const Offset(-900, -1600));
      await tester.pump(const Duration(milliseconds: 300));

      final t = project.watermark.transform;
      expect(
        t.x,
        inInclusiveRange(0, 1),
        reason: 'the mark was dragged off the side of the canvas',
      );
      expect(
        t.y,
        inInclusiveRange(0, 1),
        reason: 'the mark was dragged off the top of the canvas',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens its panel when tapped', (tester) async {
      _phone(tester);
      final project = _project(
        mark: Watermark(enabled: true, text: 'Saleem')
          ..applyAnchor(WatermarkAnchor.center),
      );
      await tester.pumpWidget(_host(EditorScreen(project: project)));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Watermark'),
        findsNothing,
        reason: 'the panel should be closed to begin with',
      );

      await tester.tap(find.text('Saleem').first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Watermark'),
        findsWidgets,
        reason: 'tapping the mark did not open its panel',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('a project saved with the mark off the canvas', () {
    test('has it pulled back into the frame when it loads', () {
      final saved = Watermark(enabled: true, text: 'Saleem').toJson()
        ..['tf'] = {'x': 0.64, 'y': -0.076, 's': 1.0, 'r': 0.0, 'o': 0.75};

      final loaded = Watermark.fromJson(saved);

      expect(loaded.transform.y, 0.0);
      expect(loaded.transform.x, 0.64);
    });
  });
}
