import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/core/utils/responsive.dart';
import 'package:video_editor/ui/picker/media_picker_screen.dart';

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.light,
  scrollBehavior: const AppScrollBehavior(),
  home: child,
);

void main() {
  group('a picker asked for one kind of media', () {
    testWidgets('offers photos only, with no way to reach a video', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const MediaPickerScreen(
            title: 'Watermark logo',
            filter: RequestType.image,
            maxSelection: 1,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // The caller asked for images: a Video tab would hand back an asset the
      // watermark cannot draw, and an All tab does the same.
      expect(find.text('Video'), findsNothing);
      expect(find.text('All'), findsNothing);
    });

    testWidgets('offers videos only when asked for video', (tester) async {
      await tester.pumpWidget(
        _host(const MediaPickerScreen(filter: RequestType.video)),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Photo'), findsNothing);
      expect(find.text('All'), findsNothing);
    });

    testWidgets('still offers every tab when the caller wants anything', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const MediaPickerScreen()));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Photo'), findsOneWidget);
    });
  });
}
