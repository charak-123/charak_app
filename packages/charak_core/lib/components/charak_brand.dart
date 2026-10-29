import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// The CHARAK mark (Charak with the rod and serpent, gold halo and leaves).
/// The mark sets the warm palette; see design-system/README.md § Brand.
class CharakLogoMark extends StatelessWidget {
  final double height;

  /// Include the चरक wordmark under the mark.
  final bool lockup;

  const CharakLogoMark({super.key, this.height = 96, this.lockup = false});

  @override
  Widget build(BuildContext context) => Image.asset(
    lockup ? 'assets/brand/charak_lockup.png' : 'assets/brand/charak_mark.png',
    package: 'charak_core',
    height: height,
    fit: BoxFit.contain,
    semanticLabel: 'Charak',
    filterQuality: FilterQuality.medium,
  );
}

/// "CHARAK चरक": the Latin name at width 125 / weight 800 next to the
/// Devanagari name in Chandan. The wordmark is a Chandan moment.
class CharakWordmark extends StatelessWidget {
  final double size;

  /// Muted suffix, e.g. "Partner" in the doctor app.
  final String? suffix;

  const CharakWordmark({super.key, this.size = 28, this.suffix});

  @override
  Widget build(BuildContext context) {
    final latin = CharakText.display.copyWith(
      fontSize: size,
      height: 1,
      letterSpacing: size * 0.04,
      color: CharakColors.ink,
    ).weight(800);
    // Scales down rather than overflowing on a 360dp phone at a large
    // system font size (the "Partner" lockup is ~350dp wide there).
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
      mainAxisSize: MainAxisSize.min,
      // Baseline, not centre: Anek Devanagari has taller line metrics than
      // Anek Latin, so centring the two boxes floated चरक above CHARAK. On a
      // shared baseline the letters sit on one line and the shirorekha meets
      // the cap height, as the two Anek scripts are designed to pair.
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('CHARAK', style: latin),
        SizedBox(width: size * 0.35),
        Text(
          'चरक',
          style: latin.copyWith(
            fontFamily: CharakType.familyDevanagari,
            letterSpacing: 0,
            color: CharakColors.isInk ? CharakPalette.chandan300 : CharakColors.chandan,
          ),
        ),
        if (suffix != null) ...[
          SizedBox(width: size * 0.4),
          Text(suffix!, style: CharakText.label.copyWith(fontSize: size * 0.55, color: CharakColors.inkMuted)),
        ],
      ],
      ),
    );
  }
}
