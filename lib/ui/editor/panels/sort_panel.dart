import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/duration_ext.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/models/video_clip.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_shell.dart';
import '../timeline/filmstrip.dart';

/// Re-orders the main track. The timeline already lets a clip be dragged into
/// place, but only while it is on screen — this lays the whole project out as
/// one row of cards so a clip can be moved from one end to the other.
class SortPanel extends StatelessWidget {
  const SortPanel({super.key, required this.editor, required this.onClose});

  final EditorController editor;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final clips = editor.project.clips;
    return PanelShell(
      title: 'Sort',
      onClose: onClose,
      onConfirm: onClose,
      child: clips.length < 2
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: r.vp(26)),
              child: Text(
                'Add a second clip to re-order the track',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: r.sp(12), color: AppColors.textDim),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: r.vp(6)),
                Text(
                  'Drag a clip to move it',
                  style: TextStyle(
                    fontSize: r.sp(10.5),
                    color: AppColors.textDim,
                  ),
                ),
                SizedBox(height: r.vp(8)),
                // Down the sheet, not across it, and it does not scroll:
                // a row that slid sideways put half the project off the
                // right-hand edge with no sign of how far, and a clip the
                // user cannot see is one they cannot move. The clips past
                // the fold are behind 'More options', where the whole track
                // is laid out and every one of them can still be dragged.
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  padding: EdgeInsets.symmetric(horizontal: r.dp(12)),
                  itemCount: clips.length,
                  proxyDecorator: (child, _, _) => Material(
                    color: Colors.transparent,
                    elevation: 6,
                    child: child,
                  ),
                  onReorder: (from, to) {
                    // ReorderableListView reports the slot the clip lands in
                    // *before* it is lifted out, so a move down the list is
                    // one index further along than the list actually wants.
                    editor.reorderClip(from, to > from ? to - 1 : to);
                  },
                  itemBuilder: (context, i) => ReorderableDragStartListener(
                    key: ValueKey(clips[i].id),
                    index: i,
                    child: _card(context, i, clips[i]),
                  ),
                ),
              ],
            ),
    );
  }

  /// One clip on the track: its place in the order, a thumbnail, and how
  /// long it runs. A row rather than a tile, because the list runs down the
  /// sheet now — and a row has somewhere to put the length in words.
  Widget _card(BuildContext context, int index, VideoClip clip) {
    final r = context.r;
    final tile = r.dp(44);
    final selected = editor.selection.id == clip.id;
    return Padding(
      key: ValueKey('sort-${clip.id}'),
      padding: EdgeInsets.only(bottom: r.vp(6)),
      child: GestureDetector(
        onTap: () => editor.selectClip(index),
        child: Container(
          padding: EdgeInsets.all(r.dp(6)),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? AppColors.accent : Colors.transparent,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: r.dp(22),
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: r.sp(10.5),
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.accent : AppColors.textDim,
                  ),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: tile,
                  height: tile,
                  child: Filmstrip(clip: clip, width: tile, height: tile),
                ),
              ),
              SizedBox(width: r.dp(10)),
              Expanded(
                child: Text(
                  clip.timelineDuration.pretty,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: r.sp(11.5),
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.accent : AppColors.text,
                  ),
                ),
              ),
              Icon(
                Icons.drag_handle,
                size: r.ic(19),
                color: AppColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
