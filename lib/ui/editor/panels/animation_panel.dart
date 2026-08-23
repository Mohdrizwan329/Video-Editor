import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/enums.dart';
import '../../widgets/panel_strip.dart';
import '../../widgets/panel_shell.dart';
import '../../widgets/app_slider.dart';

/// In/out animation chooser shared by text, stickers and PIP layers.
class AnimationPicker extends StatefulWidget {
  const AnimationPicker({
    super.key,
    required this.animationIn,
    required this.animationOut,
    required this.duration,
    required this.onIn,
    required this.onOut,
    required this.onDuration,
  });

  final LayerAnimation animationIn;
  final LayerAnimation animationOut;
  final Duration duration;
  final ValueChanged<LayerAnimation> onIn;
  final ValueChanged<LayerAnimation> onOut;
  final ValueChanged<Duration> onDuration;

  @override
  State<AnimationPicker> createState() => _AnimationPickerState();
}

class _AnimationPickerState extends State<AnimationPicker> {
  int _side = 0;

  @override
  Widget build(BuildContext context) {
    final current = _side == 0 ? widget.animationIn : widget.animationOut;
    // A fixed stack of rows. It keeps its shape rather than squeezing when
    // the sheet is short — the sheet is the one that scrolls.
    return Column(
      children: [
        ChipStrip(
          labels: const ['In', 'Out'],
          selectedIndex: _side,
          onSelected: (i) => setState(() => _side = i),
        ),
        const SizedBox(height: 10),
        PanelStrip(
          gap: 9,
          runGap: 9,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            for (final a in LayerAnimation.values)
              GestureDetector(
                onTap: () => _side == 0 ? widget.onIn(a) : widget.onOut(a),
                child: Container(
                  width: 66,
                  height: 62,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: current == a
                        ? AppColors.accent.withValues(alpha: 0.18)
                        : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: current == a
                          ? AppColors.accent
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    a.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: current == a
                          ? AppColors.accent
                          : AppColors.textDim,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        AppSlider(
          label: 'Animation length',
          value: widget.duration.inMilliseconds / 1000,
          min: 0.1,
          max: 3,
          defaultValue: 0.5,
          format: (v) => '${v.toStringAsFixed(1)}s',
          onChanged: (v) =>
              widget.onDuration(Duration(milliseconds: (v * 1000).round())),
        ),
      ],
    );
  }
}
