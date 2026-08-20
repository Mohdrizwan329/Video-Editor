import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// A property that can be animated over time.
///
/// The string values are the JSON keys, so they must stay stable once a
/// project has been saved with them.
enum KeyframeProperty {
  x('x', 'Position X'),
  y('y', 'Position Y'),
  scale('scale', 'Scale'),
  rotation('rot', 'Rotation'),
  opacity('op', 'Opacity'),
  volume('vol', 'Volume'),
  filterIntensity('fi', 'Filter'),
  cornerRadius('cr', 'Radius'),
  blurAmount('bl', 'Blur');

  const KeyframeProperty(this.key, this.label);

  final String key;
  final String label;

  static KeyframeProperty? fromKey(String k) {
    for (final p in KeyframeProperty.values) {
      if (p.key == k) return p;
    }
    return null;
  }
}

/// Interpolation used to reach a keyframe from the one before it.
enum KeyframeEasing {
  linear('Linear'),
  easeIn('Ease In'),
  easeOut('Ease Out'),
  easeInOut('Ease In Out'),
  hold('Hold');

  const KeyframeEasing(this.label);
  final String label;

  double transform(double t) => switch (this) {
        KeyframeEasing.linear => t,
        KeyframeEasing.easeIn => Curves.easeInCubic.transform(t),
        KeyframeEasing.easeOut => Curves.easeOutCubic.transform(t),
        KeyframeEasing.easeInOut => Curves.easeInOutCubic.transform(t),
        KeyframeEasing.hold => 0,
      };

  static KeyframeEasing fromName(String? n) => KeyframeEasing.values
      .firstWhere((e) => e.name == n, orElse: () => KeyframeEasing.linear);
}

/// One control point: a value pinned at an offset inside the owner.
class Keyframe implements Comparable<Keyframe> {
  Keyframe({
    required this.time,
    required this.value,
    this.easing = KeyframeEasing.linear,
  });

  /// Offset from the start of the owning clip or layer — not absolute
  /// timeline time, so trimming and moving never invalidate a keyframe.
  Duration time;
  double value;
  KeyframeEasing easing;

  @override
  int compareTo(Keyframe other) => time.compareTo(other.time);

  Keyframe copy() => Keyframe(time: time, value: value, easing: easing);

  Map<String, dynamic> toJson() =>
      {'t': time.inMicroseconds, 'v': value, 'e': easing.name};

  factory Keyframe.fromJson(Map<String, dynamic> j) => Keyframe(
        time: Duration(microseconds: (j['t'] as num?)?.toInt() ?? 0),
        value: (j['v'] as num?)?.toDouble() ?? 0,
        easing: KeyframeEasing.fromName(j['e'] as String?),
      );
}

/// The keyframes for one property, kept sorted by time.
class KeyframeTrack {
  KeyframeTrack({required this.property, List<Keyframe>? keys})
      : keys = keys ?? [] {
    this.keys.sort();
  }

  final KeyframeProperty property;
  final List<Keyframe> keys;

  bool get isEmpty => keys.isEmpty;
  bool get isNotEmpty => keys.isNotEmpty;

  /// Value at [t], or [fallback] when the track is empty.
  ///
  /// Before the first key the first value holds; after the last key the last
  /// value holds — the same clamping behaviour editors converge on.
  double valueAt(Duration t, double fallback) {
    if (keys.isEmpty) return fallback;
    if (keys.length == 1) return keys.first.value;
    if (t <= keys.first.time) return keys.first.value;
    if (t >= keys.last.time) return keys.last.value;

    for (var i = 0; i < keys.length - 1; i++) {
      final a = keys[i];
      final b = keys[i + 1];
      if (t < a.time || t > b.time) continue;
      final span = (b.time - a.time).inMicroseconds;
      if (span <= 0) return b.value;
      final raw = (t - a.time).inMicroseconds / span;
      final eased = b.easing.transform(raw.clamp(0.0, 1.0));
      return a.value + (b.value - a.value) * eased;
    }
    return keys.last.value;
  }

  /// Insert or replace the key at [t] (within one frame of tolerance).
  void set(Duration t, double value, {KeyframeEasing? easing}) {
    final existing = keyAt(t);
    if (existing != null) {
      existing.value = value;
      if (easing != null) existing.easing = easing;
      return;
    }
    keys
      ..add(Keyframe(
          time: t, value: value, easing: easing ?? KeyframeEasing.easeInOut))
      ..sort();
  }

  static const Duration snapTolerance = Duration(milliseconds: 40);

  Keyframe? keyAt(Duration t) {
    for (final k in keys) {
      if ((k.time - t).abs() <= snapTolerance) return k;
    }
    return null;
  }

  bool removeAt(Duration t) {
    final k = keyAt(t);
    if (k == null) return false;
    keys.remove(k);
    return true;
  }

  KeyframeTrack copy() => KeyframeTrack(
        property: property,
        keys: keys.map((k) => k.copy()).toList(),
      );

