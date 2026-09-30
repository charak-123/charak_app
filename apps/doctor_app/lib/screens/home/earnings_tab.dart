import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _earningsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ApiClient.instance.get('/earnings/me');
  return res as Map<String, dynamic>;
});

// ── EarningsTab ───────────────────────────────────────────────────────────────

class EarningsTab extends ConsumerWidget {
  const EarningsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_earningsProvider);
    return CharakLargeTitleScaffold(
      title: 'Earnings',
      // /earnings/me has no date filter — it returns every completed booking
      // ever, so labelling this with the current month stated something the
      // number never meant.
      subtitle: 'All time',
      onRefresh: () => ref.refresh(_earningsProvider.future),
      children: async.when(
        loading: () => const [
          CharakSkeleton(height: 132, radius: CharakRadii.card),
          SizedBox(height: 24),
          CharakSkeletonList(count: 3, avatar: false, padding: EdgeInsets.zero),
        ],
        error: (e, _) => [
          const CharakEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Couldn\'t load earnings',
            message: 'Pull down to try again.',
          ),
        ],
        data: (data) {
          final items         = List<Map<String, dynamic>>.from(data['items'] as List);
          final pendingReview = (data['pending_review_total'] as num?)?.toDouble() ?? 0;
          // /earnings/me also reports bills that are approved but not yet paid
          // by the patient — real money the doctor is owed, but not yet earned.
          final awaitingPay   = (data['awaiting_payment_total'] as num?)?.toDouble() ?? 0;
          final grandTotal    = (data['grand_total'] as num?)?.toDouble() ?? 0;
          return [
            _EarnTotal(
              label: 'Total received',
              amount: grandTotal,
              visits: items.length,
            ),
            if (awaitingPay > 0) ...[
              CharakNoteBanner(
                icon: Icons.schedule_outlined,
                tone: CharakStatusTone.primary,
                leadLabel: '₹${awaitingPay.toStringAsFixed(0)} approved, awaiting payment',
                message: '— counts as earnings once the patient pays.',
              ),
              const SizedBox(height: 16),
            ],
            if (pendingReview > 0) ...[
              CharakNoteBanner(
                icon: Icons.shield_outlined,
                tone: CharakStatusTone.review,
                leadLabel: '₹${pendingReview.toStringAsFixed(0)} awaiting senior review',
                message: '— patients can pay once a senior doctor approves the bill.',
              ),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 8),
            if (items.isEmpty)
              const CharakEmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'No completed visits yet',
                message: 'Fees from completed visits show up here.',
              )
            else
              CharakGroupedList(
                label: 'Completed bookings',
                children: [
                  for (var k = 0; k < items.length; k++)
                    _EarnRow(item: items[k], last: k == items.length - 1),
                ],
              ),
            const SizedBox(height: 16),
            const CharakHintLine(
              text: 'Full dashboard — charts, payout history, filters — is planned for a later release.',
            ),
          ];
        },
      ),
    );
  }
}

/// Month total as the blue hero card: overline, then the figure in narrow
/// tabular numerals (numbers never animate their value).
class _EarnTotal extends StatelessWidget {
  final String label;
  final double amount;
  final int visits;
  const _EarnTotal({required this.label, required this.amount, required this.visits});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: CharakCard(
      tone: CharakCardTone.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: CharakText.overline.copyWith(color: CharakPalette.blue100)),
          const SizedBox(height: 8),
          Text(
            '₹${NumberFormat.decimalPattern('en_IN').format(amount.round())}',
            style: CharakText.numeric.copyWith(fontSize: 48, height: 1.05, color: CharakColors.onPrimary).weight(700),
          ),
          const SizedBox(height: 4),
          Text('$visits completed visit${visits == 1 ? '' : 's'}',
              style: CharakText.caption.copyWith(color: CharakPalette.blue100)),
        ],
      ),
    ),
  );
}

/// One completed booking: date, patient, channel (+ procedures), then the
/// amount in tabular figures. Sits inside the grouped list.
class _EarnRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool last;
  const _EarnRow({required this.item, required this.last});

  @override
  Widget build(BuildContext context) {
    final name      = item['patient_name'] as String? ?? 'Patient';
    final channel   = item['channel'] as String? ?? '';
    final start     = item['scheduled_start'] as String? ?? '';
    final dt        = start.isNotEmpty ? DateTime.tryParse(start)?.toLocal() : null;
    final when      = dt != null ? DateFormat('d MMM').format(dt) : '—';
    final consult   = (item['consult_fee'] as num?)?.toDouble() ?? 0;
    final bill      = item['procedure_bill'] as Map<String, dynamic>?;
    final billTotal = bill != null ? (bill['total'] as num?)?.toDouble() ?? 0 : 0.0;
    final billState = bill?['status'] as String?;

    final channelLabel = channel == 'home_visit' ? 'Home visit' : 'Online';
    final subtitle = billTotal > 0
        ? '$when · $channelLabel · procedures ₹${billTotal.toStringAsFixed(0)}'
        : '$when · $channelLabel';

    return CharakListRow(
      title: name,
      subtitle: subtitle,
      showChevron: false,
      last: last,
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('₹${(consult + billTotal).toStringAsFixed(0)}',
            style: CharakText.numeric.copyWith(fontSize: 18, color: CharakColors.ink)),
        if (billState == 'under_review') ...[
          const SizedBox(height: 4),
          const CharakStatusPill(label: 'Needs review', tone: CharakStatusTone.review),
        ],
      ]),
    );
  }
}
