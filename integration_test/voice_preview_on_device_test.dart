import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/data/services/voice_preview.dart';

/// Whether Voice Enhance and the voice changer actually reach the ear in the
/// preview, on the device, through the real FFmpeg.
///
/// Both used to be export-only: the slider moved, the file came out treated,
/// and the preview played the untouched track. Checking that a treated copy
/// *exists* would not have caught that — the copy has to sound different
/// from the source, so these measure it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String quiet;

  setUpAll(() async {
    dir = Directory('${(await getTemporaryDirectory()).path}/voice_preview');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);

    // A deliberately quiet tone: Voice Enhance ends in `loudnorm`, so a
    // source well below its target is one whose treatment is measurable.
    quiet = '${dir.path}/quiet.mp4';
    final ok = await _run(
      '-hide_banner -y '
      '-f lavfi -i testsrc=size=320x568:rate=15:duration=3 '
      '-f lavfi -i "sine=frequency=440:duration=3,volume=0.03" '
      '-shortest -c:v libx264 -preset ultrafast -pix_fmt yuv420p '
      '-c:a aac -ar 48000 "$quiet"',
    );
    expect(ok, isTrue, reason: 'could not render the test clip');
  });

  setUp(VoicePreview.reset);

  VideoClip clip({bool enhance = false, VoiceEffect fx = VoiceEffect.none}) =>
      VideoClip(
        path: quiet,
        isImage: false,
        sourceDuration: const Duration(seconds: 3),
        voiceEnhance: enhance,
        voiceEffect: fx,
      );

  testWidgets('an untreated clip is played as it is', (tester) async {
    expect(await VoicePreview.ensure(clip()), isNull);
    expect(VoicePreview.ready(clip()), isNull);
  });

  testWidgets('Voice Enhance is audibly louder than the source', (
    tester,
  ) async {
    final path = await VoicePreview.ensure(clip(enhance: true));
    expect(path, isNotNull, reason: 'no treated copy was made');
    expect(File(path!).lengthSync(), greaterThan(1000));

    final before = await _meanVolume(quiet);
    final after = await _meanVolume(path);
    expect(before, isNotNull);
    expect(after, isNotNull);
    // `loudnorm=I=-16` on a tone at 3% is a lift of many decibels; 6 is well
    // clear of measurement noise and well short of the real change.
    expect(
      after!,
      greaterThan(before! + 6),
      reason: 'enhance left the level where it was',
    );
  });

  testWidgets('the voice changer keeps the clip the same length', (
    tester,
  ) async {
    final path = await VoicePreview.ensure(clip(fx: VoiceEffect.chipmunk));
    expect(path, isNotNull);
    final source = await _durationOf(quiet);
    final treated = await _durationOf(path!);
    expect(source, isNotNull);
    expect(treated, isNotNull);
    // `atempo` puts back the time `asetrate` took, which is what lets the
    // preview seek the copy to the same position as the picture.
    expect((treated! - source!).abs(), lessThan(0.15));
  });

  testWidgets('a second effect makes its own copy', (tester) async {
    final chipmunk = await VoicePreview.ensure(clip(fx: VoiceEffect.chipmunk));
    final deep = await VoicePreview.ensure(clip(fx: VoiceEffect.deep));
    expect(chipmunk, isNotNull);
    expect(deep, isNotNull);
    expect(deep, isNot(chipmunk), reason: 'the old sound was reused');
  });

  testWidgets('the copy is made once and then reused', (tester) async {
    final first = await VoicePreview.ensure(clip(enhance: true));
    expect(VoicePreview.ready(clip(enhance: true)), first);
  });
}

Future<bool> _run(String command) async {
  final session = await FFmpegKit.execute(command);
  return ReturnCode.isSuccess(await session.getReturnCode());
}

/// The mean level FFmpeg reports for a file, in dBFS.
Future<double?> _meanVolume(String path) async {
  final session = await FFmpegKit.execute(
    '-hide_banner -i "$path" -af volumedetect -f null -',
  );
  final logs = await session.getAllLogsAsString() ?? '';
  final m = RegExp(r'mean_volume:\s*(-?[\d.]+) dB').firstMatch(logs);
  return m == null ? null : double.parse(m.group(1)!);
}

/// How long a file's audio runs, in seconds.
Future<double?> _durationOf(String path) async {
  final session = await FFmpegKit.execute('-hide_banner -i "$path" -f null -');
  final logs = await session.getAllLogsAsString() ?? '';
  final m = RegExp(r'time=(\d+):(\d+):([\d.]+)').allMatches(logs).lastOrNull;
  if (m == null) return null;
  return int.parse(m.group(1)!) * 3600 +
      int.parse(m.group(2)!) * 60 +
      double.parse(m.group(3)!);
}
