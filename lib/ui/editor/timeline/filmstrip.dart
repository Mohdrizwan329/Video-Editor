import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/video_clip.dart';
import '../../../data/services/thumbnail_service.dart';

/// The frame strip drawn inside a clip. Frames are requested lazily for the
/// tiles that are actually on screen and cached by (file, time, height).
class Filmstrip extends StatefulWidget {
  const Filmstrip({
    super.key,
    required this.clip,
    required this.width,
    required this.height,
  });

  final VideoClip clip;
  final double width;
  final double height;

  @override
  State<Filmstrip> createState() => _FilmstripState();
}

class _FilmstripState extends State<Filmstrip> {
  final Map<int, String> _frames = {};
  int _generation = 0;

  double get _tileWidth => widget.height * 0.72;

  int get _tileCount =>
      (widget.width / _tileWidth).ceil().clamp(1, 400);

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(covariant Filmstrip old) {
    super.didUpdateWidget(old);
    final clip = widget.clip;
    if (old.clip.path != clip.path ||
        old.clip.trimStart != clip.trimStart ||
        old.clip.trimEnd != clip.trimEnd ||
        old.clip.speed != clip.speed ||
        (old.width - widget.width).abs() > _tileWidth) {
      _frames.clear();
      _generation++;
      _request();
    }
  }

  Future<void> _request() async {
    final clip = widget.clip;
    if (clip.isImage) return;
    final generation = _generation;
    final count = _tileCount;
    final span = clip.trimmedDuration;
    for (var i = 0; i < count; i++) {
      final at = clip.trimStart +
          Duration(microseconds: (span.inMicroseconds * (i + 0.5) / count).round());
      final cached = ThumbnailService.instance.cached(clip.path, at, 120);
      if (cached != null) {
        _frames[i] = cached;
        continue;
      }
      final path = await ThumbnailService.instance.frame(clip.path, at);
      if (!mounted || generation != _generation) return;
      if (path != null) setState(() => _frames[i] = path);
    }
    if (mounted && generation == _generation) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.clip.isImage) {
      return Image.file(
        File(widget.clip.path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _blank(),
      );
    }
    // The tile count follows the requested width so it matches the frames that
    // were fetched, but the tiles share whatever width the parent actually
    // hands us -- a clip's border eats a pixel or two off `widget.width`, and
    // laying out for the larger figure would overflow the row.
    final count = _tileCount;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(count, (i) {
        final path = _frames[i];
        return Expanded(
          child: path == null
              ? _blank()
              : Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => _blank(),
                ),
        );
      }),
    );
  }

  Widget _blank() => const ColoredBox(color: AppColors.surfaceHigh);
}
