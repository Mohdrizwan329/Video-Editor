import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The labelled slider used by every property panel: value bubble on the
/// right, optional centre detent, and a tap-to-reset title.
class AppSlider extends StatelessWidget {
  const AppSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.divisions,
    this.format,
    this.defaultValue,
    this.bipolar = false,
    this.icon,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final int? divisions;
  final String Function(double)? format;

  /// Double-tapping the label snaps back to this.
  final double? defaultValue;

  /// Draws the fill from the centre instead of the left edge.
  final bool bipolar;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = format?.call(value) ?? value.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: AppColors.textDim),
                const SizedBox(width: 6),
              ],
              GestureDetector(
                onDoubleTap: defaultValue == null
                    ? null
                    : () {
                        onChanged(defaultValue!);
                        onChangeEnd?.call(defaultValue!);
                      },
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textDim,
                        fontWeight: FontWeight.w500)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(text,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.text,
                        fontFeatures: [FontFeature.tabularFigures()],
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackShape: bipolar ? const _CenterTrackShape() : null,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

/// Track that fills outward from the middle — right for adjustment sliders
/// where 0 sits in the centre.
class _CenterTrackShape extends RoundedRectSliderTrackShape {
  const _CenterTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final canvas = context.canvas;
    final inactive = Paint()..color = sliderTheme.inactiveTrackColor!;
    final active = Paint()..color = sliderTheme.activeTrackColor!;
    final radius = Radius.circular(rect.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), inactive);
    final centre = rect.center.dx;
    final left = thumbCenter.dx < centre ? thumbCenter.dx : centre;
    final right = thumbCenter.dx < centre ? centre : thumbCenter.dx;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(left, rect.top, right, rect.bottom), radius),
      active,
    );
  }
}
