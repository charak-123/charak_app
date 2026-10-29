import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'components/charak_button.dart';
import 'components/charak_card.dart';
import 'components/charak_check.dart';
import 'components/charak_controls.dart';
import 'components/charak_layout.dart';
import 'components/charak_sheet.dart';
import 'components/charak_toast.dart';
import 'design/motion.dart';
import 'design/tokens.dart';
import 'format/charak_format.dart';
import 'legal.dart';
import 'legal_text.dart';
import 'network/api_client.dart';

// The screens where people read and sign the legal documents: each one
// readable in full in the app, agreed to with its own tick (reading is up to
// them, LD-014), and a signature recorded against the exact version and its
// fingerprint (backend /legal, migration 0030). This is how the apps ask at
// sign-up, at a material change, and when a booking needs a document signed
// first.

Future<T?> _push<T>(BuildContext context, Widget screen) => Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (_, __, ___) => CharakEntranceScope(child: screen),
        transitionDuration: CharakDurations.screenPush,
        reverseTransitionDuration: CharakDurations.screenPush,
        transitionsBuilder: charakPushTransition,
      ),
    );

String _date(DateTime d) => DateFormat('d MMM y').format(d.toLocal());
String _dateTime(DateTime d) => DateFormat('d MMM y, h:mm a').format(d.toLocal());

// ── Reading one document ─────────────────────────────────────────────────────

/// One document, in full. With [signing], the bottom bar asks for agreement
/// and the screen pops `true` when they agree. Without it, the document is
/// just shown.
class CharakLegalReaderScreen extends StatefulWidget {
  final String type;

  /// A specific version (the one someone signed); null for the current one.
  final String? version;

  /// Shown while the text loads.
  final String title;

  final bool signing;

  /// When this person signed the version shown, for the "You signed" note.
  final DateTime? acceptedAt;

  /// The web page, for versions from before the text was stored (0030).
  final String? url;

  const CharakLegalReaderScreen({
    super.key,
    required this.type,
    required this.title,
    this.version,
    this.signing = false,
    this.acceptedAt,
    this.url,
  });

  /// Open [document]. Returns true only when signing and the person agreed.
  static Future<bool> open(
    BuildContext context,
    CharakLegalDocument document, {
    bool signing = false,
  }) async =>
      await _push<bool>(
        context,
        CharakLegalReaderScreen(
          type: document.type,
          version: document.version,
          title: document.title,
          signing: signing,
          acceptedAt: document.accepted ? document.acceptedAt : null,
          url: document.url,
        ),
      ) ==
      true;

  /// The current version of [type], before an account exists (sign-in).
  static Future<void> openCurrent(BuildContext context, String type, String title, String url) =>
      _push<void>(context, CharakLegalReaderScreen(type: type, title: title, url: url));

  @override
  State<CharakLegalReaderScreen> createState() => _CharakLegalReaderScreenState();
}

class _CharakLegalReaderScreenState extends State<CharakLegalReaderScreen> {
  late Future<CharakLegalDocument> _doc = _load();

  Future<CharakLegalDocument> _load() => CharakLegal.document(widget.type, version: widget.version);

  @override
  Widget build(BuildContext context) => FutureBuilder<CharakLegalDocument>(
        future: _doc,
        builder: (context, snap) {
          final doc = snap.data;
          final noText = snap.hasError && snap.error is ApiException && (snap.error as ApiException).statusCode == 404;
          return CharakScreen(
            title: doc?.title ?? widget.title,
            eyebrow: doc?.publishedAt != null ? 'Version of ${_date(doc!.publishedAt!)}' : null,
            subtitle: doc?.summary,
            barTitle: widget.title,
            body: switch (snap.connectionState) {
              ConnectionState.done when doc != null && doc.body != null => _text(doc),
              ConnectionState.done when noText || doc != null => _webOnly(doc),
              ConnectionState.done => ListView(children: [
                  CharakErrorState(
                    error: snap.error,
                    onRetry: () => setState(() => _doc = _load()),
                  ),
                ]),
              _ => ListView(
                  padding: const EdgeInsets.symmetric(horizontal: CharakSpacing.gutter),
                  children: const [CharakSkeletonDetail()],
                ),
            },
            bottom: widget.signing ? _agreeBar() : null,
          );
        },
      );

