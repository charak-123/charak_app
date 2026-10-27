import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

/// Every payment and its refunds (backend GET /me/payments), newest first.
final paymentsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.instance.get('/me/payments') as List;
  return res.cast<Map<String, dynamic>>();
});

/// Profile → Payments: what was paid, and where each refund stands as Razorpay
/// has confirmed it ("Refund processing" until it says otherwise).
class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(paymentsProvider);
    return CharakScreen(
      title: 'Payments',
      body: async.when(
        loading: () => const SingleChildScrollView(child: CharakSkeletonList()),
        error: (e, _) => CharakErrorState(error: e, onRetry: () => ref.invalidate(paymentsProvider)),
        data: (items) => items.isEmpty
            ? const Center(
                child: CharakEmptyState(
                  icon: LucideIcons.receiptText,
                  title: 'No payments yet',
                  message: 'When you pay for a consultation, the payment and any refund show here.',
                ),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(paymentsProvider.future),
                color: CharakColors.primary,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 4, CharakSpacing.gutter, 32),
                  children: [
                    CharakGroupedList(children: [
                      for (var i = 0; i < items.length; i++)
                        _PaymentRow(p: items[i], last: i == items.length - 1),
                    ]),
                    const SizedBox(height: 12),
                    Text(
                      'Refunds go back to the method you paid with. Banks usually take '
                      '5–7 working days after a refund is processed.',
                      style: charakHintStyle,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final Map<String, dynamic> p;
  final bool last;
  const _PaymentRow({required this.p, required this.last});

  @override
  Widget build(BuildContext context) {
    final booking = p['bookings'] as Map<String, dynamic>? ?? const {};
    final doctor = CharakFormat.doctor((booking['doctors'] as Map?)?['name'] as String?);
    final amount = (p['amount'] as num?)?.toDouble() ?? 0;
    final paidAt = DateTime.tryParse(p['paid_at'] as String? ?? p['created_at'] as String? ?? '')
        ?.toLocal();
    final refund = CharakRefundSummary.fromPayments([p]);
    final what = p['type'] == 'procedure_bill' ? 'Procedure bill' : CharakFormat.channel(booking['channel'] as String?);

    final lines = <String>[
      what,
      if (paidAt != null) DateFormat('d MMM y').format(paidAt),
      if (refund != null && refund.rupees < amount)
        '${CharakFormat.rupees(refund.rupees)} of ${CharakFormat.rupees(amount)} refunded',
    ];

    return CharakListRow(
      title: '$doctor · ${CharakFormat.rupees(amount)}',
      subtitle: lines.join(' · '),
      trailing: refund != null
          ? CharakStatusPill.forRefund(refund.state)
          : const CharakStatusPill(label: 'Paid', tone: CharakStatusTone.confirmed),
      showChevron: booking['id'] != null,
      last: last,
      onTap: booking['id'] == null
          ? null
          : () => context.push('/booking/${booking['id']}/history-detail'),
    );
  }
}
