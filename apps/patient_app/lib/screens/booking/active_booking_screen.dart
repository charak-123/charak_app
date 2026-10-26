import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

/// The booking, plus (once the doctor has sent one) the id and timestamps of
/// the prescription. Its content is fetched only when the patient opens it,
/// because opening it is what completes the visit.
final _activeBookingProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ApiClient.instance.get('/bookings/$id') as Map<String, dynamic>;
  if (res['prescription_sent_at'] != null) {
    final rx = await ApiClient.instance.get('/bookings/$id/prescription') as Map<String, dynamic>;
    res['prescription'] = rx['prescription'];
  }
  return res;
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

  /// Fetch what cancelling now would refund, say exactly that, and cancel
  /// against that amount. If the outcome moved in between (the doctor just
  /// started travelling), the server refuses with the new quote and the
  /// patient sees it before anything is cancelled.
  Future<void> _cancel(BuildContext context) async {
    Map<String, dynamic> quote;
    try {
      quote = await ApiClient.instance.get('/bookings/$bookingId/cancellation-quote')
          as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (context.mounted) showCharakToast(context, message: e.message, isError: true);
      return;
    }
    if (context.mounted) await _confirmAndCancel(context, quote);
  }

  Future<void> _confirmAndCancel(BuildContext context, Map<String, dynamic> quote,
      {bool changed = false}) async {
    final ok = await showCharakConfirm(
      context,
      title: changed ? 'The refund has changed' : 'Cancel this booking?',
      message: cancellationMessage(quote),
      confirmLabel: 'Cancel booking',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ApiClient.instance.patch('/bookings/$bookingId/cancel', {
        'expected_refund_paise': (quote['refund_paise'] as num?)?.toInt() ?? 0,
      });
      if (context.mounted) context.go('/booking/$bookingId/status');
    } on ApiException catch (e) {
      if (!context.mounted) return;
      final fresh = e.body?['quote'];
      if (e.statusCode == 409 && fresh is Map<String, dynamic>) {
        await _confirmAndCancel(context, fresh, changed: true);
      } else {
        showCharakToast(context, message: e.message, isError: true);
      }
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

    final canJoin = (status == 'paid' || status == 'in_progress') && isOnline;
    final cancellable = status == 'requested' || status == 'accepted' || status == 'paid';
    final journeyAt = DateTime.tryParse(booking['journey_started_at'] as String? ?? '')?.toLocal();
    final rx = booking['prescription'] as Map<String, dynamic>?;
    void openRx() => context.push('/prescription/${rx!['id']}');

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
            else if (journeyAt != null && status == 'paid')
              // No arrival time is promised: there's no live ETA (spec §7.2).
              CharakInfoStrip(
                icon: LucideIcons.navigation,
                label: 'Your doctor is on the way',
                value: 'Left ${DateFormat('h:mm a').format(journeyAt)}',
                tone: CharakStatusTone.active,
                tabularValue: true,
              )
            else
              CharakInfoStrip(
                label: 'Visit time',
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

          if (status == 'in_progress') ...[
            const SizedBox(height: 12),
            const CharakNoteBanner(
              icon: LucideIcons.stethoscope,
              tone: CharakStatusTone.active,
              message: 'Your consultation is under way. Your doctor sends the prescription here when it ends.',
            ),
          ],

          if (rx != null) ...[
            const SizedBox(height: 12),
            CharakCard(
              tone: status == 'consulted' ? CharakCardTone.tint : CharakCardTone.plain,
              onTap: openRx,
              child: Row(children: [
                Icon(LucideIcons.fileText, size: 22, color: CharakColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(rx['kind'] == 'notes' ? 'Consultation notes' : 'Prescription',
                        style: CharakText.body.weight(600).copyWith(color: CharakColors.ink)),
                    Text(
                      rx['first_viewed_at'] == null
                          ? 'Ready. Open it to complete your visit'
                          : 'From ${docName.replaceFirst('Dr. ', 'Dr ')}',
                      style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                    ),
                  ]),
                ),
                Icon(LucideIcons.chevronRight, size: 18, color: CharakColors.inkMuted),
              ]),
            ),
          ],

          if (status == 'completed') ...[
            const SizedBox(height: 12),
            const CharakNoteBanner(
              icon: LucideIcons.circleCheck,
              tone: CharakStatusTone.success,
              message: 'Visit completed. Your receipt is in History.',
            ),
          ],

          if (cancellable && freeUntilLine(booking) != null) ...[
            const SizedBox(height: 14),
            Text(freeUntilLine(booking)!, style: charakHintStyle, textAlign: TextAlign.center),
          ],
        ],
      )),

      // ── `.cta-bar` ─────────────────────────────────────────────────
      if (status == 'consulted' && rx != null)
        CharakCtaBar.single(CharakButton(
          label: 'Open prescription',
          icon: LucideIcons.fileText,
          onPressed: openRx,
        ))
      else if (status == 'completed' || cancellable)
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
              onPressed: () => _cancel(context),
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


/// The confirm-sheet sentence for a cancellation quote (backend
/// GET /bookings/{id}/cancellation-quote). Says exactly what comes back.
String cancellationMessage(Map<String, dynamic> quote) {
  final paid = (quote['paid_paise'] as num?)?.toInt() ?? 0;
  final refund = (quote['refund_paise'] as num?)?.toInt() ?? 0;
  final pct = (quote['refund_pct'] as num?)?.toInt() ?? 100;
  String rupees(int paise) => CharakFormat.rupees(paise / 100);
  const lead = 'The doctor is told straight away.';
  const timing = 'Refunds go back to your original payment method; banks usually take '
      '5–7 working days.';

  if (paid <= 0) return '$lead You have not been charged.';
  if (pct >= 100) return '$lead Your full payment of ${rupees(paid)} is refunded. $timing';
  if (quote['reason'] == 'journey_started') {
    return 'Your doctor has already started travelling to you, so under the '
        'cancellation policy the ${rupees(paid)} fee isn\'t refunded.';
  }
  if (refund <= 0) {
    return 'Under the cancellation policy, cancelling now refunds nothing of the '
        '${rupees(paid)} you paid.';
  }
  return 'It\'s close to your appointment, so under the cancellation policy you get '
      '${rupees(refund)} back ($pct%). The rest goes to the doctor. $timing';
}

/// "Free cancellation until Today, 4:00 PM", from the booking's own policy
/// version. Null when the policy has no cut-off or it has passed.
String? freeUntilLine(Map<String, dynamic> booking, {DateTime? now}) {
  final policy = booking['cancellation_policy'] as Map<String, dynamic>?;
  final minutes = (policy?['free_cancellation_minutes'] as num?)?.toInt();
  final start = DateTime.tryParse(booking['scheduled_start'] as String? ?? '');
  if (policy == null || start == null) return null;
  if (minutes == null) return 'Free cancellation until the appointment starts.';
  final until = start.subtract(Duration(minutes: minutes));
  if (until.isBefore(now ?? DateTime.now())) return null;
  return 'Free cancellation until ${CharakFormat.dayTime(until)}.';
}
