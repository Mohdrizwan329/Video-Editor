import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/models/adjustments.dart';
import '../../../data/models/hsl_grade.dart';
import '../../../data/models/layers.dart';
import '../../../data/repositories/adjust_layout_store.dart';
import '../../../data/services/auto_adjust.dart';
import '../../../data/services/thumbnail_service.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/app_slider.dart';
import '../../widgets/panel_shell.dart';
import 'color_tool_tabs.dart';
import 'curve_editor.dart';

/// One adjustable value on the Adjust row.
class _Knob {
  const _Knob(
    this.label,
    this.icon,
    this.read,
    this.write, {
    this.bipolar = true,
  });

  final String label;
  final IconData icon;
  final double Function(Adjustments) read;
  final void Function(Adjustments, double) write;

  /// Bipolar knobs run -1..1 from a centred zero; the rest run 0..1 from the
  /// left, because there is no such thing as negative grain.
  final bool bipolar;
}

/// Manual colour adjustments — the same values the renderer folds into the
/// FFmpeg `eq` chain. Targets a clip or an overlay, like the effects sheet.
///
/// Laid out the way the phone editors lay it out: the two colour tools as a
/// pill at the top, one slider for the knob in hand, and the knobs
/// themselves as a row of icons underneath. Seventeen sliders stacked in a
/// scroll — which is what this was — makes the user hunt for the one they
/// want and leaves no room for the picture they are grading.
class AdjustPanel extends StatefulWidget {
  const AdjustPanel({
    super.key,
    required this.editor,
    required this.onClose,
    this.clipIndex,
    this.overlay,
    this.onTool,
  });

  final EditorController editor;
  final VoidCallback onClose;

  /// Switches the sheet to the looks. Null leaves the pill off.
  final ValueChanged<ColorTool>? onTool;

  /// Exactly one of these is set.
  final int? clipIndex;
  final OverlayLayer? overlay;

  @override
  State<AdjustPanel> createState() => _AdjustPanelState();
}

class _AdjustPanelState extends State<AdjustPanel> {
  /// The row, in the order a phone editor puts it in: the tonal basics
  /// first, then the colour, then the texture. The last two are this
  /// editor's own and follow behind, the way the tool bar does it.
  static const List<_Knob> _knobs = [
    _Knob('Lightness', Icons.brightness_6, _rBrightness, _wBrightness),
    _Knob('Contrast', Icons.contrast, _rContrast, _wContrast),
    _Knob('Warmth', Icons.thermostat, _rTemperature, _wTemperature),
    _Knob('Tint', Icons.colorize, _rTint, _wTint),
    _Knob('Saturation', Icons.water_drop_outlined, _rSaturation, _wSaturation),
    _Knob('HSL', Icons.lens_blur, _rHslTouched, _wNothing),
    _Knob('Curves', Icons.show_chart, _rCurvesTouched, _wNothing),
    _Knob('Fade', Icons.gradient, _rFade, _wFade, bipolar: false),
    _Knob('Highlights', Icons.wb_sunny_outlined, _rHighlights, _wHighlights),
    _Knob('Shadows', Icons.nightlight_outlined, _rShadows, _wShadows),
    _Knob('Color', Icons.format_color_fill, _rColorCast, _wNothing),
    _Knob('Hue', Icons.palette_outlined, _rHue, _wHue),
    _Knob(
      'Vignette',
      Icons.vignette_outlined,
      _rVignette,
      _wVignette,
      bipolar: false,
    ),
    _Knob('Sharpen', Icons.details, _rSharpen, _wSharpen, bipolar: false),
    _Knob('Grain', Icons.grain, _rGrain, _wGrain, bipolar: false),
    _Knob(
      'Film Grain',
      Icons.movie_filter_outlined,
      _rFilmGrain,
      _wFilmGrain,
      bipolar: false,
    ),
    _Knob('Blur', Icons.blur_circular, _rBlur, _wBlur, bipolar: false),
    _Knob(
      'Denoise',
      Icons.cleaning_services_outlined,
      _rDenoise,
      _wDenoise,
      bipolar: false,
    ),
  ];

  /// HSL has no single value of its own — the row only needs to know whether
  /// anything under it has been touched, so the dot can say so.
  static double _rHslTouched(Adjustments a) => a.hsl.isNeutral ? 0 : 1;
  static void _wNothing(Adjustments a, double v) {}

