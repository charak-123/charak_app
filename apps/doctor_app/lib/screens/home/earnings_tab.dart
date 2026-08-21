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
    return Scaffold(
      backgroundColor: CharakColors.bgSubtle,
      appBar: AppBar(
        title: const Text('Earnings'),
        backgroundColor: CharakColors.bg,
        foregroundColor: CharakColors.ink,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_earningsProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          final items          = List<Map<String, dynamic>>.from(data['items'] as List);
          final consultTotal   = (data['consult_total']   as num?)?.toDouble() ?? 0;
          final procedureTotal = (data['procedure_total'] as num?)?.toDouble() ?? 0;
          final pendingReview  = (data['pending_review_total'] as num?)?.toDouble() ?? 0;
          final grandTotal     = (data['grand_total']     as num?)?.toDouble() ?? 0;

          return ListView(
            padding: const EdgeInsets.all(CharakSpacing.base),
            children: [
              _SummaryCard(
                grandTotal: grandTotal,
                consultTotal: consultTotal,
                procedureTotal: procedureTotal,
                pendingReview: pendingReview,
              ),
              if (pendingReview > 0) ...[
                const SizedBox(height: 12),
                _SeniorReviewCard(amount: pendingReview),
              ],
              const SizedBox(height: 16),
              Text('Completed Visits', style: CharakText.h2),
              const SizedBox(height: 8),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Center(
                    child: Text('No completed visits yet',
                        style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
                  ),
                )
              else
                ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _EarningsItem(item: item),
                )),
            ],
          );
        },
      ),
    );
  }
}

// ── Summary card ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final double grandTotal;
  final double consultTotal;
  final double procedureTotal;
  final double pendingReview;
  const _SummaryCard({
    required this.grandTotal,
    required this.consultTotal,
    required this.procedureTotal,
    required this.pendingReview,
  });

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: CharakColors.primary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(CharakRadius.card),
    ),
    child: Padding(
      padding: const EdgeInsets.all(CharakSpacing.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Total Earned', style: CharakText.caption.copyWith(color: Colors.white70)),
        const SizedBox(height: 4),
        Text('₹${grandTotal.toStringAsFixed(0)}',
            style: CharakText.display.copyWith(color: Colors.white)),
        const SizedBox(height: 16),
        Row(children: [
          _StatChip(label: 'Consult', amount: consultTotal),
          const SizedBox(width: 8),
          _StatChip(label: 'Procedures', amount: procedureTotal),
          if (pendingReview > 0) ...[
            const SizedBox(width: 8),
            _StatChip(label: 'Pending Review', amount: pendingReview, muted: true),
          ],
        ]),
      ]),
    ),
  );
}

class _StatChip extends StatelessWidget {
  final String label;
  final double amount;
  final bool muted;
  const _StatChip({required this.label, required this.amount, this.muted = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: muted ? Colors.white12 : Colors.white24,
      borderRadius: BorderRadius.all(CharakRadius.pill),
    ),
    child: Column(children: [
      Text('₹${amount.toStringAsFixed(0)}',
          style: TextStyle(
              color: muted ? Colors.white54 : Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13)),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
    ]),
  );
}

// ── Senior review notice ──────────────────────────────────────────────────────

class _SeniorReviewCard extends StatelessWidget {
  final double amount;
  const _SeniorReviewCard({required this.amount});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3CD),
      borderRadius: BorderRadius.all(CharakRadius.card),
      border: Border.all(color: CharakColors.warning),
    ),
    child: Row(children: [
      const Icon(Icons.hourglass_top, color: CharakColors.warning, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(
        '₹${amount.toStringAsFixed(0)} in procedure bills awaiting senior review. '
        'Patients can pay once approved.',
        style: CharakText.caption.copyWith(color: CharakColors.warning),
      )),
    ]),
  );
}

// ── Per-visit row ─────────────────────────────────────────────────────────────

class _EarningsItem extends StatelessWidget {
  final Map<String, dynamic> item;
  const _EarningsItem({required this.item});
  @override
  Widget build(BuildContext context) {
    final name       = item['patient_name'] as String? ?? 'Patient';
    final channel    = item['channel'] as String? ?? '';
    final start      = item['scheduled_start'] as String? ?? '';
    final dt         = start.isNotEmpty ? DateTime.tryParse(start)?.toLocal() : null;
    final dateStr    = dt != null ? DateFormat('d MMM, h:mm a').format(dt) : '—';
    final consultFee = (item['consult_fee'] as num?)?.toDouble();
    final bill       = item['procedure_bill'] as Map<String, dynamic>?;
    final billTotal  = bill != null ? (bill['total'] as num?)?.toDouble() : null;
    final billStatus = bill?['status'] as String?;

    final isHome = channel == 'home_visit';
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(CharakRadius.card),
        side: const BorderSide(color: CharakColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CharakSpacing.base),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: isHome ? const Color(0xFFEAF7F1) : CharakColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isHome ? Icons.home_outlined : Icons.videocam_outlined,
              size: 18,
              color: isHome ? CharakColors.success : CharakColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: CharakText.bodyMed),
            Text(dateStr, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
            if (billTotal != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                _BillStatusBadge(status: billStatus ?? ''),
                const SizedBox(width: 6),
                Text('Procedures: ₹${billTotal.toStringAsFixed(0)}',
                    style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              ]),
            ],
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (consultFee != null)
              Text('₹${consultFee.toStringAsFixed(0)}', style: CharakText.bodyMed),
            if (billTotal != null && billStatus == 'paid')
              Text('+₹${billTotal.toStringAsFixed(0)}',
                  style: CharakText.caption.copyWith(color: CharakColors.success)),
          ]),
        ]),
      ),
    );
  }
}

class _BillStatusBadge extends StatelessWidget {
  final String status;
  const _BillStatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    Color bg; Color fg; String label;
    switch (status) {
      case 'under_review': bg = const Color(0xFFFFF3CD); fg = CharakColors.warning; label = 'Under Review'; break;
      case 'approved':     bg = const Color(0xFFEAF7F1); fg = CharakColors.success; label = 'Approved'; break;
      case 'paid':         bg = const Color(0xFFEAF7F1); fg = CharakColors.success; label = 'Paid'; break;
      default:             bg = CharakColors.bgSubtle;   fg = CharakColors.inkMuted; label = 'Pending'; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.all(CharakRadius.pill)),
      child: Text(label, style: CharakText.micro.copyWith(color: fg)),
    );
  }
}
