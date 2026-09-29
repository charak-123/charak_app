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
    return CharakLargeTitleScaffold(
      title: 'History',
      subtitle: 'Past visits, receipts and ratings',
      onRefresh: () => ref.refresh(patientBookingsProvider.future),
      children: async.when(
        loading: () => const [CharakSkeletonList(count: 4, padding: EdgeInsets.zero)],
        error: (e, _) => const [
          CharakEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Couldn\'t load history',
            message: 'Pull down to try again.',
          ),
        ],
        data: (bookings) {
          final past = bookings.where((b) => _pastStatuses.contains(b['status'])).toList();
          if (past.isEmpty) {
            return const [
              CharakEmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Nothing here yet',
                message: 'Completed visits will appear here with receipts and your ratings.',
              ),
            ];
          }
          // One grouped block per month (One UI settings style).
          return [
            for (final entry in _grouped(past).entries) ...[
              CharakGroupedList(
                label: entry.key,
                children: [
                  for (var k = 0; k < entry.value.length; k++)
                    _HistoryRow(booking: entry.value[k], last: k == entry.value.length - 1),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ];
        },
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

/// History row inside a month block: avatar, doctor, channel · time, then
/// the fee (tabular) over its status chip.
class _HistoryRow extends StatelessWidget {
  final Map<String, dynamic> booking;
  final bool last;
  const _HistoryRow({required this.booking, required this.last});

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
    final channelLabel = channel == 'home_visit' ? 'Home visit' : 'Online';

    return CharakListRow(
      leading: CharakAvatar(name: docName, radius: 22),
      title: 'Dr. $docName',
      subtitle: '$channelLabel · $formattedTime',
      showChevron: false,
      last: last,
      onTap: () => context.push('/booking/$id/history-detail'),
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (price != null)
          Text('₹${price.toStringAsFixed(0)}', style: CharakText.label.tabular.copyWith(fontSize: 16)),
        const SizedBox(height: 4),
        CharakStatusPill.forStatus(status),
      ]),
    );
  }
}