  Widget _text(CharakLegalDocument doc) => ListView(
        padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 0, CharakSpacing.gutter, 40),
        children: [
          if (widget.acceptedAt != null) ...[
            CharakInfoStrip(
              icon: LucideIcons.badgeCheck,
              tone: CharakStatusTone.success,
              label: 'You signed this version on ${_dateTime(widget.acceptedAt!)}',
            ),
            const SizedBox(height: 14),
          ],
          if (doc.highlights.isNotEmpty) ...[
            CharakLegalHighlights(points: doc.highlights),
            const SizedBox(height: 28),
          ],
          CharakLegalText(body: doc.body!),
          const SizedBox(height: 20),
          Container(height: 1, color: CharakColors.border),
          const SizedBox(height: 14),
          Text('End of the ${doc.title}', style: charakHintStyle),
          if (doc.sha256 != null) ...[
            const SizedBox(height: 4),
            Text(
              'Fingerprint ${doc.sha256!.substring(0, 16)}',
              style: CharakText.caption.tabular.copyWith(color: CharakColors.inkFaint),
            ),
          ],
        ],
      );

  /// A version from before the text was stored: its words are on the website.
  Widget _webOnly(CharakLegalDocument? doc) => ListView(
        padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 0, CharakSpacing.gutter, 40),
        children: [
          Text(
            'This version is published on our website. Open it to read it in full.',
            style: CharakText.body.copyWith(color: CharakColors.inkMuted),
          ),
          const SizedBox(height: 16),
          CharakButton(
            label: 'Read it on charak.care',
            variant: CharakButtonVariant.outline,
            icon: LucideIcons.externalLink,
            onPressed: () => CharakLegal.open(doc?.url ?? widget.url ?? CharakLegal.termsUrl),
          ),
        ],
      );

  Widget _agreeBar() => CharakCtaBar(
        children: [
          Expanded(
            child: CharakButton(label: 'I agree', onPressed: () => Navigator.of(context).pop(true)),
          ),
        ],
      );
}

/// The key points of a document, above its full text.
class CharakLegalHighlights extends StatelessWidget {
  final List<String> points;
  const CharakLegalHighlights({super.key, required this.points});

  @override
  Widget build(BuildContext context) => CharakCard(
        tone: CharakCardTone.tint,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CharakSectionTitle(label: 'In short'),
          const SizedBox(height: 10),
          for (final p in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 10),
                  child: Icon(LucideIcons.check, size: 16, color: CharakColors.primary),
                ),
                Expanded(
                  child: Text(p, style: CharakText.body.copyWith(color: CharakColors.ink, height: 1.5)),
                ),
              ]),
            ),
        ]),
      );
}

// ── Signing a set of documents ───────────────────────────────────────────────

/// The documents to sign, one tick each: "I agree to the Practitioner
/// Agreement", the title opening the full text in the app. Reading is up to
/// the person; agreeing in the reader ticks the box too. Reports whether
/// every one is ticked. The screen that hosts it records the signatures
/// ([CharakLegal.accept]) with its own button.
class CharakAgreementsList extends StatefulWidget {
  final List<CharakLegalDocument> documents;
  final ValueChanged<bool> onAllAgreed;

  const CharakAgreementsList({super.key, required this.documents, required this.onAllAgreed});

  @override
  State<CharakAgreementsList> createState() => _CharakAgreementsListState();
}

class _CharakAgreementsListState extends State<CharakAgreementsList> {
  final _agreed = <String>{};

  void _set(CharakLegalDocument d, bool agreed) {
    setState(() => agreed ? _agreed.add(d.type) : _agreed.remove(d.type));
    widget.onAllAgreed(widget.documents.every((x) => _agreed.contains(x.type)));
  }

  Future<void> _read(CharakLegalDocument d) async {
    final agreed = await CharakLegalReaderScreen.open(context, d, signing: true);
    if (mounted && agreed) _set(d, true);
  }

  @override
  Widget build(BuildContext context) => CharakCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final d in widget.documents)
              Semantics(
                label: d.summary,
                child: CharakCheckRow(
                  value: _agreed.contains(d.type),
                  onChanged: (v) => _set(d, v),
                  spans: [
                    const TextSpan(text: 'I agree to the '),
                    CharakCheckRow.link(d.title, () => _read(d)),
                  ],
                ),
              ),
          ],
        ),
      );
}

