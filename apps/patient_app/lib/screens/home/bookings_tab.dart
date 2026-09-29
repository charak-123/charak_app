import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';
import 'booking_providers.dart';

const _activeStatuses = {'requested', 'accepted', 'paid'};

class BookingsTab extends ConsumerWidget {
  const BookingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(patientBookingsProvider);
    final active = async.valueOrNull
        ?.where((b) => _activeStatuses.contains(b['status']))
        .toList();
    return CharakLargeTitleScaffold(
      title: 'Your bookings',
      barTitle: 'Bookings',
      subtitle: active == null
          ? 'Loading…'
          : '${active.length} active booking${active.length == 1 ? '' : 's'}',
      onRefresh: () => ref.refresh(patientBookingsProvider.future),
      children: async.when(
        loading: () =>
            const [CharakSkeletonList(count: 3, padding: EdgeInsets.zero)],
        error: (e, _) => [
          const CharakEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Couldn\'t load bookings',
            message: 'Pull down to try again.',
          ),
        ],
        data: (_) => active!.isEmpty
            ? [
                CharakEmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'No active bookings',
                  message:
                      'Book a doctor from Home and your appointments will show up here.',
                  action: CharakButton(
                    label: 'Find a doctor',
                    onPressed: () {
                      ref.read(homeTabIndexProvider.notifier).state = 0;
                      context.go('/home');
                    },
                  ),
                ),
              ]
            : [
                for (final b in active)
                  Padding(
                    key: ValueKey(b['id']),
                    padding: const EdgeInsets.only(bottom: 12),
                    // Status change: the card flashes and the chip cross-fades.
                    child: CharakStatusPulse(
                      trigger: b['status'],
                      child: _BookingCard(booking: b),
                    ),
                  ),
              ],
      ),
    );
  }
}

/// Booking card: avatar, doctor and status chip, then the time and fee in
/// narrow tabular figures.
class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _BookingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final status = booking['status'] as String? ?? 'requested';
    final channel = booking['channel'] as String? ?? '';
    final start = booking['scheduled_start'] as String?;
    final docName =
        (booking['doctors'] as Map?)?['name'] as String? ?? 'Doctor';
    final docCategory = ((booking['doctors'] as Map?)?['categories']
            as Map?)?['name'] as String? ??
        '';
    final pricing = List<Map<String, dynamic>>.from(
        (booking['doctors'] as Map?)?['doctor_pricing'] as List? ?? []);
    final priceRow = pricing.where((p) => p['channel'] == channel).firstOrNull;
    final priceStr = priceRow != null
        ? '₹${(priceRow['price'] as num).toStringAsFixed(0)}'
        : null;

    String formattedTime = '';
    if (start != null) {
      final dt = DateTime.tryParse(start);
      if (dt != null) {
        formattedTime = DateFormat('d MMM, h:mm a').format(dt.toLocal());
      }
    }

    final channelLabel =
        channel == 'home_visit' ? 'Home Visit' : 'Online Consult';

    return CharakCard(
      onTap: () => _navigate(context, status, booking['id'] as String),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CharakAvatar(name: docName, radius: 24),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Dr. $docName',
                    style: CharakText.titleSmall.copyWith(fontSize: 18),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                Text(
                  docCategory.isNotEmpty
                      ? '$docCategory · $channelLabel'
                      : channelLabel,
                  style:
                      CharakText.caption.copyWith(color: CharakColors.inkMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ])),
          const SizedBox(width: 8),
          CharakFadeSwap(
            child: CharakStatusPill.forStatus(status, key: ValueKey(status)),
          ),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
              border: Border(top: BorderSide(color: CharakColors.border))),
          child: Row(children: [
            if (formattedTime.isNotEmpty) ...[
              Icon(Icons.schedule_rounded,
                  size: 16, color: CharakColors.inkMuted),
              const SizedBox(width: 8),
              Text(formattedTime,
                  style: CharakText.label.tabular
                      .copyWith(color: CharakColors.ink)),
            ],
            const Spacer(),
            if (priceStr != null)
              Text(priceStr,
                  style: CharakText.numeric.copyWith(color: CharakColors.ink)),
          ]),
        ),
      ]),
    );
  }

  void _navigate(BuildContext context, String status, String id) {
    switch (status) {
      case 'accepted':
        context.push('/booking/$id/pay');
      case 'paid':
      case 'completed':
        context.push('/booking/$id/active');
      default:
        context.push('/booking/$id/status');
    }
  }
}
