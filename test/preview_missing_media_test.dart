import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/data/models/layers.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/ui/editor/preview/clip_view.dart';
import 'package:video_editor/ui/editor/preview/layer_views.dart';

/// A clip pointing at a file that is not there — media the user deleted from
/// the phone after building the project on it.
VideoClip _gone({bool isImage = false}) => VideoClip(
      path: '/nonexistent/clip.mp4',
      isImage: isImage,
      sourceDuration: const Duration(seconds: 6),
    );

Widget _stage(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 300, height: 500, child: child),
        ),
      ),
    );

void main() {
  group('a clip whose file has gone', () {
    testWidgets('says so instead of showing a black rectangle',
        (tester) async {
      await tester.pumpWidget(_stage(
        ClipView(clip: _gone(), controller: null, unopenable: true),
      ));
      await tester.pump();

      expect(find.textContaining('could not be opened'), findsOneWidget);
      expect(find.textContaining('moved or deleted'), findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);
    });

    testWidgets('stays quiet while the decoder is still opening',
        (tester) async {
      // Not yet known to be broken: this is the ordinary first frame of a
      // clip that is about to appear, and it must not accuse the file.
      await tester.pumpWidget(_stage(
        ClipView(clip: _gone(), controller: null),
      ));
      await tester.pump();

      expect(find.byType(MissingMedia), findsNothing);
      expect(find.textContaining('could not be opened'), findsNothing);
    });

    testWidgets('a floating clip that has lost its media says so too',
        (tester) async {
      final pip = OverlayLayer(
        start: Duration.zero,
        duration: const Duration(seconds: 4),
        path: '/nonexistent/pip.mp4',
        isImage: false,
        sourceDuration: const Duration(seconds: 4),
      );
      // The view positions itself on the canvas, so it needs a Stack the way
      // the stage gives it one.
      await tester.pumpWidget(_stage(
        Stack(
          children: [
            OverlayLayerView(
              layer: pip,
              time: const Duration(seconds: 1),
              canvasSize: const Size(300, 500),
              controller: null,
              unopenable: true,
            ),
          ],
        ),
      ));
      await tester.pump();

      expect(find.byType(MissingMedia), findsOneWidget);
    });

    testWidgets('a photo clip that will not load says the same thing',
        (tester) async {
      // Image.file only discovers the file is missing by going to the disk,
      // which needs a real event loop.
      await tester.runAsync(() async {
        await tester.pumpWidget(_stage(
          ClipView(clip: _gone(isImage: true), controller: null),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump();
      });

      expect(find.byType(MissingMedia), findsOneWidget);
    });
  });
}
