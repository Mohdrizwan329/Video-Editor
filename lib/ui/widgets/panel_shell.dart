import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';

/// The sheet chrome every property panel sits in: a grab handle, a title row
/// with a close and a confirm action, and an optional reset.
///
/// A sheet opens at the height its own controls ask for — a tool with a
/// colour row and a line of help is not given the room a tab bar and a grid
/// of presets needs — capped at [_cap] so there is always a preview to edit
/// against.
///
/// The body does not scroll. A sheet that scrolls hides how much is left
/// under a gesture the user has to guess at, and on a tool like Adjust —
/// nineteen sliders — that is most of the panel. So the sheet keeps the
/// height it opened at and shows what fits, and everything past the fold
/// goes behind one "More options" button pinned under the body, which opens
/// the whole set of controls in a bottom sheet of its own. What is left is a
/// panel whose size is a promise: what you see is what this tool puts on the
/// first screen, and there is a labelled way to the rest.
///
/// The handle and the title row still drag the sheet taller for a user who
/// would rather have the room than the second sheet.
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
    this.footer,
  });

  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final VoidCallback? onConfirm;
  final VoidCallback? onReset;
  final Widget? trailing;
  final VoidCallback? applyToAll;

  /// Pinned under the body, outside the scroll view. A tool that switches
  /// the sheet to a sibling tool puts its tab bar here: it belongs to the
  /// sheet rather than to the controls, and scrolled away with the controls
  /// it would be a way out the user cannot find.
  final Widget? footer;

  /// The height a panel gets when it asks for room rather than measuring its
  /// own controls — see [bodyHeight].
  ///
  /// It is the tallest first screen any tool needs: the Effects and Stickers
  /// tabs, which are a tab bar over a row of presets. Anything less and those
  /// open on a row the user has to scroll to find. Panels that are just a
  /// column of controls ignore this and come out as tall as they are.
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

  static double _defaultHeight(Responsive r) => math.min(kSheetHeight, _cap(r));

  /// A wide window puts the panel in a rail beside the preview rather than
  /// under it. Nothing there is competing with the video for height, so the
  /// panel keeps the room its controls ask for and there is nothing to drag.
  static bool isRail(Responsive r) => r.width >= 1000 && r.width > r.height;

  /// The room a sheet's body has when it opens: the sheet, less its handle
  /// and title row.
  ///
  /// A panel whose content is a grid or a long list asks for this and scrolls
  /// *inside* it. Handing that kind of control a height of its own instead
  /// would leave it hanging past the bottom of the sheet, where only the
  /// "More options" sheet could reach it.
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
  /// Null until the user drags: the sheet is as tall as its controls, and
  /// only a deliberate drag pins it to a number.
  double? _dragged;

  /// The column being sized, so a drag can start from whatever height the
  /// content settled at rather than jumping to a default first.
  final GlobalKey _sheetKey = GlobalKey();

  /// The body's viewport, which is how the sheet knows whether there is
  /// anything left to reveal by growing. It never scrolls under a finger —
  /// see the class doc — it is only ever measured.
  final ScrollController _scroll = ScrollController();

  /// True once a laid-out frame has found more controls than the body can
  /// show. It is what puts the "More options" button on screen, so it is
  /// measured rather than guessed: the same panel overflows on a short phone
  /// and fits on a tall one.
  bool _overflows = false;

  /// The controls as the panel last built them, handed to the "More options"
  /// sheet through a listenable rather than as a snapshot. A slider moved in
  /// that sheet calls back into the panel, which rebuilds this shell with a
  /// fresh child — and the open sheet has to show the new value, not the one
  /// the tree had when it opened.
  ///
  /// It is filled after the frame rather than during it: notifying a
  /// listener in another route mid-build is the "markNeedsBuild during
  /// build" error. The sheet is one frame behind the finger, which is the
  /// price of not writing a copy of every panel.
  final ValueNotifier<Widget> _live = ValueNotifier(const SizedBox.shrink());

  /// The open "More options" route and the navigator holding it, so a panel
  /// that is torn down — the tool switched out from under it — takes its
  /// second sheet along instead of leaving it stranded over the editor.
  ModalRoute<void>? _moreRoute;
  NavigatorState? _navigator;

  @override
  void initState() {
    super.initState();
    _live.value = widget.child;
  }

  @override
  void dispose() {
    final route = _moreRoute;
    final navigator = _navigator;
    if (route != null && route.isActive) {
      // Routes cannot be removed while the tree is being torn down.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) navigator?.removeRoute(route);
      });
    }
    _scroll.dispose();
    _live.dispose();
    super.dispose();
  }

  /// Reads the laid-out body once the frame is done: how much of it is out of
  /// sight, and what the controls now are.
  ///
  /// Adding the button costs the body height, which can only make an
  /// overflowing panel overflow further, so this settles in one pass instead
  /// of flipping the button on and off frame after frame.
  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _live.value = widget.child;
      if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
      final overflows = _scroll.position.maxScrollExtent > 0.5;
      if (overflows != _overflows) setState(() => _overflows = overflows);
    });
  }

  /// How much of the body is currently out of sight. Growing the sheet past
  /// this only opens blank space under the last control, so a drag stops
  /// here even though the cap is further up.
  double get _hidden {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) {
      return double.infinity;
    }
    return math.max(0, _scroll.position.maxScrollExtent);
  }

  double _height(Responsive r) {
    final dragged = _dragged;
    if (dragged != null) return dragged;
    final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) return box.size.height;
    return PanelShell._defaultHeight(r);
  }

  void _resize(double dy, Responsive r) {
    final from = _height(r);
    // Up is negative in a drag delta and taller on screen.
    var next = from - dy;
    // Taller is only worth it while something is still hidden: a sheet whose
    // controls already fit has nothing to show for the room it would take
    // off the preview.
    if (dy < 0) next = math.min(next, from + _hidden);
    setState(() {
      _dragged = next.clamp(
        math.min(PanelShell.kMinSheetHeight, PanelShell._cap(r)),
        PanelShell._cap(r),
      );
    });
  }

  /// A tap on the handle hands the sheet back to its own controls, so a user
  /// who has dragged one taller does not have to eyeball their way back.
  void _reset() => setState(() => _dragged = null);

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final rail = PanelShell.isRail(r);
    _measure();
    // The two notches the rounded top corners cut out of the sheet are left
    // transparent: what belongs behind them is whatever strip the sheet is
    // docked under, and only the screen that docked it knows which that is.
    // See EditorScreen, which paints it.
    return Container(
      // The height goes on the column inside the safe area, not here: the
      // gesture bar the sheet fills in behind sits under it, and counting
      // that in would take the difference out of the controls.
      constraints: BoxConstraints(maxHeight: PanelShell._cap(r)),
      // The app bar's own colour, so the sheet reads as the other end of the
      // same frame rather than as a panel that floated in.
      //
      // The outline goes all the way round rather than along the top alone:
      // a one-sided border is drawn as a straight line and leaves the two
      // rounded corners to fade out into nothing, which is what made the
      // sheet look unfinished at its top edges. The bottom of the run sits
      // off the end of the screen behind the gesture bar.
      decoration: const ShapeDecoration(
        color: AppColors.surfaceSheet,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: AppColors.appBar, width: 1.2),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      // So no child can paint itself into a corner the shape has rounded off.
      clipBehavior: Clip.antiAlias,
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
          // Undragged, the column takes the height of what is in it and the
          // Flexible below trims it to the cap. Dragged, it is pinned to the
          // number the finger left it at and the body fills that instead.
          child: SizedBox(
            height: rail ? null : _dragged,
            child: Column(
              key: _sheetKey,
              mainAxisSize: (rail || _dragged == null)
                  ? MainAxisSize.min
                  : MainAxisSize.max,
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
                // A panel hands its controls over as a plain column and this
                // shows as many of them as the sheet's height has room for.
                // The scroll view is here to measure and to clip, never to
                // scroll: its physics refuse the gesture, and what it cuts
                // off is what the button below then offers by name.
                Flexible(
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        controller: _scroll,
                        physics: const NeverScrollableScrollPhysics(),
                        child: widget.child,
                      ),
                      // A control cut off mid-way by the fold looks like a
                      // drawing bug; the same control fading out reads as
                      // "there is more this way", which is what the button
                      // under it says in words.
                      if (_overflows)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              height: 16,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    AppColors.surfaceSheet
                                        .withValues(alpha: 0),
                                    AppColors.surfaceSheet,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_overflows) _moreButton(context, r),
                ?widget.footer,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The way to everything the sheet had to leave out. It is a labelled row
  /// rather than a chevron: "more" is the whole point of it, and a user who
  /// has just been shown eight of nineteen sliders should not have to work
  /// out that the panel is bigger than it looks.
  Widget _moreButton(BuildContext context, Responsive r) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        SizedBox(
          height: math.max(r.vp(38), 36),
          width: double.infinity,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              shape: const RoundedRectangleBorder(),
              padding: EdgeInsets.symmetric(horizontal: r.dp(12)),
            ),
            onPressed: () => _openMore(context),
            icon: Icon(Icons.expand_less, size: r.ic(18)),
            label: Text(
              'More options',
              style: TextStyle(
                fontSize: r.sp(12.5),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Opens the full set of controls in a sheet of its own.
  ///
  /// This one *is* allowed to scroll: it is a list the user asked for by
  /// name and it opens most of the way up the window, so its scroll bar is a
  /// list's scroll bar rather than a panel quietly hiding half of itself.
  Future<void> _openMore(BuildContext context) async {
    _navigator = Navigator.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceSheet,
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(maxHeight: context.r.height * 0.85),
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: AppColors.appBar, width: 1.2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        _moreRoute = ModalRoute.of(sheetContext);
        return _MoreSheet(title: widget.title, body: _live);
      },
    );
    _moreRoute = null;
  }

  Widget _handle() {
    return Tooltip(
      message: _dragged == null
          ? 'Drag to make this panel taller'
          : 'Drag to resize, tap to fit the controls',
      child: SizedBox(
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
      ),
    );
  }

  Widget _titleRow(BuildContext context, Responsive r, bool rail) {
    final row = Row(
      children: [
        IconButton(
          tooltip: 'Close without keeping the change',
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
            style: TextStyle(fontSize: r.sp(13.5), fontWeight: FontWeight.w600),
          ),
        ),
        if (widget.applyToAll != null)
          // The words have to stay short to fit the row, so what they *do* —
          // rewrite every clip on the track, not filter the view — is spelled
          // out here rather than in the label.
          Tooltip(
            message: 'Apply this setting to every clip',
            child: TextButton(
              onPressed: widget.applyToAll,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                'All clips',
                style: TextStyle(fontSize: r.sp(11), color: AppColors.textDim),
              ),
            ),
          ),
        if (widget.onReset != null)
          IconButton(
            tooltip: 'Reset to default',
            icon: Icon(Icons.restart_alt, size: r.ic(19)),
            color: AppColors.textDim,
            onPressed: widget.onReset,
          ),
        ?widget.trailing,
        IconButton(
          tooltip: 'Done',
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

/// The overflow half of a panel: everything the docked sheet could not fit,
/// shown on its own at a height that can hold it.
///
/// It renders whatever [body] currently holds rather than a copy taken when
/// it opened — the controls in here drive the same panel state the docked
/// sheet does, and a slider that did not move under the finger would be a
/// worse bug than the scroll this replaced.
class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.title, required this.body});

  final String title;
  final ValueListenable<Widget> body;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: ContentBox(
        maxWidth: 760,
        hugHeight: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: PanelShell.kHandleHeight,
              child: Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: math.max(r.vp(44), 44),
              child: Row(
                children: [
                  SizedBox(width: r.dp(12)),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: r.sp(13.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Closing this sheet is going back to the panel, not
                  // throwing the changes away: every control in here has
                  // already written to the project on the way past.
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Done',
                      style: TextStyle(
                        fontSize: r.sp(12.5),
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  SizedBox(width: r.dp(4)),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                child: ValueListenableBuilder<Widget>(
                  valueListenable: body,
                  builder: (_, child, _) => child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal row of plain text tabs, the way a phone editor labels the
/// packs inside a preset strip.
///
/// Pills ([ChipStrip]) are the app's usual answer for a category row, and
/// they still are wherever a sheet shows five or six of them. A library that
/// runs to fifteen packs is a different problem: fifteen pills is a row the
/// user drags through, where fifteen words is a row they read. The active
/// one is the only one that takes a colour, so the row stays quiet until it
/// is being used.
class TextTabStrip extends StatefulWidget {
  const TextTabStrip({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  static const double kHeight = 26;

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<TextTabStrip> createState() => _TextTabStripState();
}

class _TextTabStripState extends State<TextTabStrip> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return SizedBox(
      // The pack name's line box grows with the system font, so the row is
      // measured rather than assumed — at 1.3x an assumed row clips it.
      height: math.max(
        math.max(r.vp(TextTabStrip.kHeight), 24),
        MediaQuery.textScalerOf(context).scale(r.sp(11.5)) * 1.5,
      ),
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: r.dp(14)),
        itemCount: widget.labels.length,
        separatorBuilder: (_, _) => SizedBox(width: r.dp(16)),
        itemBuilder: (context, i) {
          final active = i == widget.selectedIndex;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onSelected(i),
            child: Center(
              child: Text(
                widget.labels[i],
                style: TextStyle(
                  fontSize: r.sp(11.5),
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? AppColors.accent : AppColors.textDim,
                ),
              ),
            ),
          );
        },
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
