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
import 'package:video_editor/ui/editor/preview/preview_stage.dart';
import 'package:video_editor/ui/widgets/panel_shell.dart';
import 'package:video_editor/ui/export/export_screen.dart';
import 'package:video_editor/ui/home/home_screen.dart';
import 'package:video_editor/ui/image_editor/image_editor_screen.dart';
import 'package:video_editor/ui/templates/template_gallery_screen.dart';
import 'package:video_editor/ui/picker/media_picker_screen.dart';
import 'package:video_editor/ui/splash/splash_screen.dart';
import 'package:video_editor/ui/text_to_video/text_slides_screen.dart';
import 'package:video_editor/ui/text_to_video/text_to_video_screen.dart';

import 'helpers/editor_tools.dart';

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
  'Change speed',
  'Volume',
  'Filter',
  'Effects',
  'Adjust',
  'Crop',
  'Duration',
  'Transition',
  'Mask',
  'Chroma',
];

/// The toolbar is a lazily-built horizontal strip, so a tool far enough along
/// it is not mounted until it is scrolled into view.
Future<void> _tapTool(WidgetTester tester, String label) async {
  // A toast from the tool before this one sits over the bottom bar for two
  // seconds, and the drag below would land on it instead of the toolbar.
  final snack = find.byType(SnackBar);
  if (snack.evaluate().isNotEmpty) {
    ScaffoldMessenger.of(tester.element(snack)).clearSnackBars();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  await tapEditorTool(tester, label);
}

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
            await _tapTool(tester, tool);
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

  group('every sheet is the same height and scrolls', () {
    // The preview is whatever the sheet leaves over, so a sheet that sized
    // itself to its own controls resized the video every time the user moved
    // from one tool to the next. Every sheet is one height now — whichever
    // tool opened it, whatever it is holding — and it scrolls what does not
    // fit rather than growing or stranding a control off the bottom.
    const phone = Size(390, 844);

    // Two clips: Transition is a tool about the join between them, and with
    // only one it toasts rather than opening.
    Project projectWithClips() => Project(
      name: 'Clip project',
      ratio: CanvasRatio.r9x16,
      clips: [
        for (var i = 0; i < 2; i++)
          VideoClip(
            path: '/nonexistent/clip$i.jpg',
            isImage: true,
            sourceDuration: const Duration(seconds: 4),
          ),
      ],
    );

    /// Opens [tool] and returns the sheet's height and the preview's.
    Future<(double, double)> openTool(
      WidgetTester tester,
      String tool, {
      bool selectClip = false,
      bool addText = false,
    }) async {
      await tester.pumpWidget(
        _host(EditorScreen(key: ValueKey(tool), project: projectWithClips())),
      );
      await tester.pump(const Duration(milliseconds: 300));

      if (selectClip) {
        // The track runs on past the right edge, so its centre is not
        // necessarily on screen. Tap the middle of the part that is.
        final strip = tester.getRect(find.byType(ClipStrip).first);
        final screen = Offset.zero & phone;
        await tester.tapAt(strip.intersect(screen).center);
        await tester.pump(const Duration(milliseconds: 300));
      }
      if (addText) {
        await _tapTool(tester, 'Text');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.check).first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await _tapTool(tester, tool);
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byType(PanelShell),
        findsWidgets,
        reason: 'the $tool tool did not open a sheet',
      );
      return (
        tester.getSize(find.byType(PanelShell).first).height,
        tester.getSize(find.byType(PreviewStage).first).height,
      );
    }

    // Every tool the toolbar can reach, and what it needs selected first.
    final everyTool = <String, ({bool clip, bool text})>{
      for (final t in _panelTools) t: (clip: false, text: false),
      for (final t in _clipTools) t: (clip: true, text: false),
      'Animate': (clip: false, text: true),
      'Keyframe': (clip: false, text: true),
    };

    testWidgets('one height for all of them', (tester) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final heights = <String, double>{};
      for (final entry in everyTool.entries) {
        final (sheet, _) = await openTool(
          tester,
          entry.key,
          selectClip: entry.value.clip,
          addText: entry.value.text,
        );
        heights[entry.key] = sheet;
      }

      final distinct = heights.values.map((h) => h.toStringAsFixed(1)).toSet();
      expect(
        distinct,
        hasLength(1),
        reason: 'sheets came out different heights, so the preview resizes as '
            'the user moves along the toolbar: $heights',
      );
    });

    testWidgets('and the preview keeps its size across them', (tester) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Text is left out on purpose: opening it adds a text layer, and the
      // lane that appears on the timeline for it is what takes the height —
      // not the sheet. Every other tool leaves the timeline as it found it,
      // so any difference between them would be the sheet's doing.
      final previews = <String, double>{};
      for (final tool in _panelTools.where((t) => t != 'Text')) {
        final (_, preview) = await openTool(tester, tool);
        previews[tool] = preview;
      }

      final distinct = previews.values.map((h) => h.toStringAsFixed(1)).toSet();
      expect(
        distinct,
        hasLength(1),
        reason: 'the video is a different size depending on which tool is '
            'open: $previews',
      );
    });

    for (final entry in everyTool.entries) {
      testWidgets('${entry.key} scrolls', (tester) async {
        tester.view.physicalSize = phone;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await openTool(
          tester,
          entry.key,
          selectClip: entry.value.clip,
          addText: entry.value.text,
        );

        // Not "has a scroll offset" — a sheet whose controls fit has nothing
        // to scroll. What matters is that reaching them is possible at all,
        // which is the scroll view the shell puts round every body.
        expect(
          find.descendant(
            of: find.byType(PanelShell).first,
            matching: find.byType(Scrollable),
          ),
          findsWidgets,
          reason: 'the ${entry.key} sheet cannot be scrolled, so anything '
              'past its bottom edge is out of reach',
        );
      });
    }
  });

  group('a sheet resizes by hand', () {
    // Two gestures that have to stay out of each other's way: the chrome
    // drags the sheet, the body scrolls inside it.
    const phone = Size(390, 844);

    Future<void> openWatermark(WidgetTester tester) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(EditorScreen(project: sampleProject())));
      await tester.pump(const Duration(milliseconds: 300));
      await _tapTool(tester, 'Watermark');
      await tester.pump(const Duration(milliseconds: 400));
    }

    double sheetHeight(WidgetTester tester) =>
        tester.getSize(find.byType(PanelShell).first).height;

    /// The middle of the grab handle, which moves as the sheet resizes.
    Offset handle(WidgetTester tester) {
      final sheet = tester.getRect(find.byType(PanelShell).first);
      return Offset(sheet.center.dx, sheet.top + PanelShell.kHandleHeight / 2);
    }

    testWidgets('dragging the handle up makes it taller', (tester) async {
      await openWatermark(tester);
      final opened = sheetHeight(tester);

      await tester.dragFrom(handle(tester), const Offset(0, -90));
      await tester.pump();

      expect(sheetHeight(tester), closeTo(opened + 90, 1));
      // What the sheet took is the preview's, which is the whole point of the
      // gesture: the user is choosing to trade video for controls.
      expect(tester.getSize(find.byType(PreviewStage).first).height,
          lessThan(844));
    });

    testWidgets('dragging it down stops at a usable minimum', (tester) async {
      await openWatermark(tester);

      await tester.dragFrom(handle(tester), const Offset(0, 400));
      await tester.pump();

      // Still showing its title row and a control — a sheet dragged to
      // nothing would be a close button the user did not press.
      expect(sheetHeight(tester), greaterThan(PanelShell.kHandleHeight + 44));
      expect(find.text('Watermark'), findsOneWidget);
    });

    testWidgets('tapping the handle puts it back', (tester) async {
      await openWatermark(tester);
      final opened = sheetHeight(tester);

      await tester.dragFrom(handle(tester), const Offset(0, -90));
      await tester.pump();
      await tester.tapAt(handle(tester));
      await tester.pump();

      expect(sheetHeight(tester), opened);
    });

    testWidgets('the title row drags it too', (tester) async {
      await openWatermark(tester);
      final opened = sheetHeight(tester);

      await tester.dragFrom(
        tester.getCenter(find.text('Watermark')),
        const Offset(0, -60),
      );
      await tester.pump();

      expect(sheetHeight(tester), greaterThan(opened));
    });

    testWidgets('scrolling the body does not resize the sheet',
        (tester) async {
      await openWatermark(tester);
      final opened = sheetHeight(tester);
      final body = find
          .descendant(
            of: find.byType(PanelShell).first,
            matching: find.byType(SingleChildScrollView),
          )
          .first;

      await tester.drag(body, const Offset(0, -60));
      await tester.pump();

      final scroll = tester.state<ScrollableState>(
        find.descendant(of: body, matching: find.byType(Scrollable)).first,
      );
      expect(scroll.position.pixels, greaterThan(0),
          reason: 'the body did not scroll');
      expect(sheetHeight(tester), opened,
          reason: 'scrolling the controls resized the sheet as well');
    });

    testWidgets('the buttons in the chrome still take taps', (tester) async {
      await openWatermark(tester);

      await tester.tap(find.byIcon(Icons.close).first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(PanelShell), findsNothing,
          reason: 'the drag gesture swallowed the close button');
    });
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
            await tester.tap(find.byType(ClipStrip).first, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 300));

            await _tapTool(tester, tool);
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
            await _tapTool(tester, 'Text');
            await tester.pump(const Duration(milliseconds: 300));
            // A short window scrolls the whole editor column, so the sheet's
            // confirm can be below the fold — bring it into reach first, or
            // the panel stays open and the layer tools never show.
            final confirm = find.byIcon(Icons.check).first;
            await tester.ensureVisible(confirm);
            await tester.pump();
            await tester.tap(confirm, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 300));

            await _tapTool(tester, tool);
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
            'ImageEditorScreen',
            entry.value,
            textScale,
            () => const ImageEditorScreen(path: '/nonexistent/photo.jpg'),
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
