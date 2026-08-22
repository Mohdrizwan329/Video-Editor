import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Knocks the background out of the preview using the same mattes the
/// exporter merges into the file.
///
/// The renderer pairs the clip with a matte *video* through `alphamerge`. A
/// preview cannot do that — asking a player for one particular frame every
/// time it paints is far slower than painting — so the cutout pass keeps the
/// same mattes as small stills and this reads the one under the playhead.
/// Same numbers, same rate, so what the user sees is the cut the render will
/// make rather than a promise of one.
///
/// A matte that has not finished loading shows the clip untouched: a frame
/// with no cut is better than a frame with no picture.
class MatteBox extends StatefulWidget {
  const MatteBox({
    super.key,
    required this.framesDir,
    required this.fps,
    required this.localTime,
    required this.child,
  });

  /// Where the stills live, named `00001.png` upward from the clip's start.
  final String framesDir;

  /// Stills a second, which is how [localTime] becomes an index.
  final int fps;

  /// How far into the clip the playhead is.
  final Duration localTime;

  final Widget child;

  @override
  State<MatteBox> createState() => _MatteBoxState();
}

class _MatteBoxState extends State<MatteBox> {
  /// Decoded mattes, by frame index. A matte is a few kilobytes, and a clip
  /// is played over and over while it is being cut — decoding the same
  /// handful of frames on every pass would cost more than holding them.
  static final Map<String, ui.Image> _cache = {};

  /// Which keys are already being decoded, so a frame held on screen for
  /// several painted frames is not fetched several times over.
  static final Set<String> _loading = {};

  int get _index => (widget.localTime.inMilliseconds * widget.fps / 1000)
      .floor()
      .clamp(0, 1 << 20);

  String get _key => '${widget.framesDir}/$_index';

  ui.Image? get _matte => _cache[_key];

  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(MatteBox old) {
    super.didUpdateWidget(old);
    _ensure();
  }

  Future<void> _ensure() async {
    final key = _key;
    if (_cache.containsKey(key) || _loading.contains(key)) return;
    _loading.add(key);
    try {
      // The sequence is one-based, the way FFmpeg's image demuxer numbers it.
      final name = (_index + 1).toString().padLeft(5, '0');
      final file = File('${widget.framesDir}/$name.png');
      if (!await file.exists()) return;
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final frame = await codec.getNextFrame();
      codec.dispose();
      final matte = await _asAlpha(frame.image);
      frame.image.dispose();
      if (matte == null) return;
      _cache[key] = matte;
      if (mounted) setState(() {});
    } catch (_) {
      // A matte that cannot be read leaves the clip whole, which is the
      // safe way to be wrong.
    } finally {
      _loading.remove(key);
    }
  }

  /// Turns the grey matte into an alpha one.
  ///
  /// The stills are written the way `alphamerge` wants them — brightness
  /// carries the mask and every pixel is opaque. `dstIn` reads alpha instead,
  /// so handed the file as it is, it would find the whole frame opaque and cut
  /// nothing. Moving brightness into alpha here keeps one set of files
  /// answering to both, rather than baking the same mask twice.
  static Future<ui.Image?> _asAlpha(ui.Image grey) async {
    final data = await grey.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final px = data.buffer.asUint8List();
    for (var i = 0; i < px.length; i += 4) {
      px[i + 3] = px[i];
      px[i] = 255;
      px[i + 1] = 255;
      px[i + 2] = 255;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      px,
      grey.width,
      grey.height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  @override
  Widget build(BuildContext context) {
    final matte = _matte;
    if (matte == null) return widget.child;
    return ShaderMask(
      // `dstIn` keeps the clip where the matte is bright and drops it where
      // the matte is dark — the same thing `alphamerge` does at export.
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => ui.ImageShader(
        matte,
        TileMode.clamp,
        TileMode.clamp,
        (Matrix4.identity()..scaleByDouble(
              rect.width / matte.width,
              rect.height / matte.height,
              1,
              1,
            ))
            .storage,
      ),
      child: widget.child,
    );
  }
}
