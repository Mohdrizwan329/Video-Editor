import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/adjustments.dart';
import '../../data/models/filter_preset.dart';
import '../../data/models/layers.dart';
import '../../data/models/photo_edit.dart';
import '../../data/models/text_presets.dart';
import '../../data/models/watermark.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/services/face_enhancer.dart';
import '../../data/services/media_library.dart';
import '../../data/services/photo_renderer.dart';
import '../editor/panels/effects_panel.dart' show PresetTile, SwatchSource;
import '../editor/panels/sticker_panel.dart' show StickerCatalog;
import '../editor/preview/grade_extras_box.dart';
import '../widgets/app_slider.dart';
import '../widgets/panel_shell.dart' show ChipStrip;
import 'widgets/crop_overlay.dart';

part 'panels/photo_panels.dart';

/// The photo editor: frame it, grade it, clean the face up, then put things
/// on top of it.
///
/// The grade is the video editor's own pipeline pointed at a single still —
/// the same [FilterLibrary] looks and the same [Adjustments] sliders — so a
/// photo and a clip given the same preset come out matching. The overlays are
/// the video editor's own layers for the same reason.
class ImageEditorScreen extends StatefulWidget {
  const ImageEditorScreen({super.key, required this.path});

  /// The photo to edit. It is never written to: saving produces a new file.
  final String path;

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

/// The bottom row, left to right, in the order a photo is usually worked.
enum _Tool {
  core,
  adjust,
  filter,
  face,
  markup,
  text,
  watermark,
  pixelate,
  retouch,
  sticker,
}

extension on _Tool {
  String get label => switch (this) {
    _Tool.core => 'Core',
    _Tool.adjust => 'Adjust',
    _Tool.filter => 'Filter',
    _Tool.face => 'AI Face',
    _Tool.markup => 'Markup',
    _Tool.text => 'Text',
    _Tool.watermark => 'Watermark',
    _Tool.pixelate => 'Pixelate',
    _Tool.retouch => 'Retouch',
    _Tool.sticker => 'Stickers',
  };

  IconData get icon => switch (this) {
    _Tool.core => Icons.crop_rotate,
    _Tool.adjust => Icons.tune,
    _Tool.filter => Icons.photo_filter,
    _Tool.face => Icons.face_retouching_natural,
    _Tool.markup => Icons.draw_outlined,
    _Tool.text => Icons.title,
    _Tool.watermark => Icons.branding_watermark_outlined,
    _Tool.pixelate => Icons.blur_on,
    _Tool.retouch => Icons.healing,
    _Tool.sticker => Icons.emoji_emotions_outlined,
  };

  /// Tools the user paints with: the stage hands them a stroke instead of a
  /// long-press comparison.
  bool get isBrush =>
      this == _Tool.markup || this == _Tool.pixelate || this == _Tool.retouch;

  /// Tools that place something on the picture and then let it be dragged,
  /// pinched and turned.
  bool get isOverlay =>
      this == _Tool.text ||
      this == _Tool.sticker ||
      this == _Tool.watermark;
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  /// The stage never needs more pixels than a screen has; the file is
  /// re-decoded at full size only when the edit is saved.
  static const int _previewMaxSide = 1600;

  PhotoEdit _edit = PhotoEdit();

  /// The last committed state, and the two stacks either side of it. Slider
  /// drags mutate [_edit] live and commit once on release, so an undo steps
  /// back a whole gesture rather than one frame of one.
  PhotoEdit _committed = PhotoEdit();
  final List<PhotoEdit> _undo = [];
  final List<PhotoEdit> _redo = [];

  ui.Image? _image;

  /// Where the skin is, found once when the photo opens. The face tools are
  /// gated on it: without one there is no face to retouch.
  ui.Image? _skinMask;
  bool _lookingForSkin = false;

  /// The watermark logo, decoded so the stage can draw the mark itself rather
  /// than a placeholder for it. [_logoPath] is what it was decoded from.
  ui.Image? _logo;
  String? _logoPath;

  bool _loading = true;
  bool _saving = false;
  bool _comparing = false;
  bool _saved = false;
  _Tool _tool = _Tool.core;
  int _filterCategory = 0;

  /// The overlay the stage is acting on, by id — 'watermark' for the mark.
  String? _selected;

  /// The stroke under the finger. It is already in the edit's own list, so
  /// the picture draws it as it is made; this only marks where to add points.
  PhotoStroke? _live;

