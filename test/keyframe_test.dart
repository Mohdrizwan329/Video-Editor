import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/keyframe.dart';
import 'package:video_editor/data/models/layers.dart';
import 'package:video_editor/data/models/text_presets.dart';
import 'package:video_editor/data/models/video_clip.dart';

void main() {
  group('keyframe interpolation', () {
    KeyframeTrack track() => KeyframeTrack(
      property: KeyframeProperty.scale,
      keys: [
        Keyframe(time: Duration.zero, value: 1, easing: KeyframeEasing.linear),
        Keyframe(
          time: const Duration(seconds: 2),
          value: 2,
          easing: KeyframeEasing.linear,
        ),
      ],
    );

    test('interpolates linearly between two keys', () {
      expect(
        track().valueAt(const Duration(seconds: 1), 0),
        closeTo(1.5, 1e-9),
      );
    });

    test('holds the first and last value outside the range', () {
      final t = track();
      expect(t.valueAt(const Duration(seconds: -5), 0), 1);
      expect(t.valueAt(const Duration(seconds: 99), 0), 2);
    });

    test('falls back when the track is empty', () {
      final t = KeyframeTrack(property: KeyframeProperty.opacity);
      expect(t.valueAt(Duration.zero, 0.42), 0.42);
    });

    test('setting a key near an existing one replaces it', () {
      final t = track();
      t.set(const Duration(milliseconds: 20), 0.5);
      expect(t.keys.length, 2);
      expect(t.keys.first.value, 0.5);
    });

    test('hold easing keeps the previous value until the next key', () {
      final t = KeyframeTrack(
        property: KeyframeProperty.opacity,
        keys: [
          Keyframe(time: Duration.zero, value: 0),
          Keyframe(
            time: const Duration(seconds: 2),
            value: 1,
            easing: KeyframeEasing.hold,
          ),
        ],
      );
      expect(t.valueAt(const Duration(milliseconds: 1900), 0), 0);
      expect(t.valueAt(const Duration(seconds: 2), 0), 1);
    });

    test('the FFmpeg expression is offset onto the timeline', () {
      final expr = track().toExpression(offset: 5);
      expect(expr, contains('5.0000'));
      expect(expr, contains('7.0000'));
      expect(expr, startsWith('if(lt(t,'));
    });
  });

  group('keyframes on a clip', () {
    test('survive a JSON round trip', () {
      final clip = VideoClip(
        path: '/tmp/a.mp4',
        isImage: false,
        sourceDuration: const Duration(seconds: 5),
      );
      clip.track(KeyframeProperty.scale).set(const Duration(seconds: 1), 1.8);
      final restored = VideoClip.fromJson(clip.toJson());
      expect(restored.hasKeyframes, isTrue);
      expect(
        restored.animated(
          KeyframeProperty.scale,
          const Duration(seconds: 1),
          1,
        ),
        closeTo(1.8, 1e-9),
      );
    });

    test('duplicating a clip carries its keyframes but not its id', () {
      final clip = VideoClip(
        path: '/tmp/a.mp4',
        isImage: false,
        sourceDuration: const Duration(seconds: 5),
      );
      clip.track(KeyframeProperty.opacity).set(Duration.zero, 0.25);
      final copy = clip.copyWith();
      expect(copy.id, isNot(clip.id));
      expect(copy.hasKeyframes, isTrue);
    });

    test('keyframeTimes lists each distinct offset once', () {
      final clip = VideoClip(
        path: '/tmp/a.mp4',
        isImage: false,
        sourceDuration: const Duration(seconds: 5),
      );
      clip.track(KeyframeProperty.x).set(const Duration(seconds: 1), 0);
      clip.track(KeyframeProperty.y).set(const Duration(seconds: 1), 0);
      clip.track(KeyframeProperty.scale).set(const Duration(seconds: 3), 2);
      expect(clip.keyframeTimes.length, 2);
    });
  });

  group('speed curves', () {
    test('a flat curve leaves the duration alone', () {
      expect(SpeedCurve.none.averageSpeed, 1);
    });

    test('ramping changes the clip length', () {
      final clip = VideoClip(
        path: '/tmp/a.mp4',
        isImage: false,
        sourceDuration: const Duration(seconds: 10),
      )..speedCurve = SpeedCurve.bullet;
      expect(clip.effectiveSpeed, isNot(1.0));
      expect(clip.timelineDuration, isNot(const Duration(seconds: 10)));
    });

    test('speedAt follows the control points', () {
      expect(SpeedCurve.rampUp.speedAt(0), closeTo(0.35, 1e-9));
      expect(SpeedCurve.rampUp.speedAt(1), closeTo(3.0, 1e-9));
      expect(SpeedCurve.rampUp.speedAt(0.5), closeTo(1.675, 1e-6));
    });
  });

  group('libraries', () {
    test('every transition maps to an xfade name', () {
      for (final t in TransitionType.values) {
        expect(t.ffmpegName, isNotEmpty, reason: t.name);
      }
    });

    test('transition categories cover the whole list', () {
      final grouped = TransitionType.categories
          .expand(TransitionType.byCategory)
          .toSet();
      expect(grouped.length, TransitionType.values.length);
    });

    test('animation categories cover the whole list', () {
      final grouped = LayerAnimation.categories
          .expand(LayerAnimation.byCategory)
          .toSet();
      expect(grouped.length, LayerAnimation.values.length);
    });

    test('a text preset writes every style field onto the layer', () {
      final layer = TextLayer(
        start: Duration.zero,
        duration: const Duration(seconds: 2),
      );
      final preset = TextPresetLibrary.all.firstWhere(
        (p) => p.id == 'neonCyan',
      );
      preset.applyTo(layer);
      expect(layer.fontFamily, preset.fontFamily);
      expect(layer.shadowBlur, preset.shadowBlur);
      expect(layer.stylePresetId, 'neonCyan');
    });

    test('voice effects other than none change the audio chain', () {
      final layer = AudioLayer(
        start: Duration.zero,
        duration: const Duration(seconds: 3),
        path: '/tmp/a.mp3',
        title: 'a',
        sourceDuration: const Duration(seconds: 3),
      );
      expect(layer.audioFilterChain(), isEmpty);
      layer.voiceEffect = VoiceEffect.chipmunk;
      expect(layer.audioFilterChain(), isNotEmpty);
    });
  });
}
