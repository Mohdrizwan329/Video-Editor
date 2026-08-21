import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/duration_ext.dart';
import '../../../data/models/keyframe.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_shell.dart';
import '../../widgets/app_slider.dart';

/// Keyframe editor: step between keys, drop or remove one at the playhead,
/// and scrub the value of each animatable property.
class KeyframePanel extends StatefulWidget {
  const KeyframePanel({
    super.key,
    required this.editor,
    required this.onClose,
  });

  final EditorController editor;
  final VoidCallback onClose;

  @override
  State<KeyframePanel> createState() => _KeyframePanelState();
}

class _KeyframePanelState extends State<KeyframePanel> {
  EditorController get _e => widget.editor;

  /// Range and formatting per property, so one slider serves them all.
  static (double, double, String Function(double)) _spec(KeyframeProperty p) =>
      switch (p) {
        KeyframeProperty.x => (-1, 1, (v) => v.toStringAsFixed(2)),
        KeyframeProperty.y => (-1, 1, (v) => v.toStringAsFixed(2)),
        KeyframeProperty.scale => (0.05, 4, (v) => '${(v * 100).round()}%'),
        KeyframeProperty.rotation =>
          (-3.2, 3.2, (v) => '${(v * 57.2958).round()}°'),
        KeyframeProperty.opacity => (0, 1, (v) => '${(v * 100).round()}%'),
        KeyframeProperty.volume => (0, 2, (v) => '${(v * 100).round()}%'),
        KeyframeProperty.filterIntensity =>
          (0, 1, (v) => '${(v * 100).round()}%'),
        KeyframeProperty.cornerRadius => (0, 120, (v) => v.round().toString()),
        KeyframeProperty.blurAmount => (0, 40, (v) => v.round().toString()),
      };

  @override
  Widget build(BuildContext context) {
    final target = _e.keyframeTarget;
    if (target == null) {
      return PanelShell(
        title: 'Keyframes',
        onClose: widget.onClose,
        onConfirm: widget.onClose,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Text('Select a clip or layer first',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textDim)),
        ),
      );
    }

    final (owner, local) = target;
    final onKey = _e.hasKeyframeAtPlayhead;
    final props = _e.availableProperties;

    return PanelShell(
      title: 'Keyframes',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      onReset: owner.hasKeyframes
          ? () {
              _e.clearKeyframes();
              setState(() {});
            }
          : null,
      child: PanelBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _transport(owner, local, onKey),
            const Divider(height: 12),
            // Plain rows: the sheet is one height for every tool and scrolls,
            // so a list of its own here would only fight that scroll.
            for (final p in props) _propertyRow(owner, local, p),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _transport(Keyframable owner, Duration local, bool onKey) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.skip_previous, size: 20),
            color: AppColors.textDim,
            onPressed: () {
              _e.stepKeyframe(forward: false);
              setState(() {});
            },
          ),
          GestureDetector(
            onTap: () {
              if (onKey) {
                _e.removeKeyframeAtPlayhead();
              } else {
                _e.addKeyframeAtPlayhead();
              }
              setState(() {});
            },
            child: Container(
              width: 44,
              height: 36,
              decoration: BoxDecoration(
                color: onKey
                    ? AppColors.accent
                    : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Transform.rotate(
                angle: 0.785,
                child: Icon(onKey ? Icons.close : Icons.square,
                    size: onKey ? 15 : 13,
                    color: onKey ? AppColors.onAccent : AppColors.accent),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next, size: 20),
            color: AppColors.textDim,
            onPressed: () {
              _e.stepKeyframe(forward: true);
              setState(() {});
            },
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${owner.keyframeTimes.length} keys',
                  style: const TextStyle(
                      fontSize: 10.5, color: AppColors.textFaint)),
              Text(local.isNegative ? '—' : local.timecode,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textDim,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _propertyRow(Keyframable owner, Duration local, KeyframeProperty p) {
    final (min, max, format) = _spec(p);
    final track = owner.keyframes[p];
    final active = track != null && track.isNotEmpty;
    final value = active
        ? track.valueAt(local, _e.currentValueOf(p))
        : _e.currentValueOf(p);

    return Row(
      children: [
        Expanded(
          child: AppSlider(
            label: p.label,
            value: value.clamp(min, max),
            min: min,
            max: max,
            format: format,
            onChanged: (v) {
              _e.setKeyframe(p, v, record: false);
              setState(() {});
            },
            onChangeEnd: (v) {
              _e.setKeyframe(p, v);
              setState(() {});
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 10, top: 12),
          child: GestureDetector(
            onTap: () {
              _e.addKeyframeAtPlayhead(only: p);
              setState(() {});
            },
            child: Transform.rotate(
              angle: 0.785,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: active ? AppColors.accent : Colors.transparent,
                  border: Border.all(
                      color: active ? AppColors.accent : AppColors.textFaint,
                      width: 1.4),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