  /// Piecewise-linear FFmpeg expression in terms of `t`, where `t` is
  /// absolute timeline seconds. [offset] shifts the track onto the timeline
  /// and [scale]/[bias] map the stored value into output units.
  ///
  /// Easing is approximated by subdividing eased segments, because FFmpeg
  /// expressions have no cubic helper.
  String toExpression({
    required double offset,
    double scale = 1,
    double bias = 0,
    int easingSteps = 6,
  }) {
    if (keys.isEmpty) return bias.toStringAsFixed(4);
    if (keys.length == 1) {
      return (keys.first.value * scale + bias).toStringAsFixed(4);
    }

    final points = <(double, double)>[];
    for (var i = 0; i < keys.length - 1; i++) {
      final a = keys[i];
      final b = keys[i + 1];
      final ta = offset + a.time.inMicroseconds / 1e6;
      final tb = offset + b.time.inMicroseconds / 1e6;
      if (b.easing == KeyframeEasing.linear || b.easing == KeyframeEasing.hold) {
        points.add((ta, a.value * scale + bias));
        if (b.easing == KeyframeEasing.hold) {
          points.add((tb - 0.0001, a.value * scale + bias));
        }
      } else {
        // Sample the curve so the expression stays piecewise linear.
        for (var s = 0; s < easingSteps; s++) {
          final f = s / easingSteps;
          final eased = b.easing.transform(f);
          points.add((
            ta + (tb - ta) * f,
            (a.value + (b.value - a.value) * eased) * scale + bias,
          ));
        }
      }
    }
    points.add((
      offset + keys.last.time.inMicroseconds / 1e6,
      keys.last.value * scale + bias,
    ));

    // Build nested if() from the end backwards so the common case is shallow.
    var expr = points.last.$2.toStringAsFixed(4);
    for (var i = points.length - 2; i >= 0; i--) {
      final (t0, v0) = points[i];
      final (t1, v1) = points[i + 1];
      final span = math.max(t1 - t0, 0.0001);
      final segment = '($v0+(${(v1 - v0).toStringAsFixed(4)})'
          '*(t-${t0.toStringAsFixed(4)})/${span.toStringAsFixed(4)})';
      expr = 'if(lt(t,${t1.toStringAsFixed(4)}),$segment,$expr)';
    }
    final first = points.first;
    return 'if(lt(t,${first.$1.toStringAsFixed(4)}),'
        '${first.$2.toStringAsFixed(4)},$expr)';
  }

  Map<String, dynamic> toJson() =>
      {'p': property.key, 'k': keys.map((e) => e.toJson()).toList()};

  static KeyframeTrack? fromJson(Map<String, dynamic> j) {
    final p = KeyframeProperty.fromKey(j['p'] as String? ?? '');
    if (p == null) return null;
    return KeyframeTrack(
      property: p,
      keys: ((j['k'] as List?) ?? const [])
          .map((e) => Keyframe.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// Mixin for anything that owns keyframe tracks.
mixin Keyframable {
  final Map<KeyframeProperty, KeyframeTrack> keyframes = {};

  bool get hasKeyframes => keyframes.values.any((t) => t.isNotEmpty);

  KeyframeTrack track(KeyframeProperty p) =>
      keyframes.putIfAbsent(p, () => KeyframeTrack(property: p));

  KeyframeTrack? trackOrNull(KeyframeProperty p) {
    final t = keyframes[p];
    return (t == null || t.isEmpty) ? null : t;
  }

  double animated(KeyframeProperty p, Duration local, double fallback) =>
      trackOrNull(p)?.valueAt(local, fallback) ?? fallback;

  /// Every distinct keyframe offset, used to draw the diamonds on the lane.
  List<Duration> get keyframeTimes {
    final set = <int>{};
    for (final t in keyframes.values) {
      for (final k in t.keys) {
        set.add(k.time.inMicroseconds);
      }
    }
    final out = set.map((e) => Duration(microseconds: e)).toList()..sort();
    return out;
  }

  void clearKeyframes() => keyframes.clear();

  void removeKeyframesAt(Duration local) {
    for (final t in keyframes.values) {
      t.removeAt(local);
    }
    keyframes.removeWhere((_, t) => t.isEmpty);
  }

  List<Map<String, dynamic>> keyframesToJson() =>
      keyframes.values.where((t) => t.isNotEmpty).map((t) => t.toJson()).toList();

  void keyframesFromJson(List? raw) {
    keyframes.clear();
    for (final e in raw ?? const []) {
      final t = KeyframeTrack.fromJson((e as Map).cast<String, dynamic>());
      if (t != null && t.isNotEmpty) keyframes[t.property] = t;
    }
  }

  void copyKeyframesFrom(Keyframable other) {
    keyframes.clear();
    other.keyframes.forEach((k, v) => keyframes[k] = v.copy());
  }
}
