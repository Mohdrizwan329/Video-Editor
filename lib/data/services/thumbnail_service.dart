import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Extracts and caches timeline filmstrip frames. Frames are keyed by
/// (file, position, height) so a clip that is trimmed or zoomed reuses
/// whatever it already pulled.
class ThumbnailService {
  ThumbnailService._();

  static final ThumbnailService instance = ThumbnailService._();

  Directory? _cacheDir;
  final Map<String, Future<String?>> _inflight = {};
  final Map<String, String> _ready = {};

  Future<Directory> _dir() async {
    if (_cacheDir != null) return _cacheDir!;
    final base = await getTemporaryDirectory();
    final d = Directory('${base.path}/sve_thumbs');
    if (!await d.exists()) await d.create(recursive: true);
    _cacheDir = d;
    return d;
  }

  /// FNV-1a keeps the cache filename short and stable without pulling in
  /// a crypto dependency we would use for nothing else.
  String _key(String path, Duration at, int height) {
    var hash = 0xcbf29ce484222325;
    for (final unit in '$path|${at.inMilliseconds}|$height'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// Returns a cached frame path immediately if we already have it.
  String? cached(String path, Duration at, int height) =>
      _ready[_key(path, at, height)];

  Future<String?> frame(String path, Duration at, {int height = 120}) {
    final key = _key(path, at, height);
    final done = _ready[key];
    if (done != null) return Future.value(done);
    return _inflight.putIfAbsent(key, () => _extract(path, at, height, key));
  }

  Future<String?> _extract(String path, Duration at, int height, String key) async {
    try {
      final dir = await _dir();
      final out = '${dir.path}/$key.jpg';
      if (await File(out).exists()) {
        _ready[key] = out;
        return out;
      }
      final ss = (at.inMicroseconds / 1000000).clamp(0, double.infinity);
      final cmd = '-hide_banner -loglevel error -ss ${ss.toStringAsFixed(3)} '
          '-i ${_q(path)} -frames:v 1 '
          '-vf "scale=-2:$height" -q:v 5 -y ${_q(out)}';
      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc) && await File(out).exists()) {
        _ready[key] = out;
        return out;
      }
      return null;
    } catch (e) {
      debugPrint('thumbnail failed: $e');
      return null;
    } finally {
      _inflight.remove(key);
    }
  }

  /// A single representative frame used for the project card cover.
  Future<String?> cover(String path, {Duration at = const Duration(seconds: 1)}) =>
      frame(path, at, height: 320);

  Future<void> clear() async {
    final d = await _dir();
    if (await d.exists()) await d.delete(recursive: true);
    _cacheDir = null;
    _ready.clear();
  }

  static String _q(String p) => '"${p.replaceAll('"', r'\"')}"';
}
