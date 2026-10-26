import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

final _bookingProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ApiClient.instance.get('/bookings/$id');
  return res as Map<String, dynamic>;
});

/// Refunds on a cancelled booking, as Razorpay has confirmed them. Only read
/// once the booking is cancelled; a live booking has nothing to refund.
final _refundProvider =
    FutureProvider.autoDispose.family<CharakRefundSummary?, String>((ref, id) async {
  final payments = await ApiClient.instance.get('/payments/$id') as List;
  return CharakRefundSummary.fromPayments(payments);
});

// Statuses still waiting on someone else to act — a doctor's decision, a
// payment hold expiring. Anything else (paid, completed, declined,
// cancelled) is the end of the line for this screen and needs no more polls.
const _liveStatuses = {'requested', 'accepted'};

class BookingStatusScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const BookingStatusScreen({super.key, required this.bookingId});

  @override
  ConsumerState<BookingStatusScreen> createState() => _BookingStatusScreenState();
}

class _BookingStatusScreenState extends ConsumerState<BookingStatusScreen> {
  CharakPoller? _poll;

  @override
  void initState() {
    super.initState();
    // The push for a doctor's decision is the real signal; this is the same
    // backstop request_sent_screen.dart already uses — a patient who
    // navigates here directly (history, a restored app) rather than straight
    // from sending the request gets the same live update, not just whoever
    // was on the other screen when it happened.
    _poll = CharakPoller(onPoll: _refresh)..start();
  }

  Future<bool> _refresh() async {
    if (!mounted) return true;
    ref.invalidate(_bookingProvider(widget.bookingId));
    final booking = await ref.read(_bookingProvider(widget.bookingId).future);
    final status = booking['status'] as String? ?? 'requested';
    return !_liveStatuses.contains(status);
  }

  @override
  void dispose() {
    _poll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_bookingProvider(widget.bookingId));
    return CharakScreen(
      body: async.when(
        loading: () => const _StatusLoading(),
        error: (e, _) => CharakErrorState(
            error: e, onRetry: () => ref.invalidate(_bookingProvider(widget.bookingId))),
        data: (booking) => _StatusBody(booking: booking, bookingId: widget.bookingId),
      ),
    );
  }
}

