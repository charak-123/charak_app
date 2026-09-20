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
    return Scaffold(
      backgroundColor: CharakColors.bg,
      body: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => const _BookingsLoading(),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (bookings) {
            final active = bookings.where((b) => _activeStatuses.contains(b['status'])).toList();
            return RefreshIndicator(
              onRefresh: () => ref.refresh(patientBookingsProvider.future),
              child: ListView(
                // `.body` — 8/20/24, home screens open at 14px.
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                children: [
                  Text('Bookings', style: CharakText.h1.copyWith(letterSpacing: -0.01 * 22)),
                  const SizedBox(height: 5),
                  Text(
                    '${active.length} active booking${active.length == 1 ? '' : 's'}',
                    style: charakScreenSubStyle,
                  ),
                  const SizedBox(height: 16),
                  if (active.isEmpty)
                    CharakEmptyState(
                      icon: Icons.event_busy_outlined,
                      title: 'No active bookings',
                      message: 'Book a doctor from the Home tab and your '
                          'appointments will show up here.',
                      action: CharakButton(
                        label: 'Browse doctors',
                        onPressed: () {
                          ref.read(homeTabIndexProvider.notifier).state = 0;
                          context.go('/home');
                        },
                      ),
                    )
                  else
                    ...active.map((b) => Padding(
                      key: ValueKey(b['id']),
                      padding: const EdgeInsets.only(bottom: 10),
                      // `.pulse` — the row flashes when its status changes.
                      child: CharakStatusPulse(
                        trigger: b['status'],
                        child: _BookingCard(booking: b),
                      ),
                    )),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// `.bk-card` — 15px-padded card: a 46px avatar row with a status pill, then
/// the `.bk-mid` time/price line.
class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _BookingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final status = booking['status'] as String? ?? 'requested';
    final channel = booking['channel'] as String? ?? '';
    final start = booking['scheduled_start'] as String?;
    final docName = (booking['doctors'] as Map?)?['name'] as String? ?? 'Doctor';
    final docCategory = ((booking['doctors'] as Map?)?['categories'] as Map?)?['name'] as String? ?? '';
    final pricing = List<Map<String,dynamic>>.from(
        (booking['doctors'] as Map?)?['doctor_pricing'] as List? ?? []);
    final priceRow = pricing.where((p) => p['channel'] == channel).firstOrNull;
    final priceStr = priceRow != null
        ? '₹${(priceRow['price'] as num).toStringAsFixed(0)}'
        : null;

    String formattedTime = '';
    if (start != null) {
      final dt = DateTime.tryParse(start);
      if (dt != null) formattedTime = DateFormat('d MMM, h:mm a').format(dt.toLocal());
    }

    final channelLabel = channel == 'home_visit' ? 'Home Visit' : 'Online Consult';

    return GestureDetector(
      onTap: () => _navigate(context, status, booking['id'] as String),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: CharakColors.bg,
          border: Border.all(color: CharakColors.border),
          borderRadius: const BorderRadius.all(CharakRadius.card),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CharakAvatar(name: docName, radius: 23),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dr. $docName',
                  style: CharakText.bodyMed.copyWith(
                      fontSize: 15, fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 1),
              Text(
                docCategory.isNotEmpty ? '$docCategory · $channelLabel' : channelLabel,
                style: const TextStyle(
                  fontFamily: CharakText.fontFamily,
                  fontSize: 12.5,
                  height: 1.4,
                  color: CharakColors.inkMuted,
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ])),
            const SizedBox(width: 8),
            // `.fade-swap` — the label cross-fades when the status changes.
            CharakFadeSwap(
              child: CharakStatusPill.forStatus(status, key: ValueKey(status)),
            ),
          ]),
          const SizedBox(height: 11),
          // `.bk-mid`
          Row(children: [
            if (formattedTime.isNotEmpty) ...[
              const Icon(Icons.schedule, size: 14, color: CharakColors.inkMuted),
              const SizedBox(width: 8),
              Text(formattedTime,
                  style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
            ],
            const Spacer(),
            if (priceStr != null)
              Text(priceStr, style: CharakText.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: CharakColors.ink,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ]),
      ),
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

/// Loading state: the real screen header stays put while `.skel` blocks stand
/// in for the booking cards, so nothing shifts when data arrives.
class _BookingsLoading extends StatelessWidget {
  const _BookingsLoading();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
    children: [
      Text('Bookings', style: CharakText.h1.copyWith(letterSpacing: -0.01 * 22)),
      const SizedBox(height: 5),
      const CharakSkeleton(width: 130, height: 13),
      const SizedBox(height: 16),
      const CharakSkeletonList(count: 3, padding: EdgeInsets.zero),
    ],
  );
}
