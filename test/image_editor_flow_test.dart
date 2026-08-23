import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/ui/image_editor/image_editor_screen.dart';

/// End to end through the real screen: open a photo, work it with each tool
/// the way a finger would, press Save, and read the file that came out.
///
/// The other image-editor tests call the renderer directly. These do not:
/// everything here goes through the stage's own gestures and the Save button,
/// so a tool that draws beautifully but never reaches the file — or reaches
/// it somewhere else — fails here.
void main() {
  late Directory sandbox;
  late String photo;

  Widget host(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sandbox = Directory.systemTemp.createTempSync('photo_flow');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => sandbox.path,
    );
    // The gallery is a side effect of saving, not the point of it: answer
    // yes so the code takes its normal path.
    messenger.setMockMethodCallHandler(
      const MethodChannel('gal'),
      (call) async => true,
    );

    // A 400x400 photograph: a complexion across the top half, something dark
    // and flat across the bottom, and a hard edge between the two.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 400, 200),
      Paint()..color = const Color(0xFFDCAA8C),
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 200, 400, 200),
      Paint()..color = const Color(0xFF10203C),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(400, 400);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    photo = '${sandbox.path}/source.png';
    File(photo).writeAsBytesSync(bytes!.buffer.asUint8List());
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null);
    messenger.setMockMethodCallHandler(const MethodChannel('gal'), null);
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  /// Opens the editor on the test photo and waits for the decode and the skin
  /// pass to finish. Both are real file work, so they need a real event loop.
  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(host(ImageEditorScreen(path: photo)));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });
    expect(find.textContaining('could not be opened'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'the photo should have finished decoding');
  }

  Future<void> tapTool(WidgetTester tester, String label) async {
    final finder = find.text(label).last;
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Presses Save and hands back the pixels of the file it wrote.
  Future<_Pixels> save(WidgetTester tester) async {
    final before = Directory('${sandbox.path}/sve_exports');
    final had = before.existsSync()
        ? before.listSync().map((e) => e.path).toSet()
        : <String>{};

    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await tester.pump();
      await Future<void>.delayed(const Duration(seconds: 2));
      await tester.pump();
    });

    // The button says so itself when the file is on disk.
    expect(find.text('Saved'), findsOneWidget);

    final written = Directory('${sandbox.path}/sve_exports')
        .listSync()
        .where((e) => !had.contains(e.path))
        .toList();
    expect(written, hasLength(1), reason: 'saving should write one file');

    final pixels = await tester.runAsync(() async {
      final bytes = await File(written.single.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final result = _Pixels(
        data!.buffer.asUint8List(),
        image.width,
        image.height,
      );
      image.dispose();
      return result;
    });
    return pixels!;
  }

  /// The picture's own rectangle on screen, in the coordinates the brushes
  /// and the overlays are stored against.
  Rect stage(WidgetTester tester, {bool overlay = false}) => tester.getRect(
        find.byKey(ValueKey(overlay ? 'photo-overlay' : 'photo-brush')),
      );

  group('the photo editor, end to end', () {
    testWidgets('saves an untouched photo as the photo', (tester) async {
      await open(tester);
      final out = await save(tester);

      expect(out.width, 400);
      expect(out.height, 400);
      expect(out.at(0.5, 0.25).r, greaterThan(200), reason: 'the complexion');
      expect(out.at(0.5, 0.75).b, lessThan(80), reason: 'the dark half');
    });

    testWidgets('Crop crops to the ratio that was chosen', (tester) async {
      await open(tester);
      await tapTool(tester, 'Crop');
      await tester.tap(find.text('9:16'));
      await tester.pump();
      final out = await save(tester);

      // The tallest 9:16 window a 400 square can hold.
      expect(out.height, 400);
      expect(out.width, closeTo(225, 2));
      // The middle of the photo is what the window was centred on.
      expect(out.at(0.5, 0.25).r, greaterThan(200));
      expect(out.at(0.5, 0.75).b, lessThan(80));
    });

    testWidgets('Filter regrades the saved file', (tester) async {
      await open(tester);
      final plain = await save(tester);

      await tapTool(tester, 'Filter');
      await tester.tap(find.text('Kodak'));
      await tester.pump();
      final graded = await save(tester);

      final before = plain.at(0.5, 0.25);
      final after = graded.at(0.5, 0.25);
      final moved =
          (after.r - before.r).abs() +
          (after.g - before.g).abs() +
          (after.b - before.b).abs();
      expect(moved, greaterThan(10), reason: 'the look should have landed');
    });

    testWidgets('Doodle ink is drawn where the finger went', (tester) async {
      await open(tester);
      await tapTool(tester, 'Doodle');
      final rect = stage(tester);

      // A line across the dark half, three quarters of the way down.
      final y = rect.top + rect.height * 0.75;
      await tester.dragFrom(
        Offset(rect.left + rect.width * 0.2, y),
        Offset(rect.width * 0.6, 0),
      );
      await tester.pump();
      final out = await save(tester);

      // The default ink is red, and the half it was drawn on is not.
      final ink = out.at(0.5, 0.75);
      expect(ink.r, greaterThan(150), reason: 'the stroke should be here');
      expect(out.at(0.5, 0.25).r, greaterThan(200), reason: 'and not here');
      expect(out.at(0.1, 0.75).b, greaterThan(40), reason: 'nor short of it');
    });

    testWidgets('Pixelate blurs the edge it is painted over, and only it',
        (tester) async {
      await open(tester);
      await tapTool(tester, 'Pixelate');
      final rect = stage(tester);

      // A fat dab on the seam between the two halves, on the right.
      await tester.dragFrom(
        Offset(rect.left + rect.width * 0.65, rect.top + rect.height * 0.5),
        const Offset(20, 0),
      );
      await tester.pump();
      final out = await save(tester);

      // Under the dab the seam is a block of the average of both halves…
      final mixed = out.at(0.7, 0.49);
      expect(mixed.r, greaterThan(60));
      expect(mixed.r, lessThan(200));
      // …and away from it the edge is still exactly where it was.
      expect(out.at(0.1, 0.49).r, greaterThan(200));
      expect(out.at(0.1, 0.51).r, lessThan(60));
    });

    testWidgets('Remove softens the spot it was dabbed on', (tester) async {
      await open(tester);
      await tapTool(tester, 'Remove');
      final rect = stage(tester);

      await tester.dragFrom(
        Offset(rect.left + rect.width * 0.65, rect.top + rect.height * 0.5),
        const Offset(12, 0),
      );
      await tester.pump();
      final out = await save(tester);

      // The hard seam has been carried across itself under the dab, and
      // left alone everywhere else.
      final dabbed = out.at(0.65, 0.51).r;
      final untouched = out.at(0.1, 0.51).r;
      expect(dabbed, greaterThan(untouched + 10));
    });

    testWidgets('Portrait lifts the skin and leaves the rest alone',
        (tester) async {
      await open(tester);
      await tapTool(tester, 'Portrait');
      // The photo is half complexion, so the pass has something to work on.
      expect(find.textContaining('No face found'), findsNothing);

      await tester.tap(find.text('Auto'));
      await tester.pump();
      final out = await save(tester);

      expect(out.at(0.5, 0.25).r, greaterThan(225),
          reason: 'the complexion should have been lifted');
      expect(out.at(0.5, 0.75).b, lessThan(80),
          reason: 'the dark half is not skin');
    });

    testWidgets('Text is typed, placed, and burned in', (tester) async {
      await open(tester);
      await tapTool(tester, 'Text');
      await tester.tap(find.text('Add text'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), 'HELLO');
      await tester.tap(find.text('Done'));
      await tester.pump(const Duration(milliseconds: 400));

      // Drag it down onto the dark half, where white letters show.
      final rect = stage(tester, overlay: true);
      await tester.dragFrom(
        rect.center,
        Offset(0, rect.height * 0.25),
      );
      await tester.pump();
      final out = await save(tester);

      expect(out.countWhite(0.2, 0.6, 0.8, 0.9), greaterThan(30),
          reason: 'white letters should be on the dark half');
      expect(out.countWhite(0.2, 0.05, 0.8, 0.3), 0,
          reason: 'and nowhere near the top');
    });

    testWidgets('a sticker shape is placed at the middle', (tester) async {
      await open(tester);
      await tapTool(tester, 'Sticker');
      await tester.tap(find.text('Shapes'));
      await tester.pump();
      // The first shape is a filled circle, in the ink colour.
      await tester.tap(find.byIcon(Icons.circle).first);
      await tester.pump();
      expect(find.text('Delete'), findsOneWidget);
      final out = await save(tester);

      final middle = out.at(0.5, 0.5);
      expect(middle.r, greaterThan(180));
      expect(middle.g, lessThan(120));
    });

    testWidgets('the watermark is burned into the corner it belongs in',
        (tester) async {
      await open(tester);
      await tapTool(tester, 'Watermark');
      await tester.tap(find.text('Off'));
      await tester.pump();
      final out = await save(tester);

      // A fresh mark sits bottom right at three quarters opacity, so it
      // lands pale rather than white.
      expect(out.countWhite(0.6, 0.8, 0.99, 0.99, floor: 150),
          greaterThan(20), reason: 'the mark should be in the bottom right');
      expect(out.countWhite(0.02, 0.55, 0.4, 0.99, floor: 150), 0,
          reason: 'and nowhere else on the dark half');
    });

    testWidgets('two tools at once both land in the same file',
        (tester) async {
      await open(tester);

      await tapTool(tester, 'Doodle');
      final rect = stage(tester);
      await tester.dragFrom(
        Offset(rect.left + rect.width * 0.2, rect.top + rect.height * 0.75),
        Offset(rect.width * 0.6, 0),
      );
      await tester.pump();

      await tapTool(tester, 'Crop');
      await tester.tap(find.text('1:1'));
      await tester.pump();

      await tapTool(tester, 'Filter');
      await tester.tap(find.text('Kodak'));
      await tester.pump();

      final out = await save(tester);
      expect(out.width, out.height, reason: 'the square crop');
      // The stroke was placed against the finished picture, so a crop taken
      // afterwards keeps it where the user drew it.
      expect(out.at(0.5, 0.75).r, greaterThan(150));
    });

    testWidgets('undo takes back what the last gesture did', (tester) async {
      await open(tester);
      await tapTool(tester, 'Doodle');
      final rect = stage(tester);
      await tester.dragFrom(
        Offset(rect.left + rect.width * 0.2, rect.top + rect.height * 0.75),
        Offset(rect.width * 0.6, 0),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      final out = await save(tester);

      expect(out.at(0.5, 0.75).r, lessThan(60), reason: 'the ink is gone');
      expect(out.at(0.5, 0.75).b, greaterThan(40), reason: 'the photo is not');
    });
  });
}

/// The pixels of a saved file, read in fractions of the picture.
class _Pixels {
  const _Pixels(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;

  ({double r, double g, double b, double a}) at(double fx, double fy) {
    final x = (fx * width).clamp(0, width - 1).toInt();
    final y = (fy * height).clamp(0, height - 1).toInt();
    final i = (y * width + x) * 4;
    return (
      r: bytes[i].toDouble(),
      g: bytes[i + 1].toDouble(),
      b: bytes[i + 2].toDouble(),
      a: bytes[i + 3].toDouble(),
    );
  }

  /// How many pale pixels a region holds — how a glyph or a mark shows up in
  /// a picture that has nothing pale anywhere else in it. [floor] drops for a
  /// mark that is deliberately see-through.
  int countWhite(
    double left,
    double top,
    double right,
    double bottom, {
    int floor = 240,
  }) {
    var found = 0;
    final x0 = (left * width).toInt(), x1 = (right * width).toInt();
    final y0 = (top * height).toInt(), y1 = (bottom * height).toInt();
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final i = (y * width + x) * 4;
        if (bytes[i] > floor &&
            bytes[i + 1] > floor &&
            bytes[i + 2] > floor) {
          found++;
        }
      }
    }
    return found;
  }
}
