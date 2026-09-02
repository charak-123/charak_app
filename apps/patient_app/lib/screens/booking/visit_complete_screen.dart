import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

class VisitCompleteScreen extends ConsumerWidget {
  final String bookingId;
  const VisitCompleteScreen({super.key, required this.bookingId});

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
            child: const Icon(Icons.done_all, color: CharakColors.success, size: 48),
          ),
          const SizedBox(height: 24),
          Text('Visit Complete', style: CharakText.display),
          const SizedBox(height: 8),
          Text(
            'Your consultation has been completed.\nThank you for using Charak!',
            style: CharakText.body.copyWith(color: CharakColors.inkMuted),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          CharakButton(
            label: 'Rate Your Experience',
            onPressed: () => context.go('/booking/$bookingId/rate'),
          ),
          const SizedBox(height: 12),
          CharakButton(
            label: 'View Bill',
            outlined: true,
            onPressed: () => context.go('/booking/$bookingId/bill'),
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
