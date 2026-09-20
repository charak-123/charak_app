import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../design/tokens.dart';

/// Labelled text input using ShadInput.
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
    label: label != null ? Text(label!, style: CharakText.caption.copyWith(color: CharakColors.ink)) : null,
    placeholder: placeholder != null ? Text(placeholder!, style: CharakText.body.copyWith(color: CharakColors.inkMuted)) : null,
    description: description != null ? Text(description!, style: CharakText.micro.copyWith(color: CharakColors.inkMuted)) : null,
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
    // Inputs stay at the 14px input radius even though the Shad theme
    // radius follows the 20px card radius.
    decoration: const ShadDecoration(
      border: ShadBorder(radius: BorderRadius.all(CharakRadius.input)),
    ),
  );
}
