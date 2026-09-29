import 'package:flutter/material.dart';

import 'tokens.g.dart';

export 'tokens.g.dart';

/// CHARAK Design System V2. See `design-system/README.md`.
///
/// Raw values live in `tokens.g.dart`, which is generated from
/// `design-system/tokens.json`. This file maps them onto the names screens use.
///
/// Each app picks its surface once, before `runApp`:
///
/// ```dart
/// CharakColors.useScheme(CharakScheme.doctor); // ink surfaces
/// ```
///
/// The patient app keeps the default, [CharakScheme.patient] (cream ground,
/// white cards). Every colour below is a *role*, so the same screen code
/// reads correctly on either surface.
abstract final class CharakColors {
  static CharakScheme _scheme = CharakScheme.patient;

  /// The scheme the running app uses.
  static CharakScheme get scheme => _scheme;

  /// Call once in `main()` before `runApp`.
  static void useScheme(CharakScheme scheme) => _scheme = scheme;

  static bool get isInk => _scheme.brightness == Brightness.dark;

  // ── Surfaces ──
  /// Screen background: cream (patient) / ink-900 (doctor).
  static Color get ground => _scheme.ground;
  /// Card, sheet and bar surface: white (patient) / ink-800 (doctor).
  static Color get bg => _scheme.card;
  static Color get card => _scheme.card;
  /// Quiet fill inside a card: segment tracks, disabled slots, inputs.
  static Color get bgSubtle => _scheme.fill;
  /// Blue-tinted surface (surface.tint).
  static Color get tint => _scheme.tint;
  /// Chandan-tinted surface (surface.warm).
  static Color get warm => _scheme.warm;

  // ── Text ──
  static Color get ink => _scheme.text;
  static Color get inkMuted => _scheme.textMuted;
  static Color get inkFaint => _scheme.textFaint;

  // ── Lines ──
  static Color get border => _scheme.line;
  static Color get borderStrong => _scheme.lineStrong;

  // ── Blue acts ──
  static Color get primary => _scheme.primary;
  static Color get onPrimary => _scheme.onPrimary;
  static Color get primaryPressed => _scheme.primaryPressed;
  static Color get primarySoft => _scheme.primarySoft;
  static Color get primaryMid => _scheme.primaryMid;
  /// Blue text/icons on [primarySoft].
  static Color get primaryDeep => _scheme.onPrimarySoft;

  // ── Chandan welcomes (never a button) ──
  static Color get chandan => _scheme.accentWarm;
  static Color get chandanSoft => _scheme.accentWarmSoft;
  static Color get onChandanSoft => _scheme.onAccentWarmSoft;
  /// Date line above the greeting, "N waiting" line on doctor screens.
  static Color get greeting => _scheme.greeting;

  // ── Feedback ──
  static Color get success => _scheme.success;
  static Color get warning => _scheme.warning;
  static Color get danger => _scheme.danger;
  static Color get dangerSoft => _scheme.dangerSoft;
  static Color get onDangerSoft => _scheme.onDangerSoft;

  // ── Chrome (Now Bar, dark pills) ──
  static Color get chrome => _scheme.chrome;
  static Color get onChrome => _scheme.onChrome;
  static Color get scrim => _scheme.scrim;
}

/// Text styles. The V2 names ([display], [titleLarge] …) are the spec; the V1
/// names ([h1], [h2], [bodyMed], [micro]) are kept as aliases so older
/// screens pick up Anek without edits. Prefer the V2 names in new code.
///
/// Styles carry no colour: they inherit the theme's text colour, so they
/// work on both schemes.
abstract final class CharakText {
  static const fontFamily = CharakType.family;
  static const fontFamilyFallback = CharakType.fallback;

  // V2 scale
  static const display = CharakType.display;
  static const titleLarge = CharakType.titleLarge;
  static const titleMedium = CharakType.titleMedium;
  static const titleSmall = CharakType.titleSmall;
  static const bodyLarge = CharakType.bodyLarge;
  static const body = CharakType.body;
  static const label = CharakType.label;
  static const caption = CharakType.caption;
  static const overline = CharakType.overline;
  static const numeric = CharakType.numeric;

  // V1 aliases
  static const h1 = CharakType.titleMedium;
  static const h2 = CharakType.titleSmall;
  static const bodyMed = TextStyle(
    fontFamily: CharakType.family,
    fontFamilyFallback: CharakType.fallback,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w500,
  );
  static const micro = CharakType.overline;
}

/// Helpers for the variable font.
extension CharakTextStyleX on TextStyle {
  /// Exact weight on the wght axis (e.g. 650). Use this rather than
  /// `copyWith(fontWeight:)` on title styles, whose weight rides on the axis.
  TextStyle weight(double wght) => copyWith(
    fontWeight: FontWeight.values[((wght ~/ 100) - 1).clamp(0, 8)],
    fontVariations: [
      for (final v in fontVariations ?? const <FontVariation>[])
        if (v.axis != 'wght') v,
      FontVariation('wght', wght),
    ],
  );

  /// Width on the wdth axis: 125 wide header, 100 reading, 75 narrow data.
  TextStyle width(double wdth) => copyWith(
    fontVariations: [
      for (final v in fontVariations ?? const <FontVariation>[])
        if (v.axis != 'wdth') v,
      FontVariation('wdth', wdth),
    ],
  );

  /// Tabular, narrow figures for fees, times, ratings and countdowns.
  TextStyle get tabular => width(80).copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

abstract final class CharakRadius {
  /// 26 — cards and grouped-list blocks.
  static const card = Radius.circular(CharakRadii.card);
  /// Pill — every button.
  static const button = Radius.circular(CharakRadii.pill);
  /// 20 — text fields.
  static const input = Radius.circular(CharakRadii.field);
  /// Pill — chips, badges, segments, search.
  static const pill = Radius.circular(CharakRadii.pill);
  /// 20 — specialty tiles and inner blocks.
  static const tile = Radius.circular(CharakRadii.tile);
  /// 32 — top corners of bottom sheets.
  static const sheet = Radius.circular(CharakRadii.sheet);
  /// 16 — rounded-square avatars.
  static const avatar = Radius.circular(CharakRadii.avatar);
}

abstract final class CharakSpacing {
  static const double xs = CharakSpace.xs;
  static const double sm = CharakSpace.sm;
  static const double md = CharakSpace.md;
  static const double base = CharakSpace.base;
  /// 20 — horizontal screen gutter.
  static const double gutter = CharakSpace.gutter;
  static const double lg = CharakSpace.lg;
  static const double xl = CharakSpace.xl;
  static const double xxl = CharakSpace.xxl;
}

/// Legacy motion names, mapped onto the V2 motion tokens.
abstract final class CharakDurations {
  static const screenPush = CharakMotion.emphasized;
  static const sheetOpen = CharakMotion.emphasized;
  static const sheetClose = CharakMotion.exit;
  static const buttonPress = CharakMotion.press;
  static const statusChange = CharakMotion.standard;
  static const successAnim = CharakMotion.standard;
  static const newRequest = CharakMotion.emphasized;
}
