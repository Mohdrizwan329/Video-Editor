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

  // Load environment variables before opening the app.
  await AppEnv.load();

  // Apply portrait orientation on phones.
  await _applyOrientationLock();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.appBar,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const VideoEditorApp());
}

/// Lock phones to portrait orientation.
/// Tablets and other larger screens can rotate freely.
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
        scrollBehavior: const AppScrollBehavior(),

        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            systemNavigationBarColor: AppColors.background,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.85,
            maxScaleFactor: 1.3,
            child: child ?? const SizedBox.shrink(),
          ),
        ),

        // The mandatory update check runs when HomeScreen opens.
        home: const SplashScreen(),
      ),
    );
  }
}
