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

class ReviewConfirmScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> booking;
  const ReviewConfirmScreen({super.key, required this.booking});
  @override
  ConsumerState<ReviewConfirmScreen> createState() => _State();
}

class _State extends ConsumerState<ReviewConfirmScreen> {
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final b = widget.booking;

      final created = await ApiClient.instance.post('/bookings/', {
        'doctor_id':       b['doctor_id'] as String,
        'channel':         b['channel'] as String,
        'scheduled_start': b['scheduled_start'] as String,
        // Home visits book against a saved address; the backend needs its
        // coordinates to check the doctor's service radius.
        if (b['address_id'] != null) 'address_id': b['address_id'] as String,
      }) as Map<String, dynamic>;

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: CharakPalette.statusDeclined),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
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
    final p        = pricing.where((p) => p['channel'] == channel).firstOrNull;
    final price    = (p?['price'] as num?)?.toDouble() ?? 0;
    final extra    = (p?['extra_rate_per_15min'] as num?)?.toDouble() ?? 0;

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

    return Scaffold(
      backgroundColor: CharakColors.ground,
      appBar: const CharakTopBar(title: 'Review & confirm'),
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
                  value: isHome ? 'Home Visit' : 'Online Consult'),
              const CharakSummaryDivider(),
              if (price > 0)
                CharakSummaryRow(
                    label: 'Consult fee · 15 min',
                    value: '₹${price.toStringAsFixed(0)}',
                    tabular: true),
              if (extra > 0)
                CharakSummaryRow(
                    label: 'Extra 15 min',
                    value: '₹${extra.toStringAsFixed(0)}',
                    muted: true,
                    tabular: true),
              const CharakSummaryDivider(),
              CharakSummaryRow(
                label: 'Payment',
                value: isHome
                    ? 'Consult fee now · procedures billed after visit'
                    : 'Paid before the call',
                muted: true,
              ),
            ]),

            // ── Home-visit billing notice (`.clarify-banner`) ────────────
            if (isHome) ...[
              const SizedBox(height: 12),
              CharakNoteBanner(
                icon: Icons.receipt_long_outlined,
                leadLabel: 'Procedures billed after the visit',
                message: "— if any procedure is done, it's charged at the "
                    'doctor\'s fixed rates on this profile.'
                    '${threshold != null ? ' Bills above ₹${(threshold as num).toStringAsFixed(0)} are reviewed by a senior doctor first.' : ''}',
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
          ],
        )),

        CharakCtaBar.single(
          CharakButton(
            label: price > 0 ? 'Send request · ₹${price.toStringAsFixed(0)}' : 'Send request',
            isLoading: _sending,
            onPressed: _send,
          ),
        ),
      ]),
    );
  }
}
