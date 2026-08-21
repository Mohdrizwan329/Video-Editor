import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';

/// The tool families along the very bottom of the editor. Each one swaps the
/// strip of tools above the timeline for its own set — the same shape every
/// phone editor uses, so the tools a user is looking for are one tap away
/// instead of somewhere along one very long scrolling row.
enum ToolCategory { trim, music, text, adjust, filter, frame }

extension ToolCategoryInfo on ToolCategory {
  String get label => switch (this) {
    ToolCategory.trim => 'Trim',
    ToolCategory.music => 'Music',
    ToolCategory.text => 'Text',
    ToolCategory.adjust => 'Adjust',
    ToolCategory.filter => 'Filter',
    ToolCategory.frame => 'Frame',
  };

  IconData get icon => switch (this) {
    ToolCategory.trim => Icons.content_cut,
    ToolCategory.music => Icons.music_note,
    ToolCategory.text => Icons.title,
    ToolCategory.adjust => Icons.tune,
    // The same pair the photo editor uses for these two, so the two editors
    // read as one app.
    ToolCategory.filter => Icons.photo_filter,
    ToolCategory.frame => Icons.filter_frames,
  };
}

/// The bottom-most strip: one tab per [ToolCategory], the active one picked
/// out in the accent colour.
class CategoryBar extends StatelessWidget {
  const CategoryBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final ToolCategory selected;
  final void Function(ToolCategory) onSelected;

  /// A phone on its side has to fit a preview, a tool strip, the timeline and
  /// this row into 390pt. The labels are the part that gives way — the icons
  /// carry the row on their own there.
  static bool _compact(Responsive r) => r.isShort;

  /// The tab row itself, measured through the text scaler — a large system
  /// font grows the row rather than clipping the labels off the bottom of it.
  static double rowHeight(BuildContext context) {
    final r = context.r;
    if (_compact(r)) return r.vp(6) + r.ic(21) + r.vp(6);
    final label = MediaQuery.textScalerOf(context).scale(r.sp(10)) * 1.6;
    return r.vp(7) + r.ic(21) + r.vp(4) + label + r.vp(7);
  }

  /// The row plus the bottom inset it sits above — this strip is what meets
  /// the navigation bar now.
  static double heightFor(BuildContext context) =>
      rowHeight(context) + context.r.viewPadding.bottom;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: rowHeight(context),
          child: Row(
            children: [
              for (final category in ToolCategory.values)
                Expanded(child: _tab(context, category)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, ToolCategory category) {
    final r = context.r;
    final active = category == selected;
    final color = active ? AppColors.accent : AppColors.textDim;
    final compact = _compact(r);
    return InkWell(
      onTap: () => onSelected(category),
      child: Padding(
        padding: EdgeInsets.symmetric(
            vertical: compact ? r.vp(6) : r.vp(7), horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The label is what a screen reader reads out either way, so
            // dropping it from the row costs nothing there.
            Tooltip(
              message: category.label,
              child: Icon(category.icon, size: r.ic(21), color: color),
            ),
            if (!compact) ...[
              SizedBox(height: r.vp(4)),
              Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: r.sp(10),
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
