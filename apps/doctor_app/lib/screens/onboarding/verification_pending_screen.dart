import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

class VerificationPendingScreen extends ConsumerStatefulWidget {
  const VerificationPendingScreen({super.key});

  @override
  ConsumerState<VerificationPendingScreen> createState() =>
      _VerificationPendingScreenState();
}

class _VerificationPendingScreenState
    extends ConsumerState<VerificationPendingScreen> {
  CharakPoller? _poll;
  String _status = 'pending';
  String? _rejectionReason;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Verification is a human decision minutes-to-days away, so this starts
    // slow and eases off to five minutes. Push (`doctor.verified`) is what
    // makes it feel immediate; this only catches a missed notification.
    _poll = CharakPoller(
      onPoll: _refresh,
      interval: const Duration(seconds: 20),
      maxInterval: const Duration(minutes: 5),
    )..start();
  }

  /// Reads the doctor's own profile through the backend.
  ///
  /// A Supabase realtime subscription cannot work here: the app holds only the
  /// anon key and authenticates with a FastAPI JWT, so `auth.uid()` is NULL
  /// and the doctors RLS policy matches no rows. The stream never fired, so a
  /// doctor approved by ops sat on this screen until they restarted the app.
  /// Returns true once ops have approved, which stops the poll. A rejection
  /// keeps polling: ops can reverse it after the doctor re-submits.
  Future<bool> _refresh() async {
    final Map<String, dynamic> me;
    try {
      me = await ApiClient.instance.get('/doctors/me') as Map<String, dynamic>;
    } on ApiException {
      return false; // Offline or server hiccup: keep the last state, poll again.
    }
    if (!mounted) return true;
    final status = me['verification_status'] as String? ?? 'pending';
    setState(() {
      _status = status;
      _rejectionReason = me['verification_rejection_reason'] as String?;
    });
    if (status == 'verified') {
      context.go('/onboarding/verified');
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _poll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRejected = _status == 'rejected';
    final reason = _rejectionReason;

    // Same shape as every other outcome screen: the state up top, actions in
    // the CTA bar within thumb reach.
    return Scaffold(
      backgroundColor: CharakColors.ground,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 44, 20, 24),
              child: isRejected
                  ? CharakOutcomeState(
                      tone: CharakOutcomeTone.neutral,
                      icon: LucideIcons.circleX,
                      title: 'Verification declined',
                      message:
                          'We could not verify your credentials. Please check and resubmit.',
                      child: reason == null
                          ? null
                          : CharakNoteBanner(
                              tone: CharakStatusTone.danger,
                              icon: LucideIcons.circleAlert,
                              leadLabel: 'Reason',
                              message: reason,
                            ),
                    )
                  : const CharakOutcomeState(
                      tone: CharakOutcomeTone.waiting,
                      icon: LucideIcons.clipboardCheck,
                      title: 'Under review',
                      message:
                          "Our team is verifying your license. You can set up your "
                          "practice now — you'll appear in the directory the moment "
                          "you're approved.",
                      child: CharakStatusPill(
                        label: 'Under review',
                        tone: CharakStatusTone.warning,
                        pulsingDot: true,
                      ),
                    ),
            ),
          ),
          CharakCtaBar(children: [
            Expanded(
              child: isRejected
                  ? CharakButton(
                      label: 'Resubmit credentials',
                      onPressed: () => context.go('/onboarding/verification'),
                    )
                  : CharakButton(
                      label: 'Explore the app',
                      outlined: true,
                      onPressed: () => context.go('/home'),
                    ),
            ),
          ]),
        ]),
      ),
    );
  }
}
