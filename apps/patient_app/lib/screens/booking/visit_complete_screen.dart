import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../home/booking_providers.dart';

class VisitCompleteScreen extends ConsumerWidget {
  final String bookingId;
  const VisitCompleteScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: CharakColors.bg,
    body: SafeArea(
      child: Column(children: [
        const Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 44, 20, 24),
            // `.ok-state .wait-ic` — the neutral grey badge, not the check.
            child: CharakOutcomeState(
              tone: CharakOutcomeTone.neutral,
              icon: Icons.flag_outlined,
              title: 'Visit complete',
              message: 'Hope it went well. A quick rating helps other '
                  'patients choose well.',
            ),
          ),
        ),

        CharakCtaBar(children: [
          Expanded(
            child: CharakButton(
              label: 'Skip',
              outlined: true,
              onPressed: () {
                ref.read(homeTabIndexProvider.notifier).state = 2;
                context.go('/home');
              },
            ),
          ),
          Expanded(
            child: CharakButton(
              label: 'Rate your visit',
              onPressed: () => context.go('/booking/$bookingId/rate'),
            ),
          ),
        ]),
      ]),
    ),
  );
}