/// The full-screen signing flow: every document in [documents] read and
/// agreed, then one "Sign and continue" that records them all. Returns true
/// once signed, false if the person went back.
Future<bool> showCharakAgreements(
  BuildContext context,
  List<CharakLegalDocument> documents, {
  String method = 'reconsent',
  String title = 'Review and sign',
  String message = 'We have updated the documents that cover how CHARAK works. '
      'Agree to each one to continue. Tap a title to read it.',
}) async {
  if (documents.isEmpty) return true;
  return await _push<bool>(
        context,
        _AgreementsScreen(documents: documents, method: method, title: title, message: message),
      ) ==
      true;
}

class _AgreementsScreen extends StatefulWidget {
  final List<CharakLegalDocument> documents;
  final String method;
  final String title;
  final String message;
  const _AgreementsScreen({
    required this.documents,
    required this.method,
    required this.title,
    required this.message,
  });

  @override
  State<_AgreementsScreen> createState() => _AgreementsScreenState();
}

class _AgreementsScreenState extends State<_AgreementsScreen> {
  bool _all = false;
  bool _saving = false;

  Future<void> _sign() async {
    setState(() => _saving = true);
    try {
      await CharakLegal.accept(widget.documents, method: widget.method);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showCharakToast(context, message: e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) => CharakScreen(
        title: widget.title,
        subtitle: widget.message,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 0, CharakSpacing.gutter, 32),
          children: [
            CharakAgreementsList(documents: widget.documents, onAllAgreed: (v) => setState(() => _all = v)),
            const SizedBox(height: 8),
            Text(charakSigningStatement, style: charakHintStyle),
          ],
        ),
        bottom: CharakCtaBar(
          header: _all
              ? null
              : Text('Agree to each document to continue.',
                  style: charakHintStyle, textAlign: TextAlign.center),
          children: [
            Expanded(
              child: CharakButton(
                label: 'Sign and continue',
                isLoading: _saving,
                onPressed: _all && !_saving ? _sign : null,
              ),
            ),
          ],
        ),
      );
}

/// What signing means, under every list of documents to sign.
const charakSigningStatement =
    'Tapping the button below is your electronic signature. We record the version of each '
    'document you agreed to and when. You can read them again any time in Profile → Legal.';

/// On reaching home: if a document this person must sign has a new version
/// (a material change) or was never signed, ask for it. Once per app session
/// (going back isn't asked again on every tab), and never in the way: a
/// failed check just skips. Where it matters (booking, accepting a booking),
/// the server enforces it with a 428 anyway.
bool _askedThisSession = false;

Future<void> charakAskForMissingConsent(BuildContext context) async {
  if (_askedThisSession) return;
  _askedThisSession = true;
  try {
    final missing = (await CharakLegal.status()).missing;
    if (missing.isEmpty || !context.mounted) return;
    await showCharakAgreements(context, missing);
  } catch (_) {
    // Offline, or an older backend: the booking path enforces it later.
  }
}

/// Run [call]; if the server answers 428 because a document must be signed
/// first (a new version since this person last signed), show the documents,
/// and once they're signed run [call] once more. Any other error, or going
/// back without signing, is rethrown as it was.
Future<T> charakWithSignatures<T>(BuildContext context, Future<T> Function() call) async {
  try {
    return await call();
  } on ApiException catch (e) {
    final needed = CharakLegalDocument.listFrom(e.body?['consent_required']);
    if (e.statusCode != 428 || needed.isEmpty || !context.mounted) rethrow;
    if (!await showCharakAgreements(context, needed)) rethrow;
    return await call();
  }
}

// ── What this person has signed ──────────────────────────────────────────────

/// Profile → Legal: every document that covers this person, the version they
/// signed and when, each readable in full; and a way to sign anything new.
class CharakLegalCenterScreen extends StatefulWidget {
  const CharakLegalCenterScreen({super.key});

  static Future<void> open(BuildContext context) => _push<void>(context, const CharakLegalCenterScreen());

  @override
  State<CharakLegalCenterScreen> createState() => _CharakLegalCenterScreenState();
}

class _CharakLegalCenterScreenState extends State<CharakLegalCenterScreen> {
  late Future<({List<CharakLegalDocument> documents, List<CharakLegalDocument> missing})> _status =
      CharakLegal.status();

  void _reload() => setState(() => _status = CharakLegal.status());

