import 'layers.dart';

/// A ready-made text look from the style gallery: pick one and
/// every style field is set at once, then tweak individual fields after.
class TextStylePreset {
  const TextStylePreset({
    required this.id,
    required this.name,
    required this.category,
    this.fontFamily = 'Poppins',
    this.color = 0xFFFFFFFF,
    this.bold = false,
    this.italic = false,
    this.letterSpacing = 0,
    this.strokeWidth = 0,
    this.strokeColor = 0xFF000000,
    this.shadowBlur = 0,
    this.shadowColor = 0xB3000000,
    this.shadowOffsetX = 4,
    this.shadowOffsetY = 4,
    this.backgroundColor = 0x00000000,
    this.backgroundRadius = 14,
    this.backgroundPadding = 22,
    this.gradientColor,
  });

  final String id;
  final String name;
  final String category;
  final String fontFamily;
  final int color;
  final bool bold;
  final bool italic;
  final double letterSpacing;
  final double strokeWidth;
  final int strokeColor;
  final double shadowBlur;
  final int shadowColor;
  final double shadowOffsetX;
  final double shadowOffsetY;
  final int backgroundColor;
  final double backgroundRadius;
  final double backgroundPadding;
  final int? gradientColor;

  /// Copy the look onto [layer], leaving its text, timing and position alone.
  void applyTo(TextLayer layer) {
    layer
      ..fontFamily = fontFamily
      ..color = color
      ..bold = bold
      ..italic = italic
      ..letterSpacing = letterSpacing
      ..strokeWidth = strokeWidth
      ..strokeColor = strokeColor
      ..shadowBlur = shadowBlur
      ..shadowColor = shadowColor
      ..shadowOffsetX = shadowOffsetX
      ..shadowOffsetY = shadowOffsetY
      ..backgroundColor = backgroundColor
      ..backgroundRadius = backgroundRadius
      ..backgroundPadding = backgroundPadding
      ..gradientColor = gradientColor
      ..stylePresetId = id;
  }
}

class TextPresetLibrary {
  TextPresetLibrary._();

  static const List<String> categories = [
    'Plain', 'Title', 'Caption', 'Bold', 'Retro', 'Neon'
  ];

