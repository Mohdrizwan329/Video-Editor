import 'enums.dart';
import 'project.dart';
import 'template.dart';

/// The built-in template gallery.
///
/// Every template is expressed with the same primitives the user has — clips,
/// transitions, keyframes, text presets — so opening one leaves a fully
/// editable project rather than a locked-down effect.
class TemplateLibrary {
  TemplateLibrary._();

  static const List<String> categories = [
    'Reels', 'Vlog', 'Travel', 'Promo', 'Story', 'Cinematic'
  ];

  static List<VideoTemplate> byCategory(String c) =>
      all.where((t) => t.category == c).toList();

  static VideoTemplate? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  static final List<VideoTemplate> all = [
    // --------------------------------------------------------------- Reels
    VideoTemplate(
      id: 'beatDrop',
      name: 'Beat Drop',
      category: 'Reels',
      description: 'Six fast cuts with a punchy grade.',
      ratio: CanvasRatio.r9x16,
      slots: [
        for (var i = 0; i < 6; i++)
          TemplateSlot(
            duration: const Duration(milliseconds: 700),
            filterId: 'pop',
            transitionOut: i.isEven ? TransitionType.zoomIn : TransitionType.slideLeft,
            transitionDuration: const Duration(milliseconds: 180),
            move: i.isEven
                ? const TemplateMove(fromScale: 1.0, toScale: 1.14)
                : const TemplateMove(fromScale: 1.14, toScale: 1.0),
          ),
      ],
      texts: [
        TemplateText(
          placeholder: 'YOUR HOOK',
          presetId: 'impact',
          slot: 0,
          y: 0.22,
          fontSize: 92,
          animationIn: LayerAnimation.pop,
          animationOut: LayerAnimation.fade,
        ),
      ],
    ),
    VideoTemplate(
      id: 'quickIntro',
      name: 'Quick Intro',
      category: 'Reels',
      description: 'Title card, then three beats.',
      ratio: CanvasRatio.r9x16,
      slots: [
        TemplateSlot(
          duration: Duration(milliseconds: 1400),
          filterId: 'cine',
          transitionOut: TransitionType.whiteFlash,
          transitionDuration: Duration(milliseconds: 220),
          move: TemplateMove(fromScale: 1.2, toScale: 1.0),
        ),
        TemplateSlot(
          duration: Duration(milliseconds: 1100),
          filterId: 'cine',
          transitionOut: TransitionType.slideUp,
          transitionDuration: Duration(milliseconds: 260),
        ),
        TemplateSlot(
          duration: Duration(milliseconds: 1100),
          filterId: 'cine',
          transitionOut: TransitionType.slideUp,
          transitionDuration: Duration(milliseconds: 260),
        ),
        TemplateSlot(
          duration: Duration(milliseconds: 1600),
          filterId: 'cine',
          transitionOut: TransitionType.none,
          move: TemplateMove(fromScale: 1.0, toScale: 1.12),
        ),
      ],
      texts: [
        TemplateText(
          placeholder: 'NEW VIDEO',
          presetId: 'headline',
          slot: 0,
          y: 0.5,
          fontSize: 110,
          animationIn: LayerAnimation.scale,
          animationOut: LayerAnimation.fade,
        ),
        TemplateText(
          placeholder: 'Subscribe',
          presetId: 'accentChip',
          slot: 3,
          y: 0.82,
          fontSize: 54,
          animationIn: LayerAnimation.slideUp,
          animationOut: LayerAnimation.fade,
        ),
      ],
    ),
    VideoTemplate(
      id: 'listicle',
      name: 'Top 5',
      category: 'Reels',
      description: 'Numbered countdown, one shot each.',
      ratio: CanvasRatio.r9x16,
      slots: [
        for (var i = 0; i < 5; i++)
          const TemplateSlot(
            duration: Duration(milliseconds: 1500),
            filterId: 'clean',
            transitionOut: TransitionType.wipeLeft,
            transitionDuration: Duration(milliseconds: 240),
          ),
      ],
      texts: [
        for (var i = 0; i < 5; i++)
          TemplateText(
            placeholder: '#${5 - i}',
            presetId: 'poster',
            slot: i,
            x: 0.2,
            y: 0.2,
            fontSize: 96,
            animationIn: LayerAnimation.slideRight,
            animationOut: LayerAnimation.fade,
          ),
      ],
    ),
    // ----------------------------------------------------------------- Vlog
    VideoTemplate(
      id: 'dayInLife',
      name: 'Day In Life',
      category: 'Vlog',
      description: 'Warm grade, slow moves, lower thirds.',
      ratio: CanvasRatio.r9x16,
      slots: [
        for (var i = 0; i < 5; i++)
          TemplateSlot(
            duration: const Duration(milliseconds: 2600),
            filterId: 'portra',
            transitionOut: TransitionType.dissolve,
            transitionDuration: const Duration(milliseconds: 500),
            move: TemplateMove(
                fromScale: 1.0, toScale: 1.08, fromX: 0, toX: i.isEven ? 0.05 : -0.05),
          ),
      ],
      texts: [
        TemplateText(
          placeholder: 'Morning',
          presetId: 'lower3rd',
          slot: 0,
          x: 0.32,
          y: 0.86,
          fontSize: 48,
          animationIn: LayerAnimation.slideRight,
          animationOut: LayerAnimation.fade,
          duration: Duration(milliseconds: 1800),
        ),
      ],
    ),
    VideoTemplate(
      id: 'weeklyRecap',
      name: 'Weekly Recap',
      category: 'Vlog',
      description: 'Eight quick moments, film look.',
      ratio: CanvasRatio.r16x9,
      slots: [
        for (var i = 0; i < 8; i++)
          const TemplateSlot(
            duration: Duration(milliseconds: 1200),
            filterId: 'kodak',
            transitionOut: TransitionType.smoothLeft,
            transitionDuration: Duration(milliseconds: 300),
          ),
      ],
      texts: [
        TemplateText(
          placeholder: 'THIS WEEK',
          presetId: 'cinema',
          slot: 0,
          y: 0.5,
          fontSize: 84,
          animationIn: LayerAnimation.fade,
          animationOut: LayerAnimation.fade,
        ),
      ],
    ),
    // --------------------------------------------------------------- Travel
    VideoTemplate(
      id: 'travelDiary',
      name: 'Travel Diary',
      category: 'Travel',
      description: 'Wide grade, drifting moves, place cards.',
      ratio: CanvasRatio.r9x16,
      slots: [
        for (var i = 0; i < 6; i++)
          TemplateSlot(
            duration: const Duration(milliseconds: 2200),
            filterId: 'tropical',
            transitionOut:
                i.isEven ? TransitionType.smoothUp : TransitionType.circleOpen,
            transitionDuration: const Duration(milliseconds: 420),
            move: TemplateMove(
                fromScale: i.isEven ? 1.0 : 1.12,
                toScale: i.isEven ? 1.12 : 1.0,
                fromY: 0,
                toY: i.isEven ? -0.04 : 0.04),
          ),
      ],
      texts: [
        TemplateText(
          placeholder: 'DESTINATION',
          presetId: 'sunsetRetro',
          slot: 0,
          y: 0.3,
          fontSize: 88,
          animationIn: LayerAnimation.flyIn,
          animationOut: LayerAnimation.fade,
        ),
      ],
      stickers: [('✈️', 0, 0.82, 0.14, 0.7)],
    ),
    VideoTemplate(
      id: 'goldenHour',
      name: 'Golden Hour',
      category: 'Travel',
      description: 'Slow dissolves, warm sun grade.',
      ratio: CanvasRatio.r235x1,
      slots: [
        for (var i = 0; i < 4; i++)
          const TemplateSlot(
            duration: Duration(milliseconds: 3000),
            filterId: 'goldenHour',
            transitionOut: TransitionType.dissolve,
            transitionDuration: Duration(milliseconds: 800),
            move: TemplateMove(fromScale: 1.0, toScale: 1.1),
          ),
      ],
    ),
    // ---------------------------------------------------------------- Promo
    VideoTemplate(
      id: 'productDrop',
      name: 'Product Drop',
      category: 'Promo',
      description: 'Punch cuts, price chip, call to action.',
      ratio: CanvasRatio.r1x1,
      slots: [
        TemplateSlot(
          duration: Duration(milliseconds: 1200),
          filterId: 'crisp',
          transitionOut: TransitionType.squeezeH,
          transitionDuration: Duration(milliseconds: 200),
          move: TemplateMove(fromScale: 1.15, toScale: 1.0),
        ),
        TemplateSlot(
          duration: Duration(milliseconds: 1000),
          filterId: 'crisp',
          transitionOut: TransitionType.wipeRight,
          transitionDuration: Duration(milliseconds: 200),
        ),
        TemplateSlot(
          duration: Duration(milliseconds: 1000),
          filterId: 'crisp',
          transitionOut: TransitionType.wipeLeft,
          transitionDuration: Duration(milliseconds: 200),
        ),
        TemplateSlot(
          duration: Duration(milliseconds: 1800),
          filterId: 'crisp',
          transitionOut: TransitionType.none,
          move: TemplateMove(fromScale: 1.0, toScale: 1.08),
        ),
      ],
      texts: [
        TemplateText(
          placeholder: 'NEW DROP',
          presetId: 'redAlert',
          slot: 0,
          y: 0.18,
          fontSize: 72,
          animationIn: LayerAnimation.slideDown,
          animationOut: LayerAnimation.fade,
        ),
        TemplateText(
          placeholder: 'Shop now',
          presetId: 'chip',
          slot: 3,
          y: 0.84,
          fontSize: 56,
          animationIn: LayerAnimation.pop,
          animationOut: LayerAnimation.fade,
        ),
      ],
    ),
    VideoTemplate(
      id: 'saleBanner',
      name: 'Flash Sale',
      category: 'Promo',
      description: 'Three panels with a bold bar.',
      ratio: CanvasRatio.r4x5,
      slots: [
        for (var i = 0; i < 3; i++)
          const TemplateSlot(
            duration: Duration(milliseconds: 1600),
            filterId: 'vivid',
            transitionOut: TransitionType.horzOpen,
            transitionDuration: Duration(milliseconds: 260),
          ),
      ],
      texts: [
        TemplateText(
          placeholder: '50% OFF',
          presetId: 'blackBar',
          slot: -1,
          y: 0.9,
          fontSize: 64,
          animationIn: LayerAnimation.slideUp,
          animationOut: LayerAnimation.slideDown,
        ),
      ],
    ),
    // ---------------------------------------------------------------- Story
    VideoTemplate(
      id: 'photoStory',
      name: 'Photo Story',
      category: 'Story',
      description: 'Stills with slow pushes and captions.',
      ratio: CanvasRatio.r9x16,
      slots: [
        for (var i = 0; i < 5; i++)
          TemplateSlot(
            duration: const Duration(milliseconds: 2400),
            filterId: 'airy',
            transitionOut: TransitionType.fade,
            transitionDuration: const Duration(milliseconds: 500),
            move: TemplateMove(
                fromScale: 1.0,
                toScale: 1.1,
                fromX: i.isEven ? -0.04 : 0.04,
                toX: i.isEven ? 0.04 : -0.04),
          ),
      ],
      texts: [
        TemplateText(
          placeholder: 'Say something',
          presetId: 'subtitle',
          slot: 0,
          y: 0.88,
          fontSize: 46,
          animationIn: LayerAnimation.fade,
          animationOut: LayerAnimation.fade,
        ),
      ],
    ),
    VideoTemplate(
      id: 'birthday',
      name: 'Celebrate',
      category: 'Story',
      description: 'Bright cuts with party stickers.',
      ratio: CanvasRatio.r9x16,
      slots: [
        for (var i = 0; i < 6; i++)
          const TemplateSlot(
            duration: Duration(milliseconds: 1400),
            filterId: 'candy',
            transitionOut: TransitionType.circleCrop,
            transitionDuration: Duration(milliseconds: 280),
          ),
      ],
      texts: [
        TemplateText(
          placeholder: 'HAPPY BIRTHDAY',
          presetId: 'script',
          slot: 0,
          y: 0.24,
          fontSize: 78,
          animationIn: LayerAnimation.bounce,
          animationOut: LayerAnimation.fade,
        ),
      ],
      stickers: [
        ('🎉', 0, 0.18, 0.16, 0.8),
        ('🎂', 2, 0.8, 0.8, 0.9),
        ('✨', 4, 0.5, 0.14, 0.7),
      ],
    ),
    // ------------------------------------------------------------ Cinematic
    VideoTemplate(
      id: 'trailer',
      name: 'Trailer',
      category: 'Cinematic',
      description: 'Black fades, wide bars, title at the end.',
      ratio: CanvasRatio.r235x1,
      slots: [
        for (var i = 0; i < 5; i++)
          TemplateSlot(
            duration: Duration(milliseconds: i == 4 ? 3000 : 1600),
            filterId: 'blockbuster',
            transitionOut:
                i == 4 ? TransitionType.none : TransitionType.blackFade,
            transitionDuration: const Duration(milliseconds: 500),
            move: TemplateMove(
                fromScale: i.isEven ? 1.06 : 1.0,
                toScale: i.isEven ? 1.0 : 1.06),
          ),
      ],
      texts: [
        TemplateText(
          placeholder: 'THE TITLE',
          presetId: 'cinema',
          slot: 4,
          y: 0.5,
          fontSize: 96,
          startOffset: Duration(milliseconds: 600),
          animationIn: LayerAnimation.scale,
          animationOut: LayerAnimation.fade,
        ),
      ],
      background: null,
    ),
    VideoTemplate(
      id: 'moodFilm',
      name: 'Mood Film',
      category: 'Cinematic',
      description: 'Long dissolves, muted grade, blurred frame.',
      ratio: CanvasRatio.r16x9,
      slots: [
        for (var i = 0; i < 4; i++)
          const TemplateSlot(
            duration: Duration(milliseconds: 3200),
            filterId: 'moody',
            transitionOut: TransitionType.dissolve,
            transitionDuration: Duration(milliseconds: 900),
            move: TemplateMove(fromScale: 1.0, toScale: 1.06),
          ),
      ],
    ),
    VideoTemplate(
      id: 'slowmo',
      name: 'Slow Motion',
      category: 'Cinematic',
      description: 'Ramped speed on every shot.',
      ratio: CanvasRatio.r9x16,
      slots: [
        for (var i = 0; i < 4; i++)
          const TemplateSlot(
            duration: Duration(milliseconds: 2400),
            filterId: 'cine',
            transitionOut: TransitionType.smoothUp,
            transitionDuration: Duration(milliseconds: 380),
            speed: 0.5,
          ),
      ],
    ),
  ];
}

/// Convenience so callers can build the background without importing project.
BackgroundStyle blurredBackground() =>
    BackgroundStyle(type: BackgroundType.blur, blurAmount: 24);
