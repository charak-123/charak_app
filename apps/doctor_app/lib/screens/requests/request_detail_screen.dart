import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _bookingDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final booking = await ApiClient.instance.get('/bookings/$id');
  final intake  = await ApiClient.instance.get('/bookings/$id/intake');
  return {
    'booking': booking as Map<String, dynamic>,
    'intake': intake as List,
  };
});

// ── Screen ────────────────────────────────────────────────────────────────────

class RequestDetailScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const RequestDetailScreen({super.key, required this.bookingId});

  @override
  ConsumerState<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends ConsumerState<RequestDetailScreen> {
  bool _deciding = false;

  Future<void> _accept() async {
    setState(() => _deciding = true);
    try {
      await ApiClient.instance.patch('/bookings/${widget.bookingId}/accept', {});
      if (mounted) context.go('/visit/${widget.bookingId}');
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _deciding = false);
    }
  }

  Future<void> _decline() async {
    setState(() => _deciding = true);
    try {
      await ApiClient.instance.patch('/bookings/${widget.bookingId}/decline', {});
      if (mounted) {
        showCharakToast(context, message: 'Request declined — patient notified');
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _deciding = false);
    }
  }

  void _showError(String msg) =>
      showCharakToast(context, message: msg, isError: true);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_bookingDetailProvider(widget.bookingId));
    return Scaffold(
      backgroundColor: CharakColors.bg,
      appBar: const CharakTopBar(title: 'Request'),
      body: async.when(
        // `.skel` blocks tracing the real body: the `.pat-strip` card, the
        // intake blocks and the visit-details card. The top bar stays live.
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: const [
            CharakSkeleton(height: 74, radius: 14),
            SizedBox(height: 18),
            CharakSkeleton(width: 168, height: 13),
            SizedBox(height: 9),
            CharakSkeleton(height: 82, radius: 12),
            SizedBox(height: 10),
            CharakSkeleton(height: 82, radius: 12),
            SizedBox(height: 16),
            CharakSkeleton(width: 96, height: 13),
            SizedBox(height: 6),
            CharakSkeleton(height: 118, radius: 14),
            SizedBox(height: 14),
            CharakSkeleton(height: 50, radius: 12),
          ],
        ),
        error: (e, _) => Center(
          child: Text('Failed to load request',
              style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
        ),
        data: (data) {
          final booking = data['booking'] as Map<String, dynamic>;
          final intake  = List<Map<String, dynamic>>.from(data['intake'] as List);
          return Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                children: [
                  // `.pulse` — the strip announces itself when the request's
                  // status moves (accepted / declined).
                  CharakStatusPulse(
                    trigger: booking['status'],
                    child: _PatientStrip(booking: booking),
                  ),
                  const SizedBox(height: 18),
                  if (intake.isNotEmpty) ...[
                    const CharakSectionTitle(label: 'What the patient said'),
                    const SizedBox(height: 9),
                    ...intake.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _IntakeBlock(item: item),
                    )),
                    const SizedBox(height: 6),
                  ],
                  const CharakSectionTitle(label: 'Visit details'),
                  const SizedBox(height: 6),
                  _VisitDetailsCard(booking: booking),
                  const SizedBox(height: 14),
                  CharakButton(
                    label: 'Request clarification call',
                    outlined: true,
                    icon: Icons.phone_outlined,
                    onPressed: () => context.push('/call/${widget.bookingId}'),
                  ),
                ],
              ),
            ),
            if (booking['status'] == 'requested')
              CharakCtaBar(children: [
                Expanded(
                  child: CharakButton(
                    label: 'Decline',
                    outlined: true,
                    onPressed: _deciding ? null : _decline,
                  ),
                ),
                Expanded(
                  child: CharakButton(
                    label: 'Accept',
                    isLoading: _deciding,
                    onPressed: _accept,
                  ),
                ),
              ]),
          ]);
        },
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

