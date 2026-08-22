import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/filter_preset.dart';
import 'package:video_editor/data/models/layers.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/state/editor_controller.dart';
import 'package:video_editor/state/projects_controller.dart';
import 'package:video_editor/ui/editor/editor_screen.dart';
import 'package:video_editor/ui/editor/panels/color_panels.dart';
import 'package:video_editor/ui/editor/panels/effects_panel.dart';
import 'package:video_editor/ui/editor/panels/filter_panel.dart';
import 'package:video_editor/ui/editor/preview/clip_view.dart';
import 'package:video_editor/ui/editor/timeline/clip_strip.dart';
import 'package:video_editor/ui/widgets/panel_shell.dart';

import 'helpers/editor_tools.dart';

VideoClip _clip() => VideoClip(
      path: '/nonexistent/clip.jpg',
      isImage: true,
      sourceDuration: const Duration(seconds: 4),
    );

OverlayLayer _overlay() => OverlayLayer(
      start: Duration.zero,
      duration: const Duration(seconds: 2),
      path: '/nonexistent/pip.jpg',
      isImage: true,
      sourceDuration: const Duration(seconds: 4),
    );

/// The test window is 800x600 by default — shorter than any phone, and short
/// enough that a sheet has to leave a row of its controls behind the panel's
/// "More options" button. A test that reaches for a preset by name wants the
/// window a user actually has.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Widget _host(Widget child) => ChangeNotifierProvider(
      create: (_) => ProjectsController(),
      child: MaterialApp(theme: AppTheme.light, home: child),
    );

