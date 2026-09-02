import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../design/tokens.dart';

/// Circular avatar — shows image if available, falls back to initials.
class CharakAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double radius;

  const CharakAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    return ShadAvatar(
      imageUrl,
      size: Size(radius * 2, radius * 2),
      placeholder: Text(
        initials,
        style: CharakText.bodyMed.copyWith(
          color: CharakColors.primary,
          fontSize: radius * 0.7,
        ),
      ),
      backgroundColor: CharakColors.primarySoft,
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
