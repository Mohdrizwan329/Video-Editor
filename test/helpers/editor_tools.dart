import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/ui/editor/toolbar/category_bar.dart';
import 'package:video_editor/ui/editor/toolbar/editor_toolbar.dart';

/// Which bottom-bar category a tool lives under.
///
/// The editor's tool strip shows one family at a time now, so a test that
/// wants a tool has to put its category in front first — the same tap a user
/// makes. Tools that appear in more than one family are listed under the one
/// the bar opens on.
ToolCategory? categoryOf(String label) => switch (label) {
  'Split' || 'Replace' || 'Delete' || 'Crop' || 'Change speed' || 'Sort' =>
    ToolCategory.trim,
  'Audio' || 'Voice' || 'TTS' || 'Extract' || 'Volume' || 'Mix' =>
    ToolCategory.music,
  'Text' || 'Captions' || 'Sticker' => ToolCategory.text,
  'Adjust' || 'Keyframe' || 'Mask' || 'Chroma' || 'Stabilize' =>
    ToolCategory.adjust,
  'Filter' || 'Effects' => ToolCategory.filter,
  'Canvas' || 'Backdrop' || 'Overlay' || 'Watermark' => ToolCategory.frame,
  _ => null,
};

/// The clip tools that are not one of the six on the strip: they live behind
/// the '⋯' on the context row, which only appears once a clip is selected.
const Set<String> moreMenuTools = {
  'Duplicate',
  'Duration',
  'Transition',
  'Rotate',
  'Mirror',
  'Reverse',
  'Freeze frame',
};

/// Brings [label]'s family of tools to the front of the strip.
///
/// A no-op when the label is a layer tool with no category of its own, or
/// when the bar is not on screen — a panel is open over it, say.
Future<void> openToolCategory(WidgetTester tester, String label) async {
  final category = categoryOf(label);
  if (category == null) return;
  final bar = find.byType(CategoryBar);
  if (bar.evaluate().isEmpty) return;
  // A short window scrolls the whole editor column, which can leave the bar
  // below the fold — scroll it back into reach before tapping, the way a
  // user would.
  final tab = find.descendant(of: bar, matching: find.byIcon(category.icon));
  if (tab.evaluate().isEmpty) return;
  await tester.ensureVisible(tab.first);
  await tester.pump();
  await tester.tap(tab.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 200));
}

/// Opens [label] from the editor's tool strip.
///
/// Puts the tool's category in front first, then scrolls the strip along —
/// it is a lazily-built list, so a tool past its right edge is not mounted
/// until it is scrolled into view.
Future<void> tapEditorTool(WidgetTester tester, String label) async {
  if (moreMenuTools.contains(label)) {
    final more = find.descendant(
        of: find.byType(EditorToolbar), matching: find.byIcon(Icons.more_horiz));
    expect(more, findsOneWidget,
        reason: "'$label' lives behind the context row's overflow menu, "
            'which needs a clip selected');
    await tester.ensureVisible(more);
    await tester.pump();
    await tester.tap(more, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    return;
  }
  // Scoped to the strip: the category bar along the bottom carries some of
  // the same words, so an unscoped finder would match twice.
  final button = find.descendant(
      of: find.byType(EditorToolbar), matching: find.text(label));
  // Switch family only when the tool is not already on the strip — the tools
  // for a selected layer take it over whatever the category is, and taking
  // the tab would drop that selection.
  if (button.evaluate().isEmpty) {
    await openToolCategory(tester, label);
  }
  if (button.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      button,
      find.byType(EditorToolbar),
      const Offset(-120, 0),
      maxIteration: 40,
    );
  }
  await tester.ensureVisible(button.first);
  await tester.pump();
  await tester.tap(button.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 300));
}
