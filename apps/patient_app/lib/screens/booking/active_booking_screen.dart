import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

final _activeBookingProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ApiClient.instance.get('/bookings/$id');
  return res as Map<String, dynamic>;
});

class ActiveBookingScreen extends ConsumerWidget {
  final String bookingId;
  const ActiveBookingScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_activeBookingProvider(bookingId));
    // The card below names the doctor; the title says what this visit is.
    final channel = async.maybeWhen(data: (b) => b['channel'] as String?, orElse: () => null);
    return CharakScreen(
      title: channel != null ? CharakFormat.channel(channel) : 'Your booking',
      body: async.when(
        loading: () => const SingleChildScrollView(child: CharakSkeletonDetail()),
        error: (e, _) => CharakErrorState(error: e, onRetry: () => ref.invalidate(_activeBookingProvider(bookingId))),
        data: (booking) => _Body(booking: booking, bookingId: bookingId),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Map<String, dynamic> booking;
  final String bookingId;
  const _Body({required this.booking, required this.bookingId});

  Future<void> _cancel(BuildContext context, bool paid) async {
    final ok = await showCharakConfirm(
      context,
      title: 'Cancel this booking?',
      message: paid
          ? 'The doctor is told straight away. Your full payment is refunded to your '
              'original payment method — banks usually take 5–7 working days.'
          : 'The doctor is told straight away. You have not been charged.',
      confirmLabel: 'Cancel booking',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ApiClient.instance.patch('/bookings/$bookingId/cancel', {});
      if (context.mounted) context.go('/booking/$bookingId/status');
    } on ApiException catch (e) {
      if (context.mounted) showCharakToast(context, message: e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status  = booking['status'] as String? ?? '';
    final channel = booking['channel'] as String? ?? '';
    final doc     = booking['doctors'] as Map<String, dynamic>? ?? {};
    final docName = CharakFormat.doctor(doc['name'] as String?);
    final start   = booking['scheduled_start'] as String?;
    final address = booking['patient_address'] as String?;
    final price   = (booking['price_confirmed'] as num?)?.toDouble();

    final isOnline = channel != 'home_visit';
    final channelLabel = CharakFormat.channel(isOnline ? 'online_consult' : 'home_visit');

    final startDt = start != null ? DateTime.tryParse(start)?.toLocal() : null;
    final when = startDt != null
        ? DateFormat('EEE d MMM, h:mm a').format(startDt)
        : '';

    // `.act-timer`: a live countdown in the last hour, otherwise the day and
    // time ("Today, 7:00 PM") — an 18-hour stopwatch helps nobody.
    final remaining = startDt?.difference(DateTime.now());
    String two(int n) => n.toString().padLeft(2, '0');
    final countdown = (remaining != null && !remaining.isNegative && remaining.inMinutes < 60)
        ? '${two(remaining.inMinutes)}:${two(remaining.inSeconds % 60)}'
        : null;

    final canJoin = status == 'paid' && isOnline;

    return Column(children: [
      Expanded(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        children: [
          // ── `.act-card` — doctor + timer ─────────────────────────────
          _ActCard(child: Column(children: [
            Row(children: [
              CharakAvatar(name: docName, radius: 24),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(CharakFormat.doctor(docName), style: CharakText.h2.copyWith(fontSize: 16)),
                const SizedBox(height: 1),
                Text(when.isNotEmpty ? '$channelLabel · $when' : channelLabel,
                    style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
                // Under the name rather than beside it: on a 360dp phone a
                // pill on the right squeezes the name and time into 5 lines.
                const SizedBox(height: 6),
                CharakStatusPill.forStatus(status),
              ])),
            ]),
            const SizedBox(height: 14),
            if (isOnline)
              CharakInfoStrip(
                label: countdown != null ? 'Consult starts in' : 'Consult',
                value: countdown ?? (startDt != null ? CharakFormat.dayTime(startDt) : '—'),
                tabularValue: countdown != null,
              )
            else
              CharakInfoStrip(
                label: 'Doctor arrives',
                value: startDt != null ? CharakFormat.dayTime(startDt) : '—',
              ),
          ])),
          const SizedBox(height: 12),

          // ── `.act-card` — detail rows ────────────────────────────────
          _ActCard(child: Column(children: [
            if (isOnline) ...[
              const _ActRow(
                  icon: LucideIcons.video,
                  label: 'Video call',
                  value: 'Join from this screen',
                  muted: true),
              _ActRow(
                icon: LucideIcons.receiptText,
                label: status == 'paid' ? 'Paid' : 'Fee',
                value: price != null ? CharakFormat.rupees(price) : '—',
                tabular: true,
                last: true,
              ),
            ] else ...[
              _ActRow(
                  icon: LucideIcons.mapPin,
                  label: 'Address',
                  value: (address != null && address.isNotEmpty) ? address : '—'),
              _ActRow(
                icon: LucideIcons.receiptText,
                label: status == 'paid' ? 'Paid' : 'Fee',
                value: price != null ? CharakFormat.rupees(price) : '—',
                tabular: true,
                last: true,
              ),
            ],
          ])),

          if (canJoin) ...[
            const SizedBox(height: 6),
            CharakButton(
              label: 'Join call',
              icon: LucideIcons.video,
              onPressed: () => context.push('/booking/$bookingId/call'),
            ),
            const SizedBox(height: 10),
            Text('Join opens 5 minutes before the slot.',
                style: charakHintStyle, textAlign: TextAlign.center),
          ],

          if (status == 'completed') ...[
            const SizedBox(height: 12),
            const CharakNoteBanner(
              icon: LucideIcons.circleCheck,
              tone: CharakStatusTone.success,
              message: 'Visit completed. Your receipt is in History.',
            ),
          ],
        ],
      )),

      // ── `.cta-bar` ─────────────────────────────────────────────────
      CharakCtaBar(children: [
        if (status == 'completed') ...[
          Expanded(
            child: CharakButton(
              label: 'View bill',
              outlined: true,
              onPressed: () => context.push('/booking/$bookingId/bill'),
            ),
          ),
          Expanded(
            child: CharakButton(
              label: 'Rate your visit',
              onPressed: () => context.push('/booking/$bookingId/rate'),
            ),
          ),
        ] else ...[
          Expanded(
            child: CharakButton(
              label: 'Cancel booking',
              variant: CharakButtonVariant.danger,
              onPressed: () => _cancel(context, status == 'paid'),
            ),
          ),
        ],
      ]),
    ]);
  }
}

/// `.act-card` — plain 16px-padded bordered card.
class _ActCard extends StatelessWidget {
  final Widget child;
  const _ActCard({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(CharakSpacing.base),
    decoration: BoxDecoration(
      color: CharakColors.bg,
      borderRadius: const BorderRadius.all(CharakRadius.card),
    ),
    child: child,
  );
}

/// `.act-row` — 17px primary glyph, 14px label, value pushed right; the last
/// row drops its rule (`.act-row:last-child { border-bottom: 0 }`).
class _ActRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool muted;
  final bool tabular;
  final bool last;

  const _ActRow({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
    this.tabular = false,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: BoxDecoration(
      border: last ? null : Border(bottom: BorderSide(color: CharakColors.border)),
    ),
    child: Row(children: [
      Icon(icon, size: 17, color: CharakColors.primary),
      const SizedBox(width: 10),
      Text(label,
          style: CharakText.body.copyWith(fontSize: 14, color: CharakColors.ink)),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: CharakText.body.tabular.copyWith(color: muted ? CharakColors.inkMuted : CharakColors.ink, fontWeight: muted ? FontWeight.w400 : FontWeight.w500, fontSize: 15),
        ),
      ),
    ]),
  );
}