/// `.pat-strip` — 13px-padded card: avatar, name/channel stack, and a
/// right-aligned 16px tabular price with the `New` badge beneath it.
class _PatientStrip extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _PatientStrip({required this.booking});

  @override
  Widget build(BuildContext context) {
    final patient = booking['users'] as Map<String, dynamic>? ?? {};
    final name    = patient['name'] as String? ?? 'Unknown patient';
    final channel = booking['channel'] as String? ?? '';
    final price   = (booking['price_confirmed'] as num?)?.toDouble();
    final isNew   = booking['status'] == 'requested';

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: CharakColors.bg,
        borderRadius: const BorderRadius.all(CharakRadius.card),
        border: Border.all(color: CharakColors.border),
      ),
      child: Row(children: [
        CharakAvatar(name: name, radius: 24),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: CharakText.h2.copyWith(fontSize: 15.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 1),
          Text(
            channel == 'home_visit' ? 'Home Visit' : 'Online Consult',
            style: const TextStyle(
              fontFamily: CharakText.fontFamily,
              fontSize: 12.5,
              height: 1.4,
              color: CharakColors.inkMuted,
            ),
          ),
        ])),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (price != null)
            Text.rich(TextSpan(children: [
              TextSpan(
                text: '₹${price.toStringAsFixed(0)}',
                style: CharakText.h2.copyWith(
                  fontSize: 16,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              // `.per`
              const TextSpan(
                text: '/15m',
                style: TextStyle(
                  fontFamily: CharakText.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: CharakColors.inkMuted,
                ),
              ),
            ])),
          // `.fade-swap` — the status label cross-fades out in place when the
          // booking leaves `requested`, rather than vanishing on a rebuild.
          CharakFadeSwap(
            child: isNew
                ? const Padding(
                    key: ValueKey('requested'),
                    padding: EdgeInsets.only(top: 4),
                    child: CharakBadge(label: 'New', variant: CharakBadgeVariant.warning),
                  )
                : SizedBox.shrink(key: ValueKey(booking['status'])),
          ),
        ]),
      ]),
    );
  }
}

/// `.intake-blk` — a bgSubtle block whose `.bhead` pairs a 14px primary icon
/// with a 12px/600 label (and a green `.vtag` for transcribed audio), over
/// 13.5px/1.55 body copy or a bordered `.file-chip`.
class _IntakeBlock extends StatelessWidget {
  final Map<String, dynamic> item;
  const _IntakeBlock({required this.item});

  @override
  Widget build(BuildContext context) {
    final type = item['media_type'] as String? ?? '';
    final text = item['transcript_text'] as String?;
    final url  = item['file_url'] as String?;

    final (icon, label, transcribed) = switch (type) {
      'voice' => (Icons.mic_none_rounded, 'Voice note', true),
      'video' => (Icons.videocam_outlined, 'Video attached', false),
      'image' => (Icons.image_outlined, 'Attachments', false),
      _       => (Icons.short_text_rounded, 'Typed note', false),
    };
    final hasText = text != null && text.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        color: CharakColors.bgSubtle,
        borderRadius: BorderRadius.all(CharakRadius.card),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // `.bhead`
        Row(children: [
          Icon(icon, size: 14, color: CharakColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: CharakText.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: CharakColors.ink,
              ),
            ),
          ),
          // `.vtag`
          if (transcribed && hasText)
            const Text(
              'TRANSCRIBED',
              style: TextStyle(
                fontFamily: CharakText.fontFamily,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1.3,
                letterSpacing: 10 * 0.05,
                color: CharakColors.success,
              ),
            ),
        ]),
        if (hasText) ...[
          const SizedBox(height: 7),
          Text(
            text,
            style: const TextStyle(
              fontFamily: CharakText.fontFamily,
              fontSize: 13.5,
              height: 1.55,
              color: CharakColors.ink,
            ),
          ),
        ],
        if (url != null && url.isNotEmpty) ...[
          const SizedBox(height: 9),
          _FileChip(icon: icon, label: type == 'image' ? '1 photo' : 'Open file'),
        ],
      ]),
    );
  }
}

/// `.file-chip` — white pill-ish chip on a 9px radius with a 14px primary
/// glyph and a 12.5px/500 label.
class _FileChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FileChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: CharakColors.bg,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: CharakColors.border),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: CharakColors.primary),
      const SizedBox(width: 7),
      Text(label, style: CharakText.bodyMed.copyWith(fontSize: 12.5)),
    ]),
  );
}

/// Visit-details card — `.card` with the spec's 6px/14px inset wrapping
/// `.visit-line` rows.
class _VisitDetailsCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _VisitDetailsCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final channel = booking['channel'] as String? ?? '';
    final start   = booking['scheduled_start'] as String? ?? '';
    final dt      = start.isNotEmpty ? DateTime.tryParse(start)?.toLocal() : null;
    final slotStr = dt != null ? DateFormat('EEE d MMM, h:mm a').format(dt) : '—';
    final isHome  = channel == 'home_visit';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: CharakColors.bg,
        borderRadius: const BorderRadius.all(CharakRadius.card),
        border: Border.all(color: CharakColors.border),
      ),
      child: Column(children: [
        CharakVisitLine(icon: Icons.access_time_rounded, value: slotStr),
        CharakVisitLine(
          icon: isHome ? Icons.place_outlined : Icons.videocam_outlined,
          value: isHome ? 'Address shared on accept' : 'Video call',
          trailing: isHome ? null : 'join from active visit',
        ),
      ]),
    );
  }
}
