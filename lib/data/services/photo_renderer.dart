import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/utils/constants.dart';
import '../models/adjustments.dart';
import '../models/enums.dart';
import '../models/filter_preset.dart';
import '../models/layers.dart';
import '../models/photo_edit.dart';
import '../models/video_effect.dart';
import '../models/watermark.dart';
import 'effect_painter.dart';
import 'overlay_rasterizer.dart' show OverlayRasterizer, pictureToPng;

/// Draws a [PhotoEdit] onto a canvas, and writes the same drawing out as a
/// full-resolution PNG.
///
/// Both the on-screen stage and the saved file come through here, so the
/// framing, the grade and the textures the user approves in the preview are
/// the ones that land in the gallery. Everything is measured off the canvas
/// it is painting into, which is what lets a 300pt preview and a 4000px
/// export be the same picture at two sizes.
class PhotoRenderer {
  const PhotoRenderer._();

  /// The size of the picture this edit produces, in source pixels.
  ///
  /// The Canvas tool asks for a shape the photo may not have. Rather than
  /// stretch it, the box takes that shape and the photo is fitted inside it
  /// — the empty sides are what [paintMedia] fills.
  static Size outputSize(ui.Image image, PhotoEdit e) {
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final odd = e.quarterTurns.isOdd;
    final ow = odd ? ih : iw, oh = odd ? iw : ih;
    final w = math.max(1.0, ow * e.cropWidth);
    final h = math.max(1.0, oh * e.cropHeight);
    final canvas = e.canvasAspect;
    if (canvas == null) return Size(w, h);
    // The longer side is kept, so a photo never loses resolution to a shape.
    return canvas >= w / h
        ? Size(math.max(1, h * canvas), h)
        : Size(w, math.max(1, w / canvas));
  }

  /// The picture's aspect ratio (width / height) once framed.
  static double aspectOf(ui.Image image, PhotoEdit e) {
    final s = outputSize(image, e);
    return s.height <= 0 ? 1 : s.width / s.height;
  }

  /// The whole photo's aspect ratio after the turns and mirrors, ignoring the
  /// crop — what the crop tool lays its rectangle over.
  static double fullAspect(ui.Image image, PhotoEdit e) {
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    if (iw <= 0 || ih <= 0) return 1;
    return e.quarterTurns.isOdd ? ih / iw : iw / ih;
  }

  /// The picture itself: the crop window, the turns and mirrors, the blur and
  /// the colour grade. [cropped] is false while the crop tool is open, where
  /// the whole photo has to stay visible under the rectangle.
  ///
  /// Everything a 4x5 colour matrix can express happens here; the rest —
  /// gamma, the tone curve, sharpening, denoise and grain — is the second
  /// pass in [GradeExtrasBox] on screen and in [_extras] on the way to a file.
  static void paintMedia(
    Canvas canvas,
    Size size,
    ui.Image image,
    PhotoEdit e, {
    bool cropped = true,
    bool graded = true,
    ui.Image? sampler,
  }) {
    if (size.isEmpty) return;
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    if (iw <= 0 || ih <= 0) return;

    final odd = e.quarterTurns.isOdd;
    final ow = odd ? ih : iw, oh = odd ? iw : ih;
    final left = cropped ? e.cropLeft : 0.0;
    final top = cropped ? e.cropTop : 0.0;
    final windowW = (cropped ? e.cropWidth : 1.0) * ow;
    final windowH = (cropped ? e.cropHeight : 1.0) * oh;

    // The Canvas tool's fill, under everything. It only shows where the photo
    // does not reach, which is why it is painted rather than left blank: a
    // transparent margin comes out of a JPEG black.
    if (cropped && sampler == null && e.canvasAspect != null) {
      paintBackdrop(canvas, size, image, e);
    }

    // The box is normally cut to the picture's own aspect; when it is not,
    // the picture sits in the middle of it rather than stretching.
    final scale = math.min(size.width / windowW, size.height / windowH);
    final drawn = Size(windowW * scale, windowH * scale);
    // A sampler stands in for the photo — the skin mask, drawn through the
    // very same framing so it stays registered to the face — and it is never
    // graded, blurred or vignetted: it is a stencil, not a picture.
    if (sampler != null) graded = false;
    // gradedFilter, not grade: Enhance is a tone folded into the look rather
    // than a pass of its own, so it has to ride along here.
    final grade = graded ? e.gradedFilter : FilterLibrary.none;
    // The exporter's `gblur` is 12px at 1080p — 1.11% of the frame height —
    // so the same slider softens by the same fraction at any size.
    final sigma = graded ? e.adjustments.blur * 0.0111 * drawn.height : 0.0;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(
      (size.width - drawn.width) / 2,
      (size.height - drawn.height) / 2,
    );

    // Saved before the scale below, so the blur is measured in the canvas we
    // are painting into rather than in source pixels.
    if (sigma > 0.05) {
      canvas.saveLayer(
        Offset.zero & drawn,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
      );
    }

    canvas.save();
    canvas.scale(scale);
    // Into the displayed picture's own coordinates: the crop window's corner
    // becomes the origin…
    canvas.translate(-left * ow, -top * oh);
    // …and the photo is turned and mirrored about the middle of it. The
    // mirrors sit outside the rotation so they answer to the picture as the
    // user sees it, not to the file's own axes.
    canvas.translate(ow / 2, oh / 2);
    if (e.flipH || e.flipV) {
      canvas.scale(e.flipH ? -1.0 : 1.0, e.flipV ? -1.0 : 1.0);
    }
    if (e.quarterTurns != 0) canvas.rotate(e.quarterTurns * math.pi / 2);
    canvas.translate(-iw / 2, -ih / 2);
    final src = sampler ?? image;
    canvas.drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      Rect.fromLTWH(0, 0, iw, ih),
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high
        ..colorFilter = sampler == null
            ? ColorFilter.matrix(grade.toColorMatrix())
            : null,
    );
    canvas.restore();