  /// Color has a hue as well as a strength, so like HSL the row only asks
  /// whether it has been touched.
  static double _rColorCast(Adjustments a) => a.colorCastAmount;

  static double _rBrightness(Adjustments a) => a.brightness;
  static void _wBrightness(Adjustments a, double v) => a.brightness = v;
  static double _rContrast(Adjustments a) => a.contrast;
  static void _wContrast(Adjustments a, double v) => a.contrast = v;
  static double _rTemperature(Adjustments a) => a.temperature;
  static void _wTemperature(Adjustments a, double v) => a.temperature = v;
  static double _rTint(Adjustments a) => a.tint;
  static void _wTint(Adjustments a, double v) => a.tint = v;
  static double _rSaturation(Adjustments a) => a.saturation;
  static void _wSaturation(Adjustments a, double v) => a.saturation = v;

  /// Curves has no single value either — the row only needs to know whether
  /// the shape has been bent, so the dot can say so.
  static double _rCurvesTouched(Adjustments a) => a.hasCurves ? 1 : 0;
  static double _rFade(Adjustments a) => a.fade;
  static void _wFade(Adjustments a, double v) => a.fade = v;
  static double _rHighlights(Adjustments a) => a.highlights;
  static void _wHighlights(Adjustments a, double v) => a.highlights = v;
  static double _rShadows(Adjustments a) => a.shadows;
  static void _wShadows(Adjustments a, double v) => a.shadows = v;
  static double _rHue(Adjustments a) => a.hue;
  static void _wHue(Adjustments a, double v) => a.hue = v;
  static double _rVignette(Adjustments a) => a.vignette;
  static void _wVignette(Adjustments a, double v) => a.vignette = v;
  static double _rSharpen(Adjustments a) => a.sharpen;
  static void _wSharpen(Adjustments a, double v) => a.sharpen = v;
  static double _rGrain(Adjustments a) => a.grain;
  static void _wGrain(Adjustments a, double v) => a.grain = v;
  static double _rFilmGrain(Adjustments a) => a.filmGrain;
  static void _wFilmGrain(Adjustments a, double v) => a.filmGrain = v;
  static double _rBlur(Adjustments a) => a.blur;
  static void _wBlur(Adjustments a, double v) => a.blur = v;
  static double _rDenoise(Adjustments a) => a.denoise;
  static void _wDenoise(Adjustments a, double v) => a.denoise = v;

  int _selected = 0;

  final AdjustLayoutStore _layout = AdjustLayoutStore.instance;

  /// The knobs the user has kept, in the order they put them.
  List<_Knob> get _shown {
    final order = _layout.visible([for (final k in _knobs) k.label]);
    return [
      for (final label in order) _knobs.firstWhere((k) => k.label == label),
    ];
  }

