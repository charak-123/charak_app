import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'charak_controls.dart';

enum CharakBadgeVariant { primary, success, warning, danger, muted, requested, active }

/// Small label badge: sentence case, caption/600, soft status fill. Shares
/// its colours with [CharakStatusPill] so badges and pills never drift apart.
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
    final (bg, fg) = charakToneColors(switch (variant) {
      CharakBadgeVariant.primary   => CharakStatusTone.accepted,
      CharakBadgeVariant.success   => CharakStatusTone.confirmed,
      CharakBadgeVariant.warning   => CharakStatusTone.review,
      CharakBadgeVariant.danger    => CharakStatusTone.declined,
      CharakBadgeVariant.muted     => CharakStatusTone.muted,
      CharakBadgeVariant.requested => CharakStatusTone.requested,
      CharakBadgeVariant.active    => CharakStatusTone.active,
    });
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.all(CharakRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: CharakText.caption.copyWith(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
