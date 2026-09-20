import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../home/booking_providers.dart';

class BookingConfirmedScreen extends ConsumerWidget {
  final String bookingId;
  const BookingConfirmedScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: CharakColors.bg,
    body: SafeArea(
      child: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 34, 20, 24),
            // `.ok-state` — animated success check, 24px title, 260px-wide sub.
            child: CharakOutcomeState(
              title: 'Booking confirmed',
              message: 'Your payment went through. The doctor will be with '
                  'you at the scheduled time.',
              child: Column(children: [
                CharakSummaryCard(rows: [
                  const CharakSummaryRow(
                      label: 'Payment', value: 'Paid via UPI', muted: true),
                  CharakSummaryRow(
                    label: 'Status',
                    child: CharakStatusPill.forStatus('paid'),
                  ),
                ]),
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: CharakButton(
                    label: 'Add to calendar',
                    outlined: true,
                    icon: Icons.event_available_outlined,
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Added to calendar')),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),

        CharakCtaBar(children: [
          Expanded(
            child: CharakButton(
              label: 'My bookings',
              outlined: true,
              onPressed: () {
                ref.read(homeTabIndexProvider.notifier).state = 1;
                context.go('/home');
              },
            ),
          ),
          Expanded(
            child: CharakButton(
              label: 'View booking',
              onPressed: () => context.go('/booking/$bookingId/active'),
            ),
          ),
        ]),
      ]),
    ),
  );
}
