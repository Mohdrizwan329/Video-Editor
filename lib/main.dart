import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_env.dart';
import 'core/utils/responsive.dart';
import 'state/projects_controller.dart';
import 'ui/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Reads the bundled .env so the Gemini key is ready before any screen can
  // ask for it. A missing file is not fatal; generation reports it instead.
  await AppEnv.load();
  await _applyOrientationLock();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      // The splash shows first and carries the dark app-bar fill; the splash
      // hands the light page bars back before the home screen appears.
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.appBar,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  // The chroma shader and the first project load now happen behind the splash
  // screen, so nothing is awaited here and the first frame arrives sooner.
  runApp(const VideoEditorApp());
}

/// Phones are held one way up, so they stay locked to portrait. Anything with
/// room for a landscape layout — tablets, foldables, desktop and web windows —
/// is free to rotate or be resized, because every screen now lays itself out
/// from the window it is given.
Future<void> _applyOrientationLock() async {
  if (kIsWeb) return;
  final onMobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (!onMobile) return;

  final view = ui.PlatformDispatcher.instance.implicitView;
  final ratio = view?.devicePixelRatio ?? 1;
  final logical = view == null || ratio <= 0
      ? Size.zero
      : view.physicalSize / ratio;
  // A zero size means the view has not been measured yet; treat it as a phone,
  // which is the safe default for the platforms this branch can reach.
  final isPhone = logical.shortestSide == 0 || logical.shortestSide < 600;

  await SystemChrome.setPreferredOrientations(
    isPhone
        ? const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
        : DeviceOrientation.values,
  );
}

class VideoEditorApp extends StatelessWidget {
  const VideoEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProjectsController(),
      child: MaterialApp(
        title: 'Video Editor',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        themeMode: ThemeMode.light,
        // Mouse and trackpad drags scroll the app's horizontal strips — the
        // toolbar, the chip rows, the timeline — the same way a finger does.
        scrollBehavior: const AppScrollBehavior(),
        // The navigation-bar colour every screen gets unless it wraps itself in
        // its own AnnotatedRegion. Declaring it here rather than setting it
        // imperatively means it is re-resolved from the tree on every frame, so
        // popping back from a screen that overrode it restores this one.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            systemNavigationBarColor: AppColors.background,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: MediaQuery.withClampedTextScaling(
            // The editor's strips are sized to their labels. A system font
            // scale beyond this overflows them, so text grows to a point and
            // then stops rather than breaking the layout.
            minScaleFactor: 0.85,
            maxScaleFactor: 1.3,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
