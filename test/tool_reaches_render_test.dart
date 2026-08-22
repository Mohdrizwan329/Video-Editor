import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/data/models/adjustments.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/keyframe.dart';
import 'package:video_editor/data/models/layers.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/data/services/export_service.dart';
import 'package:video_editor/data/services/export_settings.dart';
import 'package:video_editor/data/services/overlay_rasterizer.dart';

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
        reason:
            'the graph carries "$expected" even untouched, so this '
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
    (c) => c.adjustments = Adjustments(colorCastHue: 0.1, colorCastAmount: 0.5),
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

  // ---------------------------------------------------------------- project

  /// A project the whole graph can be built from, so the tools that live
  /// above the clip — the canvas, the backdrop, the layers — are covered by
  /// the same question as the ones that live on it.
  Project blank({int clips = 1}) => Project(
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

  String commandOf(
    Project p, {
    Map<String, RasterizedLayer> rasterized = const {},
    Map<String, String> hslLuts = const {},
  }) => ExportService.debugCommandFor(
    p,
    ExportSettings(),
    rasterized: rasterized,
    hslLuts: hslLuts,
  );

  /// A stand-in for a baked PNG. The rasterizer needs a canvas to run, which
  /// a unit test has none of — but the graph only ever handles the result as
  /// a path and a size, so this is the whole of what it needs.
  RasterizedLayer baked() => RasterizedLayer(
    path: '/nonexistent/baked.png',
    width: 200,
    height: 100,
    centerX: 0.5,
    centerY: 0.5,
  );

  void projectReaches(String tool, Project Function() build, String expected) {
    test('$tool reaches the render', () {
      expect(
        commandOf(build()),
        contains(expected),
        reason: '$tool wrote its value and the exporter never used it',
      );
      expect(
        plain.contains(expected),
        isFalse,
        reason:
            'the graph carries "$expected" untouched, so this proves '
            'nothing about $tool',
      );
    });
  }

  test('Canvas reaches the render', () {
    // The ratio travels as the settings' canvasAspect — the export screen
    // fills that in from the project — so that is where the graph reads it.
    final square = ExportService.debugCommandFor(
      blank(),
      ExportSettings(canvasAspect: 1),
    );
    expect(square, contains('1080:1080'));
    expect(plain.contains('1080:1080'), isFalse);
  });

  projectReaches(
    'Backdrop',
    () => blank()..background = BackgroundStyle(type: BackgroundType.blur),
    'boxblur',
  );

  test('Effect — frame and texture reach the render', () {
    final p = blank()
      ..frameId = 'polaroid'
      ..fxId = 'grain';
    final command = commandOf(
      p,
      rasterized: {
        ExportService.frameKey: baked(),
        ExportService.fxKey: baked(),
      },
    );
    expect(command, contains('baked.png'));
    expect(plain.contains('baked.png'), isFalse);
  });

  test('Switch reaches the render', () {
    final p = blank(clips: 2);
    p.clips.first.path = '/nonexistent/first.mp4';
    p.clips.last.path = '/nonexistent/second.mp4';
    final before = commandOf(p);
    p.clips.insert(0, p.clips.removeAt(1));
    final after = commandOf(p);
    expect(
      after,
      isNot(before),
      reason: 'the order of the clips does not reach the graph',
    );
    expect(after.indexOf('second.mp4'), lessThan(after.indexOf('first.mp4')));
  });

  test('Duplicate and Split reach the render', () {
    // Both end as more clips on the track, which the graph has to join.
    expect(commandOf(blank(clips: 2)), contains('concat'));
    expect(plain.contains('concat'), isFalse);
  });

  test('Delete reaches the render', () {
    final p = blank(clips: 2);
    p.clips.removeLast();
    expect(
      commandOf(p).contains('concat'),
      isFalse,
      reason: 'a deleted clip is still being joined into the graph',
    );
  });

  test('Duration reaches the render', () {
    final p = blank();
    p.clips.first.trimEnd = const Duration(seconds: 1);
    expect(commandOf(p), contains('-t 1.000'));
  });

  test('Replace reaches the render', () {
    final p = blank();
    p.clips.first.path = '/nonexistent/replaced.mp4';
    expect(commandOf(p), contains('replaced.mp4'));
  });

  test('Freeze reaches the render', () {
    final p = blank();
    // Freeze hands back a still, which the graph has to loop rather than
    // decode as footage.
    p.clips.first
      ..path = '/nonexistent/frozen.png'
      ..isImage = true;
    expect(commandOf(p), contains('-loop 1'));
  });

  test('Cutout reaches the render', () {
    final p = blank();
    p.clips.first.cutoutMattePath = '/nonexistent/matte.mp4';
    expect(commandOf(p), contains('alphamerge'));
    expect(plain.contains('alphamerge'), isFalse);
  });

  test('HSL reaches the render', () {
    final p = blank();
    expect(
      commandOf(p, hslLuts: {p.clips.first.id: '/nonexistent/hsl.cube'}),
      contains('lut3d'),
    );
    expect(plain.contains('lut3d'), isFalse);
  });

  // ------------------------------------------------------------------ sound

  test('Volume reaches the render', () {
    final p = blank();
    p.clips.first.volume = 0.4;
    expect(commandOf(p), contains('volume=0.400'));
  });

  test('Mix reaches the render', () {
    final p = blank()..masterVolume = 0.5;
    expect(commandOf(p), contains('volume=0.500'));
  });

  test('Voice Enhance reaches the render', () {
    final p = blank();
    p.clips.first.voiceEnhance = true;
    expect(commandOf(p), contains('loudnorm'));
    expect(plain.contains('loudnorm'), isFalse);
  });

  test('Voice Effect reaches the render', () {
    final p = blank();
    p.clips.first.voiceEffect = VoiceEffect.deep;
    expect(commandOf(p), contains('asetrate'));
    expect(plain.contains('asetrate'), isFalse);
  });

  test('Audio, TTS, Voice and Extract reach the render', () {
    // All four land as an audio lane, which is one path in the graph.
    final p = blank()
      ..audios.add(
        AudioLayer(
          start: Duration.zero,
          duration: const Duration(seconds: 2),
          path: '/nonexistent/track.m4a',
          title: 'probe',
          sourceDuration: const Duration(seconds: 2),
        ),
      );
    final command = commandOf(p);
    expect(command, contains('track.m4a'));
    expect(command, contains('amix'));
  });

  // ----------------------------------------------------------------- layers

  test('PIP reaches the render', () {
    final p = blank()
      ..overlays.add(
        OverlayLayer(
          start: Duration.zero,
          duration: const Duration(seconds: 2),
          path: '/nonexistent/pip.mp4',
          isImage: false,
          sourceDuration: const Duration(seconds: 2),
        ),
      );
    expect(commandOf(p), contains('pip.mp4'));
  });

  test('Text and Captions reach the render', () {
    final p = blank()
      ..texts.add(
        TextLayer(
          start: Duration.zero,
          duration: const Duration(seconds: 2),
          text: 'probe',
        ),
      );
    final command = commandOf(p, rasterized: {p.texts.first.id: baked()});
    expect(command, contains('baked.png'));
  });

  test('Sticker reaches the render', () {
    final p = blank()
      ..stickers.add(
        StickerLayer(
          start: Duration.zero,
          duration: const Duration(seconds: 2),
          content: '\u2b50',
        ),
      );
    expect(
      commandOf(p, rasterized: {p.stickers.first.id: baked()}),
      contains('baked.png'),
    );
  });

  test('Watermark reaches the render', () {
    final p = blank();
    p.watermark.enabled = true;
    expect(
      commandOf(p, rasterized: {ExportService.watermarkKey: baked()}),
      contains('baked.png'),
    );
  });

  // -------------------------------------------------------------- keyframes

  test('Keyframe reaches the render', () {
    final p = blank();
    p.clips.first.track(KeyframeProperty.scale)
      ..set(Duration.zero, 1)
      ..set(const Duration(seconds: 2), 1.5);
    expect(commandOf(p), contains('eval=frame'));
    expect(plain.contains('eval=frame'), isFalse);
  });
}
