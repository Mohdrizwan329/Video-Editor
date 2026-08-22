import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/filter_preset.dart';
import '../../../data/models/layers.dart';
import '../../../data/models/video_clip.dart';
import '../../../data/services/thumbnail_service.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_shell.dart';
import 'color_tool_tabs.dart';
import 'effects_panel.dart' show PresetTile, SwatchSource, hasTonalRange;

/// The one-tap grade picker, laid out the way the phone editors lay theirs
/// out: strength, then a strip of the user's own frame graded every way the
/// library knows, then the packs, then the tab bar onto the two sibling
/// colour tools.
///
/// A look goes on the moment its tile is tapped, and its strength is on
/// screen from that moment too — the row it lives in is held open by the
/// prompt beforehand, so picking a look never shunts the strip up the sheet.
/// The strip opens on whatever look the clip is already wearing.
///
/// The effects sheet still carries the same grades under its Color tab
/// alongside frames, FX and templates. This is the shortcut, not a rival:
/// both write [VideoClip.filterId] and [OverlayLayer.filterId].
class FilterPanel extends StatefulWidget {
  const FilterPanel({
    super.key,
    required this.editor,
    required this.onClose,
    this.clipIndex,
    this.overlay,
    this.onTool,
  });

  final EditorController editor;
  final VoidCallback onClose;

  /// Switches the sheet to one of the other two colour tools. Null leaves the
  /// tab bar off, for a caller that has nowhere to switch to.
  final ValueChanged<ColorTool>? onTool;

  /// Exactly one of these is set.
  final int? clipIndex;
  final OverlayLayer? overlay;

  @override
  State<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<FilterPanel> {
  /// 'All' plus the library's own groups, with 'None' dropped — the original
  /// is pinned to the head of every row instead of hiding in a tab of one.
  static final List<String> _categories = [
    'All',
    ...FilterLibrary.categories.where((c) => c != 'None'),
  ];

  int _category = 0;

  /// The strip's own scroll, so the look a clip already carries can be put
  /// on screen rather than left somewhere down a row of a hundred tiles.
  final ScrollController _strip = ScrollController();

  /// The frame under the playhead, graded live behind every tile. Null until
  /// it lands, and left null for footage too flat to grade — there the tiles
  /// fall back to the reference gradient rather than showing one colour
  /// sixty-seven times.
  String? _frame;

  VideoClip? get _clip => widget.clipIndex == null
      ? null
      : widget.editor.project.clips[widget.clipIndex!];

  String get _filterId => widget.overlay?.filterId ?? _clip!.filterId;

  double get _intensity =>
      widget.overlay?.filterIntensity ?? _clip!.filterIntensity;

  List<FilterPreset> get _items {
    if (_category == 0) return FilterLibrary.all;
    return [
      FilterLibrary.none,
      ...FilterLibrary.byCategory(_categories[_category]),
    ];
  }

  /// Edge of a tile, and the gap after it. The strip scrolls by these, so
  /// they are shared with the builder rather than written out twice.
  static const double _tile = 58;
  static const double _gap = 10;
  static const double _stripPad = 14;

  @override
  void initState() {
    super.initState();
    _loadFrame();
    // After the first layout, so the strip has a viewport to centre against.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
  }

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  /// Brings the live look into view. Opening the tool on a clip that is
  /// already graded and showing the head of the library instead reads as
  /// 'nothing is applied' — in a library this size the applied tile is
  /// usually well off the right edge.
  void _revealActive({int tries = 8}) {
    if (!mounted) return;
    // The sheet animates in, so the first frame after initState can land
    // before the strip has a viewport to measure. Wait for the frame that
    // gives it one rather than giving up on the first miss.
    if (!_strip.hasClients || !_strip.position.hasContentDimensions) {
      if (tries <= 0) return;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _revealActive(tries: tries - 1),
      );
      return;
    }
    final i = _items.indexWhere((f) => f.id == _filterId);
    if (i < 0) return;
    final viewport = _strip.position.viewportDimension;
    final width = PresetTile.widthFor(_tile);
    final centre = _stripPad + i * (width + _gap) + width / 2 - viewport / 2;
    _strip.jumpTo(centre.clamp(0.0, _strip.position.maxScrollExtent));
  }

  @override
  void didUpdateWidget(FilterPanel old) {
    super.didUpdateWidget(old);
    if (old.clipIndex != widget.clipIndex ||
        old.overlay?.id != widget.overlay?.id) {
      _frame = null;
      _loadFrame();
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
    }
  }

