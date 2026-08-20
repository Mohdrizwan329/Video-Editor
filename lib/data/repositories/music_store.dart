import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'project_repository.dart';

/// A track the user has imported before.
class SavedTrack {
  const SavedTrack({
    required this.path,
    required this.title,
    required this.duration,
    required this.addedAt,
  });

  final String path;
  final String title;
  final Duration duration;
  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
        'path': path,
        'title': title,
        'dur': duration.inMilliseconds,
        'at': addedAt.millisecondsSinceEpoch,
      };

  factory SavedTrack.fromJson(Map<String, dynamic> j) => SavedTrack(
        path: j['path'] as String,
        title: j['title'] as String? ?? 'Track',
        duration: Duration(milliseconds: (j['dur'] as num?)?.toInt() ?? 0),
        addedAt: DateTime.fromMillisecondsSinceEpoch(
            (j['at'] as num?)?.toInt() ?? 0),
      );
}

/// Remembers imported music so the second project does not start from an
/// empty list — the closest thing to a personal library the app can offer
/// without shipping anyone else's audio.
class MusicStore {
  MusicStore._();

  static final MusicStore instance = MusicStore._();

  List<SavedTrack>? _cache;

  Future<File> _file() async {
    final dir = await ProjectRepository.instance.mediaDir();
    return File('${dir.path}/my_music.json');
  }

  Future<List<SavedTrack>> tracks() async {
    if (_cache != null) return _cache!;
    try {
      final f = await _file();
      if (!await f.exists()) return _cache = [];
      final raw = jsonDecode(await f.readAsString()) as List;
      final all = raw
          .map((e) => SavedTrack.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      // Drop entries whose file has gone; a dead row is worse than no row.
      final alive = <SavedTrack>[];
      for (final t in all) {
        if (await File(t.path).exists()) alive.add(t);
      }
      alive.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      if (alive.length != all.length) await _write(alive);
      return _cache = alive;
    } catch (e) {
      debugPrint('music store read failed: $e');
      return _cache = [];
    }
  }

  Future<void> remember(String path, String title, Duration duration) async {
    final list = [...await tracks()];
    list.removeWhere((t) => t.path == path);
    list.insert(
        0,
        SavedTrack(
            path: path,
            title: title,
            duration: duration,
            addedAt: DateTime.now()));
    // 40 is plenty for a picker; beyond that it stops being browsable.
    if (list.length > 40) list.removeRange(40, list.length);
    await _write(list);
  }

  Future<void> forget(String path) async {
    final list = [...await tracks()]..removeWhere((t) => t.path == path);
    await _write(list);
  }

  Future<void> _write(List<SavedTrack> list) async {
    _cache = list;
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('music store write failed: $e');
    }
  }
}
