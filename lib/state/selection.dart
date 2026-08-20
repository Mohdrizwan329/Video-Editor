import '../data/models/enums.dart';

/// What the toolbar and the property panels are currently pointed at.
class EditorSelection {
  const EditorSelection({this.kind, this.id, this.index});

  const EditorSelection.none()
      : kind = null,
        id = null,
        index = null;

  final LaneKind? kind;
  final String? id;

  /// Only meaningful for main-track clips.
  final int? index;

  bool get isEmpty => kind == null;
  bool get isClip => kind == LaneKind.video;

  bool matches(LaneKind k, String layerId) => kind == k && id == layerId;

  @override
  bool operator ==(Object other) =>
      other is EditorSelection &&
      other.kind == kind &&
      other.id == id &&
      other.index == index;

  @override
  int get hashCode => Object.hash(kind, id, index);
}
