import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';

/// Button variants (design-system/README.md § Buttons). Every button is a
/// pill, at least 52px tall, and presses to scale 0.96.
enum CharakButtonVariant {
  /// Solid blue: the one main action on a screen (Send request, Pay, Book).
  primary,
  /// Blue-tinted: a supporting action (Add family member).
  tonal,
  /// Outlined: a neutral alternative (Reschedule).
  outline,
  /// Solid ink: a decisive confirm next to a soft decline (doctor Accept).
  ink,
  /// Soft red: a decline or cancel that shouldn't shout.
  danger,
  /// White on a blue or ink card (Pay ₹800 on the booking hero).
  inverse,
}

/// Pill button. Full width by default; pass [expand] false to hug content.
class CharakButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final IconData? trailingIcon;
  final CharakButtonVariant variant;
  final bool expand;
  final bool compact;

  /// V1 flag: `outlined: true` is the same as `variant: outline`.
  final bool outlined;

  const CharakButton({
    super.key,
    required this.label,
    this.onPressed,
    this.outlined = false,
    this.isLoading = false,
    this.icon,
    this.trailingIcon,
    this.variant = CharakButtonVariant.primary,
    this.expand = true,
    this.compact = false,
  });

  CharakButtonVariant get _variant => outlined ? CharakButtonVariant.outline : variant;

  @override
  Widget build(BuildContext context) {
    final available = onPressed != null;
    final (bg, fg, edge) = charakButtonColors(_variant);
    // "Busy" is not "disabled": while loading the button keeps its colour but
    // swallows taps. Unavailable buttons turn quiet grey ("Button wakes up"
    // fades them to blue once they become available).
    final fill = available || isLoading ? bg : CharakColors.bgSubtle;
    final ink = available || isLoading ? fg : CharakColors.inkFaint;
    final height = compact ? CharakSizes.buttonCompact : CharakSizes.buttonMinHeight;

    final content = isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: ink),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20, color: ink), const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CharakText.label.copyWith(fontSize: compact ? 15 : 16, color: ink),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 8),
                Icon(trailingIcon, size: 20, color: ink),
              ],
            ],
          );

    final button = CharakPressable(
      onTap: isLoading ? null : onPressed,
      child: AnimatedContainer(
        duration: CharakMotion.standard,
        curve: CharakCurves.standard,
        height: height,
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: const BorderRadius.all(CharakRadius.button),
          border: edge != null && (available || isLoading)
              ? Border.all(color: edge, width: 1.5)
              : null,
        ),
        child: content,
      ),
    );

    return Semantics(button: true, enabled: available, label: label, excludeSemantics: true, child: button);
  }
}

/// (fill, label, outline) for a button variant on the active scheme.
(Color, Color, Color?) charakButtonColors(CharakButtonVariant v) => switch (v) {
  CharakButtonVariant.primary => (CharakColors.primary, CharakColors.onPrimary, null),
  CharakButtonVariant.tonal => (CharakColors.primarySoft, CharakColors.primaryDeep, null),
  CharakButtonVariant.outline => (CharakColors.card, CharakColors.ink, CharakColors.borderStrong),
  CharakButtonVariant.ink => CharakColors.isInk
      ? (CharakColors.primary, CharakColors.onPrimary, null)
      : (CharakColors.chrome, CharakColors.onChrome, null),
  CharakButtonVariant.danger => (CharakColors.dangerSoft, CharakColors.onDangerSoft, null),
  CharakButtonVariant.inverse => (Colors.white, CharakPalette.blue700, null),
};

/// Text button: blue label, no fill ("View all", "See all").
class CharakGhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const CharakGhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = onPressed != null ? CharakColors.primary : CharakColors.inkFaint;
    return CharakPressable(
      onTap: onPressed,
      child: Container(
        height: CharakSizes.touchMin,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 18, color: color), const SizedBox(width: 6)],
            Text(label, style: CharakText.label.copyWith(fontSize: 16, color: color)),
          ],
        ),
      ),
    );
  }
}

/// Soft-red pill for cancel / decline / delete.
class CharakDestructiveButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const CharakDestructiveButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) => CharakButton(
    label: label,
    onPressed: onPressed,
    isLoading: isLoading,
    variant: CharakButtonVariant.danger,
  );
}

/// Round icon button (video, call, mic): 52px tinted circle, blue glyph.
class CharakIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final double size;
  final bool solid;

  const CharakIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.size = CharakSizes.buttonMinHeight,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: CharakPressable(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: solid ? CharakColors.primary : CharakColors.primarySoft,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: size * 0.42, color: solid ? CharakColors.onPrimary : CharakColors.primaryDeep),
      ),
    ),
  );
}
