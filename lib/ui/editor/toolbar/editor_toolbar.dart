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
  opacity,
  voiceEffect,
  ease,
  enhance,
  cutout,
  aiCut,
  voiceEnhance,
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

/// A tool that grades or shapes *something* on the canvas. Both a main-track
/// clip and an overlay lane count, so these stay live on a project that is
/// nothing but a picture-in-picture.
bool _needsTarget(EditorController e) =>
    e.project.clips.isNotEmpty || e.project.overlays.isNotEmpty;

class _Tool {
  const _Tool(
    this.action,
    this.icon,
    this.label, {
    this.danger = false,
    this.enabled,
  });

  final ToolAction action;
  final IconData icon;
  final String label;
  final bool danger;

  /// When the tool can be used at all; null means always.
  final bool Function(EditorController)? enabled;
}

/// A hairline between the project tools and the clip tools, the way the
/// phone editors separate 'what this video has' from 'what this clip is'.
class _Divider extends _Tool {
  const _Divider() : super(ToolAction.addMedia, Icons.remove, '');
}

/// The strip of tools above the timeline.
///
/// One flat row, scrolled sideways — no families, no overflow menu. The
/// project tools come first and stay live on an empty project; the clip
/// tools follow a hairline and go grey until there is a clip to act on.
/// A selected text, sticker, overlay or audio layer takes the strip over
/// with that layer's own tools.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.editor,
    required this.onAction,
    this.axis = Axis.horizontal,
  });

  final EditorController editor;
  final void Function(ToolAction) onAction;

  /// A strip above the timeline on phones and tablets; a filled rail down the
  /// side once the window is wide enough for the editor's two-column layout.
  final Axis axis;

  /// One row of buttons, measured rather than assumed — the editor needs the
  /// number to work out how much room is left for the preview.
  ///
  /// Two label lines are reserved: 'Voice Enhance' is two words, and a large
  /// system font would otherwise cut it to 'Voice Enh…'.
  static double rowHeight(BuildContext context) {
    final r = context.r;
    final label = MediaQuery.textScalerOf(context).scale(r.sp(9.5)) * 1.6;
    return r.vp(12) + r.dp(34) + r.vp(4) + label * 2;
  }

  /// The whole strip. There is no context row any more — the flat bar carries
  /// every clip tool itself.
  static double heightFor(BuildContext context) => rowHeight(context);

  // ------------------------------------------------------------ tool sets

  /// The bar, in order.
  ///
  /// The first seven act on the project and are always live. Everything after
  /// the hairline acts on one clip, and follows the order a phone editor puts
  /// them in: the cuts first, then the sound, then the look, then the
  /// one-shot transforms.
  static const List<_Tool> _mainTools = [
    _Tool(ToolAction.ratio, Icons.aspect_ratio, 'Canvas'),
    _Tool(ToolAction.soundLibrary, Icons.music_note, 'Audio'),
    _Tool(ToolAction.sticker, Icons.emoji_emotions_outlined, 'Sticker'),
    _Tool(ToolAction.text, Icons.title, 'Text'),
    _Tool(ToolAction.filter, Icons.star, 'Effect'),
    _Tool(ToolAction.colorFilter, Icons.filter_vintage, 'Filter'),
    _Tool(ToolAction.overlay, Icons.picture_in_picture_alt, 'PIP'),
    _Divider(),
    _Tool(ToolAction.duration, Icons.schedule, 'Duration', enabled: _needsClip),
    _Tool(ToolAction.split, Icons.content_cut, 'Split', enabled: _needsClip),
    _Tool(
      ToolAction.delete,
      Icons.delete_outline,
      'Delete',
      danger: true,
      enabled: _needsClip,
    ),
    _Tool(ToolAction.volume, Icons.volume_up, 'Volume', enabled: _needsClip),
    _Tool(ToolAction.speed, Icons.speed, 'Speed', enabled: _needsClip),
    _Tool(
      ToolAction.animation,
      Icons.animation,
      'Animation',
      enabled: _needsClip,
    ),
    _Tool(ToolAction.aiCut, Icons.auto_fix_high, 'AI Cut', enabled: _needsClip),
    _Tool(
      ToolAction.voiceEnhance,
      Icons.settings_voice,
      'Voice Enhance',
      enabled: _needsClip,
    ),
    _Tool(ToolAction.crop, Icons.crop, 'Crop', enabled: _needsClip),
    _Tool(ToolAction.sort, Icons.shuffle, 'Switch', enabled: _needsTwoClips),
    _Tool(ToolAction.enhance, Icons.hd, 'Enhance', enabled: _needsClip),
    _Tool(
      ToolAction.cutout,
      Icons.person_outline,
      'Cutout',
      enabled: _needsClip,
    ),
    _Tool(
      ToolAction.stabilize,
      Icons.center_focus_strong,
      'Stabilizer',
      enabled: _needsClip,
    ),
    _Tool(ToolAction.mask, Icons.crop_square, 'Mask', enabled: _needsClip),
    _Tool(ToolAction.opacity, Icons.opacity, 'Opacity', enabled: _needsClip),
    _Tool(ToolAction.replace, Icons.swap_horiz, 'Replace', enabled: _needsClip),
    _Tool(
      ToolAction.voiceEffect,
      Icons.record_voice_over,
      'Voice Effect',
      enabled: _needsClip,
    ),
    _Tool(
      ToolAction.duplicate,
      Icons.content_copy,
      'Duplicate',
      enabled: _needsClip,
    ),
    _Tool(ToolAction.rotate, Icons.rotate_right, 'Rotate', enabled: _needsClip),
    _Tool(ToolAction.freeze, Icons.ac_unit, 'Freeze', enabled: _needsClip),
    _Tool(
      ToolAction.reverse,
      Icons.fast_rewind,
      'Reverse',
      enabled: _needsClip,
    ),
    _Tool(ToolAction.ease, Icons.show_chart, 'Ease', enabled: _needsClip),
    _Divider(),
    // Past the second hairline: the tools this editor has that the phone
    // editors keep somewhere other than the bar. They are last because the
    // bar's order up to here is the one the user already knows.
    _Tool(ToolAction.adjust, Icons.tune, 'Adjust', enabled: _needsTarget),
    _Tool(
      ToolAction.chroma,
      Icons.color_lens_outlined,
      'Chroma',
      enabled: _needsTarget,
    ),
    _Tool(
      ToolAction.keyframe,
      Icons.diamond_outlined,
      'Keyframe',
      enabled: _needsTarget,
    ),
    _Tool(
      ToolAction.transition,
      Icons.compare_arrows,
      'Transition',
      enabled: _needsTwoClips,
    ),
    _Tool(ToolAction.mirror, Icons.flip, 'Mirror', enabled: _needsClip),
    _Tool(ToolAction.background, Icons.wallpaper_outlined, 'Backdrop'),
    _Tool(ToolAction.watermark, Icons.branding_watermark_outlined, 'Watermark'),
    _Tool(ToolAction.captions, Icons.closed_caption_outlined, 'Captions'),
    _Tool(ToolAction.textToSpeech, Icons.record_voice_over_outlined, 'TTS'),
    _Tool(ToolAction.voiceOver, Icons.mic_none, 'Voice'),
    _Tool(
      ToolAction.extractAudio,
      Icons.audio_file_outlined,
      'Extract',
      enabled: _needsClip,
    ),
    _Tool(ToolAction.masterVolume, Icons.graphic_eq, 'Mix'),
  ];

  /// Every label on the main bar, in the order it is shown. Exposed so a test
  /// can walk the whole bar without keeping a second copy of the list that
  /// would quietly drift out of step with this one.
  static List<String> get mainToolLabels => [
    for (final tool in _mainTools)
      if (tool is! _Divider) tool.label,
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
    _Tool(ToolAction.mask, Icons.crop_square, 'Mask'),
    _Tool(ToolAction.chroma, Icons.color_lens_outlined, 'Chroma'),
    _Tool(ToolAction.blend, Icons.layers_outlined, 'Blend'),
    _Tool(ToolAction.colorFilter, Icons.filter_vintage, 'Filter'),
    _Tool(ToolAction.filter, Icons.star, 'Effects'),
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

  List<_Tool> get _tools => switch (editor.selection.kind) {
    LaneKind.text => _textLayerTools,
    LaneKind.sticker => _stickerTools,
    LaneKind.overlay => _overlayTools,
    LaneKind.audio => _audioTools,
    _ => _mainTools,
  };

  @override
  Widget build(BuildContext context) {
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
      child: vertical
          ? _toolGrid(context, r)
          : SizedBox(height: rowHeight(context), child: _strip(context, r)),
    );
  }

  /// One flat row, scrolled sideways. It is never squeezed to fit: the bar is
  /// thirty tools long, and a row that shrank them to fit the window would
  /// leave every icon too small to hit.
  Widget _strip(BuildContext context, Responsive r) {
    final tools = _tools;
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: r.dp(6)),
      itemCount: tools.length,
      itemBuilder: (context, i) => _button(context, tools[i]),
    );
  }

  /// The rail's layout: the same buttons, wrapped into as many columns as the
  /// rail is wide, scrolling when the list outgrows the window's height.
  Widget _toolGrid(BuildContext context, Responsive r) {
    final tools = _tools.where((t) => t is! _Divider).toList();
    final tile = r.dp(66);
    return GridView.builder(
      padding: EdgeInsets.symmetric(horizontal: r.dp(6), vertical: r.vp(6)),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: tile,
        mainAxisExtent: rowHeight(context),
        crossAxisSpacing: r.dp(2),
        mainAxisSpacing: r.vp(2),
      ),
      itemCount: tools.length,
      itemBuilder: (context, i) => _button(context, tools[i], width: 62),
    );
  }

  Widget _button(BuildContext context, _Tool tool, {double? width}) {
    if (tool is _Divider) {
      final r = context.r;
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: r.dp(6), vertical: r.vp(14)),
        child: const VerticalDivider(
          width: 1,
          thickness: 1,
          color: AppColors.divider,
        ),
      );
    }
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
