import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

import 'helpers/editor_tools.dart';

/// Every tool the bottom bar offers has to answer a tap — with its panel, a
/// change to the project, or a word about why it cannot. A button that does
/// nothing at all reads as a broken app, and that is what "the tools don't
/// work" means from the outside.
///
/// The list is taken from the bar itself rather than written out again here,
/// so a tool added to the strip is a tool this file starts covering on its
/// own. [_expected] is the guard against that going the other way: it fails
/// if the bar's own order changes, which is what would otherwise let a tool
/// be dropped without anything noticing.
void main() {
  const phone = Size(390, 844);

  /// The bar, in order: the seven project tools, the clip tools a phone
  /// editor puts after them, and this editor's own extras behind the second
  /// hairline.
  const expected = <String>[
    // project
    'Canvas', 'Audio', 'Sticker', 'Text', 'Effect', 'Filter', 'PIP',
    // clip
    'Duration', 'Split', 'Delete', 'Volume', 'Speed', 'Animation', 'AI Cut',
    'Voice Enhance', 'Crop', 'Switch', 'Enhance', 'Cutout', 'Stabilizer',
    'Mask', 'Opacity', 'Replace', 'Voice Effect', 'Duplicate', 'Rotate',
    'Freeze', 'Reverse', 'Ease',
    // this editor's extras
    'Adjust', 'Chroma', 'Keyframe', 'Transition', 'Mirror', 'Backdrop',
    'Watermark', 'Captions', 'TTS', 'Voice', 'Extract', 'Mix',
  ];

  /// A project the clip tools have something real to act on: two clips, so
  /// Switch and Transition are live, and each long enough to split.
  ///
  /// The sweep runs twice over this — once on photos, once on footage —
  /// because half the bar takes a different path on each. Freeze, Reverse,
  /// AI Cut, Cutout and Extract all have a 'not for a photo' answer and a
  /// real one, and only the second sweep ever reaches the real one.
  Project project({required bool isImage}) => Project(
    name: 'Every tool',
    ratio: CanvasRatio.r9x16,
    clips: [
      for (var i = 0; i < 2; i++)
        VideoClip(
          path: isImage ? '/nonexistent/c$i.jpg' : '/nonexistent/c$i.mp4',
          isImage: isImage,
          hasAudio: !isImage,
          sourceDuration: const Duration(seconds: 4),
        ),
    ],
  );

  Future<EditorController> open(
    WidgetTester tester,
    String key, {
    required bool isImage,
  }) async {
    tester.view.physicalSize = phone * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ProjectsController(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          scrollBehavior: const AppScrollBehavior(),
          home: EditorScreen(
            key: ValueKey(key),
            project: project(isImage: isImage),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return Provider.of<EditorController>(
      tester.element(find.byType(PreviewStage).first),
      listen: false,
    );
  }

  test('the bar carries every tool, in order, and nothing else', () {
    expect(
      EditorToolbar.mainToolLabels,
      expected,
      reason: 'the strip and this file disagree about what the bar holds',
    );
  });

  for (final onPhotos in const [true, false]) {
    final kind = onPhotos ? 'photo' : 'video';
    for (final tool in EditorToolbar.mainToolLabels) {
      testWidgets('$tool answers a tap on a $kind', (tester) async {
        final editor = await open(tester, '$kind/$tool', isImage: onPhotos);
        final before = editor.project.toJson().toString();

        await tapEditorTool(tester, tool);
        await tester.pump(const Duration(milliseconds: 400));

        final panel = find.byType(PanelShell).evaluate().isNotEmpty;
        final toast = find.byType(SnackBar).evaluate().isNotEmpty;
        final changed = editor.project.toJson().toString() != before;
        // A tool that has to render before it can show anything — Reverse,
        // Freeze, AI Cut, Extract — answers by putting its name in the busy
        // bar. That is the response the user sees, and it is proof the tool
        // started the work rather than swallowing the tap.
        final busy = editor.isBusy;
        // A tool that leaves the screen — the pickers — counts as answered
        // by the route it pushed.
        final left =
            find.byType(MediaPickerScreen).evaluate().isNotEmpty ||
            find.byType(EditorScreen).evaluate().isEmpty;

        expect(
          panel || toast || changed || left || busy,
          isTrue,
          reason: '$tool did nothing: no panel, no message, no change',
        );
        expect(tester.takeException(), isNull, reason: '$tool threw');
      });
    }
  }
}
