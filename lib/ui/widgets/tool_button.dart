import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';

/// Icon-over-label button used across the editor toolbars.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.selected = false,
    this.enabled = true,
    this.accent,
    this.tint,
    this.width,
    this.maxLines = 1,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  /// Whether the tool can do anything right now.
  ///
  /// A tool that cannot still answers a tap: it goes grey so the row shows at
  /// a glance what is live, and the tap is passed on so the screen can say
  /// *why* — 'Add a video or photo first' teaches; a dead button does not.
  final bool enabled;

  /// Colour used while [selected].
  final Color? accent;

  /// Resting icon colour. Toolbars pass the header tone so the row reads as
  /// one set; [AppColors.danger] marks the destructive slot.
  final Color? tint;

  /// Phone-baseline width; the button scales it to the window. Left null it
  /// takes the toolbar's own 62.
  final double? width;

  /// How many lines the label may take. The bottom strip gives it two, so a
  /// two-word tool keeps its name at a large system font size.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final color = !enabled
        ? AppColors.textFaint
        : selected
        ? (accent ?? AppColors.accent)
        : (tint ?? AppColors.text);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox(
        width: r.dp(width ?? 62),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: r.vp(6)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: r.dp(34),
                  height: r.dp(34),
                  decoration: BoxDecoration(
                    color: enabled
                        ? color.withValues(alpha: selected ? 0.24 : 0.13)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    border: selected
                        ? Border.all(color: color.withValues(alpha: 0.5))
                        : null,
                  ),
                  child: Icon(icon, size: r.ic(19), color: color),
                ),
                SizedBox(height: r.vp(4)),
                Text(
                  label,
                  maxLines: maxLines,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: r.sp(9.5),
                    color: enabled
                        ? (selected ? color : AppColors.textDim)
                        : AppColors.textFaint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
