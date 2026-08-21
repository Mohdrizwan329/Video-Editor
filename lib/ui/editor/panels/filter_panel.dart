import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/filter_preset.dart';
import '../../../data/models/layers.dart';
import '../../../data/models/video_clip.dart';
import '../../../data/services/thumbnail_service.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_shell.dart';
import 'effects_panel.dart' show PresetTile, SwatchSource, hasTonalRange;

/// The one-tap grade picker, modelled on the phone gallery editor's Filter
/// tool: a single strip of the user's own frame graded every way the library
/// knows, applied the moment it is tapped. Tapping the tile that is already
/// on reveals its strength, so the common case — try looks until one fits —
/// never has to walk past a slider.
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
  });

  final EditorController editor;
  final VoidCallback onClose;

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

  /// Revealed by tapping the active tile a second time, the way the phone's
  /// filter row does it.
  bool _showStrength = false;

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

  @override
  void initState() {
    super.initState();
    _loadFrame();
  }

  @override
  void didUpdateWidget(FilterPanel old) {
    super.didUpdateWidget(old);
    if (old.clipIndex != widget.clipIndex ||
        old.overlay?.id != widget.overlay?.id) {
      _frame = null;
      _loadFrame();
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
          : clip!.sourcePositionFor(widget.editor.position.value -
              widget.editor.project.clipStart(widget.clipIndex!));
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
      widget.editor
          .updateLayer<OverlayLayer>(overlay, onOverlay, record: record);
    } else {
      widget.editor.updateClip(widget.clipIndex!, onClip, record: record);
    }
    setState(() {});
  }

  void _pick(FilterPreset preset) {
    if (preset.id == _filterId) {
      // Second tap on the look that is already on: the strength control is
      // what the user can still want from a tile they have already chosen.
      setState(() => _showStrength = preset.id != 'none' && !_showStrength);
      return;
    }
    _showStrength = false;
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
    final showSlider = _showStrength && active != 'none';

    // A tile is a square over its name, and that name's line box grows with
    // the system font — measured through the text scaler rather than assumed,
    // the way the toolbar measures its own row. Assumed, a large system font
    // overflows the strip by a hair and stripes it.
    const tile = 58.0;
    final stripHeight =
        tile + 4 + MediaQuery.textScalerOf(context).scale(9.5) * 1.6;

    return PanelShell(
      title: 'Filter',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      onReset: () => _apply(
        (c) {
          c.filterId = 'none';
          c.filterIntensity = 1;
        },
        (o) {
          o.filterId = 'none';
          o.filterIntensity = 1;
        },
      ),
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
      // The sheet is one height for every tool and scrolls the rest, so this
      // column is built to need no scrolling: the strip is what the user
      // came for, and a row they have to drag into view is a row they will
      // not find. That is why strength takes the category row's place rather
      // than sitting under the tiles — the two are never wanted at once, and
      // stacked they push the strip off the bottom. [_StrengthRow] is built
      // to the same height as the pills it stands in for, so the tiles do
      // not jump as the user turns a look up and down.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          if (showSlider)
            _StrengthRow(
              value: _intensity,
              onChanged: (v) => _setIntensity(v, record: false),
              onChangeEnd: _setIntensity,
            )
          else
            ChipStrip(
              labels: _categories,
              selectedIndex: _category,
              onSelected: (i) => setState(() => _category = i),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: stripHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final preset = items[i];
                return PresetTile(
                  size: tile,
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
          if (!showSlider)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                active == 'none'
                    ? 'Tap a look to apply it'
                    : 'Tap ${FilterPreset.fromId(active).name} again for '
                        'strength',
                style: const TextStyle(
                  fontSize: 9.5,
                  color: AppColors.textDim,
                ),
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}


/// Strength on one line — name, track and value — so it fits the row the
/// category pills leave behind. The panel-wide [AppSlider] stacks its label
/// over its track, which is the right shape for a sheet of many sliders and
/// the wrong one for a sheet with a single slider and no room to spare.
class _StrengthRow extends StatelessWidget {
  const _StrengthRow({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ChipStrip.kHeight,
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
