import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

class BookingConfirmedScreen extends ConsumerWidget {
  final String bookingId;
  const BookingConfirmedScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: CharakColors.bg,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(CharakSpacing.lg),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Spacer(),
          Container(
            width: 88, height: 88,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF7F1), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_outline,
                color: CharakColors.success, size: 48),
          ),
          const SizedBox(height: 24),
          Text('Booking Confirmed!', style: CharakText.display),
          const SizedBox(height: 8),
          Text(
            'Your payment was successful.\nThe doctor will be with you at the scheduled time.',
            style: CharakText.body.copyWith(color: CharakColors.inkMuted),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          CharakButton(
            label: 'View Booking',
            onPressed: () => context.go('/booking/$bookingId/active'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/home'),
            child: const Text('Go to Home'),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    ),
  );
}
