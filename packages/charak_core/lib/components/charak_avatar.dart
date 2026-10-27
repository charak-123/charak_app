import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../format/charak_format.dart';

// Six tone pairs from the V2 ramps (bg, initials). Avatars keep these light
// tones on both schemes, as in the doctor app's ink mockup.
const _toneBg = [
  CharakPalette.chandan100, CharakPalette.blue100, CharakPalette.sage100,
  Color(0xFFECE7FA), CharakPalette.chandan50, CharakPalette.ink100,
];
const _toneFg = [
  CharakPalette.chandan700, CharakPalette.blue700, CharakPalette.sage700,
  Color(0xFF4A3499), CharakPalette.chandan600, CharakPalette.ink700,
];

/// Rounded-square avatar (One UI): shows the image when there is one,
/// otherwise toned initials in wide Anek.
///
/// [tone] is 1–6 (deterministic from the name if omitted). [radius] is half
/// the side length (default 24 → 48px), kept for V1 call sites.
class CharakAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double radius;
  final int? tone;

  /// Draw a circle instead of the rounded square (the account button).
  final bool circle;

  const CharakAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 24,
    this.tone,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = ((tone ?? _toneFromName(name)) - 1).clamp(0, 5);
    final side = radius * 2;
    final shape = circle
        ? const StadiumBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(side / 3));
    final initials = _Initials(initials: _initials(name), fg: _toneFg[t], fontSize: radius * 0.72);

    return Container(
      width: side,
      height: side,
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(color: _toneBg[t], shape: shape),
      alignment: Alignment.center,
      child: (imageUrl != null && imageUrl!.isNotEmpty)
          ? Image(
              image: CharakCoverResizeImage(
                NetworkImage(imageUrl!),
                (side * (MediaQuery.maybeDevicePixelRatioOf(context) ?? View.of(context).devicePixelRatio)).ceil(),
              ),
              width: side,
              height: side,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => initials,
              loadingBuilder: (_, child, progress) => progress == null ? child : initials,
            )
          : initials,
    );
  }

  static String _initials(String name) => CharakFormat.initials(name);

  static int _toneFromName(String name) => name.isEmpty ? 1 : (name.codeUnitAt(0) % 6) + 1;

  // Expose for callers that want the tone colours for overlaid content.
  static Color fgForTone(int tone) => _toneFg[(tone - 1).clamp(0, 5)];
  static Color bgForTone(int tone) => _toneBg[(tone - 1).clamp(0, 5)];
}

/// Decodes a photo at the size the avatar shows it, not the size it was
/// uploaded: the shorter side comes out at [side] device pixels (never larger
/// than the original), which is all `BoxFit.cover` in a square needs. An
/// 800px doctor photo in a 52px avatar otherwise sits in memory as ~2.5MB of
/// pixels instead of ~50KB, once per row of the directory.
///
/// [ResizeImage] can't do this: its policies size to a fixed box or fit
/// inside one, and either would soften a landscape photo once cover crops it.
@immutable
@visibleForTesting
class CharakCoverResizeImage extends ImageProvider<CharakCoverResizeKey> {
  final ImageProvider<Object> image;
  final int side;

  const CharakCoverResizeImage(this.image, this.side);

  @override
  Future<CharakCoverResizeKey> obtainKey(ImageConfiguration configuration) =>
      // NetworkImage answers synchronously; `then` on a SynchronousFuture stays
      // synchronous, so a cached photo still paints on the first frame.
      image.obtainKey(configuration).then((key) => CharakCoverResizeKey(key, side));

  @override
  ImageStreamCompleter loadImage(CharakCoverResizeKey key, ImageDecoderCallback decode) =>
      image.loadImage(
        key.inner,
        (buffer, {getTargetSize}) => decode(buffer, getTargetSize: (w, h) {
          final shorter = math.min(w, h);
          if (shorter <= side) return ui.TargetImageSize(width: w, height: h);
          final scale = side / shorter;
          return ui.TargetImageSize(width: (w * scale).round(), height: (h * scale).round());
        }),
      );

  @override
  bool operator ==(Object other) =>
      other is CharakCoverResizeImage && other.image == image && other.side == side;

  @override
  int get hashCode => Object.hash(image, side);
}

@immutable
@visibleForTesting
class CharakCoverResizeKey {
  final Object inner;
  final int side;

  const CharakCoverResizeKey(this.inner, this.side);

  @override
  bool operator ==(Object other) =>
      other is CharakCoverResizeKey && other.inner == inner && other.side == side;

  @override
  int get hashCode => Object.hash(inner, side);
}

class _Initials extends StatelessWidget {
  final String initials;
  final Color fg;
  final double fontSize;
  const _Initials({required this.initials, required this.fg, required this.fontSize});

  @override
  Widget build(BuildContext context) => Text(
    initials,
    style: CharakText.titleSmall.copyWith(color: fg, fontSize: fontSize, height: 1),
  );
}
