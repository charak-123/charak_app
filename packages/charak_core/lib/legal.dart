import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'design/tokens.dart';
import 'legal_screens.dart';
import 'network/api_client.dart';

/// One published legal document (backend legal_documents, migrations 0024
/// and 0030). Since 0030 a version carries its full text, which the apps show
/// in full and people sign; [sha256] fingerprints that text.
class CharakLegalDocument {
  final String type;
  final String version;
  final String title;
  final String url;
  final bool accepted;

  /// When this person signed this version (null if they haven't).
  final DateTime? acceptedAt;

  /// One line for the list of documents.
  final String? summary;

  /// The key points, shown above the full text.
  final List<String> highlights;

  final DateTime? publishedAt;
  final String? sha256;

  /// False for versions from before 0030, which live only on the website.
  final bool hasText;

  /// Whether this person must sign it (not just read it).
  final bool required;

  /// The full text, when fetched with [CharakLegal.document].
  final String? body;

  const CharakLegalDocument({
    required this.type,
    required this.version,
    required this.title,
    required this.url,
    this.accepted = false,
    this.acceptedAt,
    this.summary,
    this.highlights = const [],
    this.publishedAt,
    this.sha256,
    this.hasText = false,
    this.required = true,
    this.body,
  });

  factory CharakLegalDocument.fromJson(Map<String, dynamic> j) => CharakLegalDocument(
        type: j['type'] as String,
        version: j['version'] as String,
        title: j['title'] as String? ?? j['type'] as String,
        url: j['url'] as String? ?? CharakLegal.termsUrl,
        accepted: j['accepted'] == true,
        acceptedAt: DateTime.tryParse(j['accepted_at'] as String? ?? '')?.toLocal(),
        summary: j['summary'] as String?,
        highlights: [for (final h in (j['highlights'] as List? ?? const [])) if (h is String) h],
        publishedAt: DateTime.tryParse(j['published_at'] as String? ?? '')?.toLocal(),
        sha256: j['sha256'] as String?,
        hasText: j['has_text'] == true || (j['body'] is String),
        required: j['required'] != false,
        body: j['body'] as String?,
      );

  /// The documents listed in an error body (`consent_required` on a 428).
  static List<CharakLegalDocument> listFrom(dynamic raw) => [
        for (final d in (raw as List? ?? const []))
          if (d is Map<String, dynamic>) CharakLegalDocument.fromJson(d),
      ];
}

/// Legal documents, and signatures recorded against the published versions.
///
/// The versions and their text live on the server. A material change is
/// published there, and the apps ask again: [status] reports what is missing,
/// and [showCharakAgreements] (legal_screens.dart) collects it.
class CharakLegal {
  static const privacyUrl = String.fromEnvironment(
      'PRIVACY_URL', defaultValue: 'https://www.charak.care/privacy');
  static const termsUrl = String.fromEnvironment(
      'TERMS_URL', defaultValue: 'https://www.charak.care/terms');
  static const telemedicineUrl = String.fromEnvironment(
      'TELEMEDICINE_URL', defaultValue: 'https://www.charak.care/telemedicine');
  /// Help and grievance contact (the website's contact page).
  static const supportUrl = String.fromEnvironment(
      'SUPPORT_URL', defaultValue: 'https://www.charak.care/contact');

  static Future<void> open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Every document this user must accept, and the ones still outstanding.
  static Future<({List<CharakLegalDocument> documents, List<CharakLegalDocument> missing})>
      status() async {
    final res = await ApiClient.instance.get('/legal/current') as Map<String, dynamic>;
    return (
      documents: [
        for (final d in (res['documents'] as List? ?? const []))
          CharakLegalDocument.fromJson(d as Map<String, dynamic>),
      ],
      missing: CharakLegalDocument.listFrom(res['missing']),
    );
  }

  /// One document with its full text: the current version of [type], or
  /// [version] (the one someone signed). Public, so it works before sign-in.
  static Future<CharakLegalDocument> document(String type, {String? version}) async {
    final query = version == null ? '' : '?version=${Uri.encodeQueryComponent(version)}';
    final res = await ApiClient.instance.get('/legal/documents/$type$query') as Map<String, dynamic>;
    return CharakLegalDocument.fromJson(res);
  }

  /// Record acceptance of exactly these versions. Throws [ApiException] (409)
  /// if one was superseded while the screen was open.
  static Future<void> accept(Iterable<CharakLegalDocument> documents,
      {String method = 'signup_checkbox'}) async {
    await ApiClient.instance.post('/legal/accept', {
      'documents': [
        for (final d in documents) {'type': d.type, 'version': d.version},
      ],
      'method': method,
    });
  }
}

/// Where the documents live, on screens before an account exists: each link
/// opens the current version in full, in the app. Signing comes afterwards
/// ([CharakAgreementsList]), never assumed from "continuing".
class CharakLegalFooter extends StatelessWidget {
  /// The sentence after the links: when signing will be asked for.
  final String afterwards;

  /// The main agreement for this app: the Terms of Use for patients, the
  /// Practitioner Agreement for doctors.
  final String termsType;
  final String termsTitle;

  const CharakLegalFooter({
    super.key,
    this.afterwards = 'You will be asked to sign them before you book.',
    this.termsType = 'tos',
    this.termsTitle = 'Terms of Use',
  });

  @override
  Widget build(BuildContext context) {
    final base = CharakText.caption.copyWith(color: CharakColors.inkMuted);
    final link = base.copyWith(color: CharakColors.primary);
    TapGestureRecognizer tap(String type, String title, String url) => TapGestureRecognizer()
      ..onTap = () => CharakLegalReaderScreen.openCurrent(context, type, title, url);
    return Text.rich(
      TextSpan(style: base, children: [
        const TextSpan(text: 'Read our '),
        TextSpan(text: termsTitle, style: link, recognizer: tap(termsType, termsTitle, CharakLegal.termsUrl)),
        const TextSpan(text: ' and '),
        TextSpan(text: 'Privacy Policy',
            style: link, recognizer: tap('privacy', 'Privacy Policy', CharakLegal.privacyUrl)),
        TextSpan(text: '. $afterwards'),
      ]),
      textAlign: TextAlign.center,
    );
  }
}
