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
    this.badge,
    this.maxLines = 1,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;
  /// Colour used while [selected].
  final Color? accent;

  /// Resting icon colour. Toolbars pass the header tone so the row reads as
  /// one set; [AppColors.danger] marks the destructive slot.
  final Color? tint;

  /// Phone-baseline width; the button scales it to the window. Left null it
  /// takes the toolbar's own 62.
  final double? width;
  final String? badge;

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
    return SizedBox(
      width: r.dp(width ?? 62),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: r.vp(6)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
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
                  if (badge != null)
                    Positioned(
                      right: -r.dp(6),
                      top: -r.dp(3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(badge!,
                            style: TextStyle(
                                fontSize: r.sp(8),
                                color: AppColors.onAccent,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
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
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
