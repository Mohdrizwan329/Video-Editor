import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

/// Layout classes the whole app agrees on. They follow the Material window
/// size classes so a phone, a tablet, a browser window and a desktop window
/// all land in a bucket the screens already know how to draw.
enum ScreenClass {
  /// Phones in portrait, and any window narrower than a phone.
  compact,

  /// Large phones in landscape, small tablets, half-screen desktop windows.
  medium,

  /// Tablets in landscape and ordinary desktop/browser windows.
  expanded,

  /// Maximised desktop windows and anything wider.
  large,
}

/// Every hard-coded size in the UI was authored against this width — a 390pt
/// phone. Scaling is expressed as a ratio to it, so a value of `14` still
/// means "14 on a normal phone" everywhere it appears.
const double _kDesignWidth = 390.0;

/// …and this height, for the vertical rhythm.
const double _kDesignHeight = 780.0;

/// One resolved answer to "how big is this window, and what should sizes be
/// on it". Read it from a [BuildContext] with `context.r` — it is cheap
/// enough to build per widget and it depends on [MediaQuery], so a window
/// resize, a rotation or a keyboard rebuilds everything that uses it.
class Responsive {
  Responsive._(this.size, this.orientation, this.viewPadding, this.viewInsets);

  factory Responsive.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Responsive._(mq.size, mq.orientation, mq.viewPadding, mq.viewInsets);
  }

  final Size size;
  final Orientation orientation;
  final EdgeInsets viewPadding;
  final EdgeInsets viewInsets;

  double get width => size.width;
  double get height => size.height;
  double get shortestSide => size.shortestSide;

  bool get isLandscape => orientation == Orientation.landscape;

  ScreenClass get screen {
    if (width < 600) return ScreenClass.compact;
    if (width < 1024) return ScreenClass.medium;
    if (width < 1440) return ScreenClass.expanded;
    return ScreenClass.large;
  }

  bool get isCompact => screen == ScreenClass.compact;
  bool get isExpanded => screen == ScreenClass.expanded;

  /// A phone-sized window, whichever way round it is held.
  bool get isPhone => shortestSide < 600;

  /// A window short enough that stacked fixed-height strips stop fitting —
  /// a phone in landscape, or a browser window dragged down to a sliver.
  bool get isShort => height < 620;

  /// Ratio of this window to the phone the UI was drawn on, damped above the
  /// baseline so a 13" laptop does not get 3× everything, and floored so a
  /// 320pt phone shrinks rather than overflows.
  double get scale {
    final raw = shortestSide / _kDesignWidth;
    final damped = raw <= 1 ? raw : 1 + (raw - 1) * 0.32;
    return damped.clamp(0.82, 1.25);
  }

  /// Type grows more slowly than boxes do: past a point a bigger screen means
  /// more content, not bigger letters.
  double get _typeScale => 1 + (scale - 1) * 0.62;

  /// Vertical rhythm also answers to the window's height, so a landscape
  /// phone tightens its stacks instead of pushing them off the bottom.
  double get _verticalScale {
    final byHeight = (height / _kDesignHeight).clamp(0.72, 1.25);
    return math.min(scale, byHeight);
  }

  /// A size in logical pixels — paddings, radii, box sizes.
  double dp(double value) => value * scale;

  /// A font size.
  double sp(double value) => value * _typeScale;

  /// A vertical gap or a fixed row height.
  double vp(double value) => value * _verticalScale;

  /// An icon size. Icons track type rather than boxes so a label and the icon
  /// beside it keep their proportions.
  double ic(double value) => value * _typeScale;

  /// The page's horizontal margin. Wider windows get more breathing room, but
  /// the content itself is capped by [maxContentWidth] so it never sprawls.
  double get gutter => switch (screen) {
    ScreenClass.compact => dp(14),
    ScreenClass.medium => 22,
    ScreenClass.expanded => 28,
    ScreenClass.large => 32,
  };

  /// How wide a column of reading-and-tapping content may get. Beyond this a
  /// page centres itself rather than stretching rows to a metre wide.
  double get maxContentWidth => switch (screen) {
    ScreenClass.compact => double.infinity,
    ScreenClass.medium => 720,
    ScreenClass.expanded => 900,
    ScreenClass.large => 1000,
  };

  /// Dialogs and bottom sheets follow the same rule, a little tighter.
  double get maxDialogWidth => isCompact ? double.infinity : 520;

  /// Picks the value that belongs to this window, falling back down the
  /// classes so only the cases that differ have to be spelled out.
  T pick<T>({required T compact, T? medium, T? expanded, T? large}) {
    return switch (screen) {
      ScreenClass.compact => compact,
      ScreenClass.medium => medium ?? compact,
      ScreenClass.expanded => expanded ?? medium ?? compact,
      ScreenClass.large => large ?? expanded ?? medium ?? compact,
    };
  }

  /// A tap target never falls below the platform minimum, however small the
  /// window gets.
  double tap(double value) => math.max(value * scale, 44);
}

extension ResponsiveContext on BuildContext {
  /// The window's measurements and the scaling rules that go with them.
  Responsive get r => Responsive.of(this);
}

/// Centres its child and stops it growing past [Responsive.maxContentWidth],
/// so a page that reads well on a phone does not turn into a single stretched
/// row on a desktop monitor. [padded] adds the page gutter as well.
class ContentBox extends StatelessWidget {
  const ContentBox({
    super.key,
    required this.child,
    this.maxWidth,
    this.padded = false,
    this.alignment = Alignment.topCenter,
    this.hugHeight = false,
  });

  final Widget child;
  final double? maxWidth;
  final bool padded;
  final AlignmentGeometry alignment;

  /// Take the child's height instead of the full height on offer. A page
  /// wants the fill; a bottom sheet wants to end where its controls do.
  final bool hugHeight;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final limit = maxWidth ?? r.maxContentWidth;
    return Align(
      alignment: alignment,
      heightFactor: hugHeight ? 1.0 : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: limit),
        child: padded
            ? Padding(
                padding: EdgeInsets.symmetric(horizontal: r.gutter),
                child: child,
              )
            : child,
      ),
    );
  }
}

/// Scroll behaviour that lets a mouse and a trackpad drag a scroll view the
/// way a finger does. Without it every horizontal strip in the app — the
/// toolbar, the chip rows, the timeline — is unreachable on desktop and web.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };
}
