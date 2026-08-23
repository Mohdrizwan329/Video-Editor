part of '../image_editor_screen.dart';

/// The colours the ink, the shapes and the captions all draw from. One list
/// for every tool: a photo edited with two palettes looks like two edits.
const List<int> _palette = [
  0xFFFFFFFF,
  0xFF000000,
  0xFFFF3B30,
  0xFFFF9500,
  0xFFFFCC00,
  0xFF34C759,
  0xFF00C7BE,
  0xFF32ADE6,
  0xFF5856D6,
  0xFFAF52DE,
  0xFFFF2D55,
  0xFF8E8E93,
];

/// The bottom sheets for everything the picture carries rather than the way
/// it is graded: the portrait pass, the three brushes, and the overlays.
///
/// They live in an extension so the screen file stays about the stage and the
/// history, and they never call `setState` directly — the state class owns
/// [_edited], [_dragging], [_commit] and [_refresh], and which of those a
/// change goes through is what decides where the undo stack lands.
extension _PhotoPanels on _ImageEditorScreenState {
  // ------------------------------------------------------------- AI Face

  Widget _faceTools() {
    final r = context.r;
    final face = _edit.face;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(8)),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: r.dp(4),
          runSpacing: r.vp(6),
          children: [
            _action(
              Icons.auto_fix_high,
              'Auto',
              () => _edited(() => _edit.face.auto()),
            ),
            _action(
              Icons.restart_alt,
              'Reset',
              () => _edited(() => _edit.face.reset()),
            ),
          ],
        ),
        _faceNote(),
        _amount(
          'Smooth',
          Icons.blur_on,
          face.smooth,
          (v) => _edit.face.smooth = v,
        ),
        _amount(
          'Brighten',
          Icons.wb_sunny_outlined,
          face.brighten,
          (v) => _edit.face.brighten = v,
        ),
        _amount(
          'Even tone',
          Icons.face_retouching_natural,
          face.evenTone,
          (v) => _edit.face.evenTone = v,
        ),
        _amount(
          'Clarity',
          Icons.details,
          face.clarity,
          (v) => _edit.face.clarity = v,
        ),
        SizedBox(height: r.vp(8)),
      ],
    );
  }

  /// Says plainly whether there is a face to work on. The sliders are left
  /// alive either way — the answer can change when the photo is re-framed —
  /// but a picture with no skin in it will not quietly go soft.
  Widget _faceNote() {
    if (_lookingForSkin) return _hint('Looking for a face…');
    if (_image != null && _skinMask == null) {
      return _hint('No face found — these sliders have nothing to work on.');
    }
    return _hint('Skin only: the rest of the picture is left alone.');
  }

  // -------------------------------------------------------------- Markup

  Widget _markupTools() {
    final r = context.r;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(8)),
        _pills([
          _Pill(
            'Draw',
            Icons.edit,
            active: !_erasing,
            onTap: () => _refresh(() => _erasing = false),
          ),
          _Pill(
            'Erase',
            Icons.auto_fix_normal,
            active: _erasing,
            onTap: () => _refresh(() => _erasing = true),
          ),
          _Pill(
            'Undo line',
            Icons.undo,
            enabled: _edit.markup.isNotEmpty,
            onTap: () => _edited(() => _edit.markup.removeLast()),
          ),
          _Pill(
            'Clear',
            Icons.layers_clear,
            enabled: _edit.markup.isNotEmpty,
            onTap: () => _edited(() => _edit.markup.clear()),
          ),
        ]),
        SizedBox(height: r.vp(8)),
        _swatches(_inkColor, (c) => _refresh(() => _inkColor = c)),
        _brushSlider(_inkWidth, (v) => _refresh(() => _inkWidth = v)),
        _hint('Draw straight on the photo.'),
        SizedBox(height: r.vp(6)),
      ],
    );
  }

  // ------------------------------------------------------------ Pixelate

  Widget _pixelateTools() {
    final r = context.r;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(8)),
        _pills([
          for (final style in PixelStyle.values)
            _Pill(
              style.label,
              style == PixelStyle.mosaic ? Icons.grid_on : Icons.blur_circular,
              active: _edit.pixelStyle == style,
              onTap: () => _edited(() => _edit.pixelStyle = style),
            ),
          _Pill(
            'Undo',
            Icons.undo,
            enabled: _edit.pixelate.isNotEmpty,
            onTap: () => _edited(() => _edit.pixelate.removeLast()),
          ),
          _Pill(
            'Clear',
            Icons.layers_clear,
            enabled: _edit.pixelate.isNotEmpty,
            onTap: () => _edited(() => _edit.pixelate.clear()),
          ),
        ]),
        _amount(
          _edit.pixelStyle == PixelStyle.mosaic ? 'Block size' : 'Blur',
          Icons.grid_view,
          _edit.pixelSize,
          (v) => _edit.pixelSize = v,
        ),
        _brushSlider(_pixelBrush, (v) => _refresh(() => _pixelBrush = v)),
        _hint('Paint over a face or a number plate to hide it.'),
        SizedBox(height: r.vp(6)),
      ],
    );
  }

  // ------------------------------------------------------------- Retouch

  Widget _retouchTools() {
    final r = context.r;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(8)),
        _pills([
          _Pill(
            'Undo',
            Icons.undo,
            enabled: _edit.retouch.isNotEmpty,
            onTap: () => _edited(() => _edit.retouch.removeLast()),
          ),
          _Pill(
            'Clear',
            Icons.layers_clear,
            enabled: _edit.retouch.isNotEmpty,
            onTap: () => _edited(() => _edit.retouch.clear()),
          ),
        ]),
        _amount(
          'Strength',
          Icons.healing,
          _edit.retouchStrength,
          (v) => _edit.retouchStrength = v,
        ),
        _brushSlider(_retouchBrush, (v) => _refresh(() => _retouchBrush = v)),
        _hint('Dab a blemish to soften it and take the redness out.'),
        SizedBox(height: r.vp(6)),
      ],
    );
  }

  // ---------------------------------------------------------------- Text

  TextLayer? get _selectedText {
    final overlay = _edit.overlayById(_selected);
    return overlay is TextLayer ? overlay : null;
  }

  Widget _textTools() {
    final r = context.r;
    final layer = _selectedText;
    // Every category here is a real one — there is no 'All' chip in front of
    // them, so the strip is exactly what the chosen category holds.
    final presets = TextPresetLibrary.byCategory(
      TextPresetLibrary.categories[_textCategory],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(8)),
        _pills([
          _Pill('Add text', Icons.add, onTap: _addText),
          _Pill(
            'Edit',
            Icons.keyboard,
            enabled: layer != null,
            onTap: () {
              if (layer != null) _writeText(layer);
            },
          ),
          _Pill(
            'Delete',
            Icons.delete_outline,
            enabled: layer != null,
            onTap: _deleteSelected,
          ),
        ]),
        SizedBox(height: r.vp(8)),
        ChipStrip(
          labels: TextPresetLibrary.categories,
          selectedIndex: _textCategory,
          onSelected: (i) => _refresh(() => _textCategory = i),
        ),
        SizedBox(height: r.vp(8)),
        SizedBox(
          // The tile, the gap and the name at the system font scale — the
          // same sum the filter strip makes, one tile size smaller.
          height: math.max(
            r.vp(68),
            46 + MediaQuery.textScalerOf(context).scale(9.5) * 1.7,
          ),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: r.dp(14)),
            itemCount: presets.length,
            separatorBuilder: (_, _) => SizedBox(width: r.dp(9)),
            itemBuilder: (context, i) {
              final preset = presets[i];
              return PresetTile(
                label: preset.name,
                active: layer?.stylePresetId == preset.id,
                size: 42,
                onTap: () => _applyTextPreset(preset),
                child: ColoredBox(
                  color: AppColors.appBar,
                  child: Center(
                    child: Text(
                      'Aa',
                      style: TextStyle(
                        fontFamily: preset.fontFamily,
                        color: Color(preset.color),
                        fontSize: 17,
                        fontWeight: preset.bold
                            ? FontWeight.w800
                            : FontWeight.w500,
                        fontStyle: preset.italic
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: r.vp(8)),
        if (layer == null)
          _hint('Add a caption, then drag it on the photo to place it.')
        else ...[
          _swatches(layer.color, (c) => _edited(() => layer.color = c)),
          _sizeSlider(layer.transform),
          _opacitySlider(layer.transform),
        ],
        SizedBox(height: r.vp(6)),
      ],
    );
  }

  Future<void> _addText() async {
    final layer = TextLayer(
      start: Duration.zero,
      duration: const Duration(hours: 6),
      text: 'Your text',
      fontSize: 64,
      transform: LayerTransform(x: 0.5, y: 0.5),
    );
    _edited(() {
      _edit.texts.add(layer);
      _selected = layer.id;
    });
    // A brand new caption opens on an empty field: 'Your text' is a stand-in
    // to drag around, not something to type around.
    await _writeText(layer, fresh: true);
  }

  /// Asks for a line of words and hands back what was typed, or null if the
  /// user backed out.
  ///
  /// The controller belongs to the dialog rather than to this method. A
  /// controller made out here has to be disposed when the await returns —
  /// which is while the dialog is still animating away, and the field it
  /// belongs to is still being built. That is a use-after-dispose, and it
  /// threw every time a caption was typed.
  Future<String?> _promptFor({
    required String title,
    required String hint,
    required String initial,
    bool selectAll = false,
    int lines = 1,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => _TextPrompt(
        title: title,
        hint: hint,
        initial: initial,
        selectAll: selectAll,
        lines: lines,
      ),
    );
  }

  /// The keyboard, in a dialog. A caption is typed far more often than it is
  /// dragged, so it opens the moment one is added.
  ///
  /// Re-opening it on an existing caption selects the whole of it, so the
  /// first key replaces the words instead of running on from them.
  Future<void> _writeText(TextLayer layer, {bool fresh = false}) async {
    final typed = await _promptFor(
      title: 'Text',
      hint: 'Type something',
      initial: fresh ? '' : layer.text,
      selectAll: !fresh,
      lines: 3,
    );
    // Backing out of a brand new caption takes the caption with it — the
    // user asked for words and gave none.
    if (typed == null) {
      if (fresh) _edited(() => _edit.removeOverlay(layer.id));
      return;
    }
    // An empty caption is a deleted one: there is nothing to select and
    // nothing to draw.
    if (typed.trim().isEmpty) {
      _edited(() {
        _edit.removeOverlay(layer.id);
        _selected = null;
      });
      return;
    }
    _edited(() => layer.text = typed);
  }

  void _applyTextPreset(TextStylePreset preset) {
    final layer = _selectedText;
    if (layer == null) return;
    _edited(() => preset.applyTo(layer));
  }

  // ------------------------------------------------------------ Stickers

  StickerLayer? get _selectedSticker {
    final overlay = _edit.overlayById(_selected);
    return overlay is StickerLayer ? overlay : null;
  }

  Widget _stickerTools() {
    final r = context.r;
    final layer = _selectedSticker;
    final shapes = StickerCatalog.isShapes(_stickerPack);
    final count = StickerCatalog.countIn(_stickerPack);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(8)),
        ChipStrip(
          labels: StickerCatalog.packNames,
          selectedIndex: _stickerPack,
          onSelected: (i) => _refresh(() => _stickerPack = i),
        ),
        SizedBox(height: r.vp(8)),
        SizedBox(
          height: math.max(r.vp(46), 40),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: r.dp(14)),
            itemCount: count,
            separatorBuilder: (_, _) => SizedBox(width: r.dp(8)),
            itemBuilder: (context, i) {
              final size = math.max(r.dp(40), 36.0);
              if (shapes) {
                final (key, icon) = StickerCatalog.shapes[i];
                return _tile(
                  size,
                  Icon(icon, size: r.ic(20), color: AppColors.appBarMuted),
                  () => _addSticker(key, emoji: false),
                );
              }
              final glyph = StickerCatalog.packs[_stickerPack]![i];
              return _tile(
                size,
                Text(glyph, style: TextStyle(fontSize: r.sp(19))),
                () => _addSticker(glyph),
              );
            },
          ),
        ),
        SizedBox(height: r.vp(8)),
        if (layer == null)
          _hint('Tap a sticker to place it, then drag or pinch it.')
        else ...[
          _pills([
            _Pill('Delete', Icons.delete_outline, onTap: _deleteSelected),
          ]),
          if (!layer.isEmoji)
            _swatches(layer.color, (c) => _edited(() => layer.color = c)),
          _sizeSlider(layer.transform),
          _opacitySlider(layer.transform),
        ],
        SizedBox(height: r.vp(6)),
      ],
    );
  }

  void _addSticker(String content, {bool emoji = true}) {
    final layer = StickerLayer(
      start: Duration.zero,
      duration: const Duration(hours: 6),
      content: content,
      isEmoji: emoji,
      size: 220,
      color: emoji ? 0xFFFFFFFF : _inkColor,
      transform: LayerTransform(x: 0.5, y: 0.5),
    );
    _edited(() {
      _edit.stickers.add(layer);
      _selected = layer.id;
    });
  }

  // ----------------------------------------------------------- Watermark

  Widget _watermarkTools() {
    final r = context.r;
    final mark = _edit.watermark;
    final anchors = WatermarkAnchor.values;
    final anchor = mark.anchor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(8)),
        _pills([
          _Pill(
            mark.enabled ? 'On' : 'Off',
            mark.enabled ? Icons.check_circle : Icons.circle_outlined,
            active: mark.enabled,
            onTap: () => _edited(() => mark.enabled = !mark.enabled),
          ),
          for (final type in WatermarkType.values)
            _Pill(
              type.label,
              type == WatermarkType.text ? Icons.title : Icons.image_outlined,
              active: mark.type == type,
              onTap: () => _edited(() {
                mark.type = type;
                mark.enabled = true;
              }),
            ),
          if (mark.type == WatermarkType.text)
            _Pill('Edit', Icons.keyboard, onTap: _writeMark)
          else
            _Pill('Pick logo', Icons.folder_open, onTap: _pickLogo),
        ]),
        SizedBox(height: r.vp(8)),
        ChipStrip(
          labels: [for (final a in anchors) a.label],
          selectedIndex: anchor == null ? -1 : anchors.indexOf(anchor),
          onSelected: (i) => _edited(() {
            mark.applyAnchor(anchors[i]);
            mark.enabled = true;
          }),
        ),
        SizedBox(height: r.vp(6)),
        if (mark.type == WatermarkType.image && (mark.imagePath ?? '').isEmpty)
          _hint('Pick a logo and it will be burned into the saved photo.')
        else if (!mark.enabled)
          _hint('The mark is off — turn it on to put it on the photo.')
        else
          _hint('Drag the mark on the photo to place it exactly.'),
        _sizeSlider(mark.transform),
        _opacitySlider(mark.transform),
        SizedBox(height: r.vp(6)),
      ],
    );
  }

  Future<void> _writeMark() async {
    final mark = _edit.watermark;
    final typed = await _promptFor(
      title: 'Watermark',
      hint: 'Your brand',
      initial: mark.text,
    );
    if (typed == null) return;
    _edited(() {
      mark.text = typed;
      mark.type = WatermarkType.text;
      mark.enabled = typed.trim().isNotEmpty;
    });
  }

  Future<void> _pickLogo() async {
    final picked = await MediaLibrary.instance.pickFiles(
      allowMultiple: false,
      kind: PickKind.image,
    );
    final path = picked.isEmpty ? null : picked.first.filePath;
    if (path == null || !mounted) return;
    _edited(() {
      _edit.watermark
        ..imagePath = path
        ..type = WatermarkType.image
        ..enabled = true;
    });
  }

  // -------------------------------------------------------------- shared

  void _deleteSelected() {
    final id = _selected;
    if (id == null) return;
    _edited(() {
      _edit.removeOverlay(id);
      _selected = null;
    });
  }

  /// A 0..1 slider that writes into the picture: live while it moves, one
  /// entry on the undo stack when it is let go.
  Widget _amount(
    String label,
    IconData icon,
    double value,
    void Function(double) apply,
  ) => AppSlider(
    label: label,
    icon: icon,
    value: value.clamp(0.0, 1.0),
    min: 0,
    max: 1,
    defaultValue: 0,
    format: (v) => '${(v * 100).round()}%',
    onChanged: (v) => _dragging(() => apply(v)),
    onChangeEnd: (_) => _commit(),
  );

  /// The brush itself is a tool setting, so it never reaches the undo stack.
  Widget _brushSlider(double value, ValueChanged<double> onChanged) =>
      AppSlider(
        label: 'Brush',
        icon: Icons.brush,
        value: value,
        min: 0.006,
        max: 0.22,
        defaultValue: value,
        format: (v) => '${(v * 100).round()}',
        onChanged: onChanged,
      );

  Widget _sizeSlider(LayerTransform transform) => AppSlider(
    label: 'Size',
    icon: Icons.photo_size_select_small,
    value: transform.scale.clamp(0.2, 4.0),
    min: 0.2,
    max: 4,
    defaultValue: 1,
    format: (v) => '${(v * 100).round()}%',
    onChanged: (v) => _dragging(() => transform.scale = v),
    onChangeEnd: (_) => _commit(),
  );

  Widget _opacitySlider(LayerTransform transform) => AppSlider(
    label: 'Opacity',
    icon: Icons.opacity,
    value: transform.opacity.clamp(0.0, 1.0),
    min: 0,
    max: 1,
    defaultValue: 1,
    format: (v) => '${(v * 100).round()}%',
    onChanged: (v) => _dragging(() => transform.opacity = v),
    onChangeEnd: (_) => _commit(),
  );

  Widget _swatches(int current, ValueChanged<int> onPick) {
    final r = context.r;
    final side = math.max(r.dp(26), 24.0);
    return SizedBox(
      height: side,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: r.dp(14)),
        itemCount: _palette.length,
        separatorBuilder: (_, _) => SizedBox(width: r.dp(7)),
        itemBuilder: (context, i) {
          final colour = _palette[i];
          final active = colour == current;
          return GestureDetector(
            onTap: () => onPick(colour),
            child: Container(
              width: side,
              decoration: BoxDecoration(
                color: Color(colour),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: active ? AppColors.accent : AppColors.divider,
                  width: active ? 2.4 : 1,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// One row of small labelled buttons. A Wrap and not a Row for the same
  /// reason the crop tool's row is one: at the largest system font they do
  /// not fit across a small phone, and a second line beats a clipped button.
  Widget _pills(List<_Pill> pills) {
    final r = context.r;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: r.dp(6),
      runSpacing: r.vp(6),
      children: [for (final pill in pills) _PillButton(pill: pill, scale: r)],
    );
  }

  Widget _tile(double side, Widget child, VoidCallback onTap) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: AppColors.tint(AppColors.appBar),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.appBar.withValues(alpha: 0.16)),
      ),
      child: child,
    ),
  );

  Widget _hint(String text) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.fromLTRB(r.dp(16), r.vp(6), r.dp(16), r.vp(2)),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: r.sp(10.5), color: AppColors.textFaint),
      ),
    );
  }
}

