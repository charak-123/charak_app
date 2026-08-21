import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';
import '../shared/charak_button.dart';

// ── Procedure checklist entry ─────────────────────────────────────────────────

class _ProcedureEntry {
  final String procedureId;
  final String name;
  final double unitPrice;
  bool selected;
  _ProcedureEntry({
    required this.procedureId,
    required this.name,
    required this.unitPrice,
    this.selected = false,
  });
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _activeVisitProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final booking    = await ApiClient.instance.get('/bookings/$id');
  final procedures = await ApiClient.instance.get('/doctors/me/procedures');
  return {
    'booking': booking as Map<String, dynamic>,
    'procedures': procedures as List,
  };
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ActiveVisitScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const ActiveVisitScreen({super.key, required this.bookingId});
  @override
  ConsumerState<ActiveVisitScreen> createState() => _State();
}

class _State extends ConsumerState<ActiveVisitScreen> {
  List<_ProcedureEntry> _procedures = [];
  bool _completing = false;

  void _initProcedures(List rawProcs) {
    if (_procedures.isEmpty && rawProcs.isNotEmpty) {
      _procedures = rawProcs.map((p) {
        final m = p as Map<String, dynamic>;
        return _ProcedureEntry(
          procedureId: m['id'] as String,
          name: m['name'] as String,
          unitPrice: double.tryParse(m['price'].toString()) ?? 0,
        );
      }).toList();
    }
  }

  double get _total => _procedures
      .where((p) => p.selected)
      .fold(0.0, (sum, p) => sum + p.unitPrice);

  List<Map<String, dynamic>> get _selectedItems => _procedures
      .where((p) => p.selected)
      .map((p) => {'name': p.name, 'price': p.unitPrice})
      .toList();

