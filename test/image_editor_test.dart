import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/data/models/layers.dart';
import 'package:video_editor/data/models/photo_edit.dart';
import 'package:video_editor/data/models/watermark.dart';
import 'package:video_editor/data/services/face_enhancer.dart';
import 'package:video_editor/data/services/photo_renderer.dart';
import 'package:video_editor/ui/image_editor/image_editor_screen.dart';
import 'package:video_editor/ui/image_editor/widgets/crop_overlay.dart';

Widget _host(Widget child) =>
    MaterialApp(theme: AppTheme.light, home: child);

/// A [width]x[height] picture whose left half is red and right half is blue —
/// enough asymmetry to tell a mirror from a turn from a no-op.
Future<ui.Image> _twoTone(WidgetTester tester, int width, int height) async {
  final image = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final w = width.toDouble(), h = height.toDouble();
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w / 2, h), Paint()..color = const Color(0xFFFF0000));
    canvas.drawRect(Rect.fromLTWH(w / 2, 0, w / 2, h),
        Paint()..color = const Color(0xFF0000FF));
    final picture = recorder.endRecording();
    final out = await picture.toImage(width, height);
    picture.dispose();
    return out;
  });
  return image!;
}

/// Renders [edit] and reports the colour at a point given in fractions of the
/// finished picture.
Future<(Color, Size)> _renderAt(
  WidgetTester tester,
  ui.Image source,
  PhotoEdit edit,
  double fx,
  double fy,
) async {
  final result = await tester.runAsync(() async {
    final bytes = await PhotoRenderer.renderPng(source, edit);
    final codec = await ui.instantiateImageCodec(bytes!);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final x = (fx * image.width).clamp(0, image.width - 1).toInt();
    final y = (fy * image.height).clamp(0, image.height - 1).toInt();
    final i = (y * image.width + x) * 4;
    final px = data!.buffer.asUint8List();
    image.dispose();
    return (Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]), size);
  });
  return result!;
}