/// The wireframe's `accepted` and `declined` screens, plus the remaining
/// lifecycle states, all rendered through `.ok-state` + `.bsum`.
class _StatusBody extends ConsumerWidget {
  final Map<String, dynamic> booking;
  final String bookingId;
  const _StatusBody({required this.booking, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status  = booking['status'] as String? ?? 'requested';
    // A failed lookup just hides the refund row; the cancel itself happened.
    final refund = status == 'cancelled'
        ? ref.watch(_refundProvider(bookingId)).valueOrNull
        : null;
    final channel = booking['channel'] as String? ?? '';
    final docName = (booking['doctors'] as Map?)?['name'] as String?;
    final start   = booking['scheduled_start'] as String?;

    final pricing = List<Map<String, dynamic>>.from(
        (booking['doctors'] as Map?)?['doctor_pricing'] as List? ?? []);
    final priceRow = pricing.where((p) => p['channel'] == channel).firstOrNull;
    final price = (booking['price_confirmed'] as num?)?.toDouble() ??
        (priceRow?['price'] as num?)?.toDouble();

    String when = '';
    if (start != null) {
      final dt = DateTime.tryParse(start);
      if (dt != null) when = DateFormat('EEE, d MMM, h:mm a').format(dt.toLocal());
    }
    final channelLabel = CharakFormat.channel(channel);
    final doctor = CharakFormat.doctor(docName);

    final (tone, icon, title, message) = switch (status) {
      'accepted' => (
        CharakOutcomeTone.success,
        null,
        'Booking accepted!',
        '$doctor accepted your request. Pay to confirm the slot — the price '
            'stays exactly as shown.',
      ),
      'declined' => (
        CharakOutcomeTone.neutral,
        LucideIcons.info,
        'Request declined',
        "$doctor couldn't take this request — it happens for all sorts of "
            'reasons, none of them about you. Plenty of other doctors are '
            'available.',
      ),
      'paid' => (
        CharakOutcomeTone.success,
        null,
        'Booking confirmed',
        "You're set with $doctor${when.isNotEmpty ? ' on $when' : ''} "
            '($channelLabel).',
      ),
      'completed' => (
        CharakOutcomeTone.success,
        null,
        'Visit complete',
        'This visit is done. A quick rating helps other patients choose well.',
      ),
      'cancelled' => (
        CharakOutcomeTone.neutral,
        LucideIcons.circleMinus,
        'Booking cancelled',
        refund != null
            ? 'This booking was cancelled. ${refund.message}'
            : 'This booking was cancelled. You can book another slot any time.',
      ),
      'no_show' => (
        CharakOutcomeTone.neutral,
        LucideIcons.circleMinus,
        'Marked as a no-show',
        '$doctor marked this booking as a no-show. You have not been charged.',
      ),
      _ => (
        CharakOutcomeTone.waiting,
        LucideIcons.hourglass,
        'Awaiting response',
        "$doctor is reviewing your request. You'll be notified the moment "
            'they decide.',
      ),
    };

    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 34, 20, 24),
          // `.pulse` — the whole status block flashes when the booking moves
          // to a new state (requested → accepted → paid).
          child: CharakStatusPulse(
            trigger: status,
            child: CharakOutcomeState(
              tone: tone,
              icon: icon,
              title: title,
              message: message,
              child: Column(children: [
                CharakSummaryCard(rows: [
                  if (docName != null && status == 'accepted')
                    CharakSummaryRow(label: 'Doctor', value: doctor),
                  if (when.isNotEmpty) CharakSummaryRow(label: 'When', value: when),
                  CharakSummaryRow(label: 'Channel', value: channelLabel),
                  const CharakSummaryDivider(),
                  if (price != null)
                    CharakSummaryRow(
                      label: status == 'accepted' ? 'To pay' : 'Amount',
                      value: CharakFormat.rupees(price),
                      tabular: true,
                    ),
                  CharakSummaryRow(
                    label: 'Status',
                    // `.fade-swap` — the pill swaps its label in place.
                    child: CharakFadeSwap(
                      child: CharakStatusPill.forStatus(status, key: ValueKey(status)),
                    ),
                  ),
                  if (refund != null) ...[
                    CharakSummaryRow(
                      label: 'Refund',
                      value: CharakFormat.rupees(refund.rupees),
                      tabular: true,
                    ),
                    CharakSummaryRow(
                      label: 'Refund status',
                      child: CharakStatusPill.forRefund(refund.state),
                    ),
                  ],
                ]),
                if (status == 'accepted') ...[
                  const SizedBox(height: 10),
                  Text('Payment via UPI or card · Razorpay secure checkout',
                      style: charakHintStyle, textAlign: TextAlign.center),
                ],
              ]),
            ),
          ),
        ),
      ),

      CharakCtaBar(children: [
        if (status == 'accepted')
          Expanded(
            child: CharakButton(
              label: price != null ? 'Pay ${CharakFormat.rupees(price)} now' : 'Pay now',
              onPressed: () => context.go('/booking/$bookingId/pay'),
            ),
          )
        else if (status == 'declined')
          Expanded(
            child: CharakButton(
              label: 'Find another doctor',
              onPressed: () => context.go('/directory'),
            ),
          )
        else if (status == 'paid')
          Expanded(
            child: CharakButton(
              label: 'View booking',
              onPressed: () => context.go('/booking/$bookingId/active'),
            ),
          )
        else if (status == 'completed') ...[
          Expanded(
            child: CharakButton(
              label: 'Rate your visit',
              onPressed: () => context.push('/booking/$bookingId/rate'),
            ),
          ),
        ] else
          Expanded(
            child: CharakButton(
              label: 'Go to Home',
              outlined: true,
              onPressed: () => context.go('/home'),
            ),
          ),
      ]),
    ]);
  }
}

/// Loading state: `.skel` blocks in the shape of `.ok-state` — the centred
/// icon medallion, title and message lines, then the `.bsum` summary card.
class _StatusLoading extends StatelessWidget {
  const _StatusLoading();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(20, 34, 20, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: CharakSkeleton(width: 84, height: 84, radius: 42)),
        SizedBox(height: 16),
        Center(child: CharakSkeleton(width: 196, height: 21)),
        SizedBox(height: 12),
        CharakSkeleton(height: 14),
        SizedBox(height: 7),
        CharakSkeleton(height: 14),
        SizedBox(height: 22),
        CharakSkeleton(height: 148, radius: 14),
      ],
    ),
  );
}
