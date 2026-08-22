import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/data/repositories/adjust_layout_store.dart';

/// The layout has to survive the app growing. A knob added in a later version
/// is not in anybody's saved file, and the one thing that must never happen
/// is for it to be invisible because of that.
void main() {
  final store = AdjustLayoutStore.instance;
  const shipped = ['Lightness', 'Contrast', 'Warmth', 'Tint', 'Saturation'];

  setUp(() => store.seed());

  test('an empty layout is the order the app ships with', () {
    expect(store.arrange(shipped), shipped);
    expect(store.visible(shipped), shipped);
  });

  test('a stored order is honoured', () {
    store.seed(order: ['Tint', 'Contrast', 'Lightness']);
    expect(
      store.arrange(shipped),
      ['Tint', 'Contrast', 'Lightness', 'Warmth', 'Saturation'],
      reason: 'the knobs the file never mentioned should follow behind',
    );
  });

  test('a knob added since the file was written still shows up', () {
    store.seed(order: shipped);
    final grown = [...shipped, 'Film Grain'];
    expect(store.arrange(grown).contains('Film Grain'), isTrue);
    expect(store.visible(grown).contains('Film Grain'), isTrue);
  });

  test('a knob dropped from the app is dropped from the order', () {
    store.seed(order: ['Lightness', 'Gone', 'Contrast']);
    expect(store.arrange(shipped).contains('Gone'), isFalse);
  });

  test('hidden knobs leave the row but stay in the manage list', () {
    store.seed(hidden: {'Tint'});
    expect(store.visible(shipped).contains('Tint'), isFalse);
    expect(store.arrange(shipped).contains('Tint'), isTrue);
  });

  test('hiding and showing are the same switch, both ways', () async {
    expect(store.isHidden('Warmth'), isFalse);
    await store.setHidden('Warmth', true);
    expect(store.isHidden('Warmth'), isTrue);
    await store.setHidden('Warmth', false);
    expect(store.isHidden('Warmth'), isFalse);
  });

  test('reset puts everything back', () async {
    store.seed(order: ['Tint'], hidden: {'Contrast'});
    await store.reset();
    expect(store.arrange(shipped), shipped);
    expect(store.visible(shipped), shipped);
  });
}
