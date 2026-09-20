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
      backgroundColor: CharakColors.bg,
      body: SafeArea(
        bottom: false,
        child: async.when(
          // `.skel` stand-ins for the ink `.earn-total` card and the first few
          // `.earn-row`s, under the screen's real header.
          loading: () => ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            children: const [
              CharakScreenHeader(
                  title: 'Earnings', subtitle: 'This month · V1 keeps it simple'),
              SizedBox(height: 14),
              // `.earn-total` — 18px padding around a 12px label and 28px figure.
              CharakSkeleton(height: 92, radius: 14),
              SizedBox(height: 16),
              CharakSkeleton(width: 168, height: 13),
              SizedBox(height: 4),
              _EarnRowSkeleton(),
              _EarnRowSkeleton(),
              _EarnRowSkeleton(),
              _EarnRowSkeleton(),
            ],
          ),
          error: (e, _) => Center(
            child: Text('Failed to load earnings',
                style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
          ),
          data: (data) {
            final items         = List<Map<String, dynamic>>.from(data['items'] as List);
            final pendingReview = (data['pending_review_total'] as num?)?.toDouble() ?? 0;
            final grandTotal    = (data['grand_total'] as num?)?.toDouble() ?? 0;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              children: [
                const CharakScreenHeader(
                    title: 'Earnings', subtitle: 'This month · V1 keeps it simple'),
                const SizedBox(height: 14),
                _EarnTotal(
                  label: 'Total · ${DateFormat('MMMM yyyy').format(DateTime.now())}',
                  amount: grandTotal,
                ),
                if (pendingReview > 0) ...[
                  CharakNoteBanner(
                    icon: Icons.shield_outlined,
                    leadLabel: '₹${pendingReview.toStringAsFixed(0)} awaiting senior review',
                    message: '— patients can pay once a senior doctor approves the bill.',
                  ),
                  const SizedBox(height: 16),
                ],
                const CharakSectionTitle(label: 'Completed bookings'),
                const SizedBox(height: 4),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: Center(
                      child: Text('No completed visits yet',
                          style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
                    ),
                  )
                else
                  ...items.asMap().entries.map((e) => _EarnRow(
                        item: e.value,
                        last: e.key == items.length - 1,
                      )),
                const SizedBox(height: 14),
                const CharakHintLine(
                  text: 'Full dashboard — charts, payout history, filters — is planned for V2.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Loading placeholder for one `.earn-row`: a two-line left stack with the
/// amount on the right, over the row's hairline divider.
class _EarnRowSkeleton extends StatelessWidget {
  const _EarnRowSkeleton();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: CharakColors.border)),
    ),
    child: const Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CharakSkeleton(width: 128, height: 14),
          SizedBox(height: 6),
          CharakSkeleton(width: 92, height: 12),
        ]),
      ),
      SizedBox(width: 10),
      CharakSkeleton(width: 58, height: 15),
    ]),
  );
}

// ── `.earn-total` ─────────────────────────────────────────────────────────────

/// `.earn-total` — an ink card: uppercase 12px/0.05em translucent label over a
/// 28px/600 tabular figure in white.
class _EarnTotal extends StatelessWidget {
  final String label;
  final double amount;
  const _EarnTotal({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: const BoxDecoration(
      color: CharakColors.ink,
      borderRadius: BorderRadius.all(CharakRadius.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontFamily: CharakText.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 1.3,
            letterSpacing: 12 * 0.05,
            // `.earn-total .l` — rgba(255,255,255,0.6)
            color: Color(0x99FFFFFF),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '₹${NumberFormat.decimalPattern('en_IN').format(amount.round())}',
          style: CharakText.display.copyWith(
            color: Colors.white,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

// ── `.earn-row` ───────────────────────────────────────────────────────────────

/// `.earn-row` — 58px date column, a title/subtitle stack (plus the amber
/// `.rev-line` when a bill is still with a senior doctor) and a tabular amount.
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

    final channelLabel = channel == 'home_visit' ? 'Home Visit' : 'Online';
    final subtitle = billTotal > 0
        ? '$channelLabel · procedures ₹${billTotal.toStringAsFixed(0)}'
        : channelLabel;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: CharakColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `.earn-row .when` — fixed 58px muted column.
          SizedBox(
            width: 58,
            child: Text(
              when,
              style: const TextStyle(
                fontFamily: CharakText.fontFamily,
                fontSize: 12.5,
                height: 1.5,
                color: CharakColors.inkMuted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: CharakText.bodyMed.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: CharakText.fontFamily,
                    fontSize: 12,
                    height: 1.4,
                    color: CharakColors.inkMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (billState == 'under_review') ...[
                  const SizedBox(height: 2),
                  // `.rev-line` — 11.5px warning line with a 12px shield.
                  Row(children: [
                    const Icon(Icons.shield_outlined, size: 12, color: CharakColors.warning),
                    const SizedBox(width: 5),
                    Text(
                      'Awaiting senior review',
                      style: CharakText.micro.copyWith(
                        fontSize: 11.5,
                        letterSpacing: 0,
                        color: CharakColors.warning,
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '₹${(consult + billTotal).toStringAsFixed(0)}',
            style: CharakText.bodyMed.copyWith(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
