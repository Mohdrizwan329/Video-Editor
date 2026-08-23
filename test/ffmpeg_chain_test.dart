import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/data/models/adjustments.dart';
import 'package:video_editor/data/models/filter_preset.dart';

/// Hands every export chain to a real FFmpeg.
///
/// The library tests check that a fragment is non-empty and has no blank
/// links — but a fragment can be perfectly shaped as a *string* and still be
/// rejected by the binary. That is not a hypothetical: `curves` separates its
/// points with spaces, and writing them with a colon instead built a chain
/// that read fine, passed every test here, and failed every export of the
/// forty-nine looks that carry a fade.
///
/// Skipped when FFmpeg is not on the PATH, so a machine without it still runs
/// the rest of the suite. The device suite in `integration_test/` runs the
/// same sweep against the FFmpeg the app actually ships with.
void main() {
  final ffmpeg = _which('ffmpeg');

  group(
    'the export chains FFmpeg is given',
    () {
      /// Runs [chain] over a generated frame and returns FFmpeg's complaint,
      /// or null when it was accepted.
      Future<String?> reject(String chain) async {
        final r = await Process.run(ffmpeg!, [
          '-hide_banner',
          '-nostdin',
          '-y',
          '-f',
          'lavfi',
          '-i',
          'testsrc=size=64x64:d=1',
          '-vf',
          chain,
          '-frames:v',
          '1',
          '-f',
          'null',
          '-',
        ]);
        if (r.exitCode == 0) return null;
        final err = (r.stderr as String).trim().split('\n');
        return err.sublist(err.length > 3 ? err.length - 3 : 0).join(' | ');
      }

      test('every look on its own', () async {
        final failed = <String>[];
        for (final look in FilterLibrary.all.where((f) => f.id != 'none')) {
          final chain = look.toFFmpegFilter();
          final error = await reject(chain);
          if (error != null) failed.add('${look.id}: $chain\n    $error');
        }
        expect(
          failed,
          isEmpty,
          reason: 'these looks would fail an export:\n${failed.join('\n')}',
        );
      }, timeout: const Timeout(Duration(minutes: 5)));

      test(
        'every look with the sliders pushed to their limits',
        () async {
          // The exporter never emits a preset alone: it emits the preset folded
          // together with the Adjust panel, plus the extras that have no matrix
          // equivalent. That whole string is what has to parse.
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
            final error = await reject(chain);
            if (error != null) failed.add('${look.id}: $chain\n    $error');
          }
          expect(
            failed,
            isEmpty,
            reason:
                'these fail with the Adjust panel at its ends:\n'
                '${failed.join('\n')}',
          );
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    },
    skip: ffmpeg == null
        ? 'ffmpeg is not on the PATH; the device suite covers this'
        : null,
  );
}

String? _which(String bin) {
  try {
    final r = Process.runSync('which', [bin]);
    if (r.exitCode != 0) return null;
    final path = (r.stdout as String).trim();
    return path.isEmpty ? null : path;
  } catch (_) {
    return null;
  }
}
