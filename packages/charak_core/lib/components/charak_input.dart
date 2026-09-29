import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../design/tokens.dart';

/// Labelled text input built on ShadInput, styled as the V2 text field.
/// Prefer [CharakField] for new screens (label inside the box).
class CharakInput extends StatelessWidget {
  final String? label;
  final String? placeholder;
  final String? description;
  final String? error;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final int? maxLines;
  final Widget? leading;
  final Widget? trailing;
  final bool enabled;

  const CharakInput({
    super.key,
    this.label,
    this.placeholder,
    this.description,
    this.error,
    this.controller,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.onEditingComplete,
    this.maxLines = 1,
    this.leading,
    this.trailing,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => ShadInputFormField(
    controller: controller,
    label: label != null ? Text(label!, style: CharakText.caption.weight(600).copyWith(color: CharakColors.inkMuted)) : null,
    placeholder: placeholder != null ? Text(placeholder!, style: CharakText.bodyLarge.copyWith(color: CharakColors.inkFaint)) : null,
    description: description != null ? Text(description!, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)) : null,
    obscureText: obscureText,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    onChanged: onChanged,
    onEditingComplete: onEditingComplete,
    maxLines: maxLines,
    leading: leading,
    trailing: trailing,
    enabled: enabled,
    validator: error != null ? (_) => error : null,
    // V2 text field: 20px radius, 1.5px outline that turns blue on focus.
    style: CharakText.bodyLarge.copyWith(color: CharakColors.ink),
    decoration: ShadDecoration(
      color: CharakColors.card,
      border: ShadBorder.all(
        radius: const BorderRadius.all(CharakRadius.input),
        color: CharakColors.borderStrong,
        width: 1.5,
      ),
      focusedBorder: ShadBorder.all(
        radius: const BorderRadius.all(CharakRadius.input),
        color: CharakColors.primary,
        width: 2,
      ),
    ),
  );
}
