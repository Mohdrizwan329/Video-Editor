import 'package:flutter/material.dart';

/// Canvas aspect ratios offered by the editor.
enum CanvasRatio {
  original(null, 'Original', Icons.crop_original),
  r9x16(9 / 16, '9:16', Icons.stay_current_portrait),
  r16x9(16 / 9, '16:9', Icons.stay_current_landscape),
  r1x1(1, '1:1', Icons.crop_square),
  r4x5(4 / 5, '4:5', Icons.crop_portrait),
  r3x4(3 / 4, '3:4', Icons.crop_portrait),
  r4x3(4 / 3, '4:3', Icons.crop_landscape),
  r2x1(2, '2:1', Icons.crop_16_9),
  r235x1(2.35, '2.35:1', Icons.panorama_wide_angle);

  const CanvasRatio(this.value, this.label, this.icon);

  /// width / height. `null` means follow the first clip.
  final double? value;
  final String label;
  final IconData icon;

  static CanvasRatio fromName(String? n) =>
      CanvasRatio.values.firstWhere((e) => e.name == n, orElse: () => CanvasRatio.r9x16);
}

/// Fit mode of a clip inside the canvas.
enum FitMode { contain, cover, stretch }

/// How the empty canvas area behind a clip is painted.
enum BackgroundType { color, blur, gradient }

/// Transition between two adjacent main-track clips.
///
/// Every entry maps to a real FFmpeg `xfade` transition, so what the picker
/// offers is exactly what the renderer can produce.
enum TransitionType {
  none('None', Icons.block, 'Basic', 'fade'),
  // Basic
  fade('Fade', Icons.gradient, 'Basic', 'fade'),
  dissolve('Dissolve', Icons.blur_on, 'Basic', 'dissolve'),
  blackFade('Black', Icons.brightness_2, 'Basic', 'fadeblack'),
  whiteFlash('White', Icons.flash_on, 'Basic', 'fadewhite'),
  greyFade('Grey', Icons.brightness_medium, 'Basic', 'fadegrays'),
  distance('Distance', Icons.linear_scale, 'Basic', 'distance'),
  // Slide
  slideLeft('Slide L', Icons.arrow_back, 'Slide', 'slideleft'),
  slideRight('Slide R', Icons.arrow_forward, 'Slide', 'slideright'),
  slideUp('Slide U', Icons.arrow_upward, 'Slide', 'slideup'),
  slideDown('Slide D', Icons.arrow_downward, 'Slide', 'slidedown'),
  smoothLeft('Smooth L', Icons.swipe_left, 'Slide', 'smoothleft'),
  smoothRight('Smooth R', Icons.swipe_right, 'Slide', 'smoothright'),
  smoothUp('Smooth U', Icons.swipe_up, 'Slide', 'smoothup'),
  smoothDown('Smooth D', Icons.swipe_down, 'Slide', 'smoothdown'),
  // Wipe
  wipeLeft('Wipe L', Icons.first_page, 'Wipe', 'wipeleft'),
  wipeRight('Wipe R', Icons.last_page, 'Wipe', 'wiperight'),
  wipeUp('Wipe U', Icons.vertical_align_top, 'Wipe', 'wipeup'),
  wipeDown('Wipe D', Icons.vertical_align_bottom, 'Wipe', 'wipedown'),
  wipeTopLeft('Wipe TL', Icons.north_west, 'Wipe', 'wipetl'),
  wipeTopRight('Wipe TR', Icons.north_east, 'Wipe', 'wipetr'),
  wipeBottomLeft('Wipe BL', Icons.south_west, 'Wipe', 'wipebl'),
  wipeBottomRight('Wipe BR', Icons.south_east, 'Wipe', 'wipebr'),
  diagTopLeft('Diag TL', Icons.call_made, 'Wipe', 'diagtl'),
  diagTopRight('Diag TR', Icons.call_received, 'Wipe', 'diagtr'),
  diagBottomLeft('Diag BL', Icons.call_missed, 'Wipe', 'diagbl'),
  diagBottomRight('Diag BR', Icons.call_missed_outgoing, 'Wipe', 'diagbr'),
  // Shape
  circleOpen('Circle Op', Icons.circle_outlined, 'Shape', 'circleopen'),
  circleClose('Circle Cl', Icons.circle, 'Shape', 'circleclose'),
  circleCrop('Circle Cr', Icons.crop_free, 'Shape', 'circlecrop'),
  rectCrop('Rect Crop', Icons.crop_square, 'Shape', 'rectcrop'),
  radial('Radial', Icons.radar, 'Shape', 'radial'),
  diamond('Diamond', Icons.diamond_outlined, 'Shape', 'diagtl'),
  // Blinds & bars
  horzOpen('H Open', Icons.unfold_more, 'Bars', 'horzopen'),
  horzClose('H Close', Icons.unfold_less, 'Bars', 'horzclose'),
  vertOpen('V Open', Icons.unfold_more_double, 'Bars', 'vertopen'),
  vertClose('V Close', Icons.unfold_less_double, 'Bars', 'vertclose'),
  hlSlice('H Slice', Icons.view_stream, 'Bars', 'hlslice'),
  hrSlice('H Slice R', Icons.view_stream_outlined, 'Bars', 'hrslice'),
  vuSlice('V Slice', Icons.view_column, 'Bars', 'vuslice'),
  vdSlice('V Slice D', Icons.view_column_outlined, 'Bars', 'vdslice'),
  // Motion
  zoomIn('Zoom In', Icons.zoom_in, 'Motion', 'zoomin'),
  squeezeH('Squeeze H', Icons.compress, 'Motion', 'squeezeh'),
  squeezeV('Squeeze V', Icons.expand, 'Motion', 'squeezev'),
  pixelize('Pixelize', Icons.grid_on, 'Motion', 'pixelize'),
  wind('Wind', Icons.air, 'Motion', 'wipeleft'),
  coverLeft('Cover L', Icons.chevron_left, 'Motion', 'coverleft'),
  coverRight('Cover R', Icons.chevron_right, 'Motion', 'coverright'),
  coverUp('Cover U', Icons.expand_less, 'Motion', 'coverup'),
  coverDown('Cover D', Icons.expand_more, 'Motion', 'coverdown'),
  revealLeft('Reveal L', Icons.arrow_left, 'Motion', 'revealleft'),
  revealRight('Reveal R', Icons.arrow_right, 'Motion', 'revealright');

