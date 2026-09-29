import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';

/// Card tones. Depth comes from tone, never from shadows.
enum CharakCardTone {
  /// White (patient) / ink-800 (doctor) on the ground. The default.
  plain,
  /// surface.tint — blue-tinted.
  tint,
  /// surface.warm — chandan-tinted, for welcomes and "Requested".
  warm,
  /// Solid blue hero (the upcoming booking on Home). White text on top.
  hero,
}

/// Standard content card: flat, 26px radius, no border, no shadow.
class CharakCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final String? title;
  final String? description;
  final Widget? trailing;
  final CharakCardTone tone;
  final VoidCallback? onTap;

  const CharakCard({
    super.key,
    required this.child,
    this.padding,
    this.title,
    this.description,
    this.trailing,
    this.tone = CharakCardTone.plain,
    this.onTap,
  });

  static Color colorFor(CharakCardTone tone) => switch (tone) {
    CharakCardTone.plain => CharakColors.card,
    CharakCardTone.tint => CharakColors.tint,
    CharakCardTone.warm => CharakColors.warm,
    CharakCardTone.hero => CharakColors.primary,
  };

  @override
  Widget build(BuildContext context) {
    final onHero = tone == CharakCardTone.hero;
    Widget body = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(CharakSpacing.gutter),
      decoration: BoxDecoration(
        color: colorFor(tone),
        borderRadius: const BorderRadius.all(CharakRadius.card),
      ),
      child: title == null && description == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title != null)
                            Text(title!,
                                style: CharakText.titleSmall
                                    .copyWith(color: onHero ? Colors.white : CharakColors.ink)),
                          if (description != null) ...[
                            const SizedBox(height: 2),
                            Text(description!,
                                style: CharakText.caption.copyWith(
                                    color: onHero ? CharakPalette.blue100 : CharakColors.inkMuted)),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
    );
    if (onTap != null) body = CharakPressable(onTap: onTap, child: body);
    return body;
  }
}

/// Clickable list-tile card, used for menu rows and booking cards.
class CharakTileCard extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  const CharakTileCard({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) => CharakPressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: CharakColors.card,
        borderRadius: const BorderRadius.all(CharakRadius.card),
      ),
      child: Row(children: [
        leading,
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: CharakText.body.weight(600).copyWith(color: titleColor ?? CharakColors.ink)),
            if (subtitle != null)
              Text(subtitle!, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    ),
  );
}
