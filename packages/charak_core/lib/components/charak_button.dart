import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../design/tokens.dart';

/// Controls use `--radius-control` (pill), cards use the 20px card radius the
/// ShadApp theme applies globally.
const _controlShape = ShadDecoration(
  border: ShadBorder(radius: BorderRadius.all(CharakRadius.button)),
);

/// Primary CTA button — full-width, 52px tall, built on [ShadButton].
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
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: outlined ? CharakColors.ink : Colors.white,
            ),
          )
        : Text(
            label,
            style: CharakText.bodyMed.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
          );
    final leading = (icon != null && !isLoading) ? Icon(icon, size: 18) : null;

    // "Busy" is not "disabled": while loading the button keeps its full
    // primary fill and glow (only `.btn:disabled` drops to 0.45 opacity), but
    // taps are swallowed. Fading it would leave a white spinner on a washed
    // out field with almost no contrast.
    final available = onPressed != null;
    // `.btn` — 50px tall, pill control radius; `.btn.primary` carries a
    // coloured glow (0 2px 8px rgba(55,108,213,0.28)) that outline/ghost lack.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(CharakRadius.button),
        boxShadow: (!outlined && available)
            ? const [BoxShadow(color: Color(0x47376CD5), blurRadius: 8, offset: Offset(0, 2))]
            : null,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: outlined
            ? ShadButton.outline(
                enabled: available,
                onPressed: isLoading ? null : onPressed,
                leading: leading,
                decoration: _controlShape,
                child: child,
              )
            : ShadButton(
                enabled: available,
                onPressed: isLoading ? null : onPressed,
                leading: leading,
                decoration: _controlShape,
                child: child,
              ),
      ),
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

  // `.btn.text` — 44px tall, primary-coloured label, no fill.
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: ShadButton.ghost(
      enabled: onPressed != null,
      onPressed: onPressed,
      leading: icon != null ? Icon(icon, size: 16, color: CharakColors.primary) : null,
      decoration: _controlShape,
      child: Text(
        label,
        style: CharakText.bodyMed.copyWith(
          color: CharakColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
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
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 50,
    child: ShadButton.destructive(
      // Busy keeps full opacity; only unavailable fades. See [CharakButton].
      enabled: onPressed != null,
      onPressed: isLoading ? null : onPressed,
      decoration: _controlShape,
      child: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Text(label, style: CharakText.bodyMed.copyWith(fontWeight: FontWeight.w600)),
    ),
  );
}
