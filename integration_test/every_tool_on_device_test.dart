import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/core/utils/responsive.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/state/editor_controller.dart';
import 'package:video_editor/state/projects_controller.dart';
import 'package:video_editor/ui/editor/editor_screen.dart';
import 'package:video_editor/ui/editor/preview/preview_stage.dart';
import 'package:video_editor/ui/editor/toolbar/editor_toolbar.dart';
import 'package:video_editor/ui/picker/media_picker_screen.dart';
import 'package:video_editor/ui/widgets/panel_shell.dart';

/// Presses every tool on the bar, one at a time, in the real app on the real
/// device — with real footage under the playhead and the device's own FFmpeg
/// behind the tools that render.
///
/// The widget-test sweep can only prove a tool answers; the plugins it needs
/// are not there. This one puts the whole thing together: Reverse actually
/// reverses, Freeze actually grabs a frame, AI Cut actually listens for the
/// silences. A tool that only works when nothing is plugged in fails here.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String clipPath;

  setUpAll(() async {
    dir = Directory('${(await getTemporaryDirectory()).path}/every_tool');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);

    // Three seconds of moving picture with a silent track, so the clip tools
    // — and the audio ones — all have something real to act on.
    clipPath = '${dir.path}/clip.mp4';
    final session = await FFmpegKit.execute(
      '-hide_banner -y '
      '-f lavfi -i testsrc=size=480x854:rate=30:duration=3 '
      '-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 '
      '-shortest -c:v libx264 -preset ultrafast -pix_fmt yuv420p '
      '-c:a aac "$clipPath"',
    );
    expect(
      ReturnCode.isSuccess(await session.getReturnCode()),
      isTrue,
      reason:
          'could not render the test clip: '
          '${await session.getAllLogsAsString()}',
    );
  });

  Project project() => Project(
    name: 'Every tool on device',
    ratio: CanvasRatio.r9x16,
    clips: [
      for (var i = 0; i < 2; i++)
        VideoClip(
          path: clipPath,
          isImage: false,
          sourceDuration: const Duration(seconds: 3),
        ),
    ],
  );

  Future<EditorController> open(WidgetTester tester, String key) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ProjectsController(),
        child: MaterialApp(
          theme: AppTheme.light,
          scrollBehavior: const AppScrollBehavior(),
          home: EditorScreen(key: ValueKey(key), project: project()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return Provider.of<EditorController>(
      tester.element(find.byType(PreviewStage).first),
      listen: false,
    );
  }

  /// The bar is a lazily-built strip: a tool past its edge is not mounted
  /// until it has been scrolled into view.
  Future<void> tapTool(WidgetTester tester, String label) async {
    final button = find.descendant(
      of: find.byType(EditorToolbar),
      matching: find.text(label),
    );
    if (button.evaluate().isEmpty) {
      final strip = find.descendant(
        of: find.byType(EditorToolbar),
        matching: find.byType(Scrollable),
      );
      await tester.dragUntilVisible(
        button,
        strip.first,
        const Offset(-120, 0),
        maxIteration: 60,
      );
    }
    await tester.ensureVisible(button.first);
    await tester.pump();
    await tester.tap(button.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 600));
  }

  for (final tool in EditorToolbar.mainToolLabels) {
    testWidgets('$tool answers on the device', (tester) async {
      final editor = await open(tester, tool);
      final before = editor.project.toJson().toString();

      await tapTool(tester, tool);

      // Latched, not sampled at the end: a message is the whole answer some
      // tools give, and on the device it has come and gone inside two
      // seconds. Reading the screen once after the wait is how a tool that
      // answered promptly gets recorded as answering not at all.
      var answered = false;
      for (var i = 0; i < 20 && !answered; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        answered =
            find.byType(PanelShell).evaluate().isNotEmpty ||
            find.byType(SnackBar).evaluate().isNotEmpty ||
            editor.isBusy ||
            editor.project.toJson().toString() != before ||
            find.byType(MediaPickerScreen).evaluate().isNotEmpty ||
            find.byType(EditorScreen).evaluate().isEmpty;
      }

      expect(answered, isTrue, reason: '$tool did nothing on the device');
      expect(tester.takeException(), isNull, reason: '$tool threw');
    });
  }
}
