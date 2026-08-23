import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/layers.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/state/editor_controller.dart';
import 'package:video_editor/state/projects_controller.dart';
import 'package:video_editor/ui/editor/editor_screen.dart';
import 'package:video_editor/ui/editor/panels/effect_panels.dart';
import 'package:video_editor/ui/editor/preview/clip_view.dart';
import 'package:video_editor/ui/editor/toolbar/editor_toolbar.dart';

VideoClip _clip() => VideoClip(
  path: '/nonexistent/c.jpg',
  isImage: true,
  sourceDuration: const Duration(seconds: 4),
);

Widget _host(Widget child) => ChangeNotifierProvider(
  create: (_) => ProjectsController(),
  child: MaterialApp(theme: AppTheme.light, home: child),
);

EditorController _editorOf(WidgetTester t) => Provider.of<EditorController>(
  t.element(find.byType(ClipView).first),
  listen: false,
);

/// Taps a bottom-bar tool by label. `scrollUntilVisible` alone can stop with
/// the button's centre still outside the strip, which turns `tap` into a
/// silent no-op — `ensureVisible` finishes the job.
Future<void> _tapTool(WidgetTester t, String label) async {
  final button = find.descendant(
    of: find.byType(EditorToolbar),
    matching: find.text(label),
  );
  // A set of six or fewer is spread across the strip rather than scrolled,
  // so there is nothing to scroll and every button is already mounted.
  final bar = find.descendant(
    of: find.byType(EditorToolbar),
    matching: find.byType(Scrollable),
  );
  if (button.evaluate().isEmpty && bar.evaluate().isNotEmpty) {
    await t.scrollUntilVisible(button, 120, scrollable: bar);
  }
  await t.ensureVisible(button);
  await t.pump();
  await t.tap(button);
  await t.pump(const Duration(milliseconds: 400));
}

/// A project with one of every selectable thing, all parked at the head of
/// the timeline so the playhead can be moved well clear of them.
({Project project, TextLayer text, StickerLayer sticker, OverlayLayer overlay})
_fixture() {
  final project = Project(name: 'Tools', clips: [_clip(), _clip(), _clip()]);
  final text = TextLayer(
    start: Duration.zero,
    duration: const Duration(seconds: 3),
    text: 'Hi',
  );
  final sticker = StickerLayer(
    start: Duration.zero,
    duration: const Duration(seconds: 3),
    content: '\u{1F600}',
  );
  final overlay = OverlayLayer(
    start: Duration.zero,
    duration: const Duration(seconds: 3),
    path: '/nonexistent/p.jpg',
    isImage: true,
    sourceDuration: const Duration(seconds: 4),
  );
  project.texts.add(text);
  project.stickers.add(sticker);
  project.overlays.add(overlay);
  return (project: project, text: text, sticker: sticker, overlay: overlay);
}

void main() {
  /// Mounts a fresh editor, parks the playhead at 9s — clear of every layer
  /// in [_fixture] — points the selection at [select], then taps [tool].
  ///
  /// One mount per tool on purpose: the bottom bar is replaced by the panel
  /// as soon as a tool opens one, so a second tap would have nothing to hit.
  Future<
    ({
      Project project,
      TextLayer text,
      StickerLayer sticker,
      OverlayLayer overlay,
      EditorController editor,
    })
  >
  openTool(
    WidgetTester tester,
    String tool,
    void Function(EditorController, dynamic) select,
  ) async {
    final f = _fixture();
    await tester.pumpWidget(_host(EditorScreen(project: f.project)));
    await tester.pump(const Duration(milliseconds: 300));
    final editor = _editorOf(tester);
    select(editor, f);
    editor.seek(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 300));

    await _tapTool(tester, tool);
    return (
      project: f.project,
      text: f.text,
      sticker: f.sticker,
      overlay: f.overlay,
      editor: editor,
    );
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  // Every one of these tools edits the *selected* thing while the canvas only
  // draws what sits under the *playhead*. Let the two drift apart and the
  // tool looks broken: the edit lands somewhere off screen.
  group('a tool always brings its target on screen', () {
    for (final tool in ['Edit', 'Animate', 'Keyframe']) {
      testWidgets('text — $tool', (tester) async {
        final r = await openTool(
          tester,
          tool,
          (ed, f) => ed.select(LaneKind.text, f.text.id),
        );
        expect(r.text.isVisibleAt(r.editor.position.value), isTrue);
        await teardown(tester);
      });
    }

    for (final tool in ['Style', 'Animate', 'Keyframe']) {
      testWidgets('sticker — $tool', (tester) async {
        final r = await openTool(
          tester,
          tool,
          (ed, f) => ed.select(LaneKind.sticker, f.sticker.id),
        );
        expect(r.sticker.isVisibleAt(r.editor.position.value), isTrue);
        await teardown(tester);
      });
    }

    for (final tool in [
      'Adjust',
      'Animate',
      'Keyframe',
      'Mask',
      'Chroma',
      'Blend',
      'Filter',
      'Effects',
      'Color',
    ]) {
      testWidgets('overlay — $tool', (tester) async {
        final r = await openTool(
          tester,
          tool,
          (ed, f) => ed.select(LaneKind.overlay, f.overlay.id),
        );
        expect(r.overlay.isVisibleAt(r.editor.position.value), isTrue);
        await teardown(tester);
      });
    }

    for (final tool in ['Rotate', 'Mirror']) {
      testWidgets('one-shot clip action — $tool', (tester) async {
        final r = await openTool(tester, tool, (ed, _) => ed.selectClip(0));
        expect(
          r.project.clipIndexAt(r.editor.position.value),
          0,
          reason: '$tool changed a clip the user could not see',
        );
        // The action itself still has to happen, not just the seek.
        final clip = r.project.clips.first;
        expect(clip.rotation != 0 || clip.mirrored, isTrue);
        await teardown(tester);
      });
    }

    testWidgets('transition parks on the junction it dresses', (tester) async {
      final r = await openTool(
        tester,
        'Transition',
        (ed, _) => ed.selectClip(0),
      );
      expect(r.editor.position.value, r.project.clipStart(1));
      await teardown(tester);
    });
  });

  testWidgets('the chroma panel opens for an overlay with no key picked', (
    tester,
  ) async {
    // `overlay?.chromaKeyColor ?? clips[clipIndex!]` fell through to the clip
    // branch whenever no key was set, and clipIndex is null there.
    final r = await openTool(
      tester,
      'Chroma',
      (ed, f) => ed.select(LaneKind.overlay, f.overlay.id),
    );
    expect(r.overlay.chromaKeyColor, isNull);
    expect(tester.takeException(), isNull);
    expect(find.byType(ChromaPanel), findsOneWidget);
    await teardown(tester);
  });
}
