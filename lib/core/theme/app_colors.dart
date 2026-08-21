import 'package:flutter/material.dart';

/// Aurora palette: a soft off-white base lit by a set of saturated hues.
///
/// The base tones stay light and low-chroma so the chrome recedes and the
/// footage in the preview stays the focus; the colour comes from [accent] for
/// interactive state, the hue constants for anything that needs to look
/// distinct at a glance (tools, categories, tracks), and the gradients for
/// hero surfaces. Every hue is picked to clear 4.5:1 against [surface], so the
/// same constant works as a fill *and* as text/icon colour.
class AppColors {
  AppColors._();

  // ----------------------------------------------------------------- base
  static const Color background = Color(0xFFF5F4FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceHigh = Color(0xFFECEAF5);
  static const Color surfaceSheet = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE3E0EF);
  static const Color stroke = Color(0xFFCFCBE2);

  /// One flat fill for every top bar in the app — no gradient, no elevation
  /// tint — so the header reads the same on every screen. It stays dark while
  /// the page below it is light, so [onAppBar] (not [text]) is what anything
  /// sitting *in* the bar must be painted with.
  static const Color appBar = Color(0xFF15122A);
  static const Color onAppBar = Color(0xFFF4F2FF);
  static const Color onAppBarDim = Color(0xFFA49FC4);

  /// Tonal steps off [appBar]. Surfaces on the light page that belong to the
  /// header — the home cards and their icons — take their colour from here
  /// instead of the hue constants, so the page reads as one bar-and-page pair
  /// rather than a set of unrelated tiles.
  ///
  /// [appBarSoft] is the lifted end of the header fill; [appBarMuted] is the
  /// step that still clears 4.5:1 as an icon or label on [background].
  static const Color appBarSoft = Color(0xFF2C2652);
  static const Color appBarMuted = Color(0xFF4A4374);

  /// The header fill as a gradient — for cards that carry the app bar's
  /// weight (the primary action, icon tiles, cover placeholders).
  static const LinearGradient appBarGradient = LinearGradient(
    colors: [appBar, appBarSoft],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // --------------------------------------------------------------- accent
  //
  // These tones are pinned by contrast, not by taste: [accent] carries the
  // interactive graphics (progress rings, the playhead, the confirm tick) and
  // has to clear 3:1 on every light fill the app paints, while [warning] and
  // [danger] are read as text and have to clear 4.5:1 there. The dark popups
  // take [accentDim] and [dangerSoft] instead — see [appBar].
  static const Color accent = Color(0xFF0D8E78);
  static const Color accentDim = Color(0xFF7CCFC2);
  static const Color warning = Color(0xFF8F5500);
  static const Color danger = Color(0xFFBF1F38);

  /// [danger] only clears 3.9:1 on [appBar], so popups — which now carry the
  /// bar's fill — use this lifted red for their destructive action instead.
  static const Color dangerSoft = Color(0xFFFF7A8F);

  /// Foreground for anything filled with [accent] or a hue — the hues are
  /// dark enough now that white, not black, is the readable choice.
  static const Color onAccent = Color(0xFFFFFFFF);

  // ------------------------------------------------------------ hue wheel
  static const Color violet = Color(0xFF7C3AED);
  static const Color sky = Color(0xFF0284C7);
  static const Color pink = Color(0xFFDB2777);

  // ------------------------------------------------------------- text
  static const Color text = Color(0xFF14121F);
  static const Color textDim = Color(0xFF55506E);
  static const Color textFaint = Color(0xFF645F7D);

  // --------------------------------------------------------- timeline
  static const Color timelineBg = Color(0xFFE9E7F2);
  static const Color clipBorder = Color(0xFFCFCBE2);
  static const Color playhead = Color(0xFF14121F);

  static const Color trackAudio = Color(0xFF0F9C7C);
  static const Color trackText = Color(0xFF4F46E5);
  static const Color trackSticker = Color(0xFF9333EA);
  static const Color trackOverlay = Color(0xFFC2660A);

  // -------------------------------------------------------- gradients
  static const LinearGradient heroGradient = LinearGradient(
    colors: [violet, pink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient oceanGradient = LinearGradient(
    colors: [sky, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Card fill that hints at [hue] without lifting the surface far off the
  /// background — used for tiles that carry an icon in the same hue.
  static LinearGradient tint(Color hue) => LinearGradient(
        colors: [
          Color.alphaBlend(hue.withValues(alpha: 0.14), surface),
          Color.alphaBlend(hue.withValues(alpha: 0.04), surface),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Soft glow for a hue-coloured card, kept cheap enough for list scroll.
  static List<BoxShadow> glow(Color hue, {double opacity = 0.22}) => [
        BoxShadow(
          // Halved against the dark original: the same alpha that read as a
          // soft halo on near-black turns into a dirty smudge on off-white.
          color: hue.withValues(alpha: opacity * 0.5),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];
}
