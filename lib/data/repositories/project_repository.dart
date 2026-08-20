import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/project.dart';

/// Projects live as one JSON file each under `<appdocs>/projects/`, so a
/// crash can never take more than the project being written at that moment.
class ProjectRepository {
  ProjectRepository._();

  static final ProjectRepository instance = ProjectRepository._();

  Directory? _root;

  Future<Directory> _dir() async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/sve_projects');
    if (!await d.exists()) await d.create(recursive: true);
    _root = d;
    return d;
  }

  Future<Directory> mediaDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/sve_media');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<Directory> exportDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/sve_exports');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<List<Project>> loadAll() async {
    final d = await _dir();
    final files = await d
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    final out = <Project>[];
    for (final f in files) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        out.add(Project.fromJson(j));
      } catch (_) {
        // A corrupt project must not block the whole library.
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<Project?> load(String id) async {
    final f = File('${(await _dir()).path}/$id.json');
    if (!await f.exists()) return null;
    return Project.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  }

  Future<void> save(Project p) async {
    p.updatedAt = DateTime.now();
    final f = File('${(await _dir()).path}/${p.id}.json');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(p.toJson()));
    await tmp.rename(f.path);
  }

  Future<void> delete(String id) async {
    final f = File('${(await _dir()).path}/$id.json');
    if (await f.exists()) await f.delete();
  }

  Future<Project> duplicate(Project p) async {
    final copy = Project.fromJson(p.toJson())
      ..name = '${p.name} copy'
      ..createdAt = DateTime.now();
    // fromJson keeps the id, so rebuild with a fresh one.
    final fresh = Project(
      name: copy.name,
      ratio: copy.ratio,
      clips: copy.clips,
      audios: copy.audios,
      texts: copy.texts,
      stickers: copy.stickers,
      overlays: copy.overlays,
      background: copy.background,
      coverPath: copy.coverPath,
      masterVolume: copy.masterVolume,
    );
    await save(fresh);
    return fresh;
  }
}
