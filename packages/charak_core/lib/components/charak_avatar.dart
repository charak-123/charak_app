import 'package:flutter/material.dart';

import '../design/tokens.dart';

// Six tone pairs from the V2 ramps (bg, initials). Avatars keep these light
// tones on both schemes, as in the doctor app's ink mockup.
const _toneBg = [
  CharakPalette.chandan100, CharakPalette.blue100, CharakPalette.sage100,
  Color(0xFFECE7FA), CharakPalette.chandan50, CharakPalette.ink100,
];
const _toneFg = [
  CharakPalette.chandan700, CharakPalette.blue700, CharakPalette.sage700,
  Color(0xFF4A3499), CharakPalette.chandan600, CharakPalette.ink700,
];

/// Rounded-square avatar (One UI): shows the image when there is one,
/// otherwise toned initials in wide Anek.
///
/// [tone] is 1–6 (deterministic from the name if omitted). [radius] is half
/// the side length (default 24 → 48px), kept for V1 call sites.
class CharakAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double radius;
  final int? tone;

  /// Draw a circle instead of the rounded square (the account button).
  final bool circle;

  const CharakAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 24,
    this.tone,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = ((tone ?? _toneFromName(name)) - 1).clamp(0, 5);
    final side = radius * 2;
    final shape = circle
        ? const StadiumBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(side / 3));
    final initials = _Initials(initials: _initials(name), fg: _toneFg[t], fontSize: radius * 0.72);

    return Container(
      width: side,
      height: side,
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(color: _toneBg[t], shape: shape),
      alignment: Alignment.center,
      child: (imageUrl != null && imageUrl!.isNotEmpty)
          ? Image.network(
              imageUrl!,
              width: side,
              height: side,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => initials,
              loadingBuilder: (_, child, progress) => progress == null ? child : initials,
            )
          : initials,
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
  }

  static int _toneFromName(String name) => name.isEmpty ? 1 : (name.codeUnitAt(0) % 6) + 1;

  // Expose for callers that want the tone colours for overlaid content.
  static Color fgForTone(int tone) => _toneFg[(tone - 1).clamp(0, 5)];
  static Color bgForTone(int tone) => _toneBg[(tone - 1).clamp(0, 5)];
}

class _Initials extends StatelessWidget {
  final String initials;
  final Color fg;
  final double fontSize;
  const _Initials({required this.initials, required this.fg, required this.fontSize});

  @override
  Widget build(BuildContext context) => Text(
    initials,
    style: CharakText.titleSmall.copyWith(color: fg, fontSize: fontSize, height: 1),
  );
}
