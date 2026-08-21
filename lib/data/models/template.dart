import 'enums.dart';
import 'keyframe.dart';
import 'layers.dart';
import 'project.dart';
import 'video_clip.dart';

/// A text element baked into a template, positioned in normalised canvas
/// space and timed relative to the slot it belongs to.
class TemplateText {
  const TemplateText({
    required this.placeholder,
    required this.presetId,
    this.slot = 0,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1,
    this.fontSize = 74,
    this.startOffset = Duration.zero,
    this.duration,
    this.animationIn = LayerAnimation.fade,
    this.animationOut = LayerAnimation.fade,
  });

  final String placeholder;

  /// Which [TextPresetLibrary] look to apply.
  final String presetId;

  /// Index of the media slot this text sits over; -1 pins it to the whole
  /// project instead.
  final int slot;
  final double x;
  final double y;
  final double scale;
  final double fontSize;
  final Duration startOffset;

  /// Null means "as long as the slot".
  final Duration? duration;
  final LayerAnimation animationIn;
  final LayerAnimation animationOut;
}

/// A Ken Burns style move applied to a slot's clip.
class TemplateMove {
  const TemplateMove({
    required this.fromScale,
    required this.toScale,
    this.fromX = 0,
    this.toX = 0,
    this.fromY = 0,
    this.toY = 0,
  });

  final double fromScale;
  final double toScale;
  final double fromX;
  final double toX;
  final double fromY;
  final double toY;
}

/// One media slot: how long it runs and what happens to it.
class TemplateSlot {
  const TemplateSlot({
    this.duration = const Duration(milliseconds: 1800),
    this.filterId = 'none',
    this.transitionOut = TransitionType.fade,
    this.transitionDuration = const Duration(milliseconds: 400),
    this.move,
    this.speed = 1,
  });

  final Duration duration;
  final String filterId;

  /// Transition into the next slot.
  final TransitionType transitionOut;
  final Duration transitionDuration;
  final TemplateMove? move;
  final double speed;
}

/// A prefab project the user drops their own media into.
class VideoTemplate {
  const VideoTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.ratio,
    required this.slots,
    this.texts = const [],
    this.stickers = const [],
    this.description = '',
    this.background,
  });

  final String id;
  final String name;
  final String category;
  final CanvasRatio ratio;
  final List<TemplateSlot> slots;
  final List<TemplateText> texts;

  /// (emoji, slot, x, y, scale) tuples.
  final List<(String, int, double, double, double)> stickers;
  final String description;
  final BackgroundStyle? background;

  int get slotCount => slots.length;

  Duration get approximateDuration {
    var total = Duration.zero;
    for (var i = 0; i < slots.length; i++) {
      total += slots[i].duration;
      if (i < slots.length - 1 &&
          slots[i].transitionOut != TransitionType.none) {
        total -= slots[i].transitionDuration;
      }
    }
    return total;
  }
}

/// Fills a template with the user's media.
///
/// Media is cycled when the user picks fewer items than there are slots, so a
/// template always produces a complete edit rather than a half-empty one.
class TemplateApplier {
  TemplateApplier._();

  static void apply({
    required VideoTemplate template,
    required Project project,
    required List<VideoClip> media,
  }) {
    if (media.isEmpty) return;

    project
      ..ratio = template.ratio
      ..clips.clear()
      ..texts.clear()
      ..stickers.clear();
    if (template.background != null) {
      project.background = template.background!.copy();
    }

    for (var i = 0; i < template.slots.length; i++) {
      final slot = template.slots[i];
      final source = media[i % media.length];
      final clip = source.copyWith();

      // Trim the middle of the source down to the slot length, since the
      // centre of a shot is usually the usable part.
      final wanted = Duration(
          microseconds:
              (slot.duration.inMicroseconds * slot.speed).round());
      if (!clip.isImage && clip.trimmedDuration > wanted) {
        final slack = clip.trimmedDuration - wanted;
        final lead = Duration(microseconds: slack.inMicroseconds ~/ 2);
        clip
          ..trimStart = clip.trimStart + lead
          ..trimEnd = clip.trimStart + wanted;
      } else if (clip.isImage) {
        clip
          ..sourceDuration = wanted
          ..trimStart = Duration.zero
          ..trimEnd = wanted;
      }

      clip
        ..speed = slot.speed
        ..filterId = slot.filterId
        ..transitionType =
            i == template.slots.length - 1 ? TransitionType.none : slot.transitionOut
        ..transitionDuration = slot.transitionDuration;

      final move = slot.move;
      if (move != null) {
        // Ken Burns as two keyframes — the same machinery the user gets.
        clip.track(KeyframeProperty.scale)
          ..set(Duration.zero, move.fromScale, easing: KeyframeEasing.linear)
          ..set(slot.duration, move.toScale, easing: KeyframeEasing.easeInOut);
        if (move.fromX != move.toX) {
          clip.track(KeyframeProperty.x)
            ..set(Duration.zero, move.fromX, easing: KeyframeEasing.linear)
            ..set(slot.duration, move.toX, easing: KeyframeEasing.easeInOut);
        }
        if (move.fromY != move.toY) {
          clip.track(KeyframeProperty.y)
            ..set(Duration.zero, move.fromY, easing: KeyframeEasing.linear)
            ..set(slot.duration, move.toY, easing: KeyframeEasing.easeInOut);
        }
      }
      project.clips.add(clip);
    }

    for (final t in template.texts) {
      final slotIndex = t.slot.clamp(-1, project.clips.length - 1);
      final start = slotIndex < 0
          ? t.startOffset
          : project.clipStart(slotIndex) + t.startOffset;
      final duration = t.duration ??
          (slotIndex < 0
              ? project.videoDuration
              : project.clips[slotIndex].timelineDuration - t.startOffset);

      project.texts.add(TextLayer(
        start: start,
        duration: duration < const Duration(milliseconds: 400)
            ? const Duration(milliseconds: 900)
            : duration,
        text: t.placeholder,
        fontSize: t.fontSize,
        animationIn: t.animationIn,
        animationOut: t.animationOut,
        transform: LayerTransform(x: t.x, y: t.y, scale: t.scale),
      ));
    }

    for (final (emoji, slot, x, y, scale) in template.stickers) {
      final slotIndex = slot.clamp(0, project.clips.length - 1);
      project.stickers.add(StickerLayer(
        start: project.clipStart(slotIndex),
        duration: project.clips[slotIndex].timelineDuration,
        content: emoji,
        transform: LayerTransform(x: x, y: y, scale: scale),
        animationIn: LayerAnimation.pop,
        animationOut: LayerAnimation.fade,
      ));
    }
  }
}
