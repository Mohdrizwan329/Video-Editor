import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor/ui/editor/preview/matte_box.dart';

/// The mattes the cutout pass leaves behind, and what the preview must make
/// of them.
///
/// The exporter merges them with `alphamerge`, which reads brightness. The
/// preview masks with `dstIn`, which reads alpha. The two disagreeing is
/// exactly how a cutout can be right in the file and invisible on screen, so
/// these check the picture rather than the wiring.
void main() {
  late Directory frames;

  setUp(() async {
    frames = await Directory.systemTemp.createTemp('matte');
    // Frame 1 keeps the left half, frame 2 the right: a mask that moves is
    // the only way to tell "reads the matte" from "reads the first matte".
    await _writeMatte('${frames.path}/00001.png', keepLeft: true);
    await _writeMatte('${frames.path}/00002.png', keepLeft: false);
  });

  tearDown(() => frames.deleteSync(recursive: true));

  testWidgets('cuts the picture where the matte is dark', (tester) async {
    final shot = await _render(tester, frames.path, Duration.zero);
    expect(_alphaAt(shot, 0.25), greaterThan(200), reason: 'subject kept');
    expect(_alphaAt(shot, 0.75), lessThan(50), reason: 'background cut');
  });

  testWidgets('follows the playhead into the next matte', (tester) async {
    // 15 stills a second, so 100ms in is frame two.
    final shot = await _render(
      tester,
      frames.path,
      const Duration(milliseconds: 100),
    );
    expect(_alphaAt(shot, 0.25), lessThan(50));
    expect(_alphaAt(shot, 0.75), greaterThan(200));
  });

  testWidgets('a matte that is not there leaves the clip whole', (
    tester,
  ) async {
    final shot = await _render(tester, '${frames.path}/gone', Duration.zero);
    expect(_alphaAt(shot, 0.25), greaterThan(200));
    expect(_alphaAt(shot, 0.75), greaterThan(200));
  });
}

/// Renders [MatteBox] over a solid square and returns its pixels.
Future<ByteData> _render(
  WidgetTester tester,
  String dir,
  Duration localTime,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: key,
        child: SizedBox(
          width: 100,
          height: 100,
          child: MatteBox(
            framesDir: dir,
            fps: 15,
            localTime: localTime,
            child: const ColoredBox(color: Color(0xFFFF0000)),
          ),
        ),
      ),
    ),
  );
  // The matte is read off disk and decoded twice, so give the load a few
  // real turns of the clock before deciding what the frame looks like.
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late ByteData data;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    data = (await image.toByteData())!;
    image.dispose();
  });
  return data;
}

/// The alpha of the pixel [x] of the way across the middle row.
int _alphaAt(ByteData shot, double x) {
  const side = 100;
  final px = (x * side).round().clamp(0, side - 1);
  return shot.getUint8(((side ~/ 2) * side + px) * 4 + 3);
}

/// Writes a matte the way the cutout pass does: grey, and fully opaque.
Future<void> _writeMatte(String path, {required bool keepLeft}) async {
  const side = 64;
  final rgba = Uint8List(side * side * 4);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final keep = (x < side / 2) == keepLeft;
      final o = (y * side + x) * 4;
      rgba[o] = rgba[o + 1] = rgba[o + 2] = keep ? 255 : 0;
      rgba[o + 3] = 255;
    }
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: side,
    height: side,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(png!.buffer.asUint8List(), flush: true);
  frame.image.dispose();
  codec.dispose();
  descriptor.dispose();
}
