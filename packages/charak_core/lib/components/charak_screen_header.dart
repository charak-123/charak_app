import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Big header block for the top third of a screen ("Look up top, reach
/// down low"): an optional Chandan [eyebrow] (date, doctor name), a wide
/// title.large title, and a muted [subtitle].
///
/// Used inside [CharakLargeTitleScaffold], or on its own at the top of a
/// scrollable body.
class CharakScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? eyebrow;
  final Widget? trailing;

  /// Use the 56px display size (greetings).
  final bool display;

  /// Colour for the subtitle; defaults to muted. The doctor app passes
  /// [CharakColors.greeting] for "3 waiting for your decision".
  final Color? subtitleColor;

  const CharakScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.trailing,
    this.display = false,
    this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null) ...[
              Text(eyebrow!, style: CharakText.label.copyWith(color: CharakColors.greeting)),
              const SizedBox(height: 6),
            ],
            Text(
              title,
              style: (display ? CharakText.display.copyWith(fontSize: 44, height: 48 / 44) : CharakText.titleLarge)
                  .copyWith(color: CharakColors.ink),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: (subtitleColor != null ? CharakText.label : CharakText.body)
                    .copyWith(color: subtitleColor ?? CharakColors.inkMuted),
              ),
            ],
          ],
        ),
      ),
      if (trailing != null) trailing!,
    ],
  );
}
