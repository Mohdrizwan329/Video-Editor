import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The app's brand mark: the clapper-and-scissors logo shipped in
/// `assets/logo/app_logo.png`.
///
/// The artwork is drawn for a white ground, so the widget keeps that plate and
/// rounds it into the same squircle the rest of the app's tiles use. One
/// asset serves every size the app asks for, from the 34px app-bar tile to the
/// splash mark, because it is exported at 1024px and scaled down.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 84, this.glow = false});

  /// Path to the mark, exposed so precacheImage callers do not restate it.
  static const String asset = 'assets/logo/app_logo.png';

  final double size;

  /// Splash-sized uses lift the mark off the page; the app bar does not.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.29);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        boxShadow: glow ? AppColors.glow(AppColors.violet, opacity: 0.5) : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // The mark is decorative next to the app's own name, which is always
          // spelled out beside it.
          excludeFromSemantics: true,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
