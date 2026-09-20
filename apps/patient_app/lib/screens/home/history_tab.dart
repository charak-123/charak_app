import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';
import 'booking_providers.dart';

const _pastStatuses = {'completed', 'cancelled', 'declined'};

class HistoryTab extends ConsumerWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(patientBookingsProvider);
    return Scaffold(
      backgroundColor: CharakColors.bg,
      body: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => const _HistoryLoading(),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (bookings) {
            final past = bookings.where((b) => _pastStatuses.contains(b['status'])).toList();
            return RefreshIndicator(
              onRefresh: () => ref.refresh(patientBookingsProvider.future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                children: [
                  Text('History', style: CharakText.h1.copyWith(letterSpacing: -0.01 * 22)),
                  const SizedBox(height: 5),
                  const Text('Past visits, receipts and ratings',
                      style: charakScreenSubStyle),
                  const SizedBox(height: 6),
                  if (past.isEmpty)
                    const CharakEmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'Nothing here yet',
                      message: 'Completed visits will appear here with receipts '
                          'and your ratings.',
                    )
                  else
                    ..._grouped(past).entries.expand((entry) => [
                      // `.month` — 13px/600 muted group heading, 18px above.
                      Padding(
                        padding: const EdgeInsets.only(top: 18, bottom: 8),
                        child: Text(entry.key,
                            style: CharakText.caption.copyWith(
                                color: CharakColors.inkMuted,
                                fontWeight: FontWeight.w600)),
                      ),
                      ...entry.value.map((b) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _HistoryCard(booking: b),
                      )),
                    ]),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _grouped(List<Map<String, dynamic>> bookings) {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final b in bookings) {
      final start = b['scheduled_start'] as String?;
      final dt = start != null ? DateTime.tryParse(start) : null;
      final key = dt != null ? DateFormat('MMMM yyyy').format(dt.toLocal()) : 'Earlier';
      out.putIfAbsent(key, () => []).add(b);
    }
    return out;
  }
}

/// `.hist-card` — 13/14-padded row: 42px avatar, name + channel line, then a
/// right-aligned amount over a status badge.
class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _HistoryCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final id = booking['id'] as String;
    final status = booking['status'] as String? ?? 'completed';
    final channel = booking['channel'] as String? ?? '';
    final start = booking['scheduled_start'] as String?;
    final docName = (booking['doctors'] as Map?)?['name'] as String? ?? 'Doctor';
    final price = (booking['price_confirmed'] as num?)?.toDouble();

    String formattedTime = '';
    if (start != null) {
      final dt = DateTime.tryParse(start);
      if (dt != null) formattedTime = DateFormat('d MMM, h:mm a').format(dt.toLocal());
    }
    final channelLabel = channel == 'home_visit' ? 'Home Visit' : 'Online';

    return GestureDetector(
      onTap: () => context.push('/booking/$id/history-detail'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: CharakColors.bg,
          border: Border.all(color: CharakColors.border),
          borderRadius: const BorderRadius.all(CharakRadius.card),
        ),
        child: Row(children: [
          CharakAvatar(name: docName, radius: 21),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Dr. $docName',
                style: CharakText.bodyMed.copyWith(
                    fontSize: 14.5, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 1),
            Text('$channelLabel · $formattedTime',
                style: const TextStyle(
                  fontFamily: CharakText.fontFamily,
                  fontSize: 12.5,
                  height: 1.4,
                  color: CharakColors.inkMuted,
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (price != null)
              Text('₹${price.toStringAsFixed(0)}',
                  style: CharakText.bodyMed.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 3),
            CharakBadge(
              label: status == 'completed' ? 'Completed' : status == 'declined' ? 'Declined' : 'Cancelled',
              variant: status == 'completed' ? CharakBadgeVariant.success : CharakBadgeVariant.danger,
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Loading state: the real header stays, then a month heading block and
/// `.hist-card`-shaped `.skel` rows (no footer line — history rows are two
/// lines tall).
class _HistoryLoading extends StatelessWidget {
  const _HistoryLoading();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
    children: [
      Text('History', style: CharakText.h1.copyWith(letterSpacing: -0.01 * 22)),
      const SizedBox(height: 5),
      const Text('Past visits, receipts and ratings', style: charakScreenSubStyle),
      const SizedBox(height: 6),
      // `.month` heading stand-in.
      const Padding(
        padding: EdgeInsets.only(top: 18, bottom: 8),
        child: CharakSkeleton(width: 108, height: 13),
      ),
      ...List.generate(4, (_) => const CharakSkeletonCard(footer: false)),
    ],
  );
}
