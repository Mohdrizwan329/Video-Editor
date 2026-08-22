import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/ui/editor/toolbar/editor_toolbar.dart';

/// Opens [label] from the editor's tool strip.
///
/// The strip is one flat list now — no families to switch first — but it is
/// lazily built, so a tool past its edge is not mounted until it has been
/// scrolled into view. The list runs sideways under the preview and downwards
/// in the wide layout's rail, so the drag follows whichever axis the strip is
/// actually scrolling on.
Future<void> tapEditorTool(WidgetTester tester, String label) async {
  final button = await revealEditorTool(tester, label);
  await tester.ensureVisible(button.first);
  await tester.pump();
  await tester.tap(button.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Scrolls [label] into view and hands back its finder, without tapping it —
/// for a test that wants to look at the button rather than press it.
Future<Finder> revealEditorTool(WidgetTester tester, String label) async {
  final button = find.descendant(
    of: find.byType(EditorToolbar),
    matching: find.text(label),
  );
  if (button.evaluate().isEmpty) {
    final scrollable = find.descendant(
      of: find.byType(EditorToolbar),
      matching: find.byType(Scrollable),
    );
    if (scrollable.evaluate().isEmpty) return button;
    final axis = tester.widget<Scrollable>(scrollable.first).axisDirection;
    final step = axis == AxisDirection.down || axis == AxisDirection.up
        ? const Offset(0, -120)
        : const Offset(-120, 0);
    await tester.dragUntilVisible(
      button,
      scrollable.first,
      step,
      maxIteration: 60,
    );
  }
  return button;
}
