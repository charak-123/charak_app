import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadAvatar;

// Six tone pairs from the wireframe (av-1 … av-6)
const _toneBg = [
  Color(0xFFE9EFFB), Color(0xFFE7F5EF), Color(0xFFFDF0E0),
  Color(0xFFEFEAFE), Color(0xFFFDEAF0), Color(0xFFE5F4FA),
];
const _toneFg = [
  Color(0xFF24478F), Color(0xFF177C53), Color(0xFFB26A1A),
  Color(0xFF5B3FC4), Color(0xFFB83A63), Color(0xFF0E6E9C),
];

/// Circular avatar — shows image if available, falls back to toned initials.
///
/// [tone] is 1–6 matching the wireframe palette (deterministic from name hash
/// if not supplied). [radius] is the circle radius (default 24 → 48px diameter).
class CharakAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double radius;
  final int? tone;

  const CharakAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 24,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    final t = ((tone ?? _toneFromName(name)) - 1).clamp(0, 5);
    final diameter = radius * 2;

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ShadAvatar(
        imageUrl,
        size: Size(diameter, diameter),
        placeholder: _Initials(initials: initials, fg: _toneFg[t],
            fontSize: radius * 0.67, bg: _toneBg[t], diameter: diameter),
        backgroundColor: _toneBg[t],
      );
    }

    // No image — always show toned initials circle
    return _Initials(initials: initials, fg: _toneFg[t],
        fontSize: radius * 0.67, bg: _toneBg[t], diameter: diameter);
  }

  static String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  static int _toneFromName(String name) => (name.codeUnitAt(0) % 6) + 1;

  // Expose for callers that want foreground color for overlaid text
  static Color fgForTone(int tone) => _toneFg[(tone - 1).clamp(0, 5)];
  static Color bgForTone(int tone) => _toneBg[(tone - 1).clamp(0, 5)];
}

class _Initials extends StatelessWidget {
  final String initials;
  final Color fg;
  final Color bg;
  final double fontSize;
  final double diameter;
  const _Initials({required this.initials, required this.fg, required this.bg,
      required this.fontSize, required this.diameter});
  @override
  Widget build(BuildContext context) => Container(
    width: diameter, height: diameter,
    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: Text(initials,
        style: TextStyle(
            color: fg, fontSize: fontSize,
            fontWeight: FontWeight.w600, height: 1)),
  );
}
