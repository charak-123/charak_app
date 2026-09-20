import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../design/tokens.dart';

/// Standard content card with optional title and padding.
class CharakCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final String? title;
  final String? description;
  final Widget? trailing;

  const CharakCard({
    super.key,
    required this.child,
    this.padding,
    this.title,
    this.description,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => ShadCard(
    padding: padding ?? const EdgeInsets.all(16),
    title: title != null ? Text(title!, style: CharakText.h2) : null,
    description: description != null
        ? Text(description!, style: CharakText.caption.copyWith(color: CharakColors.inkMuted))
        : null,
    trailing: trailing,
    child: child,
  );
}

/// Clickable list-tile card — used for menu rows, booking cards, etc.
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
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: ShadCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: CharakText.bodyMed.copyWith(color: titleColor)),
            if (subtitle != null)
              Text(subtitle!,
                  style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    ),
  );
}
