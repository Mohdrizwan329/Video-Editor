/// How a design frame is drawn around the canvas.
enum FrameStyle {
  none,
  solid,
  rounded,
  doubleLine,
  corners,
  polaroid,
  mat,
  filmStrip,
  tape,
  neon,
}

/// A decorative border drawn over the finished frame.
///
/// Geometry is expressed as a fraction of the canvas, so the same preset
/// paints identically into the on-screen preview and into the full-resolution
/// PNG the exporter composites.
class FramePreset {
  const FramePreset({
    required this.id,
    required this.name,
    required this.category,
    this.style = FrameStyle.none,
    this.color = 0xFFFFFFFF,
    this.accent = 0xFF101014,
    this.thickness = 0.03,
  });

  final String id;
  final String name;
  final String category;
  final FrameStyle style;

  /// Main border colour.
  final int color;

  /// Secondary colour: sprocket holes, glow, tape.
  final int accent;

  /// Border width as a fraction of the canvas's shorter side.
  final double thickness;

  bool get isNone => style == FrameStyle.none;
}

class FrameLibrary {
  FrameLibrary._();

  static const none =
      FramePreset(id: 'none', name: 'None', category: 'None');

  static const List<FramePreset> all = [
    none,
    // ------------------------------------------------------------- Classic
    FramePreset(id: 'thin', name: 'Thin', category: 'Classic',
        style: FrameStyle.solid, thickness: 0.012),
    FramePreset(id: 'bold', name: 'Bold', category: 'Classic',
        style: FrameStyle.solid, thickness: 0.045),
    FramePreset(id: 'soft', name: 'Soft', category: 'Classic',
        style: FrameStyle.rounded, thickness: 0.035),
    FramePreset(id: 'double', name: 'Double', category: 'Classic',
        style: FrameStyle.doubleLine, thickness: 0.03),
    FramePreset(id: 'corners', name: 'Corners', category: 'Classic',
        style: FrameStyle.corners, thickness: 0.02),
    // --------------------------------------------------------------- Photo
    FramePreset(id: 'polaroid', name: 'Polaroid', category: 'Photo',
        style: FrameStyle.polaroid, thickness: 0.045),
    FramePreset(id: 'mat_white', name: 'White Mat', category: 'Photo',
        style: FrameStyle.mat, thickness: 0.07),
    FramePreset(id: 'mat_black', name: 'Black Mat', category: 'Photo',
        style: FrameStyle.mat, color: 0xFF0B0B0F, thickness: 0.07),
    // --------------------------------------------------------------- Retro
    FramePreset(id: 'filmstrip', name: 'Film', category: 'Retro',
        style: FrameStyle.filmStrip, color: 0xFF121216, accent: 0xFFF2F2F2,
        thickness: 0.035),
    FramePreset(id: 'tape', name: 'Tape', category: 'Retro',
        style: FrameStyle.tape, color: 0xFFF6F3EA, accent: 0xB3E8D9A8,
        thickness: 0.022),
    // ---------------------------------------------------------------- Neon
    FramePreset(id: 'neon_pink', name: 'Neon Pink', category: 'Neon',
        style: FrameStyle.neon, color: 0xFFFFFFFF, accent: 0xFFFF2D95,
        thickness: 0.02),
    FramePreset(id: 'neon_cyan', name: 'Neon Cyan', category: 'Neon',
        style: FrameStyle.neon, color: 0xFFFFFFFF, accent: 0xFF00E5FF,
        thickness: 0.02),
    FramePreset(id: 'neon_glow', name: 'Glow', category: 'Neon',
        style: FrameStyle.neon, color: 0xFFFFF3C4, accent: 0xFFFFC64A,
        thickness: 0.026),
  ];

  static List<String> get categories =>
      ['None', 'Classic', 'Photo', 'Retro', 'Neon'];

  static List<FramePreset> byCategory(String c) =>
      all.where((f) => f.category == c).toList();

  static FramePreset fromId(String? id) =>
      all.firstWhere((f) => f.id == id, orElse: () => none);
}

