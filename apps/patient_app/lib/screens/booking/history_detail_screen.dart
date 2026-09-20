import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

class _HistoryDetail {
  final Map<String, dynamic> booking;
  final Map<String, dynamic>? procedureBill;
  final Map<String, dynamic>? rating;
  final String? paymentRef;
  const _HistoryDetail({required this.booking, this.procedureBill, this.rating, this.paymentRef});
}

final _historyDetailProvider =
    FutureProvider.autoDispose.family<_HistoryDetail, String>((ref, bookingId) async {
  final booking = await ApiClient.instance.get('/bookings/$bookingId') as Map<String, dynamic>;

  Map<String, dynamic>? procedureBill;
  try {
    procedureBill = await ApiClient.instance.get('/bookings/$bookingId/procedure-bill') as Map<String, dynamic>;
  } on ApiException catch (e) {
    if (e.statusCode != 404) rethrow;
  }

  Map<String, dynamic>? rating;
  try {
    rating = await ApiClient.instance.get('/bookings/$bookingId/rate') as Map<String, dynamic>?;
  } on ApiException catch (e) {
    if (e.statusCode != 404) rethrow;
  }

  String? paymentRef;
  try {
    final payments = await ApiClient.instance.get('/payments/$bookingId') as List;
    final completed = payments.cast<Map<String, dynamic>>().where((p) => p['status'] == 'completed').firstOrNull;
    paymentRef = completed?['razorpay_payment_id'] as String?;
  } on ApiException {
    // Payment lookup is best-effort — the receipt row just won't show a reference.
  }

  return _HistoryDetail(booking: booking, procedureBill: procedureBill, rating: rating, paymentRef: paymentRef);
});

class HistoryDetailScreen extends ConsumerWidget {
  final String bookingId;
  const HistoryDetailScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_historyDetailProvider(bookingId));
    return Scaffold(
      backgroundColor: CharakColors.bg,
      appBar: const CharakTopBar(title: 'Visit details'),
      body: async.when(
        loading: () => const SingleChildScrollView(child: CharakSkeletonDetail()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (detail) => _Body(bookingId: bookingId, detail: detail),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String bookingId;
  final _HistoryDetail detail;
  const _Body({required this.bookingId, required this.detail});

  @override
  Widget build(BuildContext context) {
    final b = detail.booking;
    final docName = (b['doctors'] as Map?)?['name'] as String? ?? 'Doctor';
    final channel = b['channel'] as String? ?? '';
    final status = b['status'] as String? ?? 'completed';
    final start = b['scheduled_start'] as String?;
    final consultFee = (b['price_confirmed'] as num?)?.toDouble() ?? 0;

    String formattedTime = '';
    if (start != null) {
      final dt = DateTime.tryParse(start);
      if (dt != null) formattedTime = DateFormat('EEE, d MMM, h:mm a').format(dt.toLocal());
    }

    final bill = detail.procedureBill;
    final procs = List<Map<String, dynamic>>.from((bill?['items'] as List?) ?? []);
    final procTotal = (bill?['total'] as num?)?.toDouble() ?? 0;
    final amount = consultFee + procTotal;

    final rating = detail.rating;
    final stars = (rating?['stars'] as num?)?.toInt();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        // `.card.rev-sum` — the full receipt for this visit.
        CharakSummaryCard(rows: [
          CharakSummaryRow(label: 'Doctor', value: 'Dr. $docName'),
          if (formattedTime.isNotEmpty)
            CharakSummaryRow(label: 'When', value: formattedTime),
          CharakSummaryRow(
              label: 'Channel',
              value: channel == 'home_visit' ? 'Home Visit' : 'Online Consult'),
          const CharakSummaryDivider(),
          CharakSummaryRow(
              label: 'Consult fee · 15 min',
              value: '₹${consultFee.toStringAsFixed(0)}',
              tabular: true),
          for (final p in procs)
            CharakSummaryRow(
                label: p['name'] as String? ?? '',
                value: '₹${(p['price'] as num).toStringAsFixed(0)}',
                tabular: true),
          if (procTotal > 0)
            CharakSummaryRow(
                label: 'Procedures',
                value: '₹${procTotal.toStringAsFixed(0)}',
                tabular: true),
          const CharakSummaryDivider(),
          CharakSummaryRow(
              label: 'Amount',
              value: '₹${amount.toStringAsFixed(0)}',
              tabular: true),
          CharakSummaryRow(
            label: 'Paid via',
            value: detail.paymentRef != null ? 'UPI · ${detail.paymentRef}' : '—',
            muted: true,
          ),
          CharakSummaryRow(
            label: 'Status',
            child: CharakStatusPill.forStatus(status),
          ),
        ]),

        if (stars != null) ...[
          const SizedBox(height: 12),
          CharakSummaryCard(
            title: 'Your rating',
            rows: [
              Align(
                alignment: Alignment.centerLeft,
                child: CharakStarRating(value: stars, size: 18, gap: 4),
              ),
            ],
          ),
        ],

        const SizedBox(height: 8),
        // `.btn.text` — a quiet primary-coloured link row.
        CharakGhostButton(
          label: 'Submit a complaint about this visit',
          onPressed: () => context.push('/booking/$bookingId/complaint'),
        ),
      ],
    );
  }
}