  // The brushes themselves. These describe the tool rather than the picture,
  // so they sit outside [PhotoEdit] and outside the undo stack with it.
  int _inkColor = 0xFFFF3B30;
  double _inkWidth = 0.012;
  bool _erasing = false;
  double _pixelBrush = 0.07;
  double _retouchBrush = 0.05;

  int _textCategory = 0;
  int _stickerPack = 0;

  // Where the running pinch was on the last frame, and whether it has moved
  // anything worth putting on the undo stack.
  double _gestureScale = 1;
  double _gestureRotation = 0;
  bool _gestureMoved = false;
  bool _gestureMissed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _image?.dispose();
    _skinMask?.dispose();
    _logo?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final image = await PhotoRenderer.decode(
      widget.path,
      maxSide: _previewMaxSide,
    );
    if (!mounted) {
      image?.dispose();
      return;
    }
    setState(() {
      _image = image;
      _loading = false;
    });
    if (image != null) _findSkin(image);
  }

  /// Looks for skin in the background: the editor is usable while it runs,
  /// and only the AI Face panel waits on the answer.
  Future<void> _findSkin(ui.Image image) async {
    setState(() => _lookingForSkin = true);
    final mask = await FaceEnhancer.skinMask(image);
    if (!mounted) {
      mask?.dispose();
      return;
    }
    setState(() {
      _skinMask?.dispose();
      _skinMask = mask;
      _lookingForSkin = false;
    });
  }

  /// Keeps [_logo] in step with whatever logo the watermark points at —
  /// including after an undo, which can swap one back in.
  Future<void> _syncLogo() async {
    final path = _edit.watermark.imagePath;
    if (path == _logoPath) return;
    final image = (path == null || path.isEmpty)
        ? null
        : await PhotoRenderer.decode(path, maxSide: 1024);
    if (!mounted) {
      image?.dispose();
      return;
    }
    setState(() {
      _logo?.dispose();
      _logo = image;
      _logoPath = path;
    });
  }

  // ---------------------------------------------------------------- history

  /// Remembers the state a change is about to leave behind.
  void _remember() {
    _undo.add(_committed);
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
  }

  /// Call after a gesture that mutated [_edit] in place — a slider release.
  void _commit() {
    setState(() {
      _remember();
      _committed = _edit.copy();
    });
  }

