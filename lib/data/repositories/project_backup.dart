import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/project.dart';
import 'project_repository.dart';

/// Exports and restores a project as a single `.svproj` bundle.
///
/// The bundle is a JSON manifest plus every media file the project points at,
/// so it survives being moved to another device where those paths mean
/// nothing. Media is stored base64-inline to keep it to one file.
class ProjectBackup {
  ProjectBackup._();

  static const String extension = 'svproj';
  static const int _formatVersion = 1;

  /// Media larger than this is referenced rather than embedded, because a
  /// base64 bundle of a long 4K clip would be unusable.
  static const int maxEmbeddedBytes = 120 * 1024 * 1024;

  static Future<String?> export(Project project) async {
    try {
      final dir = await ProjectRepository.instance.exportDir();
      final safe = project.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final out = File('${dir.path}/$safe.$extension');

      final paths = _mediaPaths(project);
      final media = <String, String>{};
      var embedded = 0;
      final skipped = <String>[];

      for (final p in paths) {
        final f = File(p);
        if (!await f.exists()) continue;
        final length = await f.length();
        if (embedded + length > maxEmbeddedBytes) {
          skipped.add(p);
          continue;
        }
        media[p] = base64Encode(await f.readAsBytes());
        embedded += length;
      }

      final manifest = {
        'format': _formatVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'project': project.toJson(),
        'media': media,
        'skipped': skipped,
      };
      await out.writeAsString(jsonEncode(manifest));
      return out.path;
    } catch (e) {
      debugPrint('backup export failed: $e');
      return null;
    }
  }

  /// Restore a bundle, rewriting every media path to the freshly written copy.
  static Future<Project?> import() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [extension, 'json'],
      );
      final path = picked?.files.single.path;
      if (path == null) return null;

      final manifest =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      final projectJson = (manifest['project'] as Map).cast<String, dynamic>();
      final media = ((manifest['media'] as Map?) ?? {}).cast<String, dynamic>();

      final mediaDir = await ProjectRepository.instance.mediaDir();
      final remap = <String, String>{};
      for (final entry in media.entries) {
        final name = entry.key.split(Platform.pathSeparator).last;
        final target = File(
            '${mediaDir.path}/${DateTime.now().microsecondsSinceEpoch}_$name');
        await target.writeAsBytes(base64Decode(entry.value as String));
        remap[entry.key] = target.path;
      }

      var raw = jsonEncode(projectJson);
      remap.forEach((from, to) {
        raw = raw.replaceAll(jsonEncode(from), jsonEncode(to));
      });

      // A fresh id keeps the restored copy from overwriting the original.
      final restored = Project.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
      final copy = Project(
        name: restored.name,
        ratio: restored.ratio,
        clips: restored.clips,
        audios: restored.audios,
        texts: restored.texts,
        stickers: restored.stickers,
        overlays: restored.overlays,
        background: restored.background,
        masterVolume: restored.masterVolume,
      );
      await ProjectRepository.instance.save(copy);
      return copy;
    } catch (e) {
      debugPrint('backup import failed: $e');
      return null;
    }
  }

  static Set<String> _mediaPaths(Project p) => {
        ...p.clips.map((c) => c.path),
        ...p.overlays.map((o) => o.path),
        ...p.audios.map((a) => a.path),
        if (p.coverPath != null) p.coverPath!,
      };
}
