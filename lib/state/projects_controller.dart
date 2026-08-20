import 'package:flutter/foundation.dart';

import '../data/models/enums.dart';
import '../data/models/project.dart';
import '../data/repositories/project_repository.dart';

/// Backs the home screen's project library.
class ProjectsController extends ChangeNotifier {
  ProjectsController() {
    refresh();
  }

  final ProjectRepository _repo = ProjectRepository.instance;

  List<Project> _projects = [];
  bool _loading = true;

  List<Project> get projects => _projects;
  bool get loading => _loading;
  bool get isEmpty => !_loading && _projects.isEmpty;

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    _projects = await _repo.loadAll();
    _loading = false;
    notifyListeners();
  }

  Future<Project> create({
    String? name,
    CanvasRatio ratio = CanvasRatio.r9x16,
  }) async {
    final p = Project(
      name: name ?? 'Project ${_projects.length + 1}',
      ratio: ratio,
    );
    await _repo.save(p);
    _projects.insert(0, p);
    notifyListeners();
    return p;
  }

  Future<void> delete(Project p) async {
    await _repo.delete(p.id);
    _projects.removeWhere((e) => e.id == p.id);
    notifyListeners();
  }

  Future<Project> duplicate(Project p) async {
    final copy = await _repo.duplicate(p);
    _projects.insert(0, copy);
    notifyListeners();
    return copy;
  }

  Future<void> rename(Project p, String name) async {
    p.name = name;
    await _repo.save(p);
    notifyListeners();
  }

  void touch(Project p) {
    final i = _projects.indexWhere((e) => e.id == p.id);
    if (i >= 0) _projects[i] = p;
    _projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();
  }
}
