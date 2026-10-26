import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

final _reviewDoctorProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ApiClient.instance.get('/doctors/$id');
  return res as Map<String, dynamic>;
});

/// The cancellation policy a booking made now would get, shown and ticked
/// before the request is sent (backend GET /legal/cancellation-policy).
final _policyProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, channel) async {
  return await ApiClient.instance.get('/legal/cancellation-policy?channel=$channel')
      as Map<String, dynamic>;
});

/// Which documents this patient has accepted; telemedicine consent is asked
/// for here, at their first online consultation.
final _legalProvider = FutureProvider.autoDispose((ref) => CharakLegal.status());

class ReviewConfirmScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> booking;
  const ReviewConfirmScreen({super.key, required this.booking});
  @override
  ConsumerState<ReviewConfirmScreen> createState() => _State();
}

class _State extends ConsumerState<ReviewConfirmScreen> {
  bool _sending = false;
  bool _policyTicked = false;
  bool _telemedicineTicked = false;

  Future<void> _send({
    required Map<String, dynamic> policy,
    CharakLegalDocument? telemedicine,
  }) async {
    setState(() => _sending = true);
    try {
      final b = widget.booking;

      // First online consultation: record the telemedicine consent the
      // patient just ticked, before the booking that relies on it.
      if (telemedicine != null) {
        await CharakLegal.accept([telemedicine], method: 'booking_confirmation');
      }

      final created = await _create(b, policy['version'] as String);

      final bookingId = created['id'] as String;

      final text = b['text'] as String? ?? '';
      if (text.isNotEmpty) {
        await ApiClient.instance.post('/bookings/$bookingId/intake', {
          'media_type': 'text',
          'transcript_text': text,
        });
      }

      // Photos, video and the voice note are files, not text — they go through
      // the upload endpoint. The voice note is what triggers transcription
      // server-side, so sending only a transcript string would leave the
      // doctor reading a placeholder.
      await _uploadIntakeMedia(bookingId, b);

      if (mounted) context.go('/book/sent/$bookingId');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409 && e.body?['policy'] != null) {
        // The policy changed while this screen was open: show the new one,
        // and ask for the tick again.
        ref.invalidate(_policyProvider(widget.booking['channel'] as String));
        setState(() => _policyTicked = false);
      }
      showCharakToast(context, message: e.message, isError: true);
      if (e.statusCode == 409 && e.body?['code'] == 'price_changed') {
        // The doctor changed their price: back to the first step, where the
        // new prices are shown. Nothing was booked.
        final b = widget.booking;
        context.go('/book/${b['doctor_id']}/channel',
            extra: {if (b['follow_up_of'] != null) 'follow_up_of': b['follow_up_of']});
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Create the booking. A 428 means a document this booking needs hasn't been
  /// accepted (a material update since sign-up): show it, then try once more.
  Future<Map<String, dynamic>> _create(Map<String, dynamic> b, String policyVersion) async {
    Future<Map<String, dynamic>> post() async => await ApiClient.instance.post('/bookings/', {
          'doctor_id':       b['doctor_id'] as String,
          'channel':         b['channel'] as String,
          'scheduled_start': b['scheduled_start'] as String,
          // Home visits book against a saved address; the backend needs its
          // coordinates to check the doctor's service radius.
          if (b['address_id'] != null) 'address_id': b['address_id'] as String,
          'accepted_policy_version': policyVersion,
          // The price option picked and the price shown. The server charges its
          // own price, and refuses (409 price_changed) if it isn't this one.
          if (b['price_rule_id'] != null) 'price_rule_id': b['price_rule_id'],
          if (b['duration_min'] != null) 'duration_min': b['duration_min'],
          if (b['price_paise'] != null) 'expected_price_paise': b['price_paise'],
          if (b['follow_up_of'] != null) 'follow_up_of': b['follow_up_of'],
          if (b['replaces_incident_id'] != null) 'replaces_incident_id': b['replaces_incident_id'],
        }) as Map<String, dynamic>;
    try {
      return await post();
    } on ApiException catch (e) {
      final needed = CharakLegalDocument.listFrom(e.body?['consent_required']);
      if (e.statusCode != 428 || needed.isEmpty || !mounted) rethrow;
      final ok = await showCharakConsentSheet(context, needed, method: 'reconsent');
      if (!ok) rethrow;
      return await post();
    }
  }

  /// Upload every attachment the patient added during intake.
  ///
  /// A failed attachment must not lose the booking — it is already created and
  /// the doctor has been notified — so each upload is reported and skipped
  /// rather than thrown. `_mediaWarning` surfaces that on the next screen.
  Future<void> _uploadIntakeMedia(String bookingId, Map<String, dynamic> b) async {
    final failures = <String>[];

    Future<void> send(String path, String mediaType, String kind) async {
      try {
        final file = File(path);
        if (!await file.exists()) {
          failures.add(kind);
          return;
        }
        await ApiClient.instance.postFile(
          '/uploads/bookings/$bookingId/intake?media_type=$mediaType',
          bytes: await file.readAsBytes(),
          filename: path.split('/').last,
        );
      } catch (_) {
        failures.add(kind);
      }
    }

    for (final path in (b['images'] as List? ?? const [])) {
      await send(path as String, 'image', 'a photo');
    }
    for (final path in (b['videos'] as List? ?? const [])) {
      await send(path as String, 'video', 'a video');
    }
    final voice = b['voice_path'] as String?;
    if (voice != null && voice.isNotEmpty) {
      await send(voice, 'voice', 'your voice note');
    }

    if (failures.isNotEmpty && mounted) {
      showCharakToast(context,
          message: 'Booking sent, but ${failures.toSet().join(' and ')} '
              "couldn't be attached.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final b       = widget.booking;
    final channel = b['channel'] as String? ?? '';
    final start   = b['scheduled_start'] as String? ?? '';
    final dt      = DateTime.tryParse(start.replaceAll('+05:30', ''))?.toLocal();
    final dateStr = dt != null ? DateFormat('EEE, d MMM, h:mm a').format(dt) : start;
    final text    = b['text'] as String? ?? '';
    final transcript = b['voice_transcript'] as String? ?? '';
    final images  = b['images'] as List? ?? [];
    final videos  = b['videos'] as List? ?? [];
    final isHome  = channel == 'home_visit';

    final docAsync  = ref.watch(_reviewDoctorProvider(b['doctor_id'] as String));
    final docName   = docAsync.maybeWhen(data: (d) => d['name'] as String?, orElse: () => null);
    final pricing   = docAsync.maybeWhen(
      data: (d) => List<Map<String,dynamic>>.from(d['doctor_pricing'] as List? ?? []),
      orElse: () => <Map<String,dynamic>>[],
    );
    final threshold = docAsync.maybeWhen(
      data: (d) => d['procedure_review_threshold'],
      orElse: () => null,
    );
    // The option picked in the first step. (A draft without one comes from a
    // flow that predates the matrix; show the doctor's listed price.)
    final p        = pricing.where((p) => p['channel'] == channel).firstOrNull;
    final paise    = (b['price_paise'] as num?)?.toInt();
    final price    = paise != null ? paise / 100 : (p?['price'] as num?)?.toDouble() ?? 0;
    final mins     = (b['duration_min'] as num?)?.toInt() ?? (p?['base_duration_min'] as num?)?.toInt() ?? 15;
    final followUp = b['visit_category'] == 'follow_up';
    final replacing = b['replaces_incident_id'] != null;

    final intakeLabel = text.isNotEmpty
        ? 'Text'
        : transcript.isNotEmpty
            ? 'Voice · transcribed'
            : images.isNotEmpty
                ? 'Photo · ${images.length} file${images.length > 1 ? 's' : ''}'
                : videos.isNotEmpty
                    ? 'Video · ${videos.length} file${videos.length > 1 ? 's' : ''}'
                    : null;
    final intakePreview = text.isNotEmpty ? text : transcript;

    final policyAsync = ref.watch(_policyProvider(channel));
    final policy = policyAsync.valueOrNull;
    final legal = ref.watch(_legalProvider).valueOrNull;
    // Asked once: only when this is an online consult and the current version
    // hasn't been accepted.
    final telemedicine = isHome
        ? null
        : legal?.documents.where((d) => d.type == 'telemedicine' && !d.accepted).firstOrNull;
    final freeMinutes = (policy?['free_cancellation_minutes'] as num?)?.toInt();
    final startAt = DateTime.tryParse(start)?.toLocal();
    final freeUntil = (freeMinutes != null && startAt != null)
        ? startAt.subtract(Duration(minutes: freeMinutes))
        : null;
    final ready = policy != null &&
        _policyTicked &&
        (telemedicine == null || _telemedicineTicked);

    return CharakScreen(
      title: 'Review & confirm',
      body: Column(children: [
        Expanded(child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [

            // ── `.card.rev-sum` ──────────────────────────────────────────
            CharakSummaryCard(rows: [
              if (docName != null) CharakSummaryRow(label: 'Doctor', value: docName),
              CharakSummaryRow(label: 'When', value: dateStr),
              CharakSummaryRow(
                  label: 'Channel',
                  value: CharakFormat.channel(isHome ? 'home_visit' : 'online_consult')),
              const CharakSummaryDivider(),
              CharakSummaryRow(
                  label: '${followUp ? 'Follow-up' : 'Consult fee'} · $mins min',
                  value: price > 0 ? CharakFormat.rupees(price) : 'Free',
                  tabular: true),
              const CharakSummaryDivider(),
              CharakSummaryRow(
                label: 'Payment',
                value: replacing
                    ? 'Covered by your earlier payment'
                    : price <= 0
                    ? 'Nothing to pay'
                    : isHome
                        ? 'Consult fee now · procedures billed after visit'
                        : 'Paid before the call',
                muted: true,
              ),
            ]),

            // ── Home-visit billing notice (`.clarify-banner`) ────────────
            if (isHome) ...[
              const SizedBox(height: 12),
              CharakNoteBanner(
                icon: LucideIcons.receiptText,
                leadLabel: 'Procedures billed after the visit',
                message: "— if any procedure is done, it's charged at the "
                    'doctor\'s fixed rates on this profile.'
                    '${threshold != null ? ' Bills above ${CharakFormat.rupees(threshold as num)} are reviewed by a senior doctor first.' : ''}',
              ),
            ],

            // ── `.intake-prev` ───────────────────────────────────────────
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: CharakColors.bgSubtle,
                borderRadius: const BorderRadius.all(CharakRadius.card),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (intakeLabel != null) ...[
                  CharakBadge(label: intakeLabel),
                  const SizedBox(height: 8),
                ],
                Text(
                  intakePreview.isNotEmpty ? intakePreview : 'No description added',
                  style: CharakText.body.copyWith(
                    fontSize: 13.5,
                    height: 1.6,
                    color: intakePreview.isNotEmpty
                        ? CharakColors.ink
                        : CharakColors.inkMuted,
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 10),
            Text(
              'The doctor reviews your request before accepting — booking a '
              'slot does not confirm it automatically.',
              style: charakHintStyle,
            ),

            // ── Cancellation policy, shown and ticked before booking ─────
            const SizedBox(height: 18),
            policyAsync.when(
              loading: () => const CharakSkeleton(height: 120, radius: 26),
              error: (e, _) => CharakErrorState(
                error: e,
                onRetry: () => ref.invalidate(_policyProvider(channel)),
              ),
              data: (policy) => CharakSummaryCard(
                title: 'Cancellation',
                rows: [
                  Text(
                    freeUntil != null
                        ? 'Free cancellation until ${CharakFormat.dayTime(freeUntil)}'
                        : 'Free cancellation until the consultation starts',
                    style: CharakText.label.copyWith(color: CharakColors.ink),
                  ),
                  const SizedBox(height: 6),
                  Text(policy['summary'] as String? ?? '',
                      style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
                  const SizedBox(height: 6),
                  CharakCheckRow(
                    value: _policyTicked,
                    onChanged: (v) => setState(() => _policyTicked = v),
                    label: "I've read the cancellation policy",
                  ),
                  if (telemedicine != null)
                    CharakCheckRow(
                      value: _telemedicineTicked,
                      onChanged: (v) => setState(() => _telemedicineTicked = v),
                      spans: [
                        const TextSpan(text: 'I accept the '),
                        CharakCheckRow.link(telemedicine.title,
                            () => CharakLegal.open(telemedicine.url)),
                        const TextSpan(text: ' for consultations by video'),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'CHARAK is not for emergencies. In an emergency, call 112.',
              style: charakHintStyle,
            ),
          ],
        )),

        CharakCtaBar(
          // A disabled button needs a reason: the boxes to tick sit below the
          // fold on most phones.
          header: ready || policy == null
              ? null
              : Text(
                  telemedicine != null && !_telemedicineTicked && _policyTicked
                      ? 'Accept the telemedicine consent below to continue.'
                      : 'Tick the cancellation policy below to continue.',
                  style: charakHintStyle,
                  textAlign: TextAlign.center,
                ),
          children: [
            Expanded(
              child: CharakButton(
                label: price > 0 && !replacing ? 'Send request · ${CharakFormat.rupees(price)}' : 'Send request',
                isLoading: _sending,
                onPressed: ready && !_sending
                    ? () => _send(policy: policy, telemedicine: telemedicine)
                    : null,
              ),
            ),
          ],
        ),
      ]),
    );
  }
}
