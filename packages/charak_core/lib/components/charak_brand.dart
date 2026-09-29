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
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
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
    );
  }
}
