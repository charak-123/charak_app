import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';
import '../shared/charak_button.dart';

final _activeBookingProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ApiClient.instance.get('/bookings/$id');
  return res as Map<String, dynamic>;
});

class ActiveBookingScreen extends ConsumerWidget {
  final String bookingId;
  const ActiveBookingScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_activeBookingProvider(bookingId));
    return Scaffold(
      backgroundColor: CharakColors.bgSubtle,
      appBar: AppBar(
        title: const Text('Booking Details'),
        backgroundColor: CharakColors.bg,
        foregroundColor: CharakColors.ink,
        elevation: 0,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (booking) => _Body(booking: booking, bookingId: bookingId, ref: ref),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Map<String, dynamic> booking;
  final String bookingId;
  final WidgetRef ref;
  const _Body({required this.booking, required this.bookingId, required this.ref});

  @override
  Widget build(BuildContext context) {
    final status = booking['status'] as String? ?? '';
    final channel = booking['channel'] as String? ?? '';
    final doc = booking['doctors'] as Map<String, dynamic>? ?? {};
    final docName = doc['name'] as String? ?? 'Doctor';
    final docCategory = (doc['categories'] as Map?)?['name'] as String? ?? '';
    final start = booking['scheduled_start'] as String?;
    final price = booking['price_confirmed'];

    String formattedTime = '';
    if (start != null) {
      final dt = DateTime.tryParse(start);
      if (dt != null) formattedTime = DateFormat('EEEE, d MMM yyyy · h:mm a').format(dt.toLocal());
    }

    return Column(children: [
      Expanded(child: ListView(
        padding: const EdgeInsets.all(CharakSpacing.base),
        children: [
          // Doctor card
          _InfoCard(children: [
            Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: CharakColors.primarySoft,
                child: Text(
                  docName.isNotEmpty ? docName[0].toUpperCase() : 'D',
                  style: CharakText.h1.copyWith(color: CharakColors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Dr. $docName', style: CharakText.h2),
                Text(docCategory, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              ])),
              _StatusBadge(status: status),
            ]),
          ]),
          const SizedBox(height: 12),

          // Appointment details
          _InfoCard(children: [
            _DetailRow(icon: Icons.access_time, label: 'Time', value: formattedTime),
            const Divider(height: 20, color: CharakColors.border),
            _DetailRow(
              icon: channel == 'home_visit' ? Icons.home_outlined : Icons.videocam_outlined,
              label: 'Type',
              value: channel == 'home_visit' ? 'Home Visit' : 'Online Consult',
            ),
            if (price != null) ...[
              const Divider(height: 20, color: CharakColors.border),
              _DetailRow(
                icon: Icons.currency_rupee,
                label: 'Fee',
                value: '₹${(price as num).toStringAsFixed(0)}',
              ),
            ],
          ]),
          const SizedBox(height: 12),

          // Actions for paid/online consult
          if (status == 'paid' && channel == 'online_consult')
            _InfoCard(children: [
              Row(children: [
                const Icon(Icons.info_outline, size: 16, color: CharakColors.inkMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Join the call when the doctor is ready.',
                    style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
                  ),
                ),
              ]),
            ]),

          if (status == 'completed') ...[
            const SizedBox(height: 12),
            _InfoCard(children: [
              Row(children: [
                const Icon(Icons.check_circle_outline, color: CharakColors.success, size: 20),
                const SizedBox(width: 8),
                Text('Visit completed', style: CharakText.body.copyWith(color: CharakColors.success)),
              ]),
            ]),
          ],
        ],
      )),

      // Action bar
      Padding(
        padding: const EdgeInsets.fromLTRB(CharakSpacing.base, 0, CharakSpacing.base, 24),
        child: Column(children: [
          if (status == 'paid' && channel == 'online_consult')
            CharakButton(
              label: 'Join Call',
              onPressed: () => context.push('/booking/$bookingId/call'),
            ),
          if (status == 'completed') ...[
            CharakButton(
              label: 'Rate Your Experience',
              onPressed: () => context.push('/booking/$bookingId/rate'),
            ),
            const SizedBox(height: 10),
            CharakButton(
              label: 'View Bill',
              outlined: true,
              onPressed: () => context.push('/booking/$bookingId/bill'),
            ),
          ],
          const SizedBox(height: 10),
          TextButton(onPressed: () => context.go('/home'), child: const Text('Go Home')),
        ]),
      ),
    ]);
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: CharakColors.bg,
      borderRadius: const BorderRadius.all(CharakRadius.card),
      border: Border.all(color: CharakColors.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 18, color: CharakColors.inkMuted),
    const SizedBox(width: 8),
    Text('$label:', style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
    const SizedBox(width: 8),
    Expanded(child: Text(value, style: CharakText.bodyMed, textAlign: TextAlign.end)),
  ]);
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'paid':
        color = CharakColors.primary; label = 'Confirmed';
      case 'completed':
        color = CharakColors.success; label = 'Completed';
      default:
        color = CharakColors.warning; label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: const BorderRadius.all(CharakRadius.pill),
      ),
      child: Text(label, style: CharakText.micro.copyWith(color: color)),
    );
  }
}
