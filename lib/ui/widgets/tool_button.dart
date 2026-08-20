import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

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
    this.width = 62,
    this.badge,
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

  final double width;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.textFaint
        : selected
            ? (accent ?? AppColors.accent)
            : (tint ?? AppColors.text);
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: enabled
                          ? color.withValues(alpha: selected ? 0.24 : 0.13)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      border: selected
                          ? Border.all(color: color.withValues(alpha: 0.5))
                          : null,
                    ),
                    child: Icon(icon, size: 19, color: color),
                  ),
                  if (badge != null)
                    Positioned(
                      right: -6,
                      top: -3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(badge!,
                            style: const TextStyle(
                                fontSize: 8,
                                color: AppColors.onAccent,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 9.5,
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
