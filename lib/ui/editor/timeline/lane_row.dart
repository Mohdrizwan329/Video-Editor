import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/layers.dart';
import '../../../state/editor_controller.dart';

/// One secondary lane (audio, text, sticker or PIP). Bars can be dragged
/// along the timeline and resized from either edge.
class LaneRow extends StatelessWidget {
  const LaneRow({
    super.key,
    required this.editor,
    required this.kind,
    required this.layers,
    required this.pixelsPerSecond,
    required this.width,
    required this.color,
    required this.icon,
    this.labelBuilder,
  });

  final EditorController editor;
  final LaneKind kind;
  final List<TimelineLayer> layers;
  final double pixelsPerSecond;
  final double width;
  final Color color;
  final IconData icon;
  final String Function(TimelineLayer)? labelBuilder;

  double _x(Duration d) => d.inMicroseconds / 1000000 * pixelsPerSecond;

  @override
  Widget build(BuildContext context) {
    if (layers.isEmpty) return const SizedBox.shrink();
    // Pack overlapping bars onto sub-rows so nothing is hidden.
    final rows = _pack(layers);
    return Padding(
      padding: const EdgeInsets.only(top: kLaneGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            SizedBox(
              width: width,
              height: kLaneHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final layer in row)
                    Positioned(
                      left: _x(layer.start),
                      width: _x(layer.duration).clamp(10.0, double.infinity),
                      top: 0,
                      bottom: 0,
                      child: _bar(context, layer),
                    ),
                ],
              ),
            ),
          if (rows.length > 1) const SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, TimelineLayer layer) {
    final selected = editor.selection.matches(kind, layer.id);
    final label = labelBuilder?.call(layer) ?? '';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => editor.select(kind, layer.id),
      onHorizontalDragStart: (_) {
        editor.select(kind, layer.id);
        HapticFeedback.selectionClick();
      },
      onHorizontalDragUpdate: (d) {
        editor.moveLayer(
          layer,
          layer.start +
              Duration(microseconds: (d.delta.dx / pixelsPerSecond * 1e6).round()),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          // Near-opaque on purpose: the chip sits on a light timeline now, so
          // a translucent fill would wash the hue out and lose the white label.
          color: color.withValues(alpha: selected ? 1 : 0.88),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: selected ? 1.6 : 0,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Icon(icon, size: 11, color: Colors.white),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: const TextStyle(
                          fontSize: 9.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            if (layer is AudioLayer && layer.waveform.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _WavePainter(layer.waveform)),
                ),
              ),
            if (layer is AudioLayer && layer.beats.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _BeatPainter(
                      beats: layer.beats,
                      trimStart: layer.trimStart,
                      duration: layer.duration,
                    ),
                  ),
                ),
              ),
            if (selected) ...[
              _grip(layer, left: true),
              _grip(layer, left: false),
            ],
          ],
        ),
      ),
    );
  }

  Widget _grip(TimelineLayer layer, {required bool left}) {
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) {
          final delta =
              Duration(microseconds: (d.delta.dx / pixelsPerSecond * 1e6).round());
          if (left) {
            editor.resizeLayer(layer, start: layer.start + delta);
          } else {
            editor.resizeLayer(layer, end: layer.end + delta);
          }
        },
        child: Container(
          width: 9,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(left ? 3 : 0),
              right: Radius.circular(left ? 0 : 3),
            ),
          ),
        ),
      ),
    );
  }

  /// Greedy packing: a bar goes on the first row where it does not overlap.
  static List<List<TimelineLayer>> _pack(List<TimelineLayer> layers) {
    final sorted = [...layers]..sort((a, b) => a.start.compareTo(b.start));
    final rows = <List<TimelineLayer>>[];
    for (final layer in sorted) {
      var placed = false;
      for (final row in rows) {
        if (row.last.end <= layer.start) {
          row.add(layer);
          placed = true;
          break;
        }
      }
      if (!placed) rows.add([layer]);
    }
    return rows;
  }
}

/// Tick per detected onset, so cuts can be lined up with the music.
class _BeatPainter extends CustomPainter {
  _BeatPainter({
    required this.beats,
    required this.trimStart,
    required this.duration,
  });

  final List<Duration> beats;
  final Duration trimStart;
  final Duration duration;

  @override
  void paint(Canvas canvas, Size size) {
    if (duration.inMicroseconds <= 0) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 1;
    for (final b in beats) {
      final local = b - trimStart;
      if (local < Duration.zero || local > duration) continue;
      final x = local.inMicroseconds / duration.inMicroseconds * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height * 0.28), paint);
      canvas.drawLine(
          Offset(x, size.height * 0.72), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BeatPainter old) =>
      old.beats != beats || old.trimStart != trimStart;
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.samples);

  final List<double> samples;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final mid = size.height / 2;
    for (var x = 0.0; x < size.width; x += 2) {
      final i = ((x / size.width) * samples.length).floor().clamp(0, samples.length - 1);
      final h = samples[i] * mid;
      canvas.drawLine(Offset(x, mid - h), Offset(x, mid + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.samples != samples;
}