  @override
  void initState() {
    super.initState();
    _layout.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Which of the eight colour bands the HSL controls are pointed at.
  int _band = 0;

  /// True while the frame is being read. Auto is one tap and a moment's
  /// work, so it says so rather than looking like a button that missed.
  bool _autoRunning = false;

  Adjustments get _adj =>
      widget.overlay?.adjustments ??
      widget.editor.project.clips[widget.clipIndex!].adjustments;

  /// Both targets hold an [Adjustments] of their own, so one mutator covers
  /// them once we know which object to hand it.
  void _apply(void Function(Adjustments) mutate, {bool record = true}) {
    final overlay = widget.overlay;
    if (overlay != null) {
      widget.editor.updateLayer<OverlayLayer>(
        overlay,
        (o) => mutate(o.adjustments),
        record: record,
      );
    } else {
      widget.editor.updateClip(
        widget.clipIndex!,
        (c) => mutate(c.adjustments),
        record: record,
      );
    }
    setState(() {});
  }

  /// Read the frame under the playhead and set the sliders it is asking for.
  ///
  /// It writes over the tonal knobs rather than adding to them: Auto is an
  /// answer to the picture, and stacking it on a grade the user already made
  /// would give neither.
  Future<void> _runAuto() async {
    if (_autoRunning) return;
    final path = await _framePath();
    if (path == null) {
      if (mounted) {
        setState(() => _autoRunning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read this frame')),
        );
      }
      return;
    }
    final measured = await AutoAdjust.forFrame(path);
    if (!mounted) return;
    setState(() => _autoRunning = false);
    if (measured == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read this frame')),
      );
      return;
    }
    if (measured.isNeutral) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This frame is already well exposed')),
      );
      return;
    }
    _apply((a) {
      a.brightness = measured.brightness;
      a.contrast = measured.contrast;
      a.saturation = measured.saturation;
    });
  }

  /// A still of what the playhead is on, which is what Auto measures.
  Future<String?> _framePath() async {
    final overlay = widget.overlay;
    final clip = widget.clipIndex == null
        ? null
        : widget.editor.project.clips[widget.clipIndex!];
    final path = overlay?.path ?? clip?.path;
    if (path == null) return null;
    if (overlay?.isImage ?? clip?.isImage ?? false) return path;

    setState(() => _autoRunning = true);
    final at = overlay != null
        ? overlay.trimStart
        : clip!.sourcePositionFor(
            widget.editor.position.value -
                widget.editor.project.clipStart(widget.clipIndex!),
          );
    final grabbed = await ThumbnailService.instance.frame(
      path,
      at,
      height: 128,
    );
    // A decode can fail on a seek past the last keyframe; the strip the
    // timeline already has is a better frame than none.
    return grabbed ?? clip?.thumbnailPath;
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final adj = _adj;
    final shown = _shown;
    // A knob hidden from the row while it was in hand leaves the index
    // pointing past the end.
    final knob = shown.isEmpty
        ? _knobs.first
        : shown[_selected.clamp(0, shown.length - 1)];

    return PanelShell(
      title: 'Adjust',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      onReset: () => _apply((a) => a.reset()),
      applyToAll: widget.overlay != null
          ? null
          : () {
              final copy = adj.copy();
              widget.editor.applyToAllClips((c) {
                c.adjustments = copy.copy();
              });
            },
      child: PanelBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: r.vp(4)),
            ColorToolPill(current: ColorTool.adjust, onSelected: widget.onTool),
            SizedBox(height: r.vp(10)),
            // One slider, for whichever knob is in hand — except HSL, which
            // is eight bands of three and brings its own controls.
            if (knob.label == 'Color')
              _colorCastControls(r, adj)
            else if (knob.label == 'Curves')
              CurveEditor(
                adjustments: adj,
                onChanged: (i, v) =>
                    _apply((a) => _writeCurve(a, i, v), record: false),
                onChangeEnd: (i, v) => _apply((a) => _writeCurve(a, i, v)),
              )
            else if (knob.label == 'HSL')
              _hslControls(r, adj)
            else
              AppSlider(
                label: knob.label,
                icon: knob.icon,
                value: knob.read(adj),
                min: knob.bipolar ? -1 : 0,
                max: 1,
                bipolar: knob.bipolar,
                defaultValue: 0,
                format: (v) => (v * 100).round().toString(),
                onChanged: (v) =>
                    _apply((a) => knob.write(a, v), record: false),
                onChangeEnd: (v) => _apply((a) => knob.write(a, v)),
              ),
            SizedBox(height: r.vp(6)),
            _knobRow(context, r, adj, shown),
            SizedBox(height: r.vp(8)),
          ],
        ),
      ),
    );
  }

  /// Written through the target's own adjustments, for the same reason the
  /// HSL bands are.
  void _writeCurve(Adjustments a, int point, double v) {
    switch (point) {
      case 0:
        a.curveLow = v;
      case 1:
        a.curveMid = v;
      default:
        a.curveHigh = v;
    }
  }

  /// Manage's own tile, at the tail of the row.
  Widget _manageButton(Responsive r) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openManage,
      child: SizedBox(
        width: r.dp(64),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.settings_outlined,
              size: r.ic(22),
              color: AppColors.appBarMuted,
            ),
            SizedBox(height: r.vp(6)),
            Text(
              'Manage',
              style: TextStyle(
                fontSize: r.sp(9.5),
                height: 1.15,
                fontWeight: FontWeight.w500,
                color: AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The sheet that decides what the row holds: drag to re-order, switch off
  /// to hide. A knob switched off keeps whatever it was set to — hiding is
  /// about the row being long, not about undoing work.
  Future<void> _openManage() async {
    final all = [for (final k in _knobs) k.label];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final order = _layout.arrange(all);
          final r = context.r;
          return SafeArea(
            top: false,
            child: SizedBox(
              height: r.height * 0.62,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(r.dp(16), 0, r.dp(8), r.vp(4)),
                    child: Row(
                      children: [
                        Text(
                          'Manage tools',
                          style: TextStyle(
                            fontSize: r.sp(15),
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            await _layout.reset();
                            setSheet(() {});
                            if (mounted) setState(() {});
                          },
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: EdgeInsets.only(bottom: r.vp(12)),
                      itemCount: order.length,
                      onReorder: (from, to) async {
                        final next = List<String>.from(order);
                        final moved = next.removeAt(from);
                        next.insert(to > from ? to - 1 : to, moved);
                        await _layout.setOrder(next);
                        setSheet(() {});
                        if (mounted) setState(() {});
                      },
                      itemBuilder: (context, i) {
                        final label = order[i];
                        final hidden = _layout.isHidden(label);
                        return ListTile(
                          key: ValueKey(label),
                          dense: true,
                          leading: Icon(
                            _knobs.firstWhere((k) => k.label == label).icon,
                            size: r.ic(20),
                            color: hidden
                                ? AppColors.textFaint
                                : AppColors.appBarMuted,
                          ),
                          title: Text(
                            label,
                            style: TextStyle(
                              fontSize: r.sp(13),
                              color: hidden
                                  ? AppColors.textFaint
                                  : AppColors.text,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch.adaptive(
                                value: !hidden,
                                onChanged: (on) async {
                                  await _layout.setHidden(label, !on);
                                  setSheet(() {});
                                  if (mounted) setState(() {});
                                },
                              ),
                              SizedBox(width: r.dp(6)),
                              Icon(
                                Icons.drag_handle,
                                size: r.ic(20),
                                color: AppColors.textFaint,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// The colour cast: which hue, then how much of it.
  ///
  /// The hues are spread evenly round the wheel rather than taken from the
  /// HSL band centres — this is a cast to choose, not a band to grade, so an
  /// even spread gives the eye more to pick from at the warm end where most
  /// casts are wanted.
  Widget _colorCastControls(Responsive r, Adjustments adj) {
    const swatches = 12;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: r.dp(40),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: r.dp(12)),
            itemCount: swatches,
            separatorBuilder: (_, _) => SizedBox(width: r.dp(8)),
            itemBuilder: (context, i) {
              final hue = i / swatches;
              final on = (adj.colorCastHue - hue).abs() < 0.001;
              return GestureDetector(
                onTap: () => _apply((a) {
                  a.colorCastHue = hue;
                  // Picking a colour with the strength at zero would look
                  // like a dead swatch, so the first pick brings it up.
                  if (a.colorCastAmount == 0) a.colorCastAmount = 0.35;
                }),
                child: Container(
                  width: r.dp(34),
                  decoration: BoxDecoration(
                    color: HSVColor.fromAHSV(1, hue * 360, 0.8, 0.95).toColor(),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: on ? AppColors.text : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: r.vp(4)),
        AppSlider(
          label: 'Strength',
          icon: Icons.format_color_fill,
          value: adj.colorCastAmount,
          min: 0,
          max: 1,
          defaultValue: 0,
          format: (v) => (v * 100).round().toString(),
          onChanged: (v) => _apply((a) => a.colorCastAmount = v, record: false),
          onChangeEnd: (v) => _apply((a) => a.colorCastAmount = v),
        ),
      ],
    );
  }

  /// A swatch per band, then that band's three sliders.
  ///
  /// The swatches carry the colour they grade rather than a label, because
  /// the whole point of the tool is picking a colour out of the picture —
  /// reading the word 'Aqua' and finding it on the wheel is a step the
  /// swatch removes.
  Widget _hslControls(Responsive r, Adjustments adj) {
    final grade = adj.hsl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: r.dp(40),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: r.dp(12)),
            itemCount: HslGrade.bandCount,
            separatorBuilder: (_, _) => SizedBox(width: r.dp(8)),
            itemBuilder: (context, i) {
              final on = i == _band;
              final touched =
                  grade.hue[i] != 0 ||
                  grade.saturation[i] != 0 ||
                  grade.luminance[i] != 0;
              return GestureDetector(
                onTap: () => setState(() => _band = i),
                child: Container(
                  width: r.dp(34),
                  decoration: BoxDecoration(
                    color: HSLColor.fromAHSL(
                      1,
                      HslGrade.bandCentres[i],
                      0.72,
                      0.52,
                    ).toColor(),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: on ? AppColors.text : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: touched
                      ? Icon(
                          Icons.circle,
                          size: r.ic(7),
                          color: AppColors.onAccent,
                        )
                      : null,
                ),
              );
            },
          ),
        ),
        SizedBox(height: r.vp(4)),
        _hslSlider(r, 'Hue', Icons.palette_outlined, grade.hue),
        _hslSlider(
          r,
          'Saturation',
          Icons.water_drop_outlined,
          grade.saturation,
        ),
        _hslSlider(r, 'Luminance', Icons.brightness_6, grade.luminance),
      ],
    );
  }

  Widget _hslSlider(
    Responsive r,
    String label,
    IconData icon,
    List<double> band,
  ) {
    return AppSlider(
      label: '${HslGrade.bandNames[_band]} $label',
      icon: icon,
      value: band[_band],
      min: -1,
      max: 1,
      bipolar: true,
      defaultValue: 0,
      format: (v) => (v * 100).round().toString(),
      onChanged: (v) => _apply((a) => _writeBand(a, label, v), record: false),
      onChangeEnd: (v) => _apply((a) => _writeBand(a, label, v)),
    );
  }

  /// Written through the target's own grade rather than the list handed to
  /// the slider: an overlay and a clip each hold their own [HslGrade], and
  /// the list that built the control belongs to whichever was current when
  /// it was built.
  void _writeBand(Adjustments a, String label, double v) {
    switch (label) {
      case 'Hue':
        a.hsl.hue[_band] = v;
      case 'Saturation':
        a.hsl.saturation[_band] = v;
      default:
        a.hsl.luminance[_band] = v;
    }
  }

  /// Auto's own tile: a spinner while the frame is being read, so a tap that
  /// is doing work does not look like a tap that missed.
  Widget _autoButton(Responsive r) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _runAuto,
      child: SizedBox(
        width: r.dp(64),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: r.ic(22),
              width: r.ic(22),
              child: _autoRunning
                  ? CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.accent,
                      ),
                    )
                  : Icon(
                      Icons.auto_fix_high,
                      size: r.ic(22),
                      color: AppColors.appBarMuted,
                    ),
            ),
            SizedBox(height: r.vp(6)),
            Text(
              'Auto',
              style: TextStyle(
                fontSize: r.sp(9.5),
                height: 1.15,
                fontWeight: FontWeight.w500,
                color: AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The knobs as a row of icons. A knob that has been moved off zero keeps
  /// the accent under it, so the row also says what has been touched — the
  /// thing a stack of sliders showed for free and a single slider cannot.
  Widget _knobRow(
    BuildContext context,
    Responsive r,
    Adjustments adj,
    List<_Knob> shown,
  ) {
    // Measured through the text scaler rather than assumed: the label runs to
    // two lines, and at a large system font a fixed 74 is a pixel short —
    // which is exactly the kind of miss that paints the overflow stripe.
    final line = MediaQuery.textScalerOf(context).scale(r.sp(9.5)) * 1.15;
    return SizedBox(
      height: r.ic(22) + r.vp(6) + line * 2 + r.vp(10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: r.dp(10)),
        itemCount: shown.length + 2,
        itemBuilder: (context, i) {
          // Auto leads the row and is a button, not a knob: it has no slider
          // of its own, it reads the frame and moves the others.
          if (i == 0) return _autoButton(r);
          // Manage closes it, for the same reason: it changes the row rather
          // than the picture.
          if (i == shown.length + 1) return _manageButton(r);
          final k = shown[i - 1];
          final on = i - 1 == _selected;
          final touched = k.read(adj) != 0;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _selected = i - 1),
            child: SizedBox(
              width: r.dp(64),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        k.icon,
                        size: r.ic(22),
                        color: on
                            ? AppColors.text
                            : (touched
                                  ? AppColors.accent
                                  : AppColors.appBarMuted),
                      ),
                      if (touched)
                        Positioned(
                          top: -r.vp(6),
                          right: -r.dp(8),
                          child: Container(
                            width: r.dp(6),
                            height: r.dp(6),
                            decoration: const BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: r.vp(6)),
                  Text(
                    k.label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: r.sp(9.5),
                      height: 1.15,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                      color: on ? AppColors.text : AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