/// The pattern an [FxPreset] paints over the frame.
enum FxPattern {
  none,
  grain,
  scanlines,
  halftone,
  vhs,
  lightLeak,
  bloom,
  prism,
  dust,
  glitch,
  staticNoise,
  // Motion patterns: these carry the frame index into what they draw, so
  // they only read as themselves once they are running.
  strobe,
  flash,
  oldTv,
  filmBurn,
  neonPulse,
  sparkle,
  rain,
  snow,
  bokeh,
  confetti,
  hearts,
  bubbles,
}

/// A texture effect laid over the finished frame.
///
/// Everything is plain alpha compositing — the exporter can reproduce it with
/// the same `overlay` filter the watermark already uses, which is what keeps
/// the render honest to the preview.
class FxPreset {
  const FxPreset({
    required this.id,
    required this.name,
    required this.category,
    this.pattern = FxPattern.none,
    this.opacity = 1.0,
    this.seed = 7,
    this.period = 0,
    this.frameRate = 12,
  });

  final String id;
  final String name;
  final String category;
  final FxPattern pattern;

  /// Baked into the pattern's alpha, on top of the user's intensity slider.
  final double opacity;

  /// Fixed so the preview and the exported PNG scatter grain identically.
  final int seed;

  /// Length of the effect's loop in seconds. Zero is a still texture, which
  /// is one PNG at export time instead of a sequence.
  ///
  /// Every motion effect here is a *loop*: it has to read the same at second
  /// three as at second thirty, and the renderer plays a short strip of
  /// frames over and over rather than baking one per frame of the video.
  /// Anything that reads as a cycle — grain reshuffling, a band rolling down
  /// the screen, snow falling — costs the same whether the clip is two
  /// seconds long or ten minutes.
  final double period;

  /// How many frames of its own the effect runs at. Grain and film dirt were
  /// shot on twos and read *better* chunky, so this is well under video rate
  /// and the renderer holds each frame for several output frames.
  final int frameRate;

  bool get isNone => pattern == FxPattern.none;

  bool get isAnimated => !isNone && period > 0;

  /// Frames in one loop. Capped so a slow drift cannot ask the exporter for
  /// hundreds of full-resolution PNGs.
  int get frameCount =>
      isAnimated ? (period * frameRate).round().clamp(2, 48) : 1;

  /// Which frame of the loop is showing at [t].
  ///
  /// The preview asks this of the playhead and the renderer lays the same
  /// frames out at [frameRate] on a loop, so both land on the same picture at
  /// the same moment — the whole reason the loop is defined in frames rather
  /// than in a continuous phase.
  int frameAt(Duration t) {
    if (!isAnimated) return 0;
    final n = frameCount;
    final i = (t.inMicroseconds * frameRate) ~/ Duration.microsecondsPerSecond;
    return ((i % n) + n) % n;
  }
}

class FxLibrary {
  FxLibrary._();

  static const none = FxPreset(id: 'none', name: 'None', category: 'None');

