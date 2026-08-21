import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/core/utils/responsive.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/state/projects_controller.dart';
import 'package:video_editor/ui/editor/editor_screen.dart';
import 'package:video_editor/ui/editor/toolbar/editor_toolbar.dart';
import 'package:video_editor/ui/text_to_video/text_slides_screen.dart';
import 'package:video_editor/ui/text_to_video/text_to_video_screen.dart';

import 'helpers/editor_tools.dart';

/// The windows a text field has to stay usable in.
const Map<String, Size> _windows = {
  'small phone': Size(320, 568),
  'phone': Size(390, 844),
  'phone landscape': Size(844, 390),
  'tablet portrait': Size(834, 1194),
  'tablet landscape': Size(1194, 834),
  'small desktop window': Size(1024, 640),
};

/// A typical software keyboard. Portrait phones give up about 40% of the
/// window to it; landscape is worse, which is exactly the case that breaks.
double _keyboardFor(Size window) =>
    window.height < 500 ? window.height * 0.55 : window.height * 0.38;

Widget _host(Widget child) => ChangeNotifierProvider(
      create: (_) => ProjectsController(),
      child: MaterialApp(
        theme: AppTheme.light,
        scrollBehavior: const AppScrollBehavior(),
        home: child,
      ),
    );

Project _project() => Project(
      name: 'Typing',
      clips: [
        VideoClip(
          path: '/nonexistent/clip.jpg',
          isImage: true,
          sourceDuration: const Duration(seconds: 4),
        ),
      ],
    );

/// Sizes the window. The keyboard is down, as it is when the user is still
/// looking for the tool that opens the field.
void _useWindow(WidgetTester tester, Size window) {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Raises the software keyboard, which is what happens the moment a field
/// takes focus — and what the layout then has to make room for.
Future<void> _raiseKeyboard(WidgetTester tester, Size window) async {
  tester.view.viewInsets = FakeViewPadding(bottom: _keyboardFor(window));
  await tester.pump(const Duration(milliseconds: 400));
}

/// A field the user can actually type into: on screen, above the keyboard,
/// and big enough to hit.
void _expectUsable(
  WidgetTester tester,
  Finder field, {
  required Size window,
  required String where,
}) {
  expect(field, findsOneWidget, reason: '$where: the field is not there');
  final rect = tester.getRect(field);
  final floor = window.height - _keyboardFor(window);

  expect(rect.height, greaterThan(16),
      reason: '$where: the field is collapsed ($rect)');
  expect(rect.top, greaterThanOrEqualTo(-0.5),
      reason: '$where: the field is off the top of the window ($rect)');
  expect(rect.top, lessThan(floor),
      reason: '$where: the field starts under the keyboard — '
          'window ${window.height}, keyboard floor $floor, field $rect');
}

/// The editor toolbar is a lazily-built horizontal strip: a tool far enough
/// along it is not mounted until it is scrolled into view.
Future<void> _tapTool(WidgetTester tester, String label) async {
  await openToolCategory(tester, label);
  // Scoped to the strip: the category bar along the bottom carries some of
  // the same words, so an unscoped finder would match twice.
  final button = find.descendant(
      of: find.byType(EditorToolbar), matching: find.text(label));
  if (button.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      button,
      find.byType(EditorToolbar),
      const Offset(-120, 0),
      maxIteration: 40,
    );
  }
  // dragUntilVisible stops as soon as the button is mounted, which can leave
  // it half off the edge; ensureVisible finishes the job so the tap lands.
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
}

