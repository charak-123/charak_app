import 'package:flutter/material.dart';
import '../design/tokens.dart';

/// Inline title block for tab-root screens (no AppBar), matching the
/// wireframe's `.screen-title` / `.screen-sub` — an H1 followed by an
/// optional muted subtitle, meant to sit at the top of a scrollable body.
class CharakScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const CharakScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: CharakText.h1),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(subtitle!, style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
            ],
          ],
        ),
      ),
      if (trailing != null) trailing!,
    ],
  );
}
