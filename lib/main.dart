import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'state/projects_controller.dart';
import 'ui/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
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

class VideoEditorApp extends StatelessWidget {
  const VideoEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProjectsController(),
      child: MaterialApp(
        title: 'Saleem Video Editor',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        themeMode: ThemeMode.light,
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
          child: child ?? const SizedBox.shrink(),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
