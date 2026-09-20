import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:charak_core/charak_core.dart';
// intl is a direct dependency; don't rely on shadcn_ui re-exporting DateFormat.
// ignore: unnecessary_import
import 'package:intl/intl.dart';

// ── Procedure checklist entry ─────────────────────────────────────────────────

class _ProcedureEntry {
  final String procedureId;
  final String name;
  final double unitPrice;
  bool selected = false;
  _ProcedureEntry({
    required this.procedureId,
    required this.name,
    required this.unitPrice,
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
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog(
        title: const Text('Mark visit complete?'),
        description: Text(_selectedItems.isEmpty
            ? 'No procedures selected. Only the consult fee will be charged.'
            : '${_selectedItems.length} procedure(s) totalling ₹${_total.toStringAsFixed(0)} will be billed.'),
        actions: [
          ShadButton.outline(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ShadButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Complete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _completing = true);
    try {
      await ApiClient.instance.patch('/bookings/${widget.bookingId}/complete', {});
      if (_selectedItems.isNotEmpty) {
        await ApiClient.instance.post(
          '/bookings/${widget.bookingId}/procedure-bill',
          {'items': _selectedItems},
        );
      }
      if (mounted) {
        showCharakToast(context, message: 'Visit completed — patient can now pay');
        context.go('/home');
      }
    } on ApiException catch (e) {
      if (mounted) {
        showCharakToast(context, message: e.message, isError: true);
      }
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  void _stub(String label) => showCharakToast(context, message: label);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_activeVisitProvider(widget.bookingId));
    return Scaffold(
      backgroundColor: CharakColors.bg,
      appBar: const CharakTopBar(title: 'Active visit'),
      body: async.when(
        // `.skel` blocks matching the real body — `.act-doctor-card`, the
        // visit-lines card, the procedure checklist and the two actions.
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: const [
            CharakSkeleton(height: 78, radius: 14),
            SizedBox(height: 12),
            CharakSkeleton(height: 104, radius: 14),
            SizedBox(height: 14),
            CharakSkeleton(height: 210, radius: 14),
            SizedBox(height: 14),
            CharakSkeleton(height: 50, radius: 12),
            SizedBox(height: 10),
            CharakSkeleton(height: 50, radius: 12),
          ],
        ),
        error: (e, _) => Center(
          child: Text('Failed to load visit',
              style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
        ),
        data: (data) {
          final booking = data['booking'] as Map<String, dynamic>;
          final procs   = data['procedures'] as List;
          _initProcedures(procs);
          final isHome = booking['channel'] == 'home_visit';
          final isPaid = booking['status'] == 'paid';
          final price  = (booking['price_confirmed'] as num?)?.toStringAsFixed(0) ?? '—';

          final threshold = (booking['doctors'] as Map<String, dynamic>?)?['procedure_review_threshold'];
          final needsReview = threshold != null && _total > (threshold as num);

          return Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                children: [
                  // `.pulse` — the status block flashes when the booking's
                  // status moves (accepted → paid → completed).
                  CharakStatusPulse(
                    trigger: booking['status'],
                    child: _PatientInfoCard(booking: booking),
                  ),
                  const SizedBox(height: 12),
                  if (isPaid) ...[
                    CharakNoteBanner(
                      icon: Icons.payments_outlined,
                      leadLabel: 'Payment received',
                      message: '— ₹$price confirmed. Visit proceeds.',
                      tone: CharakStatusTone.success,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _VisitLinesCard(booking: booking),
                  const SizedBox(height: 14),
                  if (isHome) ...[
                    // The bill crossing the senior-review threshold is a
                    // status change too — pulse the card that reports it.
                    CharakStatusPulse(
                      trigger: needsReview,
                      child: _ProcedureChecklist(
                        procedures: _procedures,
                        total: _total,
                        threshold: threshold != null ? (threshold as num).toDouble() : null,
                        needsReview: needsReview,
                        onToggle: (i) =>
                            setState(() => _procedures[i].selected = !_procedures[i].selected),
                      ),
                    ),
                    const SizedBox(height: 14),
                    CharakButton(label: 'Navigate to patient', icon: Icons.navigation_outlined, onPressed: () => _stub('Opens native maps')),
                    const SizedBox(height: 10),
                    CharakButton(label: 'Contact patient', outlined: true, icon: Icons.message_outlined, onPressed: () => _stub('Contact through app — no raw number')),
                  ] else ...[
                    CharakButton(label: 'Start call', icon: Icons.videocam_rounded, onPressed: () => context.push('/call/${widget.bookingId}')),
                    const SizedBox(height: 10),
                    CharakButton(label: 'Directions to patient', outlined: true, icon: Icons.navigation_outlined, onPressed: () => _stub('Opens native maps')),
                  ],
                  const SizedBox(height: 8),
                  CharakHintLine(
                    align: TextAlign.center,
                    text: 'Consult fee ₹$price is confirmed from the request. '
                        'Procedures are billed separately after the visit.',
                  ),
                ],
              ),
            ),
            CharakCtaBar.single(
              CharakButton(
                label: 'Mark as complete',
                icon: Icons.flag_outlined,
                isLoading: _completing,
                onPressed: () => _markComplete(booking),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

/// `.act-doctor-card` — 15px-padded card: avatar, 16px/600 name over a
/// 12.5px muted channel · slot line, and a success status pill.
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
    final label   = channel == 'home_visit' ? 'Home Visit' : 'Online Consult';

    return Container(
      padding: const EdgeInsets.all(15),
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
              style: CharakText.h2.copyWith(fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 1),
          Text(
            dt != null ? '$label · ${_slotFormat.format(dt)}' : label,
            style: const TextStyle(
              fontFamily: CharakText.fontFamily,
              fontSize: 12.5,
              height: 1.4,
              color: CharakColors.inkMuted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ])),
        const SizedBox(width: 10),
        // `.fade-swap` — keyed on the status so the pill lifts and
        // cross-fades whenever the booking moves on.
        CharakFadeSwap(
          child: CharakStatusPill(
            key: ValueKey(booking['status']),
            label: 'Accepted',
            tone: CharakStatusTone.success,
          ),
        ),
      ]),
    );
  }
}

final _slotFormat = DateFormat('EEE d MMM, h:mm a');

/// `.card` with the 6px/14px inset wrapping the visit's `.visit-line` rows.
class _VisitLinesCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _VisitLinesCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final isHome  = booking['channel'] == 'home_visit';
    final start   = booking['scheduled_start'] as String? ?? '';
    final dt      = start.isNotEmpty ? DateTime.tryParse(start)?.toLocal() : null;
    final address = booking['patient_address'] as String?;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: CharakColors.bg,
        borderRadius: const BorderRadius.all(CharakRadius.card),
        border: Border.all(color: CharakColors.border),
      ),
      child: Column(children: [
        CharakVisitLine(
          icon: Icons.access_time_rounded,
          value: dt != null ? _slotFormat.format(dt) : '—',
        ),
        if (isHome)
          CharakVisitLine(
            icon: Icons.place_outlined,
            value: (address != null && address.isNotEmpty) ? address : 'Address in the booking',
          )
        else
          const CharakVisitLine(
            icon: Icons.videocam_outlined,
            value: 'Video consult',
            trailing: 'start the call at slot time',
          ),
      ]),
    );
  }
}

/// Procedures card — `.proc-check` rows (11px, hairline-separated, 18px
/// checkbox, muted tabular price), a `.proc-total` footer, and either the
/// senior-review banner or the threshold `.hint-line`.
class _ProcedureChecklist extends StatelessWidget {
  final List<_ProcedureEntry> procedures;
  final double total;
  final double? threshold;
  final bool needsReview;
  final void Function(int) onToggle;
  const _ProcedureChecklist({
    required this.procedures,
    required this.total,
    required this.threshold,
    required this.needsReview,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: CharakColors.bg,
      borderRadius: const BorderRadius.all(CharakRadius.card),
      border: Border.all(color: CharakColors.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const CharakSectionTitle(label: 'Procedures performed'),
      const SizedBox(height: 2),
      const Text(
        'Tap the procedures done this visit — fixed rates apply. Patient is billed '
        'after the visit.',
        style: TextStyle(
          fontFamily: CharakText.fontFamily,
          fontSize: 12.5,
          height: 1.5,
          color: CharakColors.inkMuted,
        ),
      ),
      const SizedBox(height: 10),
      if (procedures.isEmpty)
        Text('No procedures configured.\nAdd procedures in Profile → Pricing.',
            style: CharakText.caption.copyWith(color: CharakColors.inkMuted))
      else
        ...procedures.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          return GestureDetector(
            onTap: () => onToggle(i),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                border: i == procedures.length - 1
                    ? null
                    : const Border(bottom: BorderSide(color: CharakColors.border)),
              ),
              child: Row(children: [
                Expanded(child: Text(p.name, style: CharakText.body.copyWith(fontSize: 14))),
                Text(
                  '₹${p.unitPrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontFamily: CharakText.fontFamily,
                    fontSize: 14,
                    height: 1.4,
                    color: CharakColors.inkMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                // `.proc-check input` — 18px, primary accent.
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: p.selected,
                    activeColor: CharakColors.primary,
                    side: const BorderSide(color: CharakColors.border, width: 1.5),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (_) => onToggle(i),
                  ),
                ),
              ]),
            ),
          );
        }),
      // `.proc-total` — 12px top gap, 13.5px muted label, 16px ink figure.
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text(
            'Procedures total',
            style: TextStyle(
              fontFamily: CharakText.fontFamily,
              fontSize: 13.5,
              height: 1.4,
              color: CharakColors.inkMuted,
            ),
          ),
          Text(
            '₹${total.toStringAsFixed(0)}',
            style: CharakText.h2.copyWith(
              fontSize: 16,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ]),
      ),
      if (needsReview && threshold != null) ...[
        const SizedBox(height: 10),
        CharakNoteBanner(
          icon: Icons.gpp_maybe_outlined,
          leadLabel: 'Senior review needed',
          message: '— this bill is above ₹${threshold!.toStringAsFixed(0)}. '
              'A senior doctor verifies it before the patient pays.',
        ),
      ] else if (threshold != null) ...[
        const SizedBox(height: 8),
        CharakHintLine(
          text: 'Bills above ₹${threshold!.toStringAsFixed(0)} are auto-sent for senior review.',
        ),
      ],
    ]),
  );
}
