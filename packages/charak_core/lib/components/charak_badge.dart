import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../design/tokens.dart';
import 'charak_controls.dart';

enum CharakBadgeVariant { primary, success, warning, danger, muted }

/// Status / label badge using ShadBadge.
class CharakBadge extends StatelessWidget {
  final String label;
  final CharakBadgeVariant variant;
  final IconData? icon;

  const CharakBadge({
    super.key,
    required this.label,
    this.variant = CharakBadgeVariant.primary,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors();
    // `.badge` — 3×10 padding, 11px/600, 0.04em tracking, uppercase.
    return ShadBadge(
      backgroundColor: bg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label.toUpperCase(),
            style: CharakText.micro.copyWith(color: fg, letterSpacing: 11 * 0.04),
          ),
        ],
      ),
    );
  }

  // Tone pairs are shared with CharakStatusPill so badges and pills never
  // drift apart; values come straight from `core.css`.
  (Color, Color) _colors() => charakToneColors(switch (variant) {
    CharakBadgeVariant.primary => CharakStatusTone.primary,
    CharakBadgeVariant.success => CharakStatusTone.success,
    CharakBadgeVariant.warning => CharakStatusTone.warning,
    CharakBadgeVariant.danger  => CharakStatusTone.danger,
    CharakBadgeVariant.muted   => CharakStatusTone.muted,
  });
}
