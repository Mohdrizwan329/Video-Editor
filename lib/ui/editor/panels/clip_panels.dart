import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/duration_ext.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/video_clip.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_strip.dart';
import '../../widgets/panel_shell.dart';
import '../../widgets/app_slider.dart';

/// Playback rate: a flat multiplier, or one of the ramping curves.
class SpeedPanel extends StatefulWidget {
  const SpeedPanel({
    super.key,
    required this.editor,
    required this.index,
    required this.onClose,
  });

  final EditorController editor;
  final int index;
  final VoidCallback onClose;

  @override
  State<SpeedPanel> createState() => _SpeedPanelState();
}

class _SpeedPanelState extends State<SpeedPanel> {
  int _tab = 0;

  static const List<double> _presets = [0.25, 0.5, 1, 2, 4, 8];

  EditorController get editor => widget.editor;
  int get index => widget.index;

  @override
  void initState() {
    super.initState();
    _tab = editor.project.clips[index].speedCurve == SpeedCurve.none ? 0 : 1;
  }

  @override
  Widget build(BuildContext context) {
    final clip = editor.project.clips[index];
    return PanelShell(
      title: 'Speed',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      onReset: () => editor.updateClip(index, (c) {
        c.speed = 1;
        c.speedCurve = SpeedCurve.none;
      }),
      applyToAll: () => editor.applyToAllClips((c) {
        c.speed = clip.speed;
        c.speedCurve = clip.speedCurve;
      }),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ChipStrip(
            labels: const ['Normal', 'Curve'],
            selectedIndex: _tab,
            onSelected: (i) {
              setState(() => _tab = i);
              if (i == 0) {
                editor.updateClip(index, (c) => c.speedCurve = SpeedCurve.none);
              }
            },
          ),
          const SizedBox(height: 10),
          if (_tab == 1) ...[
            PanelStrip(
              gap: 9,
              runGap: 9,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final c in SpeedCurve.values)
                  GestureDetector(
                    onTap: () =>
                        editor.updateClip(index, (v) => v.speedCurve = c),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 62,
                          height: 50,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: clip.speedCurve == c
                                ? AppColors.accent.withValues(alpha: 0.16)
                                : AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: clip.speedCurve == c
                                  ? AppColors.accent
                                  : Colors.transparent,
                            ),
                          ),
                          child: CustomPaint(
                            painter: _CurvePainter(
                              c,
                              clip.speedCurve == c
                                  ? AppColors.accent
                                  : AppColors.textDim,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          c.label,
                          style: TextStyle(
                            fontSize: 9,
                            color: clip.speedCurve == c
                                ? AppColors.accent
                                : AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    size: 13,
                    color: AppColors.textFaint,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'New length ${clip.timelineDuration.timecode}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textFaint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ] else ...[
            PanelStrip(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final v in _presets)
                  GestureDetector(
                    onTap: () => editor.updateClip(index, (c) => c.speed = v),
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: (clip.speed - v).abs() < 0.001
                            ? AppColors.accent
                            : AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      // widthFactor, or the chip takes the whole line: a
                      // Wrap hands each child the full width to lay out in.
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          v % 1 == 0 ? '${v.toInt()}x' : '${v}x',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: (clip.speed - v).abs() < 0.001
                                ? AppColors.onAccent
                                : AppColors.textDim,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            AppSlider(
              label: 'Rate',
              value: clip.speed,
              min: 0.1,
              max: 8,
              defaultValue: 1,
              format: (v) => '${v.toStringAsFixed(2)}x',
              onChanged: (v) =>
                  editor.updateClip(index, (c) => c.speed = v, record: false),
              onChangeEnd: (v) => editor.updateClip(index, (c) => c.speed = v),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    size: 13,
                    color: AppColors.textFaint,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'New length ${clip.timelineDuration.timecode}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textFaint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Thumbnail sparkline of a speed ramp.
class _CurvePainter extends CustomPainter {
  _CurvePainter(this.curve, this.color);

  final SpeedCurve curve;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;
    if (curve.points.isEmpty) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      return;
    }
    const maxSpeed = 3.2;
    final path = Path();
    for (var i = 0; i < curve.points.length; i++) {
      final (p, sp) = curve.points[i];
      final x = p * size.width;
      final y = size.height - (sp / maxSpeed).clamp(0.0, 1.0) * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.curve != curve || old.color != color;
}

/// Clip volume plus the in/out fades applied to it.
class VolumePanel extends StatelessWidget {
  const VolumePanel({
    super.key,
    required this.editor,
    required this.index,
    required this.onClose,
  });

  final EditorController editor;
  final int index;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final clip = editor.project.clips[index];
    return PanelShell(
      title: 'Volume',
      onClose: onClose,
      onConfirm: onClose,
      onReset: () => editor.updateClip(index, (c) {
        c.volume = 1;
        c.fadeIn = Duration.zero;
        c.fadeOut = Duration.zero;
      }),
      applyToAll: () => editor.applyToAllClips((c) => c.volume = clip.volume),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          AppSlider(
            label: clip.volume == 0 ? 'Muted' : 'Level',
            icon: clip.volume == 0 ? Icons.volume_off : Icons.volume_up,
            value: clip.volume,
            min: 0,
            max: 2,
            defaultValue: 1,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v) =>
                editor.updateClip(index, (c) => c.volume = v, record: false),
            onChangeEnd: (v) => editor.updateClip(index, (c) => c.volume = v),
          ),
          AppSlider(
            label: 'Fade in',
            icon: Icons.north_east,
            value: clip.fadeIn.inMilliseconds / 1000,
            min: 0,
            max: 5,
            defaultValue: 0,
            format: (v) => '${v.toStringAsFixed(1)}s',
            onChanged: (v) => editor.updateClip(
              index,
              (c) => c.fadeIn = durationFromSeconds(v),
              record: false,
            ),
            onChangeEnd: (v) => editor.updateClip(
              index,
              (c) => c.fadeIn = durationFromSeconds(v),
            ),
          ),
          AppSlider(
            label: 'Fade out',
            icon: Icons.south_east,
            value: clip.fadeOut.inMilliseconds / 1000,
            min: 0,
            max: 5,
            defaultValue: 0,
            format: (v) => '${v.toStringAsFixed(1)}s',
            onChanged: (v) => editor.updateClip(
              index,
              (c) => c.fadeOut = durationFromSeconds(v),
              record: false,
            ),
            onChangeEnd: (v) => editor.updateClip(
              index,
              (c) => c.fadeOut = durationFromSeconds(v),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Crop with the ratio presets, plus pan/zoom of the clip inside the canvas.
class CropPanel extends StatelessWidget {
  const CropPanel({
    super.key,
    required this.editor,
    required this.index,
    required this.onClose,
  });

  final EditorController editor;
  final int index;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final clip = editor.project.clips[index];
    return PanelShell(
      title: 'Crop & Zoom',
      onClose: onClose,
      onConfirm: onClose,
      onReset: () => editor.updateClip(index, (c) {
        c.cropLeft = c.cropRight = c.cropTop = c.cropBottom = 0;
        c.scale = 1;
        c.offsetX = c.offsetY = 0;
        c.fit = FitMode.contain;
      }),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          _fitRow(clip),
          AppSlider(
            label: 'Zoom',
            value: clip.scale,
            min: 0.2,
            max: 4,
            defaultValue: 1,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v) =>
                editor.updateClip(index, (c) => c.scale = v, record: false),
            onChangeEnd: (v) => editor.updateClip(index, (c) => c.scale = v),
          ),
          AppSlider(
            label: 'Position X',
            value: clip.offsetX,
            min: -1,
            max: 1,
            bipolar: true,
            defaultValue: 0,
            format: (v) => v.toStringAsFixed(2),
            onChanged: (v) =>
                editor.updateClip(index, (c) => c.offsetX = v, record: false),
            onChangeEnd: (v) => editor.updateClip(index, (c) => c.offsetX = v),
          ),
          AppSlider(
            label: 'Position Y',
            value: clip.offsetY,
            min: -1,
            max: 1,
            bipolar: true,
            defaultValue: 0,
            format: (v) => v.toStringAsFixed(2),
            onChanged: (v) =>
                editor.updateClip(index, (c) => c.offsetY = v, record: false),
            onChangeEnd: (v) => editor.updateClip(index, (c) => c.offsetY = v),
          ),
          const Divider(height: 18),
          _cropSlider(
            'Left',
            clip.cropLeft,
            (v) => editor.updateClip(index, (c) => c.cropLeft = v),
          ),
          _cropSlider(
            'Right',
            clip.cropRight,
            (v) => editor.updateClip(index, (c) => c.cropRight = v),
          ),
          _cropSlider(
            'Top',
            clip.cropTop,
            (v) => editor.updateClip(index, (c) => c.cropTop = v),
          ),
          _cropSlider(
            'Bottom',
            clip.cropBottom,
            (v) => editor.updateClip(index, (c) => c.cropBottom = v),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _fitRow(VideoClip clip) {
    const modes = [
      (FitMode.contain, 'Fit', Icons.fit_screen),
      (FitMode.cover, 'Fill', Icons.crop_free),
      (FitMode.stretch, 'Stretch', Icons.open_in_full),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          for (final (mode, label, icon) in modes)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => editor.updateClip(index, (c) => c.fit = mode),
                  child: Container(
                    // A minimum, not a fixed height: at a large system font
                    // the icon and label together need more than 42.
                    constraints: const BoxConstraints(minHeight: 42),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: clip.fit == mode
                          ? AppColors.accent.withValues(alpha: 0.18)
                          : AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: clip.fit == mode
                            ? AppColors.accent
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 15,
                          color: clip.fit == mode
                              ? AppColors.accent
                              : AppColors.textDim,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.5,
                            color: clip.fit == mode
                                ? AppColors.accent
                                : AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cropSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return AppSlider(
      label: 'Crop $label',
      value: value,
      min: 0,
      max: 0.45,
      defaultValue: 0,
      format: (v) => '${(v * 100).round()}%',
      onChanged: onChanged,
    );
  }
}

/// Still-image duration, or trim length for a video clip.
class DurationPanel extends StatelessWidget {
  const DurationPanel({
    super.key,
    required this.editor,
    required this.index,
    required this.onClose,
  });

  final EditorController editor;
  final int index;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final clip = editor.project.clips[index];
    final maxSeconds = clip.isImage
        ? 30.0
        : clip.sourceDuration.seconds.clamp(0.5, 3600.0).toDouble();
    return PanelShell(
      title: 'Duration',
      onClose: onClose,
      onConfirm: onClose,
      applyToAll: clip.isImage
          ? () => editor.applyToAllClips((c) {
              if (!c.isImage) return;
              c.sourceDuration = clip.sourceDuration;
              c.trimStart = Duration.zero;
              c.trimEnd = clip.sourceDuration;
            })
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          AppSlider(
            label: 'Length',
            value: clip.trimmedDuration.seconds
                .clamp(0.2, maxSeconds)
                .toDouble(),
            min: 0.2,
            max: maxSeconds,
            format: (v) => '${v.toStringAsFixed(1)}s',
            onChanged: (v) =>
                editor.setClipDuration(index, durationFromSeconds(v)),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
