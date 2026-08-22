import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/duration_ext.dart';
import '../../../data/models/filter_preset.dart';
import '../../../data/models/layers.dart';
import '../../../data/models/template.dart';
import '../../../data/models/template_library.dart';
import '../../../data/models/video_clip.dart';
import '../../../data/models/video_effect.dart';
import '../../../data/services/thumbnail_service.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/app_slider.dart';
import '../../widgets/panel_shell.dart';
import 'color_tool_tabs.dart';
import '../preview/effects_view.dart';
import 'sticker_panel.dart';

/// The effects sheet: colour grades, design frames, FX textures, emoji and
/// templates behind one set of tabs.
///
/// Colour lives on the selected clip or overlay, the frame and the FX texture
/// are project-wide (they wrap the finished picture, the way the watermark
/// does), and emoji and templates act on the timeline.
class EffectsPanel extends StatefulWidget {
  const EffectsPanel({
    super.key,
    required this.editor,
    required this.onClose,
    this.clipIndex,
    this.overlay,
    this.onTool,
  });

  final EditorController editor;
  final VoidCallback onClose;

  /// Switches the sheet to one of the other two colour tools. Null leaves
  /// the tab bar off.
  final ValueChanged<ColorTool>? onTool;

  /// Exactly one of these is set — the colour tab's target.
  final int? clipIndex;
  final OverlayLayer? overlay;

  @override
  State<EffectsPanel> createState() => _EffectsPanelState();
}

enum _Tab { color, design, fx, emoji, template }

extension on _Tab {
  String get label => switch (this) {
        _Tab.color => 'Color',
        _Tab.design => 'Design',
        _Tab.fx => 'FX',
        _Tab.emoji => 'Emoji',
        _Tab.template => 'Template',
      };
}

class _EffectsPanelState extends State<EffectsPanel> {
  _Tab _tab = _Tab.color;

  /// A frame of the user's own footage, used as the swatch source. Null while
  /// it loads, and deliberately left null for footage too flat to grade.
  String? _swatch;

  VideoClip? get _clip => widget.clipIndex == null
      ? null
      : widget.editor.project.clips[widget.clipIndex!];

  String get _filterId => widget.overlay?.filterId ?? _clip!.filterId;

  double get _filterIntensity =>
      widget.overlay?.filterIntensity ?? _clip!.filterIntensity;

  List<_Tab> get _tabs => [
        _Tab.color,
        _Tab.design,
        _Tab.fx,
        _Tab.emoji,
        // A template re-cuts the main track, which an overlay selection has
        // no business doing.
        if (widget.overlay == null) _Tab.template,
      ];

  @override
  void initState() {
    super.initState();
    _loadSwatch();
  }

  @override
  void didUpdateWidget(EffectsPanel old) {
    super.didUpdateWidget(old);
    if (old.clipIndex != widget.clipIndex ||
        old.overlay?.id != widget.overlay?.id) {
      _swatch = null;
      _loadSwatch();
    }
  }

  /// Grading the user's own frame beats grading a stock gradient — they can
  /// see what a look does to their footage before committing to it. Footage
  /// with no tonal range to speak of is the exception: a solid colour card
  /// grades to the same swatch under every preset, so the picker would look
  /// broken. There we fall back to the reference gradient.
  Future<void> _loadSwatch() async {
    final overlay = widget.overlay;
    final clip = _clip;
    final path = overlay?.path ?? clip?.path;
    if (path == null) return;

    String? candidate;
    if (overlay?.isImage ?? clip?.isImage ?? false) {
      candidate = path;
    } else {
      // The timeline already pulled a frame for most clips; reuse it rather
      // than paying for a second FFmpeg call.
      final ready = clip?.thumbnailPath;
      if (ready != null && File(ready).existsSync()) {
        candidate = ready;
      } else {
        final at = overlay != null
            ? overlay.trimStart
            : clip!.trimStart + (clip.trimEnd - clip.trimStart) ~/ 2;
        candidate =
            await ThumbnailService.instance.frame(path, at, height: 96);
      }
    }
    if (candidate == null || !mounted) return;
    final usable = await hasTonalRange(candidate);
    if (mounted && usable) setState(() => _swatch = candidate);
  }

  /// One writer for both colour targets keeps the tab free of branching.
  void _applyColor(
    void Function(VideoClip) onClip,
    void Function(OverlayLayer) onOverlay, {
    bool record = true,
  }) {
    final overlay = widget.overlay;
    if (overlay != null) {
      widget.editor
          .updateLayer<OverlayLayer>(overlay, onOverlay, record: record);
    } else {
      widget.editor.updateClip(widget.clipIndex!, onClip, record: record);
    }
    setState(() {});
  }

