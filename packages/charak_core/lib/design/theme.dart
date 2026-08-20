import 'package:flutter/material.dart';
import 'tokens.dart';

ThemeData charakTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: CharakColors.primary,
    surface: CharakColors.bg,
  ),
  fontFamily: CharakText.fontFamily,
  scaffoldBackgroundColor: CharakColors.bg,
  cardTheme: CardThemeData(
    elevation: 0,
    color: CharakColors.bg,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(CharakRadius.card),
      side: const BorderSide(color: CharakColors.border),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: CharakColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(CharakRadius.button),
      ),
      minimumSize: const Size(double.infinity, 52),
      textStyle: CharakText.bodyMed,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: CharakColors.primary,
      side: const BorderSide(color: CharakColors.primary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(CharakRadius.button),
      ),
      minimumSize: const Size(double.infinity, 52),
      textStyle: CharakText.bodyMed,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: CharakColors.bgSubtle,
    hintStyle: CharakText.body.copyWith(color: CharakColors.inkMuted),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(CharakRadius.button),
      borderSide: const BorderSide(color: CharakColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(CharakRadius.button),
      borderSide: const BorderSide(color: CharakColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(CharakRadius.button),
      borderSide: const BorderSide(color: CharakColors.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(CharakRadius.button),
      borderSide: const BorderSide(color: CharakColors.danger),
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: CharakColors.bg,
    foregroundColor: CharakColors.ink,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleTextStyle: CharakText.h1,
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: CharakColors.bg,
    selectedItemColor: CharakColors.primary,
    unselectedItemColor: CharakColors.inkMuted,
    type: BottomNavigationBarType.fixed,
    elevation: 0,
  ),
  dividerTheme: const DividerThemeData(color: CharakColors.border, thickness: 1, space: 0),
);
