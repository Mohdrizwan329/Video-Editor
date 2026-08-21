import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';

/// The sheet chrome every property panel sits in: a grab handle, a title row
/// with a close and a confirm action, and an optional reset.
///
/// Every sheet opens at the same height whichever tool opened it — see
/// [kSheetHeight] — and from there the user has two independent gestures: drag
/// the handle or the title row to resize the sheet, and scroll the body to
/// reach a control past its bottom edge. They never fight each other, because
/// only the chrome above the divider drags and only the body below it scrolls.
class PanelShell extends StatefulWidget {
  const PanelShell({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
    this.onConfirm,
    this.onReset,
    this.trailing,
    this.applyToAll,
  });

  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final VoidCallback? onConfirm;
  final VoidCallback? onReset;
  final Widget? trailing;
  final VoidCallback? applyToAll;

  /// How tall a sheet opens, whichever tool opened it.
  ///
  /// The preview is whatever the sheet leaves over, so a sheet that sized
  /// itself to its own controls resized the video every time the user moved
  /// from one tool to the next — a tall tool shrank it, a short one grew it
  /// back. One height for all of them keeps the video the same size across
  /// the whole toolbar; a tool with more controls than fit scrolls, and a
  /// user who wants to see more of one drags it taller.
  ///
  /// The number is the tallest first screen any tool needs — the Effects and
  /// Stickers tabs, which are a tab bar over a row of presets. Anything less
  /// and those open on a row the user has to scroll to find.
  static const double kSheetHeight = 214;

  /// The handle strip above the title row: what the user grabs to resize.
  static const double kHandleHeight = 14;

  /// Dragged all the way down, a sheet still shows its title row and a
  /// control or two — collapsing it to nothing is what the close button is
  /// for.
  static const double kMinSheetHeight = 132;

  /// A sheet is never more than half the window, or 42% of a short one —
  /// dragged or otherwise. Past that there is no preview left to edit against.
  static double _cap(Responsive r) => r.height * (r.isShort ? 0.42 : 0.5);

  static double _defaultHeight(Responsive r) =>
      math.min(kSheetHeight, _cap(r));

  /// A wide window puts the panel in a rail beside the preview rather than
  /// under it. Nothing there is competing with the video for height, so the
  /// panel keeps the room its controls ask for and there is nothing to drag.
  static bool isRail(Responsive r) => r.width >= 1000 && r.width > r.height;

  /// The room a sheet's body has when it opens: the sheet, less its handle
  /// and title row.
  ///
  /// A panel whose content is a grid or a long list asks for this and scrolls
  /// *inside* it. Handing that kind of control a height of its own instead
  /// would leave it hanging past the bottom of the sheet, reachable only by
  /// dragging the sheet taller.
  static double bodyHeight(BuildContext context) {
    final r = context.r;
    final sheet = isRail(r) ? _cap(r) : _defaultHeight(r);
    return math.max(sheet - _chromeHeight(r), 72);
  }

  static double _chromeHeight(Responsive r) =>
      kHandleHeight + math.max(r.vp(44), 44) + 1;

  @override
  State<PanelShell> createState() => _PanelShellState();
}

class _PanelShellState extends State<PanelShell> {
  /// Null until the user drags: the sheet opens at the height every other
  /// sheet opens at, and only a deliberate drag takes it off that.
  double? _dragged;

  double _height(Responsive r) =>
      _dragged ?? PanelShell._defaultHeight(r);

  void _resize(double dy, Responsive r) {
    setState(() {
      // Up is negative in a drag delta and taller on screen.
      _dragged = (_height(r) - dy).clamp(
        math.min(PanelShell.kMinSheetHeight, PanelShell._cap(r)),
        PanelShell._cap(r),
      );
    });
  }

