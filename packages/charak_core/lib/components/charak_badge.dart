import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../design/tokens.dart';

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
    return ShadBadge(
      backgroundColor: bg,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: CharakText.micro.copyWith(color: fg, letterSpacing: 0.02)),
        ],
      ),
    );
  }

  (Color, Color) _colors() => switch (variant) {
    CharakBadgeVariant.primary => (CharakColors.primarySoft, CharakColors.primary),
    CharakBadgeVariant.success => (const Color(0xFFEAF7F1), CharakColors.success),
    CharakBadgeVariant.warning => (const Color(0xFFFEF3C7), CharakColors.warning),
    CharakBadgeVariant.danger  => (const Color(0xFFFFEEED), CharakColors.danger),
    CharakBadgeVariant.muted   => (CharakColors.bgSubtle, CharakColors.inkMuted),
  };
}
