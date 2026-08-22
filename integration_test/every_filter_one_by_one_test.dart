import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:video_editor/data/models/filter_preset.dart';
import 'package:video_editor/data/models/video_effect.dart';
import 'package:video_editor/data/services/effect_painter.dart';
import 'package:video_editor/data/services/overlay_rasterizer.dart';

/// Runs every look and every effect on the device, one at a time, and puts
/// the two halves of the app's central promise side by side: the colour the
/// *preview* paints and the colour the *renderer* writes into the file.
///
/// The preview grades with a 4x5 colour matrix and the exporter grades with
/// an FFmpeg chain. They are two implementations of one look, and nothing
/// until now has ever compared their output — only that each was individually
/// willing to run. A look whose two halves disagree is a look that lies to
/// the person choosing it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  /// Colours to grade: a shadow, a skin tone, a saturated red, a sky, a
  /// near-white. Between them they cover the ranges the looks pull apart.
  const probes = <(String, int, int, int)>[
    ('shadow', 34, 38, 46),
    ('skin', 214, 172, 140),
    ('red', 198, 62, 48),
    ('sky', 74, 118, 190),
    ('white', 238, 240, 236),
  ];

  /// The preview's own maths, on the device's own Skia: a patch of [rgb]
  /// drawn through the preset's colour matrix, read back.
  Future<List<int>> previewPixel(FilterPreset look, (String, int, int, int) p) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 16, 16),
      Paint()
        ..color = Color.fromARGB(255, p.$2, p.$3, p.$4)
        ..colorFilter = ui.ColorFilter.matrix(look.toColorMatrix()),
    );
    final image = await recorder.endRecording().toImage(16, 16);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    final px = data!.buffer.asUint8List();
    // The centre pixel, so nothing at an edge can be antialiased into it.
    const i = (8 * 16 + 8) * 4;
    return [px[i], px[i + 1], px[i + 2]];
  }

  /// The renderer's maths, on the device's own FFmpeg: the same patch put
  /// through the chain the exporter would emit, read back out of the file.
  Future<List<int>?> exportPixel(
      FilterPreset look, (String, int, int, int) p) async {
    final chain = look.toFFmpegFilter();
    final out = '${dir.path}/x_${look.id}_${p.$1}.png';
    final hex = '0x${p.$2.toRadixString(16).padLeft(2, '0')}'
        '${p.$3.toRadixString(16).padLeft(2, '0')}'
        '${p.$4.toRadixString(16).padLeft(2, '0')}';
    final vf = chain.isEmpty ? 'null' : chain;
    final session = await FFmpegKit.execute(
      '-hide_banner -y -f lavfi -i color=c=$hex:s=64x64:d=1 '
      '-vf "$vf" -frames:v 1 "$out"',
    );
    if (!ReturnCode.isSuccess(await session.getReturnCode())) return null;

    final bytes = await File(out).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final data =
        await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    final px = data!.buffer.asUint8List();
    const i = (32 * 64 + 32) * 4;
    return [px[i], px[i + 1], px[i + 2]];
  }

  setUpAll(() async {
    dir = Directory('${(await getTemporaryDirectory()).path}/one_by_one');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
  });

  testWidgets('every look, one at a time, preview against export',
      (tester) async {
    final dead = <String>[];
    final broken = <String>[];
    final drift = <String, int>{};

    await tester.runAsync(() async {
      for (final look in FilterLibrary.all) {
        var worst = 0;
        var moved = 0;
        final line = StringBuffer(look.id.padRight(18));

        for (final p in probes) {
          final preview = await previewPixel(look, p);
          final export = await exportPixel(look, p);
          if (export == null) {
            broken.add('${look.id}: FFmpeg refused "${look.toFFmpegFilter()}"');
            break;
          }
          final source = [p.$2, p.$3, p.$4];
          for (var c = 0; c < 3; c++) {
            final d = (preview[c] - export[c]).abs();
            if (d > worst) worst = d;
            final m = (preview[c] - source[c]).abs();
            if (m > moved) moved = m;
          }
          if (p.$1 == 'skin') {
            line.write(' skin ${preview.join(",").padRight(11)}'
                '-> ${export.join(",").padRight(11)}');
          }
        }

        drift[look.id] = worst;
        line.write(' worstDrift=$worst moved=$moved');
        debugPrint(line.toString());

        if (look.id != 'none' && moved == 0) {
          dead.add('${look.id} changed nothing on any probe colour');
        }
        if (look.id == 'none' && worst > 2) {
          broken.add('none drifted by $worst, so the baseline itself is off');
        }
      }
    });

    final ranked = drift.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    debugPrint('=== worst preview/export drift ===');
    for (final e in ranked.take(15)) {
      debugPrint('  ${e.key.padRight(18)} ${e.value}');
    }
    final over = ranked.where((e) => e.value > 24).map((e) => e.key).toList();
    debugPrint('looks drifting over 24/255: ${over.length}/${drift.length}');

    expect(broken, isEmpty, reason: broken.join('\n'));
    expect(dead, isEmpty, reason: dead.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 25)));

  testWidgets('every effect, one at a time', (tester) async {
    final failed = <String>[];

    await tester.runAsync(() async {
      for (final fx in FxLibrary.all.where((f) => !f.isNone)) {
        final baked = await OverlayRasterizer.instance
            .rasterizeFx(fx, 1, outWidth: 240, outHeight: 426);
        if (baked == null) {
          failed.add('${fx.id}: baked nothing');
          debugPrint('${fx.id.padRight(12)} FAILED to bake');
          continue;
        }

        // Two numbers per frame: how many pixels it marks, and a signature
        // of *which* ones. Area alone is not enough — snow keeps the same
        // number of flakes on every frame and moves all of them, so a check
        // on coverage would call it a still. The signature is what separates
        // moving from stopped.
        final lit = <int>[];
        final signature = <int>[];
        for (var i = 0; i < fx.frameCount; i++) {
          final recorder = ui.PictureRecorder();
          EffectPainter.paintFx(
              Canvas(recorder), const Size(120, 213), fx, 1, frame: i);
          final image = await recorder.endRecording().toImage(120, 213);
          final data =
              await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          image.dispose();
          final px = data!.buffer.asUint8List();
          var marked = 0;
          var hash = 17;
          for (var j = 0; j < px.length; j += 4) {
            if (px[j + 3] == 0) continue;
            marked++;
            // Position and colour both fold in, so a flake that moved and a
            // flake that changed shade are each a different signature.
            hash = (hash * 31 + j) & 0x3FFFFFFF;
            hash = (hash * 31 + px[j] + px[j + 1] + px[j + 2]) & 0x3FFFFFFF;
          }
          lit.add(marked);
          signature.add(hash);
        }

        final rate = baked.isSequence ? baked.frameRate : 30;
        final out = '${dir.path}/v_${fx.id}.mp4';
        final session = await FFmpegKit.execute(
          '-hide_banner -y -f lavfi -t 2 -i color=c=gray:s=240x426:r=30 '
          '-loop 1 -framerate $rate -i "${baked.path}" '
          '-filter_complex "[1:v] format=rgba [fx];'
          '[0:v][fx] overlay=0:0:format=auto [v]" '
          '-map "[v]" -c:v libx264 -pix_fmt yuv420p -t 2 "$out"',
        );
        final ok = ReturnCode.isSuccess(await session.getReturnCode()) &&
            File(out).existsSync() &&
            File(out).lengthSync() > 1024;

        final distinct = signature.toSet().length;
        debugPrint('${fx.id.padRight(12)} '
            '${fx.frameCount.toString().padLeft(2)} frames @${rate}fps  '
            'lit=${lit.first}..${lit.reduce((a, b) => a > b ? a : b)}  '
            'distinctFrames=$distinct/${fx.frameCount}  '
            'render=${ok ? "ok" : "FAILED"}');

        if (!ok) failed.add('${fx.id}: the renderer would not composite it');
        if (fx.isAnimated && distinct == 1) {
          failed.add('${fx.id}: all ${fx.frameCount} frames of the loop are '
              'the same picture, so it would export as a still');
        }
        if (lit.every((n) => n == 0)) {
          failed.add('${fx.id}: marked no pixels on any frame');
        }
      }
    });

    expect(failed, isEmpty, reason: failed.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 25)));
}
