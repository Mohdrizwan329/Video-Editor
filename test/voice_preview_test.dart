import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/data/services/voice_preview.dart';

/// Whether the preview knows it has to treat a clip's audio, and whether it
/// can tell one treatment from another.
///
/// Getting this wrong is silent in both directions: too eager and a plain
/// clip is muted waiting for a bake it does not need, too lazy and the voice
/// changer stays an export-only tool.
void main() {
  VideoClip clip({bool enhance = false, VoiceEffect fx = VoiceEffect.none}) =>
      VideoClip(
        path: '/tmp/a.mp4',
        isImage: false,
        sourceDuration: const Duration(seconds: 3),
        voiceEnhance: enhance,
        voiceEffect: fx,
      );

  test('a clip with neither tool on is played as it is', () {
    expect(clip().hasVoiceWork, isFalse);
    expect(VoicePreview.ready(clip()), isNull);
  });

  test('either tool alone is enough to want a treated copy', () {
    expect(clip(enhance: true).hasVoiceWork, isTrue);
    expect(clip(fx: VoiceEffect.chipmunk).hasVoiceWork, isTrue);
  });

  test('the treatment is the same one the render applies', () {
    final chain = clip(enhance: true, fx: VoiceEffect.chipmunk)
        .audioFilterChain()
        .join(',');
    // Clean-up first, then the shift — the order the exporter emits.
    expect(chain, contains('afftdn'));
    expect(chain, contains('asetrate'));
    expect(
      chain.indexOf('afftdn'),
      lessThan(chain.indexOf('asetrate')),
    );
  });

  test('changing the effect asks for a different copy', () {
    expect(
      clip(fx: VoiceEffect.chipmunk).audioFilterChain(),
      isNot(clip(fx: VoiceEffect.deep).audioFilterChain()),
    );
  });
}
