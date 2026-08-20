import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
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
  watermark,
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
    this.axis = Axis.horizontal,
  });

  final EditorController editor;
  final void Function(ToolAction) onAction;

  /// A strip along the bottom on phones and tablets; a filled rail down the
  /// side once the window is wide enough for the editor's two-column layout.
  final Axis axis;

  /// One row of buttons, measured rather than assumed — the editor needs the
  /// number to work out how much room is left for the preview.
  static double rowHeight(BuildContext context) {
    final r = context.r;
    // The label's line box has to be measured through the text scaler, not
    // just the app's own type scale — a large system font is what used to
    // push the row past its box.
    final label = MediaQuery.textScalerOf(context).scale(r.sp(9.5)) * 1.6;
    return r.vp(12) + r.dp(34) + r.vp(4) + label;
  }

  /// The whole strip, including the context row shown while something is
  /// selected and the bottom inset it sits above.
  static double heightFor(BuildContext context, {required bool selected}) {
    final r = context.r;
    return rowHeight(context) +
        (selected ? math.max(r.vp(26), 24) : 0) +
        r.viewPadding.bottom;
  }

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
    _Tool(ToolAction.watermark, Icons.branding_watermark_outlined,
        'Watermark'),
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
    final r = context.r;
    final vertical = axis == Axis.vertical;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: vertical
              ? BorderSide.none
              : const BorderSide(color: AppColors.divider),
          left: vertical
              ? const BorderSide(color: AppColors.divider)
              : BorderSide.none,
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: vertical ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (selected) _contextRow(r),
            if (vertical)
              Expanded(child: _toolGrid(context, r))
            else
              SizedBox(
                // 6+6 padding + 34 icon + 4 gap + the 9.5pt label's line box;
                // 62 clipped the label and drew the overflow stripe.
                height: rowHeight(context),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: r.dp(6)),
                  itemCount: _tools.length,
                  itemBuilder: (context, i) => _button(_tools[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _contextRow(Responsive r) {
    return SizedBox(
      height: math.max(r.vp(26), 24),
      child: Row(
        children: [
          SizedBox(width: r.dp(12)),
          Container(
            padding: EdgeInsets.symmetric(horizontal: r.dp(8), vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.appBar.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(_contextLabel,
                style: TextStyle(
                    fontSize: r.sp(10),
                    fontWeight: FontWeight.w700,
                    color: AppColors.appBarMuted)),
          ),
          const Spacer(),
          TextButton(
            onPressed: editor.clearSelection,
            style: TextButton.styleFrom(
                minimumSize: const Size(0, 24),
                padding: EdgeInsets.symmetric(horizontal: r.dp(10))),
            child: Text('Done',
                style:
                    TextStyle(fontSize: r.sp(11), color: AppColors.textDim)),
          ),
        ],
      ),
    );
  }

  /// The rail's layout: the same buttons, wrapped into as many columns as the
  /// rail is wide, scrolling when the list outgrows the window's height.
  Widget _toolGrid(BuildContext context, Responsive r) {
    final tile = r.dp(66);
    return GridView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: r.dp(6),
        vertical: r.vp(6),
      ),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: tile,
        mainAxisExtent: rowHeight(context),
        crossAxisSpacing: r.dp(2),
        mainAxisSpacing: r.vp(2),
      ),
      itemCount: _tools.length,
      itemBuilder: (context, i) => _button(_tools[i], width: 62),
    );
  }

  Widget _button(_Tool tool, {double? width}) {
    return ToolButton(
      icon: tool.icon,
      label: tool.label,
      width: width,
      accent: tool.danger ? AppColors.danger : null,
      tint: tool.danger ? AppColors.danger : AppColors.appBarMuted,
      selected: tool.danger,
      onTap: () => onAction(tool.action),
    );
  }
}
