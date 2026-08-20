import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/enums.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/tool_button.dart';

/// Every action the bottom bar can trigger. The editor screen owns the
/// behaviour; the toolbar only decides which actions are relevant right now.
enum ToolAction {
  addMedia,
  audio,
  text,
  sticker,
  overlay,
  filter,
  adjust,
  ratio,
  background,
  masterVolume,
  voiceOver,
  soundLibrary,
  textToSpeech,
  captions,
  // clip tools
  split,
  speed,
  volume,
  crop,
  rotate,
  mirror,
  reverse,
  freeze,
  transition,
  duration,
  duplicate,
  delete,
  replace,
  extractAudio,
  mask,
  chroma,
  keyframe,
  blend,
  stabilize,
  // layer tools
  editText,
  editSticker,
  editOverlay,
  editAudio,
  animation,
  splitLayer,
  duplicateLayer,
  deleteLayer,
}

class _Tool {
  const _Tool(this.action, this.icon, this.label, {this.danger = false});

  final ToolAction action;
  final IconData icon;
  final String label;
  final bool danger;
}

/// Contextual bottom toolbar: project tools when nothing is selected, and the
/// matching tool set for whatever the user picked.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.editor,
    required this.onAction,
  });

  final EditorController editor;
  final void Function(ToolAction) onAction;

  static const List<_Tool> _projectTools = [
    _Tool(ToolAction.addMedia, Icons.video_library_outlined, 'Media'),
    _Tool(ToolAction.soundLibrary, Icons.library_music_outlined, 'Audio'),
    _Tool(ToolAction.voiceOver, Icons.mic_none, 'Voice'),
    _Tool(ToolAction.textToSpeech, Icons.record_voice_over_outlined, 'TTS'),
    _Tool(ToolAction.captions, Icons.closed_caption_outlined, 'Captions'),
    _Tool(ToolAction.text, Icons.title, 'Text'),
    _Tool(ToolAction.sticker, Icons.emoji_emotions_outlined, 'Sticker'),
    _Tool(ToolAction.overlay, Icons.picture_in_picture_alt_outlined, 'Overlay'),
    _Tool(ToolAction.ratio, Icons.aspect_ratio, 'Canvas'),
    _Tool(ToolAction.background, Icons.wallpaper_outlined, 'Backdrop'),
    _Tool(ToolAction.masterVolume, Icons.graphic_eq, 'Mix'),
  ];

  static const List<_Tool> _clipTools = [
    _Tool(ToolAction.split, Icons.content_cut, 'Split'),
    _Tool(ToolAction.speed, Icons.speed, 'Speed'),
    _Tool(ToolAction.volume, Icons.volume_up_outlined, 'Volume'),
    _Tool(ToolAction.filter, Icons.auto_awesome, 'Filter'),
    _Tool(ToolAction.adjust, Icons.tune, 'Adjust'),
    _Tool(ToolAction.crop, Icons.crop, 'Crop'),
    _Tool(ToolAction.keyframe, Icons.diamond_outlined, 'Keyframe'),
    _Tool(ToolAction.mask, Icons.masks_outlined, 'Mask'),
    _Tool(ToolAction.chroma, Icons.color_lens_outlined, 'Chroma'),
    _Tool(ToolAction.stabilize, Icons.filter_center_focus, 'Stabilize'),
    _Tool(ToolAction.transition, Icons.compare_arrows, 'Transition'),
    _Tool(ToolAction.duration, Icons.timer_outlined, 'Duration'),
    _Tool(ToolAction.rotate, Icons.rotate_90_degrees_ccw, 'Rotate'),
    _Tool(ToolAction.mirror, Icons.flip, 'Mirror'),
    _Tool(ToolAction.reverse, Icons.fast_rewind, 'Reverse'),
    _Tool(ToolAction.freeze, Icons.ac_unit, 'Freeze'),
    _Tool(ToolAction.extractAudio, Icons.audio_file_outlined, 'Extract'),
    _Tool(ToolAction.replace, Icons.swap_horiz, 'Replace'),
    _Tool(ToolAction.duplicate, Icons.copy_outlined, 'Copy'),
    _Tool(ToolAction.delete, Icons.delete_outline, 'Delete', danger: true),
  ];

  static const List<_Tool> _textTools = [
    _Tool(ToolAction.editText, Icons.edit_outlined, 'Edit'),
    _Tool(ToolAction.animation, Icons.animation, 'Animate'),
    _Tool(ToolAction.keyframe, Icons.diamond_outlined, 'Keyframe'),
    _Tool(ToolAction.splitLayer, Icons.content_cut, 'Split'),
    _Tool(ToolAction.duplicateLayer, Icons.copy_outlined, 'Copy'),
    _Tool(ToolAction.deleteLayer, Icons.delete_outline, 'Delete', danger: true),
  ];

  static const List<_Tool> _stickerTools = [
    _Tool(ToolAction.editSticker, Icons.tune, 'Style'),
    _Tool(ToolAction.sticker, Icons.add_reaction_outlined, 'Add'),
    _Tool(ToolAction.animation, Icons.animation, 'Animate'),
    _Tool(ToolAction.keyframe, Icons.diamond_outlined, 'Keyframe'),
    _Tool(ToolAction.splitLayer, Icons.content_cut, 'Split'),
    _Tool(ToolAction.duplicateLayer, Icons.copy_outlined, 'Copy'),
    _Tool(ToolAction.deleteLayer, Icons.delete_outline, 'Delete', danger: true),
  ];

  static const List<_Tool> _overlayTools = [
    _Tool(ToolAction.editOverlay, Icons.tune, 'Adjust'),
    _Tool(ToolAction.animation, Icons.animation, 'Animate'),
    _Tool(ToolAction.keyframe, Icons.diamond_outlined, 'Keyframe'),
    _Tool(ToolAction.mask, Icons.masks_outlined, 'Mask'),
    _Tool(ToolAction.chroma, Icons.color_lens_outlined, 'Chroma'),
    _Tool(ToolAction.blend, Icons.layers_outlined, 'Blend'),
    _Tool(ToolAction.filter, Icons.auto_awesome, 'Filter'),
    _Tool(ToolAction.splitLayer, Icons.content_cut, 'Split'),
    _Tool(ToolAction.duplicateLayer, Icons.copy_outlined, 'Copy'),
    _Tool(ToolAction.deleteLayer, Icons.delete_outline, 'Delete', danger: true),
  ];

  static const List<_Tool> _audioTools = [
    _Tool(ToolAction.editAudio, Icons.tune, 'Mix'),
    _Tool(ToolAction.keyframe, Icons.diamond_outlined, 'Keyframe'),
    _Tool(ToolAction.splitLayer, Icons.content_cut, 'Split'),
    _Tool(ToolAction.duplicateLayer, Icons.copy_outlined, 'Copy'),
    _Tool(ToolAction.deleteLayer, Icons.delete_outline, 'Delete', danger: true),
  ];

  List<_Tool> get _tools => switch (editor.selection.kind) {
        LaneKind.video => _clipTools,
        LaneKind.text => _textTools,
        LaneKind.sticker => _stickerTools,
        LaneKind.overlay => _overlayTools,
        LaneKind.audio => _audioTools,
        _ => _projectTools,
      };

  String get _contextLabel => switch (editor.selection.kind) {
        LaneKind.video => 'Clip',
        LaneKind.text => 'Text',
        LaneKind.sticker => 'Sticker',
        LaneKind.overlay => 'Overlay',
        LaneKind.audio => 'Audio',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final selected = !editor.selection.isEmpty;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              SizedBox(
                height: 26,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.appBar.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_contextLabel,
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.appBarMuted)),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: editor.clearSelection,
                      style: TextButton.styleFrom(
                          minimumSize: const Size(0, 24),
                          padding: const EdgeInsets.symmetric(horizontal: 10)),
                      child: const Text('Done',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textDim)),
                    ),
                  ],
                ),
              ),
            SizedBox(
              // 6+6 padding + 34 icon + 4 gap + the 9.5pt label's line box; 62
              // clipped the label and drew the overflow stripe.
              height: 66,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: _tools.length,
                itemBuilder: (context, i) {
                  final tool = _tools[i];
                  return ToolButton(
                    icon: tool.icon,
                    label: tool.label,
                    accent: tool.danger ? AppColors.danger : null,
                    tint: tool.danger
                        ? AppColors.danger
                        : AppColors.appBarMuted,
                    selected: tool.danger,
                    onTap: () => onAction(tool.action),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
