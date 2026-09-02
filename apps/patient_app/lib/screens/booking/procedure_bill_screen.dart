import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

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
      backgroundColor: CharakColors.bgSubtle,
      appBar: AppBar(
        title: const Text('Procedure Bill'),
        backgroundColor: CharakColors.bg,
        foregroundColor: CharakColors.ink,
        elevation: 0,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (bills) {
          if (bills.isEmpty) {
            return const Center(child: Text('No procedure bill for this visit.'));
          }
          final bill = bills.first;
          return _BillBody(bill: bill, bookingId: bookingId);
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

    return Column(children: [
      Expanded(child: ListView(
        padding: const EdgeInsets.all(CharakSpacing.base),
        children: [
          // Status banner
          _StatusBanner(status: status),
          const SizedBox(height: 16),

          // Items list
          Container(
            decoration: BoxDecoration(
              color: CharakColors.bg,
              borderRadius: const BorderRadius.all(CharakRadius.card),
              border: Border.all(color: CharakColors.border),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Text('Procedure Items', style: CharakText.h2),
                ]),
              ),
              const Divider(height: 1, color: CharakColors.border),
              ...items.map<Widget>((item) {
                final name = item['name'] as String? ?? '';
                final price = (item['price'] as num?)?.toDouble() ?? 0;
                final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Expanded(child: Text(name, style: CharakText.body)),
                    Text('×$qty', style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
                    const SizedBox(width: 8),
                    Text('₹${(price * qty).toStringAsFixed(0)}', style: CharakText.bodyMed),
                  ]),
                );
              }),
              const Divider(height: 1, color: CharakColors.border),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Text('Total', style: CharakText.h2),
                  const Spacer(),
                  Text('₹${total.toStringAsFixed(0)}',
                      style: CharakText.h1.copyWith(color: CharakColors.primary)),
                ]),
              ),
            ]),
          ),

          if (status == 'under_review') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CharakColors.warning.withOpacity(0.1),
                borderRadius: const BorderRadius.all(CharakRadius.card),
                border: Border.all(color: CharakColors.warning.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.hourglass_top, color: CharakColors.warning, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This bill is under senior review. You will be notified once approved.',
                    style: CharakText.caption.copyWith(color: CharakColors.warning),
                  ),
                ),
              ]),
            ),
          ],
        ],
      )),

      if (status == 'approved')
        Padding(
          padding: const EdgeInsets.fromLTRB(CharakSpacing.base, 0, CharakSpacing.base, 24),
          child: CharakButton(
            label: 'Pay ₹${total.toStringAsFixed(0)}',
            onPressed: () => context.go('/booking/$bookingId/pay'),
          ),
        ),
    ]);
  }
}

class _StatusBanner extends StatelessWidget {
  final String status;
  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String label;
    switch (status) {
      case 'approved':
        color = CharakColors.success; icon = Icons.check_circle_outline; label = 'Approved — Payment due';
      case 'paid':
        color = CharakColors.primary; icon = Icons.payments_outlined; label = 'Paid';
      case 'under_review':
        color = CharakColors.warning; icon = Icons.hourglass_top; label = 'Under Senior Review';
      default:
        color = CharakColors.inkMuted; icon = Icons.receipt_outlined; label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: const BorderRadius.all(CharakRadius.card),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(label, style: CharakText.bodyMed.copyWith(color: color)),
      ]),
    );
  }
}