    if (sigma > 0.05) canvas.restore();

    // The vignette is part of the grade, so it goes on the picture and not
    // over the frame — the same order [GradedBox] draws it in.
    if (graded && grade.vignette > 0) {
      paintVignette(canvas, drawn, grade.vignette);
    }
    canvas.restore();
  }

  /// What fills the canvas either side of a photo the Canvas tool has given a
  /// shape the photo does not have.
  ///
  /// A flat colour, or a blurred copy of the photo blown up to cover — the
  /// backdrop a square crop of a tall photo usually wants, and the one that
  /// makes the margin read as deliberate rather than as a mistake.
  static void paintBackdrop(
    Canvas canvas,
    Size size,
    ui.Image image,
    PhotoEdit e,
  ) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = Color(e.canvasBackground));
    if (!e.canvasBlurBackdrop) return;

    final iw = image.width.toDouble(), ih = image.height.toDouble();
    if (iw <= 0 || ih <= 0) return;
    // Cover, not fit: the whole box has to be filled or the colour shows
    // through in a band and the backdrop reads as a second mistake.
    final cover = math.max(size.width / iw, size.height / ih);
    final drawn = Size(iw * cover, ih * cover);
    canvas.saveLayer(
      rect,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: size.shortestSide * 0.06,
          sigmaY: size.shortestSide * 0.06,
          tileMode: TileMode.clamp,
        ),
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, iw, ih),
      Rect.fromLTWH(
        (size.width - drawn.width) / 2,
        (size.height - drawn.height) / 2,
        drawn.width,
        drawn.height,
      ),
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.restore();
  }

  /// The corner darkening [GradedBox] lays over a graded clip.
  static void paintVignette(Canvas canvas, Size size, double strength) {
    if (size.isEmpty || strength <= 0) return;
    final rect = Offset.zero & size;
    final shader = RadialGradient(
      radius: 0.85,
      colors: [
        Colors.transparent,
        Colors.black.withValues(alpha: (strength * 0.75).clamp(0.0, 1.0)),
      ],
      stops: const [0.55, 1.0],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  /// The grain, over a picture already painted. It is the video editor's own
  /// FX grain at slider strength, so a photo and a clip given the same amount
  /// come out with the same texture.
  ///
  /// The video preset reshuffles its scatter over a loop; a photo has no
  /// timeline to run one on, so it takes the loop's first frame and holds it.
  static void paintDecorations(Canvas canvas, Size size, PhotoEdit e) {
    if (size.isEmpty || e.adjustments.grain <= 0) return;
    EffectPainter.paintFx(
      canvas,
      size,
      FxLibrary.fromId('grain'),
      e.adjustments.grain,
    );
  }

  // ------------------------------------------------------- picture + brushes

  /// The whole picture: the framing and the grade, then the passes that need
  /// to re-read the photo — the portrait retouch, the healing brush and the
  /// mosaic.
  ///
  /// Those three all work the same way: paint a stencil, then paint a
  /// corrected copy of the picture through it with [BlendMode.srcIn]. A
  /// canvas cannot read back what it has drawn, so the copy is a second pass
  /// of [paintMedia] under a filter rather than a filter over the first.
  ///
  /// [cropped] is false while the crop tool is open, where the whole photo
  /// stays visible under the rectangle and the brushes are hidden with it —
  /// their marks are placed against the finished picture, not this one.
  static void paintPicture(
    Canvas canvas,
    Size size,
    ui.Image image,
    PhotoEdit e, {
    bool cropped = true,
    ui.Image? skinMask,
    ui.Image? cutoutMatte,
  }) {
    // The cut and the mask both knock holes in the picture, so everything
    // that paints *on* the picture — the portrait pass, the brushes — has to
    // happen inside the same layer, or it would paint over the hole.
    final knocksOut = cropped && (e.hasCutout || e.hasMask);
    if (knocksOut) canvas.saveLayer(Offset.zero & size, Paint());

    paintMedia(canvas, size, image, e, cropped: cropped);
    if (cropped && !size.isEmpty) {
      paintFace(canvas, size, image, e, skinMask);
      paintRetouch(canvas, size, image, e);
      paintPixelate(canvas, size, image, e);
      paintReshape(canvas, size, image, e, skinMask);
    }

    if (knocksOut) {
      if (e.hasCutout) paintCutout(canvas, size, cutoutMatte);
      if (e.hasMask) paintMask(canvas, size, e);
      canvas.restore();
    }
    if (cropped && !size.isEmpty) paintEffect(canvas, size, e);
  }

  /// Keeps the picture where the matte is bright and drops it where the matte
  /// is dark — the cut the Cutout tool baked.
  ///
  /// The matte is grey rather than transparent, the way the video editor's is,
  /// because `alphamerge` reads brightness. `dstIn` reads alpha, so the
  /// brightness is moved across as it is drawn.
  static void paintCutout(Canvas canvas, Size size, ui.Image? matte) {
    if (matte == null || size.isEmpty) return;
    canvas.saveLayer(Offset.zero & size, Paint()..blendMode = BlendMode.dstIn);
    canvas.drawImageRect(
      matte,
      Rect.fromLTWH(0, 0, matte.width.toDouble(), matte.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.high
        // Brightness into alpha: the matte's own colour is thrown away and
        // what is left is how opaque the picture is under it.
        ..colorFilter = const ColorFilter.matrix(<double>[
          0,
          0,
          0,
          0,
          255,
          0,
          0,
          0,
          0,
          255,
          0,
          0,
          0,
          0,
          255,
          1,
          0,
          0,
          0,
          0,
        ]),
    );
    canvas.restore();
  }

  /// Shows the picture through a shape — the Mask tool.
  static void paintMask(Canvas canvas, Size size, PhotoEdit e) {
    if (size.isEmpty || !e.hasMask) return;
    final shorter = size.shortestSide;
    final radius = e.maskSize * shorter / 2;
    final centre = Offset(e.maskX * size.width, e.maskY * size.height);
    final feather = math.max(0.5, e.maskFeather * shorter / 2);

    final path = Path();
    switch (e.maskShape) {
      case MaskShape.none:
        return;
      case MaskShape.circle:
        path.addOval(Rect.fromCircle(center: centre, radius: radius));
      case MaskShape.rectangle:
        path.addRect(
          Rect.fromCenter(
            center: centre,
            width: radius * 2,
            height: radius * 2 * 0.68,
          ),
        );
      case MaskShape.heart:
        path.addPath(_heart(centre, radius), Offset.zero);
      case MaskShape.star:
        path.addPath(_star(centre, radius), Offset.zero);
      case MaskShape.linear:
        path.addRect(
          Rect.fromLTWH(0, centre.dy - radius, size.width, radius * 2),
        );
      case MaskShape.mirror:
        path.addRect(Rect.fromLTWH(0, 0, size.width, centre.dy));
    }

    final turned = Path()
      ..addPath(
        path,
        Offset.zero,
        matrix4:
            (Matrix4.identity()
                  ..translateByDouble(centre.dx, centre.dy, 0, 1)
                  ..rotateZ(e.maskRotation)
                  ..translateByDouble(-centre.dx, -centre.dy, 0, 1))
                .storage,
      );

    // The shape is drawn into alpha with a soft edge, then used to keep or
    // to cut, which is what makes 'inverted' one flag rather than two paths.
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..blendMode = e.maskInverted ? BlendMode.dstOut : BlendMode.dstIn,
    );
    canvas.drawPath(
      turned,
      Paint()
        ..isAntiAlias = true
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, feather),
    );
    canvas.restore();
  }

  static Path _heart(Offset c, double r) {
    final path = Path()..moveTo(c.dx, c.dy + r * 0.75);
    path.cubicTo(
      c.dx - r * 1.6,
      c.dy - r * 0.2,
      c.dx - r * 0.6,
      c.dy - r * 1.2,
      c.dx,
      c.dy - r * 0.45,
    );
    path.cubicTo(
      c.dx + r * 0.6,
      c.dy - r * 1.2,
      c.dx + r * 1.6,
      c.dy - r * 0.2,
      c.dx,
      c.dy + r * 0.75,
    );
    return path..close();
  }

  static Path _star(Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r * 0.44;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(
        c.dx + radius * math.cos(a),
        c.dy + radius * math.sin(a),
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  /// Face and body shaping, painted through the same skin mask the portrait
  /// pass uses.
  ///
  /// A true liquify would push pixels about; this reads as one because the
  /// three sliders do what the eye reads as slimming, brightening the eyes
  /// and softening — through the mask, so nothing outside the skin moves.
  static void paintReshape(
    Canvas canvas,
    Size size,
    ui.Image image,
    PhotoEdit e,
    ui.Image? skinMask,
  ) {
    if (!e.hasReshape || skinMask == null || size.isEmpty) return;
    canvas.saveLayer(Offset.zero & size, Paint());
    // Slimming darkens the edge of the skin so the shape reads narrower;
    // the eyes slider lifts it; smoothing softens what is left.
    final darken = (e.reshapeSlim.clamp(-1.0, 1.0) * 0.28);
    final lift = (e.reshapeEyes.clamp(-1.0, 1.0) * 0.22);
    paintMedia(canvas, size, image, e, sampler: skinMask);
    canvas.saveLayer(Offset.zero & size, Paint()..blendMode = BlendMode.srcIn);
    if (e.reshapeSmooth != 0) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: e.reshapeSmooth.abs() * size.shortestSide * 0.01,
            sigmaY: e.reshapeSmooth.abs() * size.shortestSide * 0.01,
            tileMode: TileMode.clamp,
          ),
      );
      paintMedia(canvas, size, image, e);
      canvas.restore();
    }
    if (darken != 0 || lift != 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = (lift >= 0 ? Colors.white : Colors.black).withValues(
            alpha: (lift.abs() + darken.abs()).clamp(0.0, 0.5),
          )
          ..blendMode = BlendMode.overlay,
      );
    }
    canvas.restore();
    canvas.restore();
  }

  /// The Effect tool: grain, a leak of light, a bloom. It goes on last, over
  /// everything the picture is made of, the way an effect layer does in the
  /// video editor.
  static void paintEffect(Canvas canvas, Size size, PhotoEdit e) {
    if (size.isEmpty || e.effectId == 'none') return;
    final strength = e.effectIntensity.clamp(0.0, 1.0);
    if (strength <= 0) return;
    final rect = Offset.zero & size;
    switch (e.effectId) {
      case 'grain':
        _paintGrain(canvas, size, strength);
      case 'leak':
        canvas.drawRect(
          rect,
          Paint()
            ..blendMode = BlendMode.screen
            ..shader = ui.Gradient.linear(
              rect.topRight,
              rect.bottomLeft,
              [
                const Color(0xFFFF7A3D).withValues(alpha: 0.62 * strength),
                const Color(0x00000000),
              ],
              const [0.0, 0.62],
            ),
        );
      case 'glow':
        canvas.drawRect(
          rect,
          Paint()
            ..blendMode = BlendMode.softLight
            ..shader = ui.Gradient.radial(rect.center, rect.longestSide * 0.6, [
              Colors.white.withValues(alpha: 0.75 * strength),
              const Color(0x00FFFFFF),
            ]),
        );
      case 'vignette':
        paintVignette(canvas, size, strength);
      case 'dust':
        _paintDust(canvas, size, strength);
      case 'chroma':
        // A red/cyan split at the edges, the way a cheap lens fringes.
        final shift = strength * size.shortestSide * 0.006;
        canvas.drawRect(
          rect.translate(shift, 0),
          Paint()
            ..blendMode = BlendMode.screen
            ..color = const Color(
              0xFFFF0040,
            ).withValues(alpha: 0.16 * strength),
        );
        canvas.drawRect(
          rect.translate(-shift, 0),
          Paint()
            ..blendMode = BlendMode.screen
            ..color = const Color(
              0xFF00E5FF,
            ).withValues(alpha: 0.16 * strength),
        );
    }
  }

  static void _paintGrain(Canvas canvas, Size size, double strength) {
    // Points in two batches rather than a circle apiece: the picture wants
    // thousands of specks, and thousands of drawCircle calls is a frame the
    // device cannot paint — it hung the stage on a phone.
    //
    // The pattern is fixed rather than random, so the same picture comes out
    // of the preview and out of the saved file looking the same.
    final rnd = math.Random(7);
    final count = (size.width * size.height / 1400).clamp(200, 4000).toInt();
    final light = <Offset>[];
    final dark = <Offset>[];
    for (var i = 0; i < count; i++) {
      final at = Offset(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );
      (rnd.nextBool() ? light : dark).add(at);
    }
    final dot = math.max(1.0, size.shortestSide / 500);
    canvas.drawPoints(
      ui.PointMode.points,
      light,
      Paint()
        ..blendMode = BlendMode.overlay
        ..strokeCap = StrokeCap.round
        ..strokeWidth = dot
        ..color = Colors.white.withValues(alpha: 0.22 * strength),
    );
    canvas.drawPoints(
      ui.PointMode.points,
      dark,
      Paint()
        ..blendMode = BlendMode.overlay
        ..strokeCap = StrokeCap.round
        ..strokeWidth = dot
        ..color = Colors.black.withValues(alpha: 0.22 * strength),
    );
  }

  static void _paintDust(Canvas canvas, Size size, double strength) {
    final rnd = math.Random(19);
    final paint = Paint()
      ..blendMode = BlendMode.screen
      ..color = Colors.white.withValues(alpha: 0.5 * strength)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 46; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final len = rnd.nextDouble() * size.shortestSide * 0.05;
      paint.strokeWidth = math.max(0.6, size.shortestSide * 0.0016);
      canvas.drawLine(Offset(x, y), Offset(x, y + len), paint);
    }
  }

  /// The portrait pass, gated by the skin mask [FaceEnhancer] found. Without
  /// a mask there is nothing to enhance: a picture with no face in it is left
  /// exactly as it was rather than being softened all over.
  static void paintFace(
    Canvas canvas,
    Size size,
    ui.Image image,
    PhotoEdit e,
    ui.Image? skinMask,
  ) {
    final f = e.face;
    if (f.isNeutral || skinMask == null) return;
    final rect = Offset.zero & size;

    // Softening is a blend, so the mask carries the strength: at 50% the
    // skin is half the blurred copy and half the pores it started with.
    if (f.smooth > 0) {
      final sigma = f.smooth * 0.005 * size.shortestSide;
      _throughMask(
        canvas,
        rect,
        stencil: () => paintMedia(canvas, size, image, e, sampler: skinMask),
        stencilOpacity: f.smooth.clamp(0.0, 1.0),
        content: Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
        paint: () => paintMedia(canvas, size, image, e),
      );
    }

    // Lifting, evening out and putting the detail back are all colour, so
    // they ride in one matrix at full mask and their own strengths.
    if (f.brighten > 0 || f.evenTone > 0 || f.clarity > 0) {
      _throughMask(
        canvas,
        rect,
        stencil: () => paintMedia(canvas, size, image, e, sampler: skinMask),
        content: Paint()..colorFilter = ColorFilter.matrix(_faceMatrix(f)),
        paint: () => paintMedia(canvas, size, image, e),
      );
    }
  }

  /// Brightness, red-cast removal and local contrast as one 4x5 matrix.
  ///
  /// The red mix is what takes the heat out of blemishes: the red channel is
  /// pulled towards the pixel's own luma, which leaves the complexion and
  /// flattens what is redder than it.
  static List<double> _faceMatrix(FaceEnhance f) {
    final k = 1 + f.clarity * 0.35;
    final a = f.evenTone * 0.35;
    final off = 128 * (1 - k) + f.brighten * 30;
    return [
      (1 - a) * k + a * 0.299 * k, a * 0.587 * k, a * 0.114 * k, 0, off, //
      0, k, 0, 0, off, //
      0, 0, k, 0, off, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// The healing brush: softens what it is painted over and drains the red
  /// out of it, which between them is what a blemish is made of.
  static void paintRetouch(
    Canvas canvas,
    Size size,
    ui.Image image,
    PhotoEdit e,
  ) {
    if (e.retouch.isEmpty) return;
    final strength = e.retouchStrength.clamp(0.0, 1.0);
    final sigma = (0.25 + strength) * 0.01 * size.shortestSide;
    _throughMask(
      canvas,
      Offset.zero & size,
      stencil: () => _paintStencil(canvas, size, e.retouch),
      content: Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.clamp,
        )
        ..colorFilter = ColorFilter.matrix(
          _faceMatrix(
            FaceEnhance(evenTone: strength, brighten: strength * 0.25),
          ),
        ),
      paint: () => paintMedia(canvas, size, image, e),
    );
  }

  /// The mosaic — or a heavy blur, if that is the style chosen. The mosaic is
  /// drawn small and scaled back up with nearest-neighbour sampling, so the
  /// blocks are true squares of averaged colour rather than a soft smear.
  static void paintPixelate(
    Canvas canvas,
    Size size,
    ui.Image image,
    PhotoEdit e,
  ) {
    if (e.pixelate.isEmpty) return;
    final amount = e.pixelSize.clamp(0.0, 1.0);
    final rect = Offset.zero & size;

    if (e.pixelStyle == PixelStyle.blur) {
      final sigma = (0.008 + amount * 0.045) * size.shortestSide;
      _throughMask(
        canvas,
        rect,
        stencil: () => _paintStencil(canvas, size, e.pixelate),
        content: Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
        paint: () => paintMedia(canvas, size, image, e),
      );
      return;
    }

    // The block edge, as a share of the picture — so the same setting gives
    // the same coarseness on the preview and in the exported file.
    final block = math.max(2.0, (0.008 + amount * 0.05) * size.shortestSide);
    _throughMask(
      canvas,
      rect,
      stencil: () => _paintStencil(canvas, size, e.pixelate),
      // Three filters, innermost first: average each block's worth of the
      // picture, sample one pixel per block, then blow those pixels back up
      // with no smoothing at all. Without the first pass a block would take
      // the colour of whatever single pixel it happened to land on, which
      // leaves an edge running through a mosaic still legible.
      content: Paint()
        ..imageFilter = ui.ImageFilter.compose(
          outer: ui.ImageFilter.matrix(
            Matrix4.diagonal3Values(block, block, 1).storage,
            filterQuality: FilterQuality.none,
          ),
          inner: ui.ImageFilter.compose(
            outer: ui.ImageFilter.matrix(
              Matrix4.diagonal3Values(1 / block, 1 / block, 1).storage,
              filterQuality: FilterQuality.none,
            ),
            inner: ui.ImageFilter.blur(
              sigmaX: block * 0.42,
              sigmaY: block * 0.42,
              tileMode: TileMode.clamp,
            ),
          ),
        ),
      paint: () => paintMedia(canvas, size, image, e),
    );
  }

  /// Paints [paint] through the stencil [stencil] draws, under [content]'s
  /// filters. Three layers deep on purpose: the outer one holds the stencil,
  /// the middle one clips the copy to it, and the inner one is what the blur
  /// or the mosaic matrix acts on.
  static void _throughMask(
    Canvas canvas,
    Rect rect, {
    required VoidCallback stencil,
    required Paint content,
    required VoidCallback paint,
    double stencilOpacity = 1,
  }) {
    canvas.saveLayer(rect, Paint());
    if (stencilOpacity < 1) {
      canvas.saveLayer(
        rect,
        Paint()..color = Color.fromRGBO(0, 0, 0, stencilOpacity),
      );
      stencil();
      canvas.restore();
    } else {
      stencil();
    }
    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.srcIn);
    canvas.saveLayer(rect, content);
    paint();
    canvas.restore();
    canvas.restore();
    canvas.restore();
  }

  /// The brushed mask itself: opaque white wherever the user painted.
  static void _paintStencil(
    Canvas canvas,
    Size size,
    List<PhotoStroke> strokes,
  ) {
    for (final s in strokes) {
      _paintStroke(canvas, size, s, Paint()..color = const Color(0xFFFFFFFF));
    }
  }

  /// One stroke, in the canvas it is being painted into. A tap that never
  /// moved is a dot rather than a line of no length.
  static void _paintStroke(
    Canvas canvas,
    Size size,
    PhotoStroke stroke,
    Paint paint,
  ) {
    if (stroke.points.isEmpty) return;
    final width = math.max(1.0, stroke.width * size.shortestSide);
    final pts = [
      for (final p in stroke.points)
        Offset(p.dx * size.width, p.dy * size.height),
    ];
    if (pts.length == 1) {
      canvas.drawCircle(
        pts.first,
        width / 2,
        paint
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );
      return;
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = (pts[i] + pts[i + 1]) / 2;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(
      path,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  // --------------------------------------------------------------- overlays

  /// Everything laid over the finished picture, back to front: the ink, then
  /// the stickers, then the text, then the mark.
  static void paintOverlays(
    Canvas canvas,
    Size size,
    PhotoEdit e, {
    ui.Image? logo,
    Map<String, ui.Image> pips = const {},
  }) {
    if (size.isEmpty) return;
    paintMarkup(canvas, size, e);
    // Pictures first: a caption or an emoji is meant to sit on top of one.
    for (final p in e.pips) {
      paintPip(canvas, size, p, pips[p.path]);
    }
    for (final s in e.stickers) {
      paintSticker(canvas, size, s);
    }
    for (final t in e.texts) {
      paintText(canvas, size, t);
    }
    paintWatermark(canvas, size, e.watermark, logo: logo);
  }

  /// The ink. Every stroke shares one layer so the eraser can cut through
  /// what came before it without taking the photograph with it.
  static void paintMarkup(Canvas canvas, Size size, PhotoEdit e) {
    if (e.markup.isEmpty) return;
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final s in e.markup) {
      _paintStroke(
        canvas,
        size,
        s,
        Paint()
          ..color = Color(s.color)
          ..blendMode = s.erase ? BlendMode.clear : BlendMode.srcOver,
      );
    }
    canvas.restore();
  }

  /// Overlay sizes are authored against a reference canvas, exactly as the
  /// video editor's are. A photo has no fixed shape to reference, so the
  /// shorter side stands in: it makes a caption the same share of the picture
  /// whichever way round the picture is.
  static double overlayScale(Size size) =>
      size.shortestSide / kCanvasReferenceHeight;

  static void paintText(Canvas canvas, Size size, TextLayer layer) {
    if (layer.text.trim().isEmpty) return;
    final scale = overlayScale(size) * layer.transform.scale;
    final maxWidth = size.width * 1.6;
    // Measure once to size the gradient, then build the real painter — the
    // same two-pass the rasterizer does, so the two agree glyph for glyph.
    final measure = OverlayRasterizer.buildTextPainter(layer, scale)
      ..layout(maxWidth: maxWidth);
    final painter = OverlayRasterizer.buildTextPainter(
      layer,
      scale,
      gradientBounds: Size(measure.width, measure.height),
    )..layout(maxWidth: maxWidth);

    final pad = layer.backgroundPadding * scale;
    final hasBg = (layer.backgroundColor >> 24) != 0;
    final contentW = painter.width + (hasBg ? pad * 2 : 0);
    final contentH = painter.height + (hasBg ? pad * 2 : 0);
    final opacity = layer.transform.opacity.clamp(0.0, 1.0);

    canvas.save();
    canvas.translate(
      layer.transform.x * size.width,
      layer.transform.y * size.height,
    );
    if (layer.transform.rotation != 0) canvas.rotate(layer.transform.rotation);
    if (opacity < 1) {
      final margin = layer.shadowBlur * scale + layer.strokeWidth * scale * 2;
      canvas.saveLayer(
        Rect.fromCenter(
          center: Offset.zero,
          width: contentW + margin * 4 + 24,
          height: contentH + margin * 4 + 24,
        ),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
    }
    if (hasBg) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: contentW,
            height: contentH,
          ),
          Radius.circular(layer.backgroundRadius * scale),
        ),
        Paint()..color = Color(layer.backgroundColor),
      );
    }
    final origin = Offset(-painter.width / 2, -painter.height / 2);
    if (layer.strokeWidth > 0) {
      (OverlayRasterizer.buildTextPainter(
        layer,
        scale,
        strokeOnly: true,
      )..layout(maxWidth: maxWidth)).paint(canvas, origin);
    }
    painter.paint(canvas, origin);
    if (opacity < 1) canvas.restore();
    canvas.restore();
  }

  static void paintSticker(Canvas canvas, Size size, StickerLayer layer) {
    final side = layer.size * overlayScale(size) * layer.transform.scale;
    if (side <= 0) return;
    final opacity = layer.transform.opacity.clamp(0.0, 1.0);

    canvas.save();
    canvas.translate(
      layer.transform.x * size.width,
      layer.transform.y * size.height,
    );
    if (layer.transform.rotation != 0) canvas.rotate(layer.transform.rotation);
    if (opacity < 1) {
      canvas.saveLayer(
        Rect.fromCenter(center: Offset.zero, width: side * 2, height: side * 2),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
    }
    if (layer.isEmoji) {
      final tp = TextPainter(
        text: TextSpan(
          text: layer.content,
          style: TextStyle(fontSize: side * 0.86, color: Color(layer.color)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    } else {
      OverlayRasterizer.paintShape(
        canvas,
        layer.content,
        side,
        Color(layer.color),
      );
    }
    if (opacity < 1) canvas.restore();
    canvas.restore();
  }

  /// The creator's mark. A text mark is a text layer — the same one the
  /// video editor draws — so the two cannot drift apart.
  static void paintWatermark(
    Canvas canvas,
    Size size,
    Watermark mark, {
    ui.Image? logo,
  }) {
    if (!mark.isReady) return;
    if (mark.type == WatermarkType.text) {
      paintText(canvas, size, mark.asTextLayer());
      return;
    }
    if (logo == null || logo.width <= 0) return;
    final scale = overlayScale(size) * mark.transform.scale;
    final w = mark.imageSize * scale;
    final h = w * logo.height / logo.width;
    canvas.save();
    canvas.translate(
      mark.transform.x * size.width,
      mark.transform.y * size.height,
    );
    if (mark.transform.rotation != 0) canvas.rotate(mark.transform.rotation);
    canvas.drawImageRect(
      logo,
      Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high
        ..color = Color.fromRGBO(
          0,
          0,
          0,
          mark.transform.opacity.clamp(0.0, 1.0),
        ),
    );
    canvas.restore();
  }

  /// The transform behind any overlay, whichever kind it is.
  static LayerTransform? transformOf(Object? overlay) => switch (overlay) {
    TextLayer l => l.transform,
    StickerLayer l => l.transform,
    Watermark m => m.transform,
    PhotoImageLayer l => l.transform,
    _ => null,
  };

  /// One picture laid over the photo, at the place, size and angle the user
  /// dragged it to.
  static void paintPip(
    Canvas canvas,
    Size size,
    PhotoImageLayer layer,
    ui.Image? image,
  ) {
    if (image == null || size.isEmpty) return;
    final rect = pipRect(size, layer, image);
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(layer.transform.rotation);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    final radius = layer.corner * rect.shortestSide / 2;
    if (radius > 0.5) {
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high
        ..color = Colors.white.withValues(
          alpha: layer.transform.opacity.clamp(0.0, 1.0),
        ),
    );
    if (radius > 0.5) canvas.restore();
    canvas.restore();
  }

  /// Where a picture layer lands, keeping the picture's own shape.
  static Rect pipRect(Size size, PhotoImageLayer layer, ui.Image image) {
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final aspect = ih <= 0 ? 1.0 : iw / ih;
    // Scale is a fraction of the photo's width, so the same number means the
    // same size whatever the picture's own resolution is.
    final w = size.width * layer.transform.scale;
    return Rect.fromCenter(
      center: Offset(
        layer.transform.x * size.width,
        layer.transform.y * size.height,
      ),
      width: w,
      height: w / (aspect <= 0 ? 1 : aspect),
    );
  }

  /// The box an overlay occupies on a canvas of [size], before its rotation —
  /// what the stage draws its selection frame around and hit-tests taps
  /// against.
  static Rect overlayRect(Size size, Object overlay, {ui.Image? logo}) {
    final transform = transformOf(overlay);
    if (transform == null) return Rect.zero;
    final centre = Offset(transform.x * size.width, transform.y * size.height);
    final scale = overlayScale(size) * transform.scale;

    Size box;
    switch (overlay) {
      case StickerLayer l:
        box = Size.square(l.size * scale);
      case Watermark m when m.type == WatermarkType.image:
        final w = m.imageSize * scale;
        box = Size(w, logo == null ? w : w * logo.height / logo.width);
      case Watermark m:
        box = _textBox(size, m.asTextLayer(), scale);
      case TextLayer l:
        box = _textBox(size, l, scale);
      case PhotoImageLayer _:
        // Its own helper knows the picture's shape; this one does not have
        // the image to ask.
        return Rect.zero;
      default:
        return Rect.zero;
    }
    return Rect.fromCenter(
      center: centre,
      width: math.max(box.width, 12),
      height: math.max(box.height, 12),
    );
  }

  static Size _textBox(Size size, TextLayer layer, double scale) {
    final painter = OverlayRasterizer.buildTextPainter(layer, scale)
      ..layout(maxWidth: size.width * 1.6);
    final hasBg = (layer.backgroundColor >> 24) != 0;
    final pad = hasBg ? layer.backgroundPadding * scale * 2 : 0.0;
    return Size(painter.width + pad, painter.height + pad);
  }

  /// Whether [point], in canvas pixels, lands on [overlay] — the rotation
  /// taken off the point rather than put on the box.
  static bool hitTest(
    Size size,
    Object overlay,
    Offset point, {
    ui.Image? logo,
    double slop = 0,
  }) {
    final rect = overlayRect(size, overlay, logo: logo);
    if (rect.isEmpty) return false;
    final rotation = transformOf(overlay)?.rotation ?? 0;
    var local = point - rect.center;
    if (rotation != 0) {
      final cos = math.cos(-rotation), sin = math.sin(-rotation);
      local = Offset(
        local.dx * cos - local.dy * sin,
        local.dx * sin + local.dy * cos,
      );
    }
    return local.dx.abs() <= rect.width / 2 + slop &&
        local.dy.abs() <= rect.height / 2 + slop;
  }

  /// Decodes a photo, optionally at a smaller size — the stage only ever
  /// needs enough pixels to fill itself, and a 50MP phone photo decoded at
  /// full size for a 400pt preview is how an editor runs a device out of
  /// memory.
  static Future<ui.Image?> decode(String path, {int? maxSide}) async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      if (maxSide == null) {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        codec.dispose();
        return frame.image;
      }
      // Measure first so the target keeps the photo's aspect ratio exactly.
      final probe = await ui.instantiateImageCodec(bytes);
      final head = await probe.getNextFrame();
      final w = head.image.width, h = head.image.height;
      probe.dispose();
      final longest = math.max(w, h);
      if (longest <= maxSide) return head.image;
      head.image.dispose();
      final k = maxSide / longest;
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: math.max(1, (w * k).round()),
        targetHeight: math.max(1, (h * k).round()),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (e) {
      debugPrint('photo decode failed: $e');
      return null;
    }
  }

  /// Renders the edit at full size and writes it to [path] as a PNG.
  ///
  /// [maxSide] caps a very large crop so the recorder is not asked for a
  /// surface the device cannot hold; anything smaller keeps every pixel it
  /// started with.
  static Future<String?> renderToFile(
    ui.Image image,
    PhotoEdit edit, {
    required String path,
    int maxSide = 4096,
    ui.Image? skinMask,
    ui.Image? cutoutMatte,
    Map<String, ui.Image> pips = const {},
  }) async {
    final bytes = await renderPng(
      image,
      edit,
      maxSide: maxSide,
      skinMask: skinMask,
      cutoutMatte: cutoutMatte,
      pips: pips,
    );
    if (bytes == null) return null;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// The edit as PNG bytes, at full resolution.
  static Future<Uint8List?> renderPng(
    ui.Image image,
    PhotoEdit edit, {
    int maxSide = 4096,
    ui.Image? skinMask,
    ui.Image? cutoutMatte,
    Map<String, ui.Image> pips = const {},
  }) async {
    final out = outputSize(image, edit);
    var w = out.width, h = out.height;
    final longest = math.max(w, h);
    if (longest > maxSide) {
      final k = maxSide / longest;
      w *= k;
      h *= k;
    }
    final width = w.round().clamp(1, maxSide);
    final height = h.round().clamp(1, maxSide);
    final size = Size(width.toDouble(), height.toDouble());

    ui.Image media;
    {
      final recorder = ui.PictureRecorder();
      paintPicture(
        Canvas(recorder),
        size,
        image,
        edit,
        skinMask: skinMask,
        cutoutMatte: cutoutMatte,
      );
      final picture = recorder.endRecording();
      media = await picture.toImage(width, height);
      picture.dispose();
    }

    // The half of the grade a matrix cannot carry, run through the very
    // shader the live preview uses.
    final shaded = await _extras(media, edit, size);
    if (!identical(shaded, media)) media.dispose();

    // The logo is the one overlay that is not drawn from what the edit
    // already holds, so it is fetched before the canvas opens.
    final logo = await loadLogo(edit.watermark);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(shaded, Offset.zero, Paint());
    paintDecorations(canvas, size, edit);
    paintOverlays(canvas, size, edit, logo: logo, pips: pips);
    final picture = recorder.endRecording();
    shaded.dispose();
    logo?.dispose();
    final bytes = await pictureToPng(picture, width, height);
    picture.dispose();
    return bytes;
  }

  /// Decodes the watermark's logo file, or null when the mark is text, has no
  /// logo, or points at a file that has since gone.
  static Future<ui.Image?> loadLogo(Watermark mark) async {
    if (!mark.isReady || mark.type != WatermarkType.image) return null;
    final path = mark.imagePath;
    if (path == null || path.isEmpty) return null;
    return decode(path, maxSide: 2048);
  }

  static ui.FragmentProgram? _program;
  static bool _programFailed = false;

  /// Runs `shaders/grade_extras.frag` over [src] — the offline twin of
  /// [GradeExtrasBox], with the uniforms in the order the shader declares
  /// them. Returns [src] untouched when there is nothing to do, or when the
  /// shader will not load: no second pass beats no picture.
  static Future<ui.Image> _extras(
    ui.Image src,
    PhotoEdit edit,
    Size size,
  ) async {
    final adj = edit.adjustments;
    final gamma = edit.grade.gamma;
    if (!_wantsExtras(adj, gamma)) return src;

    if (_program == null && !_programFailed) {
      try {
        _program = await ui.FragmentProgram.fromAsset(
          'shaders/grade_extras.frag',
        );
      } catch (e) {
        _programFailed = true;
        debugPrint('grade shader unavailable: $e');
      }
    }
    final program = _program;
    if (program == null) return src;

    final (lo, mid, hi) = adj.curvePoints;
    final shader = program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, lo)
      ..setFloat(3, mid)
      ..setFloat(4, hi)
      ..setFloat(5, adj.hasCurves ? 1 : 0)
      ..setFloat(6, gamma)
      ..setFloat(7, adj.sharpen * 1.5)
      ..setFloat(8, adj.denoise)
      // Grain is the Adjust panel's own; the FX texture paints separately.
      ..setFloat(9, 0)
      ..setFloat(10, 0)
      ..setImageSampler(0, src);

    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(Offset.zero & size, Paint()..shader = shader);
    final picture = recorder.endRecording();
    final out = await picture.toImage(size.width.round(), size.height.round());
    picture.dispose();
    shader.dispose();
    return out;
  }

  /// Grain is left to [paintDecorations], so it is not a reason on its own to
  /// run the shader pass.
  static bool _wantsExtras(Adjustments adj, double gamma) =>
      adj.hasCurves || adj.sharpen > 0 || adj.denoise > 0 || gamma != 1;
}
