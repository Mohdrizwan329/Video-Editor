import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/enums.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_shell.dart';
import '../../widgets/app_slider.dart';

/// Canvas aspect ratio picker.
class RatioPanel extends StatelessWidget {
  const RatioPanel({super.key, required this.editor, required this.onClose});

  final EditorController editor;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final current = editor.project.ratio;
    return PanelShell(
      title: 'Canvas',
      onClose: onClose,
      onConfirm: onClose,
      child: SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          itemCount: CanvasRatio.values.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final r = CanvasRatio.values[i];
            final active = r == current;
            final aspect = r.value ?? 9 / 16;
            return GestureDetector(
              onTap: () => editor.setRatio(r),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 52,
                    height: 44,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: aspect,
                        child: Container(
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.accent.withValues(alpha: 0.2)
                                : AppColors.surfaceHigh,
                            border: Border.all(
                              color: active
                                  ? AppColors.accent
                                  : AppColors.clipBorder,
                              width: active ? 1.8 : 1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(r.label,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color:
                              active ? AppColors.accent : AppColors.textDim)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// What fills the canvas behind a letterboxed clip.
class BackgroundPanel extends StatelessWidget {
  const BackgroundPanel({
    super.key,
    required this.editor,
    required this.onClose,
  });

  final EditorController editor;
  final VoidCallback onClose;

  static const List<int> _swatches = [
    0xFF000000, 0xFFFFFFFF, 0xFF141417, 0xFF2E2E38,
    0xFFE86A5C, 0xFFF2B33D, 0xFF31E1B4, 0xFF2BB8E1,
    0xFF6B5BD2, 0xFFE85C9E, 0xFF3A6B4A, 0xFF8A5A2B,
  ];

  static const List<(int, int)> _gradients = [
    (0xFF232526, 0xFF414345),
    (0xFF0F2027, 0xFF2C5364),
    (0xFF42275A, 0xFF734B6D),
    (0xFFDD5E89, 0xFFF7BB97),
    (0xFF1F4037, 0xFF99F2C8),
    (0xFF3A1C71, 0xFFD76D77),
  ];

  @override
  Widget build(BuildContext context) {
    final bg = editor.project.background;
    return PanelShell(
      title: 'Background',
      onClose: onClose,
      onConfirm: onClose,
      child: PanelBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            ChipStrip(
              labels: const ['Color', 'Blur', 'Gradient'],
              selectedIndex: BackgroundType.values.indexOf(bg.type),
              onSelected: (i) => editor
                  .setBackground((b) => b.type = BackgroundType.values[i]),
            ),
            const SizedBox(height: 12),
            if (bg.type == BackgroundType.color)
              _swatchGrid(
                _swatches.map((c) => (c, c)).toList(),
                selected: bg.color,
                onTap: (c) => editor.setBackground((b) => b.color = c),
              ),
            if (bg.type == BackgroundType.gradient)
              _gradientGrid(bg.gradientStart, bg.gradientEnd),
            if (bg.type == BackgroundType.blur)
              AppSlider(
                label: 'Blur amount',
                icon: Icons.blur_on,
                value: bg.blurAmount,
                min: 2,
                max: 60,
                defaultValue: 18,
                format: (v) => v.round().toString(),
                onChanged: (v) =>
                    editor.setBackground((b) => b.blurAmount = v),
              ),
            const SizedBox(height: 12),
          ],
        ),
),
    );
  }

  Widget _swatchGrid(List<(int, int)> colors,
      {required int selected, required ValueChanged<int> onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final (color, _) in colors)
            GestureDetector(
              onTap: () => onTap(color),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Color(color),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected == color
                        ? AppColors.accent
                        : AppColors.divider,
                    width: selected == color ? 2.4 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _gradientGrid(int start, int end) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final (a, b) in _gradients)
            GestureDetector(
              onTap: () => editor.setBackground((bg) {
                bg.gradientStart = a;
                bg.gradientEnd = b;
              }),
              child: Container(
                width: 52,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(a), Color(b)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (start == a && end == b)
                        ? AppColors.accent
                        : AppColors.divider,
                    width: (start == a && end == b) ? 2.4 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Transition picker for one clip boundary, grouped the way the library is.
class TransitionPanel extends StatefulWidget {
  const TransitionPanel({
    super.key,
    required this.editor,
    required this.index,
    required this.onClose,
    this.onPreview,
  });

  final EditorController editor;
  final int index;
  final VoidCallback onClose;

  /// Puts the playhead back in the middle of the join. Every pick and every
  /// length change moves that join, so the canvas needs re-parking or the
  /// transition stops showing after the first tap.
  final VoidCallback? onPreview;

  @override
  State<TransitionPanel> createState() => _TransitionPanelState();
}

class _TransitionPanelState extends State<TransitionPanel> {
  int _category = 0;

  EditorController get editor => widget.editor;
  int get index => widget.index;

  @override
  Widget build(BuildContext context) {
    final clip = editor.project.clips[index];
    final maxSeconds = _maxDuration().clamp(0.2, 3.0);
    final items = [
      if (_category == 0) TransitionType.none,
      ...TransitionType.byCategory(TransitionType.categories[_category])
          .where((t) => t != TransitionType.none),
    ];
    return PanelShell(
      title: 'Transition',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      applyToAll: () => editor.applyToAllClips((c) {
        c.transitionType = clip.transitionType;
        c.transitionDuration = clip.transitionDuration;
      }),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ChipStrip(
            labels: TransitionType.categories,
            selectedIndex: _category,
            onSelected: (i) => setState(() => _category = i),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final t = items[i];
                final active = clip.transitionType == t;
                return GestureDetector(
                  onTap: () {
                    editor.setTransition(index, t, clip.transitionDuration);
                    widget.onPreview?.call();
                  },
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.accent.withValues(alpha: 0.18)
                              : AppColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color:
                                active ? AppColors.accent : Colors.transparent,
                            width: 1.6,
                          ),
                        ),
                        child: Icon(t.icon,
                            size: 19,
                            color: active
                                ? AppColors.accent
                                : AppColors.textDim),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 52,
                        child: Text(t.label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 9,
                                color: active
                                    ? AppColors.accent
                                    : AppColors.textDim)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (clip.transitionType != TransitionType.none)
            AppSlider(
              label: 'Duration',
              value: (clip.transitionDuration.inMilliseconds / 1000)
                  .clamp(0.2, maxSeconds),
              min: 0.2,
              max: maxSeconds,
              format: (v) => '${v.toStringAsFixed(1)}s',
              onChanged: (v) => editor.setTransition(index, clip.transitionType,
                  Duration(milliseconds: (v * 1000).round())),
              onChangeEnd: (_) => widget.onPreview?.call(),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  /// A transition may not eat more than half of the shorter neighbour.
  double _maxDuration() {
    final clips = editor.project.clips;
    if (index + 1 >= clips.length) return 1;
    final a = clips[index].timelineDuration.inMilliseconds;
    final b = clips[index + 1].timelineDuration.inMilliseconds;
    return (a < b ? a : b) / 2000;
  }
}
