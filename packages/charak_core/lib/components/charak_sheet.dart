import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';
import 'charak_button.dart';

/// Bottom sheet (V2): 32px top corners, a 40×5 grab handle, flat (no
/// shadow), rising on motion.emphasized (450ms) and leaving on motion.exit
/// (200ms) over the scheme's scrim. "Sheets rise": enter from where it lives.
///
/// Returns the value passed to `Navigator.pop`, like [showModalBottomSheet].
Future<T?> showCharakSheet<T>(
  BuildContext context, {
  required Widget child,
  String? title,
  bool isScrollControlled = true,
  bool isDismissible = true,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: isDismissible,
      backgroundColor: Colors.transparent,
      barrierColor: CharakColors.scrim,
      elevation: 0,
      sheetAnimationStyle: const AnimationStyle(
        duration: CharakMotion.emphasized,
        reverseDuration: CharakMotion.exit,
        curve: CharakCurves.emphasized,
        reverseCurve: CharakCurves.exit,
      ),
      builder: (_) => CharakSheet(title: title, child: child),
    );

/// The sheet surface itself. Use [showCharakSheet] rather than building this
/// directly unless you need a custom host.
class CharakSheet extends StatelessWidget {
  final Widget child;
  final String? title;

  const CharakSheet({super.key, required this.child, this.title});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: CharakColors.card,
      borderRadius: const BorderRadius.vertical(top: CharakRadius.sheet),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(top: 6, bottom: 16),
                decoration: BoxDecoration(
                  color: CharakColors.borderStrong,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            if (title != null) ...[
              Text(title!, style: CharakText.titleMedium.copyWith(color: CharakColors.ink)),
              const SizedBox(height: 8),
            ],
            Flexible(child: child),
          ],
        ),
      ),
    ),
  );
}

/// Confirmation as a bottom sheet, not a centred dialog: the question sits
/// up top and both answers sit in the thumb zone. Returns true on confirm.
Future<bool> showCharakConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showCharakSheet<bool>(
    context,
    title: title,
    child: Builder(
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message != null)
            Text(message, style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: CharakButton(
                label: cancelLabel,
                variant: CharakButtonVariant.outline,
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CharakButton(
                label: confirmLabel,
                variant: destructive ? CharakButtonVariant.danger : CharakButtonVariant.primary,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ),
          ]),
        ],
      ),
    ),
  );
  return result ?? false;
}
