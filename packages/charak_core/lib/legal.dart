import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'components/charak_button.dart';
import 'components/charak_check.dart';
import 'components/charak_sheet.dart';
import 'components/charak_toast.dart';
import 'design/tokens.dart';
import 'network/api_client.dart';

/// One published legal document (backend legal_documents, migration 0024).
class CharakLegalDocument {
  final String type;
  final String version;
  final String title;
  final String url;
  final bool accepted;

  const CharakLegalDocument({
    required this.type,
    required this.version,
    required this.title,
    required this.url,
    this.accepted = false,
  });

  factory CharakLegalDocument.fromJson(Map<String, dynamic> j) => CharakLegalDocument(
        type: j['type'] as String,
        version: j['version'] as String,
        title: j['title'] as String? ?? j['type'] as String,
        url: j['url'] as String? ?? CharakLegal.termsUrl,
        accepted: j['accepted'] == true,
      );

  /// The documents listed in an error body (`consent_required` on a 428).
  static List<CharakLegalDocument> listFrom(dynamic raw) => [
        for (final d in (raw as List? ?? const []))
          if (d is Map<String, dynamic>) CharakLegalDocument.fromJson(d),
      ];
}

/// Legal document links, and consent recorded against the published versions.
///
/// The versions live on the server. A material change is published there, and
/// the apps ask again: [status] reports what is missing, and
/// [showCharakConsentSheet] collects it.
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

/// On reaching home: if a document this person accepted has since been
/// replaced by a material update, ask for the new version. Once per app
/// session (a dismissed sheet isn't pushed again on every tab), and never in
/// the way: a failed check just skips. Where it matters (booking), the server
/// enforces it with a 428 anyway.
bool _consentCheckedThisSession = false;

Future<void> charakAskForMissingConsent(BuildContext context) async {
  if (_consentCheckedThisSession) return;
  _consentCheckedThisSession = true;
  try {
    final missing = (await CharakLegal.status()).missing;
    if (missing.isEmpty || !context.mounted) return;
    await showCharakConsentSheet(context, missing);
  } catch (_) {
    // Offline, or an older backend: the booking path enforces it later.
  }
}

/// One unticked box per document: "I accept the Terms of Use", with the title
/// a link to the published text. Reports whether every box is ticked.
class CharakConsentChecklist extends StatefulWidget {
  final List<CharakLegalDocument> documents;
  final ValueChanged<bool> onAllChecked;

  const CharakConsentChecklist({
    super.key,
    required this.documents,
    required this.onAllChecked,
  });

  @override
  State<CharakConsentChecklist> createState() => _CharakConsentChecklistState();
}

class _CharakConsentChecklistState extends State<CharakConsentChecklist> {
  final _ticked = <String>{};

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final d in widget.documents)
            CharakCheckRow(
              value: _ticked.contains(d.type),
              onChanged: (v) {
                setState(() => v ? _ticked.add(d.type) : _ticked.remove(d.type));
                widget.onAllChecked(_ticked.length == widget.documents.length);
              },
              spans: [
                const TextSpan(text: 'I accept the '),
                CharakCheckRow.link(d.title, () => CharakLegal.open(d.url)),
              ],
            ),
        ],
      );
}

/// Ask for the documents still outstanding (a material change, or a 428 from
/// the API) and record them. Returns true once accepted, false if dismissed.
Future<bool> showCharakConsentSheet(
  BuildContext context,
  List<CharakLegalDocument> documents, {
  String method = 'reconsent',
  String title = 'Before you continue',
  String message = 'We have updated the documents that cover how CHARAK works. '
      'Please review and accept them to continue.',
}) async {
  if (documents.isEmpty) return true;
  final accepted = await showCharakSheet<bool>(
    context,
    title: title,
    child: _ConsentSheetBody(documents: documents, method: method, message: message),
  );
  return accepted == true;
}

class _ConsentSheetBody extends StatefulWidget {
  final List<CharakLegalDocument> documents;
  final String method;
  final String message;
  const _ConsentSheetBody({required this.documents, required this.method, required this.message});

  @override
  State<_ConsentSheetBody> createState() => _ConsentSheetBodyState();
}

class _ConsentSheetBodyState extends State<_ConsentSheetBody> {
  bool _all = false;
  bool _saving = false;

  Future<void> _accept() async {
    setState(() => _saving = true);
    try {
      await CharakLegal.accept(widget.documents, method: widget.method);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showCharakToast(context, message: e.message, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.message, style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
            const SizedBox(height: 14),
            CharakConsentChecklist(
              documents: widget.documents,
              onAllChecked: (v) => setState(() => _all = v),
            ),
            const SizedBox(height: 20),
            CharakButton(
              label: 'Agree and continue',
              isLoading: _saving,
              onPressed: _all && !_saving ? _accept : null,
            ),
          ],
        ),
      );
}

/// Where the documents live, on screens before an account exists. Consent
/// itself is asked for with ticked boxes afterwards ([CharakConsentChecklist]),
/// never assumed from "continuing".
class CharakLegalFooter extends StatelessWidget {
  /// The sentence after the links: when acceptance will be asked for.
  final String afterwards;
  const CharakLegalFooter({
    super.key,
    this.afterwards = 'You will be asked to accept them before you book.',
  });

  @override
  Widget build(BuildContext context) {
    final base = CharakText.caption.copyWith(color: CharakColors.inkMuted);
    final link = base.copyWith(color: CharakColors.primary);
    TapGestureRecognizer tap(String url) =>
        TapGestureRecognizer()..onTap = () => CharakLegal.open(url);
    return Text.rich(
      TextSpan(style: base, children: [
        const TextSpan(text: 'Read our '),
        TextSpan(text: 'Terms', style: link, recognizer: tap(CharakLegal.termsUrl)),
        const TextSpan(text: ' and '),
        TextSpan(text: 'Privacy Policy',
            style: link, recognizer: tap(CharakLegal.privacyUrl)),
        TextSpan(text: '. $afterwards'),
      ]),
      textAlign: TextAlign.center,
    );
  }
}
