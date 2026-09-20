import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'charak_avatar.dart';

/// The in-call surface, shared by the patient's video consult and the
/// doctor's clarification call. Colours come from the `.call-*` rules in
/// `charak-shared/core.css` — a near-black field with a radial lift behind
/// the peer, translucent white controls, and a red end-call button.
class CharakCallColors {
  CharakCallColors._();

  /// `.call-grid` background.
  static const field = Color(0xFF0B1220);

  /// Top stop of `.call-peer`'s radial gradient.
  static const fieldLift = Color(0xFF16233D);

  /// `.call-self` picture-in-picture tile.
  static const selfTile = Color(0xFF1C2A45);

  /// `.call-top .rec` recording indicator.
  static const recording = Color(0xFFFF5D5D);

  static const controlBg = Color(0x24FFFFFF); // rgba(255,255,255,0.14)
  static const controlBgActive = Color(0x47FFFFFF); // rgba(255,255,255,0.28)
  static const hairline = Color(0x24FFFFFF);
  static const notesBg = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
  static const notesBorder = Color(0x29FFFFFF); // rgba(255,255,255,0.16)
  static const peerSub = Color(0x99FFFFFF); // rgba(255,255,255,0.6)
  static const selfIcon = Color(0x8CFFFFFF); // rgba(255,255,255,0.55)
}

/// Full-bleed call screen: peer identity centred on the tinted field, an
/// optional self-view tile, a status strip, a notes field and a control row.
class CharakCallScaffold extends StatelessWidget {
  final String peerName;
  final String? peerSubtitle;
  final String? peerImageUrl;

  /// Status line shown at the top (e.g. "12:04" or "Connecting…").
  final String statusText;

  /// Shows the red dot next to [statusText] while the call is recorded.
  final bool recording;

  /// Renders the self-view tile. Set false before the local stream is ready.
  final bool showSelfView;

  /// Optional single-line notes field pinned above the controls.
  final Widget? notes;

  final List<Widget> controls;

  const CharakCallScaffold({
    super.key,
    required this.peerName,
    this.peerSubtitle,
    this.peerImageUrl,
    required this.statusText,
    this.recording = false,
    this.showSelfView = true,
    this.notes,
    required this.controls,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CharakCallColors.field,
    body: Stack(
      children: [
        // `.call-peer` — radial-gradient(120% 90% at 50% 0%, …)
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -1),
                radius: 1.2,
                colors: [CharakCallColors.fieldLift, CharakCallColors.field],
                stops: [0.0, 0.65],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x33FFFFFF), width: 3),
                ),
                child: CharakAvatar(name: peerName, imageUrl: peerImageUrl, radius: 42),
              ),
              const SizedBox(height: 12),
              Text(peerName,
                  style: CharakText.h1.copyWith(fontSize: 19, color: Colors.white)),
              if (peerSubtitle != null) ...[
                const SizedBox(height: 4),
                Text(peerSubtitle!,
                    style: CharakText.caption.copyWith(color: CharakCallColors.peerSub)),
              ],
            ],
          ),
        ),
        // `.call-top`
        Positioned(
          left: 0,
          right: 0,
          top: 10,
          child: SafeArea(
            bottom: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (recording) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: CharakCallColors.recording, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  statusText,
                  style: CharakText.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        // `.call-self`
        if (showSelfView)
          Positioned(
            right: 14,
            top: 46,
            child: SafeArea(
              bottom: false,
              child: Container(
                width: 96,
                height: 130,
                decoration: BoxDecoration(
                  color: CharakCallColors.selfTile,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: CharakCallColors.hairline),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.videocam_outlined,
                    size: 22, color: CharakCallColors.selfIcon),
              ),
            ),
          ),
        // `.call-notes`
        if (notes != null)
          Positioned(
            left: 14,
            right: 14,
            bottom: 96,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CharakCallColors.notesBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: CharakCallColors.notesBorder),
                  ),
                  child: notes,
                ),
              ),
            ),
          ),
        // `.call-controls`
        Positioned(
          left: 0,
          right: 0,
          bottom: 26,
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < controls.length; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  controls[i],
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// A 54px round call control. [active] uses the brighter translucent fill
/// (`.call-btn.muted`); [end] uses the danger red.
class CharakCallButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;
  final bool end;
  final String? semanticLabel;

  const CharakCallButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.active = false,
    this.end = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final bg = end
        ? CharakColors.danger
        : (active ? CharakCallColors.controlBgActive : CharakCallColors.controlBg);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: 54,
        height: 54,
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Icon(icon, size: 22, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
