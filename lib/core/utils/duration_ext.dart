/// Timecode helpers used by the ruler, the player readout and the clip chips.
extension DurationFormat on Duration {
  /// `m:ss` — the compact form shown on clips.
  String get mmss {
    final m = inMinutes;
    final s = inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// `mm:ss.d` — the player readout.
  String get timecode {
    final m = inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = inSeconds.remainder(60).toString().padLeft(2, '0');
    final d = (inMilliseconds.remainder(1000) ~/ 100);
    return '$m:$s.$d';
  }

  double get seconds => inMicroseconds / 1000000.0;

  String get pretty {
    if (inHours > 0) {
      return '$inHours:${inMinutes.remainder(60).toString().padLeft(2, '0')}'
          ':${inSeconds.remainder(60).toString().padLeft(2, '0')}';
    }
    return '${inMinutes.remainder(60)}:${inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }
}

Duration durationFromSeconds(double s) =>
    Duration(microseconds: (s * 1000000).round());