/// Taps a tool in the bottom row. There are more tools than fit across a
/// phone, so the row scrolls and the one being asked for may be off screen.
Future<void> _tapTool(WidgetTester tester, String label) async {
  final finder = find.text(label).last;
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('a photo edit', () {
    test('a quarter turn carries the crop window with it', () {
      final e = PhotoEdit()..setCrop(0.2, 0, 0, 0.4);
      e.rotate();
      expect(e.quarterTurns, 1);
      // Turning the picture clockwise takes the left edge to the top: the
      // window keeps the same content instead of jumping across the photo.
      expect(e.cropTop, closeTo(0.2, 1e-9));
      expect(e.cropLeft, closeTo(0.4, 1e-9));

      e.rotate(clockwise: false);
      expect(e.quarterTurns, 0);
      expect(e.cropLeft, closeTo(0.2, 1e-9));
      expect(e.cropBottom, closeTo(0.4, 1e-9));
    });

    test('a locked ratio turns with the picture', () {
      final e = PhotoEdit()..cropAspect = 16 / 9;
      e.rotate();
      expect(e.cropAspect, closeTo(9 / 16, 1e-9));
    });

    test('a mirror takes the crop window along', () {
      final e = PhotoEdit()..setCrop(0.3, 0, 0.1, 0);
      e.mirror(horizontal: true);
      expect(e.flipH, isTrue);
      expect(e.cropLeft, closeTo(0.1, 1e-9));
      expect(e.cropRight, closeTo(0.3, 1e-9));
    });

    test('an untouched photo counts as clean, an edited one does not', () {
      final e = PhotoEdit();
      expect(e.isClean, isTrue);
      e.adjustments.brightness = 0.2;
      expect(e.isClean, isFalse);
      e.adjustments.reset();
      e.filterId = 'kodak';
      expect(e.isClean, isFalse);
    });
  });

  group('the photo renderer', () {
    testWidgets('the output size follows the crop and the turns',
        (tester) async {
      final source = await _twoTone(tester, 100, 50);
      addTearDown(source.dispose);

      final edit = PhotoEdit();
      expect(PhotoRenderer.outputSize(source, edit), const Size(100, 50));
      expect(PhotoRenderer.aspectOf(source, edit), closeTo(2, 1e-9));

      edit.quarterTurns = 1;
      expect(PhotoRenderer.outputSize(source, edit), const Size(50, 100));
      expect(PhotoRenderer.fullAspect(source, edit), closeTo(0.5, 1e-9));

      edit.setCrop(0.5, 0, 0, 0);
      expect(PhotoRenderer.outputSize(source, edit), const Size(25, 100));
    });

    testWidgets('a crop keeps the half the window is over', (tester) async {
      final source = await _twoTone(tester, 100, 50);
      addTearDown(source.dispose);

      // Keep the right half: every pixel of the result should be blue.
      final edit = PhotoEdit()..setCrop(0.5, 0, 0, 0);
      final (colour, size) = await _renderAt(tester, source, edit, 0.1, 0.5);
      expect(size, const Size(50, 50));
      expect(colour.b, greaterThan(0.8));
      expect(colour.r, lessThan(0.25));
    });

    testWidgets('a mirror puts the right half on the left', (tester) async {
      final source = await _twoTone(tester, 100, 50);
      addTearDown(source.dispose);

      final edit = PhotoEdit()..mirror(horizontal: true);
      final (colour, _) = await _renderAt(tester, source, edit, 0.25, 0.5);
      expect(colour.b, greaterThan(0.8));
      expect(colour.r, lessThan(0.25));
    });

    testWidgets('a clockwise turn puts the left edge along the top',
        (tester) async {
      final source = await _twoTone(tester, 100, 50);
      addTearDown(source.dispose);

      final edit = PhotoEdit()..rotate();
      final (colour, size) = await _renderAt(tester, source, edit, 0.5, 0.25);
      expect(size, const Size(50, 100));
      expect(colour.r, greaterThan(0.8));
      expect(colour.b, lessThan(0.25));
    });

    testWidgets('a greyscale look drains the colour out of the file',
        (tester) async {
      final source = await _twoTone(tester, 100, 50);
      addTearDown(source.dispose);

      final edit = PhotoEdit()..filterId = 'mono';
      final (colour, _) = await _renderAt(tester, source, edit, 0.25, 0.5);
      expect((colour.r - colour.g).abs(), lessThan(0.05));
      expect((colour.g - colour.b).abs(), lessThan(0.05));
    });

    testWidgets('half strength lands between the photo and the look',
        (tester) async {
      final source = await _twoTone(tester, 100, 50);
      addTearDown(source.dispose);

      final full = PhotoEdit()..filterId = 'mono';
      final half = PhotoEdit()
        ..filterId = 'mono'
        ..filterIntensity = 0.5;
      final (graded, _) = await _renderAt(tester, source, full, 0.25, 0.5);
      final (partial, _) = await _renderAt(tester, source, half, 0.25, 0.5);
      expect(partial.r, greaterThan(graded.r));
      expect(partial.r, lessThan(0.99));
    });
  });

  group('the crop rectangle', () {
    testWidgets('a locked ratio survives a corner drag', (tester) async {
      Rect? reported;
      await tester.pumpWidget(_host(
        Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: CropOverlay(
              rect: const Rect.fromLTRB(0, 0, 1, 1),
              aspect: 1,
              onChanged: (r) => reported = r,
              onCommit: () {},
            ),
          ),
        ),
      ));

      // From the bottom-right corner, inwards and much further in x than y.
      final corner = tester.getBottomRight(find.byType(CropOverlay));
      await tester.dragFrom(corner - const Offset(2, 2), const Offset(-120, -20));
      await tester.pump();

      expect(reported, isNotNull);
      final r = reported!;
      // 300pt square, so fractions and pixels are the same shape here.
      expect(r.width, closeTo(r.height, 0.01));
      expect(r.left, closeTo(0, 1e-9));
      expect(r.top, closeTo(0, 1e-9));
    });

    testWidgets('a free rectangle never turns itself inside out',
        (tester) async {
      Rect? reported;
      await tester.pumpWidget(_host(
        Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: CropOverlay(
              rect: const Rect.fromLTRB(0, 0, 1, 1),
              onChanged: (r) => reported = r,
              onCommit: () {},
            ),
          ),
        ),
      ));

      // Drag the left edge far past the right one.
      final left = tester.getCenter(find.byType(CropOverlay));
      await tester.dragFrom(
        Offset(tester.getTopLeft(find.byType(CropOverlay)).dx + 2, left.dy),
        const Offset(600, 0),
      );
      await tester.pump();

      final r = reported!;
      expect(r.left, lessThan(r.right));
      expect(r.right, lessThanOrEqualTo(1.0));
      expect(r.left, greaterThanOrEqualTo(0.0));
    });
  });


  group('the brushes', () {
    testWidgets('a mosaic stroke averages what it is painted over',
        (tester) async {
      final source = await _twoTone(tester, 200, 200);
      addTearDown(source.dispose);

      final clean = PhotoEdit();
      final (before, _) = await _renderAt(tester, source, clean, 0.49, 0.5);
      expect(before.r, greaterThan(0.8), reason: 'the left half is red');
      expect(before.b, lessThan(0.2));

      // A fat stroke straight down the seam between the two halves, at the
      // coarsest block the slider offers.
      final edit = PhotoEdit()
        ..pixelSize = 1
        ..pixelate.add(PhotoStroke(
          width: 0.5,
          points: const [Offset(0.5, 0.2), Offset(0.5, 0.5), Offset(0.5, 0.8)],
        ));
      final (after, _) = await _renderAt(tester, source, edit, 0.49, 0.5);
      // A block that straddles the seam is half of each half.
      expect(after.b, greaterThan(0.2),
          reason: 'the block should have pulled blue across the seam');
      expect(after.r, lessThan(before.r));
    });

    testWidgets('a mosaic leaves everything outside the stroke alone',
        (tester) async {
      final source = await _twoTone(tester, 200, 200);
      addTearDown(source.dispose);

      final edit = PhotoEdit()
        ..pixelSize = 1
        ..pixelate.add(PhotoStroke(
          width: 0.3,
          points: const [Offset(0.5, 0.5)],
        ));
      final (corner, _) = await _renderAt(tester, source, edit, 0.05, 0.05);
      expect(corner.r, greaterThan(0.8));
      expect(corner.b, lessThan(0.2));
    });

    testWidgets('markup ink is burned into the file', (tester) async {
      final source = await _twoTone(tester, 200, 200);
      addTearDown(source.dispose);

      final edit = PhotoEdit()
        ..markup.add(PhotoStroke(
          color: 0xFF00FF00,
          width: 0.25,
          points: const [Offset(0.7, 0.2), Offset(0.7, 0.8)],
        ));
      final (ink, _) = await _renderAt(tester, source, edit, 0.7, 0.5);
      expect(ink.g, greaterThan(0.8), reason: 'the stroke should be there');
      expect(ink.b, lessThan(0.3));

      // …and only there.
      final (clear, _) = await _renderAt(tester, source, edit, 0.2, 0.5);
      expect(clear.r, greaterThan(0.8));
    });

    testWidgets('the eraser takes ink off without taking the photo with it',
        (tester) async {
      final source = await _twoTone(tester, 200, 200);
      addTearDown(source.dispose);

      final edit = PhotoEdit()
        ..markup.add(PhotoStroke(
          color: 0xFF00FF00,
          width: 0.25,
          points: const [Offset(0.7, 0.2), Offset(0.7, 0.8)],
        ))
        ..markup.add(PhotoStroke(
          erase: true,
          width: 0.4,
          points: const [Offset(0.7, 0.2), Offset(0.7, 0.8)],
        ));
      final (rubbed, _) = await _renderAt(tester, source, edit, 0.7, 0.5);
      expect(rubbed.g, lessThan(0.3), reason: 'the ink should be gone');
      expect(rubbed.b, greaterThan(0.8), reason: 'the photo should not be');
      expect(rubbed.a, greaterThan(0.99), reason: 'and it should be opaque');
    });

    testWidgets('the healing brush only softens where it was dabbed',
        (tester) async {
      final source = await _twoTone(tester, 200, 200);
      addTearDown(source.dispose);

      final edit = PhotoEdit()
        ..retouchStrength = 1
        ..retouch.add(PhotoStroke(
          width: 0.4,
          points: const [Offset(0.5, 0.5)],
        ));
      // On the seam, under the dab: the blur pulls the two halves together.
      final (soft, _) = await _renderAt(tester, source, edit, 0.49, 0.5);
      expect(soft.b, greaterThan(0.1));
      // Far from it, the seam is still a hard edge.
      final (hard, _) = await _renderAt(tester, source, edit, 0.49, 0.05);
      expect(hard.b, lessThan(0.05));
    });
  });

  group('the overlays', () {
    testWidgets('a text layer is burned into the file', (tester) async {
      final source = await _twoTone(tester, 200, 200);
      addTearDown(source.dispose);

      final edit = PhotoEdit()
        ..texts.add(TextLayer(
          start: Duration.zero,
          duration: const Duration(hours: 6),
          text: 'HELLO',
          fontSize: 90,
          backgroundColor: 0xFF00FF00,
          backgroundPadding: 40,
        ));
      final (colour, _) = await _renderAt(tester, source, edit, 0.5, 0.5);
      expect(colour.g, greaterThan(0.5), reason: 'the caption backdrop');
    });

    testWidgets('a sticker shape is burned into the file', (tester) async {
      final source = await _twoTone(tester, 200, 200);
      addTearDown(source.dispose);

      final edit = PhotoEdit()
        ..stickers.add(StickerLayer(
          start: Duration.zero,
          duration: const Duration(hours: 6),
          content: 'square',
          isEmoji: false,
          color: 0xFF00FF00,
          size: 600,
        ));
      final (colour, _) = await _renderAt(tester, source, edit, 0.5, 0.5);
      expect(colour.g, greaterThan(0.8));
    });

    testWidgets('an enabled watermark is burned in, a disabled one is not',
        (tester) async {
      final source = await _twoTone(tester, 200, 200);
      addTearDown(source.dispose);

      final edit = PhotoEdit()
        ..watermark = Watermark(
          enabled: true,
          text: 'BRAND',
          fontSize: 80,
          backgroundColor: 0xFF00FF00,
          backgroundPadding: 40,
          transform: LayerTransform(x: 0.5, y: 0.5),
        );
      final (marked, _) = await _renderAt(tester, source, edit, 0.5, 0.5);
      expect(marked.g, greaterThan(0.5));

      edit.watermark.enabled = false;
      final (bare, _) = await _renderAt(tester, source, edit, 0.5, 0.5);
      expect(bare.g, lessThan(0.2));
    });

    testWidgets('an overlay is hit where it is drawn and not beside it',
        (tester) async {
      final layer = TextLayer(
        start: Duration.zero,
        duration: const Duration(hours: 6),
        text: 'TAP',
        fontSize: 80,
      )..transform.x = 0.25;
      const size = Size(400, 400);
      final rect = PhotoRenderer.overlayRect(size, layer);
      expect(rect.center.dx, closeTo(100, 0.5));
      expect(PhotoRenderer.hitTest(size, layer, rect.center), isTrue);
      expect(
        PhotoRenderer.hitTest(size, layer, const Offset(380, 380)),
        isFalse,
      );
    });
  });

  group('the portrait pass', () {
    test('the sliders are off until they are asked for', () {
      final face = FaceEnhance();
      expect(face.isNeutral, isTrue);
      face.auto();
      expect(face.isNeutral, isFalse);
      face.reset();
      expect(face.isNeutral, isTrue);
    });

    testWidgets('a photo with no skin in it is left exactly as it was',
        (tester) async {
      final source = await _twoTone(tester, 120, 120);
      addTearDown(source.dispose);

      // Red and blue are both outside the chrominance window skin sits in.
      final mask = await tester.runAsync(() => FaceEnhancer.skinMask(source));
      expect(mask, isNull);

      final edit = PhotoEdit()..face.auto();
      final (colour, _) = await _renderAt(tester, source, edit, 0.25, 0.5);
      expect(colour.r, greaterThan(0.95), reason: 'no mask, no retouch');
    });

    testWidgets('skin is found, and only where it is', (tester) async {
      final source = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(const Rect.fromLTWH(0, 0, 120, 120),
            Paint()..color = const Color(0xFF203040));
        // A patch of a complexion, big enough to count as a face.
        canvas.drawRect(const Rect.fromLTWH(0, 0, 120, 60),
            Paint()..color = const Color(0xFFDCAA8C));
        final picture = recorder.endRecording();
        final image = await picture.toImage(120, 120);
        picture.dispose();
        return image;
      });
      final photo = source!;
      addTearDown(photo.dispose);

      final found = await tester.runAsync(() => FaceEnhancer.skinMask(photo));
      expect(found, isNotNull);
      final mask = found!;
      addTearDown(mask.dispose);

      final alpha = await tester.runAsync(() async {
        final data = await mask.toByteData(format: ui.ImageByteFormat.rawRgba);
        final px = data!.buffer.asUint8List();
        int at(double fx, double fy) {
          final x = (fx * mask.width).clamp(0, mask.width - 1).toInt();
          final y = (fy * mask.height).clamp(0, mask.height - 1).toInt();
          return px[(y * mask.width + x) * 4 + 3];
        }

        return (at(0.5, 0.2), at(0.5, 0.9));
      });
      expect(alpha!.$1, greaterThan(200), reason: 'the face is skin');
      expect(alpha.$2, lessThan(60), reason: 'the background is not');
    });
  });

  group('an edit that carries layers', () {
    test('counts as dirty once anything is put on the picture', () {
      final e = PhotoEdit();
      expect(e.isClean, isTrue);
      e.markup.add(PhotoStroke(points: const [Offset(0.5, 0.5)]));
      expect(e.isClean, isFalse);
      e.markup.clear();

      e.face.auto();
      expect(e.isClean, isFalse);
      e.face.reset();

      e.watermark
        ..enabled = true
        ..text = 'Brand';
      expect(e.isClean, isFalse);
    });

    test('a copy shares nothing with the edit it came from', () {
      final e = PhotoEdit()
        ..markup.add(PhotoStroke(points: const [Offset(0.1, 0.1)]))
        ..pixelate.add(PhotoStroke(points: const [Offset(0.2, 0.2)]))
        ..texts.add(TextLayer(
          start: Duration.zero,
          duration: const Duration(hours: 6),
          text: 'one',
        ))
        ..watermark.text = 'before';

      final copy = e.copy();
      // The ids survive, so an undo hands back the same overlay the stage
      // had selected rather than a twin of it.
      expect(copy.texts.single.id, e.texts.single.id);

      copy.markup.single.points.add(const Offset(0.9, 0.9));
      copy.texts.single.text = 'two';
      copy.texts.single.transform.x = 0.1;
      copy.watermark.text = 'after';
      copy.pixelate.clear();
      copy.face.smooth = 1;

      expect(e.markup.single.points.length, 1);
      expect(e.texts.single.text, 'one');
      expect(e.texts.single.transform.x, 0.5);
      expect(e.watermark.text, 'before');
      expect(e.pixelate.length, 1);
      expect(e.face.smooth, 0);
    });
  });

  group('the image editor screen', () {
    testWidgets('offers every tool and swaps the panel under it',
        (tester) async {
      await tester
          .pumpWidget(_host(const ImageEditorScreen(path: '/nonexistent.jpg')));
      await tester.pump(const Duration(milliseconds: 300));

      for (final tool in const [
        'Core',
        'Adjust',
        'Filter',
        'AI Face',
        'Markup',
        'Text',
        'Watermark',
        'Pixelate',
        'Retouch',
        'Stickers',
      ]) {
        expect(find.text(tool), findsWidgets, reason: '$tool is missing');
      }
      // The core tool opens first, so its ratio row is the one on screen.
      expect(find.text('1:1'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);

      await _tapTool(tester, 'Filter');
      expect(find.text('Kodak'), findsOneWidget);
      expect(find.text('1:1'), findsNothing);

      await _tapTool(tester, 'Adjust');
      expect(find.text('Brightness'), findsOneWidget);
      expect(find.text('Sharpen'), findsOneWidget);

      await _tapTool(tester, 'Stickers');
      expect(find.text('Faces'), findsOneWidget);
      expect(find.text('Brightness'), findsNothing);
    });

    testWidgets('every tool panel fits the smallest and largest windows',
        (tester) async {
      const windows = [
        Size(320, 568),
        Size(390, 844),
        Size(844, 390),
        Size(1440, 900),
      ];
      for (final window in windows) {
        for (final scale in const [1.0, 1.3]) {
          tester.view.physicalSize = window;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(
                size: window,
                textScaler: TextScaler.linear(scale),
              ),
              child: const ImageEditorScreen(path: '/nonexistent.jpg'),
            ),
          ));
          await tester.pump(const Duration(milliseconds: 200));

          for (final tool in const [
            'Filter',
            'Adjust',
            'AI Face',
            'Markup',
            'Text',
            'Watermark',
            'Pixelate',
            'Retouch',
            'Stickers',
            'Core',
          ]) {
            await _tapTool(tester, tool);
            expect(
              tester.takeException(),
              isNull,
              reason: 'the $tool panel broke at '
                  '${window.width}x${window.height} @ ${scale}x',
            );
          }
        }
      }
    });


    testWidgets('a sticker is placed, selected, and can be taken off again',
        (tester) async {
      await tester
          .pumpWidget(_host(const ImageEditorScreen(path: '/nonexistent.jpg')));
      await tester.pump(const Duration(milliseconds: 300));

      await _tapTool(tester, 'Stickers');
      expect(find.text('Delete'), findsNothing);
      expect(find.textContaining('Tap a sticker'), findsOneWidget);

      await tester.tap(find.text('😀'));
      await tester.pump();
      // Placing one selects it, so the size and opacity of that sticker are
      // what the panel is now about.
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('Opacity'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pump();
      expect(find.text('Delete'), findsNothing);
      expect(find.textContaining('Tap a sticker'), findsOneWidget);

      // And one placed by mistake goes away with the undo button, selection
      // and all.
      await tester.tap(find.text('😂'));
      await tester.pump();
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('adding text asks for the words', (tester) async {
      await tester
          .pumpWidget(_host(const ImageEditorScreen(path: '/nonexistent.jpg')));
      await tester.pump(const Duration(milliseconds: 300));

      await _tapTool(tester, 'Text');
      expect(find.textContaining('Add a caption'), findsOneWidget);

      await tester.tap(find.text('Add text'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.tap(find.text('Done'));
      await tester.pump(const Duration(milliseconds: 400));

      // The caption is painted on the picture rather than laid out as a
      // widget, so what proves it landed is that the panel has swapped its
      // prompt for the controls of the caption now selected.
      expect(find.textContaining('Add a caption'), findsNothing);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('Opacity'), findsOneWidget);
    });

    testWidgets('a caption typed empty is a caption deleted', (tester) async {
      await tester
          .pumpWidget(_host(const ImageEditorScreen(path: '/nonexistent.jpg')));
      await tester.pump(const Duration(milliseconds: 300));

      await _tapTool(tester, 'Text');
      await tester.tap(find.text('Add text'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Done'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Size'), findsNothing);
      expect(find.textContaining('Add a caption'), findsOneWidget);
    });

    testWidgets('the watermark is off until it is switched on', (tester) async {
      await tester
          .pumpWidget(_host(const ImageEditorScreen(path: '/nonexistent.jpg')));
      await tester.pump(const Duration(milliseconds: 300));

      await _tapTool(tester, 'Watermark');
      // The nine placements scroll, so only the first of them is on screen.
      expect(find.text('Top left'), findsOneWidget);
      expect(find.textContaining('The mark is off'), findsOneWidget);

      await tester.tap(find.text('Off'));
      await tester.pump();
      expect(find.text('On'), findsOneWidget);
      expect(find.textContaining('Drag the mark'), findsOneWidget);
    });

    testWidgets('the brushes offer their own controls', (tester) async {
      await tester
          .pumpWidget(_host(const ImageEditorScreen(path: '/nonexistent.jpg')));
      await tester.pump(const Duration(milliseconds: 300));

      await _tapTool(tester, 'Markup');
      expect(find.text('Draw'), findsOneWidget);
      expect(find.text('Erase'), findsOneWidget);
      expect(find.text('Brush'), findsOneWidget);

      await _tapTool(tester, 'Pixelate');
      expect(find.text('Mosaic'), findsOneWidget);
      expect(find.text('Blur'), findsOneWidget);
      expect(find.text('Block size'), findsOneWidget);

      await tester.tap(find.text('Blur'));
      await tester.pump();
      // The slider is the same one, renamed for what it now does.
      expect(find.text('Block size'), findsNothing);

      await _tapTool(tester, 'Retouch');
      expect(find.text('Strength'), findsOneWidget);

      await _tapTool(tester, 'AI Face');
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Smooth'), findsOneWidget);
      expect(find.text('Even tone'), findsOneWidget);
    });

    testWidgets('an edit can be undone and redone', (tester) async {
      await tester
          .pumpWidget(_host(const ImageEditorScreen(path: '/nonexistent.jpg')));
      await tester.pump(const Duration(milliseconds: 300));

      await _tapTool(tester, 'Filter');
      await tester.tap(find.text('Kodak'));
      await tester.pump();
      // The intensity slider only exists once a look is on the photo.
      expect(find.text('Intensity'), findsOneWidget);

      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(find.text('Intensity'), findsNothing);

      await tester.tap(find.byTooltip('Redo'));
      await tester.pump();
      expect(find.text('Intensity'), findsOneWidget);
    });
  });
}
