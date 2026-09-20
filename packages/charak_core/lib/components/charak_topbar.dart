import 'package:flutter/material.dart';
import '../design/tokens.dart';

/// Fixed screen header matching the wireframe's `.topbar`: a 44×44 circular
/// back button, a centered title (+ optional subtitle), and either a
/// trailing circular icon button or a same-width spacer to keep the title
/// centered. No elevation/shadow — flat, matching `CharakColors.bg`.
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
  Size get preferredSize => Size.fromHeight(subtitle != null ? 64 : 52);

  @override
  Widget build(BuildContext context) => Material(
    color: CharakColors.bg,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Row(
          children: [
            _CircleIconButton(
              icon: Icons.arrow_back,
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
                    style: CharakText.h2,
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
              _CircleIconButton(icon: trailingIcon!, onTap: onTrailingTap)
            else
              const SizedBox(width: 44, height: 44),
          ],
        ),
      ),
    ),
  );
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _CircleIconButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Icon(icon, size: 21, color: CharakColors.ink),
      ),
    ),
  );
}
