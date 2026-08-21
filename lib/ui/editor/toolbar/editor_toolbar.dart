import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/models/enums.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/tool_button.dart';
import 'category_bar.dart';

/// Every action the bottom bar can trigger. The editor screen owns the
/// behaviour; the toolbar only decides which actions are relevant right now.
enum ToolAction {
  addMedia,
  audio,
  text,
  sticker,
  overlay,
  colorFilter,
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
  sort,
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

/// A tool that needs something on the main track to act on. Tools guarded by
/// this go grey on an empty project instead of answering a tap with a toast.
bool _needsClip(EditorController e) => e.project.clips.isNotEmpty;

/// Sorting and transitions are both about the join between two clips.
bool _needsTwoClips(EditorController e) => e.project.clips.length > 1;

class _Tool {
  const _Tool(this.action, this.icon, this.label,
      {this.danger = false, this.enabled});

  final ToolAction action;
  final IconData icon;
  final String label;
  final bool danger;

  /// When the tool can be used at all; null means always.
  final bool Function(EditorController)? enabled;
}

/// The strip of tools above the timeline.
///
/// What it shows is decided two ways: a selected text, sticker, overlay or
/// audio layer takes it over with that layer's own tools, and otherwise it
/// shows the set belonging to the [category] picked in the bar along the
/// bottom of the screen.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.editor,
    required this.onAction,
    this.category = ToolCategory.trim,
    this.axis = Axis.horizontal,
  });

  final EditorController editor;
  final void Function(ToolAction) onAction;

  /// Which family of tools the bottom bar is currently pointing at.
  final ToolCategory category;

  /// A strip above the timeline on phones and tablets; a filled rail down the
  /// side once the window is wide enough for the editor's two-column layout.
  final Axis axis;

  /// One row of buttons, measured rather than assumed — the editor needs the
  /// number to work out how much room is left for the preview.
  ///
  /// Two label lines are reserved: 'Change speed' is two words, and a large
  /// system font would otherwise cut it to 'Change spe…'.
  static double rowHeight(BuildContext context) {
    final r = context.r;
    // The label's line box has to be measured through the text scaler, not
    // just the app's own type scale — a large system font is what used to
    // push the row past its box.
    final label = MediaQuery.textScalerOf(context).scale(r.sp(9.5)) * 1.6;
    return r.vp(12) + r.dp(34) + r.vp(4) + label * 2;
  }

  /// The whole strip, including the context row shown while something is
  /// selected. The bottom inset belongs to [CategoryBar], which is the strip
  /// that actually meets the navigation bar.
  static double heightFor(BuildContext context, {required bool selected}) {
    return rowHeight(context) +
        (selected ? math.max(context.r.vp(26), 24) : 0);
  }

  // ------------------------------------------------------------ tool sets

  /// Trim: the six clip actions, and only those six.
  ///
  /// Everything else a clip can have done to it lives in the overflow menu
  /// on the context row — see [_moreTools] — so this row stays the one in
  /// the design: six buttons, evenly spread, nothing to scroll past.
  static const List<_Tool> _trimTools = [
    _Tool(ToolAction.split, Icons.content_cut, 'Split', enabled: _needsClip),
    _Tool(ToolAction.replace, Icons.swap_horiz, 'Replace', enabled: _needsClip),
    _Tool(ToolAction.delete, Icons.delete_outline, 'Delete',
        danger: true, enabled: _needsClip),
    _Tool(ToolAction.crop, Icons.crop, 'Crop', enabled: _needsClip),
    _Tool(ToolAction.speed, Icons.speed, 'Change speed', enabled: _needsClip),
    _Tool(ToolAction.sort, Icons.swap_vert, 'Sort', enabled: _needsTwoClips),
  ];

  /// The clip actions that are not one of the six. They hang off the '⋯' on
  /// the context row, which only shows once a clip is selected — every one of
  /// them acts on that clip.
  static const List<_Tool> _moreTools = [
    _Tool(ToolAction.duplicate, Icons.copy_outlined, 'Duplicate'),
    _Tool(ToolAction.duration, Icons.timer_outlined, 'Duration'),
    _Tool(ToolAction.transition, Icons.compare_arrows, 'Transition'),
    _Tool(ToolAction.rotate, Icons.rotate_90_degrees_ccw, 'Rotate'),
    _Tool(ToolAction.mirror, Icons.flip, 'Mirror'),
    _Tool(ToolAction.reverse, Icons.fast_rewind, 'Reverse'),
    _Tool(ToolAction.freeze, Icons.ac_unit, 'Freeze frame'),
  ];

  /// The sound library panel imports from the device itself, so there is no
  /// separate 'add a file' tool here.
  static const List<_Tool> _musicTools = [
    _Tool(ToolAction.soundLibrary, Icons.library_music_outlined, 'Audio'),
    _Tool(ToolAction.voiceOver, Icons.mic_none, 'Voice'),
    _Tool(ToolAction.textToSpeech, Icons.record_voice_over_outlined, 'TTS'),
    _Tool(ToolAction.extractAudio, Icons.audio_file_outlined, 'Extract',
        enabled: _needsClip),
    _Tool(ToolAction.volume, Icons.volume_up_outlined, 'Volume',
        enabled: _needsClip),
    _Tool(ToolAction.masterVolume, Icons.graphic_eq, 'Mix'),
  ];

  static const List<_Tool> _textCategoryTools = [
    _Tool(ToolAction.text, Icons.title, 'Text'),
    _Tool(ToolAction.captions, Icons.closed_caption_outlined, 'Captions'),
    _Tool(ToolAction.sticker, Icons.emoji_emotions_outlined, 'Sticker'),
  ];

  static const List<_Tool> _adjustTools = [
    _Tool(ToolAction.adjust, Icons.tune, 'Adjust'),
    _Tool(ToolAction.keyframe, Icons.diamond_outlined, 'Keyframe'),
    _Tool(ToolAction.mask, Icons.masks_outlined, 'Mask'),
    _Tool(ToolAction.chroma, Icons.color_lens_outlined, 'Chroma'),
    _Tool(ToolAction.stabilize, Icons.filter_center_focus, 'Stabilize',
        enabled: _needsClip),
  ];

  static const List<_Tool> _filterTools = [
    _Tool(ToolAction.colorFilter, Icons.filter_vintage_outlined, 'Filter'),
    _Tool(ToolAction.filter, Icons.auto_awesome, 'Effects'),
  ];

  static const List<_Tool> _frameTools = [
    _Tool(ToolAction.ratio, Icons.aspect_ratio, 'Canvas'),
    _Tool(ToolAction.background, Icons.wallpaper_outlined, 'Backdrop'),
    _Tool(ToolAction.overlay, Icons.picture_in_picture_alt_outlined,
        'Overlay'),
    _Tool(ToolAction.watermark, Icons.branding_watermark_outlined,
        'Watermark'),
  ];

  static const List<_Tool> _textLayerTools = [
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
    _Tool(ToolAction.colorFilter, Icons.filter_vintage_outlined, 'Filter'),
    _Tool(ToolAction.filter, Icons.auto_awesome, 'Effects'),
    // 'Adjust' is taken by the overlay's own transform tool above.
    _Tool(ToolAction.adjust, Icons.gradient, 'Color'),
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

  /// The tools a category shows. A clip on the main track is edited through
  /// whichever category is open — Trim being the one that carries the clip
  /// actions — so only the overlay lanes override the set.
  static List<_Tool> _toolsFor(ToolCategory category) => switch (category) {
    ToolCategory.trim => _trimTools,
    ToolCategory.music => _musicTools,
    ToolCategory.text => _textCategoryTools,
    ToolCategory.adjust => _adjustTools,
    ToolCategory.filter => _filterTools,
    ToolCategory.frame => _frameTools,
  };

  List<_Tool> get _tools => switch (editor.selection.kind) {
    LaneKind.text => _textLayerTools,
    LaneKind.sticker => _stickerTools,
    LaneKind.overlay => _overlayTools,
    LaneKind.audio => _audioTools,
    _ => _toolsFor(category),
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
      child: Column(
        mainAxisSize: vertical ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (selected) _contextRow(r),
          if (vertical)
            Expanded(child: _toolGrid(context, r))
          else
            SizedBox(
              // 6+6 padding + 34 icon + 4 gap + two 9.5pt label line boxes;
              // 62 clipped the label and drew the overflow stripe.
              height: rowHeight(context),
              child: _strip(context, r),
            ),
        ],
      ),
    );
  }

  /// A set that fits the width is spread evenly across it, the way the
  /// design draws the six clip actions. A longer one — the tools for a
  /// selected layer — scrolls instead of squeezing.
  Widget _strip(BuildContext context, Responsive r) {
    final tools = _tools;
    if (tools.length <= 6) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: r.dp(4)),
        child: Row(
          children: [for (final tool in tools) Expanded(child: _button(tool))],
        ),
      );
    }
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: r.dp(6)),
      itemCount: tools.length,
      itemBuilder: (context, i) => _button(tools[i]),
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
          if (editor.selection.isClip) _moreMenu(r),
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

  /// Everything a clip can have done to it that is not one of the six on the
  /// strip. It hangs off the context row so the strip itself stays the row in
  /// the design.
  Widget _moreMenu(Responsive r) {
    return PopupMenuButton<ToolAction>(
      tooltip: 'More clip tools',
      position: PopupMenuPosition.over,
      padding: EdgeInsets.zero,
      splashRadius: 16,
      icon: Icon(Icons.more_horiz,
          size: r.ic(17), color: AppColors.appBarMuted),
      constraints: const BoxConstraints(minWidth: 168),
      onSelected: onAction,
      itemBuilder: (context) => [
        for (final tool in _moreTools)
          PopupMenuItem<ToolAction>(
            value: tool.action,
            height: 38,
            child: Row(
              children: [
                // The menu paints on AppColors.appBar, so its icons take the
                // bar's own muted foreground — the page's would go black on
                // black.
                Icon(tool.icon, size: r.ic(16), color: AppColors.onAppBarDim),
                SizedBox(width: r.dp(10)),
                Text(tool.label, style: TextStyle(fontSize: r.sp(12.5))),
              ],
            ),
          ),
      ],
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
    final enabled = tool.enabled?.call(editor) ?? true;
    return ToolButton(
      icon: tool.icon,
      label: tool.label,
      width: width,
      maxLines: 2,
      enabled: enabled,
      accent: tool.danger ? AppColors.danger : null,
      tint: tool.danger ? AppColors.danger : AppColors.appBarMuted,
      selected: tool.danger,
      onTap: () => onAction(tool.action),
    );
  }
}