  static const List<TextStylePreset> all = [
    // Plain
    TextStylePreset(id: 'plain', name: 'Plain', category: 'Plain'),
    TextStylePreset(
        id: 'plainShadow', name: 'Soft', category: 'Plain', shadowBlur: 10),
    TextStylePreset(
        id: 'plainBold', name: 'Strong', category: 'Plain', bold: true,
        shadowBlur: 6),
    TextStylePreset(
        id: 'plainOutline', name: 'Outline', category: 'Plain',
        bold: true, strokeWidth: 3),
    // Title
    TextStylePreset(
        id: 'poster', name: 'Poster', category: 'Title',
        fontFamily: 'Anton', letterSpacing: 2, shadowBlur: 14),
    TextStylePreset(
        id: 'headline', name: 'Headline', category: 'Title',
        fontFamily: 'Bebas Neue', letterSpacing: 4),
    TextStylePreset(
        id: 'cinema', name: 'Cinema', category: 'Title',
        fontFamily: 'Oswald', letterSpacing: 8, color: 0xFFF2F0E6,
        shadowBlur: 18, shadowColor: 0xCC000000),
    TextStylePreset(
        id: 'goldTitle', name: 'Gold', category: 'Title',
        fontFamily: 'Anton', color: 0xFFFFD866,
        gradientColor: 0xFFB8860B, strokeWidth: 2, strokeColor: 0xFF3A2A00),
    // Caption
    TextStylePreset(
        id: 'subtitle', name: 'Subtitle', category: 'Caption',
        backgroundColor: 0xB3000000, backgroundPadding: 18,
        backgroundRadius: 8),
    TextStylePreset(
        id: 'chip', name: 'Chip', category: 'Caption',
        color: 0xFF000000, backgroundColor: 0xFFFFFFFF,
        backgroundRadius: 40, bold: true),
    TextStylePreset(
        id: 'accentChip', name: 'Accent', category: 'Caption',
        color: 0xFF06231C, backgroundColor: 0xFF31E1B4,
        backgroundRadius: 40, bold: true),
    TextStylePreset(
        id: 'lower3rd', name: 'Lower 3rd', category: 'Caption',
        color: 0xFFFFFFFF, backgroundColor: 0xCC1B1B22,
        backgroundRadius: 4, backgroundPadding: 26, letterSpacing: 1),
    // Bold
    TextStylePreset(
        id: 'impact', name: 'Impact', category: 'Bold',
        fontFamily: 'Anton', strokeWidth: 5, strokeColor: 0xFF000000),
    TextStylePreset(
        id: 'sticker', name: 'Sticker', category: 'Bold',
        fontFamily: 'Anton', color: 0xFFFFFFFF,
        strokeWidth: 7, strokeColor: 0xFF111111, shadowBlur: 0),
    TextStylePreset(
        id: 'redAlert', name: 'Alert', category: 'Bold',
        fontFamily: 'Bebas Neue', color: 0xFFFFFFFF,
        backgroundColor: 0xFFE23B3B, backgroundRadius: 6, letterSpacing: 3),
    TextStylePreset(
        id: 'blackBar', name: 'Bar', category: 'Bold',
        fontFamily: 'Oswald', color: 0xFFFFFFFF,
        backgroundColor: 0xFF000000, backgroundRadius: 0,
        backgroundPadding: 20, letterSpacing: 5),
    // Retro
    TextStylePreset(
        id: 'script', name: 'Script', category: 'Retro',
        fontFamily: 'Pacifico', color: 0xFFFFF3D6, shadowBlur: 12,
        shadowColor: 0xAA5A3A00),
    TextStylePreset(
        id: 'vhs', name: 'VHS', category: 'Retro',
        fontFamily: 'Oswald', color: 0xFFE8F5FF, letterSpacing: 2,
        shadowBlur: 0, shadowColor: 0xFFFF3B6B, shadowOffsetX: 5,
        shadowOffsetY: 0),
    TextStylePreset(
        id: 'sunsetRetro', name: 'Sunset', category: 'Retro',
        fontFamily: 'Anton', color: 0xFFFFC371,
        gradientColor: 0xFFFF5F6D, strokeWidth: 2, strokeColor: 0xFF2A0B2E,
        letterSpacing: 3),
    TextStylePreset(
        id: 'chrome', name: 'Chrome', category: 'Retro',
        fontFamily: 'Bebas Neue', color: 0xFFEFEFF4,
        gradientColor: 0xFF8A8FA8, strokeWidth: 2, strokeColor: 0xFF2B2B33,
        letterSpacing: 4),
    // Neon
    TextStylePreset(
        id: 'neonCyan', name: 'Neon', category: 'Neon',
        fontFamily: 'Oswald', color: 0xFFB9FFF6,
        shadowBlur: 26, shadowColor: 0xFF19E3C4,
        shadowOffsetX: 0, shadowOffsetY: 0, letterSpacing: 3),
    TextStylePreset(
        id: 'neonPink', name: 'Hot', category: 'Neon',
        fontFamily: 'Oswald', color: 0xFFFFD5EC,
        shadowBlur: 26, shadowColor: 0xFFFF2D95,
        shadowOffsetX: 0, shadowOffsetY: 0, letterSpacing: 3),
    TextStylePreset(
        id: 'glowWhite', name: 'Glow', category: 'Neon',
        bold: true, shadowBlur: 30, shadowColor: 0xFFFFFFFF,
        shadowOffsetX: 0, shadowOffsetY: 0),
    TextStylePreset(
        id: 'neonOutline', name: 'Tube', category: 'Neon',
        fontFamily: 'Bebas Neue', color: 0x00000000,
        strokeWidth: 3, strokeColor: 0xFF7CF6FF,
        shadowBlur: 22, shadowColor: 0xFF00B4D8,
        shadowOffsetX: 0, shadowOffsetY: 0, letterSpacing: 5),
  ];

  static List<TextStylePreset> byCategory(String c) =>
      all.where((p) => p.category == c).toList();
}
