import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';

/// Slim top bar for pushed screens: a 44px round back button on a card-
/// coloured circle, a centred title.small (+ optional caption), and an
/// optional trailing round action. Flat, on the ground colour.
///
/// Tab-root screens don't use this; they use [CharakLargeTitleScaffold],
/// whose big title folds into the same slim bar on scroll.
class CharakTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingTap;
  final VoidCallback? onBack;

  const CharakTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.trailingIcon,
    this.onTrailingTap,
    this.onBack,
  });

  @override
  Size get preferredSize => Size.fromHeight(subtitle != null ? 68 : 58);

  @override
  Widget build(BuildContext context) => Material(
    color: CharakColors.ground,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 0),
        child: Row(
          children: [
            CharakRoundIconButton(
              icon: Icons.arrow_back_rounded,
              semanticLabel: 'Back',
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CharakText.titleSmall.copyWith(fontSize: 18, color: CharakColors.ink),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                    ),
                ],
              ),
            ),
            if (trailingIcon != null)
              CharakRoundIconButton(icon: trailingIcon!, semanticLabel: title, onTap: onTrailingTap)
            else
              const SizedBox(width: 44, height: 44),
          ],
        ),
      ),
    ),
  );
}

/// 44px round icon button on a card-coloured circle (back, bell, more).
class CharakRoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String semanticLabel;
  final bool filled;

  const CharakRoundIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onTap,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: CharakPressable(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: filled ? CharakColors.card : Colors.transparent,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 22, color: CharakColors.ink),
      ),
    ),
  );
}