  Future<void> _markComplete(Map<String, dynamic> booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark visit complete?'),
        content: _selectedItems.isEmpty
            ? const Text('No procedures selected. Only the consult fee will be charged.')
            : Text(
                '${_selectedItems.length} procedure(s) totalling ₹${_total.toStringAsFixed(0)} will be billed.',
              ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Complete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _completing = true);
    try {
      // 1. Mark booking as completed
      await ApiClient.instance.patch('/bookings/${widget.bookingId}/complete', {});

      // 2. Submit procedure bill if any procedures selected
      if (_selectedItems.isNotEmpty) {
        await ApiClient.instance.post(
          '/bookings/${widget.bookingId}/procedure-bill',
          {'items': _selectedItems},
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Visit completed!'),
            backgroundColor: CharakColors.success,
          ),
        );
        context.go('/home');
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: CharakColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_activeVisitProvider(widget.bookingId));
    return Scaffold(
      backgroundColor: CharakColors.bgSubtle,
      appBar: AppBar(
        title: const Text('Active Visit'),
        backgroundColor: CharakColors.bg,
        foregroundColor: CharakColors.ink,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_outlined),
            onPressed: () => context.push('/call/${widget.bookingId}'),
            tooltip: 'Clarification call',
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          final booking = data['booking'] as Map<String, dynamic>;
          final procs   = data['procedures'] as List;
          _initProcedures(procs);

          final threshold = (booking['doctors'] as Map<String, dynamic>?)?['procedure_review_threshold'];
          final needsReview = threshold != null && _total > (threshold as num);

          return Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(CharakSpacing.base),
                children: [
                  _PatientInfoCard(booking: booking),
                  const SizedBox(height: 12),
                  _PaymentBanner(booking: booking),
                  const SizedBox(height: 12),
                  _ProcedureChecklist(
                    procedures: _procedures,
                    onToggle: (i) => setState(() => _procedures[i].selected = !_procedures[i].selected),
                  ),
                  const SizedBox(height: 12),
                  _RunningTotal(total: _total),
                  if (needsReview) ...[
                    const SizedBox(height: 12),
                    _SeniorReviewBanner(total: _total, threshold: (threshold as num).toDouble()),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
            _CompleteBar(completing: _completing, onComplete: () => _markComplete(booking)),
          ]);
        },
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _PatientInfoCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _PatientInfoCard({required this.booking});
  @override
  Widget build(BuildContext context) {
    final patient = booking['users'] as Map<String, dynamic>? ?? {};
    final name    = patient['name'] as String? ?? 'Patient';
    final channel = booking['channel'] as String? ?? '';
    final start   = booking['scheduled_start'] as String? ?? '';
    final dt      = start.isNotEmpty ? DateTime.tryParse(start)?.toLocal() : null;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(CharakRadius.card),
        side: const BorderSide(color: CharakColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CharakSpacing.base),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: CharakColors.primarySoft,
              child: Text(name[0].toUpperCase(),
                  style: CharakText.bodyMed.copyWith(color: CharakColors.primary)),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: CharakText.bodyMed),
              Text(
                channel == 'home_visit' ? 'Home Visit' : 'Online Consult',
                style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
              ),
            ]),
          ]),
          if (dt != null) ...[
            const Divider(height: 20, color: CharakColors.border),
            Row(children: [
              const Icon(Icons.access_time, size: 14, color: CharakColors.inkMuted),
              const SizedBox(width: 6),
              Text(DateFormat('EEE d MMM, h:mm a').format(dt),
                  style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _PaymentBanner extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _PaymentBanner({required this.booking});
  @override
  Widget build(BuildContext context) {
    final status = booking['status'] as String? ?? '';
    final price  = booking['price_confirmed'];
    final isPaid = status == 'paid';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isPaid ? const Color(0xFFEAF7F1) : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.all(CharakRadius.card),
        border: Border.all(
          color: isPaid ? CharakColors.success : CharakColors.warning,
        ),
      ),
      child: Row(children: [
        Icon(
          isPaid ? Icons.check_circle_outline : Icons.payment_outlined,
          color: isPaid ? CharakColors.success : CharakColors.warning,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text(
          isPaid
              ? 'Consult fee paid${price != null ? ' (₹${(price as num).toStringAsFixed(0)})' : ''}'
              : 'Awaiting payment${price != null ? ' — ₹${(price as num).toStringAsFixed(0)}' : ''}',
          style: CharakText.caption.copyWith(
            color: isPaid ? CharakColors.success : CharakColors.warning,
            fontWeight: FontWeight.w600,
          ),
        ),
      ]),
    );
  }
}

class _ProcedureChecklist extends StatelessWidget {
  final List<_ProcedureEntry> procedures;
  final void Function(int) onToggle;
  const _ProcedureChecklist({required this.procedures, required this.onToggle});
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(CharakRadius.card),
      side: const BorderSide(color: CharakColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(CharakSpacing.base),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Procedures Performed', style: CharakText.h2),
        const SizedBox(height: 8),
        if (procedures.isEmpty)
          Text('No procedures configured.\nAdd procedures in Profile → Pricing.',
              style: CharakText.caption.copyWith(color: CharakColors.inkMuted))
        else
          ...procedures.asMap().entries.map((e) {
            final i = e.key;
            final p = e.value;
            return CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p.name, style: CharakText.body),
              subtitle: Text('₹${p.unitPrice.toStringAsFixed(0)}',
                  style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              value: p.selected,
              activeColor: CharakColors.primary,
              onChanged: (_) => onToggle(i),
            );
          }),
      ]),
    ),
  );
}

class _RunningTotal extends StatelessWidget {
  final double total;
  const _RunningTotal({required this.total});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: CharakColors.primarySoft,
      borderRadius: BorderRadius.all(CharakRadius.card),
    ),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text('Procedure Total', style: CharakText.bodyMed.copyWith(color: CharakColors.primary)),
      Text('₹${total.toStringAsFixed(0)}',
          style: CharakText.h2.copyWith(color: CharakColors.primary)),
    ]),
  );
}

class _SeniorReviewBanner extends StatelessWidget {
  final double total;
  final double threshold;
  const _SeniorReviewBanner({required this.total, required this.threshold});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3CD),
      borderRadius: BorderRadius.all(CharakRadius.card),
      border: Border.all(color: CharakColors.warning),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.warning_amber_rounded, color: CharakColors.warning, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(
        'Total ₹${total.toStringAsFixed(0)} exceeds your review threshold of '
        '₹${threshold.toStringAsFixed(0)}. This bill will require senior approval before the patient can pay.',
        style: CharakText.caption.copyWith(color: CharakColors.warning),
      )),
    ]),
  );
}

class _CompleteBar extends StatelessWidget {
  final bool completing;
  final VoidCallback onComplete;
  const _CompleteBar({required this.completing, required this.onComplete});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(CharakSpacing.base, 12, CharakSpacing.base, 24),
    decoration: const BoxDecoration(
      color: CharakColors.bg,
      border: Border(top: BorderSide(color: CharakColors.border)),
    ),
    child: CharakButton(
      label: 'Mark Visit Complete',
      isLoading: completing,
      onPressed: onComplete,
    ),
  );
}
