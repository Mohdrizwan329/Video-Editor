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
import 'package:video_editor/core/theme/app_colors.dart';
import 'package:video_editor/ui/widgets/panel_shell.dart';
import 'package:video_editor/ui/export/export_screen.dart';
import 'package:video_editor/ui/home/home_screen.dart';
import 'package:video_editor/ui/image_editor/image_editor_screen.dart';
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
      debugShowCheckedModeBanner: false,
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
  'Effect',
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

  group('every sheet is as tall as its own controls and scrolls', () {
    // A sheet takes the room its controls ask for and no more: a tool with a
    // colour row and a line of help does not open the same height as a tab
    // bar over a grid of presets, and neither of them leaves empty space
    // under the last control. What will not fit is capped and scrolls.
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

    testWidgets('a short tool opens short, a full one opens capped', (
      tester,
    ) async {
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

      // Half the window is the ceiling: past that there is no preview left
      // to edit against, however much a panel is holding.
      const cap = 844 * 0.5;
      for (final entry in heights.entries) {
        expect(
          entry.value,
          lessThanOrEqualTo(cap + 0.5),
          reason: '${entry.key} opened past half the window: $heights',
        );
      }

      // …and the whole point: they are not all one height any more. At least
      // one tool comes out shorter than the room a preset grid asks for,
      // which is the empty space that used to sit under its last control.
      expect(
        heights.values.where((h) => h < PanelShell.kSheetHeight),
        isNotEmpty,
        reason:
            'every sheet is still opening at the full height, so short '
            'panels keep their empty space: $heights',
      );
    });

    testWidgets('a short sheet leaves the preview more room than a full one', (
      tester,
    ) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Canvas is a ratio row; Sticker is a pack bar over a grid of them.
      final (shortSheet, shortPreview) = await openTool(tester, 'Canvas');
      final (fullSheet, fullPreview) = await openTool(tester, 'Sticker');

      expect(shortSheet, lessThan(fullSheet));
      expect(
        shortPreview,
        greaterThan(fullPreview),
        reason:
            'the room the shorter sheet gave up should have gone to the '
            'video',
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
          reason:
              'the ${entry.key} sheet cannot be scrolled, so anything '
              'past its bottom edge is out of reach',
        );
      });
    }
  });

  group('a sheet keeps the height it opened at', () {
    // Nothing here resizes. A sheet that can be dragged taller is a height
    // the user has to guess at, and it puts the same controls in two places
    // — some behind a drag, the rest behind the button.
    const phone = Size(390, 844);

    /// Opens a sheet. Growing one has to start from a tool short enough to
    /// have somewhere to grow: a full sheet already opens at the cap, and
    /// dragging that up is a no-op by design.
    Future<void> openSheet(
      WidgetTester tester, [
      String tool = 'Canvas',
    ]) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(EditorScreen(project: sampleProject())));
      await tester.pump(const Duration(milliseconds: 300));
      await _tapTool(tester, tool);
      await tester.pump(const Duration(milliseconds: 400));
    }

    double sheetHeight(WidgetTester tester) =>
        tester.getSize(find.byType(PanelShell).first).height;

    /// The middle of the grab handle, which moves as the sheet resizes.
    Offset handle(WidgetTester tester) {
      final sheet = tester.getRect(find.byType(PanelShell).first);
      return Offset(sheet.center.dx, sheet.top + PanelShell.kHandleHeight / 2);
    }

    testWidgets('a drag down the handle leaves it where it was', (
      tester,
    ) async {
      await openSheet(tester, 'Backdrop');
      final opened = sheetHeight(tester);

      await tester.dragFrom(handle(tester), const Offset(0, 60));
      await tester.pump();

      expect(sheetHeight(tester), closeTo(opened, 1));
    });

    testWidgets('is edged in the app bar\'s own colour', (tester) async {
      await openSheet(tester, 'Backdrop');

      final shell = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(PanelShell),
              matching: find.byType(Container),
            )
            .first,
      );
      final shape =
          (shell.decoration as ShapeDecoration).shape as RoundedRectangleBorder;
      expect(shape.side.color, AppColors.appBar);
      // All the way round, so the outline follows the rounded top corners
      // instead of stopping short of them.
      expect(shape.borderRadius, isNot(BorderRadius.zero));
    });

    testWidgets('its rounded corners show the strip it is docked under', (
      tester,
    ) async {
      await openSheet(tester, 'Backdrop');

      // The colour painted behind the sheet is what fills the two notches
      // its rounded corners cut out. Under the timeline that has to be the
      // timeline, or the corners read as shoulders stuck to the sheet.
      final behind = tester.widgetList<ColoredBox>(
        find.ancestor(
          of: find.byType(PanelShell),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(behind.map((b) => b.color), contains(AppColors.timelineBg));
    });

    testWidgets('a drag up the handle leaves it where it was', (tester) async {
      await openSheet(tester, 'Backdrop');
      final opened = sheetHeight(tester);

      await tester.dragFrom(handle(tester), const Offset(0, -260));
      await tester.pump();

      expect(sheetHeight(tester), closeTo(opened, 1));
    });

    testWidgets('a drag on the title row leaves it where it was', (
      tester,
    ) async {
      await openSheet(tester, 'Backdrop');
      final opened = sheetHeight(tester);

      await tester.dragFrom(
        tester.getCenter(find.text('Background')),
        const Offset(0, 60),
      );
      await tester.pump();

      expect(sheetHeight(tester), closeTo(opened, 1));
    });

    testWidgets('what it cannot fit is behind the button, not a drag', (
      tester,
    ) async {
      await openSheet(tester, 'Watermark');

      // The tool whose controls outrun a phone-sized sheet. There is one way
      // to the rest of them and it is labelled.
      expect(find.text('More options'), findsOneWidget);
    });

    testWidgets('the body does not scroll under a finger', (tester) async {
      // Watermark has more controls than the sheet can show. Scrolling them
      // is what the 'More options' button replaced: a sheet whose contents
      // slide under the finger hides how much of the tool is left, and the
      // gesture is one the user has to find by accident.
      await openSheet(tester, 'Watermark');
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
      expect(scroll.position.pixels, 0, reason: 'the body scrolled');
      expect(
        sheetHeight(tester),
        opened,
        reason: 'dragging the controls resized the sheet as well',
      );
    });

    testWidgets('a tool with more controls than it can show says so', (
      tester,
    ) async {
      await openSheet(tester, 'Watermark');

      expect(
        find.text('More options'),
        findsOneWidget,
        reason: 'the controls past the fold have no way in',
      );

      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();

      // The second sheet holds the whole tool, and it opens taller than the
      // docked one it came from — that is the point of it.
      expect(find.text('Watermark'), findsWidgets);
      final sheets = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .length;
      expect(sheets, greaterThan(1));
    });

    testWidgets('a tool that fits offers no way to more of it', (tester) async {
      // Backdrop opens on all of its controls, so a 'More options' button
      // would lead to the same panel the user is already looking at.
      await openSheet(tester, 'Backdrop');

      expect(find.text('More options'), findsNothing);
    });

    testWidgets('the buttons in the chrome still take taps', (tester) async {
      await openSheet(tester, 'Watermark');

      await tester.tap(find.byIcon(Icons.close).first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byType(PanelShell),
        findsNothing,
        reason: 'the drag gesture swallowed the close button',
      );
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