  const TransitionType(this.label, this.icon, this.category, this.ffmpegName);

  final String label;
  final IconData icon;
  final String category;

  /// FFmpeg `xfade` transition name used at export time.
  final String ffmpegName;

  static const List<String> categories = [
    'Basic', 'Slide', 'Wipe', 'Shape', 'Bars', 'Motion'
  ];

  static List<TransitionType> byCategory(String c) =>
      TransitionType.values.where((t) => t.category == c).toList();

  static TransitionType fromName(String? n) => TransitionType.values
      .firstWhere((e) => e.name == n, orElse: () => TransitionType.none);
}

/// In/out animations shared by text, sticker and overlay layers.
///
/// [exportKind] tells the renderer how faithfully it can reproduce the
/// animation: position moves become overlay expressions, scale/rotate become
/// filter expressions, and the rest fall back to an alpha fade.
enum LayerAnimation {
  none('None', 'Basic', AnimExport.none),
  // Fade family
  fade('Fade', 'Basic', AnimExport.alpha),
  fadeBlur('Fade Blur', 'Basic', AnimExport.alpha),
  dissolve('Dissolve', 'Basic', AnimExport.alpha),
  // Slide family
  slideUp('Slide Up', 'Slide', AnimExport.move),
  slideDown('Slide Down', 'Slide', AnimExport.move),
  slideLeft('Slide Left', 'Slide', AnimExport.move),
  slideRight('Slide Right', 'Slide', AnimExport.move),
  driftUp('Drift Up', 'Slide', AnimExport.move),
  driftDown('Drift Down', 'Slide', AnimExport.move),
  swipeIn('Swipe', 'Slide', AnimExport.move),
  flyIn('Fly In', 'Slide', AnimExport.move),
  // Scale family
  scale('Scale', 'Scale', AnimExport.scale),
  scaleDown('Scale Down', 'Scale', AnimExport.scale),
  pop('Pop', 'Scale', AnimExport.scale),
  bounce('Bounce', 'Scale', AnimExport.scale),
  zoomBlur('Zoom Blur', 'Scale', AnimExport.scale),
  stretch('Stretch', 'Scale', AnimExport.scale),
  squeeze('Squeeze', 'Scale', AnimExport.scale),
  // Rotate family
  spin('Spin', 'Rotate', AnimExport.rotate),
  spinFast('Spin Fast', 'Rotate', AnimExport.rotate),
  swing('Swing', 'Rotate', AnimExport.rotate),
  flip('Flip', 'Rotate', AnimExport.rotate),
  tilt('Tilt', 'Rotate', AnimExport.rotate),
  // Text-specific
  typewriter('Typewriter', 'Text', AnimExport.alpha),
  wordByWord('Word by Word', 'Text', AnimExport.alpha),
  lineByLine('Line by Line', 'Text', AnimExport.alpha),
  wave('Wave', 'Text', AnimExport.alpha),
  neon('Neon', 'Text', AnimExport.alpha),
  // Emphasis
  shake('Shake', 'Emphasis', AnimExport.move),
  pulse('Pulse', 'Emphasis', AnimExport.scale),
  blink('Blink', 'Emphasis', AnimExport.alpha),
  wobble('Wobble', 'Emphasis', AnimExport.rotate);