  static const List<FxPreset> all = [
    none,
    // --------------------------------------------------------------- Basic
    FxPreset(id: 'strobe', name: 'Strobe', category: 'Basic',
        pattern: FxPattern.strobe, opacity: 0.9, seed: 41,
        period: 0.4, frameRate: 15),
    FxPreset(id: 'flash', name: 'Flash', category: 'Basic',
        pattern: FxPattern.flash, opacity: 0.85, seed: 43,
        period: 1.2, frameRate: 15),
    // --------------------------------------------------------------- Retro
    FxPreset(id: 'vhs', name: 'VHS', category: 'Retro',
        pattern: FxPattern.vhs, opacity: 0.9, seed: 11,
        period: 1.5, frameRate: 12),
    FxPreset(id: 'scanline', name: 'Scanline', category: 'Retro',
        pattern: FxPattern.scanlines, opacity: 0.8, seed: 3,
        period: 1.0, frameRate: 12),
    FxPreset(id: 'halftone', name: 'Halftone', category: 'Retro',
        pattern: FxPattern.halftone, opacity: 0.75, seed: 5,
        period: 2.0, frameRate: 8),
    FxPreset(id: 'super8', name: 'Super 8', category: 'Retro',
        pattern: FxPattern.dust, opacity: 0.85, seed: 23,
        period: 0.5, frameRate: 12),
    FxPreset(id: 'oldTv', name: 'Old TV', category: 'Retro',
        pattern: FxPattern.oldTv, opacity: 0.9, seed: 47,
        period: 1.2, frameRate: 15),
    FxPreset(id: 'filmBurn', name: 'Burn', category: 'Retro',
        pattern: FxPattern.filmBurn, opacity: 0.9, seed: 53,
        period: 2.5, frameRate: 12),
    // --------------------------------------------------------------- Light
    FxPreset(id: 'leak', name: 'Light Leak', category: 'Light',
        pattern: FxPattern.lightLeak, opacity: 0.85, seed: 2,
        period: 3.0, frameRate: 12),
    FxPreset(id: 'bloom', name: 'Bloom', category: 'Light',
        pattern: FxPattern.bloom, opacity: 0.7, seed: 4,
        period: 2.0, frameRate: 12),
    FxPreset(id: 'prism', name: 'Prism', category: 'Light',
        pattern: FxPattern.prism, opacity: 0.8, seed: 6,
        period: 2.0, frameRate: 12),
    FxPreset(id: 'neon', name: 'Neon', category: 'Light',
        pattern: FxPattern.neonPulse, opacity: 0.9, seed: 59,
        period: 1.6, frameRate: 15),
    FxPreset(id: 'sparkle', name: 'Sparkle', category: 'Light',
        pattern: FxPattern.sparkle, opacity: 0.9, seed: 61,
        period: 1.5, frameRate: 12),
    // ---------------------------------------------------------------- Grit
    FxPreset(id: 'grain', name: 'Grain', category: 'Grit',
        pattern: FxPattern.grain, opacity: 0.65, seed: 13,
        period: 0.5, frameRate: 12),
    FxPreset(id: 'grain_heavy', name: 'Rough', category: 'Grit',
        pattern: FxPattern.grain, opacity: 1.0, seed: 17,
        period: 0.5, frameRate: 12),
    FxPreset(id: 'dust', name: 'Dust', category: 'Grit',
        pattern: FxPattern.dust, opacity: 0.6, seed: 29,
        period: 0.5, frameRate: 12),
    // -------------------------------------------------------------- Glitch
    FxPreset(id: 'glitch', name: 'Glitch', category: 'Glitch',
        pattern: FxPattern.glitch, opacity: 0.9, seed: 31,
        period: 0.8, frameRate: 15),
    FxPreset(id: 'static', name: 'Static', category: 'Glitch',
        pattern: FxPattern.staticNoise, opacity: 0.8, seed: 37,
        period: 0.4, frameRate: 15),
    // -------------------------------------------------------------- Nature
    FxPreset(id: 'rain', name: 'Rain', category: 'Nature',
        pattern: FxPattern.rain, opacity: 0.85, seed: 67,
        period: 1.0, frameRate: 20),
    FxPreset(id: 'snow', name: 'Snow', category: 'Nature',
        pattern: FxPattern.snow, opacity: 0.9, seed: 71,
        period: 4.0, frameRate: 10),
    FxPreset(id: 'bokeh', name: 'Bokeh', category: 'Nature',
        pattern: FxPattern.bokeh, opacity: 0.8, seed: 73,
        period: 4.0, frameRate: 10),
    // --------------------------------------------------------------- Party
    FxPreset(id: 'confetti', name: 'Confetti', category: 'Party',
        pattern: FxPattern.confetti, opacity: 0.95, seed: 79,
        period: 3.0, frameRate: 15),
    FxPreset(id: 'hearts', name: 'Hearts', category: 'Party',
        pattern: FxPattern.hearts, opacity: 0.9, seed: 83,
        period: 4.0, frameRate: 12),
    FxPreset(id: 'bubbles', name: 'Bubbles', category: 'Party',
        pattern: FxPattern.bubbles, opacity: 0.85, seed: 89,
        period: 4.0, frameRate: 12),
  ];

  static List<String> get categories => [
        'None',
        'Basic',
        'Retro',
        'Light',
        'Grit',
        'Glitch',
        'Nature',
        'Party',
      ];

  static List<FxPreset> byCategory(String c) =>
      all.where((f) => f.category == c).toList();

  static FxPreset fromId(String? id) =>
      all.firstWhere((f) => f.id == id, orElse: () => none);
}
