import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';
import '../shared/charak_button.dart';

final _bookingProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await ApiClient.instance.get('/bookings/$id');
  return res as Map<String, dynamic>;
});

class BookingStatusScreen extends ConsumerWidget {
  final String bookingId;
  const BookingStatusScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_bookingProvider(bookingId));
    return Scaffold(
      backgroundColor: CharakColors.bgSubtle,
      appBar: AppBar(
        title: const Text('Booking Status'),
        backgroundColor: CharakColors.bg,
        foregroundColor: CharakColors.ink,
        elevation: 0,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (booking) {
          final status = booking['status'] as String? ?? 'requested';
          return _StatusBody(booking: booking, status: status, bookingId: bookingId);
        },
      ),
    );
  }
}

class _StatusBody extends StatelessWidget {
  final Map<String, dynamic> booking;
  final String status;
  final String bookingId;
  const _StatusBody({required this.booking, required this.status, required this.bookingId});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    String statusLabel;
    String statusDesc;

    switch (status) {
      case 'accepted':
        statusColor = CharakColors.success; statusIcon = Icons.check_circle_outline;
        statusLabel = 'Accepted!'; statusDesc = 'Doctor has accepted your request. Please complete payment.';
        break;
      case 'declined':
        statusColor = CharakColors.danger; statusIcon = Icons.cancel_outlined;
        statusLabel = 'Declined'; statusDesc = 'The doctor is unavailable for this slot. Try another doctor or time.';
        break;
      case 'paid':
        statusColor = CharakColors.success; statusIcon = Icons.payments_outlined;
        statusLabel = 'Confirmed'; statusDesc = 'Payment received. Your appointment is confirmed!';
        break;
      case 'completed':
        statusColor = CharakColors.primary; statusIcon = Icons.done_all;
        statusLabel = 'Completed'; statusDesc = 'Your visit has been completed.';
        break;
      case 'cancelled':
        statusColor = CharakColors.inkMuted; statusIcon = Icons.remove_circle_outline;
        statusLabel = 'Cancelled'; statusDesc = 'This booking was cancelled.';
        break;
      default: // requested
        statusColor = CharakColors.warning; statusIcon = Icons.hourglass_top;
        statusLabel = 'Awaiting Response'; statusDesc = 'Waiting for the doctor to accept your request.';
    }

    return Column(children: [
      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(statusIcon, color: statusColor, size: 64),
        const SizedBox(height: 16),
        Text(statusLabel, style: CharakText.display.copyWith(color: statusColor)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(statusDesc,
              style: CharakText.body.copyWith(color: CharakColors.inkMuted),
              textAlign: TextAlign.center),
        ),
      ])),

      Padding(
        padding: const EdgeInsets.fromLTRB(CharakSpacing.base, 0, CharakSpacing.base, 24),
        child: Column(children: [
          if (status == 'accepted')
            CharakButton(
              label: 'Pay Now',
              onPressed: () => context.go('/booking/$bookingId/pay'),
            ),
          if (status == 'declined') ...[
            CharakButton(label: 'Find Another Doctor', onPressed: () => context.go('/directory')),
            const SizedBox(height: 10),
          ],
          if (status == 'paid' || status == 'completed')
            CharakButton(
              label: 'View Details',
              onPressed: () => context.go('/booking/$bookingId/active'),
            ),
          if (status == 'completed') ...[
            const SizedBox(height: 10),
            CharakButton(
              label: 'Rate Your Experience',
              outlined: true,
              onPressed: () => context.push('/booking/$bookingId/rate'),
            ),
          ],
          const SizedBox(height: 10),
          TextButton(onPressed: () => context.go('/home'), child: const Text('Go Home')),
        ]),
      ),
    ]);
  }
}
