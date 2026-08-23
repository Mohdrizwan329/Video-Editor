import 'dart:async';
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
import '../../data/models/enums.dart';
import '../../data/models/photo_edit.dart';
import '../../data/models/text_presets.dart';
import '../../data/models/watermark.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/services/face_enhancer.dart';
import '../../data/services/media_library.dart';
import '../../data/services/photo_cutout.dart';
import '../../data/services/photo_renderer.dart';
import '../editor/panels/effects_panel.dart' show PresetTile, SwatchSource;
import '../editor/panels/sticker_panel.dart' show StickerCatalog;
import '../editor/preview/grade_extras_box.dart';
import '../widgets/app_slider.dart';
import '../widgets/panel_shell.dart' show ChipStrip, PanelShell, TextTabStrip;
import '../widgets/panel_strip.dart';
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
/// The tools along the bottom, in the order the photo editor they are
/// modelled on puts them.
///
/// Crop and Rotate are two entries rather than one 'Core': they are the two
/// things a user reaches for most and burying the second inside the first
/// cost a tap and a guess. Watermark and Pixelate come after the divider —
/// they are ours, not on that bar, and the order the user knows should not
/// be shuffled to make room for them.
enum _Tool {
  canvas,
  filter,
  adjust,
  effect,
  portrait,
  sticker,
  text,
  pip,
  remove,
  enhance,
  cutout,
  mask,
  detail,
  doodle,
  reshape,
  replace,
  crop,
  rotate,
  watermark,
  pixelate,
}

extension on _Tool {
  String get label => switch (this) {
    _Tool.canvas => 'Canvas',
    _Tool.filter => 'Filter',
    _Tool.adjust => 'Adjust',
    _Tool.effect => 'Effect',
    _Tool.portrait => 'Portrait',
    _Tool.sticker => 'Sticker',
    _Tool.text => 'Text',
    _Tool.pip => 'PIP',
    _Tool.remove => 'Remove',
    _Tool.enhance => 'Enhance',
    _Tool.cutout => 'Cutout',
    _Tool.mask => 'Mask',
    _Tool.detail => 'Detail',
    _Tool.doodle => 'Doodle',
    _Tool.reshape => 'Reshape',
    _Tool.replace => 'Replace',
    _Tool.crop => 'Crop',
    _Tool.rotate => 'Rotate',
    _Tool.watermark => 'Watermark',
    _Tool.pixelate => 'Pixelate',
  };

  IconData get icon => switch (this) {
    _Tool.canvas => Icons.aspect_ratio,
    _Tool.filter => Icons.photo_filter,
    _Tool.adjust => Icons.tune,
    _Tool.effect => Icons.auto_awesome,
    _Tool.portrait => Icons.face_retouching_natural,
    _Tool.sticker => Icons.emoji_emotions_outlined,
    _Tool.text => Icons.title,
    _Tool.pip => Icons.picture_in_picture_alt_outlined,
    _Tool.remove => Icons.healing,
    _Tool.enhance => Icons.hd,
    _Tool.cutout => Icons.person_outline,
    _Tool.mask => Icons.crop_square,
    _Tool.detail => Icons.details,
    _Tool.doodle => Icons.draw_outlined,
    _Tool.reshape => Icons.transform,
    _Tool.replace => Icons.swap_horiz,
    _Tool.crop => Icons.crop,
    _Tool.rotate => Icons.rotate_right,
    _Tool.watermark => Icons.branding_watermark_outlined,
    _Tool.pixelate => Icons.blur_on,
  };

  /// Tools the user paints with: the stage hands them a stroke instead of a
  /// long-press comparison.
  bool get isBrush =>
      this == _Tool.doodle || this == _Tool.pixelate || this == _Tool.remove;

  /// Tools that place something on the picture and then let it be dragged,
  /// pinched and turned.
  bool get isOverlay =>
      this == _Tool.text ||
      this == _Tool.sticker ||
      this == _Tool.watermark ||
      this == _Tool.pip;

  /// Where the bar's own tools end and ours begin.
  bool get startsExtras => this == _Tool.watermark;
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  /// The stage never needs more pixels than a screen has; the file is
  /// re-decoded at full size only when the edit is saved.
  static const int _previewMaxSide = 1600;

  PhotoEdit _edit = PhotoEdit();

