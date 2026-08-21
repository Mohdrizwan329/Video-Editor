import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter/foundation.dart';

/// Everything the editor needs to know about a source file before it can be
/// laid on the timeline.
class MediaInfo {
  const MediaInfo({
    required this.path,
    required this.duration,
    required this.width,
    required this.height,
    required this.hasAudio,
    required this.isImage,
    this.fps = 30,
    this.rotation = 0,
  });

  final String path;
  final Duration duration;
  final int width;
  final int height;
  final bool hasAudio;
  final bool isImage;
  final double fps;
  final int rotation;

  /// Width/height after the container rotation flag is applied.
  double get aspect {
    if (width <= 0 || height <= 0) return 16 / 9;
    final swapped = rotation == 90 || rotation == 270;
    return swapped ? height / width : width / height;
  }

  int get displayWidth => (rotation == 90 || rotation == 270) ? height : width;
  int get displayHeight => (rotation == 90 || rotation == 270) ? width : height;
}

/// Thin wrapper over FFprobe with a defensive fallback, because a file the
/// picker handed us may still be unreadable (permissions, cloud placeholder…).
class MediaProbe {
  MediaProbe._();

  static const Set<String> imageExtensions = {
    'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'bmp', 'gif', 'tiff'
  };

  static const Duration defaultImageDuration = Duration(seconds: 4);

  static bool isImagePath(String p) =>
      imageExtensions.contains(p.split('.').last.toLowerCase());

  static Future<MediaInfo> probe(String path) async {
    final isImage = isImagePath(path);
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      if (info == null) return _fallback(path, isImage);

      var width = 0, height = 0, rotation = 0;
      var hasAudio = false;
      var fps = 30.0;

      for (final s in info.getStreams()) {
        final type = s.getType();
        if (type == 'video') {
          width = s.getWidth() ?? width;
          height = s.getHeight() ?? height;
          fps = _parseRate(s.getAverageFrameRate()) ?? fps;
          rotation = _parseRotation(s.getAllProperties());
        } else if (type == 'audio') {
          hasAudio = true;
        }
      }

      final durSec = double.tryParse(info.getDuration() ?? '') ?? 0;
      final duration = isImage || durSec <= 0
          ? defaultImageDuration
          : Duration(microseconds: (durSec * 1000000).round());

      return MediaInfo(
        path: path,
        duration: duration,
        width: width,
        height: height,
        hasAudio: hasAudio,
        isImage: isImage,
        fps: fps,
        rotation: rotation,
      );
    } catch (e) {
      debugPrint('probe failed for $path: $e');
      return _fallback(path, isImage);
    }
  }

  static MediaInfo _fallback(String path, bool isImage) => MediaInfo(
        path: path,
        duration: isImage ? defaultImageDuration : const Duration(seconds: 10),
        width: 1920,
        height: 1080,
        hasAudio: !isImage,
        isImage: isImage,
      );

  static double? _parseRate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.contains('/')) {
      final parts = raw.split('/');
      final n = double.tryParse(parts[0]) ?? 0;
      final d = double.tryParse(parts[1]) ?? 0;
      if (d == 0) return null;
      return n / d;
    }
    return double.tryParse(raw);
  }

  static int _parseRotation(Map<dynamic, dynamic>? props) {
    if (props == null) return 0;
    final direct = props['rotation'];
    if (direct != null) {
      final v = int.tryParse(direct.toString()) ?? 0;
      return ((v % 360) + 360) % 360;
    }
    final sideData = props['side_data_list'];
    if (sideData is List) {
      for (final e in sideData) {
        if (e is Map && e['rotation'] != null) {
          final v = (num.tryParse(e['rotation'].toString()) ?? 0).round();
          return ((v % 360) + 360) % 360;
        }
      }
    }
    return 0;
  }

  static Future<bool> exists(String path) => File(path).exists();
}
