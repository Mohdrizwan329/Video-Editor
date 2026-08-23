import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/core/utils/responsive.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/layers.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/state/projects_controller.dart';
import 'package:video_editor/ui/editor/editor_screen.dart';
import 'package:video_editor/ui/editor/timeline/clip_strip.dart';
import 'package:video_editor/ui/editor/timeline/lane_row.dart';
import 'package:video_editor/ui/editor/timeline/timeline_view.dart';

/// The timeline used to reserve a fixed 118pt plus 30 per lane while its rows
/// added up to less, which left a band of dead grey between the track and the
/// bar underneath. Its box is now measured from the rows it actually draws.
void main() {
  const phone = Size(390, 844);

  Future<void> pumpEditor(WidgetTester tester, Project project) async {
    tester.view.physicalSize = phone * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ProjectsController(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          scrollBehavior: const AppScrollBehavior(),
          // A fresh key per project: the editor holds its controller in
          // State, so without one the second pump keeps the first project.
          home: EditorScreen(key: ValueKey(project.name), project: project),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Project projectWith({bool layers = false}) {
    final p = Project(
      name: layers ? 'Timeline with lanes' : 'Timeline',
      ratio: CanvasRatio.r9x16,
      clips: [
        VideoClip(
          path: '/nonexistent/a.jpg',
          isImage: true,
          sourceDuration: const Duration(seconds: 4),
        ),
      ],
    );
    if (layers) {
      p.texts.add(
        TextLayer(
          start: Duration.zero,
          duration: const Duration(seconds: 3),
          text: 'Hi',
        ),
      );
      p.stickers.add(
        StickerLayer(
          start: Duration.zero,
          duration: const Duration(seconds: 3),
          content: '\u{1F600}',
        ),
      );
    }
    return p;
  }

  /// What the timeline reserves under its last row. A few points of air is
  /// fine; a band the height of a lane is the bug.
  double tailUnder(WidgetTester tester, Finder last) {
    final box = tester.getRect(find.byType(TimelineView));
    return box.bottom - tester.getRect(last).bottom;
  }

  testWidgets('a bare track leaves no room for lanes it is not drawing', (
    tester,
  ) async {
    await pumpEditor(tester, projectWith());

    final tail = tailUnder(tester, find.byType(ClipStrip).first);
    expect(
      tail,
      lessThanOrEqualTo(10),
      reason: 'dead space under the track: ${tail}pt',
    );
  });

  testWidgets('the lanes it does draw still fit', (tester) async {
    await pumpEditor(tester, projectWith(layers: true));

    final lanes = find.byType(LaneRow);
    expect(lanes, findsWidgets);
    // The last lane drawn, whichever it is.
    var lowest = 0.0;
    for (final e in lanes.evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      if (r.height > 0 && r.bottom > lowest) lowest = r.bottom;
    }
    final box = tester.getRect(find.byType(TimelineView));
    expect(
      lowest,
      lessThanOrEqualTo(box.bottom),
      reason: 'a lane hangs past the bottom of the timeline',
    );
    expect(
      box.bottom - lowest,
      lessThanOrEqualTo(10),
      reason: 'dead space under the lanes: ${box.bottom - lowest}pt',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the preview keeps what the timeline gave back', (tester) async {
    await pumpEditor(tester, projectWith());
    final bare = tester.getRect(find.byType(TimelineView)).height;

    await pumpEditor(tester, projectWith(layers: true));
    final withLanes = tester.getRect(find.byType(TimelineView)).height;

    expect(bare, lessThan(withLanes));
    expect(bare, lessThan(100), reason: 'a bare track is ${bare}pt tall');
  });
}