void main() {
  group('the filter library', () {
    test('has no duplicate ids', () {
      final ids = FilterLibrary.all.map((f) => f.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('has no duplicate names', () {
      // The strip labels a tile by name and nothing else, so two looks with
      // one name are two tiles the user cannot tell apart.
      final names = FilterLibrary.all.map((f) => f.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('names fit the tile they are labelled on', () {
      // The strip's tiles are 58pt wide and the label sits under one on a
      // single line; past eight characters it ellipsises into a guess.
      for (final f in FilterLibrary.all) {
        expect(f.name.length, lessThanOrEqualTo(8),
            reason: '${f.id} is labelled "${f.name}", too long for a tile');
      }
    });

    test('fills every pack it offers', () {
      // An empty tab is a tab that opens onto the original and nothing else.
      for (final c in FilterLibrary.categories.where((c) => c != 'None')) {
        expect(FilterLibrary.byCategory(c), isNotEmpty,
            reason: 'the $c pack has no looks in it');
      }
    });

    test('groups every preset under an offered category', () {
      for (final f in FilterLibrary.all) {
        expect(FilterLibrary.categories, contains(f.category),
            reason: '${f.id} is filed under an unlisted category');
      }
    });

    test('leaves the frame untouched at zero intensity', () {
      for (final f in FilterLibrary.all) {
        expect(f.lerpFromIdentity(0).isIdentity, isTrue,
            reason: '${f.id} still grades at 0% intensity');
      }
    });

    test('renders an FFmpeg fragment for every look but None', () {
      expect(FilterLibrary.none.toFFmpegFilter(), isEmpty);
      for (final f in FilterLibrary.all.where((f) => f.id != 'none')) {
        final chain = f.toFFmpegFilter();
        expect(chain, isNotEmpty, reason: '${f.id} exports as a no-op');
        // A stray empty link would make FFmpeg reject the whole graph.
        expect(chain.split(',').any((p) => p.trim().isEmpty), isFalse,
            reason: '${f.id} builds a malformed chain: $chain');
      }
    });
  });

  group('reaching the filters', () {
    testWidgets('the project toolbar opens them with nothing selected',
        (tester) async {
      final project = Project(name: 'Filters', clips: [_clip()]);
      await tester.pumpWidget(_host(EditorScreen(project: project)));
      await tester.pump(const Duration(milliseconds: 300));

      await tapEditorTool(tester, 'Effect');
      await tester.pump(const Duration(milliseconds: 300));

      // Not the 'Select a clip' placeholder: the clip under the playhead is
      // picked up on the user's behalf.
      expect(find.byType(EffectsPanel), findsOneWidget);
      expect(find.text('Nothing selected'), findsNothing);
    });

    testWidgets('applying a look grades the clip under the playhead',
        (tester) async {
      _phone(tester);
      final project = Project(name: 'Filters', clips: [_clip()]);
      await tester.pumpWidget(_host(EditorScreen(project: project)));
      await tester.pump(const Duration(milliseconds: 300));

      await tapEditorTool(tester, 'Effect');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Kodak'), warnIfMissed: false);
      await tester.pump(const Duration(seconds: 1));

      expect(project.clips.first.filterId, 'kodak');
      expect(project.clips.first.filterIntensity, 1);
    });

    testWidgets('an empty project says so instead of opening an empty panel',
        (tester) async {
      await tester.pumpWidget(_host(EditorScreen(project: Project(name: 'Empty'))));
      await tester.pump(const Duration(milliseconds: 300));

      await tapEditorTool(tester, 'Effect');
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(EffectsPanel), findsNothing);
      expect(find.text('Add a video or photo first'), findsOneWidget);
    });
  });

  group('the one-tap filter strip', () {
    Future<Project> open(WidgetTester tester, {int clips = 1}) async {
      final project = Project(
        name: 'Filters',
        clips: [for (var i = 0; i < clips; i++) _clip()],
      );
      await tester.pumpWidget(_host(EditorScreen(project: project)));
      await tester.pump(const Duration(milliseconds: 300));
      await tapEditorTool(tester, 'Filter');
      await tester.pump(const Duration(milliseconds: 300));
      return project;
    }

    testWidgets('one tap on the toolbar lands straight on the looks',
        (tester) async {
      await open(tester);

      expect(find.byType(FilterPanel), findsOneWidget);
      // No tab row to walk past, and the original is the head of the strip.
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Kodak'), findsOneWidget);
    });

    testWidgets('tapping a look applies it at full strength', (tester) async {
      final project = await open(tester);

      await tester.tap(find.text('Kodak'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(project.clips.first.filterId, 'kodak');
      expect(project.clips.first.filterIntensity, 1);
    });

    testWidgets('the strength slider is out the moment a look is on',
        (tester) async {
      await open(tester);

      // Nothing to fade yet, so the row carries the prompt instead.
      expect(find.text('Strength'), findsNothing);
      expect(find.text('Tap a look to apply it'), findsOneWidget);

      await tester.tap(find.text('Kodak'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      // One tap, and both the look and the way to dial it back are there —
      // no second tap on the tile to uncover the slider.
      expect(find.text('Strength'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      // Tapping the live tile again is a no-op rather than a toggle.
      await tester.tap(find.text('Kodak'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Strength'), findsOneWidget);
    });

    testWidgets('opens on the look the clip is already wearing',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      // A look from the far end of the library: at the head of the strip it
      // would be a hundred tiles off the right edge, and the tool would open
      // looking like nothing had been applied.
      final clip = _clip()..filterId = 'weddingPearl';
      final project = Project(name: 'Graded', clips: [clip]);
      await tester.pumpWidget(_host(EditorScreen(project: project)));
      await tester.pump(const Duration(milliseconds: 300));
      await tapEditorTool(tester, 'Filter');
      await tester.pump(const Duration(milliseconds: 300));
      // The strip is put on the applied look once it has a viewport to
      // measure, so the tiles it lands on are built on the frame after.
      await tester.pump();

      expect(find.text('Pearl'), findsOneWidget);
      final panel = tester.getRect(find.byType(FilterPanel));
      final tile = tester.getRect(find.text('Pearl'));
      expect(tile.left, greaterThanOrEqualTo(panel.left),
          reason: 'the applied look is off the left of the strip');
      expect(tile.right, lessThanOrEqualTo(panel.right),
          reason: 'the applied look is off the right of the strip');
    });

    testWidgets('the pill swaps the looks for the sliders', (tester) async {
      await open(tester);
      expect(find.byType(FilterPanel), findsOneWidget);

      // The pill carries the two colour tools the sheet switches between —
      // textures are their own button on the bar, not a third tab here.
      // 'Adjust' is the half; the sliders it opens are what proves the swap.
      await tester.tap(find.text('Adjust').last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AdjustPanel), findsOneWidget);
      expect(find.byType(FilterPanel), findsNothing);

      // And back, without the sheet ever closing.
      await tester.tap(find.text('Filter').last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FilterPanel), findsOneWidget);
    });

    testWidgets('the original never offers a strength to fade', (tester) async {
      final project = await open(tester);

      // 'Original' is already the active look on a fresh clip, so this is the
      // second-tap gesture — and there is nothing to fade an ungraded clip to.
      await tester.tap(find.text('Original'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Strength'), findsNothing);
      expect(project.clips.first.filterId, 'none');
    });

    testWidgets('a category still keeps the original within reach',
        (tester) async {
      await open(tester);

      await tester.tap(find.text('Mood'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Noir'), findsOneWidget);
      // Film is a different group, so its looks are out of the row now.
      expect(find.text('Kodak'), findsNothing);
    });

    // The sheet scrolls whatever it cannot show, so an overflow check passes
    // on a panel whose last row is below the fold. This is the row the user
    // came for; it has to be on screen without a drag.
    testWidgets('every row is on screen without scrolling the sheet',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await open(tester);

      // Whatever hangs below the fold is exactly the sheet's scroll extent,
      // and a rect check misses a row clipped by a few points.
      void expectNothingBelowTheFold(String state) {
        final position = tester
            .state<ScrollableState>(find.descendant(
              of: find.byType(PanelShell),
              matching: find.byType(Scrollable),
            ).first)
            .position;
        expect(
          position.maxScrollExtent,
          0,
          reason: 'with $state the panel is '
              '${position.maxScrollExtent}pt taller than the sheet opens, so '
              'that much of it is off the bottom until the user drags',
        );
      }

      expect(find.text('Tap a look to apply it'), findsOneWidget);
      expectNothingBelowTheFold('no look applied');

      // And again with a look on, where the strength slider takes the row
      // the prompt was holding open for it.
      await tester.tap(find.text('Kodak'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Strength'), findsOneWidget);
      expectNothingBelowTheFold('a look applied');
    });

    testWidgets('apply to all spreads the look over every clip',
        (tester) async {
      final project = await open(tester, clips: 3);

      await tester.tap(find.text('Kodak'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('All clips'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(project.clips.map((c) => c.filterId), everyElement('kodak'));
    });

    testWidgets('the strip writes to a selected overlay, not a clip',
        (tester) async {
      final overlay = _overlay();
      final clip = _clip();
      final editor = EditorController(
        Project(name: 'PiP', clips: [clip], overlays: [overlay]),
      );
      addTearDown(editor.dispose);
      editor.select(LaneKind.overlay, overlay.id);

      await tester.pumpWidget(_host(Scaffold(
        body: FilterPanel(editor: editor, overlay: overlay, onClose: () {}),
      )));
      await tester.pump();

      await tester.tap(find.text('Portra'), warnIfMissed: false);
      // Past the controller's save debounce, so no timer outlives the test.
      await tester.pump(const Duration(seconds: 1));

      expect(overlay.filterId, 'portra');
      expect(clip.filterId, 'none');
    });
  });

  group('the grade lands where the user can see it', () {
    // The panel writes to the *selected* clip while the canvas only draws the
    // clip under the *playhead*. When those two are different clips, every
    // preset looks dead — the grade lands on a frame that is nowhere on
    // screen. Both halves of that are checked here: opening the tool, and
    // switching clips while it is already open.
    VideoClip short(String path) => VideoClip(
          path: path,
          isImage: true,
          sourceDuration: const Duration(seconds: 1),
        );

    /// The x of a point inside the clip at [fraction] along the whole track.
    Offset pointOnTrack(WidgetTester tester, double fraction) {
      final track = tester.getRect(find.byType(ClipStrip).first);
      return Offset(track.left + track.width * fraction, track.center.dy);
    }

    Future<void> openEffects(WidgetTester tester) async {
      await tapEditorTool(tester, 'Effect');
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// The clip the canvas is currently drawing.
    VideoClip previewed(WidgetTester tester) =>
        (find.byType(ClipView).evaluate().first.widget as ClipView).clip;

    testWidgets('opening the tool brings the playhead to the selected clip',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final project = Project(
        name: 'Three',
        clips: [short('/nonexistent/a.jpg'), short('/nonexistent/b.jpg'),
            short('/nonexistent/c.jpg')],
      );
      await tester.pumpWidget(_host(EditorScreen(project: project)));
      await tester.pump(const Duration(milliseconds: 300));

      // Select the middle clip. The playhead stays at 0, on the first one.
      await tester.tapAt(pointOnTrack(tester, 0.42));
      await tester.pump(const Duration(milliseconds: 300));

      await openEffects(tester);
      await tester.tap(find.text('Kodak'), warnIfMissed: false);
      await tester.pump(const Duration(seconds: 1));

      expect(project.clips[1].filterId, 'kodak');
      expect(previewed(tester).path, '/nonexistent/b.jpg',
          reason: 'the canvas is showing a clip other than the graded one, so '
              'the filter looks like it did nothing');
      expect(find.byType(GradedBox), findsWidgets);
    });

    testWidgets('switching clips with the tool open follows along',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final project = Project(
        name: 'Three',
        clips: [short('/nonexistent/a.jpg'), short('/nonexistent/b.jpg'),
            short('/nonexistent/c.jpg')],
      );
      await tester.pumpWidget(_host(EditorScreen(project: project)));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tapAt(pointOnTrack(tester, 0.42));
      await tester.pump(const Duration(milliseconds: 300));
      await openEffects(tester);

      // Now pick the first clip without closing the panel.
      await tester.tapAt(pointOnTrack(tester, 0.08));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Portra'), warnIfMissed: false);
      await tester.pump(const Duration(seconds: 1));

      expect(project.clips[0].filterId, 'portra');
      expect(previewed(tester).path, '/nonexistent/a.jpg');
    });
  });

  group('grading an overlay', () {
    testWidgets('the filter panel writes to the overlay, not a clip',
        (tester) async {
      final overlay = _overlay();
      final clip = _clip();
      final editor = EditorController(
        Project(name: 'PiP', clips: [clip], overlays: [overlay]),
      );
      addTearDown(editor.dispose);
      editor.select(LaneKind.overlay, overlay.id);

      await tester.pumpWidget(_host(Scaffold(
        body: EffectsPanel(editor: editor, overlay: overlay, onClose: () {}),
      )));
      await tester.pump();

      await tester.tap(find.text('Portra'), warnIfMissed: false);
      // Past the controller's save debounce, so no timer outlives the test.
      await tester.pump(const Duration(seconds: 1));

      expect(overlay.filterId, 'portra');
      expect(clip.filterId, 'none');
    });

    testWidgets('the adjust panel writes to the overlay, not a clip',
        (tester) async {
      final overlay = _overlay();
      final clip = _clip();
      final editor = EditorController(
        Project(name: 'PiP', clips: [clip], overlays: [overlay]),
      );
      addTearDown(editor.dispose);

      await tester.pumpWidget(_host(Scaffold(
        body: AdjustPanel(editor: editor, overlay: overlay, onClose: () {}),
      )));
      await tester.pump();

      // Drive the slider the panel built rather than the model directly.
      await tester.drag(find.byType(Slider).first, const Offset(60, 0));
      await tester.pump(const Duration(seconds: 1));

      expect(overlay.adjustments.brightness, isNot(0));
      expect(clip.adjustments.brightness, 0);
    });
  });

  group('grading what the preview is showing', () {
    // The panels edit the selected clip, the canvas draws the clip under the
    // playhead. Let those drift apart and every slider looks broken: the
    // grade lands on footage that is nowhere on screen.
    testWidgets('pulls the playhead onto the clip the sliders are grading',
        (tester) async {
      final project =
          Project(name: 'Grade', clips: [_clip(), _clip(), _clip()]);
      await tester.pumpWidget(_host(EditorScreen(project: project)));
      await tester.pump(const Duration(milliseconds: 300));

      final editor = Provider.of<EditorController>(
          tester.element(find.byType(ClipView).first),
          listen: false);
      editor.selectClip(0);
      editor.seek(const Duration(seconds: 9)); // parked on the third clip
      await tester.pump(const Duration(milliseconds: 300));
      expect(project.clipIndexAt(editor.position.value), 2);

      await tapEditorTool(tester, 'Adjust');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.drag(find.byType(Slider).first, const Offset(-200, 0));
      await tester.pump(const Duration(seconds: 1));

      expect(project.clips.first.adjustments.brightness, isNot(0));
      expect(project.clipIndexAt(editor.position.value), 0,
          reason: 'the playhead should follow the graded clip');
      expect(find.byType(GradedBox), findsWidgets,
          reason: 'the grade should be visible in the preview');
    });

    testWidgets('does the same before a look is picked', (tester) async {
      _phone(tester);
      final project =
          Project(name: 'Filters', clips: [_clip(), _clip(), _clip()]);
      await tester.pumpWidget(_host(EditorScreen(project: project)));
      await tester.pump(const Duration(milliseconds: 300));

      final editor = Provider.of<EditorController>(
          tester.element(find.byType(ClipView).first),
          listen: false);
      editor.selectClip(0);
      editor.seek(const Duration(seconds: 9));
      await tester.pump(const Duration(milliseconds: 300));

      await tapEditorTool(tester, 'Effect');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Kodak'), warnIfMissed: false);
      await tester.pump(const Duration(seconds: 1));

      expect(project.clips.first.filterId, 'kodak');
      expect(project.clipIndexAt(editor.position.value), 0);
      expect(find.byType(GradedBox), findsWidgets);
    });

    testWidgets('pulls the playhead into a selected overlay\'s span',
        (tester) async {
      final overlay = _overlay()..start = const Duration(seconds: 6);
      final project = Project(
        name: 'PiP',
        clips: [_clip(), _clip(), _clip()],
        overlays: [overlay],
      );
      await tester.pumpWidget(_host(EditorScreen(project: project)));
      await tester.pump(const Duration(milliseconds: 300));

      final editor = Provider.of<EditorController>(
          tester.element(find.byType(ClipView).first),
          listen: false);
      editor.select(LaneKind.overlay, overlay.id);
      editor.seek(Duration.zero);
      await tester.pump(const Duration(milliseconds: 300));
      expect(overlay.isVisibleAt(editor.position.value), isFalse);

      // The overlay's colour tool is labelled 'Color' — plain 'Adjust' is
      // taken by its transform tool.
      final colour = find.text('Color');
      await tester.scrollUntilVisible(colour, 120,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(colour, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(overlay.isVisibleAt(editor.position.value), isTrue,
          reason: 'the overlay being graded should be on screen');
    });
  });
}
