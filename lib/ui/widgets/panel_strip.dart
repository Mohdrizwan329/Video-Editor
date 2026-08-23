import 'package:flutter/material.dart';

/// A row of tiles that shows what the sheet has room for and nothing more.
///
/// The presets used to sit in a horizontal list, so a look the user wanted
/// was somewhere off the right-hand edge with no sign of how far. This lays
/// the same tiles out as lines instead: what fits on the sheet's first
/// screen is on it, and the lines past the fold are what puts the 'More
/// options' button there — where they are all laid out at once, under a
/// heading, rather than dragged past a few at a time.
///
/// It never scrolls in either direction. In the docked sheet the extra lines
/// are simply clipped; in the taller sheet the button opens they are all on
/// screen, and only that sheet scrolls.
class PanelStrip extends StatelessWidget {
  const PanelStrip({
    super.key,
    required this.children,
    this.gap = 8,
    this.runGap = 8,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.alignment = WrapAlignment.start,
  });

  final List<Widget> children;

  /// Between tiles on a line.
  final double gap;

  /// Between lines.
  final double runGap;

  final EdgeInsets padding;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: gap,
        runSpacing: runGap,
        alignment: alignment,
        children: children,
      ),
    );
  }
}
