import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'tokens.dart';

/// Material ThemeData used inside ShadApp's materialThemeBuilder.
ThemeData charakMaterialTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: CharakColors.primary,
    surface: CharakColors.bg,
  ),
  fontFamily: CharakText.fontFamily,
  scaffoldBackgroundColor: CharakColors.bg,
  appBarTheme: const AppBarTheme(
    backgroundColor: CharakColors.bg,
    foregroundColor: CharakColors.ink,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleTextStyle: CharakText.h1,
  ),
  dividerTheme: const DividerThemeData(color: CharakColors.border, thickness: 1, space: 0),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: CharakColors.bg,
    selectedItemColor: CharakColors.primary,
    unselectedItemColor: CharakColors.inkMuted,
    type: BottomNavigationBarType.fixed,
    elevation: 0,
  ),
);

/// shadcn_ui theme tuned to Charak brand colors.
ShadThemeData charakShadTheme() => ShadThemeData(
  colorScheme: const ShadZincColorScheme.light(
    background: CharakColors.bg,
    foreground: CharakColors.ink,
    card: CharakColors.bg,
    cardForeground: CharakColors.ink,
    primary: CharakColors.primary,
    primaryForeground: Colors.white,
    secondary: CharakColors.bgSubtle,
    secondaryForeground: CharakColors.ink,
    muted: CharakColors.bgSubtle,
    mutedForeground: CharakColors.inkMuted,
    border: CharakColors.border,
    input: CharakColors.border,
    ring: CharakColors.primary,
    destructive: CharakColors.danger,
    destructiveForeground: Colors.white,
  ),
  brightness: Brightness.light,
  radius: BorderRadius.all(CharakRadius.card),
);

// Keep the old name as a convenience getter for non-ShadApp contexts.
ThemeData charakTheme() => charakMaterialTheme();
