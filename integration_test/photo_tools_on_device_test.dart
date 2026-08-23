import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/core/utils/responsive.dart';
import 'package:video_editor/ui/image_editor/image_editor_screen.dart';

/// Presses every tool on the photo editor's bar, one at a time, in the real
/// app on the real device — and then *uses* it.
///
/// A tool that opens a panel has not been checked; a tool whose control has
/// been moved and which then has something to undo has. Undo is the signal
/// because it is the app's own: it goes live exactly when an edit is
/// committed, so a panel that writes nothing leaves it dead.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String photoPath;

  setUpAll(() async {
    // A real photograph with a person in it, pushed to the device before
    // the run: the portrait tools need a face and the cutout needs a
    // subject, and neither is in a generated swatch.
    //
    // Shared storage first, because installing the app for the test wipes
    // its own directory and would take the photo with it.
    // The app's own external directory: it needs no permission to read and
    // it survives the install the test run begins with, which the internal
    // one does not.
    final external = await getExternalStorageDirectory();
    final dir = await getApplicationDocumentsDirectory();
    final candidates = [
      if (external != null) '${external.path}/person.png',
      '${dir.path}/person.png',
    ];
    photoPath = candidates.firstWhere(
      (p) => File(p).existsSync(),
      orElse: () => '',
    );
    if (photoPath.isEmpty) {
      // Installing the app for a test run takes its directories with it, so
      // a pushed photo is a convenience rather than something to depend on.
      // Without one the tools that need a face say so and are skipped; the
      // rest work on anything with detail in it.
      photoPath = await _swatchFile('${dir.path}/swatch.png');
    }
    expect(File(photoPath).existsSync(), isTrue);
  });

  Future<void> open(WidgetTester tester, String key) async {
    await tester.pumpWidget(
      MaterialApp(
        key: ValueKey(key),
        theme: AppTheme.light,
        scrollBehavior: const AppScrollBehavior(),
        home: ImageEditorScreen(path: photoPath),
      ),
    );
    // The photo is decoded off the first frame, and the skin mask after it.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Whether the app has an edit to undo — its own answer to 'did that do
  /// anything', rather than the test's guess at one.
  bool canUndo(WidgetTester tester) {
    final button = tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byIcon(Icons.undo),
            matching: find.byType(IconButton),
          )
          .first,
    );
    return button.onPressed != null;
  }

  /// Brings a tool into view on the bar and taps it.
  Future<void> tapTool(WidgetTester tester, String label) async {
    final button = find.text(label);
    await tester.scrollUntilVisible(
      button,
      120,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 60,
    );
    await tester.tap(button.last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  /// A stroke across the middle of the picture, for the brush tools.
  Future<void> paint(WidgetTester tester) async {
    final stage = find.byKey(const ValueKey('photo-brush'));
    if (stage.evaluate().isEmpty) return;
    final rect = tester.getRect(stage);
    final gesture = await tester.startGesture(
      rect.center - const Offset(40, 0),
    );
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(14, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> dragFirstSlider(WidgetTester tester) async {
    final slider = find.byType(Slider);
    if (slider.evaluate().isEmpty) return;
    await tester.drag(slider.first, const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    final f = find.text(label);
    if (f.evaluate().isEmpty) return;
    await tester.tap(f.last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Opens a tool's text dialog through [button], types [words] and keeps
  /// them.
  Future<void> typeInto(
    WidgetTester tester,
    String button,
    String words,
  ) async {
    await tapText(tester, button);
    final field = find.byType(TextField);
    if (field.evaluate().isEmpty) return;
    await tester.enterText(field.first, words);
    await tester.pump(const Duration(milliseconds: 200));
    await tapText(tester, 'Done');
  }

  /// What using each tool means. The two that open the operating system's
  /// own file picker cannot be driven from here — they are checked as far as
  /// their button and marked as such.
  final use = <String, Future<void> Function(WidgetTester)>{
    'Canvas': (t) => tapText(t, '1:1'),
    'Filter': (t) => tapText(t, 'Kodak'),
    'Adjust': dragFirstSlider,
    'Effect': (t) => tapText(t, 'Grain'),
    'Portrait': dragFirstSlider,
    'Sticker': (t) => tapText(t, '😀'),
    // Both of these type into a dialog rather than into the panel, so
    // using them means opening it, typing, and pressing Done.
    'Text': (t) => typeInto(t, 'Add text', 'Hello'),
    'Remove': paint,
    'Enhance': (t) async {
      // The switch itself, not the label: 'Enhance' is also the tool's name
      // on the bar, and tapping that would only re-open the panel.
      final toggle = find.byType(Switch);
      if (toggle.evaluate().isEmpty) return;
      await t.tap(toggle.first);
      await t.pump(const Duration(milliseconds: 400));
    },
    'Mask': (t) => tapText(t, 'Circle'),
    'Detail': dragFirstSlider,
    'Doodle': paint,
    'Reshape': dragFirstSlider,
    'Crop': (t) => tapText(t, '4:5'),
    'Rotate': (t) => tapText(t, 'Right'),
    'Watermark': (t) => typeInto(t, 'Edit', 'Mine'),
    'Pixelate': paint,
  };

  for (final entry in use.entries) {
    testWidgets('${entry.key} does something on the device', (tester) async {
      await open(tester, entry.key);
      expect(
        canUndo(tester),
        isFalse,
        reason: 'the photo opened already edited',
      );

      await tapTool(tester, entry.key);
      await entry.value(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        canUndo(tester),
        isTrue,
        reason:
            '${entry.key} was opened and used and left nothing to undo, '
            'so whatever its panel writes never reached the edit',
      );
      expect(tester.takeException(), isNull, reason: '${entry.key} threw');
    });
  }

  testWidgets('Cutout finds the subject on the device', (tester) async {
    await open(tester, 'Cutout');
    await tapTool(tester, 'Cutout');
    await tapText(tester, 'Cut out');

    // The segmenter is a real model on a real device; give it time.
    var done = false;
    for (var i = 0; i < 60 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      done = canUndo(tester);
    }
    expect(done, isTrue, reason: 'the cutout pass left nothing to undo');
    expect(find.textContaining('background is off'), findsOneWidget);
  });

  for (final tool in const ['PIP', 'Replace']) {
    testWidgets('$tool offers its own way in', (tester) async {
      // These two open the system file picker, which a widget test cannot
      // drive. What can be checked is that the tool opens and offers the
      // button that starts it.
      await open(tester, tool);
      await tapTool(tester, tool);

      expect(
        find.text(tool == 'PIP' ? 'Add' : 'Choose a photo'),
        findsOneWidget,
        reason: '$tool opened on nothing to press',
      );
      expect(tester.takeException(), isNull);
    });
  }
}

/// A picture with structure in it, for the runs with no photo pushed.
Future<String> _swatchFile(String path) async {
  const side = 512;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var y = 0; y < side; y += 32) {
    for (var x = 0; x < side; x += 32) {
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), y.toDouble(), 32, 32),
        Paint()
          ..color = ((x ~/ 32) + (y ~/ 32)).isEven
              ? const Color(0xFFE08040)
              : const Color(0xFF204060),
      );
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(side, side);
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File(path);
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  return file.path;
}