  /// A tap on the handle puts the sheet back where every other sheet sits, so
  /// a user who has dragged one taller does not have to eyeball their way
  /// back to the size the video was.
  void _reset() => setState(() => _dragged = null);

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final rail = PanelShell.isRail(r);
    return Container(
      // The height goes on the column inside the safe area, not here: the
      // gesture bar the sheet fills in behind sits under it, and counting
      // that in would take the difference out of the controls.
      constraints: BoxConstraints(maxHeight: PanelShell._cap(r)),
      decoration: const BoxDecoration(
        color: AppColors.surfaceSheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        // A sheet that hugs its content would otherwise end flush against the
        // screen edge on a device with no gesture bar to sit behind.
        minimum: const EdgeInsets.only(bottom: 8),
        // A sheet is a column of controls, not a banner: past a comfortable
        // width it centres instead of stretching its sliders across a monitor.
        child: ContentBox(
          maxWidth: 760,
          // Hug: an Align with no height factor fills whatever it is given,
          // which pinned every sheet to the cap below and left the space
          // under its controls empty.
          hugHeight: true,
          child: SizedBox(
            height: rail ? null : _height(r),
            child: Column(
              mainAxisSize: rail ? MainAxisSize.min : MainAxisSize.max,
              children: [
                // The chrome is the drag target. It is a single gesture
                // detector over the handle and the title row together, so the
                // grab area is a comfortable 58pt rather than a 4pt pill.
                if (!rail)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (d) => _resize(d.delta.dy, r),
                    onTap: _dragged == null ? null : _reset,
                    child: _handle(),
                  ),
                SizedBox(
                  height: math.max(r.vp(44), 44),
                  child: _titleRow(context, r, rail),
                ),
                const Divider(height: 1),
                // The one scroll view in a sheet. A panel hands its controls
                // over as a plain column and this reaches whatever the height
                // cannot show, so no panel has to size itself to the sheet
                // and none of them can strand a control off the bottom.
                Flexible(
                  child: SingleChildScrollView(child: widget.child),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _handle() {
    return SizedBox(
      height: PanelShell.kHandleHeight,
      child: Center(
        child: Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: _dragged == null ? AppColors.divider : AppColors.textFaint,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _titleRow(BuildContext context, Responsive r, bool rail) {
    final row = Row(
      children: [
        IconButton(
          icon: Icon(Icons.close, size: r.ic(20)),
          color: AppColors.textDim,
          onPressed: widget.onClose ?? () => Navigator.maybePop(context),
        ),
        Expanded(
          child: Text(
            widget.title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: r.sp(13.5), fontWeight: FontWeight.w600),
          ),
        ),
        if (widget.applyToAll != null)
          TextButton(
            onPressed: widget.applyToAll,
            style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: Text('All clips',
                style:
                    TextStyle(fontSize: r.sp(11), color: AppColors.textDim)),
          ),
        if (widget.onReset != null)
          IconButton(
            icon: Icon(Icons.restart_alt, size: r.ic(19)),
            color: AppColors.textDim,
            onPressed: widget.onReset,
          ),
        ?widget.trailing,
        IconButton(
          icon: Icon(Icons.check, size: r.ic(21)),
          color: AppColors.accent,
          onPressed: widget.onConfirm ?? () => Navigator.maybePop(context),
        ),
      ],
    );
    if (rail) return row;
    // The title row drags too. Its buttons still win the arena — a tap on
    // close is a tap, not a drag — so this only picks up the space between
    // them, which is most of the row.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => _resize(d.delta.dy, r),
      child: row,
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
    this.height = kHeight,
  });

  /// What the row takes when nothing asks for otherwise. Named so a control
  /// that stands in for the pills can match them rather than guess.
  static const double kHeight = 34;

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

/// The body of a property panel.
///
/// Panels used to hand [PanelShell] a fixed-height box drawn for their
/// *tallest* tab, so every shorter tab padded itself out with dead space and
/// the preview above lost that height for nothing. The sheet is one height
/// for every tool now and [PanelShell] scrolls it, so a body is simply the
/// controls it has — this passes them straight through and stays only as the
/// name panels use to say "this is the body".
///
/// The child column must be `mainAxisSize: MainAxisSize.min`, and it may not
/// use `Expanded`/`Flexible` down the page: the sheet scrolls, so there is no
/// leftover height to expand into. A control that needs a viewport of its own
/// — a grid, a long list — asks for a height outright.
class PanelBody extends StatelessWidget {
  const PanelBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
