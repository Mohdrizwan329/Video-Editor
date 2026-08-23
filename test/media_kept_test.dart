import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:video_editor/core/theme/app_theme.dart';
import 'package:video_editor/core/utils/responsive.dart';
import 'package:video_editor/data/models/enums.dart';
import 'package:video_editor/data/models/project.dart';
import 'package:video_editor/data/models/video_clip.dart';
import 'package:video_editor/state/editor_controller.dart';
import 'package:video_editor/state/projects_controller.dart';
import 'package:video_editor/ui/editor/editor_screen.dart';

/// A picked file's path is not a promise: the user can delete the photo from
/// the gallery, and for a cloud item the picker hands over a cache copy the
/// system is free to evict. A project pointing at either opens on a black
/// canvas, and from there every tool looks broken — it is acting on a frame
/// that is not there. Imports are copied into the app's own storage so that
/// cannot happen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late Directory gallery;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('media_kept');
    gallery = Directory.systemTemp.createTempSync('gallery');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => sandbox.path,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    for (final d in [sandbox, gallery]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  /// A file standing in for something the user picked out of the gallery.
  File picked(String name) {
    final f = File('${gallery.path}/$name')..createSync();
    // A PNG header is enough for the probe to call it an image.
    f.writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    return f;
  }

  test('an imported clip stops pointing at the gallery', () async {
    final editor = EditorController(Project(name: 'Import'));
    addTearDown(editor.dispose);
    final source = picked('holiday.png');

    await editor.addMedia([source.path]);

    final stored = editor.project.clips.single.path;
    expect(
      stored,
      isNot(source.path),
      reason: 'the clip still points at the picked file',
    );
    expect(File(stored).existsSync(), isTrue);
    expect(
      stored.startsWith(sandbox.path),
      isTrue,
      reason: 'the copy is not in the app\'s own storage: $stored',
    );
  });

  test('deleting the picked file leaves the project working', () async {
    final editor = EditorController(Project(name: 'Import'));
    addTearDown(editor.dispose);
    final source = picked('holiday.png');

    await editor.addMedia([source.path]);
    source.deleteSync();

    expect(
      File(editor.project.clips.single.path).existsSync(),
      isTrue,
      reason: 'the project died with the file in the gallery',
    );
  });

  test('a file already in app storage is not copied again', () async {
    final editor = EditorController(Project(name: 'Import'));
    addTearDown(editor.dispose);
    final source = picked('a.png');

    await editor.addMedia([source.path]);
    final first = editor.project.clips.single.path;
    await editor.addMedia([first]);

    expect(
      editor.project.clips[1].path,
      first,
      reason: 'app storage got a copy of its own copy',
    );
  });

  test('overlays and audio are kept too', () async {
    final editor = EditorController(Project(name: 'Import'));
    addTearDown(editor.dispose);

    await editor.addOverlay(picked('pip.png').path);
    await editor.addAudio(picked('song.png').path);

    expect(
      editor.project.overlays.single.path.startsWith(sandbox.path),
      isTrue,
    );
    expect(editor.project.audios.single.path.startsWith(sandbox.path), isTrue);
  });

  testWidgets('a project whose media is gone says so', (tester) async {
    tester.view.physicalSize =
        const Size(390, 844) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);

    final project = Project(
      name: 'Gone',
      ratio: CanvasRatio.r9x16,
      clips: [
        VideoClip(
          path: '${gallery.path}/deleted.mp4',
          isImage: false,
          sourceDuration: const Duration(seconds: 4),
        ),
      ],
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ProjectsController(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          scrollBehavior: const AppScrollBehavior(),
          home: EditorScreen(project: project),
        ),
      ),
    );
    // The check is real file IO, which only runs on the live event loop.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('missing'),
      findsOneWidget,
      reason: 'the editor opened on a black canvas without a word',
    );
  });
}
