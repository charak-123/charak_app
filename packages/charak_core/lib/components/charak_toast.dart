import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../design/tokens.dart';

/// Show a shadcn toast notification.
void showCharakToast(
  BuildContext context, {
  required String message,
  bool isError = false,
  String? action,
  VoidCallback? onAction,
}) {
  ShadToaster.of(context).show(
    ShadToast(
      description: Text(message,
          style: CharakText.body.copyWith(color: isError ? CharakColors.onDangerSoft : CharakColors.onChrome)),
      backgroundColor: isError ? CharakColors.dangerSoft : CharakColors.chrome,
      border: const Border.fromBorderSide(BorderSide.none),
      radius: const BorderRadius.all(CharakRadius.tile),
      shadows: const [],
      action: action != null
          ? ShadButton.ghost(
              onPressed: onAction,
              child: Text(action,
                  style: CharakText.label.copyWith(
                    color: isError ? CharakColors.onDangerSoft : CharakPalette.blue300,
                  )),
            )
          : null,
    ),
  );
}
