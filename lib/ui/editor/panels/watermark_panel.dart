import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/watermark.dart';
import '../../../state/editor_controller.dart';
import '../../picker/media_picker_screen.dart';
import '../../widgets/app_slider.dart';
import '../../widgets/panel_shell.dart';

/// The creator's own mark, applied to the whole project.
///
/// The two kinds are deliberately exclusive: picking Text or Logo switches
/// [Watermark.type], and only that one is ever drawn or exported.
class WatermarkPanel extends StatefulWidget {
  const WatermarkPanel({
    super.key,
    required this.editor,
    required this.onClose,
  });

  final EditorController editor;
  final VoidCallback onClose;

  @override
  State<WatermarkPanel> createState() => _WatermarkPanelState();
}

class _WatermarkPanelState extends State<WatermarkPanel> {
  late final TextEditingController _text =
      TextEditingController(text: widget.editor.project.watermark.text);

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

  Watermark get mark => widget.editor.project.watermark;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _update(void Function(Watermark) mutate, {bool record = true}) {
    widget.editor.setWatermark(mutate, record: record);
    setState(() {});
  }

  Future<void> _pickLogo() async {
    final navigator = Navigator.of(context);
    final paths = await navigator.push<List<String>>(
      MaterialPageRoute(
        builder: (_) => const MediaPickerScreen(
          title: 'Watermark logo',
          filter: RequestType.image,
          maxSelection: 1,
        ),
      ),
    );
    if (paths == null || paths.isEmpty) return;
    await widget.editor.setWatermarkImage(paths.first);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Watermark',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      trailing: Switch(
        value: mark.enabled,
        activeThumbColor: AppColors.accent,
        onChanged: (v) => _update((w) => w.enabled = v),
      ),
      child: PanelBody(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChipStrip(
                labels: WatermarkType.values.map((t) => t.label).toList(),
                selectedIndex: WatermarkType.values.indexOf(mark.type),
                onSelected: (i) =>
                    _update((w) => w.type = WatermarkType.values[i]),
              ),
              const SizedBox(height: 12),
              if (mark.type == WatermarkType.text) ..._textControls(),
              if (mark.type == WatermarkType.image) ..._logoControls(),
              const _SectionLabel('Position'),
              _anchorGrid(),
              AppSlider(
                label: 'Opacity',
                icon: Icons.opacity,
                value: mark.transform.opacity,
                min: 0.05,
                max: 1,
                defaultValue: 0.75,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) =>
                    _update(record: false, (w) => w.transform.opacity = v),
              ),
              AppSlider(
                label: 'Rotation',
                icon: Icons.rotate_right,
                value: mark.transform.rotation,
                min: -3.14,
                max: 3.14,
                bipolar: true,
                defaultValue: 0,
                format: (v) => '${(v * 180 / 3.14159).round()}°',
                onChanged: (v) =>
                    _update(record: false, (w) => w.transform.rotation = v),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ text mark

  List<Widget> _textControls() => [
        TextField(
          controller: _text,
          maxLines: 1,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(fontSize: 13.5),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Your name, handle or brand',
            hintStyle:
                const TextStyle(fontSize: 12.5, color: AppColors.textFaint),
            filled: true,
            fillColor: AppColors.surfaceHigh,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (v) => _update(record: false, (w) {
            w.text = v;
            // Typing the first character is the moment the mark becomes real.
            if (v.trim().isNotEmpty) w.enabled = true;
          }),
        ),
        const SizedBox(height: 12),
        const _SectionLabel('Font'),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _fonts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final f = _fonts[i];
              final active = mark.fontFamily == f;
              return GestureDetector(
                onTap: () => _update((w) => w.fontFamily = f),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.accent.withValues(alpha: 0.18)
                        : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: active ? AppColors.accent : Colors.transparent,
                      width: 1.4,
                    ),
                  ),
                  child: Text(
                    f,
                    style: TextStyle(
                      fontFamily: f,
                      fontSize: 12,
                      color: active ? AppColors.accent : AppColors.textDim,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        const _SectionLabel('Colour'),
        // One scrolling row, not a wrap: a second row of swatches pushed the
        // controls below it out of the sheet and left the sheet taller than
        // what it was showing.
        SizedBox(
          height: 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _palette.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = _palette[i];
              final active = mark.color == c;
              return GestureDetector(
                onTap: () => _update((w) => w.color = c),
                child: Container(
                  width: 30,
                  decoration: BoxDecoration(
                    color: Color(c),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: active ? AppColors.accent : AppColors.divider,
                      width: active ? 2.4 : 1,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // Wrap, not Row: in the editor's side rail, or at a large system
        // font, the three chips no longer fit on one line.
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _toggle('Bold', mark.bold, () => _update((w) => w.bold = !w.bold)),
            _toggle('Italic', mark.italic,
                () => _update((w) => w.italic = !w.italic)),
            _toggle(
              'Backdrop',
              (mark.backgroundColor >> 24) != 0,
              () => _update((w) => w.backgroundColor =
                  (w.backgroundColor >> 24) != 0 ? 0x00000000 : 0x80000000),
            ),
          ],
        ),
        AppSlider(
          label: 'Size',
          icon: Icons.format_size,
          value: mark.fontSize,
          min: 14,
          max: 140,
          defaultValue: 46,
          format: (v) => v.round().toString(),
          onChanged: (v) => _update(record: false, (w) => w.fontSize = v),
        ),
      ];

  // ------------------------------------------------------------ logo mark

  List<Widget> _logoControls() {
    final path = mark.imagePath;
    final hasLogo = path != null && path.isNotEmpty;
    return [
      Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasLogo
                ? Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        size: 20,
                        color: AppColors.textFaint),
                  )
                : const Icon(Icons.image_outlined,
                    size: 22, color: AppColors.textFaint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasLogo ? path.split('/').last : 'No logo chosen',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textDim),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _pickLogo,
                      icon: const Icon(Icons.add_photo_alternate_outlined,
                          size: 16),
                      label: Text(hasLogo ? 'Replace' : 'Choose logo',
                          style: const TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                    if (hasLogo)
                      TextButton(
                        onPressed: () => _update((w) {
                          w.imagePath = null;
                          w.enabled = false;
                        }),
                        style: TextButton.styleFrom(
                            minimumSize: const Size(0, 32),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10)),
                        child: const Text('Remove',
                            style: TextStyle(
                                fontSize: 11.5, color: AppColors.danger)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      AppSlider(
        label: 'Size',
        icon: Icons.photo_size_select_large,
        value: mark.imageSize,
        min: 50,
        max: 600,
        defaultValue: 180,
        format: (v) => v.round().toString(),
        onChanged: (v) => _update(record: false, (w) => w.imageSize = v),
      ),
    ];
  }

  // --------------------------------------------------------------- shared

  Widget _toggle(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accent.withValues(alpha: 0.18)
              : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.accent : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.accent : AppColors.textDim)),
      ),
    );
  }

  /// Nine corner/edge presets. Dragging the mark on the canvas clears the
  /// highlight, because the position is then the creator's own.
  Widget _anchorGrid() {
    final current = mark.anchor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          for (var row = 0; row < 3; row++)
            Row(
              children: [
                for (var col = 0; col < 3; col++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 6),
                    child: _anchorCell(
                        WatermarkAnchor.values[row * 3 + col], current),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _anchorCell(WatermarkAnchor a, WatermarkAnchor? current) {
    final active = a == current;
    return Tooltip(
      message: a.label,
      child: GestureDetector(
        onTap: () => _update((w) => w.applyAnchor(a)),
        child: Container(
          width: 30,
          height: 26,
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent.withValues(alpha: 0.18)
                : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? AppColors.accent : AppColors.divider,
              width: active ? 1.6 : 1,
            ),
          ),
          child: Align(
            alignment: Alignment(
              (a.x - 0.5) * 2.4,
              (a.y - 0.5) * 2.4,
            ),
            child: Container(
              width: 8,
              height: 5,
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: active ? AppColors.accent : AppColors.textFaint,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppColors.textFaint)),
      );
}
