import 'package:flutter/material.dart';

import '../../../data/models/adjustments.dart';
import '../../../data/models/layers.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_shell.dart';
import '../../widgets/app_slider.dart';

/// Manual colour adjustments — the same values the renderer folds into the
/// FFmpeg `eq` chain. Targets a clip or an overlay, like the effects sheet.
class AdjustPanel extends StatefulWidget {
  const AdjustPanel({
    super.key,
    required this.editor,
    required this.onClose,
    this.clipIndex,
    this.overlay,
  });

  final EditorController editor;
  final VoidCallback onClose;

  /// Exactly one of these is set.
  final int? clipIndex;
  final OverlayLayer? overlay;

  @override
  State<AdjustPanel> createState() => _AdjustPanelState();
}

class _AdjustPanelState extends State<AdjustPanel> {
  Adjustments get _adj =>
      widget.overlay?.adjustments ??
      widget.editor.project.clips[widget.clipIndex!].adjustments;

  /// Both targets hold an [Adjustments] of their own, so one mutator covers
  /// them once we know which object to hand it.
  void _apply(void Function(Adjustments) mutate, {bool record = true}) {
    final overlay = widget.overlay;
    if (overlay != null) {
      widget.editor.updateLayer<OverlayLayer>(
          overlay, (o) => mutate(o.adjustments),
          record: record);
    } else {
      widget.editor.updateClip(
          widget.clipIndex!, (c) => mutate(c.adjustments),
          record: record);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final adj = _adj;

    Widget slider(String label, IconData icon, double value,
            void Function(Adjustments, double) apply) =>
        AppSlider(
          label: label,
          icon: icon,
          value: value,
          min: -1,
          max: 1,
          bipolar: true,
          defaultValue: 0,
          format: (v) => (v * 100).round().toString(),
          onChanged: (v) => _apply((a) => apply(a, v), record: false),
          onChangeEnd: (v) => _apply((a) => apply(a, v)),
        );

    Widget unipolar(String label, IconData icon, double value,
            void Function(Adjustments, double) apply) =>
        AppSlider(
          label: label,
          icon: icon,
          value: value,
          min: 0,
          max: 1,
          defaultValue: 0,
          format: (v) => (v * 100).round().toString(),
          onChanged: (v) => _apply((a) => apply(a, v), record: false),
          onChangeEnd: (v) => _apply((a) => apply(a, v)),
        );

    return PanelShell(
      title: 'Adjust',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      onReset: () => _apply((a) => a.reset()),
      applyToAll: widget.overlay != null
          ? null
          : () {
              final copy = adj.copy();
              widget.editor.applyToAllClips((c) {
                c.adjustments = copy.copy();
              });
            },
      child: PanelBody(
        child: Column(
          children: [
            const SizedBox(height: 6),
            slider('Brightness', Icons.brightness_6, adj.brightness,
                (a, v) => a.brightness = v),
            slider('Contrast', Icons.contrast, adj.contrast,
                (a, v) => a.contrast = v),
            slider('Saturation', Icons.water_drop_outlined, adj.saturation,
                (a, v) => a.saturation = v),
            slider('Temperature', Icons.thermostat, adj.temperature,
                (a, v) => a.temperature = v),
            slider('Tint', Icons.colorize, adj.tint, (a, v) => a.tint = v),
            slider('Highlights', Icons.wb_sunny_outlined, adj.highlights,
                (a, v) => a.highlights = v),
            slider('Shadows', Icons.nightlight_outlined, adj.shadows,
                (a, v) => a.shadows = v),
            slider('Hue', Icons.palette_outlined, adj.hue, (a, v) => a.hue = v),
            const Divider(height: 18),
            slider('Curve Low', Icons.south, adj.curveLow,
                (a, v) => a.curveLow = v),
            slider('Curve Mid', Icons.horizontal_rule, adj.curveMid,
                (a, v) => a.curveMid = v),
            slider('Curve High', Icons.north, adj.curveHigh,
                (a, v) => a.curveHigh = v),
            const Divider(height: 18),
            unipolar('Sharpen', Icons.details, adj.sharpen,
                (a, v) => a.sharpen = v),
            unipolar('Vignette', Icons.vignette_outlined, adj.vignette,
                (a, v) => a.vignette = v),
            unipolar('Fade', Icons.gradient, adj.fade, (a, v) => a.fade = v),
            unipolar('Grain', Icons.grain, adj.grain, (a, v) => a.grain = v),
            unipolar('Blur', Icons.blur_circular, adj.blur,
                (a, v) => a.blur = v),
            unipolar('Denoise', Icons.cleaning_services_outlined,
                adj.denoise, (a, v) => a.denoise = v),
            const SizedBox(height: 10),
          ],
        ),
),
    );
  }
}
