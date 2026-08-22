import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/ui/image_editor/image_editor_screen.dart';

/// The photo editor's tool panel used to open at a hand-picked 178pt (212 for
/// three of the tools), which was shorter than what Core, Markup, Retouch,
/// Pixelate and Watermark actually draw — each of them hid a row behind a
/// scroll while the photo above it floated in a band of white. The panel now
/// takes what its controls need out of the room the window can spare.
void main() {
  const panelKey = ValueKey('photo-panel');

  /// Tools whose controls are short enough to fit on a phone. Adjust is not
  /// among them on purpose: it is a long column of sliders and scrolling is
  /// the right answer for it.
  const fitsOnAPhone = [
    'Core',
    'Filter',
    'Markup',
    'Text',
    'Watermark',
    'Pixelate',
    'Retouch',
  ];

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: ImageEditorScreen(path: '/nonexistent.jpg'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapTool(WidgetTester tester, String label) async {
    final f = find.text(label).last;
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await tester.pump(const Duration(milliseconds: 250));
  }

  /// How much of the panel is out of reach without scrolling it.
  double hidden(WidgetTester tester) {
    final scrollable = find.descendant(
      of: find.byKey(panelKey),
      matching: find.byType(Scrollable),
    );
    return tester.state<ScrollableState>(scrollable.first).position
        .maxScrollExtent;
  }

  testWidgets('a tool that fits shows all of itself', (tester) async {
    await open(tester, const Size(390, 844));

    for (final tool in fitsOnAPhone) {
      await tapTool(tester, tool);
      expect(hidden(tester), 0,
          reason: '$tool hides ${hidden(tester)}pt of controls behind a '
              'scroll on a 390x844 phone');
    }
  });

  testWidgets('the photo keeps the larger half of the screen', (tester) async {
    await open(tester, const Size(390, 844));

    for (final tool in const ['Core', 'Adjust', 'Watermark']) {
      await tapTool(tester, tool);
      final panel = tester.getRect(find.byKey(panelKey));
      expect(panel.height / 844, lessThan(0.5),
          reason: '$tool took ${panel.height}pt of an 844pt window');
    }
  });

  testWidgets('a short window still lays out without overflowing',
      (tester) async {
    // A small phone, where the panel has to give way rather than push the
    // photo off the screen.
    await open(tester, const Size(360, 640));

    for (final tool in const [
      'Core', 'Adjust', 'Filter', 'AI Face', 'Markup',
      'Text', 'Watermark', 'Pixelate', 'Retouch',
    ]) {
      await tapTool(tester, tool);
      expect(tester.takeException(), isNull, reason: '$tool overflowed');
    }
  });
}
