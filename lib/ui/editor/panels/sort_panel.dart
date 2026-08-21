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
  const SortPanel({
    super.key,
    required this.editor,
    required this.onClose,
  });

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
                style:
                    TextStyle(fontSize: r.sp(12), color: AppColors.textDim),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: r.vp(6)),
                Text(
                  'Drag a clip to move it',
                  style:
                      TextStyle(fontSize: r.sp(10.5), color: AppColors.textDim),
                ),
                SizedBox(height: r.vp(8)),
                SizedBox(
                  height: r.dp(96),
                  child: ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
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
                      // *before* it is lifted out, so a move to the right is
                      // one index further along than the list actually wants.
                      editor.reorderClip(from, to > from ? to - 1 : to);
                    },
                    itemBuilder: (context, i) => ReorderableDragStartListener(
                      key: ValueKey(clips[i].id),
                      index: i,
                      child: _card(context, i, clips[i]),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _card(BuildContext context, int index, VideoClip clip) {
    final r = context.r;
    final tile = r.dp(64);
    final selected = editor.selection.id == clip.id;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.dp(4)),
      child: GestureDetector(
        onTap: () => editor.selectClip(index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: tile,
              height: tile,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.clipBorder,
                  width: selected ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Filmstrip(clip: clip, width: tile, height: tile),
                    Positioned(
                      left: 3,
                      top: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.appBar.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: r.sp(9),
                            fontWeight: FontWeight.w700,
                            color: AppColors.onAppBar,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: r.vp(4)),
            SizedBox(
              width: tile,
              child: Text(
                clip.timelineDuration.pretty,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: r.sp(9.5),
                  color: selected ? AppColors.accent : AppColors.textDim,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
