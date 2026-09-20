import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';

/// Bottom sheet matching `.sheet` in `charak-shared/core.css`: an 18px
/// top-only radius, the 40×4 `.grab` handle, 8/20/22 padding and the
/// `--shadow-sheet` lift, opened over a `rgba(16,24,40,0.45)` scrim across
/// `--dur-sheet` (240ms) on `--ease-out`.
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
      // `.sheet-backdrop`
      barrierColor: const Color(0x73101828),
      elevation: 0,
      // `--dur-sheet` / `--ease-out`
      sheetAnimationStyle: AnimationStyle(
        duration: CharakDurations.sheetOpen,
        reverseDuration: CharakDurations.sheetOpen,
        curve: CharakCurves.out,
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
    decoration: const BoxDecoration(
      color: CharakColors.bg,
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      boxShadow: [CharakShadow.sheet],
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // `.sheet .grab`
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 6, bottom: 14),
                decoration: BoxDecoration(
                  color: CharakColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (title != null) ...[
              // `.sheet-title`
              Text(title!, style: CharakText.h2),
              const SizedBox(height: 4),
            ],
            Flexible(child: child),
          ],
        ),
      ),
    ),
  );
}
