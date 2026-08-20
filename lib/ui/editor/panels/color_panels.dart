import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/adjustments.dart';
import '../../../data/models/filter_preset.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_shell.dart';
import '../../widgets/app_slider.dart';

/// Filter picker: category chips over a strip of graded swatches, plus the
/// intensity slider shown once a look is applied.
class FilterPanel extends StatefulWidget {
  const FilterPanel({
    super.key,
    required this.editor,
    required this.index,
    required this.onClose,
  });

  final EditorController editor;
  final int index;
  final VoidCallback onClose;

  @override
  State<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<FilterPanel> {
  int _category = 0;

  @override
  Widget build(BuildContext context) {
    final clip = widget.editor.project.clips[widget.index];
    final categories = FilterLibrary.categories;
    final filters = _category == 0
        ? FilterLibrary.all
        : FilterLibrary.byCategory(categories[_category]);

    return PanelShell(
      title: 'Filters',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      onReset: () => widget.editor.updateClip(widget.index, (c) {
        c.filterId = 'none';
        c.filterIntensity = 1;
      }),
      applyToAll: () => widget.editor.applyToAllClips((c) {
        c.filterId = clip.filterId;
        c.filterIntensity = clip.filterIntensity;
      }),
      child: Column(
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
            height: 74,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 9),
              itemBuilder: (context, i) {
                final f = filters[i];
                final active = clip.filterId == f.id;
                return GestureDetector(
                  onTap: () => widget.editor.updateClip(widget.index, (c) {
                    c.filterId = f.id;
                    c.filterIntensity = 1;
                  }),
                  child: Column(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color:
                                active ? AppColors.accent : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: ColorFiltered(
                            colorFilter: ColorFilter.matrix(f.toColorMatrix()),
                            child: const _SwatchGradient(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 54,
                        child: Text(
                          f.name,
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
              },
            ),
          ),
          if (clip.filterId != 'none')
            AppSlider(
              label: 'Intensity',
              value: clip.filterIntensity,
              min: 0,
              max: 1,
              defaultValue: 1,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => widget.editor.updateClip(
                  widget.index, (c) => c.filterIntensity = v,
                  record: false),
              onChangeEnd: (v) => widget.editor
                  .updateClip(widget.index, (c) => c.filterIntensity = v),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Reference gradient the filter swatches are graded from.
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
            Color(0xFFFFD9A0),
            Color(0xFFE86A5C),
            Color(0xFF4A5FA8),
            Color(0xFF102030),
          ],
          stops: [0, 0.35, 0.7, 1],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

/// Manual colour adjustments — the same values the renderer folds into the
/// FFmpeg `eq` chain.
class AdjustPanel extends StatelessWidget {
  const AdjustPanel({
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
    final adj = clip.adjustments;

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
          onChanged: (v) => editor.updateClip(index, (c) => apply(c.adjustments, v),
              record: false),
          onChangeEnd: (v) =>
              editor.updateClip(index, (c) => apply(c.adjustments, v)),
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
          onChanged: (v) => editor
              .updateClip(index, (c) => apply(c.adjustments, v), record: false),
          onChangeEnd: (v) =>
              editor.updateClip(index, (c) => apply(c.adjustments, v)),
        );

    return PanelShell(
      title: 'Adjust',
      onClose: onClose,
      onConfirm: onClose,
      onReset: () => editor.updateClip(index, (c) => c.adjustments.reset()),
      applyToAll: () => editor.applyToAllClips((c) {
        c.adjustments = adj.copy();
      }),
      child: SizedBox(
        height: 268,
        child: SingleChildScrollView(
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
              AppSlider(
                label: 'Sharpen',
                icon: Icons.details,
                value: adj.sharpen,
                min: 0,
                max: 1,
                defaultValue: 0,
                format: (v) => (v * 100).round().toString(),
                onChanged: (v) => editor.updateClip(
                    index, (c) => c.adjustments.sharpen = v,
                    record: false),
                onChangeEnd: (v) =>
                    editor.updateClip(index, (c) => c.adjustments.sharpen = v),
              ),
              AppSlider(
                label: 'Vignette',
                icon: Icons.vignette_outlined,
                value: adj.vignette,
                min: 0,
                max: 1,
                defaultValue: 0,
                format: (v) => (v * 100).round().toString(),
                onChanged: (v) => editor.updateClip(
                    index, (c) => c.adjustments.vignette = v,
                    record: false),
                onChangeEnd: (v) =>
                    editor.updateClip(index, (c) => c.adjustments.vignette = v),
              ),
              AppSlider(
                label: 'Fade',
                icon: Icons.gradient,
                value: adj.fade,
                min: 0,
                max: 1,
                defaultValue: 0,
                format: (v) => (v * 100).round().toString(),
                onChanged: (v) =>
                    editor.updateClip(index, (c) => c.adjustments.fade = v,
                        record: false),
                onChangeEnd: (v) =>
                    editor.updateClip(index, (c) => c.adjustments.fade = v),
              ),
              unipolar('Grain', Icons.grain, adj.grain, (a, v) => a.grain = v),
              unipolar('Blur', Icons.blur_circular, adj.blur,
                  (a, v) => a.blur = v),
              unipolar('Denoise', Icons.cleaning_services_outlined,
                  adj.denoise, (a, v) => a.denoise = v),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