/// Some panels wait on a platform answer (voices, saved settings) that only
/// arrives off the fake clock. Pump and yield to the real event loop until
/// [target] shows up, rather than betting on a fixed delay.
Future<void> _settleFor(WidgetTester tester, Finder target,
    {int tries = 20}) async {
  for (var i = 0; i < tries && target.evaluate().isEmpty; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;

  setUpAll(() {
    // The AI screens read their settings off disk before drawing a field.
    sandbox = Directory.systemTemp.createTempSync('text_input');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => sandbox.path,
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });
  group('the editor text panel', () {
    for (final entry in _windows.entries) {
      testWidgets('takes typing on a ${entry.key}', (tester) async {
        _useWindow(tester, entry.value);
        final project = _project();
        await tester.pumpWidget(_host(EditorScreen(project: project)));
        await tester.pump(const Duration(milliseconds: 300));

        await _tapTool(tester, 'Text');
        await tester.pump(const Duration(milliseconds: 400));
        // The panel's field autofocuses, so the keyboard comes up with it.
        await _raiseKeyboard(tester, entry.value);

        final field = find.byType(TextField);
        _expectUsable(tester, field,
            window: entry.value, where: 'editor text panel on ${entry.key}');

        await tester.enterText(field, 'Hello world');
        await tester.pump(const Duration(seconds: 1));
        expect(project.texts.single.text, 'Hello world');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the text to video prompt', () {
    for (final entry in _windows.entries) {
      testWidgets('takes typing on a ${entry.key}', (tester) async {
        _useWindow(tester, entry.value);
        await tester.pumpWidget(_host(const TextToVideoScreen()));
        // The settings load is real file IO, which only runs off the fake
        // clock.
        await _settleFor(tester, find.byType(TextField));

        final field = find.byType(TextField).first;
        await tester.tap(field, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
        await _raiseKeyboard(tester, entry.value);

        _expectUsable(tester, field,
            window: entry.value, where: 'prompt on ${entry.key}');

        await tester.enterText(field, 'A drone shot over a lake');
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('A drone shot over a lake'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the text slides script', () {
    for (final entry in _windows.entries) {
      testWidgets('takes typing on a ${entry.key}', (tester) async {
        _useWindow(tester, entry.value);
        await tester.pumpWidget(_host(const TextSlidesScreen()));
        await tester.pump(const Duration(milliseconds: 400));

        final field = find.byType(TextField).first;
        await tester.tap(field, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
        await _raiseKeyboard(tester, entry.value);

        _expectUsable(tester, field,
            window: entry.value, where: 'slides title on ${entry.key}');

        await tester.enterText(field, 'My title');
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('My title'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the watermark panel', () {
    for (final entry in _windows.entries) {
      testWidgets('takes typing on a ${entry.key}', (tester) async {
        _useWindow(tester, entry.value);
        final project = _project();
        await tester.pumpWidget(_host(EditorScreen(project: project)));
        await tester.pump(const Duration(milliseconds: 300));

        await _tapTool(tester, 'Watermark');
        await tester.pump(const Duration(milliseconds: 400));

        final field = find.byType(TextField).first;
        await tester.tap(field, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 200));
        await _raiseKeyboard(tester, entry.value);

        _expectUsable(tester, field,
            window: entry.value, where: 'watermark on ${entry.key}');

        await tester.enterText(field, '@myhandle');
        await tester.pump(const Duration(seconds: 1));
        expect(project.watermark.text, '@myhandle');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the rename dialog', () {
    for (final entry in _windows.entries) {
      testWidgets('takes typing on a ${entry.key}', (tester) async {
        _useWindow(tester, entry.value);
        final project = _project();
        await tester.pumpWidget(_host(EditorScreen(project: project)));
        await tester.pump(const Duration(milliseconds: 300));

        // The title in the top bar is the rename affordance.
        await tester.tap(find.text('Typing'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 400));
        await _raiseKeyboard(tester, entry.value);

        final field = find.byType(TextField);
        _expectUsable(tester, field,
            window: entry.value, where: 'rename dialog on ${entry.key}');

        await tester.enterText(field, 'Renamed');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.text('Save'), warnIfMissed: false);
        await tester.pump(const Duration(seconds: 1));
        expect(project.name, 'Renamed');
        expect(tester.takeException(), isNull);
      });
    }
  });


  group('the text to speech panel', () {
    for (final entry in _windows.entries) {
      testWidgets('takes typing on a ${entry.key}', (tester) async {
        _useWindow(tester, entry.value);
        await tester.pumpWidget(_host(EditorScreen(project: _project())));
        await tester.pump(const Duration(milliseconds: 300));

        await _tapTool(tester, 'TTS');
        await tester.pump(const Duration(milliseconds: 300));
        // The panel shows a spinner until the platform lists its voices.
        await _settleFor(tester, find.byType(TextField));

        final field = find.byType(TextField).first;
        await tester.tap(field, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 200));
        await _raiseKeyboard(tester, entry.value);

        _expectUsable(tester, field,
            window: entry.value, where: 'tts on ${entry.key}');

        await tester.enterText(field, 'Read this out loud');
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Read this out loud'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the second field on a screen', () {
    testWidgets('the text to video negative prompt takes typing',
        (tester) async {
      const window = Size(390, 844);
      _useWindow(tester, window);
      await tester.pumpWidget(_host(const TextToVideoScreen()));
      await _settleFor(tester, find.byType(TextField));

      // It lives behind a disclosure, so it only exists once expanded.
      await tester.tap(find.text('Things to avoid (optional)'),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      final field = find.byType(TextField).last;
      await tester.tap(field, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
      await _raiseKeyboard(tester, window);

      _expectUsable(tester, field, window: window, where: 'negative prompt');
      await tester.enterText(field, 'blurry, watermark');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('blurry, watermark'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the text slides script takes typing', (tester) async {
      const window = Size(390, 844);
      _useWindow(tester, window);
      await tester.pumpWidget(_host(const TextSlidesScreen()));
      await tester.pump(const Duration(milliseconds: 400));

      final field = find.byType(TextField).at(1);
      await tester.tap(field, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
      await _raiseKeyboard(tester, window);

      _expectUsable(tester, field, window: window, where: 'slides script');
      await tester.enterText(field, 'Scene one.\n\nScene two.');
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  });
}
