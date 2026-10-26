import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design/motion.dart';
import '../design/tokens.dart';

/// A tick-box with a label, for consent and acknowledgements.
///
/// Never pre-ticked by a screen that records consent: the person has to tick
/// it themselves (DPDP, and docs/legal). The label can carry links
/// ([CharakCheckRow.links]); tapping a link opens it without toggling the box.
/// The whole row is one target, at least [CharakSizes.touchMin] tall, and reads
/// as a checkbox to screen readers.
class CharakCheckRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Plain label, or use [spans] for text with links.
  final String? label;
  final List<InlineSpan>? spans;

  const CharakCheckRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.spans,
  }) : assert(label != null || spans != null);

  /// A link for [spans]: primary colour, opens [onTap] without toggling the row.
  static TextSpan link(String text, VoidCallback onTap) => TextSpan(
        text: text,
        style: CharakText.body.copyWith(
          color: CharakColors.primary,
          fontWeight: FontWeight.w600,
        ),
        recognizer: TapGestureRecognizer()..onTap = onTap,
      );

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final reduce = charakReduceMotion(context);
    final box = AnimatedContainer(
      duration: reduce ? Duration.zero : CharakMotion.press,
      curve: CharakCurves.press,
      width: CharakSizes.checkBox,
      height: CharakSizes.checkBox,
      decoration: BoxDecoration(
        color: value ? CharakColors.primary : CharakColors.card,
        borderRadius: const BorderRadius.all(CharakRadius.check),
        border: Border.all(
          color: value ? CharakColors.primary : CharakColors.borderStrong,
          width: 1.5,
        ),
      ),
      child: value
          ? Icon(LucideIcons.check, size: 16, color: CharakColors.onPrimary)
          : null,
    );

    final text = Text.rich(
      TextSpan(
        style: CharakText.body.copyWith(
          color: enabled ? CharakColors.ink : CharakColors.inkMuted,
        ),
        children: spans ?? [TextSpan(text: label)],
      ),
    );

    return Semantics(
      checked: value,
      enabled: enabled,
      child: CharakPressable(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: CharakSizes.touchMin),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 1), child: box),
                const SizedBox(width: 12),
                Expanded(child: text),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