  @override
  Widget build(BuildContext context) => CharakScreen(
        title: 'Legal',
        subtitle: 'The documents that cover your use of CHARAK, and the versions you signed.',
        body: FutureBuilder(
          future: _status,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: CharakSpacing.gutter),
                children: const [CharakSkeleton(height: 220, radius: 26)],
              );
            }
            if (snap.hasError) {
              return ListView(children: [CharakErrorState(error: snap.error, onRetry: _reload)]);
            }
            final (:documents, :missing) = snap.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 0, CharakSpacing.gutter, 32),
              children: [
                if (missing.isNotEmpty) ...[
                  CharakNoteBanner(
                    icon: LucideIcons.fileSignature,
                    tone: CharakStatusTone.warning,
                    leadLabel: 'To sign',
                    message: missing.length == 1
                        ? 'The ${missing.first.title} has a version you haven\'t signed yet.'
                        : '${missing.length} documents have versions you haven\'t signed yet.',
                  ),
                  const SizedBox(height: 10),
                  CharakButton(
                    label: 'Review and sign',
                    onPressed: () async {
                      if (await showCharakAgreements(context, missing)) _reload();
                    },
                  ),
                  const SizedBox(height: 24),
                ],
                CharakGroupedList(
                  label: 'Your documents',
                  children: [
                    for (var i = 0; i < documents.length; i++)
                      CharakListRow(
                        icon: documents[i].accepted ? LucideIcons.fileCheck : LucideIcons.fileText,
                        title: documents[i].title,
                        subtitle: documents[i].accepted && documents[i].acceptedAt != null
                            ? 'Signed ${_date(documents[i].acceptedAt!)}'
                            : documents[i].required
                                ? 'Not signed yet'
                                : documents[i].publishedAt != null
                                    ? 'Version of ${_date(documents[i].publishedAt!)}'
                                    : null,
                        last: i == documents.length - 1,
                        onTap: () => CharakLegalReaderScreen.open(context, documents[i]),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                CharakGroupedList(
                  label: 'Questions',
                  children: [
                    CharakListRow(
                      icon: LucideIcons.lifeBuoy,
                      title: 'Help and grievances',
                      subtitle: 'Our Grievance Officer answers within 24 hours',
                      last: true,
                      onTap: () => CharakLegal.open(CharakLegal.supportUrl),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
}

// ── The cancellation rules for one booking ───────────────────────────────────

/// The Cancellation & Refund Policy for the kind of booking being made
/// (GET /legal/cancellation-policy), the way checkout pages show terms: the
/// card says when free cancellation ends and, in a line, what happens after;
/// "View details" opens a sheet with every case (`points`), how refunds are
/// paid and the full policy. The confirm screen puts the agreement tick under
/// it.
class CharakCancellationRules extends StatelessWidget {
  /// The policy from GET /legal/cancellation-policy.
  final Map<String, dynamic> policy;

  /// When free cancellation ends for this booking, if it does before the start.
  final DateTime? freeUntil;

  /// Opens the full Cancellation & Refund Policy.
  final VoidCallback? onReadPolicy;

  /// Under the rules: the agreement tick.
  final Widget? footer;

  const CharakCancellationRules({
    super.key,
    required this.policy,
    this.freeUntil,
    this.onReadPolicy,
    this.footer,
  });

  static CharakStatusTone _tone(String? tone) => switch (tone) {
        'full' => CharakStatusTone.success,
        'partial' => CharakStatusTone.warning,
        'none' => CharakStatusTone.danger,
        _ => CharakStatusTone.primary,
      };

  List<Map<String, dynamic>> get _points => [
        for (final p in (policy['points'] as List? ?? const []))
          if (p is Map<String, dynamic>) p,
      ];

  String get _headline => freeUntil != null
      ? 'Free cancellation until ${CharakFormat.dayTime(freeUntil!)}'
      : policy['channel'] == 'home_visit'
          ? 'Free cancellation until the visit'
          : 'Free cancellation until the consultation starts';

  /// Whose side of the table a row sits on. Backends from before `by` wrote
  /// the doctor's rows as sentences starting "The doctor".
  static String _by(Map<String, dynamic> p) =>
      p['by'] as String? ?? ((p['when'] as String? ?? '').startsWith('The doctor') ? 'doctor' : 'patient');

  /// What the patient's own later cancellations get, from the tones of their
  /// rows. Null when the backend sent no cases (the sheet shows its summary).
  String? get _afterLine {
    final tones = {for (final p in _points) if (_by(p) == 'patient') p['tone']};
    final partial = tones.contains('partial');
    final none = tones.contains('none');
    if (partial && none) return 'After that, a partial refund or none, depending on timing.';
    if (partial) return 'After that, a partial refund.';
    if (none) return 'After that, no refund.';
    return null;
  }

  /// Every case, in a sheet over the confirm screen: two tables, the
  /// patient's own cancellation and what happens when the doctor can't make
  /// it, each row a timing and its refund.
  void _showDetails(BuildContext context) => showCharakSheet<void>(
        context,
        title: 'Cancellation & refunds',
        child: Builder(
          builder: (sheet) => SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_headline, style: CharakText.label.weight(600).copyWith(color: CharakColors.ink)),
              const SizedBox(height: 16),
              if (_points.isEmpty)
                // An older backend, or rules it couldn't describe: the summary.
                Text(policy['summary'] as String? ?? '', style: CharakText.body.copyWith(color: CharakColors.inkMuted))
              else
                for (final (side, label) in const [('patient', 'If you cancel'), ('doctor', "If the doctor can't make it")])
                  if (_points.where((p) => _by(p) == side).toList() case final rows when rows.isNotEmpty) ...[
                    CharakSectionTitle(label: label),
                    const SizedBox(height: 2),
                    for (var i = 0; i < rows.length; i++)
                      _RuleRow(
                        when: rows[i]['when'] as String? ?? '',
                        outcome: rows[i]['outcome'] as String? ?? '',
                        note: rows[i]['note'] as String?,
                        tone: _tone(rows[i]['tone'] as String?),
                        first: i == 0,
                      ),
                    const SizedBox(height: 8),
                  ],
              if (policy['refund_timing'] case final String timing) ...[
                const SizedBox(height: 12),
                Text(timing, style: charakHintStyle),
              ],
              if (onReadPolicy != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: CharakGhostButton(label: 'Read the full policy', onPressed: onReadPolicy),
                ),
              ],
              const SizedBox(height: 16),
              CharakButton(label: 'Got it', onPressed: () => Navigator.of(sheet).pop()),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final after = _afterLine;
    return CharakSummaryCard(
      title: 'Cancellation & refunds',
      rows: [
        Text(_headline, style: CharakText.label.weight(600).copyWith(color: CharakColors.ink)),
        if (after != null) ...[
          const SizedBox(height: 4),
          Text(after, style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: CharakGhostButton(label: 'View details', onPressed: () => _showDetails(context)),
        ),
        if (footer != null) ...[const SizedBox(height: 4), footer!],
      ],
    );
  }
}

/// One row of a policy table: the timing on the left, the refund on the
/// right in its tone, fine print under both.
class _RuleRow extends StatelessWidget {
  final String when;
  final String outcome;
  final String? note;
  final CharakStatusTone tone;
  final bool first;
  const _RuleRow({required this.when, required this.outcome, this.note, required this.tone, required this.first});

  @override
  Widget build(BuildContext context) {
    final (_, ink) = charakToneColors(tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: first ? null : BoxDecoration(border: Border(top: BorderSide(color: CharakColors.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // The refund takes the width it needs (up to half the row) and the
        // timing gets the rest, so short refunds don't squeeze the timing.
        LayoutBuilder(
          builder: (context, box) => Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(when, style: CharakText.body.copyWith(color: CharakColors.ink, height: 1.35)),
              ),
              const SizedBox(width: 16),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth / 2),
                child: Text(
                  outcome,
                  textAlign: TextAlign.right,
                  style: CharakText.label.weight(600).copyWith(color: ink, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(note!, style: charakHintStyle),
        ],
      ]),
    );
  }
}

/// "I agree to the Cancellation & Refund Policy", with the title a link to
/// the full text.
class CharakPolicyAgreeRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final VoidCallback onOpen;
  final String? suffix;

  const CharakPolicyAgreeRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    required this.onOpen,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) => CharakCheckRow(
        value: value,
        onChanged: onChanged,
        spans: [
          const TextSpan(text: 'I agree to the '),
          CharakCheckRow.link(title, onOpen),
          if (suffix != null) TextSpan(text: suffix),
        ],
      );
}