/// What one of the panels' small buttons says and does.
class _Pill {
  const _Pill(
    this.label,
    this.icon, {
    this.active = false,
    this.enabled = true,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.pill, required this.scale});

  final _Pill pill;
  final Responsive scale;

  @override
  Widget build(BuildContext context) {
    final active = pill.active;
    final enabled = pill.enabled;
    final foreground = !enabled
        ? AppColors.textFaint.withValues(alpha: 0.5)
        : active
        ? AppColors.onAccent
        : AppColors.appBarMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: enabled ? pill.onTap : null,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: scale.dp(10),
          vertical: scale.vp(7),
        ),
        decoration: BoxDecoration(
          color: active ? AppColors.accent : null,
          gradient: active ? null : AppColors.tint(AppColors.appBar),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: active
                ? AppColors.accent
                : AppColors.appBar.withValues(alpha: 0.16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(pill.icon, size: scale.ic(15), color: foreground),
            SizedBox(width: scale.dp(5)),
            Text(
              pill.label,
              style: TextStyle(
                fontSize: scale.sp(11),
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A one-field dialog that owns its own controller.
///
/// The controller has to outlive the await that opens the dialog: the route
/// is still animating out when that returns, so anything disposed there is
/// disposed while the field is still being built.
class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.hint,
    required this.initial,
    required this.selectAll,
    required this.lines,
  });

  final String title;
  final String hint;
  final String initial;

  /// Re-opening on existing words selects the whole of them, so the first
  /// key replaces what is there instead of running on from it.
  final bool selectAll;

  final int lines;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.selectAll ? widget.initial.length : 0,
        );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: widget.lines,
        minLines: 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          style: AppTheme.outlinedAction(),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: AppTheme.outlinedAction(tone: AppColors.accent),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
