import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../design/tokens.dart';

/// Primary CTA button — full-width, 52px tall.
/// Uses ShadButton under the hood for consistent shadcn styling.
class CharakButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool outlined;
  final bool isLoading;
  final IconData? icon;

  const CharakButton({
    super.key,
    required this.label,
    this.onPressed,
    this.outlined = false,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          );

    if (outlined) {
      return ShadButton.outline(
        onPressed: isLoading ? null : onPressed,
        width: double.infinity,
        height: 52,
        child: child,
      );
    }

    return ShadButton(
      onPressed: isLoading ? null : onPressed,
      width: double.infinity,
      height: 52,
      backgroundColor: onPressed == null ? CharakColors.inkMuted : CharakColors.primary,
      child: child,
    );
  }
}

/// Ghost / text-style button — used for secondary actions.
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
  Widget build(BuildContext context) => ShadButton.ghost(
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
        Text(label, style: CharakText.bodyMed.copyWith(color: CharakColors.primary)),
      ],
    ),
  );
}

/// Destructive button — for cancel / delete actions.
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
  Widget build(BuildContext context) => ShadButton.destructive(
    onPressed: isLoading ? null : onPressed,
    width: double.infinity,
    height: 52,
    child: isLoading
        ? const SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : Text(label),
  );
}
