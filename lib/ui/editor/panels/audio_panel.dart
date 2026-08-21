import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/duration_ext.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/layers.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_shell.dart';
import '../../widgets/app_slider.dart';

/// Level, fades and rate for one audio lane item.
class AudioPanel extends StatefulWidget {
  const AudioPanel({
    super.key,
    required this.editor,
    required this.layer,
    required this.onClose,
  });

  final EditorController editor;
  final AudioLayer layer;
  final VoidCallback onClose;

  @override
  State<AudioPanel> createState() => _AudioPanelState();
}

class _AudioPanelState extends State<AudioPanel> {
  void _update(void Function(AudioLayer) mutate, {bool record = true}) {
    widget.editor.updateLayer<AudioLayer>(widget.layer, mutate, record: record);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.layer;
    final maxFade = (l.duration.seconds / 2).clamp(0.1, 10.0);
    return PanelShell(
      title: l.title,
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      onReset: () => _update((a) {
        a.volume = 1;
        a.speed = 1;
        a.fadeIn = Duration.zero;
        a.fadeOut = Duration.zero;
      }),
      child: PanelBody(
        child: Column(
          children: [
            const SizedBox(height: 6),
            AppSlider(
              label: 'Volume',
              icon: Icons.volume_up,
              value: l.volume,
              min: 0,
              max: 2,
              defaultValue: 1,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => _update((a) => a.volume = v, record: false),
              onChangeEnd: (v) => _update((a) => a.volume = v),
            ),
            AppSlider(
              label: 'Fade in',
              icon: Icons.north_east,
              value: (l.fadeIn.seconds).clamp(0.0, maxFade).toDouble(),
              min: 0,
              max: maxFade,
              defaultValue: 0,
              format: (v) => '${v.toStringAsFixed(1)}s',
              onChanged: (v) =>
                  _update((a) => a.fadeIn = durationFromSeconds(v),
                      record: false),
              onChangeEnd: (v) =>
                  _update((a) => a.fadeIn = durationFromSeconds(v)),
            ),
            AppSlider(
              label: 'Fade out',
              icon: Icons.south_east,
              value: (l.fadeOut.seconds).clamp(0.0, maxFade).toDouble(),
              min: 0,
              max: maxFade,
              defaultValue: 0,
              format: (v) => '${v.toStringAsFixed(1)}s',
              onChanged: (v) =>
                  _update((a) => a.fadeOut = durationFromSeconds(v),
                      record: false),
              onChangeEnd: (v) =>
                  _update((a) => a.fadeOut = durationFromSeconds(v)),
            ),
            AppSlider(
              label: 'Speed',
              icon: Icons.speed,
              value: l.speed,
              min: 0.5,
              max: 2,
              defaultValue: 1,
              format: (v) => '${v.toStringAsFixed(2)}x',
              onChanged: (v) => _update((a) => a.speed = v, record: false),
              onChangeEnd: (v) => _update((a) => a.speed = v),
            ),
            AppSlider(
              label: 'Pitch',
              icon: Icons.tune,
              value: l.pitch,
              min: -12,
              max: 12,
              bipolar: true,
              divisions: 24,
              defaultValue: 0,
              format: (v) => '${v.round() > 0 ? '+' : ''}${v.round()} st',
              onChanged: (v) => _update((a) => a.pitch = v, record: false),
              onChangeEnd: (v) => _update((a) => a.pitch = v),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Voice changer',
                    style: TextStyle(fontSize: 11, color: AppColors.textDim)),
              ),
            ),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: VoiceEffect.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final fx = VoiceEffect.values[i];
                  final active = l.voiceEffect == fx;
                  return GestureDetector(
                    onTap: () => _update((a) => a.voiceEffect = fx),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color:
                            active ? AppColors.accent : AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(fx.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: active
                                ? AppColors.onAccent
                                : AppColors.textDim,
                          )),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
),
    );
  }
}

/// Master mix for the whole project.
class MasterVolumePanel extends StatefulWidget {
  const MasterVolumePanel({
    super.key,
    required this.editor,
    required this.onClose,
  });

  final EditorController editor;
  final VoidCallback onClose;

  @override
  State<MasterVolumePanel> createState() => _MasterVolumePanelState();
}

class _MasterVolumePanelState extends State<MasterVolumePanel> {
  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Master volume',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: AppSlider(
          label: 'All audio',
          icon: Icons.graphic_eq,
          value: widget.editor.project.masterVolume,
          min: 0,
          max: 2,
          defaultValue: 1,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) {
            widget.editor.setMasterVolume(v);
            setState(() {});
          },
        ),
      ),
    );
  }
}

/// Opacity, corner radius, chroma key and volume for a PIP layer.
class OverlayPanel extends StatefulWidget {
  const OverlayPanel({
    super.key,
    required this.editor,
    required this.layer,
    required this.onClose,
  });

  final EditorController editor;
  final OverlayLayer layer;
  final VoidCallback onClose;

  @override
  State<OverlayPanel> createState() => _OverlayPanelState();
}

class _OverlayPanelState extends State<OverlayPanel> {
  void _update(void Function(OverlayLayer) mutate, {bool record = true}) {
    widget.editor
        .updateLayer<OverlayLayer>(widget.layer, mutate, record: record);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.layer;
    return PanelShell(
      title: 'Overlay',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      child: PanelBody(
        child: Column(
          children: [
            const SizedBox(height: 6),
            AppSlider(
              label: 'Size',
              icon: Icons.photo_size_select_large,
              value: l.transform.scale,
              min: 0.05,
              max: 1.6,
              defaultValue: 0.5,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) =>
                  _update((o) => o.transform.scale = v, record: false),
              onChangeEnd: (v) => _update((o) => o.transform.scale = v),
            ),
            AppSlider(
              label: 'Opacity',
              icon: Icons.opacity,
              value: l.transform.opacity,
              min: 0,
              max: 1,
              defaultValue: 1,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) =>
                  _update((o) => o.transform.opacity = v, record: false),
              onChangeEnd: (v) => _update((o) => o.transform.opacity = v),
            ),
            AppSlider(
              label: 'Corner radius',
              icon: Icons.rounded_corner,
              value: l.cornerRadius,
              min: 0,
              max: 120,
              defaultValue: 0,
              format: (v) => v.round().toString(),
              onChanged: (v) =>
                  _update((o) => o.cornerRadius = v, record: false),
              onChangeEnd: (v) => _update((o) => o.cornerRadius = v),
            ),
            if (!l.isImage)
              AppSlider(
                label: 'Volume',
                icon: Icons.volume_up,
                value: l.volume,
                min: 0,
                max: 2,
                defaultValue: 1,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) => _update((o) => o.volume = v, record: false),
                onChangeEnd: (v) => _update((o) => o.volume = v),
              ),
            if (!l.isImage)
              AppSlider(
                label: 'Speed',
                icon: Icons.speed,
                value: l.speed,
                min: 0.25,
                max: 4,
                defaultValue: 1,
                format: (v) => '${v.toStringAsFixed(2)}x',
                onChanged: (v) => _update((o) => o.speed = v, record: false),
                onChangeEnd: (v) => _update((o) => o.speed = v),
              ),
          ],
        ),
),
    );
  }
}