  const LayerAnimation(this.label, this.category, this.exportKind);

  final String label;
  final String category;
  final AnimExport exportKind;

  static const List<String> categories = [
    'Basic', 'Slide', 'Scale', 'Rotate', 'Text', 'Emphasis'
  ];

  static List<LayerAnimation> byCategory(String c) =>
      LayerAnimation.values.where((a) => a.category == c).toList();

  /// Animations that keep running for the whole layer rather than only at
  /// its edges.
  bool get isContinuous => this == LayerAnimation.shake ||
      this == LayerAnimation.pulse ||
      this == LayerAnimation.blink ||
      this == LayerAnimation.wobble ||
      this == LayerAnimation.wave ||
      this == LayerAnimation.neon;

  static LayerAnimation fromName(String? n) => LayerAnimation.values
      .firstWhere((e) => e.name == n, orElse: () => LayerAnimation.none);
}

/// How closely the renderer can reproduce an animation.
enum AnimExport { none, alpha, move, scale, rotate }

/// Mask shapes applied to a clip or overlay.
enum MaskShape {
  none('None', Icons.block),
  linear('Linear', Icons.horizontal_rule),
  mirror('Mirror', Icons.flip),
  circle('Circle', Icons.circle_outlined),
  rectangle('Rectangle', Icons.crop_square),
  heart('Heart', Icons.favorite_border),
  star('Star', Icons.star_border);

  const MaskShape(this.label, this.icon);
  final String label;
  final IconData icon;

  static MaskShape fromName(String? n) =>
      MaskShape.values.firstWhere((e) => e.name == n, orElse: () => MaskShape.none);
}

/// Layer compositing modes.
enum BlendMode2 {
  normal('Normal', 'normal'),
  multiply('Multiply', 'multiply'),
  screen('Screen', 'screen'),
  overlay('Overlay', 'overlay'),
  darken('Darken', 'darken'),
  lighten('Lighten', 'lighten'),
  colorDodge('Dodge', 'dodge'),
  colorBurn('Burn', 'burn'),
  hardLight('Hard Light', 'hardlight'),
  softLight('Soft Light', 'softlight'),
  difference('Difference', 'difference'),
  exclusion('Exclusion', 'exclusion'),
  addition('Add', 'addition'),
  subtract('Subtract', 'subtract');

  const BlendMode2(this.label, this.ffmpegName);
  final String label;

  /// Mode name accepted by FFmpeg's `blend` filter.
  final String ffmpegName;

  static BlendMode2 fromName(String? n) => BlendMode2.values
      .firstWhere((e) => e.name == n, orElse: () => BlendMode2.normal);
}