  /// The photo being edited. It starts as the one the screen was opened on
  /// and the Replace tool swaps it, so it is state rather than the widget's
  /// own field.
  late String _path = widget.path;

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

  /// The subject mask the Cutout pass baked, decoded so the stage can show
  /// the cut rather than promise it. Null until the pass has run.
  ui.Image? _cutoutMatte;
  bool _cuttingOut = false;

  /// Pictures the PIP tool has added, decoded once and kept by path.
  final Map<String, ui.Image> _pipImages = {};

  /// The watermark logo, decoded so the stage can draw the mark itself rather
  /// than a placeholder for it. [_logoPath] is what it was decoded from.
  ui.Image? _logo;
  String? _logoPath;

  bool _loading = true;
  bool _saving = false;
  bool _comparing = false;
  bool _saved = false;
  _Tool _tool = _Tool.crop;

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
    _panelScroll.dispose();
    _image?.dispose();
    _skinMask?.dispose();
    _logo?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final image = await PhotoRenderer.decode(_path, maxSide: _previewMaxSide);
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
          // The tools need to know what the window can spare before they
          // decide how tall to be, and `constraints` is the only honest
          // measure of that.
          body: LayoutBuilder(
            builder: (context, c) => Column(
              children: [
                Expanded(child: _stage()),
                _tools(context, c.maxHeight),
              ],
            ),
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
        final cropping = _tool == _Tool.crop;
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
            cutoutMatte: _cutoutMatte,
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
        final selected = _tool.isOverlay ? _edit.overlayById(_selected) : null;

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
                        painter: _DecorPainter(edit, _logo, _pipImages),
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
    _Tool.doodle => _edit.markup,
    _Tool.pixelate => _edit.pixelate,
    _Tool.remove => _edit.retouch,
    _ => null,
  };

