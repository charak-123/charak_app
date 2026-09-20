import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

final _billProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, id) async {
  final res = await ApiClient.instance.get('/bookings/$id/procedure-bill');
  if (res == null) return [];
  return [res as Map<String, dynamic>];
});

class ProcedureBillScreen extends ConsumerWidget {
  final String bookingId;
  const ProcedureBillScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_billProvider(bookingId));
    return Scaffold(
      backgroundColor: CharakColors.bg,
      appBar: const CharakTopBar(title: 'Visit complete'),
      body: async.when(
        loading: () => const _BillLoading(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (bills) {
          if (bills.isEmpty) {
            return const CharakEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No procedure bill',
              message: 'Nothing was billed beyond the consult fee for this visit.',
            );
          }
          return _BillBody(bill: bills.first, bookingId: bookingId);
        },
      ),
    );
  }
}

class _BillBody extends StatelessWidget {
  final Map<String, dynamic> bill;
  final String bookingId;
  const _BillBody({required this.bill, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    final status = bill['status'] as String? ?? 'pending';
    final total = (bill['total'] as num?)?.toDouble() ?? 0;
    final items = (bill['items'] as List?) ?? [];
    final underReview = status == 'under_review' || status == 'pending';
    final paid = status == 'paid';

    return Column(children: [
      Expanded(child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          // `.ok-state` header, tightened to the screen's 16px top inset.
          const CharakOutcomeState(
            tone: CharakOutcomeTone.neutral,
            icon: Icons.receipt_long_outlined,
            title: 'Procedures from your visit',
            message: 'These were done during your home visit, charged at the '
                'fixed rates on the doctor\'s profile.',
          ),
          const SizedBox(height: 22),

          // `.card.rev-sum` — one row per procedure, then the total.
          CharakSummaryCard(rows: [
            ...items.map<Widget>((item) {
              final name = item['name'] as String? ?? '';
              final price = (item['price'] as num?)?.toDouble() ?? 0;
              final qty = (item['quantity'] as num?)?.toInt() ?? 1;
              return CharakSummaryRow(
                label: qty > 1 ? '$name ×$qty' : name,
                value: '₹${(price * qty).toStringAsFixed(0)}',
                tabular: true,
              );
            }),
            const CharakSummaryDivider(),
            CharakSummaryRow(
              label: 'Procedures total',
              value: '₹${total.toStringAsFixed(0)}',
              tabular: true,
            ),
          ]),
          const SizedBox(height: 12),

          if (underReview) ...[
            const CharakNoteBanner(
              icon: Icons.gpp_maybe_outlined,
              leadLabel: 'Under senior review',
              message: '— larger procedure bills are checked by a senior '
                  "doctor to make sure everything was necessary. You'll be "
                  'asked to pay once approved.',
            ),
            const SizedBox(height: 10),
            const Text("We'll notify you the moment the review finishes.",
                style: charakHintStyle, textAlign: TextAlign.center),
          ] else
            CharakInfoStrip(
              icon: Icons.verified_user_outlined,
              tone: CharakStatusTone.success,
              label: paid
                  ? 'Bill settled — thanks!'
                  : 'Reviewed & approved by a senior doctor — pay to finish',
            ),
        ],
      )),

      CharakCtaBar.single(
        underReview
            ? const CharakButton(label: 'Awaiting senior review')
            : paid
                ? CharakButton(
                    label: 'Done',
                    outlined: true,
                    onPressed: () => context.go('/home'),
                  )
                : CharakButton(
                    label: 'Pay ₹${total.toStringAsFixed(0)}',
                    onPressed: () => context.go('/booking/$bookingId/pay'),
                  ),
      ),
    ]);
  }
}

/// Loading state: `.skel` blocks in the shape of the bill — the heading, the
/// itemised rows and the total line.
class _BillLoading extends StatelessWidget {
  const _BillLoading();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(20, 20, 20, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CharakSkeleton(width: 168, height: 20),
        SizedBox(height: 8),
        CharakSkeleton(width: 240, height: 14),
        SizedBox(height: 20),
        CharakSkeleton(height: 172, radius: 14),
        SizedBox(height: 16),
        CharakSkeleton(height: 56, radius: 14),
      ],
    ),
  );
}
