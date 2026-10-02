import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'design/tokens.dart';
import 'network/api_client.dart';

/// Legal document URLs, versions, and consent recording.
///
/// URLs are compile-time overridable so release builds point at the hosted
/// documents. Versions mirror the backend `LEGAL_*_VERSION` config; bump both
/// together when a document changes materially.
class CharakLegal {
  static const privacyUrl = String.fromEnvironment(
      'PRIVACY_URL', defaultValue: 'https://charak.app/privacy');
  static const termsUrl = String.fromEnvironment(
      'TERMS_URL', defaultValue: 'https://charak.app/terms');
  static const telemedicineUrl = String.fromEnvironment(
      'TELEMEDICINE_URL', defaultValue: 'https://charak.app/telemedicine');

  static const termsVersion = '2026-10-01';
  static const privacyVersion = '2026-10-01';
  static const telemedicineVersion = '2026-10-01';

  static Future<void> open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Record the user's acceptance of the current document versions, server-side
  /// and append-only (DPDP accountability). Best-effort: a failure here must not
  /// block sign-in.
  static Future<void> recordConsents({bool telemedicine = true}) async {
    final api = ApiClient.instance;
    final toRecord = <List<String>>[
      ['tos', termsVersion],
      ['privacy', privacyVersion],
      if (telemedicine) ['telemedicine', telemedicineVersion],
    ];
    for (final c in toRecord) {
      try {
        await api.post('/consents', {'type': c[0], 'version': c[1]});
      } catch (_) {/* best-effort */}
    }
  }
}

/// "By continuing you agree to our Terms and Privacy Policy." with tappable links.
class CharakLegalFooter extends StatelessWidget {
  final String verb; // e.g. "continuing", "creating an account"
  const CharakLegalFooter({super.key, this.verb = 'continuing'});

  @override
  Widget build(BuildContext context) {
    final base = CharakText.caption.copyWith(color: CharakColors.inkMuted);
    final link = base.copyWith(color: CharakColors.primary);
    TapGestureRecognizer tap(String url) =>
        TapGestureRecognizer()..onTap = () => CharakLegal.open(url);
    return Text.rich(
      TextSpan(style: base, children: [
        TextSpan(text: 'By $verb you agree to our '),
        TextSpan(text: 'Terms', style: link, recognizer: tap(CharakLegal.termsUrl)),
        const TextSpan(text: ' and '),
        TextSpan(text: 'Privacy Policy',
            style: link, recognizer: tap(CharakLegal.privacyUrl)),
        const TextSpan(text: '.'),
      ]),
      textAlign: TextAlign.center,
    );
  }
}
