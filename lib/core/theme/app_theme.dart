import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/constants.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static const String fontFamily = 'Poppins';

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accent,
        onPrimary: AppColors.onAccent,
        secondary: AppColors.appBar,
        onSecondary: Colors.white,
        tertiary: AppColors.appBarMuted,
        surface: AppColors.surface,
        onSurface: AppColors.text,
        surfaceContainerHighest: AppColors.surfaceHigh,
        outline: AppColors.stroke,
        error: AppColors.danger,
        // Material 3 tints elevated surfaces with the primary colour by
        // default, which made the app bar drift away from the scaffold.
        surfaceTint: Colors.transparent,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: fontFamily,
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      appBarTheme: const AppBarTheme(
        toolbarHeight: kAppBarHeight,
        backgroundColor: AppColors.appBar,
        foregroundColor: AppColors.onAppBar,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        // The status bar sits over the dark app bar, not the light page.
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.onAppBar,
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.text),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.surfaceHigh,
        thumbColor: AppColors.accent,
        overlayColor: AppColors.accent.withValues(alpha: 0.15),
        trackHeight: 2.5,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.onAccent
                : AppColors.surface),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.surfaceHigh),
        trackOutlineColor:
            WidgetStateProperty.all(Colors.transparent),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.surfaceHigh,
        circularTrackColor: AppColors.surfaceHigh,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 0.6),
      // Every popup — dialog, menu, sheet, snack bar — floats above the page
      // on the app bar's fill, so anything that leaves the page reads as the
      // same layer. Foregrounds come from the [AppColors.onAppBar] pair.
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.appBar,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.onAppBar,
        ),
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          color: AppColors.onAppBarDim,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.appBar,
        surfaceTintColor: Colors.transparent,
        // Material 3 resolves a menu entry's text through `labelTextStyle` and
        // ignores `textStyle` entirely — without this the items fall back to
        // `onSurface`, which is the page's near-black on the dark menu.
        // `textStyle` stays for anything still on the M2 path.
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: fontFamily,
            fontSize: 13.5,
            color: AppColors.onAppBar,
          ),
        ),
        textStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 13.5,
          color: AppColors.onAppBar,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textFaint),
        border: _inputBorder(AppColors.stroke),
        enabledBorder: _inputBorder(AppColors.stroke),
        focusedBorder: _inputBorder(AppColors.accent),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.appBar,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.appBar,
        contentTextStyle: TextStyle(
          color: AppColors.onAppBar,
          fontFamily: fontFamily,
        ),
        behavior: SnackBarBehavior.floating,
      ),
      splashFactory: InkRipple.splashFactory,
    );
  }

  /// Wraps popup content that Flutter does not theme for us. A dialog and a
  /// snack bar carry their own text style, but a bottom sheet does not: its
  /// children fall through to the page's near-black ink, which is invisible on
  /// the sheet's [AppColors.appBar] fill. The same goes for icons, which take
  /// the global [AppColors.text] icon theme.
  static Widget onPopup({required Widget child}) => DefaultTextStyle(
        style: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          color: AppColors.onAppBarDim,
        ),
        child: IconTheme(
          data: const IconThemeData(color: AppColors.onAppBar),
          child: child,
        ),
      );

  /// Outlined text action. A bare text button reads as a label rather than a
  /// target — on the popup's dark fill and on the light page alike — so every
  /// such action carries an outline in its own tone: [AppColors.dangerSoft]
  /// for the destructive one, [AppColors.appBarMuted] for a secondary action
  /// sitting on the page.
  static ButtonStyle outlinedAction({Color tone = AppColors.accentDim}) =>
      TextButton.styleFrom(
        foregroundColor: tone,
        side: BorderSide(color: tone.withValues(alpha: 0.45)),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(11)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minimumSize: const Size(0, 36),
      );

  /// Input decoration for a field inside a popup. The global
  /// [InputDecorationTheme] fills with [AppColors.surface], which is right on
  /// the light page and a white slab on a popup — this fills off the popup's
  /// own foreground instead.
  static InputDecoration dialogField(String? hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.onAppBar.withValues(alpha: 0.08),
        hintStyle: const TextStyle(color: AppColors.onAppBarDim),
        border: _inputBorder(AppColors.onAppBar.withValues(alpha: 0.20)),
        enabledBorder: _inputBorder(AppColors.onAppBar.withValues(alpha: 0.20)),
        focusedBorder: _inputBorder(AppColors.accentDim),
      );

  static OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: color, width: 1),
      );
}
