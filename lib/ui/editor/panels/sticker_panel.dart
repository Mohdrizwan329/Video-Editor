import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/layers.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_shell.dart';
import '../../widgets/app_slider.dart';
import 'animation_panel.dart';

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

  static const List<String> _packNames = [
    'Faces', 'Love', 'Hands', 'Party', 'Nature', 'Signs', 'Shapes'
  ];

  static const Map<int, List<String>> _packs = {
    0: ['😀','😂','🥹','😍','😎','🤩','😭','😡','🤔','🥳','😴','🤯','😱','🙃','😇','🤗'],
    1: ['❤️','🧡','💛','💚','💙','💜','🖤','🤍','💖','💘','💝','💕','💞','😻','💐','🌹'],
    2: ['👍','👎','👏','🙌','🤝','✌️','🤟','👊','🙏','💪','👋','🫶','☝️','🤙','👌','✍️'],
    3: ['🎉','🎊','🥂','🍾','🎈','🎁','🎂','🍰','🪅','✨','🌟','💫','🔥','⚡','🎵','🎶'],
    4: ['🌸','🌺','🌻','🌴','🌊','🏔️','☀️','🌙','⭐','☁️','🌈','❄️','🍁','🦋','🐝','🌵'],
    5: ['✅','❌','⚠️','❗','❓','💯','🔝','🆕','🔴','🟢','🔵','⏰','📍','🎯','🚀','💡'],
  };

  static const List<(String, IconData)> _shapes = [
    ('circle', Icons.circle),
    ('ring', Icons.circle_outlined),
    ('square', Icons.square),
    ('triangle', Icons.change_history),
    ('star', Icons.star),
    ('heart', Icons.favorite),
    ('arrow', Icons.arrow_forward),
    ('bubble', Icons.chat_bubble),
  ];

  @override
  Widget build(BuildContext context) {
    final isShapes = _pack == _packNames.length - 1;
    return PanelShell(
      title: 'Stickers',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      child: SizedBox(
        height: 210,
        child: Column(
          children: [
            const SizedBox(height: 8),
            ChipStrip(
              labels: _packNames,
              selectedIndex: _pack,
              onSelected: (i) => setState(() => _pack = i),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount:
                    isShapes ? _shapes.length : (_packs[_pack]?.length ?? 0),
                itemBuilder: (context, i) {
                  if (isShapes) {
                    final (key, icon) = _shapes[i];
                    return _cell(
                      child: Icon(icon, size: 24, color: AppColors.text),
                      onTap: () =>
                          widget.editor.addSticker(key, isEmoji: false),
                    );
                  }
                  final emoji = _packs[_pack]![i];
                  return _cell(
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                    onTap: () => widget.editor.addSticker(emoji),
                  );
                },
              ),
            ),
          ],
        ),
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
    0xFFFFFFFF, 0xFF000000, 0xFFFF5A5A, 0xFFFFB020,
    0xFFFFE55C, 0xFF31E1B4, 0xFF2BB8E1, 0xFF6B5BD2,
    0xFFE85C9E, 0xFF9BE15C,
  ];

  void _update(void Function(StickerLayer) mutate, {bool record = true}) {
    widget.editor
        .updateLayer<StickerLayer>(widget.layer, mutate, record: record);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Sticker',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      child: SizedBox(
        height: 210,
        child: Column(
          children: [
            const SizedBox(height: 8),
            ChipStrip(
              labels: const ['Style', 'Animate'],
              selectedIndex: _tab,
              onSelected: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _tab == 0
                  ? SingleChildScrollView(
                      child: Column(
                        children: [
                          AppSlider(
                            label: 'Size',
                            value: widget.layer.size,
                            min: 40,
                            max: 600,
                            defaultValue: 200,
                            format: (v) => v.round().toString(),
                            onChanged: (v) =>
                                _update((l) => l.size = v, record: false),
                            onChangeEnd: (v) => _update((l) => l.size = v),
                          ),
                          AppSlider(
                            label: 'Opacity',
                            value: widget.layer.transform.opacity,
                            min: 0,
                            max: 1,
                            defaultValue: 1,
                            format: (v) => '${(v * 100).round()}%',
                            onChanged: (v) => _update(
                                (l) => l.transform.opacity = v,
                                record: false),
                            onChangeEnd: (v) =>
                                _update((l) => l.transform.opacity = v),
                          ),
                          if (!widget.layer.isEmoji)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 6, 16, 10),
                              child: SizedBox(
                                height: 30,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    for (final c in _palette)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: GestureDetector(
                                          onTap: () =>
                                              _update((l) => l.color = c),
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
                                                width: widget.layer.color == c
                                                    ? 2.4
                                                    : 1,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : AnimationPicker(
                      animationIn: widget.layer.animationIn,
                      animationOut: widget.layer.animationOut,
                      duration: widget.layer.animationDuration,
                      onIn: (a) => _update((l) => l.animationIn = a),
                      onOut: (a) => _update((l) => l.animationOut = a),
                      onDuration: (d) => _update((l) => l.animationDuration = d),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
