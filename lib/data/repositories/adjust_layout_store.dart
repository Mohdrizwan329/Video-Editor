import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Which adjust knobs are shown, and in what order.
///
/// A preference, not project data: it follows the person rather than the
/// video, so it lives beside the app's other settings instead of in the
/// project file. Anything the stored list does not mention is a knob added
/// since it was written, and those come back visible at the end — a new tool
/// must not be invisible because of a file saved before it existed.
class AdjustLayoutStore {
  AdjustLayoutStore._();

  static final AdjustLayoutStore instance = AdjustLayoutStore._();

  static const String _fileName = 'sve_adjust_layout.json';

  List<String>? _order;
  Set<String>? _hidden;

  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}/$_fileName');
  }

  Future<void> load() async {
    if (_order != null) return;
    _order = const [];
    _hidden = <String>{};
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _order = [for (final v in (j['order'] as List? ?? [])) v as String];
      _hidden = {for (final v in (j['hidden'] as List? ?? [])) v as String};
    } catch (e) {
      debugPrint('could not read the adjust layout: $e');
    }
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(
        jsonEncode({
          'order': _order ?? const [],
          'hidden': (_hidden ?? const <String>{}).toList(),
        }),
        flush: true,
      );
    } catch (e) {
      debugPrint('could not write the adjust layout: $e');
    }
  }

  /// [all] arranged the way the user left it, with anything they have hidden
  /// dropped and anything new appended.
  List<String> visible(List<String> all) =>
      arrange(all).where((k) => !isHidden(k)).toList();

  /// [all] in the stored order, hidden ones included — what the manage sheet
  /// itself shows.
  List<String> arrange(List<String> all) {
    final stored = _order ?? const <String>[];
    final known = all.toSet();
    final out = [
      for (final k in stored)
        if (known.contains(k)) k,
    ];
    for (final k in all) {
      if (!out.contains(k)) out.add(k);
    }
    return out;
  }

  bool isHidden(String key) => _hidden?.contains(key) ?? false;

  Future<void> setHidden(String key, bool hidden) async {
    _hidden ??= <String>{};
    if (hidden) {
      _hidden!.add(key);
    } else {
      _hidden!.remove(key);
    }
    await _save();
  }

  Future<void> setOrder(List<String> order) async {
    _order = List<String>.from(order);
    await _save();
  }

  /// Back to the order the app ships with, everything visible.
  Future<void> reset() async {
    _order = const [];
    _hidden = <String>{};
    await _save();
  }

  @visibleForTesting
  void seed({List<String>? order, Set<String>? hidden}) {
    _order = order ?? const [];
    _hidden = hidden ?? <String>{};
  }
}