/// Speed ramping presets used by the curve tool.
enum SpeedCurve {
  none('Normal', []),
  montage('Montage', [(0.0, 1.0), (0.25, 0.4), (0.5, 2.5), (0.75, 0.4), (1.0, 1.0)]),
  hero('Hero', [(0.0, 1.0), (0.3, 2.0), (0.5, 0.25), (0.7, 2.0), (1.0, 1.0)]),
  bullet('Bullet', [(0.0, 2.5), (0.35, 0.2), (0.65, 0.2), (1.0, 2.5)]),
  jumper('Jumper', [(0.0, 1.0), (0.2, 3.0), (0.4, 0.5), (0.6, 3.0), (0.8, 0.5), (1.0, 1.0)]),
  flashIn('Flash In', [(0.0, 3.0), (0.25, 0.5), (1.0, 1.0)]),
  flashOut('Flash Out', [(0.0, 1.0), (0.75, 0.5), (1.0, 3.0)]),
  rampUp('Ramp Up', [(0.0, 0.35), (1.0, 3.0)]),
  rampDown('Ramp Down', [(0.0, 3.0), (1.0, 0.35)]);

  const SpeedCurve(this.label, this.points);

  final String label;

  /// (normalised position 0..1, speed multiplier) control points.
  final List<(double, double)> points;

  static SpeedCurve fromName(String? n) =>
      SpeedCurve.values.firstWhere((e) => e.name == n, orElse: () => SpeedCurve.none);

  /// Average multiplier, used to work out the clip's new timeline length.
  double get averageSpeed {
    if (points.length < 2) return 1;
    // Duration scales with the integral of 1/speed over the segment.
    var inverse = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      final (p0, s0) = points[i];
      final (p1, s1) = points[i + 1];
      final width = p1 - p0;
      final meanSpeed = (s0 + s1) / 2;
      inverse += width / meanSpeed;
    }
    return inverse <= 0 ? 1 : 1 / inverse;
  }

  double speedAt(double progress) {
    if (points.length < 2) return 1;
    if (progress <= points.first.$1) return points.first.$2;
    if (progress >= points.last.$1) return points.last.$2;
    for (var i = 0; i < points.length - 1; i++) {
      final (p0, s0) = points[i];
      final (p1, s1) = points[i + 1];
      if (progress < p0 || progress > p1) continue;
      final f = (progress - p0) / (p1 - p0);
      return s0 + (s1 - s0) * f;
    }
    return 1;
  }
}

/// Voice-changer presets applied to an audio lane item.
enum VoiceEffect {
  none('Normal', 0, false, false),
  chipmunk('Chipmunk', 7, false, false),
  squirrel('Squirrel', 12, false, false),
  child('Child', 4, false, false),
  deep('Deep', -5, false, false),
  monster('Monster', -9, false, false),
  giant('Giant', -12, true, false),
  robot('Robot', 0, false, true),
  cave('Cave', 0, true, false),
  alien('Alien', 6, true, true);

  const VoiceEffect(this.label, this.semitones, this.echo, this.isRobot);

  final String label;

  /// Pitch shift in semitones.
  final double semitones;
  final bool echo;

  /// Flattens the phase spectrum for a vocoder-like timbre.
  final bool isRobot;

  static VoiceEffect fromName(String? n) =>
      VoiceEffect.values.firstWhere((e) => e.name == n, orElse: () => VoiceEffect.none);
}

/// Kind of an audio lane item — drives its colour and default gain.
enum AudioKind { music, voiceover, sfx, extracted }

/// Kind of a timeline lane, used by the timeline widget builder.
enum LaneKind { video, audio, text, sticker, overlay }

/// Export presets.
enum ExportResolution {
  p480('480P', 480),
  p720('720P', 720),
  p1080('1080P', 1080),
  p2k('2K', 1440),
  p4k('4K', 2160);

  const ExportResolution(this.label, this.shortSide);
  final String label;
  final int shortSide;
}

enum ExportFps {
  fps24('24', 24),
  fps25('25', 25),
  fps30('30', 30),
  fps50('50', 50),
  fps60('60', 60);

  const ExportFps(this.label, this.value);
  final String label;
  final int value;
}

enum ExportQuality {
  low('Low', 0.5),
  standard('Standard', 1.0),
  high('High', 1.6),
  max('Max', 2.4);

  const ExportQuality(this.label, this.factor);
  final String label;
  final double factor;
}
