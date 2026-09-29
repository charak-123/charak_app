import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'tokens.dart';

/// Material ThemeData for ShadApp's `materialThemeBuilder`. Built from the
/// active [CharakScheme], so call [CharakColors.useScheme] before `runApp`.
ThemeData charakMaterialTheme() {
  final s = CharakColors.scheme;
  final dark = s.brightness == Brightness.dark;
  final text = const TextTheme(
    displayLarge: CharakText.display,
    headlineLarge: CharakText.titleLarge,
    headlineMedium: CharakText.titleMedium,
    titleLarge: CharakText.titleSmall,
    titleMedium: CharakText.label,
    bodyLarge: CharakText.bodyLarge,
    bodyMedium: CharakText.body,
    bodySmall: CharakText.caption,
    labelLarge: CharakText.label,
    labelSmall: CharakText.overline,
  ).apply(bodyColor: s.text, displayColor: s.text);

  return ThemeData(
    useMaterial3: true,
    brightness: s.brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: s.primary,
      brightness: s.brightness,
      primary: s.primary,
      onPrimary: s.onPrimary,
      surface: s.card,
      onSurface: s.text,
      error: s.danger,
    ),
    fontFamily: CharakText.fontFamily,
    fontFamilyFallback: CharakText.fontFamilyFallback,
    textTheme: text,
    scaffoldBackgroundColor: s.ground,
    canvasColor: s.ground,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: s.ground,
      foregroundColor: s.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: CharakText.titleSmall.copyWith(color: s.text),
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: s.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(CharakRadius.card)),
    ),
    dividerTheme: DividerThemeData(color: s.line, thickness: 1, space: 0),
    iconTheme: IconThemeData(color: s.text),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: s.primary),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected) ? s.primary : s.lineStrong,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.card,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: CharakRadius.sheet),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: s.chrome,
      contentTextStyle: CharakText.body.copyWith(color: s.onChrome),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(CharakRadius.tile)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: s.primary,
      selectionColor: s.primaryMid,
      selectionHandleColor: s.primary,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: s.card,
      selectedItemColor: s.primary,
      unselectedItemColor: s.textMuted,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
  );
}

/// shadcn_ui theme built from the active [CharakScheme]: flat (no shadows),
/// 26px cards, Anek throughout.
ShadThemeData charakShadTheme() {
  final s = CharakColors.scheme;
  final dark = s.brightness == Brightness.dark;
  final colors = dark
      ? ShadSlateColorScheme.dark(
          background: s.ground,
          foreground: s.text,
          card: s.card,
          cardForeground: s.text,
          popover: s.card,
          popoverForeground: s.text,
          primary: s.primary,
          primaryForeground: s.onPrimary,
          secondary: s.fill,
          secondaryForeground: s.text,
          muted: s.fill,
          mutedForeground: s.textMuted,
          accent: s.primarySoft,
          accentForeground: s.onPrimarySoft,
          border: s.line,
          input: s.lineStrong,
          ring: s.primary,
          destructive: s.danger,
          destructiveForeground: Colors.white,
          selection: s.primaryMid,
        )
      : ShadSlateColorScheme.light(
          background: s.ground,
          foreground: s.text,
          card: s.card,
          cardForeground: s.text,
          popover: s.card,
          popoverForeground: s.text,
          primary: s.primary,
          primaryForeground: s.onPrimary,
          secondary: s.fill,
          secondaryForeground: s.text,
          muted: s.fill,
          mutedForeground: s.textMuted,
          accent: s.primarySoft,
          accentForeground: s.onPrimarySoft,
          border: s.line,
          input: s.lineStrong,
          ring: s.primary,
          destructive: s.danger,
          destructiveForeground: Colors.white,
          selection: s.primaryMid,
        );

  return ShadThemeData(
    colorScheme: colors,
    brightness: s.brightness,
    radius: const BorderRadius.all(CharakRadius.card),
    textTheme: ShadTextTheme(family: CharakText.fontFamily),
    cardTheme: ShadCardTheme(
      backgroundColor: s.card,
      radius: const BorderRadius.all(CharakRadius.card),
      border: const Border.fromBorderSide(BorderSide.none),
      shadows: const [],
    ),
  );
}

// Keep the old name as a convenience getter for non-ShadApp contexts.
ThemeData charakTheme() => charakMaterialTheme();
