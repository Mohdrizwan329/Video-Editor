import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';

/// The three colour tools that share one sheet.
///
/// A phone editor keeps its looks, its textures and its sliders behind one
/// button and switches between them in place — picking a look and then
/// nudging its contrast is one continuous thought, and closing a sheet to
/// reopen another breaks it. These are the three the tab bar switches.
enum ColorTool {
  /// One-tap colour grades — [FilterPanel].
  filter,

  /// Frames, textures and templates — [EffectsPanel].
  effect,

  /// The manual sliders — [AdjustPanel].
  adjust,
}

/// The tab bar along the bottom of the colour sheets.
///
/// It sits under the controls rather than in the title row because the title
/// row is already carrying close, apply-to-all and confirm; a fourth thing
/// there overflows a 360pt phone. Under the strip it also reads the way the
/// phone editors set it out: what you are looking at, then what else you
/// could be looking at.
class ColorToolTabs extends StatelessWidget {
  const ColorToolTabs({
    super.key,
    required this.current,
    required this.onSelected,
  });

  final ColorTool current;

  /// Null on a target that has only this one tool, which hides the bar
  /// rather than showing tabs that go nowhere.
  final ValueChanged<ColorTool>? onSelected;

  /// What the bar takes on a phone at the system font size.
  static const double kHeight = 30;

  /// The bar's real height, which is the label's line box plus the rule
  /// under it — measured through the text scaler rather than assumed. A user
  /// running large type otherwise gets a bar 2pt too short and a stripe
  /// across the bottom of the sheet.
  static double heightOf(BuildContext context) {
    final r = context.r;
    final line = MediaQuery.textScalerOf(context).scale(r.sp(11.5)) * 1.4;
    return math.max(r.vp(kHeight), line + r.vp(4) + 2 + r.vp(6));
  }

  static const Map<ColorTool, String> _labels = {
    ColorTool.filter: 'Filter',
    ColorTool.effect: 'Effect',
    ColorTool.adjust: 'Adjust',
  };

  @override
  Widget build(BuildContext context) {
    final pick = onSelected;
    if (pick == null) return const SizedBox.shrink();
    return SizedBox(
      height: heightOf(context),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final tool in ColorTool.values)
            Expanded(
              child: _Tab(
                label: _labels[tool]!,
                active: tool == current,
                // Re-tapping the tab you are on is a no-op, not a rebuild of
                // the panel you are already in the middle of using.
                onTap: tool == current ? null : () => pick(tool),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active, this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final color = active ? AppColors.accent : AppColors.textDim;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: r.sp(11.5),
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
          SizedBox(height: r.vp(4)),
          // The rule under the live tab is what carries the selection at a
          // glance; colour alone is not enough on a dim phone screen.
          Container(
            width: r.dp(22),
            height: 2,
            decoration: BoxDecoration(
              color: active ? AppColors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}

/// The two-way pill the phone editors put at the top of the colour sheet.
///
/// [ColorToolTabs] is the three-way rule that lived under the controls; this
/// is the pair the sheet actually switches between — the looks and the
/// sliders. Textures are their own tool on the bar, not a third tab here,
/// which is what makes the pill read as a switch rather than a menu.
class ColorToolPill extends StatelessWidget {
  const ColorToolPill({
    super.key,
    required this.current,
    required this.onSelected,
  });

  /// One of [ColorTool.filter] or [ColorTool.adjust].
  final ColorTool current;

  /// Null on a target with only one of the two, which hides the pill rather
  /// than offering a switch that goes nowhere.
  final ValueChanged<ColorTool>? onSelected;

  static const double kHeight = 34;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    if (onSelected == null) return const SizedBox.shrink();
    Widget half(ColorTool tool, String label) {
      final on = current == tool;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: on ? null : () => onSelected!(tool),
          child: Container(
            alignment: Alignment.center,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: on ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(r.vp(kHeight)),
              boxShadow: on
                  ? const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: r.sp(12.5),
                fontWeight: FontWeight.w600,
                color: on ? AppColors.text : AppColors.textDim,
              ),
            ),
          ),
        ),
      );
    }

    return Center(
      child: Container(
        height: r.vp(kHeight),
        width: r.dp(220),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(r.vp(kHeight)),
        ),
        child: Row(
          children: [
            half(ColorTool.filter, 'Filter'),
            half(ColorTool.adjust, 'Adjust'),
          ],
        ),
      ),
    );
  }
}
