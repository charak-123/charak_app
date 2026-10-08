import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';
import '../../calendar_link.dart';
import '../home/booking_providers.dart';

class BookingConfirmedScreen extends ConsumerWidget {
  final String bookingId;
  const BookingConfirmedScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(patientBookingsProvider).maybeWhen(
          data: (all) => all.where((b) => b['id'] == bookingId).firstOrNull,
          orElse: () => null,
        );
    final start = DateTime.tryParse(booking?['scheduled_start'] as String? ?? '')?.toLocal();
    final price = booking?['price_confirmed'] as num?;
    return Scaffold(
    backgroundColor: CharakColors.ground,
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
                  if (booking != null)
                    CharakSummaryRow(
                        label: 'Doctor',
                        value: CharakFormat.doctor((booking['doctors'] as Map?)?['name'] as String?)),
                  if (start != null)
                    CharakSummaryRow(label: 'When', value: DateFormat('EEE d MMM, h:mm a').format(start)),
                  if (price != null) CharakSummaryRow(label: 'Paid', value: CharakFormat.rupees(price)),
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
                    icon: LucideIcons.calendarCheck,
                    onPressed: booking == null
                        ? null
                        : () async {
                            final ok = await addBookingToCalendar(booking);
                            if (!ok && context.mounted) {
                              showCharakToast(context, message: "Couldn't open your calendar", isError: true);
                            }
                          },
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
}
