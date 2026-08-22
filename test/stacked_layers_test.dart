import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/core/utils/constants.dart';
import 'package:video_editor/core/utils/responsive.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/state/editor_controller.dart';
import 'package:video_editor/state/projects_controller.dart';
import 'package:video_editor/ui/editor/editor_screen.dart';
import 'package:video_editor/ui/editor/timeline/lane_row.dart';
import 'package:video_editor/ui/editor/timeline/timeline_view.dart';
import 'helpers/editor_tools.dart';

/// Two overlays added at the same playhead are the ordinary way a second
/// caption gets on a frame, and both ends of the editor used to get it
/// wrong: the canvas drew them glyph over glyph, and the timeline measured
/// their lane as one row while drawing two — a 28pt overflow stripe across
/// the track.
void main() {
  Project project() => Project(
        name: 'Stacked',
        ratio: CanvasRatio.r9x16,
        clips: [
          VideoClip(
            path: '/nonexistent/c.jpg',
            isImage: true,
            sourceDuration: const Duration(seconds: 4),
          ),
        ],
      );

  group('a second overlay on the same frame', () {
    test('is not dropped on top of the first', () {
      final editor = EditorController(project());
      addTearDown(editor.dispose);

      final first = editor.addText();
      final second = editor.addText();
      final third = editor.addText();

      expect(first.transform.y, 0.5);
      for (final pair in [
        [first, second],
        [first, third],
        [second, third],
      ]) {
        expect((pair[0].transform.y - pair[1].transform.y).abs(),
            greaterThan(0.02),
            reason: 'two texts share a spot, so they draw as one smear');
      }
      // Still on the frame, not pushed off the top or the bottom of it.
      for (final layer in [second, third]) {
        expect(layer.transform.y, inInclusiveRange(0.05, 0.95));
      }
    });

    test('stickers stack the same way', () {
      final editor = EditorController(project());
      addTearDown(editor.dispose);

      final first = editor.addSticker('star');
      final second = editor.addSticker('heart');

      expect(first.transform.y, isNot(second.transform.y));
    });

    test('a spot that has come free is used again', () {
      final editor = EditorController(project());
      addTearDown(editor.dispose);

      // Far enough along that the first text has ended: nothing is on the
      // frame there, so the newcomer belongs in the middle of it.
      editor.addText();
      editor.seek(const Duration(seconds: 3, milliseconds: 500));
      expect(editor.addText().transform.y, 0.5);
    });
  });

  group('the lane that holds them', () {
    test('is measured as tall as it is drawn', () {
      final editor = EditorController(project());
      addTearDown(editor.dispose);
      final flat = TimelineView.heightFor(editor);

      editor.addText();
      final oneRow = TimelineView.heightFor(editor);
      expect(oneRow - flat, kLaneGap + kLaneHeight);

      // The second text overlaps the first, so the lane splits in two.
      editor.addText();
      final twoRows = TimelineView.heightFor(editor);
      expect(twoRows - oneRow, kLaneHeight + LaneRow.kSubRowGap,
          reason: 'the box is short by exactly the sub-row it does not know '
              'the lane is drawing');
    });

    testWidgets('draws without an overflow stripe', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ProjectsController(),
          child: MaterialApp(
            theme: AppTheme.light,
            scrollBehavior: const AppScrollBehavior(),
            home: EditorScreen(project: project()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tapEditorTool(tester, 'Text');
      await tester.pump(const Duration(milliseconds: 400));
      final editor = Provider.of<EditorController>(
        tester.element(find.byType(TimelineView)),
        listen: false,
      );

      // A second text and a second sticker on the same frame: each pair
      // shares a lane and a moment, so each lane is drawn two rows deep.
      editor.addText();
      editor.addSticker('star');
      editor.addSticker('heart');
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull,
          reason: 'a lane drawn two rows deep overflowed the timeline');
      expect(
        tester.getSize(find.byType(TimelineView)).height,
        TimelineView.heightFor(editor),
      );
    });
  });
}
