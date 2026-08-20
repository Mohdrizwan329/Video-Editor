import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The sheet chrome every property panel sits in: a title row with a close
/// and a confirm action, and an optional reset.
class PanelShell extends StatelessWidget {
  const PanelShell({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
    this.onConfirm,
    this.onReset,
    this.height,
    this.trailing,
    this.applyToAll,
  });

  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final VoidCallback? onConfirm;
  final VoidCallback? onReset;
  final double? height;
  final Widget? trailing;
  final VoidCallback? applyToAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: AppColors.surfaceSheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: AppColors.textDim,
                    onPressed: onClose ?? () => Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (applyToAll != null)
                    TextButton(
                      onPressed: applyToAll,
                      style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: const Text('All',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textDim)),
                    ),
                  if (onReset != null)
                    IconButton(
                      icon: const Icon(Icons.restart_alt, size: 19),
                      color: AppColors.textDim,
                      onPressed: onReset,
                    ),
                  ?trailing,
                  IconButton(
                    icon: const Icon(Icons.check, size: 21),
                    color: AppColors.accent,
                    onPressed: onConfirm ?? () => Navigator.maybePop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

/// Horizontal chip row used for presets (filters, fonts, transitions…).
class ChipStrip extends StatelessWidget {
  const ChipStrip({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.height = 34,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final active = i == selectedIndex;
          return GestureDetector(
            onTap: () => onSelected(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                gradient: active ? AppColors.appBarGradient : null,
                color: active ? null : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: active
                      ? Colors.transparent
                      : AppColors.appBar.withValues(alpha: 0.16),
                ),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: active ? AppColors.onAppBar : AppColors.textDim,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
