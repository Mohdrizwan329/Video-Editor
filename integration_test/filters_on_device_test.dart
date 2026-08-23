import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:video_editor/data/models/adjustments.dart';
import 'package:video_editor/data/models/filter_preset.dart';
import 'package:video_editor/data/models/video_effect.dart';
import 'package:video_editor/data/services/overlay_rasterizer.dart';

/// What the host test suite cannot answer.
///
/// Every filter is checked twice on the way in: the widget tests prove the
/// colour matrix reaches the preview, and the library tests prove the FFmpeg
/// fragment is non-empty and well formed *as a string*. Neither of those
/// runs FFmpeg. A fragment can be perfectly shaped and still be rejected by
/// the binary — an option that does not exist in this build, a value outside
/// the filter's range — and the first anyone would know is a failed export.
///
/// So this suite hands every fragment to the real FFmpeg on the real device,
/// one filter at a time, and does the same for the effect loops, which need
/// a temp directory the host tests do not have either.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String source;

  /// A frame with something in every tonal range, so a grade has shadows,
  /// skin, saturated colour and highlights to actually act on.
  Future<String> writeSource(Directory dir) async {
    const w = 480, h = 854;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF6E4),
            Color(0xFFF0C08A),
            Color(0xFFE86A5C),
            Color(0xFF4A5FA8),
            Color(0xFF14202E),
          ],
          stops: [0, 0.24, 0.5, 0.76, 1],
        ).createShader(rect),
    );
    for (var i = 0; i < 6; i++) {
      canvas.drawCircle(
        Offset(80.0 + i * 62, 300.0 + (i.isEven ? 90 : -90)),
        44,
        Paint()..color = Color(0xFF000000 | (0x111111 * (i + 1) * 3)),
      );
    }
    final image = await recorder.endRecording().toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('${dir.path}/probe_source.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    return file.path;
  }

  /// Runs [command] and returns null on success, or FFmpeg's own complaint.
  Future<String?> run(String command) async {
    final session = await FFmpegKit.execute(command);
    final code = await session.getReturnCode();
    if (ReturnCode.isSuccess(code)) return null;
    final log = await session.getOutput() ?? '';
    // The tail is where the rejection is; the head is banner and probing.
    final lines = log.trim().split('\n');
    return lines.sublist(lines.length > 6 ? lines.length - 6 : 0).join(' | ');
  }

  setUpAll(() async {
    dir = Directory('${(await getTemporaryDirectory()).path}/filter_probe');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    source = await writeSource(dir);
  });

  testWidgets(
    'every colour grade is accepted by this device\'s FFmpeg',
    (tester) async {
      final looks = FilterLibrary.all.where((f) => f.id != 'none').toList();
      final failed = <String>[];
      var checked = 0;

      for (final look in looks) {
        final chain = look.toFFmpegFilter();
        final out = '${dir.path}/grade_${look.id}.jpg';
        final error = await run(
          '-hide_banner -y -i "$source" '
          '-vf "$chain" -frames:v 1 "$out"',
        );
        if (error != null) {
          failed.add('${look.id} (${look.category}): $chain -> $error');
          continue;
        }
        // A command can exit zero and still write nothing worth having.
        final file = File(out);
        if (!file.existsSync() || file.lengthSync() < 512) {
          failed.add(
            '${look.id}: wrote '
            '${file.existsSync() ? file.lengthSync() : 0} bytes',
          );
          continue;
        }
        checked++;
      }

      // Counted only where the frame actually landed, so the line cannot read
      // like a pass while the list below says otherwise.
      debugPrint('FFmpeg rendered $checked/${looks.length} grades');
      expect(
        failed,
        isEmpty,
        reason:
            'these looks would fail an export:\n'
            '${failed.join('\n')}',
      );
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );

  testWidgets(
    'every grade survives the manual sliders on top of it',
    (tester) async {
      // The exporter never emits a preset alone — it emits the preset folded
      // together with the Adjust panel's values, and that is the chain that has
      // to parse. Pushed to the ends, where the numbers are most likely to run
      // out of a filter's range.
      final adj = Adjustments(
        brightness: 1,
        contrast: 1,
        saturation: 1,
        temperature: 1,
        tint: -1,
        highlights: -1,
        shadows: 1,
        hue: 1,
        fade: 1,
        vignette: 1,
        curveLow: 1,
        curveMid: -1,
        curveHigh: 1,
        sharpen: 1,
        grain: 1,
        blur: 1,
        denoise: 1,
      );
      final failed = <String>[];

      for (final look in FilterLibrary.all) {
        final chain = [
          adj.merge(look.lerpFromIdentity(1)).toFFmpegFilter(),
          ...adj.toFFmpegExtras(),
        ].where((p) => p.isNotEmpty).join(',');
        final out = '${dir.path}/full_${look.id}.jpg';
        final error = await run(
          '-hide_banner -y -i "$source" '
          '-vf "$chain" -frames:v 1 "$out"',
        );
        if (error != null) failed.add('${look.id}: $chain -> $error');
      }

      expect(
        failed,
        isEmpty,
        reason:
            'these looks fail once the Adjust panel '
            'is pushed to its limits:\n${failed.join('\n')}',
      );
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );

  testWidgets(
    'every effect bakes its loop and the renderer can read it',
    (tester) async {
      // rasterizeFx writes into the app's temp directory, which is why this
      // cannot run on the host at all.
      final failed = <String>[];

      for (final fx in FxLibrary.all.where((f) => !f.isNone)) {
        final baked = await OverlayRasterizer.instance.rasterizeFx(
          fx,
          1,
          outWidth: 480,
          outHeight: 854,
        );
        if (baked == null) {
          failed.add('${fx.id}: baked nothing');
          continue;
        }
        if (fx.isAnimated) {
          if (!baked.isSequence || baked.frameCount != fx.frameCount) {
            failed.add(
              '${fx.id}: expected ${fx.frameCount} frames, '
              'got ${baked.frameCount}',
            );
            continue;
          }
          // Every frame of the strip has to be on disk under the name the
          // `%03d` pattern will look for, or FFmpeg stops at the gap.
          for (var i = 0; i < baked.frameCount; i++) {
            final f = File(
              baked.path.replaceAll('%03d', i.toString().padLeft(3, '0')),
            );
            if (!f.existsSync() || f.lengthSync() < 128) {
              failed.add('${fx.id}: frame $i missing or empty');
              break;
            }
          }
        } else if (baked.isSequence) {
          failed.add('${fx.id}: a still effect baked a sequence');
        }

        // And the input form the exporter builds has to actually decode.
        final rate = baked.isSequence ? baked.frameRate : 30;
        final out = '${dir.path}/fx_${fx.id}.mp4';
        final error = await run(
          '-hide_banner -y -f lavfi -t 2 -i color=c=gray:s=480x854:r=30 '
          '-loop 1 -framerate $rate -i "${baked.path}" '
          '-filter_complex "[1:v] format=rgba [fx];[0:v][fx] overlay=0:0:format=auto [v]" '
          '-map "[v]" -c:v libx264 -pix_fmt yuv420p -t 2 "$out"',
        );
        if (error != null) {
          failed.add('${fx.id}: renderer rejected the loop -> $error');
        } else {
          final file = File(out);
          if (!file.existsSync() || file.lengthSync() < 1024) {
            failed.add('${fx.id}: overlay produced no video');
          }
        }
      }

      expect(
        failed,
        isEmpty,
        reason: 'these effects would not export:\n${failed.join('\n')}',
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
