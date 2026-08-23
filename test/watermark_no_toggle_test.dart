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

Future<void> _openPanel(WidgetTester tester, Project project) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(EditorScreen(project: project)));
  await tester.pump(const Duration(milliseconds: 300));
  await tapEditorTool(tester, 'Watermark');
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('the watermark panel without a switch', () {
    testWidgets('offers no on/off control at all', (tester) async {
      final project = _project();
      await _openPanel(tester, project);

      expect(find.byType(Switch), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens on an empty caption so nothing is on by surprise', (
      tester,
    ) async {
      final project = _project();
      await _openPanel(tester, project);

      // Merely reaching for the tool must not brand the video: the box is
      // empty, the mark is off, and the canvas is untouched.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(project.watermark.enabled, isFalse);
      expect(project.watermark.isReady, isFalse);
    });

    testWidgets('the caption is the switch, in both directions', (
      tester,
    ) async {
      final project = _project();
      await _openPanel(tester, project);

      await tester.enterText(find.byType(TextField), 'Saleem');
      await tester.pump(const Duration(milliseconds: 300));
      expect(project.watermark.enabled, isTrue);
      expect(project.watermark.isReady, isTrue);
      expect(find.text('Saleem'), findsWidgets);

      // Clearing it is how the mark comes off now that there is no switch.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 300));
      expect(project.watermark.enabled, isFalse);
      expect(project.watermark.isReady, isFalse);
    });

    testWidgets('switching to Logo with no logo picked leaves the mark off', (
      tester,
    ) async {
      final project = _project();
      await _openPanel(tester, project);

      await tester.enterText(find.byType(TextField), 'Saleem');
      await tester.pump(const Duration(milliseconds: 300));
      expect(project.watermark.enabled, isTrue);

      await tester.tap(find.text('Logo'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(project.watermark.type, WatermarkType.image);
      expect(
        project.watermark.enabled,
        isFalse,
        reason: 'there is no logo behind it yet',
      );

      // Going back to Text finds the caption still there and lights it again.
      await tester.tap(find.text('Text'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(project.watermark.enabled, isTrue);
      expect(project.watermark.text, 'Saleem');
    });

    testWidgets('a mark that was already on keeps its caption', (tester) async {
      final project = _project(mark: Watermark(enabled: true, text: 'Saleem'));
      await _openPanel(tester, project);

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Saleem',
      );
      expect(project.watermark.enabled, isTrue);
    });
  });

  _defaults();
}

// ---------------------------------------------------------------- defaults

void _defaults() {
  group('a mark the user never captioned', () {
    testWidgets('opens on an empty box even when a logo turned it on', (
      tester,
    ) async {
      // Picking a logo is what sets `enabled`, and the model still carries a
      // placeholder caption. Neither may arrive pre-filled in the box, or
      // switching to Text would put words on the video nobody typed.
      final project = _project(
        mark: Watermark(enabled: true, type: WatermarkType.image)
          ..imagePath = '/logo.png',
      );
      await _openPanel(tester, project);

      await tester.tap(find.text('Text'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(project.watermark.text, isEmpty);
      expect(project.watermark.enabled, isFalse);
      expect(project.watermark.isReady, isFalse);
    });
  });
}
