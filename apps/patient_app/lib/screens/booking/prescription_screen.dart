import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../home/booking_providers.dart';

/// Opening the prescription: `POST /prescriptions/{id}/view` records the first
/// open on the server (once; later opens change nothing) and completes the
/// visit if it was waiting on it. So this screen is the only place the
/// content is fetched: reading it and recording it are one call.
final _prescriptionProvider =
    FutureProvider.autoDispose.family<_Opened, String>((ref, id) async {
  final rx = CharakPrescription.fromJson(
      await ApiClient.instance.post('/prescriptions/$id/view', {}) as Map<String, dynamic>);
  final booking = await ApiClient.instance.get('/bookings/${rx.bookingId}') as Map<String, dynamic>;
  // The visit may have just completed: lists elsewhere should say so.
  ref.invalidate(patientBookingsProvider);
  return _Opened(rx, booking);
});

class _Opened {
  final CharakPrescription rx;
  final Map<String, dynamic> booking;
  const _Opened(this.rx, this.booking);
}

class PrescriptionScreen extends ConsumerWidget {
  final String prescriptionId;
  const PrescriptionScreen({super.key, required this.prescriptionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_prescriptionProvider(prescriptionId));
    return async.when(
      loading: () => const CharakScreen(
        title: 'Prescription',
        body: SingleChildScrollView(child: CharakSkeletonDetail()),
      ),
      error: (e, _) => CharakScreen(
        title: 'Prescription',
        body: CharakErrorState(error: e, onRetry: () => ref.invalidate(_prescriptionProvider(prescriptionId))),
      ),
      data: (o) => _Body(rx: o.rx, booking: o.booking),
    );
  }
}

class _Body extends StatefulWidget {
  final CharakPrescription rx;
  final Map<String, dynamic> booking;
  const _Body({required this.rx, required this.booking});

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _opening = false;

  /// The PDF (or the handwritten upload) through a link that works for five
  /// minutes. Downloading isn't what completes the visit; opening this
  /// screen already did.
  Future<void> _open(String key) async {
    setState(() => _opening = true);
    try {
      final files = await ApiClient.instance.get('/prescriptions/${widget.rx.id}/files') as Map;
      final url = files[key] as String?;
      if (url == null || !await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        if (mounted) showCharakToast(context, message: "Couldn't open the file", isError: true);
      }
    } on ApiException catch (e) {
      if (mounted) showCharakToast(context, message: e.message, isError: true);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _bookFollowUp() {
    final doctorId = widget.booking['doctor_id'] as String?;
    if (doctorId != null) context.push('/doctor/$doctorId');
  }

  @override
  Widget build(BuildContext context) {
    final rx = widget.rx;
    final doc = widget.booking['doctors'] as Map<String, dynamic>? ?? const {};
    final docName = CharakFormat.doctor(doc['name'] as String?);
    final specialty = (doc['categories'] as Map?)?['name'] as String?;
    final sent = rx.submittedAt;
    final followUpOpen = rx.followUp != null && rx.followUp!.status == 'open';

    return CharakScreen(
      title: rx.isNotes ? 'Consultation notes' : 'Prescription',
      subtitle: [docName, if (sent != null) CharakFormat.dayTime(sent)].join(' · '),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 4, CharakSpacing.gutter, 32),
        children: [
          if (rx.isSuperseded) ...[
            const CharakNoteBanner(
              icon: LucideIcons.fileWarning,
              leadLabel: 'Replaced.',
              message: ' Your doctor sent a corrected version. Use that one.',
              tone: CharakStatusTone.review,
            ),
            const SizedBox(height: 8),
            if (rx.replacedById != null)
              CharakButton(
                label: 'Open the corrected prescription',
                onPressed: () => context.pushReplacement('/prescription/${rx.replacedById}'),
              ),
            const SizedBox(height: 12),
          ] else if (rx.version > 1) ...[
            const CharakNoteBanner(
              icon: LucideIcons.filePen,
              leadLabel: 'Corrected by your doctor.',
              message: ' This version replaces the one sent earlier.',
              tone: CharakStatusTone.primary,
            ),
            const SizedBox(height: 12),
          ],
          CharakCard(
            child: Row(children: [
              CharakAvatar(name: docName, imageUrl: doc['photo_url'] as String?, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(docName, style: CharakText.body.weight(600).copyWith(color: CharakColors.ink)),
                  Text(
                    [if (specialty != null) specialty, CharakFormat.channel(widget.booking['channel'] as String?)]
                        .join(' · '),
                    style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          CharakPrescriptionView(
            prescription: rx,
            followUpAction: followUpOpen
                ? CharakButton(
                    label: 'Book follow-up',
                    icon: LucideIcons.calendarPlus,
                    variant: CharakButtonVariant.tonal,
                    onPressed: _bookFollowUp,
                  )
                : null,
          ),
          if (rx.hasUpload) ...[
            CharakButton(
              label: 'Open handwritten prescription',
              icon: LucideIcons.fileImage,
              variant: CharakButtonVariant.outline,
              isLoading: _opening,
              onPressed: () => _open('upload_url'),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'Take medicines only as your doctor prescribed. If symptoms get worse, or in an '
            'emergency, call 112 or go to the nearest hospital.',
            style: charakHintStyle,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      bottom: rx.hasPdf
          ? CharakCtaBar.single(CharakButton(
              label: 'Download PDF',
              icon: LucideIcons.download,
              isLoading: _opening,
              onPressed: () => _open('pdf_url'),
            ))
          : null,
    );
  }
}
