import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';

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

  /// Half the window at most, and less than that when the window is short —
  /// the editor still needs room for the preview and the timeline above.
  double _shellHeight(Responsive r) => math.min(r.vp(height!), _cap(r));

  static double _cap(Responsive r) => r.height * (r.isShort ? 0.42 : 0.5);

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Container(
      // The caller's height is a phone measurement. It grows a little on a
      // roomy window and is capped on a cramped one, so the sheet can never
      // push the editor's preview and timeline off the bottom.
      height: height == null ? null : _shellHeight(r),
      // A panel that sizes itself to its content is capped too, so it can
      // never grow past the room the editor set aside for it.
      constraints: BoxConstraints(maxHeight: _cap(r)),
      decoration: const BoxDecoration(
        color: AppColors.surfaceSheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        // A sheet is a column of controls, not a banner: past a comfortable
        // width it centres instead of stretching its sliders across a monitor.
        child: ContentBox(
          maxWidth: 760,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: math.max(r.vp(44), 44),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.close, size: r.ic(20)),
                      color: AppColors.textDim,
                      onPressed: onClose ?? () => Navigator.maybePop(context),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: r.sp(13.5),
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (applyToAll != null)
                      TextButton(
                        onPressed: applyToAll,
                        style: TextButton.styleFrom(
                            minimumSize: const Size(0, 32),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8)),
                        child: Text('All',
                            style: TextStyle(
                                fontSize: r.sp(11), color: AppColors.textDim)),
                      ),
                    if (onReset != null)
                      IconButton(
                        icon: Icon(Icons.restart_alt, size: r.ic(19)),
                        color: AppColors.textDim,
                        onPressed: onReset,
                      ),
                    ?trailing,
                    IconButton(
                      icon: Icon(Icons.check, size: r.ic(21)),
                      color: AppColors.accent,
                      onPressed: onConfirm ?? () => Navigator.maybePop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // The body keeps the size it was drawn for and scrolls when the
              // window cannot show all of it — a phone in landscape, a small
              // desktop window, or a large system font. Every panel's own
              // Expanded rows sit inside a fixed-height box, so handing the
              // body an unbounded height here is safe.
              Flexible(
                child: SingleChildScrollView(
                  child: height == null
                      ? child
                      : SizedBox(
                          height: r.vp(height!) - math.max(r.vp(44), 44) - 1,
                          child: child,
                        ),
                ),
              ),
            ],
          ),
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
    final r = context.r;
    return SizedBox(
      height: math.max(r.vp(height), 32),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: r.dp(12)),
        itemCount: labels.length,
        separatorBuilder: (_, _) => SizedBox(width: r.dp(8)),
        itemBuilder: (context, i) {
          final active = i == selectedIndex;
          return GestureDetector(
            onTap: () => onSelected(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: r.dp(14)),
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
                  fontSize: r.sp(11.5),
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
