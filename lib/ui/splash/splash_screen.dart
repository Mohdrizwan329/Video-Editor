import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../state/projects_controller.dart';
import '../editor/preview/chroma_box.dart';
import '../home/home_screen.dart';
import '../widgets/app_logo.dart';

/// First screen of the app. It paints the same flat fill as the native launch
/// window — the app-bar colour — so a cold start reads as one continuous
/// screen rather than a flash of white followed by the UI.
///
/// It also owns the startup work that used to block `main()` — compiling the
/// chroma shader and the first project load — so that time is spent behind the
/// brand mark instead of behind a blank window.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// The mark stays up at least this long even on a warm start, so the app
  /// never flickers through the splash too fast to read.
  static const Duration minimumOnScreen = Duration(milliseconds: 1400);

  /// Startup work is a courtesy, not a gate: if the shader or the repository
  /// hangs, the app still opens.
  static const Duration bootTimeout = Duration(seconds: 5);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..forward();

  late final Animation<double> _markIn = CurvedAnimation(
    parent: _anim,
    curve: const Interval(0, 0.7, curve: Curves.easeOutBack),
  );

  late final Animation<double> _textIn = CurvedAnimation(
    parent: _anim,
    curve: const Interval(0.35, 1, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final projects = context.read<ProjectsController>();
    await Future.wait([
      Future.wait([
        ChromaBox.warmUp(),
        _projectsLoaded(projects),
      ]).timeout(SplashScreen.bootTimeout, onTimeout: () => const []),
      Future<void>.delayed(SplashScreen.minimumOnScreen),
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(_fadeToHome());
  }

  /// Completes once the library has finished its first load, so the home
  /// screen opens with its list already populated instead of a spinner.
  Future<void> _projectsLoaded(ProjectsController projects) {
    if (!projects.loading) return Future.value();
    final done = Completer<void>();
    void listener() {
      if (!projects.loading && !done.isCompleted) {
        projects.removeListener(listener);
        done.complete();
      }
    }

    projects.addListener(listener);
    return done.future;
  }

  Route<void> _fadeToHome() => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 450),
    pageBuilder: (_, _, _) => const HomeScreen(),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The splash is filled with the app-bar colour, so the system icons on
      // top of it are light — the same pair the home app bar asks for.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.appBar,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.appBar,
        body: Builder(
          builder: (context) {
            final r = context.r;
            // The mark is sized from the window's short edge rather than a
            // fixed 84, so it reads the same on a 320pt phone, a tablet and a
            // maximised desktop window.
            final mark = (r.shortestSide * 0.22).clamp(64.0, 132.0);
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: r.gutter,
                  vertical: r.vp(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: Tween(begin: 0.72, end: 1.0).animate(_markIn),
                      child: FadeTransition(
                        opacity: _markIn,
                        child: AppLogo(size: mark, glow: true),
                      ),
                    ),
                    SizedBox(height: r.vp(22)),
                    FadeTransition(
                      opacity: _textIn,
                      child: Column(
                        children: [
                          Text(
                            'Video Editor',
                            style: TextStyle(
                              fontSize: r.sp(22),
                              fontWeight: FontWeight.w800,
                              color: AppColors.onAppBar,
                            ),
                          ),
                          SizedBox(height: r.vp(5)),
                          Text(
                            'Cut · Colour · Caption · Export',
                            style: TextStyle(
                              fontSize: r.sp(11),
                              color: AppColors.onAppBarDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: r.vp(34)),
                    FadeTransition(
                      opacity: _textIn,
                      child: SizedBox(
                        width: r.dp(88),
                        child: const LinearProgressIndicator(
                          minHeight: 2.5,
                          backgroundColor: AppColors.onAppBarDim,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