  double get _brushWidth => switch (_tool) {
    _Tool.pixelate => _pixelBrush,
    _Tool.remove => _retouchBrush,
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
      erase: _tool == _Tool.doodle && _erasing,
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
      // A picture layer knows its own shape, so it is measured rather than
      // guessed at by the shared hit test.
      if (overlay is PhotoImageLayer) {
        final image = _pipImages[overlay.path];
        if (image == null) continue;
        if (PhotoRenderer.pipRect(
          size,
          overlay,
          image,
        ).inflate(12).contains(point)) {
          if (overlay.id != _selected) setState(() => _selected = overlay.id);
          return true;
        }
        continue;
      }
      if (PhotoRenderer.hitTest(size, overlay, point, logo: _logo, slop: 12)) {
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
    _Tool.pip => overlay is PhotoImageLayer,
    _ => false,
  };

  String? _overlayId(Object overlay) => switch (overlay) {
    TextLayer l => l.id,
    StickerLayer l => l.id,
    PhotoImageLayer l => l.id,
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

  /// What the photo keeps whatever the open tool asks for. Below this there
  /// is not enough picture left to judge an edit against.
  static const double _kMinStageHeight = 260;

  /// The panel's viewport. It never scrolls under a finger — it is only ever
  /// measured, to find out whether the open tool outruns the ceiling.
  final ScrollController _panelScroll = ScrollController();

  /// True once a laid-out frame has found more controls than the panel can
  /// show, which is what puts the 'More options' button on screen. Measured
  /// rather than guessed: the same tool overflows on a short phone and fits
  /// on a tall one.
  bool _panelOverflows = false;

  /// Whether the panel is showing. Closing it hands the whole window back to
  /// the picture; tapping any tool on the bar opens it again.
  bool _panelOpen = true;

  /// The open tool's controls, built once and used in both places — the
  /// panel and the sheet the button opens.
  Widget _toolControls() => switch (_tool) {
    _Tool.crop => _cropTools(),
    _Tool.filter => _filterTools(),
    _Tool.adjust => _adjustTools(),
    _Tool.portrait => _faceTools(),
    _Tool.doodle => _markupTools(),
    _Tool.text => _textTools(),
    _Tool.watermark => _watermarkTools(),
    _Tool.pixelate => _pixelateTools(),
    _Tool.remove => _retouchTools(),
    _Tool.canvas => _canvasTools(),
    _Tool.effect => _effectTools(),
    _Tool.pip => _pipTools(),
    _Tool.enhance => _enhanceTools(),
    _Tool.cutout => _cutoutTools(),
    _Tool.mask => _maskTools(),
    _Tool.detail => _detailTools(),
    _Tool.reshape => _reshapeTools(),
    _Tool.replace => _replaceTools(),
    _Tool.rotate => _rotateTools(),
    _Tool.sticker => _stickerTools(),
  };

  /// Reads the laid-out panel once the frame is done: how much of it is out
  /// of sight.
  void _measurePanel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_panelScroll.hasClients ||
          !_panelScroll.position.hasContentDimensions) {
        return;
      }
      final overflows = _panelScroll.position.maxScrollExtent > 0.5;
      if (overflows != _panelOverflows) {
        setState(() => _panelOverflows = overflows);
      }
    });
  }

  /// The same row for the sheet the button opens, so the two read as one
  /// tool rather than two screens.
  Widget _sheetHeader(BuildContext sheetContext) {
    final r = context.r;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: PanelShell.kHandleHeight,
          child: Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        SizedBox(
          height: math.max(r.vp(44), 44),
          child: Row(
            children: [
              SizedBox(width: r.dp(12)),
              Expanded(
                child: Text(
                  _tool.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: r.sp(13.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: Icon(Icons.close, size: r.ic(20)),
                color: AppColors.textDim,
                onPressed: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  /// The title row every sheet in the app carries: the tool's name, and the
  /// way out top right.
  ///
  /// Closing here puts the panel away and leaves the picture as it is —
  /// every control has already written what it does, so there is nothing to
  /// throw away and nothing to confirm.
  Widget _panelHeader(Responsive r) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: PanelShell.kHandleHeight,
          child: Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        SizedBox(
          height: math.max(r.vp(44), 44),
          child: Row(
            children: [
              SizedBox(width: r.dp(12)),
              Expanded(
                child: Text(
                  _tool.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: r.sp(13.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: Icon(Icons.close, size: r.ic(20)),
                color: AppColors.textDim,
                onPressed: () => setState(() => _panelOpen = false),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  /// The way to everything the panel had to leave out.
  Widget _moreToolsButton(Responsive r) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        SizedBox(
          height: math.max(r.vp(38), 36),
          width: double.infinity,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              shape: const RoundedRectangleBorder(),
            ),
            onPressed: _openMoreTools,
            icon: Icon(Icons.expand_less, size: r.ic(18)),
            label: Text(
              'More options',
              style: TextStyle(
                fontSize: r.sp(12.5),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Opens the whole tool in a sheet of its own.
  ///
  /// This one *is* allowed to scroll: it is a list the user asked for by
  /// name, and it opens most of the way up the window, so its scroll bar is
  /// a list's rather than a panel quietly hiding half of itself.
  Future<void> _openMoreTools() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(maxHeight: context.r.height * 0.85),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        // The controls are the panel's own, so a slider moved in here writes
        // to the same edit the panel behind it is showing.
        return StatefulBuilder(
          builder: (sheetContext, _) => SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetHeader(sheetContext),
                Flexible(child: SingleChildScrollView(child: _toolControls())),
              ],
            ),
          ),
        );
      },
    );
    if (mounted) setState(() {});
  }

  Widget _tools(BuildContext context, double available) {
    final r = context.r;
    _measurePanel();
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        // The app bar's colour, the same line the editor's sheets are edged
        // with — the stage above shares this fill, so the line is what marks
        // where the picture ends and the tools begin.
        border: Border(top: BorderSide(color: AppColors.appBar, width: 1.2)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The same height the video editor's sheets open at, worked
            // out by the same code: the two editors are one app, and a
            // panel that is one size in one of them and another size in the
            // other is a thing the user has to relearn on every screen.
            //
            // Past that height nothing scrolls: the panel clips, and what it
            // clipped is behind the button under it.
            if (_panelOpen) _panelHeader(r),
            if (_panelOpen)
              ConstrainedBox(
                key: const ValueKey('photo-panel'),
                constraints: BoxConstraints(
                  maxHeight: math.min(
                    PanelShell.bodyHeight(context),
                    math.max(available - _kMinStageHeight, r.vp(120)),
                  ),
                ),
                child: SingleChildScrollView(
                  controller: _panelScroll,
                  physics: const NeverScrollableScrollPhysics(),
                  child: _toolControls(),
                ),
              ),
            if (_panelOpen && _panelOverflows) _moreToolsButton(r),
            const Divider(height: 1),
            _toolBar(),
          ],
        ),
      ),
    );
  }

  /// The row of tools along the bottom. It takes its height from what is in
  /// it rather than a constant, so a large system font grows the row instead
  /// of clipping the labels off the bottom of it.
  Widget _toolBar() {
    final r = context.r;
    return SingleChildScrollView(
      key: const ValueKey('photo-toolbar'),
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: r.dp(6), vertical: r.vp(9)),
      child: Row(
        children: [
          for (final tool in _Tool.values) ...[
            // Ours start here. The line says so, rather than letting them
            // read as two more of the ones the user already knows.
            if (tool.startsExtras)
              Container(
                width: 1,
                height: r.dp(30),
                margin: EdgeInsets.symmetric(horizontal: r.dp(6)),
                color: AppColors.divider,
              ),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() {
                _tool = tool;
                _panelOpen = true;
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

  // ----------------------------------------------------------- rotate tools

  /// The turns and the mirrors, which used to be buried in the crop panel.
  /// They are the second thing a user reaches for after the crop itself, and
  /// a tool of their own is one tap rather than two and a hunt.
  Widget _rotateTools() {
    final r = context.r;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(10)),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: r.dp(4),
          runSpacing: r.vp(6),
          children: [
            _action(
              Icons.rotate_left,
              'Left',
              () => _edited(() => _edit.rotate(clockwise: false)),
            ),
            _action(
              Icons.rotate_right,
              'Right',
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
            _action(Icons.restart_alt, 'Reset', () {
              _edited(() {
                _edit.quarterTurns = 0;
                _edit.flipH = _edit.flipV = false;
              });
            }),
          ],
        ),
        SizedBox(height: r.vp(10)),
      ],
    );
  }

  // ----------------------------------------------------------- canvas tools

  /// The shape of the finished picture, and what fills it either side of a
  /// photo that does not have that shape.
  Widget _canvasTools() {
    final r = context.r;
    final ratios = CropRatio.all;
    final selected = math.max(
      0,
      ratios.indexWhere((c) => c.id == _edit.canvasRatioId),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(10)),
        ChipStrip(
          labels: [for (final c in ratios) c.label],
          selectedIndex: selected,
          onSelected: (i) => _edited(() {
            final ratio = ratios[i];
            _edit.canvasRatioId = ratio.id;
            // 'Free' here means the photo's own shape — there is nothing to
            // fill, so the backdrop goes away with it.
            _edit.canvasAspect = ratio.value;
          }),
        ),
        SizedBox(height: r.vp(10)),
        PanelStrip(
          alignment: WrapAlignment.center,
          children: [
            for (final c in _kCanvasColours)
              GestureDetector(
                onTap: () => _edited(() {
                  _edit.canvasBackground = c;
                  _edit.canvasBlurBackdrop = false;
                }),
                child: Container(
                  width: r.dp(30),
                  height: r.dp(30),
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          _edit.canvasBackground == c &&
                              !_edit.canvasBlurBackdrop
                          ? AppColors.accent
                          : AppColors.divider,
                      width:
                          _edit.canvasBackground == c &&
                              !_edit.canvasBlurBackdrop
                          ? 2.4
                          : 1,
                    ),
                  ),
                ),
              ),
            GestureDetector(
              onTap: () => _edited(
                () => _edit.canvasBlurBackdrop = !_edit.canvasBlurBackdrop,
              ),
              child: Container(
                width: r.dp(30),
                height: r.dp(30),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _edit.canvasBlurBackdrop
                        ? AppColors.accent
                        : AppColors.divider,
                    width: _edit.canvasBlurBackdrop ? 2.4 : 1,
                  ),
                ),
                child: Icon(
                  Icons.blur_on,
                  size: r.ic(16),
                  color: _edit.canvasBlurBackdrop
                      ? AppColors.accent
                      : AppColors.textDim,
                ),
              ),
            ),
          ],
        ),
        _hint(
          _edit.canvasAspect == null
              ? 'Pick a shape to put the photo in'
              : 'Tap a colour, or the blur, for what fills the sides',
        ),
        SizedBox(height: r.vp(8)),
      ],
    );
  }

  /// The fills the Canvas tool offers, kept next to the panel that draws
  /// them rather than in a shared palette: these are backgrounds, not ink.
  static const List<int> _kCanvasColours = [
    0xFFFFFFFF,
    0xFF000000,
    0xFFF2EFE6,
    0xFFE8D9C5,
    0xFFB8C4BB,
    0xFF9AA7C7,
    0xFFD9A7A7,
    0xFF2E2E38,
  ];

  // ----------------------------------------------------------- effect tools

  /// Effects stack on top of the look rather than replacing it, which is why
  /// this is a tool of its own and not another row in Filter.
  Widget _effectTools() {
    final r = context.r;
    const effects = <(String, String)>[
      ('none', 'None'),
      ('grain', 'Grain'),
      ('leak', 'Light leak'),
      ('glow', 'Glow'),
      ('vignette', 'Vignette'),
      ('dust', 'Dust'),
      ('chroma', 'Fringe'),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(10)),
        ChipStrip(
          labels: [for (final (_, label) in effects) label],
          selectedIndex: math.max(
            0,
            effects.indexWhere((e) => e.$1 == _edit.effectId),
          ),
          onSelected: (i) => _edited(() => _edit.effectId = effects[i].$1),
        ),
        if (_edit.effectId != 'none')
          AppSlider(
            label: 'Strength',
            icon: Icons.auto_awesome,
            value: _edit.effectIntensity,
            min: 0,
            max: 1,
            defaultValue: 0.7,
            format: (v) => (v * 100).round().toString(),
            onChanged: (v) => _dragging(() => _edit.effectIntensity = v),
            onChangeEnd: (v) => _edited(() => _edit.effectIntensity = v),
          )
        else
          _hint('Tap an effect to lay it over the picture'),
        SizedBox(height: r.vp(8)),
      ],
    );
  }

  // ---------------------------------------------------------- enhance tools

  /// One tap. There is nothing to tune here on purpose — a tool with a
  /// slider is a tool the user has to think about, and the whole point of
  /// this one is that they do not.
  Widget _enhanceTools() {
    final r = context.r;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(14)),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.symmetric(horizontal: r.dp(16)),
          dense: true,
          value: _edit.enhance,
          activeThumbColor: AppColors.accent,
          title: Text(
            'Enhance',
            style: TextStyle(fontSize: r.sp(12.5), fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'A little contrast, a little colour, a little sharpening',
            style: TextStyle(fontSize: r.sp(10.5), color: AppColors.textDim),
          ),
          onChanged: (v) => _edited(() => _edit.enhance = v),
        ),
        SizedBox(height: r.vp(10)),
      ],
    );
  }

  // ----------------------------------------------------------- detail tools

  /// Sharpening, noise and grain — the half of the grade a colour matrix
  /// cannot carry, and the half a user thinks of as 'detail' rather than as
  /// colour. The sliders are the Adjust panel's own, so the two never
  /// disagree about what a value means.
  Widget _detailTools() {
    final adj = _edit.adjustments;
    final r = context.r;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(6)),
        AppSlider(
          label: 'Sharpen',
          icon: Icons.details,
          value: adj.sharpen,
          min: 0,
          max: 1,
          defaultValue: 0,
          format: (v) => (v * 100).round().toString(),
          onChanged: (v) => _dragging(() => adj.sharpen = v),
          onChangeEnd: (v) => _edited(() => adj.sharpen = v),
        ),
        AppSlider(
          label: 'Noise reduction',
          icon: Icons.grain,
          value: adj.denoise,
          min: 0,
          max: 1,
          defaultValue: 0,
          format: (v) => (v * 100).round().toString(),
          onChanged: (v) => _dragging(() => adj.denoise = v),
          onChangeEnd: (v) => _edited(() => adj.denoise = v),
        ),
        AppSlider(
          label: 'Grain',
          icon: Icons.blur_linear,
          value: adj.grain,
          min: 0,
          max: 1,
          defaultValue: 0,
          format: (v) => (v * 100).round().toString(),
          onChanged: (v) => _dragging(() => adj.grain = v),
          onChangeEnd: (v) => _edited(() => adj.grain = v),
        ),
        SizedBox(height: r.vp(8)),
      ],
    );
  }

  // -------------------------------------------------------------- mask tools

  Widget _maskTools() {
    final r = context.r;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(8)),
        PanelStrip(
          alignment: WrapAlignment.center,
          gap: r.dp(10),
          runGap: r.vp(8),
          children: [
            for (final shape in MaskShape.values)
              GestureDetector(
                onTap: () => _edited(() => _edit.maskShape = shape),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: r.dp(42),
                      height: r.dp(38),
                      decoration: BoxDecoration(
                        color: _edit.maskShape == shape
                            ? AppColors.accent.withValues(alpha: 0.18)
                            : AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: _edit.maskShape == shape
                              ? AppColors.accent
                              : Colors.transparent,
                        ),
                      ),
                      child: Icon(
                        shape.icon,
                        size: r.ic(18),
                        color: _edit.maskShape == shape
                            ? AppColors.accent
                            : AppColors.textDim,
                      ),
                    ),
                    SizedBox(height: r.vp(3)),
                    Text(
                      shape.label,
                      style: TextStyle(
                        fontSize: r.sp(9),
                        color: _edit.maskShape == shape
                            ? AppColors.accent
                            : AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (_edit.hasMask) ...[
          AppSlider(
            label: 'Size',
            icon: Icons.photo_size_select_small,
            value: _edit.maskSize,
            min: 0.1,
            max: 1.4,
            defaultValue: 0.7,
            format: (v) => (v * 100).round().toString(),
            onChanged: (v) => _dragging(() => _edit.maskSize = v),
            onChangeEnd: (v) => _edited(() => _edit.maskSize = v),
          ),
          AppSlider(
            label: 'Feather',
            icon: Icons.blur_on,
            value: _edit.maskFeather,
            min: 0,
            max: 0.5,
            defaultValue: 0.1,
            format: (v) => (v * 100).round().toString(),
            onChanged: (v) => _dragging(() => _edit.maskFeather = v),
            onChangeEnd: (v) => _edited(() => _edit.maskFeather = v),
          ),
          AppSlider(
            label: 'Rotation',
            icon: Icons.rotate_right,
            value: _edit.maskRotation,
            min: -math.pi,
            max: math.pi,
            bipolar: true,
            defaultValue: 0,
            format: (v) => '${(v * 180 / math.pi).round()}°',
            onChanged: (v) => _dragging(() => _edit.maskRotation = v),
            onChangeEnd: (v) => _edited(() => _edit.maskRotation = v),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.symmetric(horizontal: r.dp(16)),
            dense: true,
            value: _edit.maskInverted,
            activeThumbColor: AppColors.accent,
            title: Text('Invert', style: TextStyle(fontSize: r.sp(12))),
            onChanged: (v) => _edited(() => _edit.maskInverted = v),
          ),
        ] else
          _hint('Pick a shape to show the photo through'),
        SizedBox(height: r.vp(8)),
      ],
    );
  }

  // ----------------------------------------------------------- reshape tools

  Widget _reshapeTools() {
    final r = context.r;
    if (_skinMask == null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: r.vp(22)),
        child: Text(
          _lookingForSkin
              ? 'Looking for a face…'
              : 'No face found in this photo',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: r.sp(11.5), color: AppColors.textDim),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(6)),
        AppSlider(
          label: 'Slim',
          icon: Icons.compress,
          value: _edit.reshapeSlim,
          min: -1,
          max: 1,
          bipolar: true,
          defaultValue: 0,
          format: (v) => (v * 100).round().toString(),
          onChanged: (v) => _dragging(() => _edit.reshapeSlim = v),
          onChangeEnd: (v) => _edited(() => _edit.reshapeSlim = v),
        ),
        AppSlider(
          label: 'Brighten',
          icon: Icons.remove_red_eye_outlined,
          value: _edit.reshapeEyes,
          min: -1,
          max: 1,
          bipolar: true,
          defaultValue: 0,
          format: (v) => (v * 100).round().toString(),
          onChanged: (v) => _dragging(() => _edit.reshapeEyes = v),
          onChangeEnd: (v) => _edited(() => _edit.reshapeEyes = v),
        ),
        AppSlider(
          label: 'Soften',
          icon: Icons.blur_circular,
          value: _edit.reshapeSmooth,
          min: 0,
          max: 1,
          defaultValue: 0,
          format: (v) => (v * 100).round().toString(),
          onChanged: (v) => _dragging(() => _edit.reshapeSmooth = v),
          onChangeEnd: (v) => _edited(() => _edit.reshapeSmooth = v),
        ),
        SizedBox(height: r.vp(8)),
      ],
    );
  }

  // --------------------------------------------------------------- PIP tools

  /// Pictures laid over this one. Each is dragged, pinched and turned on the
  /// stage like any other overlay, so the panel is only what the stage
  /// cannot say: add one, and how solid the chosen one is.
  Widget _pipTools() {
    final r = context.r;
    final layer = _edit.pips.where((p) => p.id == _selected).firstOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(10)),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: r.dp(4),
          runSpacing: r.vp(6),
          children: [
            _action(Icons.add_photo_alternate_outlined, 'Add', _addPip),
            if (layer != null)
              _action(
                Icons.delete_outline,
                'Remove',
                () => _edited(() {
                  _edit.pips.removeWhere((p) => p.id == layer.id);
                  _selected = null;
                }),
              ),
          ],
        ),
        if (layer == null)
          _hint(
            _edit.pips.isEmpty
                ? 'Add a picture to lay over this one'
                : 'Tap a picture on the photo to change it',
          )
        else ...[
          AppSlider(
            label: 'Opacity',
            icon: Icons.opacity,
            value: layer.transform.opacity,
            min: 0,
            max: 1,
            defaultValue: 1,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v) => _dragging(() => layer.transform.opacity = v),
            onChangeEnd: (v) => _edited(() => layer.transform.opacity = v),
          ),
          AppSlider(
            label: 'Corners',
            icon: Icons.rounded_corner,
            value: layer.corner,
            min: 0,
            max: 0.5,
            defaultValue: 0,
            format: (v) => (v * 100).round().toString(),
            onChanged: (v) => _dragging(() => layer.corner = v),
            onChangeEnd: (v) => _edited(() => layer.corner = v),
          ),
        ],
        SizedBox(height: r.vp(8)),
      ],
    );
  }

  Future<void> _addPip() async {
    final picked = await MediaLibrary.instance.pickFiles(
      allowMultiple: false,
      kind: PickKind.image,
    );
    if (picked.isEmpty || !mounted) return;
    final path = await picked.first.resolvePath();
    final image = path == null
        ? null
        : await PhotoRenderer.decode(path, maxSide: _previewMaxSide);
    if (image == null || path == null || !mounted) {
      _toast('That picture could not be opened');
      return;
    }
    _pipImages[path] = image;
    final layer = PhotoImageLayer(path: path);
    // Half the frame, in the middle: big enough to see, small enough that
    // the photo underneath is still the picture.
    layer.transform.scale = 0.5;
    _edited(() {
      _edit.pips.add(layer);
      _selected = layer.id;
    });
  }

  // ------------------------------------------------------------ cutout tools

  /// Knocks the background off the subject, using the same segmenter the
  /// video editor's Cutout uses — so a photo and a frame of video are cut
  /// the same way.
  Widget _cutoutTools() {
    final r = context.r;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(10)),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: r.dp(4),
          runSpacing: r.vp(6),
          children: [
            _action(
              Icons.person_outline,
              _cutoutMatte == null ? 'Cut out' : 'Redo',
              _cuttingOut ? () {} : _runCutout,
            ),
            if (_cutoutMatte != null)
              _action(
                _edit.cutoutOn ? Icons.visibility_off : Icons.visibility,
                _edit.cutoutOn ? 'Off' : 'On',
                () => _edited(() => _edit.cutoutOn = !_edit.cutoutOn),
              ),
          ],
        ),
        _hint(
          _cuttingOut
              ? 'Finding the subject…'
              : _cutoutMatte == null
              ? 'The pass runs once and is kept with the photo'
              : _edit.cutoutOn
              ? 'The background is off. Canvas fills what is behind it.'
              : 'The cut is ready — tap On to show it',
        ),
        SizedBox(height: r.vp(8)),
      ],
    );
  }

  Future<void> _runCutout() async {
    final image = _image;
    if (image == null || _cuttingOut) return;
    setState(() => _cuttingOut = true);
    try {
      final matte = await PhotoCutout.matteFor(image);
      if (!mounted) return;
      if (matte == null) {
        _toast('No clear subject found in this photo');
        return;
      }
      _cutoutMatte?.dispose();
      _cutoutMatte = matte;
      _edited(() {
        _edit.cutoutOn = true;
        // The matte lives in memory for this session; the flag is what the
        // undo stack carries.
        _edit.cutoutMattePath = 'memory';
      });
    } catch (e) {
      if (mounted) _toast('The cutout could not be run: $e');
    } finally {
      if (mounted) setState(() => _cuttingOut = false);
    }
  }

  // ----------------------------------------------------------- replace tools

  /// Swaps the photo under the edit, keeping everything that was done to it.
  ///
  /// The crop is dropped with the picture — a rectangle measured against one
  /// photo means nothing on another — but the look, the overlays and the
  /// brushes are what the user spent their time on and they stay.
  Widget _replaceTools() {
    final r = context.r;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: r.vp(10)),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: r.dp(4),
          runSpacing: r.vp(6),
          children: [
            _action(Icons.swap_horiz, 'Choose a photo', _replacePhoto),
          ],
        ),
        _hint('The look and the layers stay; the crop starts again'),
        SizedBox(height: r.vp(8)),
      ],
    );
  }

  Future<void> _replacePhoto() async {
    final picked = await MediaLibrary.instance.pickFiles(
      allowMultiple: false,
      kind: PickKind.image,
    );
    if (picked.isEmpty || !mounted) return;
    final path = await picked.first.resolvePath();
    final image = path == null
        ? null
        : await PhotoRenderer.decode(path, maxSide: _previewMaxSide);
    if (image == null || path == null || !mounted) {
      _toast('That photo could not be opened');
      return;
    }
    final old = _image;
    setState(() {
      _path = path;
      _image = image;
      _skinMask?.dispose();
      _skinMask = null;
      _cutoutMatte?.dispose();
      _cutoutMatte = null;
    });
    old?.dispose();
    _edited(() {
      _edit.resetCrop();
      _edit.cutoutOn = false;
      _edit.cutoutMattePath = null;
    });
    unawaited(_findSkin(image));
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// The line a tool shows when it has nothing to tune yet.
  Widget _hint(String text) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.dp(20), vertical: r.vp(12)),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: r.sp(11), color: AppColors.textDim),
      ),
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
        child: SwatchSource(path: _path),
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
        SizedBox(height: r.vp(6)),
        // Text tabs, not pills: there are a dozen categories and a pill is
        // twice the height of a word. Wrapped, the pills filled the panel on
        // their own and left no room for a single look — which is the one
        // thing the tool is for.
        TextTabStrip(
          labels: categories,
          selectedIndex: selectedCategory,
          onSelected: onCategory,
        ),
        // The strength of the chosen look goes above the looks, not under
        // them: the library runs past the fold, and a slider below it is a
        // slider the user has to open another sheet to reach — for the very
        // thing they have just picked.
        ?slider,
        SizedBox(height: r.vp(8)),
        // Wrapped rather than scrolled sideways, the way every strip in the
        // app is: what is on the panel is all of what the panel has, and the
        // lines past the fold are behind 'More options'.
        PanelStrip(
          gap: r.dp(9),
          runGap: r.vp(8),
          padding: EdgeInsets.symmetric(horizontal: r.dp(14)),
          children: [
            for (var i = 0; i < count; i++)
              PresetTile(
                label: nameOf(i),
                active: idOf(i) == activeId,
                onTap: () => onPick(i),
                child: preview(i),
              ),
          ],
        ),
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
      full = await PhotoRenderer.decode(_path);
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
          cutoutMatte: _cutoutMatte,
          pips: _pipImages,
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
    this.cutoutMatte,
  });

  final ui.Image image;
  final PhotoEdit edit;
  final bool cropped;
  final ui.Image? skinMask;
  final ui.Image? cutoutMatte;

  @override
  void paint(Canvas canvas, Size size) => PhotoRenderer.paintPicture(
    canvas,
    size,
    image,
    edit,
    cropped: cropped,
    skinMask: skinMask,
    cutoutMatte: cutoutMatte,
  );

  @override
  bool shouldRepaint(_PhotoPainter old) => true;
}

/// The grain, the FX texture and the frame, and then everything laid over
/// the picture — in the order the exporter stacks them.
class _DecorPainter extends CustomPainter {
  const _DecorPainter(this.edit, this.logo, this.pips);

  final PhotoEdit edit;
  final ui.Image? logo;

  /// The pictures the PIP tool added, by path. They are decoded once when
  /// they are chosen rather than on every paint.
  final Map<String, ui.Image> pips;

  @override
  void paint(Canvas canvas, Size size) {
    PhotoRenderer.paintDecorations(canvas, size, edit);
    PhotoRenderer.paintOverlays(canvas, size, edit, logo: logo, pips: pips);
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
