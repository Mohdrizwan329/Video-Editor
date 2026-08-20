import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/core/utils/responsive.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/state/projects_controller.dart';
import 'package:video_editor/ui/editor/editor_screen.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/ui/editor/timeline/clip_strip.dart';
import 'package:video_editor/ui/editor/toolbar/editor_toolbar.dart';
import 'package:video_editor/ui/export/export_screen.dart';
import 'package:video_editor/ui/home/home_screen.dart';
import 'package:video_editor/ui/templates/template_gallery_screen.dart';
import 'package:video_editor/ui/picker/media_picker_screen.dart';
import 'package:video_editor/ui/splash/splash_screen.dart';
import 'package:video_editor/ui/text_to_video/text_slides_screen.dart';
import 'package:video_editor/ui/text_to_video/text_to_video_screen.dart';

/// The windows the app has to survive: the smallest phone still sold, a
/// mainstream phone, that phone on its side, a tablet both ways up, and the
/// desktop/browser sizes that Windows, macOS, Chrome and Edge open at.
const Map<String, Size> _windows = {
  'small phone': Size(320, 568),
  'phone': Size(390, 844),
  'phone landscape': Size(844, 390),
  'tablet portrait': Size(834, 1194),
  'tablet landscape': Size(1194, 834),
  'small desktop window': Size(1024, 640),
  'desktop': Size(1440, 900),
  'wide desktop': Size(1920, 1080),
};

/// Text scales a user can pick in the system settings, clamped by the app to
/// this range — the top of it is where fixed-height rows break first.
const List<double> _textScales = [1.0, 1.3];

Widget _host(Widget child, {double textScale = 1.0}) {
  // Above the MaterialApp, so a screen that pushes another route — the splash
  // handing over to the home screen — still finds it.
  return ChangeNotifierProvider(
    create: (_) => ProjectsController(),
    child: MaterialApp(
      theme: AppTheme.light,
      scrollBehavior: const AppScrollBehavior(),
      // copyWith, not a fresh MediaQueryData — the latter would hand every
      // screen a zero-sized window and make the whole check meaningless.
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child,
        ),
      ),
    ),
  );
}

