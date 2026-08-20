import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/enums.dart';
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
    return Column(
      children: [
        ChipStrip(
          labels: const ['In', 'Out'],
          selectedIndex: _side,
          onSelected: (i) => setState(() => _side = i),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: LayerAnimation.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 9),
            itemBuilder: (context, i) {
              final a = LayerAnimation.values[i];
              final active = current == a;
              return GestureDetector(
                onTap: () => _side == 0 ? widget.onIn(a) : widget.onOut(a),
                child: Container(
                  width: 66,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.accent.withValues(alpha: 0.18)
                        : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: active ? AppColors.accent : Colors.transparent),
                  ),
                  child: Text(
                    a.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: active ? AppColors.accent : AppColors.textDim,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
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
