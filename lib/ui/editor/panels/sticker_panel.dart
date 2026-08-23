import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/layers.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_strip.dart';
import '../../widgets/panel_shell.dart';
import '../../widgets/app_slider.dart';
import 'animation_panel.dart';

/// The emoji packs and vector shapes on offer. Kept apart from the panel so
/// the Effects sheet can show the very same catalogue in its Emoji tab.
class StickerCatalog {
  StickerCatalog._();

  static const List<String> packNames = [
    'Faces',
    'Love',
    'Hands',
    'Party',
    'Nature',
    'Signs',
    'Shapes',
  ];

  static const Map<int, List<String>> packs = {
    0: [
      '😀',
      '😂',
      '🥹',
      '😍',
      '😎',
      '🤩',
      '😭',
      '😡',
      '🤔',
      '🥳',
      '😴',
      '🤯',
      '😱',
      '🙃',
      '😇',
      '🤗',
    ],
    1: [
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '💖',
      '💘',
      '💝',
      '💕',
      '💞',
      '😻',
      '💐',
      '🌹',
    ],
    2: [
      '👍',
      '👎',
      '👏',
      '🙌',
      '🤝',
      '✌️',
      '🤟',
      '👊',
      '🙏',
      '💪',
      '👋',
      '🫶',
      '☝️',
      '🤙',
      '👌',
      '✍️',
    ],
    3: [
      '🎉',
      '🎊',
      '🥂',
      '🍾',
      '🎈',
      '🎁',
      '🎂',
      '🍰',
      '🪅',
      '✨',
      '🌟',
      '💫',
      '🔥',
      '⚡',
      '🎵',
      '🎶',
    ],
    4: [
      '🌸',
      '🌺',
      '🌻',
      '🌴',
      '🌊',
      '🏔️',
      '☀️',
      '🌙',
      '⭐',
      '☁️',
      '🌈',
      '❄️',
      '🍁',
      '🦋',
      '🐝',
      '🌵',
    ],
    5: [
      '✅',
      '❌',
      '⚠️',
      '❗',
      '❓',
      '💯',
      '🔝',
      '🆕',
      '🔴',
      '🟢',
      '🔵',
      '⏰',
      '📍',
      '🎯',
      '🚀',
      '💡',
    ],
  };

  static const List<(String, IconData)> shapes = [
    ('circle', Icons.circle),
    ('ring', Icons.circle_outlined),
    ('square', Icons.square),
    ('triangle', Icons.change_history),
    ('star', Icons.star),
    ('heart', Icons.favorite),
    ('arrow', Icons.arrow_forward),
    ('bubble', Icons.chat_bubble),
  ];

  /// The shapes pack is the last chip; everything before it is emoji.
  static bool isShapes(int pack) => pack == packNames.length - 1;

  static int countIn(int pack) =>
      isShapes(pack) ? shapes.length : (packs[pack]?.length ?? 0);
}

/// Sticker library: emoji packs and vector shapes, with colour and size for
/// the shapes.
class StickerPickerPanel extends StatefulWidget {
  const StickerPickerPanel({
    super.key,
    required this.editor,
    required this.onClose,
  });

  final EditorController editor;
  final VoidCallback onClose;

  @override
  State<StickerPickerPanel> createState() => _StickerPickerPanelState();
}

class _StickerPickerPanelState extends State<StickerPickerPanel> {
  int _pack = 0;

  @override
  Widget build(BuildContext context) {
    final isShapes = StickerCatalog.isShapes(_pack);
    return PanelShell(
      title: 'Stickers',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      child: LayoutBuilder(
        builder: (context, box) {
          // Six to a line, the way the grid had them. A Wrap has no column
          // count of its own, so the cell is worked out from the width — and
          // a Wrap is what sends the rows past the fold to 'More options'
          // rather than under a scroll the sheet gives no sign of.
          const gap = 8.0;
          final cell = (box.maxWidth - 28 - gap * 5) / 6;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ChipStrip(
                labels: StickerCatalog.packNames,
                selectedIndex: _pack,
                onSelected: (i) => setState(() => _pack = i),
              ),
              const SizedBox(height: 10),
              PanelStrip(
                gap: gap,
                runGap: gap,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (var i = 0; i < StickerCatalog.countIn(_pack); i++)
                    if (isShapes)
                      _cell(
                        size: cell,
                        onTap: () => widget.editor.addSticker(
                          StickerCatalog.shapes[i].$1,
                          isEmoji: false,
                        ),
                        child: Icon(
                          StickerCatalog.shapes[i].$2,
                          size: 24,
                          color: AppColors.text,
                        ),
                      )
                    else
                      _cell(
                        size: cell,
                        onTap: () => widget.editor.addSticker(
                          StickerCatalog.packs[_pack]![i],
                        ),
                        child: Text(
                          StickerCatalog.packs[_pack]![i],
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _cell({
    required Widget child,
    required VoidCallback onTap,
    required double size,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
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

/// Properties of the sticker already on the timeline.
class StickerPropertiesPanel extends StatefulWidget {
  const StickerPropertiesPanel({
    super.key,
    required this.editor,
    required this.layer,
    required this.onClose,
  });

  final EditorController editor;
  final StickerLayer layer;
  final VoidCallback onClose;

  @override
  State<StickerPropertiesPanel> createState() => _StickerPropertiesPanelState();
}

class _StickerPropertiesPanelState extends State<StickerPropertiesPanel> {
  int _tab = 0;

  static const List<int> _palette = [
    0xFFFFFFFF,
    0xFF000000,
    0xFFFF5A5A,
    0xFFFFB020,
    0xFFFFE55C,
    0xFF31E1B4,
    0xFF2BB8E1,
    0xFF6B5BD2,
    0xFFE85C9E,
    0xFF9BE15C,
  ];

  void _update(void Function(StickerLayer) mutate, {bool record = true}) {
    widget.editor.updateLayer<StickerLayer>(
      widget.layer,
      mutate,
      record: record,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Sticker',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      child: PanelBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ChipStrip(
              labels: const ['Style', 'Animate'],
              selectedIndex: _tab,
              onSelected: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: 8),
            if (_tab == 0) ...[
              AppSlider(
                label: 'Size',
                value: widget.layer.size,
                min: 40,
                max: 600,
                defaultValue: 200,
                format: (v) => v.round().toString(),
                onChanged: (v) => _update((l) => l.size = v, record: false),
                onChangeEnd: (v) => _update((l) => l.size = v),
              ),
              AppSlider(
                label: 'Opacity',
                value: widget.layer.transform.opacity,
                min: 0,
                max: 1,
                defaultValue: 1,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) =>
                    _update((l) => l.transform.opacity = v, record: false),
                onChangeEnd: (v) => _update((l) => l.transform.opacity = v),
              ),
              if (!widget.layer.isEmoji)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: PanelStrip(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final c in _palette)
                        GestureDetector(
                          onTap: () => _update((l) => l.color = c),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.layer.color == c
                                    ? AppColors.accent
                                    : AppColors.divider,
                                width: widget.layer.color == c ? 2.4 : 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ] else
              AnimationPicker(
                animationIn: widget.layer.animationIn,
                animationOut: widget.layer.animationOut,
                duration: widget.layer.animationDuration,
                onIn: (a) => _update((l) => l.animationIn = a),
                onOut: (a) => _update((l) => l.animationOut = a),
                onDuration: (d) => _update((l) => l.animationDuration = d),
              ),
          ],
        ),
      ),
    );
  }
}
