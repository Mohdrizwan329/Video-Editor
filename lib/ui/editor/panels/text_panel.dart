import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/layers.dart';
import '../../../data/models/text_presets.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_shell.dart';
import '../../widgets/app_slider.dart';
import 'animation_panel.dart';

/// Full text editor: content, font, colour, outline, shadow, background and
/// in/out animation — the whole text sheet in one place.
class TextPanel extends StatefulWidget {
  const TextPanel({
    super.key,
    required this.editor,
    required this.layer,
    required this.onClose,
  });

  final EditorController editor;
  final TextLayer layer;
  final VoidCallback onClose;

  @override
  State<TextPanel> createState() => _TextPanelState();
}

class _TextPanelState extends State<TextPanel> {
  late final TextEditingController _text =
      TextEditingController(text: widget.layer.text);
  int _tab = 0;
  int _presetCategory = 0;

  static const List<String> _fonts = [
    'Poppins',
    'Anton',
    'Bebas Neue',
    'Oswald',
    'Pacifico',
  ];

  static const List<int> _palette = [
    0xFFFFFFFF, 0xFF000000, 0xFFFF5A5A, 0xFFFFB020,
    0xFFFFE55C, 0xFF31E1B4, 0xFF2BB8E1, 0xFF6B5BD2,
    0xFFE85C9E, 0xFF9BE15C, 0xFFB0B0BC, 0xFF7A4A2B,
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _update(void Function(TextLayer) mutate, {bool record = true}) {
    widget.editor.updateLayer<TextLayer>(widget.layer, mutate, record: record);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Text',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      child: SizedBox(
        height: 268,
        child: Column(
          children: [
            const SizedBox(height: 8),
            ChipStrip(
              labels: const ['Text', 'Preset', 'Font', 'Style', 'Animate'],
              selectedIndex: _tab,
              onSelected: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: switch (_tab) {
                0 => _contentTab(),
                1 => _presetTab(),
                2 => _fontTab(),
                3 => _styleTab(),
                _ => AnimationPicker(
                    animationIn: widget.layer.animationIn,
                    animationOut: widget.layer.animationOut,
                    duration: widget.layer.animationDuration,
                    onIn: (a) => _update((l) => l.animationIn = a),
                    onOut: (a) => _update((l) => l.animationOut = a),
                    onDuration: (d) => _update((l) => l.animationDuration = d),
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _contentTab() {
    // The field and its format row are a fixed height; on a short window —
    // a phone in landscape, or with the keyboard up — the tab scrolls rather
    // than clipping the alignment buttons.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          TextField(
            controller: _text,
            autofocus: true,
            maxLines: 3,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Type something…',
              filled: true,
              fillColor: AppColors.surfaceHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (v) => _update((l) => l.text = v, record: false),
          ),
          const SizedBox(height: 10),
          Wrap(
            children: [
              _toggle(Icons.format_bold, widget.layer.bold,
                  () => _update((l) => l.bold = !l.bold)),
              _toggle(Icons.format_italic, widget.layer.italic,
                  () => _update((l) => l.italic = !l.italic)),
              _toggle(Icons.format_underline, widget.layer.underline,
                  () => _update((l) => l.underline = !l.underline)),
              const SizedBox(width: 12),
              _toggle(Icons.format_align_left,
                  widget.layer.align == TextAlign.left,
                  () => _update((l) => l.align = TextAlign.left)),
              _toggle(Icons.format_align_center,
                  widget.layer.align == TextAlign.center,
                  () => _update((l) => l.align = TextAlign.center)),
              _toggle(Icons.format_align_right,
                  widget.layer.align == TextAlign.right,
                  () => _update((l) => l.align = TextAlign.right)),
            ],
          ),
        ],
      ),
    );
  }

  /// The style gallery: one tap sets every look field at once.
  Widget _presetTab() {
    final category = TextPresetLibrary.categories[_presetCategory];
    final presets = TextPresetLibrary.byCategory(category);
    return Column(
      children: [
        ChipStrip(
          labels: TextPresetLibrary.categories,
          selectedIndex: _presetCategory,
          onSelected: (i) => setState(() => _presetCategory = i),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: presets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 9),
            itemBuilder: (context, i) {
              final p = presets[i];
              final active = widget.layer.stylePresetId == p.id;
              return GestureDetector(
                onTap: () => _update((l) => p.applyTo(l)),
                child: Container(
                  width: 92,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: active ? AppColors.accent : Colors.transparent,
                        width: 1.8),
                  ),
                  alignment: Alignment.center,
                  child: _presetSample(p),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _presetSample(TextStylePreset p) {
    final hasBg = (p.backgroundColor >> 24) != 0;
    final label = Stack(
      children: [
        if (p.strokeWidth > 0)
          Text('Aa',
              style: TextStyle(
                fontFamily: p.fontFamily,
                fontSize: 21,
                fontWeight: p.bold ? FontWeight.w800 : FontWeight.w500,
                letterSpacing: p.letterSpacing * 0.3,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = p.strokeWidth * 0.55
                  ..strokeJoin = StrokeJoin.round
                  ..color = Color(p.strokeColor),
              )),
        Text('Aa',
            style: TextStyle(
              fontFamily: p.fontFamily,
              fontSize: 21,
              color: Color(p.color),
              fontWeight: p.bold ? FontWeight.w800 : FontWeight.w500,
              fontStyle: p.italic ? FontStyle.italic : FontStyle.normal,
              letterSpacing: p.letterSpacing * 0.3,
              shadows: p.shadowBlur > 0
                  ? [
                      Shadow(
                        color: Color(p.shadowColor),
                        blurRadius: p.shadowBlur * 0.5,
                        offset: Offset(
                            p.shadowOffsetX * 0.3, p.shadowOffsetY * 0.3),
                      )
                    ]
                  : null,
            )),
      ],
    );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        hasBg
            ? Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Color(p.backgroundColor),
                  borderRadius:
                      BorderRadius.circular(p.backgroundRadius * 0.4),
                ),
                child: label,
              )
            : label,
        const SizedBox(height: 4),
        Text(p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 8.5, color: AppColors.textFaint)),
      ],
    );
  }

  Widget _fontTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _fonts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 9),
              itemBuilder: (context, i) {
                final f = _fonts[i];
                final active = widget.layer.fontFamily == f;
                return GestureDetector(
                  onTap: () => _update((l) => l.fontFamily = f),
                  child: Container(
                    width: 82,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.accent.withValues(alpha: 0.16)
                          : AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: active ? AppColors.accent : Colors.transparent,
                      ),
                    ),
                    child: Text('Aa',
                        style: TextStyle(
                          fontFamily: f,
                          fontSize: 20,
                          color: active ? AppColors.accent : AppColors.text,
                        )),
                  ),
                );
              },
            ),
          ),
          AppSlider(
            label: 'Size',
            value: widget.layer.fontSize,
            min: 16,
            max: 220,
            defaultValue: 64,
            format: (v) => v.round().toString(),
            onChanged: (v) => _update((l) => l.fontSize = v, record: false),
            onChangeEnd: (v) => _update((l) => l.fontSize = v),
          ),
          AppSlider(
            label: 'Letter spacing',
            value: widget.layer.letterSpacing,
            min: -6,
            max: 24,
            bipolar: true,
            defaultValue: 0,
            format: (v) => v.toStringAsFixed(1),
            onChanged: (v) => _update((l) => l.letterSpacing = v, record: false),
            onChangeEnd: (v) => _update((l) => l.letterSpacing = v),
          ),
          AppSlider(
            label: 'Line height',
            value: widget.layer.lineHeight,
            min: 0.8,
            max: 2.4,
            defaultValue: 1.2,
            format: (v) => v.toStringAsFixed(2),
            onChanged: (v) => _update((l) => l.lineHeight = v, record: false),
            onChangeEnd: (v) => _update((l) => l.lineHeight = v),
          ),
        ],
      ),
    );
  }

  Widget _styleTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _colorRow('Text', widget.layer.color,
              (c) => _update((l) => l.color = c)),
          _colorRow('Outline', widget.layer.strokeColor,
              (c) => _update((l) => l.strokeColor = c)),
          AppSlider(
            label: 'Outline width',
            value: widget.layer.strokeWidth,
            min: 0,
            max: 12,
            defaultValue: 0,
            format: (v) => v.toStringAsFixed(1),
            onChanged: (v) => _update((l) => l.strokeWidth = v, record: false),
            onChangeEnd: (v) => _update((l) => l.strokeWidth = v),
          ),
          AppSlider(
            label: 'Shadow blur',
            value: widget.layer.shadowBlur,
            min: 0,
            max: 40,
            defaultValue: 0,
            format: (v) => v.round().toString(),
            onChanged: (v) => _update((l) => l.shadowBlur = v, record: false),
            onChangeEnd: (v) => _update((l) => l.shadowBlur = v),
          ),
          _colorRow('Backdrop', widget.layer.backgroundColor,
              (c) => _update((l) => l.backgroundColor = c),
              includeClear: true),
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
        ],
      ),
    );
  }

  Widget _colorRow(String label, int selected, ValueChanged<int> onPick,
      {bool includeClear = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
          const SizedBox(height: 6),
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (includeClear)
                  _swatch(0x00000000, selected == 0x00000000,
                      () => onPick(0x00000000),
                      icon: Icons.format_color_reset),
                for (final c in _palette)
                  _swatch(c, selected == c, () => onPick(c)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _swatch(int color, bool active, VoidCallback onTap, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Color(color),
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? AppColors.accent : AppColors.divider,
              width: active ? 2.4 : 1,
            ),
          ),
          child: icon == null
              ? null
              : Icon(icon, size: 13, color: AppColors.textDim),
        ),
      ),
    );
  }

  Widget _toggle(IconData icon, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 32,
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent.withValues(alpha: 0.18)
                : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
                color: active ? AppColors.accent : Colors.transparent),
          ),
          child: Icon(icon,
              size: 16,
              color: active ? AppColors.accent : AppColors.textDim),
        ),
      ),
    );
  }
}
