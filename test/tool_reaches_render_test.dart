import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/data/models/adjustments.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/data/services/export_service.dart';
import 'package:video_editor/data/services/export_settings.dart';

/// Every clip tool has to reach the render.
///
/// The device sweep proves each button answers; it cannot prove the answer
/// goes anywhere. A field can be written by its panel, kept in the JSON and
/// read back into the model, and still be seen by no renderer at all — which
/// is what clip animation was. From the outside that is a tool that does not
/// work, and it is the kind that survives every test that only presses
/// things.
void main() {
  Project projectWith(void Function(VideoClip) setUp, {int clips = 1}) {
    final p = Project(
      name: 'probe',
      ratio: CanvasRatio.r9x16,
      clips: [
        for (var i = 0; i < clips; i++)
          VideoClip(
            path: '/nonexistent/c$i.mp4',
            isImage: false,
            sourceDuration: const Duration(seconds: 4),
          ),
      ],
    );
    setUp(p.clips.first);
    return p;
  }

  String commandFor(void Function(VideoClip) setUp, {int clips = 1}) =>
      ExportService.debugCommandFor(
        projectWith(setUp, clips: clips),
        ExportSettings(),
      );

  /// What the graph looks like with nothing touched, so a test can tell a
  /// filter the tool added from one that was always there.
  late String plain;

  setUpAll(() => plain = commandFor((_) {}));

  void reaches(
    String tool,
    void Function(VideoClip) setUp,
    String expected, {
    int clips = 1,
  }) {
    test('$tool reaches the render', () {
      final command = commandFor(setUp, clips: clips);
      expect(
        command,
        contains(expected),
        reason: '$tool wrote its value and the exporter never used it',
      );
      expect(
        plain.contains(expected),
        isFalse,
        reason: 'the graph carries "$expected" even untouched, so this '
            'assertion proves nothing about $tool',
      );
    });
  }

  // `setpts=PTS-STARTPTS` is in every chain, so the speed change has to be
  // matched by the form only a rate change produces.
  reaches('Speed', (c) => c.speed = 2, 'setpts=PTS/');
  reaches('Rotate', (c) => c.rotation = 90, 'transpose');
  reaches('Mirror', (c) => c.mirrored = true, 'hflip');
  reaches('Crop', (c) => c.cropLeft = 0.1, 'crop=iw*');
  reaches('Stabilizer', (c) => c.stabilize = true, 'deshake');
  reaches('Enhance', (c) => c.enhance = true, 'unsharp');
  reaches('Ease', (c) => c.fadeIn = const Duration(seconds: 1), 'fade=t=in');
  reaches('Opacity', (c) => c.opacity = 0.5, 'format=yuva420p');
  reaches('Chroma', (c) => c.chromaKeyColor = 0xFF00FF00, 'chromakey');
  reaches('Mask', (c) => c.maskShape = MaskShape.circle, 'geq');
  reaches('Filter', (c) => c.filterId = 'kodak', 'eq=brightness');
  reaches(
    'Adjust — grain',
    (c) => c.adjustments = Adjustments(grain: 0.5),
    'noise=alls',
  );
  reaches(
    'Adjust — film grain',
    (c) => c.adjustments = Adjustments(filmGrain: 0.5),
    'noise=c0s',
  );
  reaches(
    'Adjust — colour cast',
    (c) => c.adjustments = Adjustments(
      colorCastHue: 0.1,
      colorCastAmount: 0.5,
    ),
    'colorchannelmixer',
  );
  reaches(
    'Adjust — curves',
    (c) => c.adjustments = Adjustments(curveMid: 0.5),
    'curves=all',
  );
  reaches(
    'Adjust — blur',
    (c) => c.adjustments = Adjustments(blur: 0.5),
    'gblur',
  );
  reaches(
    'Adjust — denoise',
    (c) => c.adjustments = Adjustments(denoise: 0.5),
    'hqdn3d',
  );
  reaches('Animation', (c) => c.animationIn = LayerAnimation.fade, 'fade');
  reaches(
    'Transition',
    (c) => c.transitionType = TransitionType.fade,
    'xfade',
    clips: 2,
  );

  test('Reverse is baked rather than filtered, so the flag survives it', () {
    // Reverse renders the clip to a new file up front; the graph only has to
    // not undo that. This is here so the tool is not silently uncovered.
    final command = commandFor((c) => c.reversed = true);
    expect(command, contains('reverse'));
  });
}
