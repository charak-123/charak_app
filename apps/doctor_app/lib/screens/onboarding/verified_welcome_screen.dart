import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

/// Shown exactly once, the moment ops approves a doctor and before they're
/// asked to set up channels and pricing — whether they're staring at the
/// live /onboarding/verification-pending screen when it happens, or open the
/// app fresh afterwards (from the push notification or on their own). Both
/// paths converge on this same screen: see splash_screen.dart's routing and
/// verification_pending_screen.dart's poller.
class VerifiedWelcomeScreen extends StatelessWidget {
  const VerifiedWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: CharakColors.ground,
        body: SafeArea(
          child: Column(children: [
            const Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 44, 20, 24),
                child: CharakOutcomeState(
                  tone: CharakOutcomeTone.success,
                  title: "You're verified!",
                  message:
                      'Your credentials are confirmed. One more step — tell '
                      'us how you consult and what you charge, and you\'ll be '
                      'live in the directory.',
                ),
              ),
            ),
            CharakCtaBar(children: [
              Expanded(
                child: CharakButton(
                  label: 'Set up my practice',
                  onPressed: () => context.go('/setup/channels'),
                ),
              ),
            ]),
          ]),
        ),
      );
}
