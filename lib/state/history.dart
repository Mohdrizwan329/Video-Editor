import 'dart:convert';

import '../data/models/project.dart';

/// Snapshot-based undo. Every mutating action pushes the *previous* project
/// JSON, which is cheap for timelines of this size and impossible to get
/// subtly wrong the way per-command inverses can be.
class EditHistory {
  EditHistory({this.limit = 60});

  final int limit;
  final List<String> _undo = [];
  final List<String> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void push(Project before) {
    _undo.add(jsonEncode(before.toJson()));
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  Project? undo(Project current) {
    if (_undo.isEmpty) return null;
    _redo.add(jsonEncode(current.toJson()));
    return _decode(_undo.removeLast());
  }

  Project? redo(Project current) {
    if (_redo.isEmpty) return null;
    _undo.add(jsonEncode(current.toJson()));
    return _decode(_redo.removeLast());
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  static Project _decode(String raw) =>
      Project.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