  void _editProject(void Function() change, {bool record = true}) {
    widget.editor.edit(change, record: record);
    setState(() {});
  }

  VoidCallback? get _onReset => switch (_tab) {
        _Tab.color => () => _applyColor(
              (c) {
                c.filterId = 'none';
                c.filterIntensity = 1;
              },
              (o) {
                o.filterId = 'none';
                o.filterIntensity = 1;
              },
            ),
        _Tab.design => () =>
            _editProject(() => widget.editor.project.frameId = 'none'),
        _Tab.fx => () => _editProject(() {
              widget.editor.project
                ..fxId = 'none'
                ..fxIntensity = 1;
            }),
        _Tab.emoji || _Tab.template => null,
      };

  /// Only a colour grade has an "every clip" to spread to: the frame and the
  /// FX already cover the whole project, and an overlay is a lane of one.
  VoidCallback? get _onApplyToAll {
    if (_tab != _Tab.color || widget.overlay != null) return null;
    return () {
      final id = _filterId;
      final intensity = _filterIntensity;
      widget.editor.applyToAllClips((c) {
        c.filterId = id;
        c.filterIntensity = intensity;
      });
    };
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Effects',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      onReset: _onReset,
      applyToAll: _onApplyToAll,
      footer: ColorToolTabs(
        current: ColorTool.effect,
        onSelected: widget.onTool,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TabBar(
            tabs: _tabs,
            selected: _tab,
            onSelected: (t) => setState(() => _tab = t),
          ),
          const Divider(height: 1),
          switch (_tab) {
            _Tab.color => _colorTab(),
            _Tab.design => _designTab(),
            _Tab.fx => _fxTab(),
            _Tab.emoji => _EmojiTab(editor: widget.editor),
            _Tab.template => _TemplateTab(editor: widget.editor),
          },
        ],
      ),
    );
  }

  // -------------------------------------------------------------- color tab

  Widget _colorTab() {
    return _PresetTab(
      categories: FilterLibrary.categories,
      itemsFor: (c) => c == 'None'
          ? FilterLibrary.all
          : FilterLibrary.byCategory(c),
      allItems: FilterLibrary.all,
      idOf: (f) => (f as FilterPreset).id,
      nameOf: (f) => (f as FilterPreset).name,
      activeId: _filterId,
      onPick: (f) => _applyColor(
        (c) {
          c.filterId = (f as FilterPreset).id;
          c.filterIntensity = 1;
        },
        (o) {
          o.filterId = (f as FilterPreset).id;
          o.filterIntensity = 1;
        },
      ),
      preview: (f) => ColorFiltered(
        colorFilter: ColorFilter.matrix((f as FilterPreset).toColorMatrix()),
        child: SwatchSource(path: _swatch),
      ),
      slider: _filterId == 'none'
          ? null
          : AppSlider(
              label: 'Intensity',
              value: _filterIntensity,
              min: 0,
              max: 1,
              defaultValue: 1,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => _applyColor(
                (c) => c.filterIntensity = v,
                (o) => o.filterIntensity = v,
                record: false,
              ),
              onChangeEnd: (v) => _applyColor(
                (c) => c.filterIntensity = v,
                (o) => o.filterIntensity = v,
              ),
            ),
    );
  }

  // ------------------------------------------------------------- design tab

  Widget _designTab() {
    final project = widget.editor.project;
    return _PresetTab(
      note: 'Frames wrap the whole video',
      categories: FrameLibrary.categories,
      itemsFor: (c) =>
          c == 'None' ? FrameLibrary.all : FrameLibrary.byCategory(c),
      allItems: FrameLibrary.all,
      idOf: (f) => (f as FramePreset).id,
      nameOf: (f) => (f as FramePreset).name,
      activeId: project.frameId,
      onPick: (f) =>
          _editProject(() => project.frameId = (f as FramePreset).id),
      preview: (f) => Stack(
        fit: StackFit.expand,
        children: [
          SwatchSource(path: _swatch),
          FrameView(preset: f as FramePreset),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- fx tab

  Widget _fxTab() {
    final project = widget.editor.project;
    return _PresetTab(
      note: 'Textures cover the whole video',
      categories: FxLibrary.categories,
      itemsFor: (c) => c == 'None' ? FxLibrary.all : FxLibrary.byCategory(c),
      allItems: FxLibrary.all,
      idOf: (f) => (f as FxPreset).id,
      nameOf: (f) => (f as FxPreset).name,
      activeId: project.fxId,
      onPick: (f) => _editProject(() {
        project
          ..fxId = (f as FxPreset).id
          ..fxIntensity = 1;
      }),
      preview: (f) => Stack(
        fit: StackFit.expand,
        children: [
          SwatchSource(path: _swatch),
          FxSwatch(preset: f as FxPreset),
        ],
      ),
      slider: project.fxId == 'none'
          ? null
          : AppSlider(
              label: 'Intensity',
              value: project.fxIntensity,
              min: 0,
              max: 1,
              defaultValue: 1,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) =>
                  _editProject(() => project.fxIntensity = v, record: false),
              onChangeEnd: (v) => _editProject(() => project.fxIntensity = v),
            ),
    );
  }
}

/// Underlined tabs across the top of the sheet. Deliberately not the pill
/// [ChipStrip] the tabs' own category rows use, so the two rows never read as
/// one long list of chips.
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<_Tab> tabs;
  final _Tab selected;
  final ValueChanged<_Tab> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: tabs.length,
        itemBuilder: (context, i) {
          final tab = tabs[i];
          final active = tab == selected;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelected(tab),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: active ? AppColors.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                tab.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? AppColors.accent : AppColors.textDim,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The shape the colour, design and FX tabs all share: category pills over a
/// strip of live previews, with an optional intensity slider underneath.
class _PresetTab extends StatefulWidget {
  const _PresetTab({
    required this.categories,
    required this.itemsFor,
    required this.allItems,
    required this.idOf,
    required this.nameOf,
    required this.activeId,
    required this.onPick,
    required this.preview,
    this.slider,
    this.note,
  });

  final List<String> categories;
  final List<Object> Function(String category) itemsFor;
  final List<Object> allItems;
  final String Function(Object) idOf;
  final String Function(Object) nameOf;
  final String activeId;
  final void Function(Object) onPick;
  final Widget Function(Object) preview;
  final Widget? slider;
  final String? note;

  @override
  State<_PresetTab> createState() => _PresetTabState();
}

class _PresetTabState extends State<_PresetTab> {
  int _category = 0;

  @override
  Widget build(BuildContext context) {
    final items = _category == 0
        ? widget.allItems
        : widget.itemsFor(widget.categories[_category]);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        ChipStrip(
          labels: widget.categories,
          selectedIndex: _category,
          onSelected: (i) => setState(() => _category = i),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 74,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 9),
            itemBuilder: (context, i) {
              final item = items[i];
              return PresetTile(
                label: widget.nameOf(item),
                active: widget.idOf(item) == widget.activeId,
                onTap: () => widget.onPick(item),
                child: widget.preview(item),
              );
            },
          ),
        ),
        ?widget.slider,
        if (widget.note != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.note!,
              style: const TextStyle(fontSize: 9.5, color: AppColors.textDim),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// One preset in a strip: a live 50pt preview with its name underneath.
class PresetTile extends StatelessWidget {
  const PresetTile({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    required this.child,
    this.size = 50,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Widget child;

  /// Edge of the square preview. The filter strip runs larger than the tabs
  /// inside the effects sheet, where the tile has to share the row.
  final double size;

  /// The extra the name box takes over the square above it.
  static const double _labelSlack = 4;

  /// How wide a tile of [size] actually lays out. The name under the square
  /// is given a little more room than the square itself, so a strip that
  /// scrolls by tile — see FilterPanel — has to ask rather than assume.
  static double widthFor(double size) => size + _labelSlack;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: active ? AppColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: child,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: size + _labelSlack,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                color: active ? AppColors.accent : AppColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The swatch's ungraded source: the clip's own frame once we have one, and
/// a reference gradient until then — or for good, when the footage is too
/// flat for one grade to look different from the next.
class SwatchSource extends StatelessWidget {
  const SwatchSource({super.key, this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final p = path;
    if (p == null) return const _SwatchGradient();
    return Image.file(
      File(p),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const _SwatchGradient(),
    );
  }
}

/// Reference gradient the swatches fall back to. It spans shadow, skin tone,
/// saturated colour and highlight on purpose: those are the ranges the looks
/// pull apart, so every preset lands somewhere different on it.
class _SwatchGradient extends StatelessWidget {
  const _SwatchGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF6E4),
            Color(0xFFF0C08A),
            Color(0xFFE86A5C),
            Color(0xFF4A5FA8),
            Color(0xFF14202E),
          ],
          stops: [0, 0.24, 0.5, 0.76, 1],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

/// The sticker catalogue, reachable without leaving the effects sheet.
class _EmojiTab extends StatefulWidget {
  const _EmojiTab({required this.editor});

  final EditorController editor;

  @override
  State<_EmojiTab> createState() => _EmojiTabState();
}

class _EmojiTabState extends State<_EmojiTab> {
  int _pack = 0;

  @override
  Widget build(BuildContext context) {
    final isShapes = StickerCatalog.isShapes(_pack);
    return SizedBox(
      // The grid scrolls inside the sheet, so it takes the body less the tab
      // bar above it — any taller and its last row would hang below the sheet.
      height: PanelShell.bodyHeight(context) - 41,
      child: Column(
        children: [
          const SizedBox(height: 8),
          ChipStrip(
            labels: StickerCatalog.packNames,
            selectedIndex: _pack,
            onSelected: (i) => setState(() => _pack = i),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: StickerCatalog.countIn(_pack),
              itemBuilder: (context, i) {
                if (isShapes) {
                  final (key, icon) = StickerCatalog.shapes[i];
                  return _cell(
                    child: Icon(icon, size: 24, color: AppColors.text),
                    onTap: () =>
                        widget.editor.addSticker(key, isEmoji: false),
                  );
                }
                final emoji = StickerCatalog.packs[_pack]![i];
                return _cell(
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  onTap: () => widget.editor.addSticker(emoji),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell({required Widget child, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// Re-cut the clips already on the track to a template's pacing.
class _TemplateTab extends StatefulWidget {
  const _TemplateTab({required this.editor});

  final EditorController editor;

  @override
  State<_TemplateTab> createState() => _TemplateTabState();
}

class _TemplateTabState extends State<_TemplateTab> {
  int _category = 0;

  Future<void> _pick(VideoTemplate template) async {
    final clips = widget.editor.project.clips.length;
    if (clips == 0) return;
    // This rebuilds the timeline and drops the text and sticker layers, so it
    // asks first even though a single undo takes it all back.
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(template.name),
        content: Text(
          'Re-cut your $clips ${clips == 1 ? 'clip' : 'clips'} to this '
          'template. Text and stickers already on the timeline are replaced '
          "by the template's own. You can undo this.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await widget.editor.applyTemplateToCurrentMedia(template);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = TemplateLibrary.categories;
    final templates = TemplateLibrary.byCategory(categories[_category]);
    final empty = widget.editor.project.clips.isEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        ChipStrip(
          labels: categories,
          selectedIndex: _category,
          onSelected: (i) => setState(() => _category = i),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: templates.length,
            separatorBuilder: (_, _) => const SizedBox(width: 9),
            itemBuilder: (context, i) {
              final t = templates[i];
              return Opacity(
                opacity: empty ? 0.4 : 1,
                child: GestureDetector(
                  onTap: empty ? null : () => _pick(t),
                  child: Container(
                    width: 132,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${t.slots.length} cuts · '
                          '${t.approximateDuration.mmss}',
                          style: const TextStyle(
                              fontSize: 9.5, color: AppColors.textDim),
                        ),
                        const Spacer(),
                        Text(
                          t.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 9.5, color: AppColors.textDim),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            empty
                ? 'Add clips first'
                : 'Re-cuts the clips already on the track',
            style: const TextStyle(fontSize: 9.5, color: AppColors.textDim),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// True when [path] holds enough light-to-dark spread for colour grades to
/// land differently on it. A solid-colour card or a black slate does not, and
/// grading one produces a row of identical swatches.
Future<bool> hasTonalRange(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: 32, targetHeight: 32);
    final frame = await codec.getNextFrame();
    final data =
        await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return true;

    final px = data.buffer.asUint8List();
    var lo = 255.0, hi = 0.0, sum = 0.0, sumSq = 0.0, n = 0.0;
    for (var i = 0; i + 3 < px.length; i += 4) {
      final l = 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2];
      if (l < lo) lo = l;
      if (l > hi) hi = l;
      sum += l;
      sumSq += l * l;
      n++;
    }
    if (n == 0) return true;
    final mean = sum / n;
    final sd = math.sqrt(math.max(0, sumSq / n - mean * mean));
    return hi - lo > 36 && sd > 10;
  } catch (_) {
    // An unreadable frame is not a flat one; let the caller use it and let
    // Image.file's own error path deal with it.
    return true;
  }
}
