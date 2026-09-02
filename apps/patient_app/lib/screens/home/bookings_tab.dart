import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

final _bookingsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.instance.get('/bookings/patient/list');
  return (res as List).cast<Map<String, dynamic>>();
});

class BookingsTab extends ConsumerWidget {
  const BookingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_bookingsProvider);
    return Scaffold(
      backgroundColor: CharakColors.bgSubtle,
      appBar: AppBar(
        title: const Text('My Bookings'),
        backgroundColor: CharakColors.bg,
        foregroundColor: CharakColors.ink,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (bookings) {
          if (bookings.isEmpty) {
            return _EmptyState();
          }
          final upcoming = bookings.where((b) => _isUpcoming(b['status'])).toList();
          final past = bookings.where((b) => !_isUpcoming(b['status'])).toList();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(_bookingsProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(CharakSpacing.base),
              children: [
                if (upcoming.isNotEmpty) ...[
                  _SectionHeader(label: 'Upcoming'),
                  ...upcoming.map((b) => _BookingCard(booking: b)),
                  const SizedBox(height: 16),
                ],
                if (past.isNotEmpty) ...[
                  _SectionHeader(label: 'Past'),
                  ...past.map((b) => _BookingCard(booking: b)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  bool _isUpcoming(String? status) =>
      status == 'requested' || status == 'accepted' || status == 'paid';
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: CharakText.h2.copyWith(color: CharakColors.inkMuted)),
  );
}

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

    String formattedTime = '';
    if (start != null) {
      final dt = DateTime.tryParse(start);
      if (dt != null) formattedTime = DateFormat('d MMM, h:mm a').format(dt.toLocal());
    }

    return GestureDetector(
      onTap: () => _navigate(context, status, booking['id'] as String),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: CharakColors.bg,
          borderRadius: const BorderRadius.all(CharakRadius.card),
          border: Border.all(color: CharakColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: CharakColors.primarySoft,
              child: Text(
                docName.isNotEmpty ? docName[0].toUpperCase() : 'D',
                style: CharakText.h2.copyWith(color: CharakColors.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dr. $docName', style: CharakText.bodyMed),
              Text(docCategory, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              if (formattedTime.isNotEmpty)
                Text(formattedTime, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _StatusBadge(status: status),
              const SizedBox(height: 4),
              _ChannelChip(channel: channel),
            ]),
          ]),
        ),
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

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'accepted':
        color = CharakColors.success; label = 'Accepted';
      case 'paid':
        color = CharakColors.primary; label = 'Confirmed';
      case 'completed':
        color = CharakColors.inkMuted; label = 'Completed';
      case 'declined':
        color = CharakColors.danger; label = 'Declined';
      case 'cancelled':
        color = CharakColors.inkMuted; label = 'Cancelled';
      default:
        color = CharakColors.warning; label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: const BorderRadius.all(CharakRadius.pill),
      ),
      child: Text(label, style: CharakText.micro.copyWith(color: color)),
    );
  }
}

class _ChannelChip extends StatelessWidget {
  final String channel;
  const _ChannelChip({required this.channel});
  @override
  Widget build(BuildContext context) => Text(
    channel == 'home_visit' ? 'Home Visit' : 'Online',
    style: CharakText.micro.copyWith(color: CharakColors.inkMuted),
  );
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.calendar_today_outlined, size: 64, color: CharakColors.border),
      const SizedBox(height: 16),
      Text('No bookings yet', style: CharakText.h2.copyWith(color: CharakColors.inkMuted)),
      const SizedBox(height: 8),
      Text('Find a doctor and book a consultation',
          style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
      const SizedBox(height: 24),
      TextButton(
        onPressed: () => context.go('/directory'),
        child: const Text('Find a Doctor'),
      ),
    ]),
  );
}
