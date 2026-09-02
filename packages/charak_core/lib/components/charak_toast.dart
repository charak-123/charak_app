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
      description: Text(message),
      backgroundColor: isError ? CharakColors.danger : null,
      foregroundColor: isError ? Colors.white : null,
      action: action != null
          ? ShadButton.ghost(
              onPressed: onAction,
              child: Text(action,
                  style: CharakText.caption.copyWith(
                    color: isError ? Colors.white : CharakColors.primary,
                    fontWeight: FontWeight.w600,
                  )),
            )
          : null,
    ),
  );
}