Future<void> _expectNoOverflow(
  WidgetTester tester,
  String label,
  Size size,
  double textScale,
  Widget Function() build, {
  Duration settle = const Duration(milliseconds: 400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_host(build(), textScale: textScale));
  await tester.pump(settle);

  final error = tester.takeException();
  expect(
    error,
    isNull,
    reason:
        '$label overflowed at ${size.width}x${size.height} '
        '(text scale $textScale): $error',
  );
}

/// Panels the toolbar can open with nothing selected and no plugin behind
/// them — the dense sheets that a short window squeezes first.
const List<String> _panelTools = [
  'Canvas',
  'Backdrop',
  'Watermark',
  'Mix',
  'Text',
  'Sticker',
  'Audio',
  'Voice',
  'TTS',
  'Captions',
];

/// Panels reachable once a clip is selected.
const List<String> _clipTools = [
  'Speed',
  'Volume',
  'Filter',
  'Adjust',
  'Crop',
  'Duration',
  'Transition',
  'Mask',
  'Chroma',
];

void main() {
  Project sampleProject() {
    final p = Project(
      name: 'A rather long project name',
      ratio: CanvasRatio.r9x16,
    );
    return p;
  }

  group('every editor panel fits the window it opens in', () {
    for (final entry in _windows.entries) {
      for (final textScale in _textScales) {
        testWidgets('${entry.key} @ ${textScale}x', (tester) async {
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          for (final tool in _panelTools) {
            await tester.pumpWidget(
              _host(
                // A fresh key each time, so the editor starts back at its
                // toolbar rather than keeping the panel the last tool opened.
                EditorScreen(key: ValueKey(tool), project: sampleProject()),
                textScale: textScale,
              ),
            );
            await tester.pump(const Duration(milliseconds: 300));

            // The toolbar is a horizontal strip; the later tools need
            // scrolling into view before they can be tapped.
            final button = find.text(tool);
            if (button.evaluate().isEmpty) {
              await tester.dragUntilVisible(
                button,
                find.byType(EditorToolbar),
                const Offset(-120, 0),
                maxIteration: 40,
              );
            }
            await tester.tap(button, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 400));

            final error = tester.takeException();
            expect(
              error,
              isNull,
              reason:
                  'the $tool panel overflowed at '
                  '${entry.value.width}x${entry.value.height} '
                  '(text scale $textScale): $error',
            );
          }
        });
      }
    }
  });

  group('the tools for a selected clip fit the window', () {
    // A clip on the timeline unlocks the largest set of panels in the app.
    Project projectWithClip() => Project(
      name: 'Clip project',
      ratio: CanvasRatio.r9x16,
      clips: [
        VideoClip(
          path: '/nonexistent/clip.jpg',
          isImage: true,
          sourceDuration: const Duration(seconds: 4),
        ),
      ],
    );

    for (final entry in _windows.entries) {
      for (final textScale in _textScales) {
        testWidgets('${entry.key} @ ${textScale}x', (tester) async {
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          for (final tool in _clipTools) {
            await tester.pumpWidget(
              _host(
                EditorScreen(key: ValueKey(tool), project: projectWithClip()),
                textScale: textScale,
              ),
            );
            await tester.pump(const Duration(milliseconds: 300));

            // Tapping the clip on the timeline selects it and swaps in the
            // clip toolbar.
            await tester.tap(find.byType(ClipStrip), warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 300));

            final button = find.text(tool);
            if (button.evaluate().isEmpty) {
              await tester.dragUntilVisible(
                button,
                find.byType(EditorToolbar),
                const Offset(-120, 0),
                maxIteration: 40,
              );
            }
            await tester.tap(button, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 400));

            final error = tester.takeException();
            expect(
              error,
              isNull,
              reason:
                  'the $tool panel overflowed at '
                  '${entry.value.width}x${entry.value.height} '
                  '(text scale $textScale): $error',
            );
          }
        });
      }
    }
  });

  group('the tools for a selected layer fit the window', () {
    for (final entry in _windows.entries) {
      for (final textScale in _textScales) {
        testWidgets('${entry.key} @ ${textScale}x', (tester) async {
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          for (final tool in const ['Animate', 'Keyframe']) {
            await tester.pumpWidget(
              _host(
                EditorScreen(key: ValueKey(tool), project: sampleProject()),
                textScale: textScale,
              ),
            );
            await tester.pump(const Duration(milliseconds: 300));

            // Adding a text layer selects it, which swaps the toolbar for the
            // layer tools and grows the timeline by a lane.
            await tester.tap(find.text('Text'), warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 300));
            await tester.tap(
              find.byIcon(Icons.check).first,
              warnIfMissed: false,
            );
            await tester.pump(const Duration(milliseconds: 300));

            final button = find.text(tool);
            if (button.evaluate().isEmpty) {
              await tester.dragUntilVisible(
                button,
                find.byType(EditorToolbar),
                const Offset(-120, 0),
                maxIteration: 40,
              );
            }
            await tester.tap(button, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 400));

            final error = tester.takeException();
            expect(
              error,
              isNull,
              reason:
                  'the $tool panel overflowed at '
                  '${entry.value.width}x${entry.value.height} '
                  '(text scale $textScale): $error',
            );
          }
        });
      }
    }
  });

  group('every screen lays out without overflowing', () {
    for (final entry in _windows.entries) {
      for (final textScale in _textScales) {
        testWidgets('${entry.key} @ ${textScale}x', (tester) async {
          await _expectNoOverflow(
            tester,
            'HomeScreen',
            entry.value,
            textScale,
            () => const HomeScreen(),
          );

          await _expectNoOverflow(
            tester,
            'EditorScreen',
            entry.value,
            textScale,
            () => EditorScreen(project: sampleProject()),
          );

          await _expectNoOverflow(
            tester,
            'ExportScreen',
            entry.value,
            textScale,
            () => ExportScreen(project: sampleProject()),
          );

          await _expectNoOverflow(
            tester,
            'TemplateGalleryScreen',
            entry.value,
            textScale,
            () => const TemplateGalleryScreen(),
          );

          await _expectNoOverflow(
            tester,
            'TextSlidesScreen',
            entry.value,
            textScale,
            () => const TextSlidesScreen(),
          );

          await _expectNoOverflow(
            tester,
            'TextToVideoScreen',
            entry.value,
            textScale,
            () => const TextToVideoScreen(),
          );

          await _expectNoOverflow(
            tester,
            'MediaPickerScreen',
            entry.value,
            textScale,
            () => const MediaPickerScreen(),
          );

          await _expectNoOverflow(
            tester,
            'SplashScreen',
            entry.value,
            textScale,
            () => const SplashScreen(),
            // Long enough for the boot timeout, the minimum-on-screen delay
            // and the fade into the home screen, so no timer outlives the
            // test.
            settle: const Duration(seconds: 8),
          );
        });
      }
    }
  });
}