  void _undoOnce() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_edit.copy());
      _edit = _undo.removeLast();
      _committed = _edit.copy();
      _saved = false;
      _live = null;
    });
    _afterChange();
  }

  void _redoOnce() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_edit.copy());
      _edit = _redo.removeLast();
      _committed = _edit.copy();
      _saved = false;
      _live = null;
    });
    _afterChange();
  }

  /// A change made and committed in one go — a button, a chip, a preset.
  void _edited(VoidCallback change) {
    setState(() {
      _remember();
      change();
      _committed = _edit.copy();
      _saved = false;
    });
    _afterChange();
  }

  /// Housekeeping after the edit has been swapped or mutated: the logo the
  /// stage draws, and a selection that may have just been deleted or undone
  /// out of existence.
  void _afterChange() {
    _syncLogo();
    if (_selected != null && _edit.overlayById(_selected) == null) {
      setState(() => _selected = null);
    }
  }

  /// A change to the tool rather than to the picture — a brush colour, a
  /// category chip. Nothing here belongs on the undo stack, and nothing here
  /// makes a saved photo stale.
  void _refresh(VoidCallback change) => setState(change);

  /// A slider being dragged: live, and not yet on the undo stack.
  void _dragging(VoidCallback change) {
    setState(() {
      change();
      _saved = false;
    });
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // The screen ends in the tool row, so the navigation bar takes its
        // fill — the same handover the video editor makes.
        value: const SystemUiOverlayStyle(
          systemNavigationBarColor: AppColors.surface,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          // The editor's own fill: the photo sits on the page rather than in
          // a dark box of its own, so the two screens read as one app.
          backgroundColor: AppColors.surface,
          appBar: _appBar(context),
          body: Column(
            children: [
              Expanded(child: _stage()),
              _tools(context),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    final r = context.r;
    return AppBar(
      leading: IconButton(
        icon: Icon(Icons.close, size: r.ic(22)),
        tooltip: 'Close',
        onPressed: _close,
      ),
      titleSpacing: 0,
      title: const Text('Image Edit'),
      actions: [
        IconButton(
          tooltip: 'Undo',
          icon: Icon(Icons.undo, size: r.ic(20)),
          onPressed: _undo.isEmpty ? null : _undoOnce,
        ),
        IconButton(
          tooltip: 'Redo',
          icon: Icon(Icons.redo, size: r.ic(20)),
          onPressed: _redo.isEmpty ? null : _redoOnce,
        ),
        Padding(
          padding: EdgeInsets.only(right: r.dp(10)),
          child: InkWell(
            onTap: _image == null || _saving ? null : _save,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              height: math.min(r.dp(33), kAppBarHeight - 12),
              padding: EdgeInsets.symmetric(horizontal: r.dp(13)),
              alignment: Alignment.center,
              // The button sits inside the dark bar, so it inverts the pair
              // the rest of the app uses — the same light pill the editor's
              // Export button is.
              decoration: BoxDecoration(
                color: _saved
                    ? AppColors.onAppBar.withValues(alpha: 0.12)
                    : AppColors.onAppBar,
                borderRadius: BorderRadius.circular(11),
                border: _saved
                    ? Border.all(
                        color: AppColors.onAppBar.withValues(alpha: 0.24),
                      )
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _saved ? Icons.check : Icons.save_alt,
                    size: r.ic(15),
                    color: _saved ? AppColors.onAppBar : AppColors.appBar,
                  ),
                  SizedBox(width: r.dp(6)),
                  Text(
                    _saved ? 'Saved' : 'Save',
                    style: TextStyle(
                      fontSize: r.sp(12),
                      fontWeight: FontWeight.w800,
                      color: _saved ? AppColors.onAppBar : AppColors.appBar,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ stage

  Widget _stage() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 2,
        ),
      );
    }
    final image = _image;
    if (image == null) return _unreadable();

    return LayoutBuilder(
      builder: (context, c) {
        final r = context.r;
        final inset = EdgeInsets.all(r.dp(14));
        final box = Size(
          math.max(1, c.maxWidth - inset.horizontal),
          math.max(1, c.maxHeight - inset.vertical),
        );
        final cropping = _tool == _Tool.core;
        // Comparing shows the photo exactly as it arrived, which is the point
        // of holding the picture down.
        final edit = _comparing ? PhotoEdit() : _edit;
        final aspect = cropping
            ? PhotoRenderer.fullAspect(image, edit)
            : PhotoRenderer.aspectOf(image, edit);
        final rect = _fit(aspect, box).translate(inset.left, inset.top);

        Widget media = CustomPaint(
          painter: _PhotoPainter(
            image: image,
            edit: edit,
            cropped: !cropping,
            skinMask: _skinMask,
          ),
          size: rect.size,
        );
        // The half of the grade that needs a shader — gamma, the tone curve,
        // sharpening and denoise. Grain is not in it: the texture painter
        // scatters that, so it reads the same in this preview and in the
        // full-size file.
        final shaderAdj = edit.adjustments.copy()..grain = 0;
        if (GradeExtrasBox.wanted(shaderAdj, edit.grade.gamma)) {
          media = GradeExtrasBox(
            adjustments: shaderAdj,
            gamma: edit.grade.gamma,
            seed: 0,
            child: media,
          );
        }

        // Long-pressing the picture shows the original, which would fight
        // every tool that wants the finger for itself.
        final canCompare = !cropping && !_tool.isBrush && !_tool.isOverlay;
        final selected = _tool.isOverlay
            ? _edit.overlayById(_selected)
            : null;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: canCompare
              ? (_) => setState(() => _comparing = true)
              : null,
          onLongPressEnd: canCompare
              ? (_) => setState(() => _comparing = false)
              : null,
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: RepaintBoundary(child: media),
              ),
              if (!cropping)
                Positioned.fromRect(
                  rect: rect,
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _DecorPainter(edit, _logo),
                        size: rect.size,
                      ),
                    ),
                  ),
                ),
              if (selected != null)
                Positioned.fromRect(
                  rect: rect,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SelectionPainter(selected, _logo),
                      size: rect.size,
                    ),
                  ),
                ),
              if (cropping)
                Positioned.fromRect(
                  rect: rect,
                  child: CropOverlay(
                    rect: _cropRect,
                    aspect: _edit.cropAspect,
                    onChanged: (v) => _dragging(() => _setCropRect(v)),
                    onCommit: _commit,
                  ),
                ),
              if (_tool.isBrush)
                Positioned.fromRect(
                  rect: rect,
                  child: _brushSurface(rect.size),
                ),
              if (_tool.isOverlay)
                Positioned.fromRect(
                  rect: rect,
                  child: _overlaySurface(rect.size),
                ),
              if (_comparing)
                Positioned(
                  left: rect.left + 8,
                  top: rect.top + 8,
                  child: _badge('Original'),
                ),
              if (_saving)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x99000000),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accentDim,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _unreadable() {
    final r = context.r;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(r.dp(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: r.ic(34),
              color: AppColors.textFaint,
            ),
            SizedBox(height: r.vp(10)),
            Text(
              'That photo could not be opened',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: r.sp(12.5),
                color: AppColors.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text) {
    final r = context.r;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.dp(9), vertical: r.vp(4)),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: r.sp(10.5),
          fontWeight: FontWeight.w700,
          color: AppColors.onAppBar,
        ),
      ),
    );
  }

  /// The largest box of [aspect] that fits inside [box], centred in it.
  Rect _fit(double aspect, Size box) {
    var w = box.width, h = w / aspect;
    if (h > box.height) {
      h = box.height;
      w = h * aspect;
    }
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  Rect get _cropRect => Rect.fromLTRB(
    _edit.cropLeft,
    _edit.cropTop,
    1 - _edit.cropRight,
    1 - _edit.cropBottom,
  );

  void _setCropRect(Rect r) =>
      _edit.setCrop(r.left, r.top, 1 - r.right, 1 - r.bottom);


  // --------------------------------------------------------- stage gestures

  /// Which list the current brush paints into.
  List<PhotoStroke>? get _brushTarget => switch (_tool) {
    _Tool.markup => _edit.markup,
    _Tool.pixelate => _edit.pixelate,
    _Tool.retouch => _edit.retouch,
    _ => null,
  };

  double get _brushWidth => switch (_tool) {
    _Tool.pixelate => _pixelBrush,
    _Tool.retouch => _retouchBrush,
    _ => _inkWidth,
  };

  /// The surface the three brushes draw on. A tap leaves a dot, which is what
  /// a finger asking to hide one number plate actually does.
  Widget _brushSurface(Size size) {
    return GestureDetector(
      // Keyed so a test can find the picture's own rectangle and draw on it
      // in the coordinates the strokes are actually stored in.
      key: const ValueKey('photo-brush'),
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _strokeStart(d.localPosition, size),
      onTapUp: (_) => _strokeEnd(),
      onTapCancel: _strokeEnd,
      onPanStart: (d) => _strokeStart(d.localPosition, size),
      onPanUpdate: (d) => _strokeMove(d.localPosition, size),
      onPanEnd: (_) => _strokeEnd(),
      onPanCancel: _strokeEnd,
    );
  }

  /// The stroke joins the edit as it is drawn, so the picture shows it under
  /// the finger; the undo stack only hears about it when the finger lifts.
  void _strokeStart(Offset point, Size size) {
    final target = _brushTarget;
    if (target == null || _live != null) return;
    final stroke = PhotoStroke(
      color: _inkColor,
      width: _brushWidth,
      erase: _tool == _Tool.markup && _erasing,
    )..points.add(_normalise(point, size));
    setState(() {
      target.add(stroke);
      _live = stroke;
      _saved = false;
    });
  }

  void _strokeMove(Offset point, Size size) {
    final live = _live;
    if (live == null) return;
    final p = _normalise(point, size);
    // A stroke of a thousand near-identical points costs a repaint and buys
    // nothing the curve does not already say.
    if (live.points.isNotEmpty && (live.points.last - p).distance < 0.004) {
      return;
    }
    setState(() => live.points.add(p));
  }

  void _strokeEnd() {
    if (_live == null) return;
    _live = null;
    _commit();
  }

  Offset _normalise(Offset p, Size size) => Offset(
    (p.dx / math.max(1, size.width)).clamp(0.0, 1.0),
    (p.dy / math.max(1, size.height)).clamp(0.0, 1.0),
  );

  /// Drag to move, pinch to size and turn. One detector covers both: a
  /// one-finger drag is a scale gesture whose scale never leaves 1.
  Widget _overlaySurface(Size size) {
    return GestureDetector(
      key: const ValueKey('photo-overlay'),
      behavior: HitTestBehavior.opaque,
      onScaleStart: (d) {
        _gestureScale = 1;
        _gestureRotation = 0;
        _gestureMoved = false;
        _gestureMissed = !_selectAt(d.localFocalPoint, size);
      },
      onScaleUpdate: (d) => _dragSelected(d, size),
      onScaleEnd: (_) {
        if (_gestureMoved) {
          _commit();
        } else if (_gestureMissed && _selected != null) {
          // A tap on bare picture puts the overlay down; a *drag* from bare
          // picture still moves it, because a finger that lands a few pixels
          // outside a caption meant to drag the caption.
          setState(() => _selected = null);
        }
        _gestureMoved = false;
      },
    );
  }

  /// Picks the topmost overlay of the open tool's own kind under [point], and
  /// reports whether anything was there. A tool only ever moves what it is
  /// for, so the Text tool cannot nudge a sticker the user is not looking at.
  bool _selectAt(Offset point, Size size) {
    final candidates = [
      for (final o in _edit.overlays)
        if (_toolOwns(_tool, o)) o,
    ].reversed;
    for (final overlay in candidates) {
      if (PhotoRenderer.hitTest(
        size,
        overlay,
        point,
        logo: _logo,
        slop: 12,
      )) {
        final id = _overlayId(overlay);
        if (id != _selected) setState(() => _selected = id);
        return true;
      }
    }
    return false;
  }

  bool _toolOwns(_Tool tool, Object overlay) => switch (tool) {
    _Tool.text => overlay is TextLayer,
    _Tool.sticker => overlay is StickerLayer,
    _Tool.watermark => overlay is Watermark,
    _ => false,
  };

  String? _overlayId(Object overlay) => switch (overlay) {
    TextLayer l => l.id,
    StickerLayer l => l.id,
    Watermark _ => 'watermark',
    _ => null,
  };

  void _dragSelected(ScaleUpdateDetails d, Size size) {
    final transform = PhotoRenderer.transformOf(_edit.overlayById(_selected));
    if (transform == null) return;
    setState(() {
      // A little overhang is allowed: a mark is often meant to sit half off
      // the edge of the picture.
      transform.x = (transform.x + d.focalPointDelta.dx / size.width).clamp(
        -0.2,
        1.2,
      );
      transform.y = (transform.y + d.focalPointDelta.dy / size.height).clamp(
        -0.2,
        1.2,
      );
      if (d.pointerCount > 1) {
        if (_gestureScale > 0) {
          transform.scale = (transform.scale * (d.scale / _gestureScale)).clamp(
            0.1,
            8.0,
          );
        }
        transform.rotation += d.rotation - _gestureRotation;
        _gestureScale = d.scale;
        _gestureRotation = d.rotation;
      }
      _gestureMoved = true;
      _saved = false;
    });
  }

  // ------------------------------------------------------------------ tools

  Widget _tools(BuildContext context) {
    final r = context.r;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        // The same hairline the editor's toolbar draws now that the stage
        // above shares this fill.
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: math.min(r.vp(_tall ? 212 : 178), r.height * 0.38),
              child: SingleChildScrollView(
                child: switch (_tool) {
                  _Tool.core => _cropTools(),
                  _Tool.filter => _filterTools(),
                  _Tool.adjust => _adjustTools(),
                  _Tool.face => _faceTools(),
                  _Tool.markup => _markupTools(),
                  _Tool.text => _textTools(),
                  _Tool.watermark => _watermarkTools(),
                  _Tool.pixelate => _pixelateTools(),
                  _Tool.retouch => _retouchTools(),
                  _Tool.sticker => _stickerTools(),
                },
              ),
            ),
            const Divider(height: 1),
            _toolBar(),
          ],
        ),
      ),
    );
  }

  /// The panels that carry a picker as well as sliders need the extra room.
  bool get _tall =>
      _tool == _Tool.text ||
      _tool == _Tool.sticker ||
      _tool == _Tool.watermark;

  /// The row of tools along the bottom. It takes its height from what is in
  /// it rather than a constant, so a large system font grows the row instead
  /// of clipping the labels off the bottom of it.
  Widget _toolBar() {
    final r = context.r;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: r.dp(6), vertical: r.vp(9)),
      child: Row(
        children: [
          for (final tool in _Tool.values)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() {
                _tool = tool;
                _live = null;
                // The frame follows the tool: the Stickers tool should not
                // leave a box drawn round a caption it cannot move.
                final selected = _edit.overlayById(_selected);
                if (selected == null || !_toolOwns(tool, selected)) {
                  _selected = null;
                }
              }),
              child: SizedBox(
                width: math.max(r.dp(72), 64),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tool.icon,
                      size: r.ic(21),
                      color: tool == _tool
                          ? AppColors.accent
                          : AppColors.textDim,
                    ),
                    SizedBox(height: r.vp(4)),
                    Text(
                      tool.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: r.sp(10.5),
                        fontWeight: tool == _tool
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: tool == _tool
                            ? AppColors.accent
                            : AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- crop tools

  Widget _cropTools() {
    final r = context.r;
    final ratios = CropRatio.all;
    final selected = math.max(
      0,
      ratios.indexWhere((c) => c.id == _edit.cropRatioId),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(10)),
        // A Wrap and not a Row: at the largest text size five labelled
        // buttons are wider than a 320pt phone, and the panel scrolls, so a
        // second line costs nothing while a clipped one costs a control.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: r.dp(4),
          runSpacing: r.vp(6),
          children: [
            _action(
              Icons.rotate_left,
              'Rotate',
              () => _edited(() => _edit.rotate(clockwise: false)),
            ),
            _action(
              Icons.rotate_right,
              'Rotate',
              () => _edited(() => _edit.rotate()),
            ),
            _action(
              Icons.flip,
              'Flip H',
              () => _edited(() => _edit.mirror(horizontal: true)),
            ),
            _action(
              Icons.flip_camera_android_outlined,
              'Flip V',
              () => _edited(() => _edit.mirror(horizontal: false)),
            ),
            _action(
              Icons.restart_alt,
              'Reset',
              () => _edited(() => _edit.resetCrop()),
            ),
          ],
        ),
        SizedBox(height: r.vp(12)),
        ChipStrip(
          labels: [for (final c in ratios) c.label],
          selectedIndex: selected,
          onSelected: (i) => _applyRatio(ratios[i]),
        ),
        SizedBox(height: r.vp(10)),
      ],
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    final r = context.r;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: r.dp(8), vertical: r.vp(6)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: r.dp(38),
              height: r.dp(38),
              decoration: BoxDecoration(
                gradient: AppColors.tint(AppColors.appBar),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.appBar.withValues(alpha: 0.16),
                ),
              ),
              child: Icon(icon, size: r.ic(19), color: AppColors.appBarMuted),
            ),
            SizedBox(height: r.vp(5)),
            Text(
              label,
              style: TextStyle(fontSize: r.sp(10), color: AppColors.textDim),
            ),
          ],
        ),
      ),
    );
  }

  /// Locks the rectangle to a ratio and re-frames it as the largest window of
  /// that shape the photo can hold, centred — the ratio row is a shortcut,
  /// not one more thing to drag into place.
  void _applyRatio(CropRatio ratio) {
    final image = _image;
    if (image == null) return;
    _edited(() {
      _edit.cropRatioId = ratio.id;
      final full = PhotoRenderer.fullAspect(image, _edit);
      final target = ratio.original ? full : ratio.value;
      _edit.cropAspect = target;
      if (target == null || target <= 0) return;
      var w = 1.0, h = 1.0;
      if (target > full) {
        h = full / target;
      } else {
        w = target / full;
      }
      _edit.setCrop((1 - w) / 2, (1 - h) / 2, (1 - w) / 2, (1 - h) / 2);
    });
  }

  // ----------------------------------------------------------- filter tools

  Widget _filterTools() {
    final categories = FilterLibrary.categories;
    final items = _filterCategory == 0
        ? FilterLibrary.all
        : FilterLibrary.byCategory(categories[_filterCategory]);
    return _presetTools(
      categories: categories,
      selectedCategory: _filterCategory,
      onCategory: (i) => setState(() => _filterCategory = i),
      count: items.length,
      idOf: (i) => items[i].id,
      nameOf: (i) => items[i].name,
      activeId: _edit.filterId,
      onPick: (i) => _edited(() {
        _edit.filterId = items[i].id;
        _edit.filterIntensity = 1;
      }),
      preview: (i) => ColorFiltered(
        colorFilter: ColorFilter.matrix(items[i].toColorMatrix()),
        child: SwatchSource(path: widget.path),
      ),
      slider: _edit.filterId == 'none'
          ? null
          : AppSlider(
              label: 'Intensity',
              value: _edit.filterIntensity,
              min: 0,
              max: 1,
              defaultValue: 1,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => _dragging(() => _edit.filterIntensity = v),
              onChangeEnd: (_) => _commit(),
            ),
    );
  }

  /// The shape the filter tab is built from: category pills over a strip of
  /// live swatches cut from the user's own photo, with an optional strength
  /// slider under it.
  Widget _presetTools({
    required List<String> categories,
    required int selectedCategory,
    required ValueChanged<int> onCategory,
    required int count,
    required String Function(int) idOf,
    required String Function(int) nameOf,
    required String activeId,
    required ValueChanged<int> onPick,
    required Widget Function(int) preview,
    Widget? slider,
  }) {
    final r = context.r;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(8)),
        ChipStrip(
          labels: categories,
          selectedIndex: selectedCategory,
          onSelected: onCategory,
        ),
        SizedBox(height: r.vp(10)),
        SizedBox(
          // The swatch, the gap and the name at the system font scale.
          height: math.max(
            r.vp(76),
            54 + MediaQuery.textScalerOf(context).scale(r.sp(9.5)) * 1.7,
          ),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: r.dp(14)),
            itemCount: count,
            separatorBuilder: (_, _) => SizedBox(width: r.dp(9)),
            itemBuilder: (context, i) => PresetTile(
              label: nameOf(i),
              active: idOf(i) == activeId,
              onTap: () => onPick(i),
              child: preview(i),
            ),
          ),
        ),
        ?slider,
        SizedBox(height: r.vp(8)),
      ],
    );
  }

  // ----------------------------------------------------------- adjust tools

  Widget _adjustTools() {
    final adj = _edit.adjustments;

    Widget bipolar(
      String label,
      IconData icon,
      double value,
      void Function(Adjustments, double) apply,
    ) => AppSlider(
      label: label,
      icon: icon,
      value: value,
      min: -1,
      max: 1,
      bipolar: true,
      defaultValue: 0,
      format: (v) => (v * 100).round().toString(),
      onChanged: (v) => _dragging(() => apply(adj, v)),
      onChangeEnd: (_) => _commit(),
    );

    Widget unipolar(
      String label,
      IconData icon,
      double value,
      void Function(Adjustments, double) apply,
    ) => AppSlider(
      label: label,
      icon: icon,
      value: value,
      min: 0,
      max: 1,
      defaultValue: 0,
      format: (v) => (v * 100).round().toString(),
      onChanged: (v) => _dragging(() => apply(adj, v)),
      onChangeEnd: (_) => _commit(),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        bipolar(
          'Brightness',
          Icons.brightness_6,
          adj.brightness,
          (a, v) => a.brightness = v,
        ),
        bipolar(
          'Contrast',
          Icons.contrast,
          adj.contrast,
          (a, v) => a.contrast = v,
        ),
        bipolar(
          'Saturation',
          Icons.water_drop_outlined,
          adj.saturation,
          (a, v) => a.saturation = v,
        ),
        bipolar(
          'Temperature',
          Icons.thermostat,
          adj.temperature,
          (a, v) => a.temperature = v,
        ),
        bipolar('Tint', Icons.colorize, adj.tint, (a, v) => a.tint = v),
        bipolar(
          'Highlights',
          Icons.wb_sunny_outlined,
          adj.highlights,
          (a, v) => a.highlights = v,
        ),
        bipolar(
          'Shadows',
          Icons.nightlight_outlined,
          adj.shadows,
          (a, v) => a.shadows = v,
        ),
        bipolar('Hue', Icons.palette_outlined, adj.hue, (a, v) => a.hue = v),
        const Divider(height: 18),
        bipolar(
          'Curve Low',
          Icons.south,
          adj.curveLow,
          (a, v) => a.curveLow = v,
        ),
        bipolar(
          'Curve Mid',
          Icons.horizontal_rule,
          adj.curveMid,
          (a, v) => a.curveMid = v,
        ),
        bipolar(
          'Curve High',
          Icons.north,
          adj.curveHigh,
          (a, v) => a.curveHigh = v,
        ),
        const Divider(height: 18),
        unipolar(
          'Sharpen',
          Icons.details,
          adj.sharpen,
          (a, v) => a.sharpen = v,
        ),
        unipolar(
          'Vignette',
          Icons.vignette_outlined,
          adj.vignette,
          (a, v) => a.vignette = v,
        ),
        unipolar('Fade', Icons.gradient, adj.fade, (a, v) => a.fade = v),
        unipolar('Grain', Icons.grain, adj.grain, (a, v) => a.grain = v),
        unipolar('Blur', Icons.blur_circular, adj.blur, (a, v) => a.blur = v),
        unipolar(
          'Denoise',
          Icons.cleaning_services_outlined,
          adj.denoise,
          (a, v) => a.denoise = v,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _edited(() => _edit.adjustments.reset()),
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('Reset adjustments'),
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- saving

  Future<void> _save() async {
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);

    String? saved;
    String? failure;
    ui.Image? full;
    try {
      // The preview runs on a downscaled copy; the file gets every pixel the
      // photo actually has.
      full = await PhotoRenderer.decode(widget.path);
      final source = full ?? _image;
      if (source == null) {
        failure = 'That photo could not be opened';
      } else {
        final dir = await ProjectRepository.instance.exportDir();
        final stamp = DateTime.now().millisecondsSinceEpoch;
        saved = await PhotoRenderer.renderToFile(
          source,
          _edit,
          path: '${dir.path}/photo_$stamp.png',
          skinMask: _skinMask,
        );
        failure = saved == null ? 'Could not render the photo' : null;
      }
    } catch (e) {
      failure = 'Could not render the photo: $e';
    } finally {
      full?.dispose();
    }

    String message;
    if (saved == null) {
      message = failure ?? 'Save failed';
    } else {
      message = await _toGallery(saved)
          ? 'Saved to your gallery'
          : 'Saved to $saved';
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = saved != null;
    });
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Puts the rendered file in the same album the video exporter uses. A
  /// refused permission is not an error worth a dialog — the file is already
  /// written, so we just say where it went.
  Future<bool> _toGallery(String path) async {
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        await Gal.requestAccess(toAlbum: true);
      }
      await Gal.putImage(path, album: 'Video Editor');
      return true;
    } catch (e) {
      debugPrint('gallery save failed: $e');
      return false;
    }
  }

  Future<void> _close() async {
    final navigator = Navigator.of(context);
    if (_edit.isClean || _saved) {
      navigator.pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard edits?'),
        content: const Text('This photo has changes that have not been saved.'),
        actions: [
          TextButton(
            style: AppTheme.outlinedAction(),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            style: AppTheme.outlinedAction(tone: AppColors.dangerSoft),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (leave == true) navigator.pop();
  }
}

/// The picture itself. [PhotoEdit] is mutated in place while a slider moves,
/// so this repaints whenever the screen rebuilds rather than trying to spot
/// the change.
class _PhotoPainter extends CustomPainter {
  const _PhotoPainter({
    required this.image,
    required this.edit,
    required this.cropped,
    this.skinMask,
  });

  final ui.Image image;
  final PhotoEdit edit;
  final bool cropped;
  final ui.Image? skinMask;

  @override
  void paint(Canvas canvas, Size size) => PhotoRenderer.paintPicture(
    canvas,
    size,
    image,
    edit,
    cropped: cropped,
    skinMask: skinMask,
  );

  @override
  bool shouldRepaint(_PhotoPainter old) => true;
}

/// The grain, the FX texture and the frame, and then everything laid over
/// the picture — in the order the exporter stacks them.
class _DecorPainter extends CustomPainter {
  const _DecorPainter(this.edit, this.logo);

  final PhotoEdit edit;
  final ui.Image? logo;

  @override
  void paint(Canvas canvas, Size size) {
    PhotoRenderer.paintDecorations(canvas, size, edit);
    PhotoRenderer.paintOverlays(canvas, size, edit, logo: logo);
  }

  @override
  bool shouldRepaint(_DecorPainter old) => true;
}

/// The frame around the overlay the stage is acting on. It is drawn on the
/// picture rather than as a widget so it follows the layer's own rotation
/// without a second copy of the geometry.
class _SelectionPainter extends CustomPainter {
  const _SelectionPainter(this.overlay, this.logo);

  final Object overlay;
  final ui.Image? logo;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = PhotoRenderer.overlayRect(size, overlay, logo: logo);
    if (rect.isEmpty) return;
    final rotation = PhotoRenderer.transformOf(overlay)?.rotation ?? 0;
    final box = Rect.fromCenter(
      center: Offset.zero,
      width: rect.width + 10,
      height: rect.height + 10,
    );

    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    if (rotation != 0) canvas.rotate(rotation);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = AppColors.accent,
    );
    for (final corner in [
      box.topLeft,
      box.topRight,
      box.bottomLeft,
      box.bottomRight,
    ]) {
      canvas.drawCircle(corner, 3.6, Paint()..color = AppColors.accent);
      canvas.drawCircle(
        corner,
        3.6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SelectionPainter old) => true;
}
