import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/duration_ext.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/models/enums.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_strip.dart';
import '../../widgets/app_slider.dart';
import '../../widgets/panel_shell.dart';

/// How solid the clip is over whatever is behind it on the canvas.
///
/// The same number drives the preview and the export, so a half-faded clip
/// looks the same in the player as it lands in the file.
class OpacityPanel extends StatelessWidget {
  const OpacityPanel({
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
      title: 'Opacity',
      onClose: onClose,
      onConfirm: onClose,
      onReset: () => editor.updateClip(index, (c) => c.opacity = 1),
      applyToAll: () => editor.applyToAllClips((c) => c.opacity = clip.opacity),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          AppSlider(
            label: 'Opacity',
            icon: Icons.opacity,
            value: clip.opacity,
            min: 0,
            max: 1,
            defaultValue: 1,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v) =>
                editor.updateClip(index, (c) => c.opacity = v, record: false),
            onChangeEnd: (v) => editor.updateClip(index, (c) => c.opacity = v),
          ),
        ],
      ),
    );
  }
}

/// The clip's in and out ramp — picture and sound together, which is what
/// makes it read as an ease rather than a separate video and audio fade.
class EasePanel extends StatelessWidget {
  const EasePanel({
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
    // An ease longer than the clip would never finish, so the sliders stop
    // at half its length — the point where in and out meet in the middle.
    final maxSeconds = (clip.timelineDuration.inMilliseconds / 2000).clamp(
      0.1,
      5.0,
    );
    return PanelShell(
      title: 'Ease',
      onClose: onClose,
      onConfirm: onClose,
      onReset: () => editor.updateClip(index, (c) {
        c.fadeIn = Duration.zero;
        c.fadeOut = Duration.zero;
      }),
      applyToAll: () => editor.applyToAllClips((c) {
        c.fadeIn = clip.fadeIn;
        c.fadeOut = clip.fadeOut;
      }),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          AppSlider(
            label: 'Ease in',
            icon: Icons.north_east,
            value: (clip.fadeIn.inMilliseconds / 1000).clamp(0.0, maxSeconds),
            min: 0,
            max: maxSeconds,
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
            label: 'Ease out',
            icon: Icons.south_east,
            value: (clip.fadeOut.inMilliseconds / 1000).clamp(0.0, maxSeconds),
            min: 0,
            max: maxSeconds,
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
        ],
      ),
    );
  }
}

/// Pitch and timbre on the clip's own audio, plus the one-tap voice clean-up.
///
/// Both are export-time filters — there is no way to run them through the
/// platform player — so the panel says so rather than letting the user hunt
/// for a change in the preview that will not come.
class VoiceEffectPanel extends StatelessWidget {
  const VoiceEffectPanel({
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
    final r = context.r;
    final clip = editor.project.clips[index];
    return PanelShell(
      title: 'Voice Effect',
      onClose: onClose,
      onConfirm: onClose,
      onReset: () => editor.updateClip(index, (c) {
        c.voiceEffect = VoiceEffect.none;
        c.voiceEnhance = false;
      }),
      applyToAll: () => editor.applyToAllClips((c) {
        c.voiceEffect = clip.voiceEffect;
        c.voiceEnhance = clip.voiceEnhance;
      }),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelStrip(
            gap: r.dp(8),
            runGap: r.dp(8),
            padding: EdgeInsets.symmetric(horizontal: r.dp(4)),
            children: [
              for (final fx in VoiceEffect.values)
                GestureDetector(
                  onTap: () =>
                      editor.updateClip(index, (c) => c.voiceEffect = fx),
                  child: Container(
                    width: r.dp(66),
                    height: r.dp(62),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: clip.voiceEffect == fx
                          ? AppColors.accent
                          : AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      fx.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: r.sp(11),
                        fontWeight: FontWeight.w600,
                        color: clip.voiceEffect == fx
                            ? AppColors.onAccent
                            : AppColors.text,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: r.vp(8)),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.symmetric(horizontal: r.dp(12)),
            dense: true,
            value: clip.voiceEnhance,
            title: Text(
              'Voice Enhance',
              style: TextStyle(
                fontSize: r.sp(13),
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            subtitle: Text(
              'Cuts rumble and hiss, then evens the level',
              style: TextStyle(fontSize: r.sp(11), color: AppColors.textDim),
            ),
            onChanged: (v) =>
                editor.updateClip(index, (c) => c.voiceEnhance = v),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(r.dp(12), 0, r.dp(12), r.vp(6)),
            child: Text(
              'Heard in the exported file — the preview player cannot run '
              'these filters live.',
              style: TextStyle(
                fontSize: r.sp(10.5),
                color: AppColors.textFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Knocking the background out from behind the person in a clip.
///
/// Two ways in, the way the phone editors offer them: the model, which finds
/// a person without being told anything, and the colour key, which is what a
/// green screen wants. The model's pass has to be baked — it cannot run
/// inside a filter graph or a preview player — so this says what state the
/// clip is in rather than pretending the result is already on screen.
class CutoutPanel extends StatelessWidget {
  const CutoutPanel({
    super.key,
    required this.editor,
    required this.index,
    required this.onClose,
    required this.onRunCutout,
    required this.onChroma,
  });

  final EditorController editor;
  final int index;
  final VoidCallback onClose;

  /// Runs — or, on a clip that already has a matte, clears — the model pass.
  final VoidCallback onRunCutout;

  /// Switches the sheet to the colour key.
  final VoidCallback onChroma;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final clip = editor.project.clips[index];
    final on = clip.hasCutout;
    return PanelShell(
      title: 'Cutout',
      onClose: onClose,
      onConfirm: onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(
            icon: on ? Icons.check_circle : Icons.person_outline,
            title: on ? 'Subject cut out' : 'Cut out the subject',
            subtitle: on
                ? 'Tap to put the background back'
                : 'Finds the person and drops what is behind them',
            selected: on,
            onTap: onRunCutout,
          ),
          SizedBox(height: r.vp(6)),
          _Row(
            icon: Icons.color_lens_outlined,
            title: 'Chroma key',
            subtitle: 'Pick a colour to knock out — for a green screen',
            selected: clip.chromaKeyColor != null,
            onTap: onChroma,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(r.dp(12), r.vp(8), r.dp(12), r.vp(6)),
            child: Text(
              on
                  ? 'The cut-out background shows in the exported file. The '
                        'preview player cannot composite it live.'
                  : 'The pass runs once over the clip and is kept with the '
                        'project, so it costs its time only the first time.',
              style: TextStyle(
                fontSize: r.sp(10.5),
                color: AppColors.textFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: r.dp(12)),
        padding: EdgeInsets.all(r.dp(12)),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.10)
              : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: r.ic(22),
              color: selected ? AppColors.accent : AppColors.appBarMuted,
            ),
            SizedBox(width: r.dp(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: r.sp(13),
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: r.sp(11),
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