  /// Pull the frame the user is actually looking at. Matching the preview
  /// matters more here than anywhere else in the app: the tile is a promise
  /// about what the picture behind it will become.
  Future<void> _loadFrame() async {
    final overlay = widget.overlay;
    final clip = _clip;
    final path = overlay?.path ?? clip?.path;
    if (path == null) return;

    String? candidate;
    if (overlay?.isImage ?? clip?.isImage ?? false) {
      candidate = path;
    } else {
      final at = overlay != null
          ? overlay.trimStart
          : clip!.sourcePositionFor(
              widget.editor.position.value -
                  widget.editor.project.clipStart(widget.clipIndex!),
            );
      candidate = await ThumbnailService.instance.frame(path, at, height: 128);
      // A decode can fail on a seek past the last keyframe; the strip the
      // timeline already has is a better fallback than a gradient.
      final ready = clip?.thumbnailPath;
      if (candidate == null && ready != null && File(ready).existsSync()) {
        candidate = ready;
      }
    }
    if (candidate == null || !mounted) return;
    final usable = await hasTonalRange(candidate);
    if (mounted && usable) setState(() => _frame = candidate);
  }

  /// One writer for both targets — a clip and an overlay hold the same two
  /// fields, so only the object they live on differs.
  void _apply(
    void Function(VideoClip) onClip,
    void Function(OverlayLayer) onOverlay, {
    bool record = true,
  }) {
    final overlay = widget.overlay;
    if (overlay != null) {
      widget.editor.updateLayer<OverlayLayer>(
        overlay,
        onOverlay,
        record: record,
      );
    } else {
      widget.editor.updateClip(widget.clipIndex!, onClip, record: record);
    }
    setState(() {});
  }

  void _pick(FilterPreset preset) {
    // Re-tapping the look that is already on does nothing: its strength is
    // already on screen, which is the only thing left to want from it.
    if (preset.id == _filterId) return;
    _apply(
      (c) {
        c.filterId = preset.id;
        c.filterIntensity = 1;
      },
      (o) {
        o.filterId = preset.id;
        o.filterIntensity = 1;
      },
    );
  }

  void _setIntensity(double v, {bool record = true}) => _apply(
    (c) => c.filterIntensity = v,
    (o) => o.filterIntensity = v,
    record: record,
  );

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final active = _filterId;

    // A tile is a square over its name, and that name's line box grows with
    // the system font — measured through the text scaler rather than assumed,
    // the way the toolbar measures its own row. Assumed, a large system font
    // overflows the strip by a hair and stripes it.
    final stripHeight =
        _tile + 4 + MediaQuery.textScalerOf(context).scale(9.5) * 1.6;

    return PanelShell(
      title: 'Filter',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      // No reset icon: the head of the strip is 'Original', which is the
      // same thing and is already under the user's thumb.
      // A grade is per-clip, so spreading it over the timeline is the way to
      // get the phone's one-video behaviour on a multi-clip project.
      applyToAll: widget.overlay != null
          ? null
          : () {
              final id = _filterId;
              final intensity = _intensity;
              widget.editor.applyToAllClips((c) {
                c.filterId = id;
                c.filterIntensity = intensity;
              });
            },
      // The order is the one a phone's filter tool uses, top to bottom: which
      // of the two colour tools, how strong, which look, then which pack.
      // The pill leads because it is the switch between the looks and the
      // sliders, and strength follows because it belongs to the look already
      // applied — the thing the user is looking at. Strength keeps a fixed
      // row whether or not there is a look to fade, so picking one never
      // shunts the strip up the sheet.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          ColorToolPill(current: ColorTool.filter, onSelected: widget.onTool),
          const SizedBox(height: 6),
          SizedBox(
            height: _StrengthRow.kHeight,
            child: active == 'none'
                ? const _Hint('Tap a look to apply it')
                : _StrengthRow(
                    value: _intensity,
                    onChanged: (v) => _setIntensity(v, record: false),
                    onChangeEnd: _setIntensity,
                  ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: stripHeight,
            child: ListView.separated(
              controller: _strip,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: _stripPad),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: _gap),
              itemBuilder: (context, i) {
                final preset = items[i];
                return PresetTile(
                  size: _tile,
                  label: preset.id == 'none' ? 'Original' : preset.name,
                  active: preset.id == active,
                  onTap: () => _pick(preset),
                  child: ColorFiltered(
                    colorFilter: ColorFilter.matrix(preset.toColorMatrix()),
                    child: SwatchSource(path: _frame),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          TextTabStrip(
            labels: _categories,
            selectedIndex: _category,
            onSelected: (i) {
              setState(() => _category = i);
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _revealActive(),
              );
            },
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// The line the strength row stands in when there is no look to fade.
class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(fontSize: 10.5, color: AppColors.textDim),
      ),
    );
  }
}

/// Strength on one line — name, track and value.
///
/// The panel-wide [AppSlider] stacks its label over its track, which is the
/// right shape for a sheet of many sliders and the wrong one for a sheet
/// whose single slider has one row to live in.
class _StrengthRow extends StatelessWidget {
  const _StrengthRow({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  /// Also the height of the hint that stands in for this row, so the strip
  /// below sits at the same y whether or not a look is on.
  static const double kHeight = 30;

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kHeight,
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Text(
            'Strength',
            style: TextStyle(fontSize: 10.5, color: AppColors.textDim),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: value,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '${(value * 100).round()}%',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10.5, color: AppColors.text),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}
